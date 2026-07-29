package gamebuild

import (
	"errors"
	"fmt"
	"path"
	"sort"
	"strings"

	"practice_love2d/33_ebitengine_spike/internal/content"
)

type AudioAsset struct {
	ID   string `json:"id"`
	Path string `json:"path"`
}

type AudioCueMapping struct {
	Event   string  `json:"event"`
	AssetID string  `json:"asset_id"`
	Volume  float64 `json:"volume"`
}

type StageMusicMapping struct {
	StageID string  `json:"stage_id"`
	AssetID string  `json:"asset_id"`
	Volume  float64 `json:"volume"`
}

// AudioPresentation is immutable project-wide routing plus packaged audio
// resources. Gameplay emits semantic event names and never imports an audio
// backend.
type AudioPresentation struct {
	MasterVolume float64             `json:"master_volume"`
	MusicVolume  float64             `json:"music_volume"`
	SFXVolume    float64             `json:"sfx_volume"`
	Assets       []AudioAsset        `json:"assets"`
	Cues         []AudioCueMapping   `json:"cues"`
	StageMusic   []StageMusicMapping `json:"stage_music"`
}

func (presentation AudioPresentation) Cue(
	event string,
) (AudioCueMapping, bool) {
	index := sort.Search(len(presentation.Cues), func(index int) bool {
		return presentation.Cues[index].Event >= event
	})
	if index == len(presentation.Cues) ||
		presentation.Cues[index].Event != event {
		return AudioCueMapping{}, false
	}
	return presentation.Cues[index], true
}

func (presentation AudioPresentation) Music(
	stageID string,
) (StageMusicMapping, bool) {
	index := sort.Search(len(presentation.StageMusic), func(index int) bool {
		return presentation.StageMusic[index].StageID >= stageID
	})
	if index == len(presentation.StageMusic) ||
		presentation.StageMusic[index].StageID != stageID {
		return StageMusicMapping{}, false
	}
	return presentation.StageMusic[index], true
}

func buildAudioPresentation(
	catalog *content.Catalog,
) (AudioPresentation, error) {
	if catalog == nil {
		return AudioPresentation{}, errors.New("catalog is nil")
	}
	project := catalog.Project()
	result := AudioPresentation{
		MasterVolume: project.Audio.MasterVolume,
		MusicVolume:  project.Audio.MusicVolume,
		SFXVolume:    project.Audio.SFXVolume,
		Assets:       []AudioAsset{},
		Cues:         make([]AudioCueMapping, len(project.Audio.Cues)),
		StageMusic: make(
			[]StageMusicMapping,
			len(project.Audio.StageMusic),
		),
	}
	for _, node := range catalog.Graph().Nodes {
		if node.Kind != "asset" {
			continue
		}
		var authored assetDefinition
		if err := catalog.Decode(node.ID, &authored); err != nil {
			return AudioPresentation{}, err
		}
		if authored.AssetType != "audio" {
			continue
		}
		if err := validateHeader(
			authored.SchemaVersion,
			authored.Kind,
			authored.ID,
			"asset",
			node.ID,
		); err != nil {
			return AudioPresentation{}, err
		}
		if authored.Path == "" ||
			strings.ToLower(path.Ext(authored.Path)) != ".wav" {
			return AudioPresentation{}, fmt.Errorf(
				"%s.path must name a WAV file",
				node.ID,
			)
		}
		result.Assets = append(result.Assets, AudioAsset{
			ID:   node.ID,
			Path: authored.Path,
		})
	}
	known := make(map[string]struct{}, len(result.Assets))
	for _, asset := range result.Assets {
		known[asset.ID] = struct{}{}
	}
	for index, cue := range project.Audio.Cues {
		if _, exists := known[cue.Asset]; !exists {
			return AudioPresentation{}, fmt.Errorf(
				"cue %q references missing packaged audio %q",
				cue.Event,
				cue.Asset,
			)
		}
		result.Cues[index] = AudioCueMapping{
			Event:   cue.Event,
			AssetID: cue.Asset,
			Volume:  cue.Volume,
		}
	}
	for index, track := range project.Audio.StageMusic {
		if _, exists := known[track.Asset]; !exists {
			return AudioPresentation{}, fmt.Errorf(
				"stage %q references missing packaged audio %q",
				track.Stage,
				track.Asset,
			)
		}
		result.StageMusic[index] = StageMusicMapping{
			StageID: track.Stage,
			AssetID: track.Asset,
			Volume:  track.Volume,
		}
	}
	return result, nil
}
