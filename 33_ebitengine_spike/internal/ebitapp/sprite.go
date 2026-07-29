package ebitapp

import "image"

type frameSpec struct {
	asset            string
	source           image.Rectangle
	originX, originY float64
	scale            float64
}

func frameRect(
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

func spriteFrame(tick uint64, entity EntityView) (frameSpec, bool) {
	switch entity.SpriteID {
	case "sprite.hero":
		column, row := heroFrame(tick, entity.State)
		return frameSpec{
			asset:   "image.player_sheet",
			source:  frameRect(column, row, 48, 48),
			originX: 24,
			originY: 24,
			scale:   2,
		}, true
	case "sprite.slime":
		column, row := slimeFrame(tick, entity.State)
		return frameSpec{
			asset:   "image.slime_red_sheet",
			source:  frameRect(column, row, 16, 32),
			originX: 8,
			originY: 24,
			scale:   2.5,
		}, true
	case "sprite.guide", "sprite.merchant":
		column, row := directionalIdleFrame(tick, entity.State)
		asset := "image.guide_sheet"
		if entity.SpriteID == "sprite.merchant" {
			asset = "image.merchant_sheet"
		}
		return frameSpec{
			asset:   asset,
			source:  frameRect(column, row, 48, 48),
			originX: 24,
			originY: 24,
			scale:   2,
		}, true
	default:
		return frameSpec{}, false
	}
}

func directionalIdleFrame(tick uint64, state string) (int, int) {
	frame := int((tick/12)%4) + 1
	switch state {
	case "idle_up", "move_up":
		return frame + 4, 1
	case "idle_left", "move_left":
		return frame, 2
	case "idle_right", "move_right":
		return frame + 4, 2
	default:
		return frame, 1
	}
}

func heroFrame(tick uint64, state string) (int, int) {
	if len(state) >= len("attack_") && state[:len("attack_")] == "attack_" {
		frame := int((tick/5)%4) + 1
		switch state {
		case "attack_up":
			return frame + 4, 11
		case "attack_left":
			return frame, 12
		case "attack_right":
			return frame + 4, 12
		default:
			return frame, 11
		}
	}
	if len(state) >= len("move_") && state[:len("move_")] == "move_" {
		index := int((tick / 5) % 6)
		switch state {
		case "move_up":
			frames := [][2]int{
				{7, 6}, {8, 6}, {1, 7},
				{2, 7}, {3, 7}, {4, 7},
			}
			return frames[index][0], frames[index][1]
		case "move_left":
			frames := [][2]int{
				{5, 7}, {6, 7}, {7, 7},
				{8, 7}, {1, 8}, {2, 8},
			}
			return frames[index][0], frames[index][1]
		case "move_right":
			frames := [][2]int{
				{3, 8}, {4, 8}, {5, 8},
				{6, 8}, {7, 8}, {8, 8},
			}
			return frames[index][0], frames[index][1]
		default:
			return index + 1, 6
		}
	}
	return directionalIdleFrame(tick, state)
}

func slimeFrame(tick uint64, state string) (int, int) {
	row := 1
	if state == "idle_left" ||
		state == "move_left" ||
		state == "attack_left" {
		row = 2
	}
	switch state {
	case "attack_left", "attack_right":
		return 8 + int((tick/6)%4), row
	case "move_left", "move_right", "move_up", "move_down":
		return 4 + int((tick/7)%4), row
	default:
		return 1 + int((tick/12)%3), row
	}
}
