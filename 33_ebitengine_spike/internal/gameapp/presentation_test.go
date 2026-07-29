package gameapp

import (
	"image/color"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
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

func TestSpriteResourcesAndEntityOverridesAreDetached(t *testing.T) {
	runtime := newCampaignRuntime(t)
	resources := runtime.SpriteResources()
	if len(resources) != 4 {
		t.Fatalf("sprite resources = %d, want 4", len(resources))
	}
	var heroIndex = -1
	for index := range resources {
		if resources[index].ID == "sprite.hero" {
			heroIndex = index
			break
		}
	}
	if heroIndex < 0 {
		t.Fatal("hero sprite resource is missing")
	}
	hero := resources[heroIndex]
	if hero.AssetID != "image.player_sheet" ||
		hero.FrameWidth != 48 ||
		hero.DefaultClip != "idle_down" ||
		len(hero.Clips) != 12 {
		t.Fatalf("hero sprite resource = %#v", hero)
	}
	resources[heroIndex].Clips[0].Frames[0].Column = 999
	if runtime.SpriteResources()[heroIndex].Clips[0].Frames[0].Column == 999 {
		t.Fatal("sprite frame resource aliases Runtime presentation")
	}
}

func TestAuthoredAbilityVisualAndAttackAnimationReachView(t *testing.T) {
	runtime := newCampaignRuntime(t)
	if err := runtime.Tick(ebitapp.Actions{Attack: true}); err != nil {
		t.Fatal(err)
	}
	view := runtime.View()
	var player ebitapp.EntityView
	for _, entity := range view.Entities {
		if entity.ID == "player" {
			player = entity
			break
		}
	}
	if player.ID == "" ||
		player.State != "attack_right" ||
		player.AnimationTick != 0 {
		t.Fatalf("player attack presentation = %#v", player)
	}
	if len(view.Effects) != 1 {
		t.Fatalf("attack effects = %#v", view.Effects)
	}
	effect := view.Effects[0]
	if effect.Kind != "ability" ||
		effect.AssetID != "image.slash" ||
		effect.Scale != 1.2 ||
		effect.Opacity != 0.95 ||
		effect.X != player.X+31 ||
		effect.Y != player.Y {
		t.Fatalf("authored ability effect = %#v player=%#v", effect, player)
	}
}
