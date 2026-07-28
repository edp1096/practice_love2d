package main

import (
	"archive/zip"
	"path/filepath"
	"reflect"
	"testing"
)

func packageTestProject(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	for path, value := range map[string]string{
		"main.lua":                          "function love.load() end\n",
		"conf.lua":                          "function love.conf() end\n",
		"engine/core/app.lua":               "return {}\n",
		"game/game.lua":                     "return {}\n",
		"game/content/actors/hero.lua":      "return {}\n",
		"game/maps/source.tmx":              "<map/>\n",
		"assets/runtime/images/hero.png":    "png",
		"assets/source/images/hero.psd":     "source",
		"docs/README.md":                    "docs",
		"tests/should_not_be_packaged.lua":  "test",
		"artifacts/should_not_be_added.png": "artifact",
	} {
		writeWatchTestFile(t, root, path, value)
	}
	return root
}

func TestRuntimePackageIsDeterministicAndExcludesAuthoringFiles(t *testing.T) {
	root := packageTestProject(t)
	graph := contentGraph{
		Total:     2,
		EdgeCount: 1,
		Nodes: []contentGraphNode{
			{
				ID:        "image.hero",
				Kind:      "asset",
				AssetPath: "assets/runtime/images/hero.png",
			},
		},
	}
	paths, err := collectRuntimeFiles(root, graph)
	if err != nil {
		t.Fatal(err)
	}
	wantPaths := []string{
		"assets/runtime/images/hero.png",
		"conf.lua",
		"engine/core/app.lua",
		"game/content/actors/hero.lua",
		"game/game.lua",
		"main.lua",
	}
	if !reflect.DeepEqual(paths, wantPaths) {
		t.Fatalf("runtime files = %#v, want %#v", paths, wantPaths)
	}

	first, err := writeLovePackage(
		root,
		filepath.Join(root, "dist", "first.love"),
		paths,
		graph,
	)
	if err != nil {
		t.Fatal(err)
	}
	second, err := writeLovePackage(
		root,
		filepath.Join(root, "dist", "second.love"),
		paths,
		graph,
	)
	if err != nil {
		t.Fatal(err)
	}
	if first.SHA256 != second.SHA256 || first.Size != second.Size {
		t.Fatalf(
			"package is not deterministic: %#v != %#v",
			first,
			second,
		)
	}

	archive, err := zip.OpenReader(first.Path)
	if err != nil {
		t.Fatal(err)
	}
	defer archive.Close()
	var names []string
	for _, file := range archive.File {
		names = append(names, file.Name)
	}
	wantArchive := append([]string(nil), wantPaths...)
	wantArchive = append(wantArchive, "recreate-build.json")
	if !reflect.DeepEqual(names, wantArchive) {
		t.Fatalf("archive entries = %#v, want %#v", names, wantArchive)
	}
}

func TestRuntimePackageRejectsAssetOutsideRuntimeBoundary(t *testing.T) {
	root := packageTestProject(t)
	_, err := collectRuntimeFiles(root, contentGraph{
		Nodes: []contentGraphNode{
			{
				ID:        "image.source",
				Kind:      "asset",
				AssetPath: "assets/source/images/hero.psd",
			},
		},
	})
	if err == nil {
		t.Fatal("expected source asset path to be rejected")
	}
}

func TestRuntimePackageRequiresEveryDeclaredAssetFile(t *testing.T) {
	root := packageTestProject(t)
	_, err := collectRuntimeFiles(root, contentGraph{
		Nodes: []contentGraphNode{
			{
				ID:        "image.missing",
				Kind:      "asset",
				AssetPath: "assets/runtime/images/missing.png",
			},
		},
	})
	if err == nil {
		t.Fatal("expected missing runtime asset to fail")
	}
}
