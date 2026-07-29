package gameapp

import (
	"path/filepath"
	"reflect"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/storage"
)

func TestPolygonWallDebugAndRenderViewsAreExactAndDetached(t *testing.T) {
	t.Parallel()
	store, err := storage.NewFileStore(filepath.Join(t.TempDir(), "saves"))
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{
		Build: gamebuild.Options{
			StageID:  "stage.world_grove",
			LocaleID: "locale.ko",
		},
		Store: store,
	})
	if err != nil {
		t.Fatal(err)
	}

	wantDTO := []pointDTO{
		{X: 690, Y: 150},
		{X: 840, Y: 178},
		{X: 810, Y: 276},
		{X: 708, Y: 254},
	}
	world := runtime.worldSnapshotLocked()
	wall := snapshotWallByID(t, world, "grove_rocks")
	if !reflect.DeepEqual(wall.Points, wantDTO) {
		t.Fatalf("debug polygon points = %#v, want %#v", wall.Points, wantDTO)
	}
	if wall.X != 690 || wall.Y != 150 ||
		wall.Width != 150 || wall.Height != 126 {
		t.Fatalf("polygon bounds wire fields = %#v", wall)
	}
	wall.Points[0].X = -999
	if got := snapshotWallByID(
		t,
		runtime.worldSnapshotLocked(),
		"grove_rocks",
	).Points[0].X; got != 690 {
		t.Fatalf("debug polygon aliases simulation storage: first x = %v", got)
	}

	wantView := []ebitapp.PointView{
		{X: 690, Y: 150},
		{X: 840, Y: 178},
		{X: 810, Y: 276},
		{X: 708, Y: 254},
	}
	view := runtime.View()
	renderWall := renderWallByPoints(t, view.Walls)
	if !reflect.DeepEqual(renderWall.Points, wantView) {
		t.Fatalf(
			"render polygon points = %#v, want %#v",
			renderWall.Points,
			wantView,
		)
	}
	renderWall.Points[0].X = -999
	if got := renderWallByPoints(t, runtime.View().Walls).Points[0].X; got != 690 {
		t.Fatalf("render polygon aliases simulation storage: first x = %v", got)
	}
}

func snapshotWallByID(
	t *testing.T,
	world worldSnapshotDTO,
	id string,
) wallDTO {
	t.Helper()
	for _, wall := range world.Walls {
		if wall.ID == id {
			return wall
		}
	}
	t.Fatalf("wall %q missing from %#v", id, world.Walls)
	return wallDTO{}
}

func renderWallByPoints(
	t *testing.T,
	walls []ebitapp.RectView,
) ebitapp.RectView {
	t.Helper()
	for _, wall := range walls {
		if len(wall.Points) != 0 {
			return wall
		}
	}
	t.Fatalf("polygon wall missing from %#v", walls)
	return ebitapp.RectView{}
}
