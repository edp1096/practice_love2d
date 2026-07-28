package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestValidateProject(t *testing.T) {
	root := t.TempDir()
	for _, path := range []string{
		"main.lua",
		"game/game.lua",
		"engine/core/app.lua",
	} {
		absolute := filepath.Join(root, path)
		if err := os.MkdirAll(filepath.Dir(absolute), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(absolute, []byte("return {}\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	project, err := validateProject(root)
	if err != nil {
		t.Fatal(err)
	}
	if project != root {
		t.Fatalf("got %q, want %q", project, root)
	}
}

func TestValidateProjectRejectsIncompleteDirectory(t *testing.T) {
	if _, err := validateProject(t.TempDir()); err == nil {
		t.Fatal("expected incomplete project to be rejected")
	}
}
