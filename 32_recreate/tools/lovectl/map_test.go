package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const validTMX = `<?xml version="1.0" encoding="UTF-8"?>
<map orientation="orthogonal" renderorder="right-down" width="2" height="1" tilewidth="32" tileheight="32" infinite="0">
 <properties>
  <property name="stage_id" value="stage.test_map"/>
  <property name="display_name" value="Test Map"/>
 </properties>
 <tileset firstgid="1" name="tiles" tilewidth="32" tileheight="32" tilecount="4" columns="2">
  <properties><property name="asset" value="image.tiles"/></properties>
  <image source="tiles.png" width="64" height="64"/>
 </tileset>
 <layer id="1" name="Ground" width="2" height="1">
  <data encoding="csv">1,4</data>
 </layer>
 <objectgroup id="2" name="Objects">
  <object id="1" name="player" class="spawn" x="8" y="9">
   <properties><property name="actor" value="actor.hero"/></properties>
   <point/>
  </object>
  <object id="2" name="rotated" class="wall" x="20" y="10" width="30" height="10" rotation="90"/>
  <object id="3" name="heal" class="trigger" x="0" y="0" width="20" height="20">
   <properties>
    <property name="actions" value="[{&quot;type&quot;:&quot;heal&quot;,&quot;amount&quot;:5}]"/>
   </properties>
  </object>
 </objectgroup>
</map>`

func writeTMXFixture(t *testing.T, contents string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "map.tmx")
	if err := os.WriteFile(path, []byte(contents), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestParseTMXCanonicalObjects(t *testing.T) {
	path := writeTMXFixture(t, validTMX)
	stage, err := parseTMX(path, "game/maps/map.tmx")
	if err != nil {
		t.Fatal(err)
	}
	if stage.ID != "stage.test_map" || stage.Width != 64 || stage.Height != 32 {
		t.Fatalf("unexpected stage: %#v", stage)
	}
	if len(stage.Layers) != 1 || len(stage.Layers[0].Data) != 2 {
		t.Fatalf("unexpected tile layers: %#v", stage.Layers)
	}
	if len(stage.Spawns) != 1 ||
		stage.Spawns[0].X != 8 ||
		stage.Spawns[0].Y != 9 {
		t.Fatalf("unexpected point spawn: %#v", stage.Spawns)
	}
	if len(stage.Walls) != 1 ||
		stage.Walls[0].Shape.Type != "polygon" ||
		len(stage.Walls[0].Shape.Points) != 4 {
		t.Fatalf("rotated rectangle was not canonicalized: %#v", stage.Walls)
	}
	if len(stage.Triggers) != 1 || len(stage.Triggers[0].Actions) != 1 {
		t.Fatalf("unexpected triggers: %#v", stage.Triggers)
	}
}

func TestEncodeStageKeepsJSONNumbersNumeric(t *testing.T) {
	path := writeTMXFixture(t, validTMX)
	stage, err := parseTMX(path, "game/maps/map.tmx")
	if err != nil {
		t.Fatal(err)
	}
	encoded := string(encodeStage(stage))
	if !strings.Contains(encoded, "amount = 5") {
		t.Fatalf("JSON number was not emitted as Lua number:\n%s", encoded)
	}
	if strings.Contains(encoded, `amount = "5"`) {
		t.Fatalf("JSON number was quoted:\n%s", encoded)
	}
	if second := string(encodeStage(stage)); second != encoded {
		t.Fatal("stage encoding is not deterministic")
	}
}

func TestParseTMXRejectsUnknownProperties(t *testing.T) {
	invalid := strings.Replace(
		validTMX,
		`<property name="stage_id" value="stage.test_map"/>`,
		`<property name="stage_id" value="stage.test_map"/>
  <property name="stag_id" value="typo"/>`,
		1,
	)
	path := writeTMXFixture(t, invalid)
	_, err := parseTMX(path, "map.tmx")
	if err == nil || !strings.Contains(err.Error(), "stag_id") {
		t.Fatalf("expected strict property error, got %v", err)
	}
}

func TestParseTMXRejectsUnsupportedObjectClass(t *testing.T) {
	invalid := strings.Replace(
		validTMX,
		`class="spawn"`,
		`class="mystery"`,
		1,
	)
	path := writeTMXFixture(t, invalid)
	_, err := parseTMX(path, "map.tmx")
	if err == nil || !strings.Contains(err.Error(), "unsupported class") {
		t.Fatalf("expected class error, got %v", err)
	}
}

func TestParseTMXRejectsGIDOutsideTilesets(t *testing.T) {
	invalid := strings.Replace(
		validTMX,
		`<data encoding="csv">1,4</data>`,
		`<data encoding="csv">1,5</data>`,
		1,
	)
	path := writeTMXFixture(t, invalid)
	_, err := parseTMX(path, "map.tmx")
	if err == nil || !strings.Contains(err.Error(), "outside every tileset") {
		t.Fatalf("expected gid range error, got %v", err)
	}
}

func TestParseTMXRejectsNestedGroups(t *testing.T) {
	invalid := strings.Replace(
		validTMX,
		`</map>`,
		` <group id="9" name="Nested"/>
</map>`,
		1,
	)
	path := writeTMXFixture(t, invalid)
	_, err := parseTMX(path, "map.tmx")
	if err == nil || !strings.Contains(err.Error(), "nested groups") {
		t.Fatalf("expected nested group error, got %v", err)
	}
}
