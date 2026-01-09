package workspace

import (
	"encoding/json"
	"time"
)

// ObjectMeta represents workspace object metadata.
// This maps to the 13-element tuple from the Workspace.spec:
//
//	[0] ObjectName - name selected for object in workspace
//	[1] ObjectType - type of the object (folder, modelfolder, txt, etc.)
//	[2] FullObjectPath - full path to object including name
//	[3] Timestamp - creation time
//	[4] ObjectID - globally unique UUID
//	[5] Username - object owner
//	[6] ObjectSize - size in bytes (or object count for directories)
//	[7] UserMetadata - user-specified metadata
//	[8] AutoMetadata - automatically populated metadata
//	[9] WorkspacePerm - user permission (r, w, o, a, n)
//	[10] WorkspacePerm - global permission
//	[11] string - shock URL (if stored in Shock)
//	[12] string - error message (if any)
type ObjectMeta struct {
	Name             string
	Type             string
	Path             string
	CreationTime     time.Time
	ID               string
	Owner            string
	Size             int64
	UserMetadata     map[string]string
	AutoMetadata     map[string]string
	UserPermission   string
	GlobalPermission string
	ShockURL         string
	Error            string
}

// FolderTypes defines which types are considered directories
var FolderTypes = map[string]bool{
	"folder":      true,
	"modelfolder": true,
}

// FullPath returns the complete path (Path already includes name per spec)
func (m *ObjectMeta) FullPath() string {
	return m.Path
}

// IsDirectory returns true for folder types
func (m *ObjectMeta) IsDirectory() bool {
	return FolderTypes[m.Type]
}

// HasReadPermission checks if user has read access
func (m *ObjectMeta) HasReadPermission() bool {
	switch m.UserPermission {
	case "r", "w", "o", "a":
		return true
	}
	switch m.GlobalPermission {
	case "r", "w":
		return true
	}
	return false
}

// HasWritePermission checks if user has write access
func (m *ObjectMeta) HasWritePermission() bool {
	switch m.UserPermission {
	case "w", "o", "a":
		return true
	}
	return false
}

// UnmarshalJSON implements custom JSON unmarshaling for ObjectMeta
// The API returns a 13-element array, not an object
func (m *ObjectMeta) UnmarshalJSON(data []byte) error {
	var arr []json.RawMessage
	if err := json.Unmarshal(data, &arr); err != nil {
		return err
	}

	if len(arr) < 12 {
		return nil // Empty or invalid
	}

	// Helper to unmarshal string fields
	unmarshalString := func(raw json.RawMessage) string {
		var s string
		json.Unmarshal(raw, &s)
		return s
	}

	// Helper to unmarshal int64
	unmarshalInt64 := func(raw json.RawMessage) int64 {
		var i int64
		json.Unmarshal(raw, &i)
		return i
	}

	// Helper to unmarshal map
	unmarshalMap := func(raw json.RawMessage) map[string]string {
		var mp map[string]string
		json.Unmarshal(raw, &mp)
		if mp == nil {
			mp = make(map[string]string)
		}
		return mp
	}

	m.Name = unmarshalString(arr[0])
	m.Type = unmarshalString(arr[1])
	m.Path = unmarshalString(arr[2])

	// Parse timestamp
	tsStr := unmarshalString(arr[3])
	if tsStr != "" {
		// Try various timestamp formats
		formats := []string{
			time.RFC3339,
			"2006-01-02T15:04:05",
			"2006-01-02T15:04:05Z",
			"2006-01-02 15:04:05",
		}
		for _, format := range formats {
			if t, err := time.Parse(format, tsStr); err == nil {
				m.CreationTime = t
				break
			}
		}
	}

	m.ID = unmarshalString(arr[4])
	m.Owner = unmarshalString(arr[5])
	m.Size = unmarshalInt64(arr[6])
	m.UserMetadata = unmarshalMap(arr[7])
	m.AutoMetadata = unmarshalMap(arr[8])
	m.UserPermission = unmarshalString(arr[9])
	m.GlobalPermission = unmarshalString(arr[10])
	m.ShockURL = unmarshalString(arr[11])

	if len(arr) > 12 {
		m.Error = unmarshalString(arr[12])
	}

	return nil
}

// MarshalJSON implements JSON marshaling for ObjectMeta as an array
func (m *ObjectMeta) MarshalJSON() ([]byte, error) {
	arr := []interface{}{
		m.Name,
		m.Type,
		m.Path,
		m.CreationTime.Format(time.RFC3339),
		m.ID,
		m.Owner,
		m.Size,
		m.UserMetadata,
		m.AutoMetadata,
		m.UserPermission,
		m.GlobalPermission,
		m.ShockURL,
		m.Error,
	}
	return json.Marshal(arr)
}

// CreateRequest represents a request to create an object
type CreateRequest struct {
	Path         string
	Type         string
	Metadata     map[string]string
	Data         string
	CreationTime string
}

// LsResponse represents the response from the ls API call
type LsResponse map[string][]*ObjectMeta

// GetResponse represents a single entry from the get API call
// It's a tuple of [ObjectMeta, ObjectData]
type GetResponseEntry struct {
	Meta *ObjectMeta
	Data []byte
}

// DiskUsageResult represents disk usage information for a path
type DiskUsageResult struct {
	Path           string
	TotalSize      int64
	FileCount      int64
	DirectoryCount int64
	Error          string
}

// UnmarshalJSON implements custom JSON unmarshaling for DiskUsageResult
func (d *DiskUsageResult) UnmarshalJSON(data []byte) error {
	var arr []json.RawMessage
	if err := json.Unmarshal(data, &arr); err != nil {
		return err
	}

	if len(arr) < 5 {
		return nil
	}

	json.Unmarshal(arr[0], &d.Path)
	json.Unmarshal(arr[1], &d.TotalSize)
	json.Unmarshal(arr[2], &d.FileCount)
	json.Unmarshal(arr[3], &d.DirectoryCount)
	json.Unmarshal(arr[4], &d.Error)

	return nil
}
