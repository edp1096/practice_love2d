package ebitapp

import "testing"

func TestCaptureRequestsArrivingDuringDrawWaitForNextFrame(t *testing.T) {
	t.Parallel()
	game := &Game{capture: make(chan captureRequest, 2)}
	first := captureRequest{result: make(chan captureResult, 1)}
	second := captureRequest{result: make(chan captureResult, 1)}

	game.capture <- first
	currentFrame := game.beginCaptures()
	if len(currentFrame) != 1 {
		t.Fatalf("current frame captures = %d, want 1", len(currentFrame))
	}
	game.capture <- second
	if got := len(currentFrame); got != 1 {
		t.Fatalf("mid-draw request changed current batch to %d", got)
	}
	nextFrame := game.beginCaptures()
	if len(nextFrame) != 1 {
		t.Fatalf("next frame captures = %d, want 1", len(nextFrame))
	}
}
