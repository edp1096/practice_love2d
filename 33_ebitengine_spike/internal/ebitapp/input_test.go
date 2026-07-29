package ebitapp

import (
	"math"
	"testing"
)

func TestMapRawInputNormalizesDigitalDiagonals(t *testing.T) {
	t.Parallel()

	got := mapRawInput(rawInput{right: true, up: true})
	want := math.Sqrt(0.5)
	if math.Abs(got.MoveX-want) > 1e-12 ||
		math.Abs(got.MoveY+want) > 1e-12 {
		t.Fatalf("movement = (%v,%v), want (%v,%v)",
			got.MoveX, got.MoveY, want, -want)
	}
}

func TestMapRawInputAppliesDeadzone(t *testing.T) {
	t.Parallel()

	got := mapRawInput(rawInput{stickX: 0.1, stickY: -0.1})
	if got.MoveX != 0 || got.MoveY != 0 {
		t.Fatalf("movement = (%v,%v), want zero", got.MoveX, got.MoveY)
	}
}

func TestMapRawInputKeepsActionEdges(t *testing.T) {
	t.Parallel()

	got := mapRawInput(rawInput{
		attack: true,
		parry:  true,
		dodge:  true,
		pause:  true,
	})
	if !got.Attack || !got.Parry || !got.Dodge || !got.Pause {
		t.Fatalf("action edges were lost: %#v", got)
	}
}
