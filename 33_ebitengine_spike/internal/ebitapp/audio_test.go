package ebitapp

import (
	"strings"
	"testing"
)

func TestLoadAudioClipsDecodesPackagedWAVResources(t *testing.T) {
	t.Parallel()

	resources := []AudioResource{
		{
			ID:   "audio.attack",
			Path: "assets/runtime/audio/sfx/attack.wav",
		},
		{
			ID:   "audio.music",
			Path: "assets/runtime/audio/music/forest-theme.wav",
		},
	}
	clips, err := loadAudioClips(resources)
	if err != nil {
		t.Fatal(err)
	}
	if len(clips) != 2 ||
		len(clips["audio.attack"]) == 0 ||
		len(clips["audio.attack"])%4 != 0 ||
		len(clips["audio.music"]) == 0 ||
		len(clips["audio.music"])%4 != 0 {
		t.Fatalf("decoded clips = %#v", clips)
	}
	clips["audio.attack"][0] = 255
	again, err := loadAudioClips(resources[:1])
	if err != nil {
		t.Fatal(err)
	}
	if again["audio.attack"][0] == 255 {
		t.Fatal("decoded audio clips share mutable storage")
	}
}

func TestLoadAudioClipsRejectsDuplicateAndUnsafeResources(t *testing.T) {
	t.Parallel()

	tests := [][]AudioResource{
		{
			{ID: "audio.same", Path: "assets/runtime/audio/sfx/hit.wav"},
			{ID: "audio.same", Path: "assets/runtime/audio/sfx/parry.wav"},
		},
		{
			{ID: "audio.bad", Path: "../outside.wav"},
		},
		{
			{
				ID:   "audio.bad",
				Path: "assets/runtime/images/effects/slash.png",
			},
		},
	}
	for _, resources := range tests {
		if _, err := loadAudioClips(resources); err == nil {
			t.Fatalf("invalid resources passed: %#v", resources)
		}
	}
}

func TestAudioVolumesRejectNonFiniteAndOutOfRangeValues(t *testing.T) {
	t.Parallel()

	for _, value := range []float64{-0.1, 1.1} {
		if validAudioVolume(value) {
			t.Fatalf("volume %v passed", value)
		}
	}
	if !validAudioVolume(0) || !validAudioVolume(1) {
		t.Fatal("boundary volumes were rejected")
	}
	if _, err := loadAudioClips([]AudioResource{{
		ID:   "audio.bad",
		Path: "assets/runtime/audio/sfx/missing.wav",
	}}); err == nil || !strings.Contains(err.Error(), "load audio.bad") {
		t.Fatalf("missing audio error = %v", err)
	}
}
