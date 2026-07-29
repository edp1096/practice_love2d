package gamebuild

import (
	"errors"
	"fmt"
	"math"

	"practice_love2d/33_ebitengine_spike/internal/content"
)

const (
	tileFlipHorizontal uint32 = 0x80000000
	tileFlipVertical   uint32 = 0x40000000
	tileFlipDiagonal   uint32 = 0x20000000
	tileGIDMask               = ^(tileFlipHorizontal |
		tileFlipVertical |
		tileFlipDiagonal)
)

// ImageAsset is one immutable image resource required by the compiled
// presentation. Path remains project-relative; a platform adapter resolves it
// through its packaged asset filesystem.
type ImageAsset struct {
	ID     string `json:"id"`
	Path   string `json:"path"`
	Width  int    `json:"width"`
	Height int    `json:"height"`
	Filter string `json:"filter"`
}

// Tilemap is a renderer-neutral authored orthogonal tilemap. Encoded layer
// GIDs retain Tiled's horizontal, vertical, and diagonal flip bits.
type Tilemap struct {
	Source     string      `json:"source,omitempty"`
	TileWidth  int         `json:"tile_width"`
	TileHeight int         `json:"tile_height"`
	Tilesets   []Tileset   `json:"tilesets"`
	Layers     []TileLayer `json:"layers"`
}

type Tileset struct {
	ID         string `json:"id"`
	AssetID    string `json:"asset_id"`
	FirstGID   uint32 `json:"first_gid"`
	TileCount  int    `json:"tile_count"`
	Columns    int    `json:"columns"`
	TileWidth  int    `json:"tile_width"`
	TileHeight int    `json:"tile_height"`
}

type TileLayer struct {
	ID      string   `json:"id"`
	Name    string   `json:"name,omitempty"`
	Width   int      `json:"width"`
	Height  int      `json:"height"`
	Visible bool     `json:"visible"`
	Opacity float64  `json:"opacity"`
	OffsetX float64  `json:"offset_x"`
	OffsetY float64  `json:"offset_y"`
	Data    []uint32 `json:"data"`
}

type assetDefinition struct {
	SchemaVersion int     `json:"schema_version"`
	Kind          string  `json:"kind"`
	ID            string  `json:"id"`
	AssetType     string  `json:"asset_type"`
	Path          string  `json:"path"`
	Width         float64 `json:"width"`
	Height        float64 `json:"height"`
	Filter        string  `json:"filter"`
}

type stageTilemap struct {
	Source     string           `json:"source"`
	TileWidth  int              `json:"tile_width"`
	TileHeight int              `json:"tile_height"`
	Tilesets   []stageTileset   `json:"tilesets"`
	Layers     []stageTileLayer `json:"layers"`
}

type stageTileset struct {
	ID         string `json:"id"`
	Asset      string `json:"asset"`
	FirstGID   uint32 `json:"first_gid"`
	TileCount  int    `json:"tile_count"`
	Columns    int    `json:"columns"`
	TileWidth  int    `json:"tile_width"`
	TileHeight int    `json:"tile_height"`
}

type stageTileLayer struct {
	ID      string   `json:"id"`
	Name    string   `json:"name"`
	Width   int      `json:"width"`
	Height  int      `json:"height"`
	Visible *bool    `json:"visible"`
	Opacity *float64 `json:"opacity"`
	OffsetX float64  `json:"offset_x"`
	OffsetY float64  `json:"offset_y"`
	Data    []uint32 `json:"data"`
}

func buildImageAssets(catalog *content.Catalog) ([]ImageAsset, error) {
	if catalog == nil {
		return nil, errors.New("catalog is nil")
	}
	graph := catalog.Graph()
	result := make([]ImageAsset, 0)
	for _, node := range graph.Nodes {
		if node.Kind != "asset" {
			continue
		}
		var authored assetDefinition
		if err := catalog.Decode(node.ID, &authored); err != nil {
			return nil, err
		}
		if err := validateHeader(
			authored.SchemaVersion,
			authored.Kind,
			authored.ID,
			"asset",
			node.ID,
		); err != nil {
			return nil, err
		}
		if authored.AssetType != "image" {
			continue
		}
		width, err := imageDimension(authored.Width, node.ID+".width")
		if err != nil {
			return nil, err
		}
		height, err := imageDimension(authored.Height, node.ID+".height")
		if err != nil {
			return nil, err
		}
		filter := authored.Filter
		if filter == "" {
			filter = "nearest"
		}
		if filter != "nearest" && filter != "linear" {
			return nil, fmt.Errorf(
				"%s.filter has unsupported value %q",
				node.ID,
				filter,
			)
		}
		if authored.Path == "" {
			return nil, fmt.Errorf("%s.path is empty", node.ID)
		}
		result = append(result, ImageAsset{
			ID:     node.ID,
			Path:   authored.Path,
			Width:  width,
			Height: height,
			Filter: filter,
		})
	}
	return result, nil
}

func imageDimension(value float64, path string) (int, error) {
	if math.IsNaN(value) ||
		math.IsInf(value, 0) ||
		value <= 0 ||
		math.Trunc(value) != value ||
		value > float64(maxIntValue()) {
		return 0, fmt.Errorf("%s must be a supported positive integer", path)
	}
	return int(value), nil
}

func maxIntValue() int {
	return int(^uint(0) >> 1)
}

