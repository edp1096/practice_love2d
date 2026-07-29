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
