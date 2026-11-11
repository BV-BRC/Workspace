package cache

import (
	"container/list"
	"sync"
	"time"

	"github.com/BV-BRC/Workspace/go/internal/workspace"
)

// Default cache sizes and TTLs (matching Perl implementation)
const (
	DefaultMetadataSize = 10000
	DefaultDirSize      = 5000
	DefaultContentSize  = 1000

	DefaultMetadataTTL = 60 * time.Second
	DefaultDirTTL      = 30 * time.Second
	DefaultContentTTL  = 300 * time.Second
)

// Cache provides TTL-based LRU caching for workspace data
type Cache struct {
	mu sync.RWMutex

	// Metadata cache
	metadata     map[string]*cacheEntry[*workspace.ObjectMeta]
	metadataList *list.List
	MetadataSize int
	MetadataTTL  time.Duration

	// Directory cache
	dirs    map[string]*cacheEntry[[]string]
	dirList *list.List
	DirSize int
	DirTTL  time.Duration

	// Content cache
	content     map[string]*cacheEntry[[]byte]
	contentList *list.List
	ContentSize int
	ContentTTL  time.Duration
}

// cacheEntry holds cached data with expiration
type cacheEntry[T any] struct {
	key     string
	data    T
	expires time.Time
	element *list.Element
}

// New creates a new cache with default settings
func New() *Cache {
	return &Cache{
		metadata:     make(map[string]*cacheEntry[*workspace.ObjectMeta]),
		metadataList: list.New(),
		MetadataSize: DefaultMetadataSize,
		MetadataTTL:  DefaultMetadataTTL,

		dirs:    make(map[string]*cacheEntry[[]string]),
		dirList: list.New(),
		DirSize: DefaultDirSize,
		DirTTL:  DefaultDirTTL,

		content:     make(map[string]*cacheEntry[[]byte]),
		contentList: list.New(),
		ContentSize: DefaultContentSize,
		ContentTTL:  DefaultContentTTL,
	}
}

// GetMetadata retrieves cached metadata for a path
func (c *Cache) GetMetadata(path string) (*workspace.ObjectMeta, bool) {
	c.mu.RLock()
	entry, ok := c.metadata[path]
	c.mu.RUnlock()

	if !ok {
		return nil, false
	}

	// Check TTL
	if time.Now().After(entry.expires) {
		c.mu.Lock()
		c.removeMetadataEntry(path)
		c.mu.Unlock()
		return nil, false
	}

	// Update LRU order
	c.mu.Lock()
	c.metadataList.MoveToFront(entry.element)
	c.mu.Unlock()

	return entry.data, true
}

// SetMetadata caches metadata for a path
func (c *Cache) SetMetadata(path string, meta *workspace.ObjectMeta) {
	c.mu.Lock()
	defer c.mu.Unlock()

	// If exists, update
	if entry, ok := c.metadata[path]; ok {
		entry.data = meta
		entry.expires = time.Now().Add(c.MetadataTTL)
		c.metadataList.MoveToFront(entry.element)
		return
	}

	// Evict if at capacity
	for len(c.metadata) >= c.MetadataSize {
		c.evictMetadataLRU()
	}

	// Add new entry
	entry := &cacheEntry[*workspace.ObjectMeta]{
		key:     path,
		data:    meta,
		expires: time.Now().Add(c.MetadataTTL),
	}
	entry.element = c.metadataList.PushFront(path)
	c.metadata[path] = entry
}

func (c *Cache) removeMetadataEntry(path string) {
	if entry, ok := c.metadata[path]; ok {
		c.metadataList.Remove(entry.element)
		delete(c.metadata, path)
	}
}

func (c *Cache) evictMetadataLRU() {
	if elem := c.metadataList.Back(); elem != nil {
		path := elem.Value.(string)
		c.metadataList.Remove(elem)
		delete(c.metadata, path)
	}
}

// GetDir retrieves cached directory listing
func (c *Cache) GetDir(path string) ([]string, bool) {
	c.mu.RLock()
	entry, ok := c.dirs[path]
	c.mu.RUnlock()

	if !ok {
		return nil, false
	}

	// Check TTL
	if time.Now().After(entry.expires) {
		c.mu.Lock()
		c.removeDirEntry(path)
		c.mu.Unlock()
		return nil, false
	}

	// Update LRU order
	c.mu.Lock()
	c.dirList.MoveToFront(entry.element)
	c.mu.Unlock()

	return entry.data, true
}

