package ebitapp

import "testing"

func TestHeroAnimationFramesStayInsideSheet(t *testing.T) {
	t.Parallel()

	states := []string{
		"idle_up", "idle_down", "idle_left", "idle_right",
		"move_up", "move_down", "move_left", "move_right",
		"attack_up", "attack_down", "attack_left", "attack_right",
	}
	for _, state := range states {
		for tick := uint64(0); tick < 240; tick++ {
			column, row := heroFrame(tick, state)
			if column < 1 || column > 8 || row < 1 || row > 20 {
				t.Fatalf(
					"heroFrame(%d,%q) = (%d,%d)",
					tick,
					state,
					column,
					row,
				)
			}
		}
	}
}

func TestSlimeAnimationFramesStayInsideSheet(t *testing.T) {
	t.Parallel()

	for _, state := range []string{
		"idle_left", "idle_right",
		"move_left", "move_right",
		"attack_left", "attack_right",
	} {
		for tick := uint64(0); tick < 240; tick++ {
			column, row := slimeFrame(tick, state)
			if column < 1 || column > 11 || row < 1 || row > 2 {
				t.Fatalf(
					"slimeFrame(%d,%q) = (%d,%d)",
					tick,
					state,
					column,
					row,
				)
			}
		}
	}
}
