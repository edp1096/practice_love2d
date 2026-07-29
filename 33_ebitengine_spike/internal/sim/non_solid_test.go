package sim

import (
	"reflect"
	"strings"
	"testing"
)

func TestNonSolidEntitiesMayOverlapWallsAcrossLifecycle(t *testing.T) {
	t.Parallel()

	config := baseConfig()
	config.Walls = []Wall{{
		ID: "collision",
		Rect: Rect{
			MinX: Pixels(100),
			MinY: Pixels(20),
			MaxX: Pixels(110),
			MaxY: Pixels(100),
		},
	}}
	visual := previewEntity("visual", Pixels(105), Pixels(60))
	wallEditVisual := previewEntity(
		"wall-edit-visual",
		Pixels(150),
		Pixels(60),
	)
	config.Entities = append(config.Entities, visual, wallEditVisual)
	simulation, err := New(config)
	if err != nil {
		t.Fatalf("New() rejected non-solid visual overlap: %v", err)
	}

	dynamic := previewEntity("dynamic", Pixels(105), Pixels(75))
	if err := simulation.SpawnEntity(dynamic); err != nil {
		t.Fatalf("SpawnEntity() rejected non-solid overlap: %v", err)
	}
	session := simulation.SaveSession()
	for index := range session.Entities {
		if session.Entities[index].ID == dynamic.ID {
			session.Entities[index].Position = Vec{
				X: Pixels(105),
				Y: Pixels(85),
			}
		}
	}
	if err := simulation.LoadSession(session); err != nil {
		t.Fatalf("LoadSession() rejected non-solid overlap: %v", err)
	}

	replacement := Rect{
		MinX: Pixels(145),
		MinY: Pixels(20),
		MaxX: Pixels(155),
		MaxY: Pixels(100),
	}
	if err := simulation.SetWall("collision", replacement); err != nil {
		t.Fatalf("SetWall() rejected non-solid overlap: %v", err)
	}
}

func TestSolidEntitiesStillRejectWallOverlapTransactionally(t *testing.T) {
	t.Parallel()

	config := baseConfig()
	config.Walls = []Wall{{
		ID: "collision",
		Rect: Rect{
			MinX: Pixels(100),
			MinY: Pixels(20),
			MaxX: Pixels(110),
			MaxY: Pixels(100),
		},
	}}
	simulation := mustNew(t, config)
	before := simulation.SaveSession()
	solid := previewEntity("solid", Pixels(105), Pixels(60))
	solid.Body.Solid = true
	if err := simulation.SpawnEntity(solid); err == nil ||
		!strings.Contains(err.Error(), "overlaps wall") {
		t.Fatalf("solid SpawnEntity() error = %v", err)
	}
	if after := simulation.SaveSession(); !reflect.DeepEqual(after, before) {
		t.Fatal("rejected solid overlap mutated simulation")
	}
}
