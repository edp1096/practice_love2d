package gameassets

import (
	"bytes"
	"image"
	_ "image/png"
	"io/fs"
	"reflect"
	"sort"
	"testing"
)

func TestRuntimeAssetsAreEmbeddedAndDecodable(t *testing.T) {
	t.Parallel()

	wantImages := map[string]image.Point{
		"images/effects/slash.png":           {X: 46, Y: 39},
		"images/enemies/slime-red-sheet.png": {X: 176, Y: 64},
		"images/npcs/guide-sheet.png":        {X: 384, Y: 96},
		"images/npcs/merchant-sheet.png":     {X: 384, Y: 96},
		"images/player/player-sheet.png":     {X: 384, Y: 960},
		"images/tilesets/tileset_area1.png":  {X: 864, Y: 576},
	}
	for path, wantSize := range wantImages {
		data, err := ReadFile(path)
		if err != nil {
			t.Fatalf("ReadFile(%q): %v", path, err)
		}
		config, format, err := image.DecodeConfig(bytes.NewReader(data))
		if err != nil {
			t.Fatalf("DecodeConfig(%q): %v", path, err)
		}
		if format != "png" {
			t.Errorf("%s format = %q, want png", path, format)
		}
		gotSize := image.Pt(config.Width, config.Height)
		if gotSize != wantSize {
			t.Errorf("%s size = %v, want %v", path, gotSize, wantSize)
		}
	}

	font, err := ReadFile("fonts/Hakgyoansim_ChaekgalpiR.ttf")
	if err != nil {
		t.Fatal(err)
	}
	if len(font) < 1_000_000 {
		t.Fatalf("embedded font is unexpectedly small: %d bytes", len(font))
	}
}

func TestFilesHasOnlyTheReviewedRuntimeSet(t *testing.T) {
	t.Parallel()

	var got []string
	err := fs.WalkDir(Files(), ".", func(
		path string,
		entry fs.DirEntry,
		walkErr error,
	) error {
		if walkErr != nil {
			return walkErr
		}
		if !entry.IsDir() {
			got = append(got, path)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	sort.Strings(got)
	want := []string{
		"fonts/Hakgyoansim_ChaekgalpiR.ttf",
		"images/effects/slash.png",
		"images/enemies/slime-red-sheet.png",
		"images/npcs/guide-sheet.png",
		"images/npcs/merchant-sheet.png",
		"images/player/player-sheet.png",
		"images/tilesets/tileset_area1.png",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("embedded files = %#v, want %#v", got, want)
	}
}
