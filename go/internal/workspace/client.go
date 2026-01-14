package workspace

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/BV-BRC/Workspace/go/internal/auth"
)

// DefaultURL is the default Workspace service URL
const DefaultURL = "https://p3.theseed.org/services/Workspace"

// Client provides access to the Workspace API
type Client struct {
	BaseURL    string
	Token      *auth.Token
	HTTPClient *http.Client
	AdminMode  bool
}

// NewClient creates a new Workspace API client
func NewClient(baseURL string, token *auth.Token) *Client {
	if baseURL == "" {
		baseURL = DefaultURL
	}
	return &Client{
		BaseURL: baseURL,
		Token:   token,
		HTTPClient: &http.Client{
			Timeout: 5 * time.Minute,
		},
	}
}

// jsonRPCRequest represents a JSON-RPC request
type jsonRPCRequest struct {
	Version string        `json:"version"`
	Method  string        `json:"method"`
	Params  []interface{} `json:"params"`
	ID      string        `json:"id"`
}

// jsonRPCResponse represents a JSON-RPC response
type jsonRPCResponse struct {
	Version string          `json:"version"`
	Result  json.RawMessage `json:"result"`
	Error   *jsonRPCError   `json:"error"`
	ID      string          `json:"id"`
}

type jsonRPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    string `json:"data"`
}

