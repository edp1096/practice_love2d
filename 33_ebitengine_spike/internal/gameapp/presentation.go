package gameapp

import (
	"image/color"
	"math"

	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

// ImageResources exposes the immutable compiled image manifest to the
// Ebitengine adapter. The returned slice owns all of its values.
func (runtime *Runtime) ImageResources() []ebitapp.ImageResource {
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	result := make(
		[]ebitapp.ImageResource,
		len(runtime.built.Presentation.Images),
	)
	for index, source := range runtime.built.Presentation.Images {
		result[index] = ebitapp.ImageResource{
			ID:     source.ID,
			Path:   source.Path,
			Width:  source.Width,
			Height: source.Height,
			Filter: source.Filter,
		}
	}
	return result
}

// SpriteResources exposes authored animation clips without leaking mutable
// Presentation slices into the platform adapter.
func (runtime *Runtime) SpriteResources() []ebitapp.SpriteResource {
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	result := make(
		[]ebitapp.SpriteResource,
		len(runtime.built.Presentation.Sprites),
	)
	for index, source := range runtime.built.Presentation.Sprites {
		target := ebitapp.SpriteResource{
			ID:          source.ID,
			AssetID:     source.AssetID,
			FrameWidth:  source.FrameWidth,
			FrameHeight: source.FrameHeight,
			OriginX:     source.OriginX,
			OriginY:     source.OriginY,
			Scale:       source.Scale,
			Tint:        presentationColor(source.Tint),
			TintSet:     source.TintSet,
			DefaultClip: source.DefaultClip,
			Clips: make(
				[]ebitapp.SpriteClipResource,
				len(source.Clips),
			),
			StateMap: make(
				[]ebitapp.SpriteStateResource,
				len(source.StateMap),
			),
		}
		for clipIndex, clip := range source.Clips {
			targetClip := ebitapp.SpriteClipResource{
				ID:   clip.ID,
				FPS:  clip.FPS,
				Loop: clip.Loop,
				Frames: make(
					[]ebitapp.SpriteFrameResource,
					len(clip.Frames),
				),
			}
			for frameIndex, frame := range clip.Frames {
				targetClip.Frames[frameIndex] = ebitapp.SpriteFrameResource{
					Column: frame.Column,
					Row:    frame.Row,
				}
			}
			target.Clips[clipIndex] = targetClip
		}
		for stateIndex, mapping := range source.StateMap {
			target.StateMap[stateIndex] = ebitapp.SpriteStateResource{
				State: mapping.State,
				Clip:  mapping.Clip,
			}
		}
		result[index] = target
	}
	return result
}

func (runtime *Runtime) AudioResources() ebitapp.AudioResourceManifest {
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	source := runtime.built.Presentation.Audio
	result := ebitapp.AudioResourceManifest{
		MasterVolume: source.MasterVolume,
		MusicVolume:  source.MusicVolume,
		SFXVolume:    source.SFXVolume,
		Assets:       make([]ebitapp.AudioResource, len(source.Assets)),
	}
	for index, asset := range source.Assets {
		result.Assets[index] = ebitapp.AudioResource{
			ID:   asset.ID,
			Path: asset.Path,
		}
	}
	return result
}

func tilemapView(source *gamebuild.Tilemap) *ebitapp.TilemapView {
	if source == nil {
		return nil
	}
	result := &ebitapp.TilemapView{
		Source:     source.Source,
		TileWidth:  source.TileWidth,
		TileHeight: source.TileHeight,
		Tilesets:   make([]ebitapp.TilesetView, len(source.Tilesets)),
		Layers:     make([]ebitapp.TileLayerView, len(source.Layers)),
	}
	for index, tileset := range source.Tilesets {
		result.Tilesets[index] = ebitapp.TilesetView{
			ID:         tileset.ID,
			AssetID:    tileset.AssetID,
			FirstGID:   tileset.FirstGID,
			TileCount:  tileset.TileCount,
			Columns:    tileset.Columns,
			TileWidth:  tileset.TileWidth,
			TileHeight: tileset.TileHeight,
		}
	}
	for index, layer := range source.Layers {
		result.Layers[index] = ebitapp.TileLayerView{
			ID:      layer.ID,
			Name:    layer.Name,
			Width:   layer.Width,
			Height:  layer.Height,
			Visible: layer.Visible,
			Opacity: layer.Opacity,
			OffsetX: layer.OffsetX,
			OffsetY: layer.OffsetY,
			Data:    append([]uint32(nil), layer.Data...),
		}
	}
	return result
}

func presentationColor(values [4]float64) color.RGBA {
	channel := func(value float64) uint8 {
		return uint8(math.Round(min(1, max(0, value)) * 255))
	}
	return color.RGBA{
		R: channel(values[0]),
		G: channel(values[1]),
		B: channel(values[2]),
		A: channel(values[3]),
	}
}
