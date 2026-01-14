package fuse

import (
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/winfsp/cgofuse/fuse"

	"github.com/BV-BRC/Workspace/go/internal/cache"
	"github.com/BV-BRC/Workspace/go/internal/workspace"
)

// Access mode constants (from unistd.h)
const (
	R_OK = 4 // Test for read permission
	W_OK = 2 // Test for write permission
	X_OK = 1 // Test for execute permission
	F_OK = 0 // Test for existence
)

// Options configures the WorkspaceFS
type Options struct {
	RootPath string
	ReadOnly bool
	TempDir  string
	Debug    bool
}

// fileHandle represents an open file
type fileHandle struct {
	path     string
	tempFile string
	dirty    bool
	readOnly bool
}

// WorkspaceFS implements a FUSE filesystem backed by BV-BRC Workspace
type WorkspaceFS struct {
	fuse.FileSystemBase

	client   *workspace.Client
	cache    *cache.Cache
	rootPath string
	readOnly bool
	tempDir  string
	debug    bool

	// File handle management
	mu       sync.Mutex
	handles  map[uint64]*fileHandle
	nextFh   uint64

	// UID/GID for files
	uid uint32
	gid uint32
}

// NewWorkspaceFS creates a new workspace filesystem
func NewWorkspaceFS(client *workspace.Client, c *cache.Cache, opts Options) *WorkspaceFS {
	tempDir := opts.TempDir
	if tempDir == "" {
		tempDir = os.TempDir()
	}

	return &WorkspaceFS{
		client:   client,
		cache:    c,
		rootPath: strings.TrimSuffix(opts.RootPath, "/"),
		readOnly: opts.ReadOnly,
		tempDir:  tempDir,
		debug:    opts.Debug,
		handles:  make(map[uint64]*fileHandle),
		nextFh:   1,
		uid:      uint32(os.Getuid()),
		gid:      uint32(os.Getgid()),
	}
}

// ClearCache clears all cached data (for SIGHUP handling)
func (fs *WorkspaceFS) ClearCache() {
	fs.cache.Clear()
}

// wsPath converts a local FUSE path to a workspace path
func (fs *WorkspaceFS) wsPath(localPath string) string {
	if localPath == "/" {
		return fs.rootPath
	}
	return fs.rootPath + localPath
}

// parentPath returns the parent directory of a path
func parentPath(path string) string {
	dir := filepath.Dir(path)
	if dir == "." {
		return "/"
	}
	return dir
}

// getMetadata fetches metadata for a path, using cache
func (fs *WorkspaceFS) getMetadata(wsPath string) (*workspace.ObjectMeta, error) {
	// Check cache first
	if meta, ok := fs.cache.GetMetadata(wsPath); ok {
		return meta, nil
	}

	// Fetch from API
	meta, err := fs.client.GetMetadata(wsPath)
	if err != nil {
		return nil, err
	}

	// Cache it
	fs.cache.SetMetadata(wsPath, meta)
	return meta, nil
}

// metaToStat converts ObjectMeta to fuse.Stat_t
func (fs *WorkspaceFS) metaToStat(meta *workspace.ObjectMeta, stat *fuse.Stat_t) {
	stat.Uid = fs.uid
	stat.Gid = fs.gid

	// Set times
	timestamp := meta.CreationTime.Unix()
	if timestamp <= 0 {
		timestamp = time.Now().Unix()
	}
	stat.Atim = fuse.Timespec{Sec: timestamp}
	stat.Mtim = fuse.Timespec{Sec: timestamp}
	stat.Ctim = fuse.Timespec{Sec: timestamp}

	if meta.IsDirectory() {
		stat.Mode = fuse.S_IFDIR | 0755
		stat.Nlink = 2
		stat.Size = 4096
	} else {
		stat.Mode = fuse.S_IFREG | 0644
		stat.Nlink = 1
		stat.Size = meta.Size
	}

	// Adjust permissions based on access
	if fs.readOnly || !meta.HasWritePermission() {
		if meta.IsDirectory() {
			stat.Mode = fuse.S_IFDIR | 0555
		} else {
			stat.Mode = fuse.S_IFREG | 0444
		}
	}
}

