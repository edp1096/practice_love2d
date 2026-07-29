package ebitapp

import (
	"fmt"
	"image"
	"image/color"
	"math"

	"github.com/hajimehoshi/ebiten/v2"
)

const presentationTicksPerSecond = 60

type frameSpec struct {
	asset            string
	source           image.Rectangle
	originX, originY float64
	scale            float64
	tint             color.RGBA
	tintSet          bool
}

type loadedSprite struct {
	resource SpriteResource
	clips    map[string]SpriteClipResource
	states   map[string]string
}

func loadSpriteResources(
	resources []SpriteResource,
	images map[string]*ebiten.Image,
) (map[string]loadedSprite, error) {
	result := make(map[string]loadedSprite, len(resources))
	for index, resource := range resources {
		if resource.ID == "" {
			return nil, fmt.Errorf("sprite resource %d has an empty ID", index)
		}
		if _, duplicate := result[resource.ID]; duplicate {
			return nil, fmt.Errorf("sprite resource %q is duplicated", resource.ID)
		}
		source := images[resource.AssetID]
		if source == nil {
			return nil, fmt.Errorf(
				"sprite resource %q references missing image %q",
				resource.ID,
				resource.AssetID,
			)
		}
		if resource.FrameWidth <= 0 || resource.FrameHeight <= 0 {
			return nil, fmt.Errorf(
				"sprite resource %q has invalid frame dimensions",
				resource.ID,
			)
		}
		if !finiteSpriteNumber(resource.OriginX) ||
			!finiteSpriteNumber(resource.OriginY) ||
			!finiteSpriteNumber(resource.Scale) ||
			resource.Scale <= 0 {
			return nil, fmt.Errorf(
				"sprite resource %q has invalid geometry",
				resource.ID,
			)
		}
		sprite := loadedSprite{
			resource: resource,
			clips:    make(map[string]SpriteClipResource, len(resource.Clips)),
			states:   make(map[string]string, len(resource.StateMap)),
		}
		for clipIndex, clip := range resource.Clips {
			if clip.ID == "" {
				return nil, fmt.Errorf(
					"sprite resource %q clip %d has an empty ID",
					resource.ID,
					clipIndex,
				)
			}
			if _, duplicate := sprite.clips[clip.ID]; duplicate {
				return nil, fmt.Errorf(
					"sprite resource %q clip %q is duplicated",
					resource.ID,
					clip.ID,
				)
			}
			if !finiteSpriteNumber(clip.FPS) ||
				clip.FPS <= 0 ||
				len(clip.Frames) == 0 {
				return nil, fmt.Errorf(
					"sprite resource %q clip %q is invalid",
					resource.ID,
					clip.ID,
				)
			}
			detached := clip
			detached.Frames = append(
				[]SpriteFrameResource(nil),
				clip.Frames...,
			)
			for frameIndex, frame := range detached.Frames {
				rect := spriteFrameRect(
					frame.Column,
					frame.Row,
					resource.FrameWidth,
					resource.FrameHeight,
				)
				if frame.Column <= 0 ||
					frame.Row <= 0 ||
					!rect.In(source.Bounds()) {
					return nil, fmt.Errorf(
						"sprite resource %q clip %q frame %d is outside image %q",
						resource.ID,
						clip.ID,
						frameIndex,
						resource.AssetID,
					)
				}
			}
			sprite.clips[clip.ID] = detached
		}
		if _, exists := sprite.clips[resource.DefaultClip]; !exists {
			return nil, fmt.Errorf(
				"sprite resource %q default clip %q is missing",
				resource.ID,
				resource.DefaultClip,
			)
		}
		for stateIndex, mapping := range resource.StateMap {
			if mapping.State == "" {
				return nil, fmt.Errorf(
					"sprite resource %q state mapping %d has an empty state",
					resource.ID,
					stateIndex,
				)
			}
			if _, duplicate := sprite.states[mapping.State]; duplicate {
				return nil, fmt.Errorf(
					"sprite resource %q state %q is duplicated",
					resource.ID,
					mapping.State,
				)
			}
			if _, exists := sprite.clips[mapping.Clip]; !exists {
				return nil, fmt.Errorf(
					"sprite resource %q state %q references missing clip %q",
					resource.ID,
					mapping.State,
					mapping.Clip,
				)
			}
			sprite.states[mapping.State] = mapping.Clip
		}
		result[resource.ID] = sprite
	}
	return result, nil
}

func finiteSpriteNumber(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0)
}

func spriteFrameRect(
	column int,
	row int,
	width int,
	height int,
) image.Rectangle {
	return image.Rect(
		(column-1)*width,
		(row-1)*height,
		column*width,
		row*height,
	)
}

func spriteFrame(
	sprites map[string]loadedSprite,
	entity EntityView,
) (frameSpec, bool) {
	sprite, exists := sprites[entity.SpriteID]
	if !exists {
		return frameSpec{}, false
	}
	clipID := sprite.resource.DefaultClip
	if mapped, exists := sprite.states[entity.State]; exists {
		clipID = mapped
	}
	clip, exists := sprite.clips[clipID]
	if !exists || len(clip.Frames) == 0 {
		return frameSpec{}, false
	}
	frameIndex := int(
		float64(entity.AnimationTick) *
			clip.FPS /
			presentationTicksPerSecond,
	)
	if clip.Loop {
		frameIndex %= len(clip.Frames)
	} else if frameIndex >= len(clip.Frames) {
		frameIndex = len(clip.Frames) - 1
	}
	frame := clip.Frames[frameIndex]
	scale := sprite.resource.Scale
	if entity.SpriteScale > 0 {
		scale = entity.SpriteScale
	}
	return frameSpec{
		asset: sprite.resource.AssetID,
		source: spriteFrameRect(
			frame.Column,
			frame.Row,
			sprite.resource.FrameWidth,
			sprite.resource.FrameHeight,
		),
		originX: sprite.resource.OriginX,
		originY: sprite.resource.OriginY,
		scale:   scale,
		tint:    sprite.resource.Tint,
		tintSet: sprite.resource.TintSet,
	}, true
}