// call makes a JSON-RPC call to the Workspace service
func (c *Client) call(method string, params interface{}) (json.RawMessage, error) {
	req := jsonRPCRequest{
		Version: "1.1",
		Method:  "Workspace." + method,
		Params:  []interface{}{params},
		ID:      "1",
	}

	body, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequest("POST", c.BaseURL, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	httpReq.Header.Set("Content-Type", "application/json")
	if c.Token != nil {
		httpReq.Header.Set("Authorization", c.Token.Authorization())
	}

	resp, err := c.HTTPClient.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	var rpcResp jsonRPCResponse
	if err := json.Unmarshal(respBody, &rpcResp); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	if rpcResp.Error != nil {
		return nil, fmt.Errorf("API error: %s", rpcResp.Error.Message)
	}

	return rpcResp.Result, nil
}

// lsParams matches the list_params structure in Workspace.spec
type lsParams struct {
	Paths                 []string            `json:"paths"`
	ExcludeDirectories    bool                `json:"excludeDirectories,omitempty"`
	ExcludeObjects        bool                `json:"excludeObjects,omitempty"`
	Recursive             bool                `json:"recursive,omitempty"`
	FullHierarchicalOutput bool               `json:"fullHierachicalOutput,omitempty"`
	Query                 map[string][]string `json:"query,omitempty"`
	AdminMode             bool                `json:"adminmode,omitempty"`
}

// Ls lists directory contents
func (c *Client) Ls(paths []string) (map[string][]*ObjectMeta, error) {
	params := lsParams{
		Paths:     paths,
		AdminMode: c.AdminMode,
	}

	result, err := c.call("ls", params)
	if err != nil {
		return nil, err
	}

	var response map[string][]*ObjectMeta
	if err := json.Unmarshal(result, &response); err != nil {
		return nil, fmt.Errorf("failed to parse ls response: %w", err)
	}

	return response, nil
}

// getParams matches the get_params structure in Workspace.spec
type getParams struct {
	Objects      []string `json:"objects"`
	MetadataOnly bool     `json:"metadata_only,omitempty"`
	AdminMode    bool     `json:"adminmode,omitempty"`
}

// Get retrieves objects with optional metadata-only mode
// Returns metadata and data for each requested object
func (c *Client) Get(paths []string, metadataOnly bool) ([]*GetResponseEntry, error) {
	params := getParams{
		Objects:      paths,
		MetadataOnly: metadataOnly,
		AdminMode:    c.AdminMode,
	}

	result, err := c.call("get", params)
	if err != nil {
		return nil, err
	}

	// Response is an array of [ObjectMeta, ObjectData] tuples
	var rawResponse [][]json.RawMessage
	if err := json.Unmarshal(result, &rawResponse); err != nil {
		return nil, fmt.Errorf("failed to parse get response: %w", err)
	}

	entries := make([]*GetResponseEntry, 0, len(rawResponse))
	for _, tuple := range rawResponse {
		if len(tuple) < 2 {
			continue
		}

		entry := &GetResponseEntry{}

		// Parse metadata
		var meta ObjectMeta
		if err := json.Unmarshal(tuple[0], &meta); err != nil {
			return nil, fmt.Errorf("failed to parse object metadata: %w", err)
		}
		entry.Meta = &meta

		// Parse data (if not metadata_only)
		if !metadataOnly {
			var dataStr string
			if err := json.Unmarshal(tuple[1], &dataStr); err == nil {
				entry.Data = []byte(dataStr)
			}
		}

		entries = append(entries, entry)
	}

	return entries, nil
}

// GetMetadata is a convenience method to get only metadata
func (c *Client) GetMetadata(path string) (*ObjectMeta, error) {
	entries, err := c.Get([]string{path}, true)
	if err != nil {
		return nil, err
	}
	if len(entries) == 0 {
		return nil, fmt.Errorf("object not found: %s", path)
	}
	return entries[0].Meta, nil
}

// createParams matches the create_params structure in Workspace.spec
type createParams struct {
	Objects           [][]interface{} `json:"objects"`
	Permission        string          `json:"permission,omitempty"`
	CreateUploadNodes bool            `json:"createUploadNodes,omitempty"`
	DownloadLinks     bool            `json:"downloadLinks,omitempty"`
	Overwrite         bool            `json:"overwrite,omitempty"`
	AdminMode         bool            `json:"adminmode,omitempty"`
	SetOwner          string          `json:"setowner,omitempty"`
}

// Create creates files or directories
// Each object is [path, type, metadata, data, creation_time]
func (c *Client) Create(objects []CreateRequest, overwrite bool, createUploadNodes bool) ([]*ObjectMeta, error) {
	// Convert to API format
	apiObjects := make([][]interface{}, 0, len(objects))
	for _, obj := range objects {
		entry := []interface{}{
			obj.Path,
			obj.Type,
			obj.Metadata,
		}
		if !createUploadNodes {
			entry = append(entry, obj.Data)
		}
		if obj.CreationTime != "" {
			entry = append(entry, obj.CreationTime)
		}
		apiObjects = append(apiObjects, entry)
	}

	params := createParams{
		Objects:           apiObjects,
		Overwrite:         overwrite,
		CreateUploadNodes: createUploadNodes,
		AdminMode:         c.AdminMode,
	}

	result, err := c.call("create", params)
	if err != nil {
		return nil, err
	}

	var response []*ObjectMeta
	if err := json.Unmarshal(result, &response); err != nil {
		return nil, fmt.Errorf("failed to parse create response: %w", err)
	}

	return response, nil
}

// CreateDirectory creates a directory at the specified path
func (c *Client) CreateDirectory(path string) (*ObjectMeta, error) {
	objects := []CreateRequest{
		{
			Path: path,
			Type: "folder",
		},
	}
	results, err := c.Create(objects, false, false)
	if err != nil {
		return nil, err
	}
	if len(results) == 0 {
		return nil, fmt.Errorf("failed to create directory")
	}
	return results[0], nil
}

// CreateUploadNode creates an upload node and returns the shock URL
func (c *Client) CreateUploadNode(path string, objType string, metadata map[string]string, overwrite bool) (*ObjectMeta, error) {
	objects := []CreateRequest{
		{
			Path:     path,
			Type:     objType,
			Metadata: metadata,
		},
	}
	results, err := c.Create(objects, overwrite, true)
	if err != nil {
		return nil, err
	}
	if len(results) == 0 {
		return nil, fmt.Errorf("failed to create upload node")
	}
	return results[0], nil
}

// deleteParams matches the delete_params structure in Workspace.spec
type deleteParams struct {
	Objects           []string `json:"objects"`
	DeleteDirectories bool     `json:"deleteDirectories,omitempty"`
	Force             bool     `json:"force,omitempty"`
	AdminMode         bool     `json:"adminmode,omitempty"`
}

// Delete removes files or directories
func (c *Client) Delete(paths []string, deleteDirectories, force bool) ([]*ObjectMeta, error) {
	params := deleteParams{
		Objects:           paths,
		DeleteDirectories: deleteDirectories,
		Force:             force,
		AdminMode:         c.AdminMode,
	}

	result, err := c.call("delete", params)
	if err != nil {
		return nil, err
	}

	var response []*ObjectMeta
	if err := json.Unmarshal(result, &response); err != nil {
		return nil, fmt.Errorf("failed to parse delete response: %w", err)
	}

	return response, nil
}

// copyParams matches the copy_params structure in Workspace.spec
type copyParams struct {
	Objects   [][2]string `json:"objects"`
	Overwrite bool        `json:"overwrite,omitempty"`
	Recursive bool        `json:"recursive,omitempty"`
	Move      bool        `json:"move,omitempty"`
	AdminMode bool        `json:"adminmode,omitempty"`
}

// Copy copies objects from source to destination
func (c *Client) Copy(pairs [][2]string, overwrite bool) ([]*ObjectMeta, error) {
	params := copyParams{
		Objects:   pairs,
		Overwrite: overwrite,
		Recursive: true,
		AdminMode: c.AdminMode,
	}

	result, err := c.call("copy", params)
	if err != nil {
		return nil, err
	}

	var response []*ObjectMeta
	if err := json.Unmarshal(result, &response); err != nil {
		return nil, fmt.Errorf("failed to parse copy response: %w", err)
	}

	return response, nil
}

// Move moves objects from source to destination
func (c *Client) Move(pairs [][2]string, overwrite bool) ([]*ObjectMeta, error) {
	params := copyParams{
		Objects:   pairs,
		Move:      true,
		Overwrite: overwrite,
		Recursive: true,
		AdminMode: c.AdminMode,
	}

	result, err := c.call("copy", params)
	if err != nil {
		return nil, err
	}

	var response []*ObjectMeta
	if err := json.Unmarshal(result, &response); err != nil {
		return nil, fmt.Errorf("failed to parse move response: %w", err)
	}

	return response, nil
}

// duParams matches the du_params structure in Workspace.spec
type duParams struct {
	Paths     []string `json:"paths"`
	Recursive bool     `json:"recursive,omitempty"`
	AdminMode bool     `json:"adminmode,omitempty"`
}

// Du computes disk usage for the given paths
func (c *Client) Du(paths []string, recursive bool) ([]*DiskUsageResult, error) {
	params := duParams{
		Paths:     paths,
		Recursive: recursive,
		AdminMode: c.AdminMode,
	}

	result, err := c.call("du", params)
	if err != nil {
		return nil, err
	}

	var response []*DiskUsageResult
	if err := json.Unmarshal(result, &response); err != nil {
		return nil, fmt.Errorf("failed to parse du response: %w", err)
	}

	return response, nil
}

// existsParams matches the exists_params structure in Workspace.spec
type existsParams struct {
	Objects   []string `json:"objects"`
	AdminMode bool     `json:"adminmode,omitempty"`
}

// Exists checks whether objects exist in the workspace
func (c *Client) Exists(paths []string) ([]*ExistsResult, error) {
	params := existsParams{
		Objects:   paths,
		AdminMode: c.AdminMode,
	}

	result, err := c.call("exists", params)
	if err != nil {
		return nil, err
	}

	var response []*ExistsResult
	if err := json.Unmarshal(result, &response); err != nil {
		return nil, fmt.Errorf("failed to parse exists response: %w", err)
	}

	return response, nil
}