// Getattr returns file attributes
func (fs *WorkspaceFS) Getattr(path string, stat *fuse.Stat_t, fh uint64) int {
	if fs.debug {
		println("Getattr:", path)
	}

	wsPath := fs.wsPath(path)

	meta, err := fs.getMetadata(wsPath)
	if err != nil {
		if fs.debug {
			println("Getattr error:", err.Error())
		}
		return -fuse.ENOENT
	}

	fs.metaToStat(meta, stat)
	return 0
}

// Readdir reads directory contents
func (fs *WorkspaceFS) Readdir(path string, fill func(name string, stat *fuse.Stat_t, ofst int64) bool, ofst int64, fh uint64) int {
	if fs.debug {
		println("Readdir:", path)
	}

	wsPath := fs.wsPath(path)

	// Add . and ..
	fill(".", nil, 0)
	fill("..", nil, 0)

	// Check cache for directory listing
	if entries, ok := fs.cache.GetDir(wsPath); ok {
		for _, name := range entries {
			fill(name, nil, 0)
		}
		return 0
	}

	// Fetch from API
	results, err := fs.client.Ls([]string{wsPath})
	if err != nil {
		if fs.debug {
			println("Readdir error:", err.Error())
		}
		return -fuse.EIO
	}

	items, ok := results[wsPath]
	if !ok {
		return -fuse.ENOENT
	}

	// Collect entry names for caching
	entryNames := make([]string, 0, len(items))

	for _, item := range items {
		name := item.Name
		if name == "" {
			continue
		}

		entryNames = append(entryNames, name)

		// Create stat for this entry
		var stat fuse.Stat_t
		fs.metaToStat(item, &stat)

		// Cache the metadata
		fs.cache.SetMetadata(item.Path, item)

		if !fill(name, &stat, 0) {
			break
		}
	}

	// Cache the directory listing
	fs.cache.SetDir(wsPath, entryNames)

	return 0
}

// Open opens a file
func (fs *WorkspaceFS) Open(path string, flags int) (int, uint64) {
	if fs.debug {
		println("Open:", path, "flags:", flags)
	}

	wsPath := fs.wsPath(path)

	// Check if file exists
	meta, err := fs.getMetadata(wsPath)
	if err != nil {
		return -fuse.ENOENT, 0
	}

	if meta.IsDirectory() {
		return -fuse.EISDIR, 0
	}

	// Check write access
	writeRequested := flags&(fuse.O_WRONLY|fuse.O_RDWR) != 0
	if writeRequested {
		if fs.readOnly {
			return -fuse.EROFS, 0
		}
		if !meta.HasWritePermission() {
			return -fuse.EACCES, 0
		}
	}

	// Allocate file handle
	fs.mu.Lock()
	fh := fs.nextFh
	fs.nextFh++
	fs.handles[fh] = &fileHandle{
		path:     wsPath,
		readOnly: !writeRequested,
	}
	fs.mu.Unlock()

	return 0, fh
}

