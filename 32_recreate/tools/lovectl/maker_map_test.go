package main

import (
	"bytes"
	"encoding/xml"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func stringPointer(value string) *string {
	return &value
}

func TestPatchMakerMapXMLUpdatesOneSemanticObjectDeterministically(
	t *testing.T,
) {
	t.Parallel()
	source := []byte(`<?xml version="1.0" encoding="UTF-8"?>
<map version="1.10" tiledversion="1.11" width="10" height="10">
 <objectgroup id="1" name="Objects">
  <object id="7" name="gate" class="trigger" x="10" y="20" width="30" height="40">
   <properties>
    <property name="actor_tag" value="player"/>
    <property name="actions" value="[{&quot;type&quot;:&quot;heal&quot;,&quot;amount&quot;:1}]"/>
   </properties>
  </object>
  <object id="8" name="exit" class="portal" x="1" y="2" width="3" height="4">
   <properties>
    <property name="target_stage" value="stage.other"/>
    <property name="target_spawn" value="entry"/>
   </properties>
  </object>
 </objectgroup>
</map>`)
	x := 25.5
	width := 64.0
	update := makerMapUpdateRequest{
		ObjectID: 7,
		Class:    "trigger",
		X:        &x,
		Width:    &width,
		Properties: map[string]*string{
			"actions": stringPointer(
				`[{"type":"show_notice","text":"Ready"}]`,
			),
			"actor_tag": nil,
			"condition": stringPointer(
				`{"type":"flag","name":"gate.open"}`,
			),
			"pages": stringPointer(
				`[{"id":"open","actions":[{"type":"emit","name":"gate.entered"}]}]`,
			),
		},
	}
	first, err := patchMakerMapXML(source, update)
	if err != nil {
		t.Fatal(err)
	}
	second, err := patchMakerMapXML(source, update)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(first, second) {
		t.Fatal("identical map edits are not deterministic")
	}
	if !bytes.Contains(first, []byte(`tiledversion="1.11"`)) {
		t.Fatal("map-level attributes were not preserved")
	}

	var document tmxMap
	if err := xml.Unmarshal(first, &document); err != nil {
		t.Fatal(err)
	}
	objects := document.ObjectGroups[0].Objects
	if objects[0].X != x || objects[0].Width != width ||
		objects[0].Y != 20 || objects[0].Height != 40 {
		t.Fatalf("updated geometry = %#v", objects[0])
	}
	properties, err := makeProperties(
		objects[0].Properties,
		"updated trigger",
	)
	if err != nil {
		t.Fatal(err)
	}
	if _, exists := properties["actor_tag"]; exists {
		t.Fatal("deleted actor_tag property remains")
	}
	if got := propertyValue(properties["actions"]); got !=
		`[{"type":"show_notice","text":"Ready"}]` {
		t.Fatalf("actions = %q", got)
	}
	if got := propertyValue(properties["condition"]); got !=
		`{"type":"flag","name":"gate.open"}` {
		t.Fatalf("condition = %q", got)
	}
	if got := propertyValue(properties["pages"]); got !=
		`[{"id":"open","actions":[{"type":"emit","name":"gate.entered"}]}]` {
		t.Fatalf("pages = %q", got)
	}
	if objects[1].X != 1 ||
		propertyValue(objects[1].Properties.Items[0]) != "stage.other" {
		t.Fatalf("unrelated portal changed: %#v", objects[1])
	}
}

func TestPatchMakerMapXMLRejectsWrongClassAndProperty(t *testing.T) {
	t.Parallel()
	source := []byte(
		`<map><objectgroup><object id="1" class="spawn"/></objectgroup></map>`,
	)
	if _, err := patchMakerMapXML(source, makerMapUpdateRequest{
		ObjectID: 1,
		Class:    "trigger",
	}); err == nil || !strings.Contains(err.Error(), "was not found") {
		t.Fatalf("wrong class error = %v", err)
	}
	if _, err := patchMakerMapXML(source, makerMapUpdateRequest{
		ObjectID: 1,
		Class:    "spawn",
		Properties: map[string]*string{
			"target_stage": stringPointer("stage.other"),
		},
	}); err == nil || !strings.Contains(err.Error(), "does not allow") {
		t.Fatalf("wrong property error = %v", err)
	}
}

func TestPatchMakerMapXMLUpdatesRootWorldPagesWithoutTouchingNestedProperties(
	t *testing.T,
) {
	t.Parallel()
	source := []byte(`<?xml version="1.0" encoding="UTF-8"?>
<map version="1.10" width="10" height="10">
 <properties>
  <property name="stage_id" value="stage.test"/>
  <property name="world_pages" value="[{&quot;id&quot;:&quot;day&quot;}]"/>
 </properties>
 <tileset firstgid="1" name="terrain">
  <properties>
   <property name="world_pages" value="tileset-value"/>
  </properties>
 </tileset>
</map>`)
	worldPages := `[{"id":"night","condition":{"type":"time_between","start":"18:00","finish":"06:00"}}]`
	patched, err := patchMakerMapXML(source, makerMapUpdateRequest{
		ObjectID: 0,
		Class:    "map",
		Properties: map[string]*string{
			"world_pages": &worldPages,
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	var document tmxMap
	if err := xml.Unmarshal(patched, &document); err != nil {
		t.Fatal(err)
	}
	properties, err := makeProperties(document.Properties, "map")
	if err != nil {
		t.Fatal(err)
	}
	if got := propertyValue(properties["stage_id"]); got != "stage.test" {
		t.Fatalf("stage_id = %q", got)
	}
	if got := propertyValue(properties["world_pages"]); got != worldPages {
		t.Fatalf("world_pages = %q", got)
	}
	if got := propertyValue(
		document.Tilesets[0].Properties.Items[0],
	); got != "tileset-value" {
		t.Fatalf("nested world_pages = %q", got)
	}
}

func TestPatchMakerMapXMLAddsAndDeletesRootWorldPages(t *testing.T) {
	t.Parallel()
	source := []byte(
		`<map width="10" height="10"><tileset name="terrain"/></map>`,
	)
	worldPages := `[{"id":"day"}]`
	added, err := patchMakerMapXML(source, makerMapUpdateRequest{
		ObjectID: 0,
		Class:    "map",
		Properties: map[string]*string{
			"world_pages": &worldPages,
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(added, []byte(`name="world_pages"`)) {
		t.Fatalf("world_pages was not added:\n%s", added)
	}
	deleted, err := patchMakerMapXML(added, makerMapUpdateRequest{
		ObjectID: 0,
		Class:    "map",
		Properties: map[string]*string{
			"world_pages": nil,
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(deleted, []byte(`name="world_pages"`)) {
		t.Fatalf("world_pages was not deleted:\n%s", deleted)
	}
}

func TestValidateMakerMapRootUpdateRejectsObjectFields(t *testing.T) {
	t.Parallel()
	x := 10.0
	for _, update := range []makerMapUpdateRequest{
		{ObjectID: 1, Class: "map"},
		{ObjectID: 0, Class: "map", X: &x},
		{
			ObjectID: 0,
			Class:    "map",
			Properties: map[string]*string{
				"stage_id": stringPointer("stage.other"),
			},
		},
	} {
		if err := validateMakerMapUpdate(update); err == nil {
			t.Fatalf("accepted invalid map root update: %#v", update)
		}
	}
}

func TestReadMakerMapOnlyPublishesEditableSemanticObjects(t *testing.T) {
	t.Parallel()
	project := t.TempDir()
	mapDirectory := filepath.Join(project, "game", "maps")
	if err := os.MkdirAll(mapDirectory, 0o755); err != nil {
		t.Fatal(err)
	}
	source := `<?xml version="1.0"?>
<map width="10" height="10">
 <properties>
  <property name="stage_id" value="stage.sample"/>
  <property name="world_pages" value="[{&quot;id&quot;:&quot;night&quot;}]"/>
 </properties>
 <objectgroup>
  <object id="1" name="hero" class="spawn" x="10" y="20">
   <properties><property name="actor" value="actor.hero"/></properties>
  </object>
  <object id="2" name="wall" class="wall" x="0" y="0" width="32" height="32"/>
  <object id="3" name="door" class="portal" x="40" y="50" width="20" height="10">
   <properties>
    <property name="target_stage" value="stage.home"/>
    <property name="target_spawn" value="entry"/>
   </properties>
  </object>
 </objectgroup>
</map>`
	path := filepath.Join(mapDirectory, "sample.tmx")
	if err := os.WriteFile(path, []byte(source), 0o644); err != nil {
		t.Fatal(err)
	}
	result, err := readMakerMap(project, "game/maps/sample.tmx")
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Objects) != 2 ||
		result.Objects[0].Class != "spawn" ||
		result.Objects[1].Class != "portal" ||
		result.Objects[1].Properties["target_stage"] != "stage.home" {
		t.Fatalf("map result = %#v", result)
	}
	if len(result.Properties) != 1 ||
		result.Properties["world_pages"] != `[{"id":"night"}]` {
		t.Fatalf("map properties = %#v", result.Properties)
	}
	if result.Revision != makerRevision([]byte(source)) {
		t.Fatalf("revision = %q", result.Revision)
	}
}
