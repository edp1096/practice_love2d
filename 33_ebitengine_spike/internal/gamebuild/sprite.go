package gamebuild

import (
	"errors"
	"fmt"
	"sort"

	"practice_love2d/33_ebitengine_spike/internal/content"
)

// SpriteFrame is a one-based cell inside an authored sprite sheet.
type SpriteFrame struct {
	Column int `json:"column"`
	Row    int `json:"row"`
}

type SpriteClip struct {
	ID     string        `json:"id"`
	FPS    float64       `json:"fps"`
	Loop   bool          `json:"loop"`
	Frames []SpriteFrame `json:"frames"`
}

type SpriteStateMapping struct {
	State string `json:"state"`
	Clip  string `json:"clip"`
}

// SpriteDefinition is the complete renderer-neutral animation resource built
// from content. Slices are kept in stable ID order so adapters do not need to
// depend on Go map iteration.
type SpriteDefinition struct {
	ID          string               `json:"id"`
	AssetID     string               `json:"asset_id"`
	FrameWidth  int                  `json:"frame_width"`
	FrameHeight int                  `json:"frame_height"`
	OriginX     float64              `json:"origin_x"`
	OriginY     float64              `json:"origin_y"`
	Scale       float64              `json:"scale"`
	Tint        [4]float64           `json:"tint"`
	TintSet     bool                 `json:"tint_set"`
	DefaultClip string               `json:"default_clip"`
	Clips       []SpriteClip         `json:"clips"`
	StateMap    []SpriteStateMapping `json:"state_map"`
}

type AbilityVisual struct {
	AbilityID      string  `json:"ability_id"`
	AssetID        string  `json:"asset_id"`
	Scale          float64 `json:"scale"`
	Distance       float64 `json:"distance"`
	RotationOffset float64 `json:"rotation_offset"`
}

type authoredSpriteDefinition struct {
	SchemaVersion int                           `json:"schema_version"`
	Kind          string                        `json:"kind"`
	ID            string                        `json:"id"`
	Asset         string                        `json:"asset"`
	FrameWidth    float64                       `json:"frame_width"`
	FrameHeight   float64                       `json:"frame_height"`
	OriginX       float64                       `json:"origin_x"`
	OriginY       float64                       `json:"origin_y"`
	Scale         float64                       `json:"scale"`
	Tint          []float64                     `json:"tint"`
	DefaultClip   string                        `json:"default_clip"`
	Clips         map[string]authoredSpriteClip `json:"clips"`
	StateMap      map[string]string             `json:"state_map"`
}

type authoredSpriteClip struct {
	FPS    float64 `json:"fps"`
	Loop   *bool   `json:"loop"`
	Frames [][]int `json:"frames"`
}

func buildSpriteDefinitions(
	catalog *content.Catalog,
) ([]SpriteDefinition, error) {
	if catalog == nil {
		return nil, errors.New("catalog is nil")
	}
	graph := catalog.Graph()
	result := make([]SpriteDefinition, 0)
	for _, node := range graph.Nodes {
		if node.Kind != "sprite" {
			continue
		}
		if _, err := ValidateDefinition(catalog, node.ID); err != nil {
			return nil, err
		}
		var authored authoredSpriteDefinition
		if err := catalog.Decode(node.ID, &authored); err != nil {
			return nil, err
		}
		if err := validateHeader(
			authored.SchemaVersion,
			authored.Kind,
			authored.ID,
			"sprite",
			node.ID,
		); err != nil {
			return nil, err
		}
		sprite, err := translateSprite(authored)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", node.ID, err)
		}
		result = append(result, sprite)
	}
	return result, nil
}

func buildAbilityVisuals(catalog *content.Catalog) ([]AbilityVisual, error) {
	if catalog == nil {
		return nil, errors.New("catalog is nil")
	}
	graph := catalog.Graph()
	result := make([]AbilityVisual, 0)
	for _, node := range graph.Nodes {
		if node.Kind != "ability" {
			continue
		}
		if _, err := ValidateDefinition(catalog, node.ID); err != nil {
			return nil, err
		}
		var authored abilityDefinition
		if err := catalog.Decode(node.ID, &authored); err != nil {
			return nil, err
		}
		if authored.Visual == nil {
			continue
		}
		visual := AbilityVisual{
			AbilityID:      node.ID,
			AssetID:        authored.Visual.Asset,
			Scale:          authored.Visual.Scale,
			Distance:       authored.Visual.Distance,
			RotationOffset: authored.Visual.RotationOffset,
		}
		if visual.Scale == 0 {
			visual.Scale = 1
		}
		if visual.AssetID == "" ||
			!positiveFinite(visual.Scale) ||
			!finite(visual.Distance) ||
			!finite(visual.RotationOffset) {
			return nil, fmt.Errorf(
				"%s has invalid visual presentation",
				node.ID,
			)
		}
		result = append(result, visual)
	}
	return result, nil
}

