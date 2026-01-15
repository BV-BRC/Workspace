package auth

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Token represents a P3/BV-BRC authentication token
type Token struct {
	TokenString string
	UserID      string
}

// LoadToken attempts to load an authentication token from various sources.
// It checks in order:
// 1. P3_TOKEN environment variable
// 2. ~/.patric_token file
// 3. ~/.bvbrc_token file
func LoadToken() (*Token, error) {
	// Check environment variable first
	if tokenStr := os.Getenv("P3_TOKEN"); tokenStr != "" {
		return parseToken(tokenStr)
	}

	// Get home directory
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, fmt.Errorf("cannot determine home directory: %w", err)
	}

	// Try ~/.patric_token
	tokenFiles := []string{
		filepath.Join(home, ".patric_token"),
		filepath.Join(home, ".bvbrc_token"),
	}

	for _, tokenFile := range tokenFiles {
		token, err := loadTokenFromFile(tokenFile)
		if err == nil {
			return token, nil
		}
		// Continue to next file if this one doesn't exist or is unreadable
	}

	return nil, fmt.Errorf("no authentication token found; please run p3-login first")
}

// loadTokenFromFile reads a token from a file
func loadTokenFromFile(path string) (*Token, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	if scanner.Scan() {
		tokenStr := strings.TrimSpace(scanner.Text())
		if tokenStr != "" {
			return parseToken(tokenStr)
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("error reading token file %s: %w", path, err)
	}

	return nil, fmt.Errorf("token file %s is empty", path)
}

// parseToken extracts user ID from a token string
// Token format is typically: un=user@example.org|...
func parseToken(tokenStr string) (*Token, error) {
	token := &Token{
		TokenString: tokenStr,
	}

	// Extract user ID from token
	// Format: un=user@example.org|tokenid=xxx|expiry=xxx|...
	parts := strings.Split(tokenStr, "|")
	for _, part := range parts {
		if strings.HasPrefix(part, "un=") {
			token.UserID = strings.TrimPrefix(part, "un=")
			break
		}
	}

	if token.UserID == "" {
		// Try alternative format with semicolons
		parts = strings.Split(tokenStr, ";")
		for _, part := range parts {
			if strings.HasPrefix(part, "un=") {
				token.UserID = strings.TrimPrefix(part, "un=")
				break
			}
		}
	}

	return token, nil
}

// Authorization returns the OAuth header value for HTTP requests
func (t *Token) Authorization() string {
	return "OAuth " + t.TokenString
}

// String returns a safe representation of the token (for debugging)
func (t *Token) String() string {
	if len(t.TokenString) > 20 {
		return fmt.Sprintf("Token{User: %s, Token: %s...}", t.UserID, t.TokenString[:20])
	}
	return fmt.Sprintf("Token{User: %s}", t.UserID)
}