// Read reads file content
func (fs *WorkspaceFS) Read(path string, buff []byte, ofst int64, fh uint64) int {
	if fs.debug {
		println("Read:", path, "offset:", ofst, "len:", len(buff))
	}

	wsPath := fs.wsPath(path)

	// Check if we have a temp file for this handle
	fs.mu.Lock()
	handle, ok := fs.handles[fh]
	fs.mu.Unlock()

	if ok && handle.tempFile != "" {
		// Read from temp file
		file, err := os.Open(handle.tempFile)
		if err != nil {
			return -fuse.EIO
		}
		defer file.Close()

		n, err := file.ReadAt(buff, ofst)
		if err != nil && n == 0 {
			return -fuse.EIO
		}
		return n
	}

	// Try cache first
	if content, ok := fs.cache.GetContent(wsPath); ok {
		if ofst >= int64(len(content)) {
			return 0
		}
		n := copy(buff, content[ofst:])
		return n
	}

	// Get metadata to check for Shock URL
	meta, err := fs.getMetadata(wsPath)
	if err != nil {
		return -fuse.ENOENT
	}

	// If file is in Shock and we're doing a partial read, use range request
	if meta.ShockURL != "" {
		data, err := fs.client.ShockReadBytes(meta.ShockURL, ofst, int64(len(buff)))
		if err != nil {
			if fs.debug {
				println("Shock read error:", err.Error())
			}
			return -fuse.EIO
		}
		n := copy(buff, data)
		return n
	}

	// Fetch full content
	entries, err := fs.client.Get([]string{wsPath}, false)
	if err != nil || len(entries) == 0 {
		return -fuse.EIO
	}

	content := entries[0].Data

	// Cache content for small files
	if len(content) < 1024*1024 { // 1MB threshold
		fs.cache.SetContent(wsPath, content)
	}

	if ofst >= int64(len(content)) {
		return 0
	}

	n := copy(buff, content[ofst:])
	return n
}

// Create creates a new file
func (fs *WorkspaceFS) Create(path string, flags int, mode uint32) (int, uint64) {
	if fs.debug {
		println("Create:", path)
	}

	if fs.readOnly {
		return -fuse.EROFS, 0
	}

	wsPath := fs.wsPath(path)

	// Create empty temp file
	tempFile, err := os.CreateTemp(fs.tempDir, "ws-fuse-*")
	if err != nil {
		return -fuse.EIO, 0
	}
	tempPath := tempFile.Name()
	tempFile.Close()

	// Allocate file handle
	fs.mu.Lock()
	fh := fs.nextFh
	fs.nextFh++
	fs.handles[fh] = &fileHandle{
		path:     wsPath,
		tempFile: tempPath,
		dirty:    true,
		readOnly: false,
	}
	fs.mu.Unlock()

	return 0, fh
}

// Mknod creates a file node
func (fs *WorkspaceFS) Mknod(path string, mode uint32, dev uint64) int {
	if fs.debug {
		println("Mknod:", path)
	}

	if fs.readOnly {
		return -fuse.EROFS
	}

	// Only support regular files
	if mode&fuse.S_IFREG == 0 {
		return -fuse.ENOSYS
	}

	wsPath := fs.wsPath(path)

	// Create empty file
	_, err := fs.client.UploadBytes([]byte{}, wsPath, "unspecified", false)
	if err != nil {
		if fs.debug {
			println("Mknod error:", err.Error())
		}
		return -fuse.EIO
	}

	// Invalidate parent directory cache
	fs.cache.InvalidateDir(fs.wsPath(parentPath(path)))

	return 0
}

// Mkdir creates a directory
func (fs *WorkspaceFS) Mkdir(path string, mode uint32) int {
	if fs.debug {
		println("Mkdir:", path)
	}

	if fs.readOnly {
		return -fuse.EROFS
	}

	wsPath := fs.wsPath(path)

	_, err := fs.client.CreateDirectory(wsPath)
	if err != nil {
		if fs.debug {
			println("Mkdir error:", err.Error())
		}
		return -fuse.EIO
	}

	// Invalidate parent directory cache
	fs.cache.InvalidateDir(fs.wsPath(parentPath(path)))

	return 0
}

// Unlink removes a file
func (fs *WorkspaceFS) Unlink(path string) int {
	if fs.debug {
		println("Unlink:", path)
	}

	if fs.readOnly {
		return -fuse.EROFS
	}

	wsPath := fs.wsPath(path)

	_, err := fs.client.Delete([]string{wsPath}, false, false)
	if err != nil {
		if fs.debug {
			println("Unlink error:", err.Error())
		}
		return -fuse.EIO
	}

	// Invalidate caches
	fs.cache.Invalidate(wsPath)
	fs.cache.InvalidateDir(fs.wsPath(parentPath(path)))

	return 0
}

