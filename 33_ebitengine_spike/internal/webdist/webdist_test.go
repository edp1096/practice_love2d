package webdist

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestHandlerServesWASMWithRequiredHeaders(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(
		filepath.Join(root, "game.wasm"),
		[]byte("\x00asm"),
		0o600,
	); err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodGet, "/game.wasm", nil)
	response := httptest.NewRecorder()
	Handler(root).ServeHTTP(response, request)
	if response.Code != http.StatusOK ||
		response.Header().Get("Content-Type") != "application/wasm" ||
		response.Header().Get("X-Content-Type-Options") != "nosniff" ||
		response.Body.String() != "\x00asm" {
		t.Fatalf(
			"web response = status %d headers %#v body %q",
			response.Code,
			response.Header(),
			response.Body.String(),
		)
	}
}

func TestValidateListenAddressRejectsNonLoopback(t *testing.T) {
	for _, address := range []string{
		"0.0.0.0:8080",
		"192.0.2.1:8080",
		"missing-port",
	} {
		if err := ValidateListenAddress(address); err == nil {
			t.Fatalf("address %q passed", address)
		}
	}
	for _, address := range []string{
		"127.0.0.1:0",
		"[::1]:0",
		"localhost:0",
	} {
		if err := ValidateListenAddress(address); err != nil {
			t.Fatalf("address %q failed: %v", address, err)
		}
	}
}

func TestVerifyRejectsChangedBundleFile(t *testing.T) {
	root := makeBundle(t)
	if _, err := Verify(root); err != nil {
		t.Fatalf("valid bundle failed: %v", err)
	}
	if err := os.WriteFile(
		filepath.Join(root, "app.js"),
		[]byte("changed"),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	if _, err := Verify(root); err == nil ||
		!strings.Contains(err.Error(), "byte count changed") {
		t.Fatalf("changed bundle error = %v", err)
	}
}

func TestSafeRelativePathRejectsTraversal(t *testing.T) {
	for _, value := range []string{
		"",
		"../game.wasm",
		"a/../../game.wasm",
		"/game.wasm",
		`nested\game.wasm`,
	} {
		if _, err := safeRelativePath(value); err == nil {
			t.Fatalf("path %q passed", value)
		}
	}
}

func makeBundle(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	var records []fileRecord
	for _, name := range requiredFiles {
		if name == "recreate-web.json" {
			continue
		}
		data := []byte("fixture:" + name)
		if err := os.WriteFile(filepath.Join(root, name), data, 0o644); err != nil {
			t.Fatal(err)
		}
		sum := sha256.Sum256(data)
		records = append(records, fileRecord{
			Path:   name,
			Bytes:  int64(len(data)),
			SHA256: hex.EncodeToString(sum[:]),
		})
	}
	data, err := json.Marshal(manifest{
		SchemaVersion:    1,
		Target:           "js/wasm",
		RequiredWASMMIME: "application/wasm",
		Files:            records,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(
		filepath.Join(root, "recreate-web.json"),
		data,
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	return root
}
