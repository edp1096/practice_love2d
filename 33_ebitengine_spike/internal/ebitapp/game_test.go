package ebitapp

import (
	"reflect"
	"testing"
)

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

func TestWallPolygonScreenPointsUsesExactVerticesAndCameraTransform(
	t *testing.T,
) {
	t.Parallel()
	view := View{
		Camera: CameraView{
			X:      100,
			Y:      50,
			ShakeX: -3,
			ShakeY: 4,
			Zoom:   2,
		},
	}
	wall := RectView{
		// Deliberately unrelated bounds prove the polygon path does not render
		// the broad-phase rectangle.
		X:      -1000,
		Y:      -1000,
		Width:  2000,
		Height: 2000,
		Points: []PointView{
			{X: 110, Y: 60},
			{X: 125, Y: 64},
			{X: 118, Y: 80},
		},
	}
	got := wallPolygonScreenPoints(view, wall)
	want := []PointView{
		{X: 14, Y: 28},
		{X: 44, Y: 36},
		{X: 30, Y: 68},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("screen polygon = %#v, want %#v", got, want)
	}
	got[0].X = -999
	if wall.Points[0].X != 110 {
		t.Fatal("screen polygon aliases the immutable world-coordinate view")
	}
	if points := wallPolygonScreenPoints(view, RectView{}); points != nil {
		t.Fatalf("rectangle produced polygon points: %#v", points)
	}
}