// SetDir caches directory listing
func (c *Cache) SetDir(path string, entries []string) {
	c.mu.Lock()
	defer c.mu.Unlock()

	// If exists, update
	if entry, ok := c.dirs[path]; ok {
		entry.data = entries
		entry.expires = time.Now().Add(c.DirTTL)
		c.dirList.MoveToFront(entry.element)
		return
	}

	// Evict if at capacity
	for len(c.dirs) >= c.DirSize {
		c.evictDirLRU()
	}

	// Add new entry
	entry := &cacheEntry[[]string]{
		key:     path,
		data:    entries,
		expires: time.Now().Add(c.DirTTL),
	}
	entry.element = c.dirList.PushFront(path)
	c.dirs[path] = entry
}

func (c *Cache) removeDirEntry(path string) {
	if entry, ok := c.dirs[path]; ok {
		c.dirList.Remove(entry.element)
		delete(c.dirs, path)
	}
}

func (c *Cache) evictDirLRU() {
	if elem := c.dirList.Back(); elem != nil {
		path := elem.Value.(string)
		c.dirList.Remove(elem)
		delete(c.dirs, path)
	}
}

// GetContent retrieves cached file content
func (c *Cache) GetContent(path string) ([]byte, bool) {
	c.mu.RLock()
	entry, ok := c.content[path]
	c.mu.RUnlock()

	if !ok {
		return nil, false
	}

	// Check TTL
	if time.Now().After(entry.expires) {
		c.mu.Lock()
		c.removeContentEntry(path)
		c.mu.Unlock()
		return nil, false
	}

	// Update LRU order
	c.mu.Lock()
	c.contentList.MoveToFront(entry.element)
	c.mu.Unlock()

	return entry.data, true
}

// SetContent caches file content
func (c *Cache) SetContent(path string, content []byte) {
	c.mu.Lock()
	defer c.mu.Unlock()

	// If exists, update
	if entry, ok := c.content[path]; ok {
		entry.data = content
		entry.expires = time.Now().Add(c.ContentTTL)
		c.contentList.MoveToFront(entry.element)
		return
	}

	// Evict if at capacity
	for len(c.content) >= c.ContentSize {
		c.evictContentLRU()
	}

	// Add new entry
	entry := &cacheEntry[[]byte]{
		key:     path,
		data:    content,
		expires: time.Now().Add(c.ContentTTL),
	}
	entry.element = c.contentList.PushFront(path)
	c.content[path] = entry
}

func (c *Cache) removeContentEntry(path string) {
	if entry, ok := c.content[path]; ok {
		c.contentList.Remove(entry.element)
		delete(c.content, path)
	}
}

func (c *Cache) evictContentLRU() {
	if elem := c.contentList.Back(); elem != nil {
		path := elem.Value.(string)
		c.contentList.Remove(elem)
		delete(c.content, path)
	}
}

// Invalidate removes a path from all caches
func (c *Cache) Invalidate(path string) {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.removeMetadataEntry(path)
	c.removeDirEntry(path)
	c.removeContentEntry(path)
}

// InvalidateDir removes only the directory listing for a path
func (c *Cache) InvalidateDir(path string) {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.removeDirEntry(path)
}

// Clear removes all cached data
func (c *Cache) Clear() {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.metadata = make(map[string]*cacheEntry[*workspace.ObjectMeta])
	c.metadataList = list.New()

	c.dirs = make(map[string]*cacheEntry[[]string])
	c.dirList = list.New()

	c.content = make(map[string]*cacheEntry[[]byte])
	c.contentList = list.New()
}

// Stats returns cache statistics for debugging
func (c *Cache) Stats() map[string]int {
	c.mu.RLock()
	defer c.mu.RUnlock()

	return map[string]int{
		"metadata_count": len(c.metadata),
		"dir_count":      len(c.dirs),
		"content_count":  len(c.content),
	}
}
