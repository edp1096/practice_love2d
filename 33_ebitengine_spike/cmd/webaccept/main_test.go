package main

import (
	"image"
	"image/color"
	"os"
	"path/filepath"
	"testing"
)

func TestBrowserPathUsesExplicitExecutable(t *testing.T) {
	directory := t.TempDir()
	executable := filepath.Join(directory, "fixture-browser")
	if err := os.WriteFile(executable, []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	path, err := browserPath(executable)
	if err != nil {
		t.Fatal(err)
	}
	if path != executable {
		t.Fatalf("browser path = %q, want %q", path, executable)
	}
}

func TestTailLimitsDiagnostics(t *testing.T) {
	if got := tail("abcdef", 3); got != "def" {
		t.Fatalf("tail() = %q", got)
	}
	if got := tail("abc", 3); got != "abc" {
		t.Fatalf("short tail() = %q", got)
	}
}

func TestVerifyRenderedImageRejectsBlankCanvas(t *testing.T) {
	blank := image.NewRGBA(image.Rect(0, 0, 960, 540))
	if err := verifyRenderedImage(blank); err == nil {
		t.Fatal("blank canvas passed")
	}
	rendered := image.NewRGBA(image.Rect(0, 0, 960, 540))
	for y := 100; y < 130; y++ {
		for x := 100; x < 140; x++ {
			rendered.Set(x, y, color.White)
		}
	}
	if err := verifyRenderedImage(rendered); err != nil {
		t.Fatalf("rendered canvas failed: %v", err)
	}
}