// Rmdir removes a directory
func (fs *WorkspaceFS) Rmdir(path string) int {
	if fs.debug {
		println("Rmdir:", path)
	}

	if fs.readOnly {
		return -fuse.EROFS
	}

	wsPath := fs.wsPath(path)

	_, err := fs.client.Delete([]string{wsPath}, true, false)
	if err != nil {
		if fs.debug {
			println("Rmdir error:", err.Error())
		}
		// Could be ENOTEMPTY if directory not empty
		return -fuse.EIO
	}

	// Invalidate caches
	fs.cache.Invalidate(wsPath)
	fs.cache.InvalidateDir(fs.wsPath(parentPath(path)))

	return 0
}

// Rename moves/renames a file or directory
func (fs *WorkspaceFS) Rename(oldpath string, newpath string) int {
	if fs.debug {
		println("Rename:", oldpath, "->", newpath)
	}

	if fs.readOnly {
		return -fuse.EROFS
	}

	oldWsPath := fs.wsPath(oldpath)
	newWsPath := fs.wsPath(newpath)

	_, err := fs.client.Move([][2]string{{oldWsPath, newWsPath}}, true)
	if err != nil {
		if fs.debug {
			println("Rename error:", err.Error())
		}
		return -fuse.EIO
	}

	// Invalidate caches
	fs.cache.Invalidate(oldWsPath)
	fs.cache.Invalidate(newWsPath)
	fs.cache.InvalidateDir(fs.wsPath(parentPath(oldpath)))
	fs.cache.InvalidateDir(fs.wsPath(parentPath(newpath)))

	return 0
}

// Write writes data to a file
func (fs *WorkspaceFS) Write(path string, buff []byte, ofst int64, fh uint64) int {
	if fs.debug {
		println("Write:", path, "offset:", ofst, "len:", len(buff))
	}

	if fs.readOnly {
		return -fuse.EROFS
	}

	fs.mu.Lock()
	handle, ok := fs.handles[fh]
	fs.mu.Unlock()

	if !ok {
		return -fuse.EBADF
	}

	if handle.readOnly {
		return -fuse.EBADF
	}

	// Ensure we have a temp file
	if handle.tempFile == "" {
		// Download existing content to temp file
		tempFile, err := os.CreateTemp(fs.tempDir, "ws-fuse-*")
		if err != nil {
			return -fuse.EIO
		}
		tempPath := tempFile.Name()

		// Download existing content
		err = fs.client.DownloadFile(handle.path, tempPath)
		if err != nil {
			// File might be new/empty, that's ok
			tempFile.Close()
		} else {
			tempFile.Close()
		}

		fs.mu.Lock()
		handle.tempFile = tempPath
		fs.mu.Unlock()
	}

	// Write to temp file
	file, err := os.OpenFile(handle.tempFile, os.O_RDWR, 0644)
	if err != nil {
		return -fuse.EIO
	}
	defer file.Close()

	n, err := file.WriteAt(buff, ofst)
	if err != nil {
		return -fuse.EIO
	}

	fs.mu.Lock()
	handle.dirty = true
	fs.mu.Unlock()

	return n
}

