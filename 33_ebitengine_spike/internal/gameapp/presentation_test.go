package gameapp

import (
	"image/color"
	"testing"
)

func TestViewPublishesDetachedAuthoredTilemapBackgroundAndResources(
	t *testing.T,
) {
	runtime := newCampaignRuntime(t)
	resources := runtime.ImageResources()
	if len(resources) != 6 {
		t.Fatalf("image resources = %d, want 6", len(resources))
	}
	foundTileset := false
	for _, resource := range resources {
		if resource.ID != "image.world_tileset" {
			continue
		}
		foundTileset = true
		if resource.Path !=
			"assets/runtime/images/tilesets/tileset_area1.png" ||
			resource.Width != 864 ||
			resource.Height != 576 ||
			resource.Filter != "nearest" {
			t.Fatalf("world tileset resource = %#v", resource)
		}
	}
	if !foundTileset {
		t.Fatal("world tileset resource is missing")
	}
	resources[0].ID = "mutated"
	if runtime.ImageResources()[0].ID == "mutated" {
		t.Fatal("image resource manifest was not detached")
	}

	moveEntityToPortal(t, runtime, "player", "to_field")
	stepProtocol(t, runtime, 1)
	view := runtime.View()
	if view.World.Background !=
		(color.RGBA{R: 16, G: 26, B: 34, A: 255}) {
		t.Fatalf("authored world background = %#v", view.World.Background)
	}
	if view.Tilemap == nil ||
		view.Tilemap.Source != "game/maps/world_hub.tmx" ||
		view.Tilemap.TileWidth != 32 ||
		view.Tilemap.TileHeight != 32 ||
		len(view.Tilemap.Tilesets) != 1 ||
		len(view.Tilemap.Layers) != 1 ||
		view.Tilemap.Layers[0].Width != 34 ||
		view.Tilemap.Layers[0].Height != 18 ||
		view.Tilemap.Layers[0].Data[0] != 29 {
		t.Fatalf("authored tilemap view = %#v", view.Tilemap)
	}
	view.Tilemap.Layers[0].Data[0] = 0
	if runtime.View().Tilemap.Layers[0].Data[0] != 29 {
		t.Fatal("tilemap View data mutated the Runtime presentation")
	}
}
