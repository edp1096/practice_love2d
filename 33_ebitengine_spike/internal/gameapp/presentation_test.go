package gameapp

import (
	"image/color"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func TestAccessibilitySettingsControlMotionFlashAndNoticeDuration(
	t *testing.T,
) {
	runtime := newCampaignRuntime(t)
	session := runtime.simulation.SaveSession()
	for index := range session.Entities {
		if session.Entities[index].ID == "player" {
			session.Entities[index].FlashTicks = 1
		}
	}
	session.Camera.Offset = sim.Vec{
		X: sim.Pixels(10),
		Y: sim.Pixels(-4),
	}
	session.Camera.Center = sim.Vec{
		X: session.Camera.BaseCenter.X + session.Camera.Offset.X,
		Y: session.Camera.BaseCenter.Y + session.Camera.Offset.Y,
	}
	session.Camera.ShakeMagnitude = sim.Pixels(10)
	session.Camera.ShakeDuration = 10
	session.Camera.ShakeRemaining = 10
	if err := runtime.simulation.LoadSession(session); err != nil {
		t.Fatal(err)
	}

	full := runtime.View()
	if full.Camera.ShakeX != -10 ||
		full.Camera.ShakeY != 4 ||
		!presentedEntity(t, full, "player").Flash {
		t.Fatalf("full accessibility view = %#v", full)
	}
	if err := runtime.campaign.Transaction(
		func(state *campaign.State) error {
			state.Accessibility = campaign.AccessibilitySettings{
				Motion:         "reduced",
				HitFlash:       false,
				NoticeDuration: "long",
			}
			return nil
		},
	); err != nil {
		t.Fatal(err)
	}

	reduced := runtime.View()
	if reduced.Camera.ShakeX != -3.5 ||
		reduced.Camera.ShakeY != 1.4 ||
		presentedEntity(t, reduced, "player").Flash {
		t.Fatalf("reduced accessibility view = %#v", reduced)
	}
	if got := noticeTicks(120, runtime.CampaignState().Accessibility); got !=
		240 {
		t.Fatalf("long notice ticks = %d, want 240", got)
	}
}

func presentedEntity(
	t *testing.T,
	view ebitapp.View,
	entityID string,
) ebitapp.EntityView {
	t.Helper()
	for _, entity := range view.Entities {
		if entity.ID == entityID {
			return entity
		}
	}
	t.Fatalf("presented entity %q is missing", entityID)
	return ebitapp.EntityView{}
}

func TestViewPublishesDetachedAuthoredTilemapBackgroundAndResources(
	t *testing.T,
) {
	runtime := newCampaignRuntime(t)
	resources := runtime.ImageResources()
	if len(resources) != 8 {
		t.Fatalf("image resources = %d, want 8", len(resources))
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
	if len(resources) != 5 {
		t.Fatalf("sprite resources = %d, want 5", len(resources))
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

func TestAuthoredMusicAndSemanticAudioCuesReachView(t *testing.T) {
	runtime := newCampaignRuntime(t)
	resources := runtime.AudioResources()
	if resources.MasterVolume != 0.8 ||
		resources.MusicVolume != 0.45 ||
		resources.SFXVolume != 0.8 ||
		len(resources.Assets) != 12 {
		t.Fatalf("audio resources = %#v", resources)
	}
	resources.Assets[0].ID = "mutated"
	if runtime.AudioResources().Assets[0].ID == "mutated" {
		t.Fatal("audio resources alias Runtime presentation")
	}

	initial := runtime.View()
	if initial.Audio.MusicAssetID != "audio.village_theme" ||
		initial.Audio.MusicVolume != 0.65 ||
		len(initial.Audio.Cues) != 0 {
		t.Fatalf("initial audio view = %#v", initial.Audio)
	}
	if err := runtime.Tick(ebitapp.Actions{Attack: true}); err != nil {
		t.Fatal(err)
	}
	attacking := runtime.View().Audio
	if len(attacking.Cues) != 1 ||
		attacking.Cues[0] != (ebitapp.AudioCueView{
			Sequence: 1,
			Event:    "attack.started",
			AssetID:  "audio.attack",
			Volume:   0.75,
		}) {
		t.Fatalf("attack audio = %#v", attacking)
	}
	repeated := runtime.View().Audio
	if len(repeated.Cues) != 1 ||
		repeated.Cues[0].Sequence != 1 {
		t.Fatalf("repeated audio view changed sequence = %#v", repeated)
	}

	finishVillageArrivalCutscene(t, runtime)
	moveEntityToPortal(t, runtime, "player", "to_field")
	stepProtocol(t, runtime, 1)
	hub := runtime.View().Audio
	if hub.MusicAssetID != "audio.road_theme" ||
		hub.MusicVolume != 0.7 {
		t.Fatalf("hub music = %#v", hub)
	}
}

func TestModalUIAudioUsesTheSameSemanticInputBoundary(t *testing.T) {
	runtime := newCampaignRuntime(t)
	if err := runtime.Tick(ebitapp.Actions{InventoryToggle: true}); err != nil {
		t.Fatal(err)
	}
	opened := runtime.View().Audio.Cues
	if len(opened) != 1 ||
		opened[0].Event != "ui.confirm" ||
		opened[0].AssetID != "audio.ui_confirm" {
		t.Fatalf("inventory open audio = %#v", opened)
	}
	if err := runtime.Tick(ebitapp.Actions{InventoryCancel: true}); err != nil {
		t.Fatal(err)
	}
	closed := runtime.View().Audio.Cues
	if len(closed) != 2 ||
		closed[1].Sequence != opened[0].Sequence+1 ||
		closed[1].Event != "ui.cancel" ||
		closed[1].AssetID != "audio.ui_cancel" {
		t.Fatalf("inventory close audio = %#v", closed)
	}
}

func TestPauseFlowQueuesSemanticConfirmAudio(t *testing.T) {
	runtime := newCampaignRuntime(t)
	if err := runtime.Tick(ebitapp.Actions{Pause: true}); err != nil {
		t.Fatal(err)
	}
	cues := runtime.View().Audio.Cues
	if len(cues) != 1 ||
		cues[0].Event != "ui.confirm" ||
		cues[0].AssetID != "audio.ui_confirm" {
		t.Fatalf("pause audio = %#v", cues)
	}
}

func TestAudioCueViewRetainsTheNewestBoundedSequence(t *testing.T) {
	runtime := newCampaignRuntime(t)
	for range 140 {
		runtime.queueAudioEvent("attack.started")
	}
	cues := runtime.View().Audio.Cues
	if len(cues) != 128 ||
		cues[0].Sequence != 13 ||
		cues[len(cues)-1].Sequence != 140 {
		t.Fatalf("retained audio cues = %#v", cues)
	}
}
