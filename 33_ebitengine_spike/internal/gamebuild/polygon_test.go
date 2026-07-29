package gamebuild

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func TestBuildPreservesExactPolygonPortalGeometry(t *testing.T) {
	t.Parallel()
	catalog := loadCatalog(t)
	raw, found := catalog.Definition("stage.village")
	if !found {
		t.Fatal("stage.village is missing")
	}
	var draft map[string]any
	if err := json.Unmarshal(raw, &draft); err != nil {
		t.Fatal(err)
	}
	portals := draft["portals"].([]any)
	portal := portals[0].(map[string]any)
	portal["shape"] = map[string]any{
		"type": "polygon",
		"points": []any{
			map[string]any{"x": 920.0, "y": 220.0},
			map[string]any{"x": 960.0, "y": 270.0},
			map[string]any{"x": 920.0, "y": 320.0},
			map[string]any{"x": 900.0, "y": 270.0},
		},
	}
	updated, err := json.Marshal(draft)
	if err != nil {
		t.Fatal(err)
	}
	catalog, err = catalog.WithDefinition("stage.village", updated)
	if err != nil {
		t.Fatal(err)
	}
	result, err := Build(catalog, Options{
		StageID:  "stage.village",
		SpawnID:  "default",
		LocaleID: "locale.ko",
	})
	if err != nil {
		t.Fatal(err)
	}
	got := result.Stage.Portals[0]
	wantPoints := []sim.Vec{
		{X: pixels(920), Y: pixels(220)},
		{X: pixels(960), Y: pixels(270)},
		{X: pixels(920), Y: pixels(320)},
		{X: pixels(900), Y: pixels(270)},
	}
	if !reflect.DeepEqual(got.Points, wantPoints) {
		t.Fatalf("portal points = %#v, want %#v", got.Points, wantPoints)
	}
	if want := polygonBounds(wantPoints); got.Rect != want {
		t.Fatalf("portal bounds = %#v, want %#v", got.Rect, want)
	}
	validation, err := ValidateDefinition(catalog, "stage.village")
	if err != nil {
		t.Fatal(err)
	}
	for _, warning := range validation.Warnings {
		if strings.Contains(warning, `stage field "portals" is not executed`) {
			t.Fatalf("executed polygon portal reported stale warning: %q", warning)
		}
	}
}

func TestBuildCampaignWorldStagesPreservesPolygonWalls(t *testing.T) {
	t.Parallel()
	tests := []struct {
		stageID string
		walls   map[string][]sim.Vec
	}{
		{
			stageID: "stage.world_hub",
			walls: map[string][]sim.Vec{
				"rotated_ruin": {
					{X: pixels(470), Y: pixels(170)},
					{X: pixels(634.2073904691416), Y: pixels(213.99923766742853)},
					{X: pixels(623.3369905748357), Y: pixels(254.5681223715694)},
					{X: pixels(459.1296001056941), Y: pixels(210.56888470414088)},
				},
				"stone_garden": {
					{X: pixels(610), Y: pixels(380)},
					{X: pixels(765), Y: pixels(380)},
					{X: pixels(800), Y: pixels(458)},
					{X: pixels(652), Y: pixels(492)},
				},
			},
		},
		{
			stageID: "stage.world_grove",
			walls: map[string][]sim.Vec{
				"grove_rocks": {
					{X: pixels(690), Y: pixels(150)},
					{X: pixels(840), Y: pixels(178)},
					{X: pixels(810), Y: pixels(276)},
					{X: pixels(708), Y: pixels(254)},
				},
			},
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.stageID, func(t *testing.T) {
			t.Parallel()
			result, err := Build(
				loadCatalog(t),
				Options{StageID: test.stageID},
			)
			if err != nil {
				t.Fatal(err)
			}
			if _, err := sim.New(result.Config); err != nil {
				t.Fatalf("translated polygon stage is not runnable: %v", err)
			}
			if test.stageID == "stage.world_hub" {
				// This spawn used to sit inside stone_garden at y=430.
				// Keeping the source-authored fix here prevents exact polygon
				// collision from being weakened to accommodate invalid data.
				found := false
				for _, entity := range result.Config.Entities {
					if entity.ID != "enemy.slime.2" {
						continue
					}
					found = true
					if entity.Position != (sim.Vec{
						X: pixels(760),
						Y: pixels(340),
					}) {
						t.Fatalf(
							"corrected slime spawn = %#v",
							entity.Position,
						)
					}
				}
				if !found {
					t.Fatal("corrected slime spawn is missing")
				}
			}
			for id, expected := range test.walls {
				wall, present := findWall(result.Config.Walls, id)
				if !present {
					t.Fatalf("wall %q missing from %#v", id, result.Config.Walls)
				}
				if !reflect.DeepEqual(wall.Points, expected) {
					t.Fatalf(
						"wall %q points = %#v, want %#v",
						id,
						wall.Points,
						expected,
					)
				}
				if got := polygonBounds(expected); wall.Rect != got {
					t.Fatalf(
						"wall %q bounds = %#v, want %#v",
						id,
						wall.Rect,
						got,
					)
				}
			}
		})
	}
}

func TestConvertWallRejectsMalformedPolygons(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name   string
		points []shapePoint
	}{
		{
			name: "too few",
			points: []shapePoint{
				{X: 10, Y: 10},
				{X: 20, Y: 20},
			},
		},
		{
			name: "concave",
			points: []shapePoint{
				{X: 10, Y: 10},
				{X: 40, Y: 10},
				{X: 25, Y: 20},
				{X: 40, Y: 40},
				{X: 10, Y: 40},
			},
		},
		{
			name: "self intersecting",
			points: []shapePoint{
				{X: 10, Y: 10},
				{X: 40, Y: 40},
				{X: 10, Y: 40},
				{X: 40, Y: 10},
			},
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			_, err := convertWall("stage.test", stageWall{
				ID: "malformed",
				Shape: shapeRect{
					Type:   "polygon",
					Points: test.points,
				},
			})
			if err == nil {
				t.Fatal("malformed polygon was accepted")
			}
		})
	}
}

func findWall(walls []sim.Wall, id string) (sim.Wall, bool) {
	for _, wall := range walls {
		if wall.ID == id {
			return wall, true
		}
	}
	return sim.Wall{}, false
}

func polygonBounds(points []sim.Vec) sim.Rect {
	result := sim.Rect{
		MinX: points[0].X,
		MinY: points[0].Y,
		MaxX: points[0].X,
		MaxY: points[0].Y,
	}
	for _, point := range points[1:] {
		result.MinX = min(result.MinX, point.X)
		result.MinY = min(result.MinY, point.Y)
		result.MaxX = max(result.MaxX, point.X)
		result.MaxY = max(result.MaxY, point.Y)
	}
	return result
}
