package gamebuild

import (
	"encoding/json"
	"testing"
)

func TestBuildRejectsDuplicateWallIdentity(t *testing.T) {
	t.Parallel()
	catalog := loadCatalog(t)
	raw, ok := catalog.Definition("stage.rpg_village")
	if !ok {
		t.Fatal("village stage definition missing")
	}
	var draft map[string]any
	if err := json.Unmarshal(raw, &draft); err != nil {
		t.Fatal(err)
	}
	walls, ok := draft["walls"].([]any)
	if !ok || len(walls) < 2 {
		t.Fatalf("unexpected wall data: %#v", draft["walls"])
	}
	first, ok := walls[0].(map[string]any)
	if !ok {
		t.Fatalf("unexpected first wall: %#v", walls[0])
	}
	second, ok := walls[1].(map[string]any)
	if !ok {
		t.Fatalf("unexpected second wall: %#v", walls[1])
	}
	second["id"] = first["id"]
	mutatedRaw, err := json.Marshal(draft)
	if err != nil {
		t.Fatal(err)
	}
	mutated, err := catalog.WithDefinition(
		"stage.rpg_village",
		mutatedRaw,
	)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Build(mutated, Options{}); err == nil {
		t.Fatal("duplicate wall ID was accepted")
	}
}
