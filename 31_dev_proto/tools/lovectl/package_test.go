package main

import (
	"archive/zip"
	"os"
	"path/filepath"
	"testing"
)

func TestPackageSelectionAndVerification(t *testing.T) {
	project := t.TempDir()
	for _, directory := range []string{"assets", "engine", "game", "vendor", "web", "tools"} {
		if err := os.MkdirAll(filepath.Join(project, directory), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	writeTestFile(t, project, "main.lua", "return true")
	writeTestFile(t, project, "config.ini", "[game]")
	writeTestFile(t, project, "engine/debug.lua", "return {}")
	writeTestFile(t, project, "assets/data.txt", "data")
	writeTestFile(t, project, "web/index.html", "excluded")
	writeTestFile(t, project, "tools/tool.go", "excluded")
	writeTestFile(t, project, ".claude/settings.json", "excluded")

	output := filepath.Join(project, "web", "game.love")
	if _, err := buildLovePackage(project, output); err != nil {
		t.Fatal(err)
	}
	if err := verifyLovePackage(project, output); err != nil {
		t.Fatal(err)
	}

	archive, err := zip.OpenReader(output)
	if err != nil {
		t.Fatal(err)
	}
	defer archive.Close()
	for _, entry := range archive.File {
		switch entry.Name {
		case "config.ini", "web/index.html", "tools/tool.go",
			".claude/settings.json":
			t.Fatalf("excluded file was packaged: %s", entry.Name)
		}
	}

	writeTestFile(t, project, "main.lua", "return false")
	if err := verifyLovePackage(project, output); err == nil {
		t.Fatal("stale package unexpectedly verified")
	}
}

func TestPackageBuildIsDeterministic(t *testing.T) {
	project := t.TempDir()
	for _, directory := range []string{"assets", "engine", "game", "vendor", "web"} {
		if err := os.MkdirAll(filepath.Join(project, directory), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	writeTestFile(t, project, "main.lua", "return true")
	writeTestFile(t, project, "engine/module.lua", "return {}")

	first := filepath.Join(t.TempDir(), "first.love")
	second := filepath.Join(t.TempDir(), "second.love")
	if _, err := buildLovePackage(project, first); err != nil {
		t.Fatal(err)
	}
	if _, err := buildLovePackage(project, second); err != nil {
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
	if string(firstData) != string(secondData) {
		t.Fatal("identical sources produced different archives")
	}
}

func writeTestFile(t *testing.T, root, relative, content string) {
	t.Helper()
	path := filepath.Join(root, filepath.FromSlash(relative))
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