func translateSprite(
	authored authoredSpriteDefinition,
) (SpriteDefinition, error) {
	width, err := imageDimension(authored.FrameWidth, "frame_width")
	if err != nil {
		return SpriteDefinition{}, err
	}
	height, err := imageDimension(authored.FrameHeight, "frame_height")
	if err != nil {
		return SpriteDefinition{}, err
	}
	scale := authored.Scale
	if scale == 0 {
		scale = 1
	}
	if !positiveFinite(scale) {
		return SpriteDefinition{}, errors.New("scale must be positive and finite")
	}
	if !finite(authored.OriginX) || !finite(authored.OriginY) {
		return SpriteDefinition{}, errors.New("origin must be finite")
	}
	result := SpriteDefinition{
		ID:          authored.ID,
		AssetID:     authored.Asset,
		FrameWidth:  width,
		FrameHeight: height,
		OriginX:     authored.OriginX,
		OriginY:     authored.OriginY,
		Scale:       scale,
		DefaultClip: authored.DefaultClip,
	}
	if len(authored.Tint) != 0 {
		result.Tint, err = rgba(authored.Tint)
		if err != nil {
			return SpriteDefinition{}, fmt.Errorf("tint: %w", err)
		}
		result.TintSet = true
	}

	clipIDs := make([]string, 0, len(authored.Clips))
	for id := range authored.Clips {
		clipIDs = append(clipIDs, id)
	}
	sort.Strings(clipIDs)
	result.Clips = make([]SpriteClip, 0, len(clipIDs))
	for _, id := range clipIDs {
		source := authored.Clips[id]
		if !positiveFinite(source.FPS) {
			return SpriteDefinition{}, fmt.Errorf(
				"clip %q fps must be positive and finite",
				id,
			)
		}
		loop := true
		if source.Loop != nil {
			loop = *source.Loop
		}
		clip := SpriteClip{
			ID:     id,
			FPS:    source.FPS,
			Loop:   loop,
			Frames: make([]SpriteFrame, len(source.Frames)),
		}
		for index, frame := range source.Frames {
			if len(frame) != 2 || frame[0] <= 0 || frame[1] <= 0 {
				return SpriteDefinition{}, fmt.Errorf(
					"clip %q frame %d must contain positive column and row",
					id,
					index,
				)
			}
			clip.Frames[index] = SpriteFrame{
				Column: frame[0],
				Row:    frame[1],
			}
		}
		if len(clip.Frames) == 0 {
			return SpriteDefinition{}, fmt.Errorf(
				"clip %q must contain frames",
				id,
			)
		}
		result.Clips = append(result.Clips, clip)
	}
	states := make([]string, 0, len(authored.StateMap))
	for state := range authored.StateMap {
		states = append(states, state)
	}
	sort.Strings(states)
	result.StateMap = make([]SpriteStateMapping, len(states))
	for index, state := range states {
		if _, exists := authored.Clips[authored.StateMap[state]]; !exists {
			return SpriteDefinition{}, fmt.Errorf(
				"state %q references missing clip %q",
				state,
				authored.StateMap[state],
			)
		}
		result.StateMap[index] = SpriteStateMapping{
			State: state,
			Clip:  authored.StateMap[state],
		}
	}
	if _, exists := authored.Clips[result.DefaultClip]; !exists {
		return SpriteDefinition{}, fmt.Errorf(
			"default clip %q is missing",
			result.DefaultClip,
		)
	}
	return result, nil
}

func rgba(values []float64) ([4]float64, error) {
	var result [4]float64
	if len(values) != len(result) {
		return result, fmt.Errorf("expected 4 channels, got %d", len(values))
	}
	for index, value := range values {
		if !finite(value) || value < 0 || value > 1 {
			return result, fmt.Errorf(
				"channel %d must be finite and between 0 and 1",
				index,
			)
		}
		result[index] = value
	}
	return result, nil
}