// Truncate changes file size
func (fs *WorkspaceFS) Truncate(path string, size int64, fh uint64) int {
	if fs.debug {
		println("Truncate:", path, "size:", size)
	}

	if fs.readOnly {
		return -fuse.EROFS
	}

	fs.mu.Lock()
	handle, ok := fs.handles[fh]
	fs.mu.Unlock()

	if ok && handle.tempFile != "" {
		// Truncate temp file
		if err := os.Truncate(handle.tempFile, size); err != nil {
			return -fuse.EIO
		}

		fs.mu.Lock()
		handle.dirty = true
		fs.mu.Unlock()

		return 0
	}

	// For truncate on a file not opened for writing,
	// we need to download, truncate, and upload
	wsPath := fs.wsPath(path)

	// Download to temp
	tempFile, err := os.CreateTemp(fs.tempDir, "ws-fuse-*")
	if err != nil {
		return -fuse.EIO
	}
	tempPath := tempFile.Name()
	tempFile.Close()

	if size > 0 {
		// Need existing content
		if err := fs.client.DownloadFile(wsPath, tempPath); err != nil {
			os.Remove(tempPath)
			return -fuse.EIO
		}
	}

	// Truncate
	if err := os.Truncate(tempPath, size); err != nil {
		os.Remove(tempPath)
		return -fuse.EIO
	}

	// Upload
	_, err = fs.client.UploadFile(tempPath, wsPath, "unspecified", true)
	os.Remove(tempPath)

	if err != nil {
		return -fuse.EIO
	}

	// Invalidate cache
	fs.cache.Invalidate(wsPath)

	return 0
}

// Flush is called on file close
func (fs *WorkspaceFS) Flush(path string, fh uint64) int {
	if fs.debug {
		println("Flush:", path)
	}

	fs.mu.Lock()
	handle, ok := fs.handles[fh]
	fs.mu.Unlock()

	if !ok {
		return 0
	}

	// If dirty, upload the file
	if handle.dirty && handle.tempFile != "" {
		_, err := fs.client.UploadFile(handle.tempFile, handle.path, "unspecified", true)
		if err != nil {
			if fs.debug {
				println("Flush upload error:", err.Error())
			}
			return -fuse.EIO
		}

		fs.mu.Lock()
		handle.dirty = false
		fs.mu.Unlock()

		// Invalidate caches
		fs.cache.Invalidate(handle.path)
		fs.cache.InvalidateDir(fs.wsPath(parentPath(path)))
	}

	return 0
}

// Release is called when all file descriptors are closed
func (fs *WorkspaceFS) Release(path string, fh uint64) int {
	if fs.debug {
		println("Release:", path)
	}

	fs.mu.Lock()
	handle, ok := fs.handles[fh]
	if ok {
		// Clean up temp file
		if handle.tempFile != "" {
			os.Remove(handle.tempFile)
		}
		delete(fs.handles, fh)
	}
	fs.mu.Unlock()

	return 0
}

// Statfs returns filesystem statistics
func (fs *WorkspaceFS) Statfs(path string, stat *fuse.Statfs_t) int {
	// Return reasonable defaults for a network filesystem
	stat.Bsize = 4096
	stat.Frsize = 4096
	stat.Blocks = 1 << 30 // ~4TB
	stat.Bfree = 1 << 29  // ~2TB free
	stat.Bavail = 1 << 29
	stat.Files = 1 << 20 // ~1M files
	stat.Ffree = 1 << 19
	stat.Favail = 1 << 19
	stat.Namemax = 255
	return 0
}

// Access checks file access permissions
func (fs *WorkspaceFS) Access(path string, mask uint32) int {
	if fs.debug {
		println("Access:", path, "mask:", mask)
	}

	wsPath := fs.wsPath(path)

	meta, err := fs.getMetadata(wsPath)
	if err != nil {
		return -fuse.ENOENT
	}

	// Check write access
	if mask&W_OK != 0 {
		if fs.readOnly {
			return -fuse.EROFS
		}
		if !meta.HasWritePermission() {
			return -fuse.EACCES
		}
	}

	// Check read access
	if mask&R_OK != 0 {
		if !meta.HasReadPermission() {
			return -fuse.EACCES
		}
	}

	return 0
}

// Utimens sets file times (we ignore this but return success)
func (fs *WorkspaceFS) Utimens(path string, tmsp []fuse.Timespec) int {
	return 0
}

// Chmod changes file mode (we ignore this but return success)
func (fs *WorkspaceFS) Chmod(path string, mode uint32) int {
	return 0
}

// Chown changes file ownership (we ignore this but return success)
func (fs *WorkspaceFS) Chown(path string, uid uint32, gid uint32) int {
	return 0
}
