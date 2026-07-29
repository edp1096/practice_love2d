package ebitapp

import (
	"image"
	"image/color"
	"testing"
)

func testLoadedSprite(loop bool) map[string]loadedSprite {
	resource := SpriteResource{
		ID:          "sprite.test",
		AssetID:     "image.test",
		FrameWidth:  16,
		FrameHeight: 24,
		OriginX:     8,
		OriginY:     20,
		Scale:       2,
		Tint:        color.RGBA{R: 200, G: 210, B: 220, A: 255},
		TintSet:     true,
		DefaultClip: "idle",
	}
	return map[string]loadedSprite{
		resource.ID: {
			resource: resource,
			clips: map[string]SpriteClipResource{
				"idle": {
					ID:   "idle",
					FPS:  5,
					Loop: true,
					Frames: []SpriteFrameResource{
						{Column: 1, Row: 1},
					},
				},
				"action": {
					ID:   "action",
					FPS:  10,
					Loop: loop,
					Frames: []SpriteFrameResource{
						{Column: 2, Row: 1},
						{Column: 3, Row: 1},
						{Column: 4, Row: 1},
					},
				},
			},
			states: map[string]string{"attack_right": "action"},
		},
	}
}

func TestSpriteFrameUsesAuthoredStateFPSAndGeometry(t *testing.T) {
	t.Parallel()

	sprites := testLoadedSprite(true)
	entity := EntityView{
		SpriteID:      "sprite.test",
		State:         "attack_right",
		AnimationTick: 6,
	}
	got, found := spriteFrame(sprites, entity)
	if !found {
		t.Fatal("authored sprite was not resolved")
	}
	if got.asset != "image.test" ||
		got.source != image.Rect(32, 0, 48, 24) ||
		got.originX != 8 ||
		got.originY != 20 ||
		got.scale != 2 ||
		!got.tintSet {
		t.Fatalf("frame = %#v", got)
	}
}

func TestSpriteFrameClampsNonLoopingClipAndAppliesScaleOverride(
	t *testing.T,
) {
	t.Parallel()

	entity := EntityView{
		SpriteID:      "sprite.test",
		State:         "attack_right",
		AnimationTick: 999,
		SpriteScale:   4,
	}
	got, found := spriteFrame(testLoadedSprite(false), entity)
	if !found {
		t.Fatal("authored sprite was not resolved")
	}
	if got.source != image.Rect(48, 0, 64, 24) || got.scale != 4 {
		t.Fatalf("clamped frame = %#v", got)
	}
}

func TestSpriteFrameFallsBackForUnknownSprite(t *testing.T) {
	t.Parallel()

	if _, found := spriteFrame(
		testLoadedSprite(true),
		EntityView{SpriteID: "sprite.missing"},
	); found {
		t.Fatal("unknown sprite unexpectedly resolved")
	}
}
