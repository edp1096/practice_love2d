package gameassets

import (
	"bytes"
	"encoding/binary"
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
		"images/effects/slash.png":              {X: 46, Y: 39},
		"images/enemies/slime-red-sheet.png":    {X: 176, Y: 64},
		"images/items/poison-jar.png":           {X: 288, Y: 32},
		"images/npcs/guide-sheet.png":           {X: 384, Y: 96},
		"images/npcs/merchant-sheet.png":        {X: 384, Y: 96},
		"images/player/player-sheet.png":        {X: 384, Y: 960},
		"images/tilesets/tileset_area1.png":     {X: 864, Y: 576},
		"images/tilesets/tileset_interior1.png": {X: 512, Y: 512},
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

	audioFiles := map[string]int{
		"audio/music/forest-theme.wav":  768044,
		"audio/music/road-theme.wav":    768044,
		"audio/music/village-theme.wav": 768044,
		"audio/sfx/attack.wav":          17324,
		"audio/sfx/hit.wav":             15404,
		"audio/sfx/jump.wav":            21164,
		"audio/sfx/kill.wav":            40364,
		"audio/sfx/parry.wav":           32684,
		"audio/sfx/projectile.wav":      23084,
		"audio/sfx/quest.wav":           69164,
		"audio/sfx/ui-cancel.wav":       11564,
		"audio/sfx/ui-confirm.wav":      11564,
	}
	for path, wantSize := range audioFiles {
		data, err := ReadFile(path)
		if err != nil {
			t.Fatalf("ReadFile(%q): %v", path, err)
		}
		if len(data) != wantSize ||
			len(data) < 44 ||
			string(data[:4]) != "RIFF" ||
			string(data[8:12]) != "WAVE" ||
			binary.LittleEndian.Uint32(data[24:28]) != 48_000 ||
			binary.LittleEndian.Uint16(data[34:36]) != 16 {
			t.Fatalf("%s is not the reviewed 48 kHz 16-bit WAV", path)
		}
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
		"audio/music/forest-theme.wav",
		"audio/music/road-theme.wav",
		"audio/music/village-theme.wav",
		"audio/sfx/attack.wav",
		"audio/sfx/hit.wav",
		"audio/sfx/jump.wav",
		"audio/sfx/kill.wav",
		"audio/sfx/parry.wav",
		"audio/sfx/projectile.wav",
		"audio/sfx/quest.wav",
		"audio/sfx/ui-cancel.wav",
		"audio/sfx/ui-confirm.wav",
		"fonts/Hakgyoansim_ChaekgalpiR.ttf",
		"images/effects/slash.png",
		"images/enemies/slime-red-sheet.png",
		"images/items/poison-jar.png",
		"images/npcs/guide-sheet.png",
		"images/npcs/merchant-sheet.png",
		"images/player/player-sheet.png",
		"images/tilesets/tileset_area1.png",
		"images/tilesets/tileset_interior1.png",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("embedded files = %#v, want %#v", got, want)
	}
}
