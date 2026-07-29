// Package webdist verifies and serves generated browser distributions.
package webdist

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

type manifest struct {
	SchemaVersion    int          `json:"schema_version"`
	Target           string       `json:"target"`
	RequiredWASMMIME string       `json:"required_wasm_mime"`
	Files            []fileRecord `json:"files"`
}

type fileRecord struct {
	Path   string `json:"path"`
	Bytes  int64  `json:"bytes"`
	SHA256 string `json:"sha256"`
}

var requiredFiles = []string{
	"app.js",
	"game.wasm",
	"icon.svg",
	"index.html",
	"manifest.webmanifest",
	"recreate-web.json",
	"style.css",
	"sw.js",
	"wasm_exec.js",
}

// Verify checks that root is a generated, unmodified browser bundle.
func Verify(rootValue string) (string, error) {
	root, err := filepath.Abs(rootValue)
	if err != nil {
		return "", err
	}
	root = filepath.Clean(root)
	info, err := os.Stat(root)
	if err != nil {
		return "", fmt.Errorf("open web root: %w", err)
	}
	if !info.IsDir() {
		return "", errors.New("web root is not a directory")
	}
	for _, name := range requiredFiles {
		info, err := os.Lstat(filepath.Join(root, name))
		if err != nil {
			return "", fmt.Errorf("web bundle is missing %s: %w", name, err)
		}
		if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
			return "", fmt.Errorf("web bundle file %s is not regular", name)
		}
	}
	data, err := os.ReadFile(filepath.Join(root, "recreate-web.json"))
	if err != nil {
		return "", err
	}
	var build manifest
	if err := json.Unmarshal(data, &build); err != nil {
		return "", fmt.Errorf("decode recreate-web.json: %w", err)
	}
	if build.SchemaVersion != 1 ||
		build.Target != "js/wasm" ||
		build.RequiredWASMMIME != "application/wasm" {
		return "", errors.New("web bundle manifest contract is unsupported")
	}
	if err := verifyRecords(root, build.Files); err != nil {
		return "", err
	}
	return root, nil
}

func verifyRecords(root string, records []fileRecord) error {
	seen := make(map[string]struct{}, len(records))
	for _, record := range records {
		name, err := safeRelativePath(record.Path)
		if err != nil {
			return err
		}
		if _, duplicate := seen[name]; duplicate {
			return fmt.Errorf("duplicate web bundle record %q", name)
		}
		seen[name] = struct{}{}
		path := filepath.Join(root, filepath.FromSlash(name))
		data, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("read web bundle record %q: %w", name, err)
		}
		if int64(len(data)) != record.Bytes {
			return fmt.Errorf("web bundle record %q byte count changed", name)
		}
		sum := sha256.Sum256(data)
		if !strings.EqualFold(hex.EncodeToString(sum[:]), record.SHA256) {
			return fmt.Errorf("web bundle record %q hash changed", name)
		}
	}
	for _, required := range requiredFiles {
		if required == "recreate-web.json" {
			continue
		}
		if _, found := seen[required]; !found {
			return fmt.Errorf("web manifest does not record %s", required)
		}
	}
	return nil
}

func safeRelativePath(value string) (string, error) {
	if value == "" ||
		strings.Contains(value, `\`) ||
		value != filepath.ToSlash(value) {
		return "", fmt.Errorf("invalid web bundle path %q", value)
	}
	clean := filepath.ToSlash(filepath.Clean(filepath.FromSlash(value)))
	if clean != value ||
		filepath.IsAbs(filepath.FromSlash(value)) ||
		value == ".." ||
		strings.HasPrefix(value, "../") {
		return "", fmt.Errorf("invalid web bundle path %q", value)
	}
	return value, nil
}

// ValidateListenAddress limits the development server to the local host.
func ValidateListenAddress(address string) error {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return fmt.Errorf("invalid web listen address: %w", err)
	}
	if host == "localhost" {
		return nil
	}
	ip := net.ParseIP(host)
	if ip == nil || !ip.IsLoopback() {
		return errors.New("web server must listen on a loopback address")
	}
	return nil
}

// Handler serves a verified static distribution with WebAssembly-safe headers.
func Handler(root string) http.Handler {
	files := http.FileServer(http.Dir(root))
	return http.HandlerFunc(func(
		writer http.ResponseWriter,
		request *http.Request,
	) {
		writer.Header().Set("Cache-Control", "no-store")
		writer.Header().Set("X-Content-Type-Options", "nosniff")
		writer.Header().Set("Referrer-Policy", "no-referrer")
		if filepath.Ext(request.URL.Path) == ".wasm" {
			writer.Header().Set("Content-Type", "application/wasm")
		}
		files.ServeHTTP(writer, request)
	})
}
