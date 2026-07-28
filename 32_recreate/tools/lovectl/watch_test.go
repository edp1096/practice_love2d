package main

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func writeWatchTestFile(t *testing.T, root string, path string, value string) {
	t.Helper()
	absolute := filepath.Join(root, filepath.FromSlash(path))
	if err := os.MkdirAll(filepath.Dir(absolute), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(absolute, []byte(value), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestWatchSnapshotDetectsAddedChangedAndRemovedFiles(t *testing.T) {
	root := t.TempDir()
	writeWatchTestFile(
		t,
		root,
		"game/content/items/potion.lua",
		"old",
	)
	writeWatchTestFile(t, root, "game/maps/world.tmx", "map")
	writeWatchTestFile(t, root, "assets/images/hero.png", "image")
	before, err := scanWatchedFiles(root)
	if err != nil {
		t.Fatal(err)
	}

	writeWatchTestFile(
		t,
		root,
		"game/content/items/potion.lua",
		"new contents",
	)
	writeWatchTestFile(
		t,
		root,
		"game/content/items/ether.lua",
		"added",
	)
	if err := os.Remove(filepath.Join(root, "assets/images/hero.png")); err != nil {
		t.Fatal(err)
	}
	after, err := scanWatchedFiles(root)
	if err != nil {
		t.Fatal(err)
	}

	got := changedWatchedFiles(before, after)
	want := []string{
		"assets/images/hero.png",
		"game/content/items/ether.lua",
		"game/content/items/potion.lua",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("changed files = %#v, want %#v", got, want)
	}
}

func TestWatchOnlyCompilesChangedTMXSources(t *testing.T) {
	if !watchNeedsMapCompile([]string{"game/maps/world.tmx"}) {
		t.Fatal("expected TMX change to require map compilation")
	}
	if watchNeedsMapCompile([]string{
		"game/content/stages/generated/world.lua",
		"assets/images/world.png",
	}) {
		t.Fatal("generated content and assets must not trigger map compilation")
	}
}
