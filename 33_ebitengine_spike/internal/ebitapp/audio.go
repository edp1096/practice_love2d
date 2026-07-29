package ebitapp

import (
	"bytes"
	"fmt"
	"io"
	"math"
	"path"
	"strings"

	gameassets "practice_love2d/33_ebitengine_spike/assets"

	"github.com/hajimehoshi/ebiten/v2/audio"
	"github.com/hajimehoshi/ebiten/v2/audio/wav"
)

const (
	audioSampleRate       = 48_000
	maxSimultaneousSounds = 32
)

type audioManager struct {
	context *audio.Context
	clips   map[string][]byte

	masterVolume float64
	musicVolume  float64
	sfxVolume    float64

	musicID          string
	musicVolumeScale float64
	musicPlayer      *audio.Player
	sounds           []*audio.Player
	lastCue          uint64
}

func newAudioManager(
	manifest AudioResourceManifest,
) (*audioManager, error) {
	clips, err := loadAudioClips(manifest.Assets)
	if err != nil {
		return nil, err
	}
	if len(clips) == 0 {
		return nil, nil
	}
	for name, value := range map[string]float64{
		"master": manifest.MasterVolume,
		"music":  manifest.MusicVolume,
		"sfx":    manifest.SFXVolume,
	} {
		if !validAudioVolume(value) {
			return nil, fmt.Errorf(
				"audio %s volume must be between 0 and 1",
				name,
			)
		}
	}
	context := audio.CurrentContext()
	if context == nil {
		context = audio.NewContext(audioSampleRate)
	}
	return &audioManager{
		context:      context,
		clips:        clips,
		masterVolume: manifest.MasterVolume,
		musicVolume:  manifest.MusicVolume,
		sfxVolume:    manifest.SFXVolume,
	}, nil
}

func loadAudioClips(
	resources []AudioResource,
) (map[string][]byte, error) {
	result := make(map[string][]byte, len(resources))
	for index, resource := range resources {
		if resource.ID == "" {
			return nil, fmt.Errorf("audio resource %d has an empty ID", index)
		}
		if _, duplicate := result[resource.ID]; duplicate {
			return nil, fmt.Errorf("audio resource %q is duplicated", resource.ID)
		}
		if strings.ToLower(path.Ext(resource.Path)) != ".wav" {
			return nil, fmt.Errorf(
				"audio resource %q must be a WAV file",
				resource.ID,
			)
		}
		relative, err := packagedAssetPath(resource.Path)
		if err != nil {
			return nil, fmt.Errorf(
				"audio resource %q: %w",
				resource.ID,
				err,
			)
		}
		data, err := gameassets.ReadFile(relative)
		if err != nil {
			return nil, fmt.Errorf("load %s: %w", resource.ID, err)
		}
		stream, err := wav.DecodeWithSampleRate(
			audioSampleRate,
			bytes.NewReader(data),
		)
		if err != nil {
			return nil, fmt.Errorf("decode %s: %w", resource.ID, err)
		}
		decoded, err := io.ReadAll(stream)
		if err != nil {
			return nil, fmt.Errorf("read %s: %w", resource.ID, err)
		}
		if len(decoded) == 0 || len(decoded)%4 != 0 {
			return nil, fmt.Errorf(
				"audio resource %q decoded to invalid stereo PCM",
				resource.ID,
			)
		}
		result[resource.ID] = decoded
	}
	return result, nil
}

func (manager *audioManager) Sync(view AudioView) error {
	if manager == nil {
		return nil
	}
	if err := manager.syncMusic(
		view.MusicAssetID,
		view.MusicVolume,
	); err != nil {
		return err
	}
	manager.removeFinishedSounds()
	for _, cue := range view.Cues {
		if cue.Sequence <= manager.lastCue {
			continue
		}
		if cue.Sequence > manager.lastCue {
			manager.lastCue = cue.Sequence
		}
		if !validAudioVolume(cue.Volume) {
			return fmt.Errorf(
				"audio cue %d has invalid volume",
				cue.Sequence,
			)
		}
		clip, exists := manager.clips[cue.AssetID]
		if !exists {
			return fmt.Errorf(
				"audio cue %d references missing asset %q",
				cue.Sequence,
				cue.AssetID,
			)
		}
		manager.limitSounds()
		player := manager.context.NewPlayerFromBytes(clip)
		player.SetVolume(
			manager.masterVolume *
				manager.sfxVolume *
				cue.Volume,
		)
		player.Play()
		manager.sounds = append(manager.sounds, player)
	}
	return nil
}

func (manager *audioManager) syncMusic(id string, volume float64) error {
	if id == "" {
		manager.closeMusic()
		return nil
	}
	if !validAudioVolume(volume) {
		return fmt.Errorf("music %q has invalid volume", id)
	}
	if id == manager.musicID && manager.musicPlayer != nil {
		if volume != manager.musicVolumeScale {
			manager.musicVolumeScale = volume
			manager.musicPlayer.SetVolume(
				manager.masterVolume *
					manager.musicVolume *
					volume,
			)
		}
		return nil
	}
	clip, exists := manager.clips[id]
	if !exists {
		return fmt.Errorf("music references missing asset %q", id)
	}
	manager.closeMusic()
	loop := audio.NewInfiniteLoop(
		bytes.NewReader(clip),
		int64(len(clip)),
	)
	player, err := manager.context.NewPlayer(loop)
	if err != nil {
		return fmt.Errorf("create music player %q: %w", id, err)
	}
	player.SetVolume(manager.masterVolume * manager.musicVolume * volume)
	player.Play()
	manager.musicID = id
	manager.musicVolumeScale = volume
	manager.musicPlayer = player
	return nil
}

func (manager *audioManager) closeMusic() {
	if manager.musicPlayer != nil {
		_ = manager.musicPlayer.Close()
	}
	manager.musicID = ""
	manager.musicVolumeScale = 0
	manager.musicPlayer = nil
}

func (manager *audioManager) removeFinishedSounds() {
	active := manager.sounds[:0]
	for _, player := range manager.sounds {
		if player.IsPlaying() {
			active = append(active, player)
			continue
		}
		_ = player.Close()
	}
	manager.sounds = active
}

func (manager *audioManager) limitSounds() {
	for len(manager.sounds) >= maxSimultaneousSounds {
		_ = manager.sounds[0].Close()
		copy(manager.sounds, manager.sounds[1:])
		manager.sounds = manager.sounds[:len(manager.sounds)-1]
	}
}

func validAudioVolume(value float64) bool {
	return value >= 0 &&
		value <= 1 &&
		!math.IsNaN(value) &&
		!math.IsInf(value, 0)
}
