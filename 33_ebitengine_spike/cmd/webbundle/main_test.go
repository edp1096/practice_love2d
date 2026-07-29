package main

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestModulePathUsesTheActualDirective(t *testing.T) {
	data := []byte(`
// module practice_love2d/33_ebitengine_spike
module "example.invalid/not-recreate"
`)
	if got := modulePath(data); got != "example.invalid/not-recreate" {
		t.Fatalf("modulePath() = %q", got)
	}
}

func TestTargetEnvironmentReplacesAndSortsOverrides(t *testing.T) {
	got := targetEnvironment(
		[]string{"PATH=/bin", "GOOS=linux", "CGO_ENABLED=1"},
		map[string]string{
			"GOOS":        "js",
			"GOARCH":      "wasm",
			"CGO_ENABLED": "0",
		},
	)
	want := []string{
		"PATH=/bin",
		"CGO_ENABLED=0",
		"GOARCH=wasm",
		"GOOS=js",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("targetEnvironment() = %#v, want %#v", got, want)
	}
}

func TestWriteServiceWorkerScopesCacheToFingerprint(t *testing.T) {
	root := t.TempDir()
	fingerprint := strings.Repeat("ab", sha256.Size)
	if err := writeServiceWorker(root, fingerprint); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(root, "sw.js"))
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	if strings.Contains(text, "__RECREATE_CACHE_NAME__") ||
		!strings.Contains(text, "recreate-web-"+fingerprint[:16]) {
		t.Fatalf("service worker cache was not resolved:\n%s", text)
	}
	if err := writeServiceWorker(root, "short"); err == nil {
		t.Fatal("short fingerprint passed")
	}
}

func TestDeterministicArchiveHasStableOrderMetadataAndBytes(t *testing.T) {
	root := t.TempDir()
	for name, data := range map[string]string{
		"z.txt":        "last",
		"nested/a.txt": "first",
		"game.wasm":    "\x00asm",
	} {
		path := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(data), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	first := filepath.Join(t.TempDir(), "first.zip")
	second := filepath.Join(t.TempDir(), "second.zip")
	if err := writeDeterministicArchive(root, first); err != nil {
		t.Fatal(err)
	}
	if err := writeDeterministicArchive(root, second); err != nil {
		t.Fatal(err)
	}
	firstData, err := os.ReadFile(first)
	if err != nil {
		t.Fatal(err)
	}
	secondData, err := os.ReadFile(second)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(firstData, secondData) {
		t.Fatal("archive bytes changed between identical builds")
	}

	reader, err := zip.OpenReader(first)
	if err != nil {
		t.Fatal(err)
	}
	defer reader.Close()
	wantNames := []string{"game.wasm", "nested/a.txt", "z.txt"}
	var gotNames []string
	fixed := time.Date(1980, 1, 1, 0, 0, 0, 0, time.UTC)
	for _, file := range reader.File {
		gotNames = append(gotNames, file.Name)
		if !file.Modified.Equal(fixed) {
			t.Fatalf("%s timestamp = %s", file.Name, file.Modified)
		}
		if file.Mode().Perm() != 0o644 {
			t.Fatalf("%s mode = %o", file.Name, file.Mode().Perm())
		}
	}
	if !reflect.DeepEqual(gotNames, wantNames) {
		t.Fatalf("archive entries = %#v, want %#v", gotNames, wantNames)
	}
}

func TestPathInsideHonorsPathBoundaries(t *testing.T) {
	root := filepath.Join(string(filepath.Separator), "tmp", "output")
	if !pathInside(root, filepath.Join(root, "game.wasm")) {
		t.Fatal("child was not considered inside")
	}
	if pathInside(root, root+"-sibling") {
		t.Fatal("prefix sibling was considered inside")
	}
}