func buildTilemap(
	authored *stageTilemap,
	images []ImageAsset,
) (*Tilemap, error) {
	if authored == nil {
		return nil, nil
	}
	if authored.TileWidth <= 0 || authored.TileHeight <= 0 {
		return nil, errors.New("tile size must be positive")
	}
	if len(authored.Tilesets) == 0 {
		return nil, errors.New("at least one tileset is required")
	}
	imageByID := make(map[string]ImageAsset, len(images))
	for _, image := range images {
		imageByID[image.ID] = image
	}
	result := &Tilemap{
		Source:     authored.Source,
		TileWidth:  authored.TileWidth,
		TileHeight: authored.TileHeight,
		Tilesets:   make([]Tileset, len(authored.Tilesets)),
		Layers:     make([]TileLayer, len(authored.Layers)),
	}
	seenTilesets := make(map[string]struct{}, len(authored.Tilesets))
	for index, source := range authored.Tilesets {
		if source.ID == "" ||
			source.Asset == "" ||
			source.FirstGID == 0 ||
			source.TileCount <= 0 ||
			source.Columns <= 0 ||
			source.TileWidth <= 0 ||
			source.TileHeight <= 0 {
			return nil, fmt.Errorf("tileset %d has invalid geometry", index)
		}
		if _, duplicate := seenTilesets[source.ID]; duplicate {
			return nil, fmt.Errorf("tileset %q is duplicated", source.ID)
		}
		seenTilesets[source.ID] = struct{}{}
		image, exists := imageByID[source.Asset]
		if !exists {
			return nil, fmt.Errorf(
				"tileset %q references unavailable image %q",
				source.ID,
				source.Asset,
			)
		}
		rows := (source.TileCount + source.Columns - 1) / source.Columns
		if source.Columns > image.Width/source.TileWidth ||
			rows > image.Height/source.TileHeight {
			return nil, fmt.Errorf(
				"tileset %q geometry %dx%d tiles exceeds image %q %dx%d",
				source.ID,
				source.Columns,
				rows,
				source.Asset,
				image.Width,
				image.Height,
			)
		}
		if uint64(source.FirstGID)+uint64(source.TileCount)-1 >
			uint64(tileGIDMask) {
			return nil, fmt.Errorf("tileset %q GID range overflows", source.ID)
		}
		result.Tilesets[index] = Tileset{
			ID:         source.ID,
			AssetID:    source.Asset,
			FirstGID:   source.FirstGID,
			TileCount:  source.TileCount,
			Columns:    source.Columns,
			TileWidth:  source.TileWidth,
			TileHeight: source.TileHeight,
		}
	}
	for left := range result.Tilesets {
		leftLast := uint64(result.Tilesets[left].FirstGID) +
			uint64(result.Tilesets[left].TileCount) - 1
		for right := left + 1; right < len(result.Tilesets); right++ {
			rightLast := uint64(result.Tilesets[right].FirstGID) +
				uint64(result.Tilesets[right].TileCount) - 1
			if uint64(result.Tilesets[left].FirstGID) <= rightLast &&
				uint64(result.Tilesets[right].FirstGID) <= leftLast {
				return nil, fmt.Errorf(
					"tileset GID ranges overlap between %q and %q",
					result.Tilesets[left].ID,
					result.Tilesets[right].ID,
				)
			}
		}
	}

	seenLayers := make(map[string]struct{}, len(authored.Layers))
	for index, source := range authored.Layers {
		if source.ID == "" || source.Width <= 0 || source.Height <= 0 {
			return nil, fmt.Errorf("layer %d has invalid geometry", index)
		}
		if _, duplicate := seenLayers[source.ID]; duplicate {
			return nil, fmt.Errorf("layer %q is duplicated", source.ID)
		}
		seenLayers[source.ID] = struct{}{}
		if len(source.Data) != source.Width*source.Height {
			return nil, fmt.Errorf(
				"layer %q contains %d GIDs, expected %d",
				source.ID,
				len(source.Data),
				source.Width*source.Height,
			)
		}
		visible := true
		if source.Visible != nil {
			visible = *source.Visible
		}
		opacity := 1.0
		if source.Opacity != nil {
			opacity = *source.Opacity
		}
		if !finite(source.OffsetX) ||
			!finite(source.OffsetY) ||
			!finite(opacity) ||
			opacity < 0 ||
			opacity > 1 {
			return nil, fmt.Errorf("layer %q has invalid presentation values", source.ID)
		}
		layer := TileLayer{
			ID:      source.ID,
			Name:    source.Name,
			Width:   source.Width,
			Height:  source.Height,
			Visible: visible,
			Opacity: opacity,
			OffsetX: source.OffsetX,
			OffsetY: source.OffsetY,
			Data:    append([]uint32(nil), source.Data...),
		}
		for tileIndex, encoded := range layer.Data {
			gid := encoded & tileGIDMask
			if gid == 0 {
				continue
			}
			if _, exists := tilesetForGID(result.Tilesets, gid); !exists {
				return nil, fmt.Errorf(
					"layer %q GID %d at %d belongs to no tileset",
					layer.ID,
					gid,
					tileIndex,
				)
			}
		}
		result.Layers[index] = layer
	}
	return result, nil
}

func tilesetForGID(tilesets []Tileset, gid uint32) (Tileset, bool) {
	for _, tileset := range tilesets {
		first := uint64(tileset.FirstGID)
		last := first + uint64(tileset.TileCount)
		if uint64(gid) >= first && uint64(gid) < last {
			return tileset, true
		}
	}
	return Tileset{}, false
}
