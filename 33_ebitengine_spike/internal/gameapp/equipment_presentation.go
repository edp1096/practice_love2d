package gameapp

import (
	"fmt"
	"strings"

	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

func equipmentModifierSummary(
	equipment *gamebuild.ItemEquipmentRule,
) string {
	if equipment == nil {
		return ""
	}
	parts := make([]string, 0, 3)
	if equipment.AttackModifier != 0 {
		parts = append(parts, fmt.Sprintf(
			"ATK %+.0f",
			equipment.AttackModifier,
		))
	}
	if equipment.DefenseModifier != 0 {
		parts = append(parts, fmt.Sprintf(
			"DEF %+.0f",
			equipment.DefenseModifier,
		))
	}
	if equipment.MoveSpeedModifier != 0 {
		parts = append(parts, fmt.Sprintf(
			"MOVE %+.2f",
			equipment.MoveSpeedModifier,
		))
	}
	return strings.Join(parts, " · ")
}
