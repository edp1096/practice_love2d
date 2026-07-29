package main

import (
	"bytes"
	"encoding/json"
	"encoding/xml"
	"errors"
	"flag"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"unicode"
)

type tmxProperty struct {
	Name  string `xml:"name,attr"`
	Type  string `xml:"type,attr"`
	Value string `xml:"value,attr"`
	Text  string `xml:",chardata"`
}

type tmxProperties struct {
	Items []tmxProperty `xml:"property"`
}

type tmxImage struct {
	Source string `xml:"source,attr"`
	Width  int    `xml:"width,attr"`
	Height int    `xml:"height,attr"`
}

type tmxTileset struct {
	FirstGID   uint32        `xml:"firstgid,attr"`
	Source     string        `xml:"source,attr"`
	Name       string        `xml:"name,attr"`
	TileWidth  int           `xml:"tilewidth,attr"`
	TileHeight int           `xml:"tileheight,attr"`
	TileCount  int           `xml:"tilecount,attr"`
	Columns    int           `xml:"columns,attr"`
	Properties tmxProperties `xml:"properties"`
	Image      tmxImage      `xml:"image"`
}

type tmxData struct {
	Encoding    string `xml:"encoding,attr"`
	Compression string `xml:"compression,attr"`
	Value       string `xml:",chardata"`
}

type tmxLayer struct {
	ID         int           `xml:"id,attr"`
	Name       string        `xml:"name,attr"`
	Class      string        `xml:"class,attr"`
	Width      int           `xml:"width,attr"`
	Height     int           `xml:"height,attr"`
	Visible    *int          `xml:"visible,attr"`
	Opacity    *float64      `xml:"opacity,attr"`
	OffsetX    float64       `xml:"offsetx,attr"`
	OffsetY    float64       `xml:"offsety,attr"`
	Properties tmxProperties `xml:"properties"`
	Data       tmxData       `xml:"data"`
}

type tmxPolygon struct {
	Points string `xml:"points,attr"`
}

type tmxPoint struct{}

type tmxEllipse struct{}

type tmxObject struct {
	ID         int           `xml:"id,attr"`
	Name       string        `xml:"name,attr"`
	Class      string        `xml:"class,attr"`
	Type       string        `xml:"type,attr"`
	X          float64       `xml:"x,attr"`
	Y          float64       `xml:"y,attr"`
	Width      float64       `xml:"width,attr"`
	Height     float64       `xml:"height,attr"`
	Rotation   float64       `xml:"rotation,attr"`
	GID        uint32        `xml:"gid,attr"`
	Template   string        `xml:"template,attr"`
	Visible    *int          `xml:"visible,attr"`
	Properties tmxProperties `xml:"properties"`
	Polygon    *tmxPolygon   `xml:"polygon"`
	Point      *tmxPoint     `xml:"point"`
	Ellipse    *tmxEllipse   `xml:"ellipse"`
}

type tmxObjectGroup struct {
	ID         int           `xml:"id,attr"`
	Name       string        `xml:"name,attr"`
	Class      string        `xml:"class,attr"`
	Properties tmxProperties `xml:"properties"`
	Objects    []tmxObject   `xml:"object"`
}

type tmxMap struct {
	XMLName         xml.Name         `xml:"map"`
	Orientation     string           `xml:"orientation,attr"`
	RenderOrder     string           `xml:"renderorder,attr"`
	Infinite        int              `xml:"infinite,attr"`
	Width           int              `xml:"width,attr"`
	Height          int              `xml:"height,attr"`
	TileWidth       int              `xml:"tilewidth,attr"`
	TileHeight      int              `xml:"tileheight,attr"`
	BackgroundColor string           `xml:"backgroundcolor,attr"`
	Properties      tmxProperties    `xml:"properties"`
	Tilesets        []tmxTileset     `xml:"tileset"`
	Layers          []tmxLayer       `xml:"layer"`
	ObjectGroups    []tmxObjectGroup `xml:"objectgroup"`
	Groups          []struct{}       `xml:"group"`
	ImageLayers     []struct{}       `xml:"imagelayer"`
}

type stageShape struct {
	Type   string
	X      float64
	Y      float64
	Width  float64
	Height float64
	Points []stagePoint
}

type stagePoint struct {
	X float64
	Y float64
}

type stageSpawn struct {
	ID    string
	Actor string
	Tags  []string
	X     float64
	Y     float64
}

type stageWall struct {
	ID    string
	Shape stageShape
}

type stageSpawnPoint struct {
	ID string
	X  float64
	Y  float64
}

type stagePortal struct {
	ID          string
	Shape       stageShape
	ActorTag    string
	TargetStage string
	TargetSpawn string
	Cooldown    float64
}

type stageTrigger struct {
	ID        string
	Shape     stageShape
	ActorTag  string
	Once      bool
	Cooldown  float64
	Condition any
	Actions   []any
}

type stageTileset struct {
	ID         string
	FirstGID   uint32
	TileCount  int
	Columns    int
	TileWidth  int
	TileHeight int
	Asset      string
}

type stageTileLayer struct {
	ID      string
	Name    string
	Width   int
	Height  int
	Visible bool
	Opacity float64
	OffsetX float64
	OffsetY float64
	Data    []uint32
}

type compiledStage struct {
	ID             string
	Name           string
	NameKey        string
	Mode           string
	Width          int
	Height         int
	Background     []float64
	CameraWidth    float64
	CameraHeight   float64
	Source         string
	TileWidth      int
	TileHeight     int
	Tilesets       []stageTileset
	Layers         []stageTileLayer
	Spawns         []stageSpawn
	Walls          []stageWall
	SpawnPoints    []stageSpawnPoint
	Portals        []stagePortal
	Triggers       []stageTrigger
	SourceObjectCt int
}

var contentIDPattern = regexp.MustCompile(
	`^[a-z][a-z0-9_]*\.[a-z][a-z0-9_.-]*$`,
)

func propertyValue(property tmxProperty) string {
	if property.Value != "" {
		return property.Value
	}
	return strings.TrimSpace(property.Text)
}

func makeProperties(properties tmxProperties, context string) (map[string]tmxProperty, error) {
	result := make(map[string]tmxProperty, len(properties.Items))
	for _, property := range properties.Items {
		if property.Name == "" {
			return nil, fmt.Errorf("%s has a property without a name", context)
		}
		if _, exists := result[property.Name]; exists {
			return nil, fmt.Errorf(
				"%s repeats property %q",
				context,
				property.Name,
			)
		}
		result[property.Name] = property
	}
	return result, nil
}

func rejectUnknownProperties(
	properties map[string]tmxProperty,
	allowed []string,
	context string,
) error {
	known := make(map[string]bool, len(allowed))
	for _, name := range allowed {
		known[name] = true
	}
	var unknown []string
	for name := range properties {
		if !known[name] {
			unknown = append(unknown, name)
		}
	}
	sort.Strings(unknown)
	if len(unknown) != 0 {
		return fmt.Errorf(
			"%s uses unknown properties: %s",
			context,
			strings.Join(unknown, ", "),
		)
	}
	return nil
}

func stringProperty(
	properties map[string]tmxProperty,
	name string,
	required bool,
	context string,
) (string, error) {
	property, exists := properties[name]
	if !exists || propertyValue(property) == "" {
		if required {
			return "", fmt.Errorf("%s requires property %q", context, name)
		}
		return "", nil
	}
	return propertyValue(property), nil
}

func floatProperty(
	properties map[string]tmxProperty,
	name string,
	fallback float64,
	context string,
) (float64, error) {
	property, exists := properties[name]
	if !exists || propertyValue(property) == "" {
		return fallback, nil
	}
	value, err := strconv.ParseFloat(propertyValue(property), 64)
	if err != nil || math.IsNaN(value) || math.IsInf(value, 0) {
		return 0, fmt.Errorf(
			"%s property %q must be a finite number",
			context,
			name,
		)
	}
	return value, nil
}

func boolProperty(
	properties map[string]tmxProperty,
	name string,
	fallback bool,
	context string,
) (bool, error) {
	property, exists := properties[name]
	if !exists || propertyValue(property) == "" {
		return fallback, nil
	}
	value, err := strconv.ParseBool(propertyValue(property))
	if err != nil {
		return false, fmt.Errorf(
			"%s property %q must be true or false",
			context,
			name,
		)
	}
	return value, nil
}

func jsonProperty(
	properties map[string]tmxProperty,
	name string,
	required bool,
	context string,
) (any, error) {
	text, err := stringProperty(properties, name, required, context)
	if err != nil || text == "" {
		return nil, err
	}
	var value any
	decoder := json.NewDecoder(strings.NewReader(text))
	decoder.UseNumber()
	if err := decoder.Decode(&value); err != nil {
		return nil, fmt.Errorf(
			"%s property %q is not valid JSON: %w",
			context,
			name,
			err,
		)
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		return nil, fmt.Errorf(
			"%s property %q contains trailing JSON",
			context,
			name,
		)
	}
	return value, nil
}

func parseColor(value string) ([]float64, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return []float64{0.07, 0.085, 0.12, 1}, nil
	}
	if !strings.HasPrefix(value, "#") ||
		(len(value) != 7 && len(value) != 9) {
		return nil, fmt.Errorf("color %q must be #RRGGBB or #AARRGGBB", value)
	}
	hex := strings.TrimPrefix(value, "#")
	alpha := uint64(255)
	if len(hex) == 8 {
		parsedAlpha, err := strconv.ParseUint(hex[:2], 16, 8)
		if err != nil {
			return nil, fmt.Errorf("invalid color %q", value)
		}
		alpha = parsedAlpha
		hex = hex[2:]
	}
	rgb, err := strconv.ParseUint(hex, 16, 24)
	if err != nil {
		return nil, fmt.Errorf("invalid color %q", value)
	}
	return []float64{
		float64((rgb>>16)&255) / 255,
		float64((rgb>>8)&255) / 255,
		float64(rgb&255) / 255,
		float64(alpha) / 255,
	}, nil
}

func parseCSV(data tmxData, expected int, context string) ([]uint32, error) {
	if data.Encoding != "csv" {
		return nil, fmt.Errorf(
			"%s uses encoding %q; canonical maps require CSV",
			context,
			data.Encoding,
		)
	}
	if data.Compression != "" {
		return nil, fmt.Errorf("%s must not compress CSV data", context)
	}
	tokens := strings.Split(data.Value, ",")
	result := make([]uint32, 0, expected)
	for _, token := range tokens {
		token = strings.TrimSpace(token)
		if token == "" {
			continue
		}
		value, err := strconv.ParseUint(token, 10, 32)
		if err != nil {
			return nil, fmt.Errorf(
				"%s contains invalid gid %q",
				context,
				token,
			)
		}
		result = append(result, uint32(value))
	}
	if len(result) != expected {
		return nil, fmt.Errorf(
			"%s contains %d gids, expected %d",
			context,
			len(result),
			expected,
		)
	}
	return result, nil
}

func sanitizeID(value string) string {
	var builder strings.Builder
	lastUnderscore := false
	for _, character := range strings.ToLower(value) {
		valid := unicode.IsLetter(character) ||
			unicode.IsDigit(character) ||
			character == '_' ||
			character == '-' ||
			character == '.'
		if valid {
			builder.WriteRune(character)
			lastUnderscore = false
		} else if !lastUnderscore {
			builder.WriteByte('_')
			lastUnderscore = true
		}
	}
	return strings.Trim(builder.String(), "_")
}

func rotatePoint(x, y, degrees float64) stagePoint {
	radians := degrees * math.Pi / 180
	cosine := math.Cos(radians)
	sine := math.Sin(radians)
	return stagePoint{
		X: x*cosine - y*sine,
		Y: x*sine + y*cosine,
	}
}

func parsePolygon(points string, object tmxObject, context string) ([]stagePoint, error) {
	fields := strings.Fields(points)
	if len(fields) < 3 {
		return nil, fmt.Errorf("%s polygon requires at least 3 points", context)
	}
	result := make([]stagePoint, 0, len(fields))
	for _, field := range fields {
		parts := strings.Split(field, ",")
		if len(parts) != 2 {
			return nil, fmt.Errorf("%s has malformed point %q", context, field)
		}
		x, xErr := strconv.ParseFloat(parts[0], 64)
		y, yErr := strconv.ParseFloat(parts[1], 64)
		if xErr != nil || yErr != nil {
			return nil, fmt.Errorf("%s has malformed point %q", context, field)
		}
		point := rotatePoint(x, y, object.Rotation)
		point.X += object.X
		point.Y += object.Y
		result = append(result, point)
	}
	return result, nil
}

func shapeFromObject(object tmxObject, context string) (stageShape, error) {
	if object.Ellipse != nil {
		return stageShape{}, fmt.Errorf(
			"%s is an ellipse; use a rectangle or polygon",
			context,
		)
	}
	if object.Point != nil {
		return stageShape{}, fmt.Errorf("%s is a point and has no area", context)
	}
	if object.Polygon != nil {
		points, err := parsePolygon(object.Polygon.Points, object, context)
		if err != nil {
			return stageShape{}, err
		}
		return stageShape{Type: "polygon", Points: points}, nil
	}
	if object.Width <= 0 || object.Height <= 0 {
		return stageShape{}, fmt.Errorf(
			"%s rectangle width and height must be positive",
			context,
		)
	}
	if object.Rotation == 0 {
		return stageShape{
			Type:   "rectangle",
			X:      object.X + object.Width/2,
			Y:      object.Y + object.Height/2,
			Width:  object.Width,
			Height: object.Height,
		}, nil
	}
	corners := []stagePoint{
		{X: 0, Y: 0},
		{X: object.Width, Y: 0},
		{X: object.Width, Y: object.Height},
		{X: 0, Y: object.Height},
	}
	for index, corner := range corners {
		rotated := rotatePoint(corner.X, corner.Y, object.Rotation)
		corners[index] = stagePoint{
			X: object.X + rotated.X,
			Y: object.Y + rotated.Y,
		}
	}
	return stageShape{Type: "polygon", Points: corners}, nil
}

func objectPosition(object tmxObject) (float64, float64) {
	if object.Point != nil || object.Polygon != nil {
		return object.X, object.Y
	}
	return object.X + object.Width/2, object.Y + object.Height/2
}

func objectID(
	object tmxObject,
	properties map[string]tmxProperty,
	class string,
	context string,
) (string, error) {
	id, err := stringProperty(properties, "id", false, context)
	if err != nil {
		return "", err
	}
	if id == "" {
		id = object.Name
	}
	if id == "" {
		id = fmt.Sprintf("%s.%d", class, object.ID)
	}
	id = sanitizeID(id)
	if id == "" {
		return "", fmt.Errorf("%s produces an empty id", context)
	}
	return id, nil
}

func splitTags(value string) []string {
	var result []string
	seen := map[string]bool{}
	for _, item := range strings.Split(value, ",") {
		item = strings.TrimSpace(item)
		if item != "" && !seen[item] {
			seen[item] = true
			result = append(result, item)
		}
	}
	sort.Strings(result)
	return result
}

func appendObject(stage *compiledStage, object tmxObject, groupName string) error {
	class := object.Class
	if class == "" {
		class = object.Type
	}
	class = strings.ToLower(strings.TrimSpace(class))
	context := fmt.Sprintf(
		"object %d (%s/%s)",
		object.ID,
		groupName,
		class,
	)
	if object.Template != "" {
		return fmt.Errorf(
			"%s uses template %q; canonical maps require explicit objects",
			context,
			object.Template,
		)
	}
	if class == "" {
		return fmt.Errorf(
			"object %d in group %q requires a Tiled class",
			object.ID,
			groupName,
		)
	}
	if object.GID != 0 {
		return fmt.Errorf("%s is a tile object, which is not a stage object", context)
	}

	properties, err := makeProperties(object.Properties, context)
	if err != nil {
		return err
	}
	id, err := objectID(object, properties, class, context)
	if err != nil {
		return err
	}

	switch class {
	case "spawn":
		if err := rejectUnknownProperties(
			properties,
			[]string{"id", "actor", "tags"},
			context,
		); err != nil {
			return err
		}
		actor, err := stringProperty(properties, "actor", true, context)
		if err != nil {
			return err
		}
		tagsText, err := stringProperty(properties, "tags", false, context)
		if err != nil {
			return err
		}
		x, y := objectPosition(object)
		stage.Spawns = append(stage.Spawns, stageSpawn{
			ID: id, Actor: actor, Tags: splitTags(tagsText), X: x, Y: y,
		})
	case "spawn_point":
		if err := rejectUnknownProperties(
			properties,
			[]string{"id"},
			context,
		); err != nil {
			return err
		}
		x, y := objectPosition(object)
		stage.SpawnPoints = append(stage.SpawnPoints, stageSpawnPoint{
			ID: id, X: x, Y: y,
		})
	case "wall":
		if err := rejectUnknownProperties(
			properties,
			[]string{"id"},
			context,
		); err != nil {
			return err
		}
		shape, err := shapeFromObject(object, context)
		if err != nil {
			return err
		}
		stage.Walls = append(stage.Walls, stageWall{ID: id, Shape: shape})
	case "portal":
		if err := rejectUnknownProperties(
			properties,
			[]string{
				"id", "actor_tag", "target_stage",
				"target_spawn", "cooldown",
			},
			context,
		); err != nil {
			return err
		}
		shape, err := shapeFromObject(object, context)
		if err != nil {
			return err
		}
		targetStage, err := stringProperty(
			properties,
			"target_stage",
			true,
			context,
		)
		if err != nil {
			return err
		}
		targetSpawn, err := stringProperty(
			properties,
			"target_spawn",
			true,
			context,
		)
		if err != nil {
			return err
		}
		actorTag, err := stringProperty(properties, "actor_tag", false, context)
		if err != nil {
			return err
		}
		cooldown, err := floatProperty(properties, "cooldown", 0.25, context)
		if err != nil {
			return err
		}
		if cooldown < 0 {
			return fmt.Errorf("%s cooldown must not be negative", context)
		}
		stage.Portals = append(stage.Portals, stagePortal{
			ID:          id,
			Shape:       shape,
			ActorTag:    actorTag,
			TargetStage: targetStage,
			TargetSpawn: targetSpawn,
			Cooldown:    cooldown,
		})
	case "trigger":
		if err := rejectUnknownProperties(
			properties,
			[]string{
				"id", "actor_tag", "once", "cooldown",
				"condition", "actions",
			},
			context,
		); err != nil {
			return err
		}
		shape, err := shapeFromObject(object, context)
		if err != nil {
			return err
		}
		actionsValue, err := jsonProperty(
			properties,
			"actions",
			true,
			context,
		)
		if err != nil {
			return err
		}
		actions, ok := actionsValue.([]any)
		if !ok || len(actions) == 0 {
			return fmt.Errorf("%s actions must be a non-empty JSON array", context)
		}
		condition, err := jsonProperty(
			properties,
			"condition",
			false,
			context,
		)
		if err != nil {
			return err
		}
		actorTag, err := stringProperty(properties, "actor_tag", false, context)
		if err != nil {
			return err
		}
		once, err := boolProperty(properties, "once", false, context)
		if err != nil {
			return err
		}
		cooldown, err := floatProperty(properties, "cooldown", 0, context)
		if err != nil {
			return err
		}
		if cooldown < 0 {
			return fmt.Errorf("%s cooldown must not be negative", context)
		}
		stage.Triggers = append(stage.Triggers, stageTrigger{
			ID:        id,
			Shape:     shape,
			ActorTag:  actorTag,
			Once:      once,
			Cooldown:  cooldown,
			Condition: condition,
			Actions:   actions,
		})
	default:
		return fmt.Errorf("%s uses unsupported class %q", context, class)
	}
	stage.SourceObjectCt++
	return nil
}

func ensureUniqueIDs(stage compiledStage) error {
	sets := []struct {
		name string
		ids  []string
	}{
		{name: "spawn", ids: make([]string, 0, len(stage.Spawns))},
		{name: "wall", ids: make([]string, 0, len(stage.Walls))},
		{name: "spawn point", ids: make([]string, 0, len(stage.SpawnPoints))},
		{name: "portal", ids: make([]string, 0, len(stage.Portals))},
		{name: "trigger", ids: make([]string, 0, len(stage.Triggers))},
	}
	for _, value := range stage.Spawns {
		sets[0].ids = append(sets[0].ids, value.ID)
	}
	for _, value := range stage.Walls {
		sets[1].ids = append(sets[1].ids, value.ID)
	}
	for _, value := range stage.SpawnPoints {
		sets[2].ids = append(sets[2].ids, value.ID)
	}
	for _, value := range stage.Portals {
		sets[3].ids = append(sets[3].ids, value.ID)
	}
	for _, value := range stage.Triggers {
		sets[4].ids = append(sets[4].ids, value.ID)
	}
	for _, set := range sets {
		seen := map[string]bool{}
		for _, id := range set.ids {
			if seen[id] {
				return fmt.Errorf("stage %s repeats %s id %q", stage.ID, set.name, id)
			}
			seen[id] = true
		}
	}
	return nil
}

func parseTMX(path, source string) (compiledStage, error) {
	var stage compiledStage
	encoded, err := os.ReadFile(path)
	if err != nil {
		return stage, err
	}
	var document tmxMap
	if err := xml.Unmarshal(encoded, &document); err != nil {
		return stage, fmt.Errorf("%s: invalid TMX: %w", source, err)
	}
	if document.Orientation != "orthogonal" {
		return stage, fmt.Errorf(
			"%s: orientation %q is unsupported; use orthogonal",
			source,
			document.Orientation,
		)
	}
	if document.Infinite != 0 {
		return stage, fmt.Errorf("%s: infinite maps are not supported", source)
	}
	if len(document.Groups) != 0 || len(document.ImageLayers) != 0 {
		return stage, fmt.Errorf(
			"%s: nested groups and image layers are not supported",
			source,
		)
	}
	if document.Width <= 0 || document.Height <= 0 ||
		document.TileWidth <= 0 || document.TileHeight <= 0 {
		return stage, fmt.Errorf("%s: map and tile dimensions must be positive", source)
	}

	mapProperties, err := makeProperties(document.Properties, "map "+source)
	if err != nil {
		return stage, err
	}
	if err := rejectUnknownProperties(
		mapProperties,
		[]string{
			"stage_id", "display_name", "display_name_key", "mode",
			"camera_width", "camera_height", "background",
		},
		"map "+source,
	); err != nil {
		return stage, err
	}
	stage.ID, err = stringProperty(mapProperties, "stage_id", true, "map "+source)
	if err != nil {
		return stage, err
	}
	if !contentIDPattern.MatchString(stage.ID) ||
		!strings.HasPrefix(stage.ID, "stage.") {
		return stage, fmt.Errorf(
			"map %s stage_id %q must match stage.name using lowercase characters",
			source,
			stage.ID,
		)
	}
	stage.Name, err = stringProperty(
		mapProperties,
		"display_name",
		false,
		"map "+source,
	)
	if err != nil {
		return stage, err
	}
	if stage.Name == "" {
		stage.Name = stage.ID
	}
	stage.NameKey, err = stringProperty(
		mapProperties,
		"display_name_key",
		false,
		"map "+source,
	)
	if err != nil {
		return stage, err
	}
	stage.Mode, err = stringProperty(mapProperties, "mode", false, "map "+source)
	if err != nil {
		return stage, err
	}
	if stage.Mode == "" {
		stage.Mode = "topdown"
	}
	if stage.Mode != "topdown" && stage.Mode != "platformer" {
		return stage, fmt.Errorf(
			"map %s mode must be topdown or platformer",
			source,
		)
	}
	stage.Width = document.Width * document.TileWidth
	stage.Height = document.Height * document.TileHeight
	stage.CameraWidth, err = floatProperty(
		mapProperties,
		"camera_width",
		math.Min(float64(stage.Width), 960),
		"map "+source,
	)
	if err != nil {
		return stage, err
	}
	stage.CameraHeight, err = floatProperty(
		mapProperties,
		"camera_height",
		math.Min(float64(stage.Height), 540),
		"map "+source,
	)
	if err != nil {
		return stage, err
	}
	if stage.CameraWidth <= 0 || stage.CameraHeight <= 0 {
		return stage, errors.New("camera dimensions must be positive")
	}
	background := document.BackgroundColor
	if property, exists := mapProperties["background"]; exists {
		background = propertyValue(property)
	}
	stage.Background, err = parseColor(background)
	if err != nil {
		return stage, fmt.Errorf("map %s background: %w", source, err)
	}
	stage.Source = filepath.ToSlash(source)
	stage.TileWidth = document.TileWidth
	stage.TileHeight = document.TileHeight

	if len(document.Tilesets) == 0 && len(document.Layers) != 0 {
		return stage, fmt.Errorf("%s: tile layers require a tileset", source)
	}
	for index, tileset := range document.Tilesets {
		context := fmt.Sprintf("tileset %d (%s)", index+1, tileset.Name)
		if tileset.Source != "" {
			return stage, fmt.Errorf(
				"%s uses external TSX; inline it so builds are self-contained",
				context,
			)
		}
		properties, err := makeProperties(tileset.Properties, context)
		if err != nil {
			return stage, err
		}
		if err := rejectUnknownProperties(
			properties,
			[]string{"asset"},
			context,
		); err != nil {
			return stage, err
		}
		asset, err := stringProperty(properties, "asset", true, context)
		if err != nil {
			return stage, err
		}
		if tileset.FirstGID == 0 || tileset.TileCount <= 0 ||
			tileset.Columns <= 0 || tileset.TileWidth <= 0 ||
			tileset.TileHeight <= 0 {
			return stage, fmt.Errorf("%s has invalid dimensions or gid range", context)
		}
		stage.Tilesets = append(stage.Tilesets, stageTileset{
			ID:         sanitizeID(tileset.Name),
			FirstGID:   tileset.FirstGID,
			TileCount:  tileset.TileCount,
			Columns:    tileset.Columns,
			TileWidth:  tileset.TileWidth,
			TileHeight: tileset.TileHeight,
			Asset:      asset,
		})
		if stage.Tilesets[len(stage.Tilesets)-1].ID == "" {
			return stage, fmt.Errorf("%s name produces an empty id", context)
		}
	}
	sort.Slice(stage.Tilesets, func(left, right int) bool {
		return stage.Tilesets[left].FirstGID < stage.Tilesets[right].FirstGID
	})
	for index := 1; index < len(stage.Tilesets); index++ {
		previous := stage.Tilesets[index-1]
		current := stage.Tilesets[index]
		if current.FirstGID < previous.FirstGID+uint32(previous.TileCount) {
			return stage, fmt.Errorf(
				"tilesets %q and %q have overlapping gid ranges",
				previous.ID,
				current.ID,
			)
		}
	}

	layerIDs := map[string]bool{}
	for _, layer := range document.Layers {
		context := fmt.Sprintf("tile layer %d (%s)", layer.ID, layer.Name)
		properties, err := makeProperties(layer.Properties, context)
		if err != nil {
			return stage, err
		}
		if err := rejectUnknownProperties(properties, nil, context); err != nil {
			return stage, err
		}
		if layer.Width <= 0 || layer.Height <= 0 {
			return stage, fmt.Errorf("%s has invalid dimensions", context)
		}
		data, err := parseCSV(
			layer.Data,
			layer.Width*layer.Height,
			context,
		)
		if err != nil {
			return stage, err
		}
		for tileIndex, encoded := range data {
			if encoded == 0 {
				continue
			}
			if encoded&0x10000000 != 0 {
				return stage, fmt.Errorf(
					"%s tile %d uses the hexagonal rotation flag",
					context,
					tileIndex+1,
				)
			}
			gid := encoded & 0x0fffffff
			found := false
			for _, tileset := range stage.Tilesets {
				if gid >= tileset.FirstGID &&
					gid < tileset.FirstGID+uint32(tileset.TileCount) {
					found = true
					break
				}
			}
			if !found {
				return stage, fmt.Errorf(
					"%s tile %d gid %d is outside every tileset",
					context,
					tileIndex+1,
					gid,
				)
			}
		}
		id := sanitizeID(layer.Name)
		if id == "" {
			id = fmt.Sprintf("layer.%d", layer.ID)
		}
		if layerIDs[id] {
			return stage, fmt.Errorf("tile layer id %q is duplicated", id)
		}
		layerIDs[id] = true
		visible := layer.Visible == nil || *layer.Visible != 0
		opacity := 1.0
		if layer.Opacity != nil {
			opacity = *layer.Opacity
		}
		if opacity < 0 || opacity > 1 {
			return stage, fmt.Errorf("%s opacity must be between 0 and 1", context)
		}
		stage.Layers = append(stage.Layers, stageTileLayer{
			ID:      id,
			Name:    layer.Name,
			Width:   layer.Width,
			Height:  layer.Height,
			Visible: visible,
			Opacity: opacity,
			OffsetX: layer.OffsetX,
			OffsetY: layer.OffsetY,
			Data:    data,
		})
	}

	for _, group := range document.ObjectGroups {
		context := fmt.Sprintf("object group %d (%s)", group.ID, group.Name)
		properties, err := makeProperties(group.Properties, context)
		if err != nil {
			return stage, err
		}
		if err := rejectUnknownProperties(properties, nil, context); err != nil {
			return stage, err
		}
		for _, object := range group.Objects {
			if err := appendObject(&stage, object, group.Name); err != nil {
				return stage, err
			}
		}
	}
	if err := ensureUniqueIDs(stage); err != nil {
		return stage, err
	}
	return stage, nil
}

func luaQuote(value string) string {
	var builder strings.Builder
	builder.WriteByte('"')
	for _, character := range value {
		switch character {
		case '\\':
			builder.WriteString(`\\`)
		case '"':
			builder.WriteString(`\"`)
		case '\n':
			builder.WriteString(`\n`)
		case '\r':
			builder.WriteString(`\r`)
		case '\t':
			builder.WriteString(`\t`)
		default:
			if character < 32 {
				fmt.Fprintf(&builder, "\\%03d", character)
			} else {
				builder.WriteRune(character)
			}
		}
	}
	builder.WriteByte('"')
	return builder.String()
}

func luaNumber(value reflect.Value) string {
	switch value.Kind() {
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		return strconv.FormatInt(value.Int(), 10)
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
		return strconv.FormatUint(value.Uint(), 10)
	default:
		return strconv.FormatFloat(value.Float(), 'f', -1, 64)
	}
}

func simpleLuaValue(value reflect.Value) bool {
	if !value.IsValid() {
		return true
	}
	switch value.Kind() {
	case reflect.Interface, reflect.Pointer:
		if value.IsNil() {
			return true
		}
		return simpleLuaValue(value.Elem())
	case reflect.Bool, reflect.String,
		reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64,
		reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64,
		reflect.Float32, reflect.Float64:
		return true
	}
	return false
}

func writeLuaValue(builder *strings.Builder, raw any, indent int) {
	if number, ok := raw.(json.Number); ok {
		builder.WriteString(number.String())
		return
	}
	value := reflect.ValueOf(raw)
	if !value.IsValid() {
		builder.WriteString("nil")
		return
	}
	if value.Kind() == reflect.Interface || value.Kind() == reflect.Pointer {
		if value.IsNil() {
			builder.WriteString("nil")
			return
		}
		writeLuaValue(builder, value.Elem().Interface(), indent)
		return
	}
	switch value.Kind() {
	case reflect.Bool:
		if value.Bool() {
			builder.WriteString("true")
		} else {
			builder.WriteString("false")
		}
	case reflect.String:
		builder.WriteString(luaQuote(value.String()))
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64,
		reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64,
		reflect.Float32, reflect.Float64:
		builder.WriteString(luaNumber(value))
	case reflect.Slice, reflect.Array:
		length := value.Len()
		builder.WriteByte('{')
		if length == 0 {
			builder.WriteByte('}')
			return
		}
		allSimple := true
		for index := 0; index < length; index++ {
			if !simpleLuaValue(value.Index(index)) {
				allSimple = false
				break
			}
		}
		if allSimple {
			for index := 0; index < length; index++ {
				if index%16 == 0 {
					builder.WriteByte('\n')
					builder.WriteString(strings.Repeat("    ", indent+1))
				} else {
					builder.WriteByte(' ')
				}
				writeLuaValue(builder, value.Index(index).Interface(), indent+1)
				builder.WriteByte(',')
			}
			builder.WriteByte('\n')
			builder.WriteString(strings.Repeat("    ", indent))
			builder.WriteByte('}')
			return
		}
		builder.WriteByte('\n')
		for index := 0; index < length; index++ {
			builder.WriteString(strings.Repeat("    ", indent+1))
			writeLuaValue(builder, value.Index(index).Interface(), indent+1)
			builder.WriteString(",\n")
		}
		builder.WriteString(strings.Repeat("    ", indent))
		builder.WriteByte('}')
	case reflect.Map:
		builder.WriteByte('{')
		if value.Len() == 0 {
			builder.WriteByte('}')
			return
		}
		keys := value.MapKeys()
		sort.Slice(keys, func(left, right int) bool {
			return fmt.Sprint(keys[left].Interface()) <
				fmt.Sprint(keys[right].Interface())
		})
		builder.WriteByte('\n')
		for _, key := range keys {
			keyText := fmt.Sprint(key.Interface())
			builder.WriteString(strings.Repeat("    ", indent+1))
			if isLuaIdentifier(keyText) {
				builder.WriteString(keyText)
			} else {
				builder.WriteByte('[')
				builder.WriteString(luaQuote(keyText))
				builder.WriteByte(']')
			}
			builder.WriteString(" = ")
			writeLuaValue(builder, value.MapIndex(key).Interface(), indent+1)
			builder.WriteString(",\n")
		}
		builder.WriteString(strings.Repeat("    ", indent))
		builder.WriteByte('}')
	default:
		panic("unsupported Lua value: " + value.Kind().String())
	}
}

func isLuaIdentifier(value string) bool {
	if value == "" {
		return false
	}
	for index, character := range value {
		if index == 0 {
			if character != '_' && !unicode.IsLetter(character) {
				return false
			}
		} else if character != '_' &&
			!unicode.IsLetter(character) &&
			!unicode.IsDigit(character) {
			return false
		}
	}
	return true
}

func shapeValue(shape stageShape) map[string]any {
	result := map[string]any{"type": shape.Type}
	if shape.Type == "rectangle" {
		result["x"] = shape.X
		result["y"] = shape.Y
		result["width"] = shape.Width
		result["height"] = shape.Height
	} else {
		points := make([]any, 0, len(shape.Points))
		for _, point := range shape.Points {
			points = append(points, map[string]any{
				"x": point.X,
				"y": point.Y,
			})
		}
		result["points"] = points
	}
	return result
}

func compiledStageValue(stage compiledStage) map[string]any {
	tilesets := make([]any, 0, len(stage.Tilesets))
	for _, tileset := range stage.Tilesets {
		tilesets = append(tilesets, map[string]any{
			"id":          tileset.ID,
			"first_gid":   tileset.FirstGID,
			"tile_count":  tileset.TileCount,
			"columns":     tileset.Columns,
			"tile_width":  tileset.TileWidth,
			"tile_height": tileset.TileHeight,
			"asset":       tileset.Asset,
		})
	}
	layers := make([]any, 0, len(stage.Layers))
	for _, layer := range stage.Layers {
		layers = append(layers, map[string]any{
			"id":       layer.ID,
			"name":     layer.Name,
			"width":    layer.Width,
			"height":   layer.Height,
			"visible":  layer.Visible,
			"opacity":  layer.Opacity,
			"offset_x": layer.OffsetX,
			"offset_y": layer.OffsetY,
			"data":     layer.Data,
		})
	}
	spawns := make([]any, 0, len(stage.Spawns))
	for _, spawn := range stage.Spawns {
		value := map[string]any{
			"id":       spawn.ID,
			"actor":    spawn.Actor,
			"position": map[string]any{"x": spawn.X, "y": spawn.Y},
		}
		if len(spawn.Tags) != 0 {
			value["tags"] = spawn.Tags
		}
		spawns = append(spawns, value)
	}
	walls := make([]any, 0, len(stage.Walls))
	for _, wall := range stage.Walls {
		walls = append(walls, map[string]any{
			"id": wall.ID, "shape": shapeValue(wall.Shape),
		})
	}
	spawnPoints := make([]any, 0, len(stage.SpawnPoints))
	for _, point := range stage.SpawnPoints {
		spawnPoints = append(spawnPoints, map[string]any{
			"id": point.ID, "x": point.X, "y": point.Y,
		})
	}
	portals := make([]any, 0, len(stage.Portals))
	for _, portal := range stage.Portals {
		value := map[string]any{
			"id":           portal.ID,
			"shape":        shapeValue(portal.Shape),
			"target_stage": portal.TargetStage,
			"target_spawn": portal.TargetSpawn,
			"cooldown":     portal.Cooldown,
		}
		if portal.ActorTag != "" {
			value["actor_tag"] = portal.ActorTag
		}
		portals = append(portals, value)
	}
	triggers := make([]any, 0, len(stage.Triggers))
	for _, trigger := range stage.Triggers {
		value := map[string]any{
			"id":       trigger.ID,
			"shape":    shapeValue(trigger.Shape),
			"once":     trigger.Once,
			"cooldown": trigger.Cooldown,
			"actions":  trigger.Actions,
		}
		if trigger.ActorTag != "" {
			value["actor_tag"] = trigger.ActorTag
		}
		if trigger.Condition != nil {
			value["condition"] = trigger.Condition
		}
		triggers = append(triggers, value)
	}
	result := map[string]any{
		"schema_version": 1,
		"kind":           "stage",
		"id":             stage.ID,
		"name":           stage.Name,
		"mode":           stage.Mode,
		"width":          stage.Width,
		"height":         stage.Height,
		"background":     stage.Background,
		"metadata": map[string]any{
			"source":    stage.Source,
			"generated": true,
		},
		"camera": map[string]any{
			"viewport_width":  stage.CameraWidth,
			"viewport_height": stage.CameraHeight,
			"follow_tag":      "player",
		},
		"tilemap": map[string]any{
			"source":      stage.Source,
			"tile_width":  stage.TileWidth,
			"tile_height": stage.TileHeight,
			"tilesets":    tilesets,
			"layers":      layers,
		},
		"spawns":       spawns,
		"walls":        walls,
		"spawn_points": spawnPoints,
		"portals":      portals,
		"triggers":     triggers,
	}
	if stage.NameKey != "" {
		result["name_key"] = stage.NameKey
	}
	return result
}

func encodeStage(stage compiledStage) []byte {
	var builder strings.Builder
	builder.WriteString("-- Generated by lovectl map compile.\n")
	builder.WriteString("-- Edit ")
	builder.WriteString(stage.Source)
	builder.WriteString(" instead of this file.\n")
	builder.WriteString("return ")
	writeLuaValue(&builder, compiledStageValue(stage), 0)
	builder.WriteByte('\n')
	return []byte(builder.String())
}

func discoverTMX(projectPath string, arguments []string) ([]string, error) {
	if len(arguments) != 0 {
		result := make([]string, 0, len(arguments))
		for _, argument := range arguments {
			path := argument
			if !filepath.IsAbs(path) {
				path = filepath.Join(projectPath, path)
			}
			info, err := os.Stat(path)
			if err != nil {
				return nil, err
			}
			if info.IsDir() {
				discovered, err := collectFiles(path, ".tmx")
				if err != nil {
					return nil, err
				}
				result = append(result, discovered...)
			} else if filepath.Ext(path) == ".tmx" {
				result = append(result, path)
			} else {
				return nil, fmt.Errorf("%s is not a TMX file", argument)
			}
		}
		sort.Strings(result)
		return result, nil
	}
	root := filepath.Join(projectPath, "game", "maps")
	info, err := os.Stat(root)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, errors.New("game/maps does not exist")
		}
		return nil, err
	}
	if !info.IsDir() {
		return nil, errors.New("game/maps is not a directory")
	}
	return collectFiles(root, ".tmx")
}

func generatedFileName(stageID string) string {
	name := strings.TrimPrefix(stageID, "stage.")
	name = strings.ReplaceAll(name, ".", "_")
	return sanitizeID(name) + ".lua"
}

func copyDirectory(source string, destination string) error {
	info, err := os.Stat(source)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	if !info.IsDir() {
		return fmt.Errorf("%s is not a directory", source)
	}
	return filepath.WalkDir(
		source,
		func(path string, entry os.DirEntry, walkError error) error {
			if walkError != nil {
				return walkError
			}
			relative, err := filepath.Rel(source, path)
			if err != nil {
				return err
			}
			if relative == "." {
				return nil
			}
			target := filepath.Join(destination, relative)
			info, err := entry.Info()
			if err != nil {
				return err
			}
			if info.Mode()&os.ModeSymlink != 0 {
				return fmt.Errorf(
					"generated directory must not contain symlink %s",
					path,
				)
			}
			if entry.IsDir() {
				return os.MkdirAll(target, info.Mode().Perm())
			}
			if !info.Mode().IsRegular() {
				return fmt.Errorf(
					"generated directory contains non-regular file %s",
					path,
				)
			}
			data, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			return os.WriteFile(target, data, info.Mode().Perm())
		},
	)
}

func replaceDirectory(
	target string,
	prepare func(temporary string) error,
) error {
	parent := filepath.Dir(target)
	if err := os.MkdirAll(parent, 0o755); err != nil {
		return err
	}
	temporary, err := os.MkdirTemp(
		parent,
		"."+filepath.Base(target)+".tmp-",
	)
	if err != nil {
		return err
	}
	keepTemporary := false
	defer func() {
		if !keepTemporary {
			_ = os.RemoveAll(temporary)
		}
	}()
	if err := copyDirectory(target, temporary); err != nil {
		return err
	}
	if err := prepare(temporary); err != nil {
		return err
	}

	backup, err := os.MkdirTemp(
		parent,
		"."+filepath.Base(target)+".backup-",
	)
	if err != nil {
		return err
	}
	if err := os.Remove(backup); err != nil {
		return err
	}
	hadTarget := false
	if _, err := os.Stat(target); err == nil {
		hadTarget = true
		if err := os.Rename(target, backup); err != nil {
			return err
		}
	} else if !os.IsNotExist(err) {
		return err
	}
	if err := os.Rename(temporary, target); err != nil {
		if hadTarget {
			_ = os.Rename(backup, target)
		}
		return err
	}
	keepTemporary = true
	if hadTarget {
		if err := os.RemoveAll(backup); err != nil {
			return err
		}
	}
	return nil
}

func compileMaps(
	projectPath string,
	sourceArguments []string,
	outputArgument string,
	write bool,
) error {
	sources, err := discoverTMX(projectPath, sourceArguments)
	if err != nil {
		return err
	}
	selectedSources := len(sourceArguments) != 0
	if len(sources) == 0 && selectedSources {
		return errors.New("no TMX maps found")
	}
	output := outputArgument
	if output == "" {
		output = filepath.Join(
			projectPath,
			"game",
			"content",
			"stages",
			"generated",
		)
	} else if !filepath.IsAbs(output) {
		output = filepath.Join(projectPath, output)
	}
	type mapOutput struct {
		stage       compiledStage
		source      string
		fileName    string
		destination string
		encoded     []byte
	}
	outputs := map[string]string{}
	stageSources := map[string]string{}
	var compiled []mapOutput
	totalLayers := 0
	totalObjects := 0
	for _, sourcePath := range sources {
		relative, err := filepath.Rel(projectPath, sourcePath)
		if err != nil {
			return err
		}
		stage, err := parseTMX(sourcePath, relative)
		if err != nil {
			return err
		}
		if previous, exists := stageSources[stage.ID]; exists {
			return fmt.Errorf(
				"%s and %s both declare %s",
				previous,
				relative,
				stage.ID,
			)
		}
		stageSources[stage.ID] = relative
		fileName := generatedFileName(stage.ID)
		if previous, exists := outputs[fileName]; exists {
			return fmt.Errorf(
				"%s and %s both generate %s",
				previous,
				relative,
				fileName,
			)
		}
		outputs[fileName] = relative
		destination := filepath.Join(output, fileName)
		encoded := encodeStage(stage)
		compiled = append(compiled, mapOutput{
			stage:       stage,
			source:      relative,
			fileName:    fileName,
			destination: destination,
			encoded:     encoded,
		})
		totalLayers += len(stage.Layers)
		totalObjects += stage.SourceObjectCt
	}

	stageByID := map[string]compiledStage{}
	for _, output := range compiled {
		stageByID[output.stage.ID] = output.stage
	}
	for _, output := range compiled {
		for _, portal := range output.stage.Portals {
			target, compiledTarget := stageByID[portal.TargetStage]
			if !compiledTarget {
				continue
			}
			found := false
			for _, point := range target.SpawnPoints {
				if point.ID == portal.TargetSpawn {
					found = true
					break
				}
			}
			if !found {
				return fmt.Errorf(
					"%s portal %q targets missing spawn %s/%s",
					output.source,
					portal.ID,
					portal.TargetStage,
					portal.TargetSpawn,
				)
			}
		}
	}

	if write {
		err := replaceDirectory(output, func(temporary string) error {
			if !selectedSources {
				entries, err := os.ReadDir(temporary)
				if err != nil {
					return err
				}
				for _, entry := range entries {
					if !entry.IsDir() &&
						filepath.Ext(entry.Name()) == ".lua" {
						if err := os.Remove(
							filepath.Join(temporary, entry.Name()),
						); err != nil {
							return err
						}
					}
				}
			}
			for _, item := range compiled {
				if err := os.WriteFile(
					filepath.Join(temporary, item.fileName),
					item.encoded,
					0o644,
				); err != nil {
					return err
				}
			}
			return nil
		})
		if err != nil {
			return err
		}
		for _, output := range compiled {
			fmt.Printf(
				"Compiled %s -> %s\n",
				output.source,
				filepath.ToSlash(output.destination),
			)
		}
	} else {
		for _, output := range compiled {
			existing, err := os.ReadFile(output.destination)
			if err != nil {
				if os.IsNotExist(err) {
					return fmt.Errorf(
						"generated map is missing: %s (run lovectl map compile)",
						output.destination,
					)
				}
				return err
			}
			if !bytes.Equal(existing, output.encoded) {
				return fmt.Errorf(
					"generated map is stale: %s (run lovectl map compile)",
					output.destination,
				)
			}
		}
		if !selectedSources {
			entries, err := os.ReadDir(output)
			if err != nil {
				if os.IsNotExist(err) && len(compiled) == 0 {
					entries = nil
				} else {
					return err
				}
			}
			for _, entry := range entries {
				if entry.IsDir() ||
					filepath.Ext(entry.Name()) != ".lua" {
					continue
				}
				if _, expected := outputs[entry.Name()]; !expected {
					return fmt.Errorf(
						"orphan generated map: %s",
						filepath.Join(output, entry.Name()),
					)
				}
			}
		}
	}
	if write {
		fmt.Printf(
			"Map compile: %d stages, %d tile layers, %d semantic objects\n",
			len(sources),
			totalLayers,
			totalObjects,
		)
	} else {
		fmt.Printf(
			"Map sources: %d stages are valid and generated output is current\n",
			len(sources),
		)
	}
	return nil
}

func runMapCommand(projectPath string, arguments []string) error {
	if len(arguments) == 0 {
		return errors.New(
			"usage: lovectl map compile|check [--output DIR] [SOURCE.tmx ...]",
		)
	}
	mode := arguments[0]
	flags := flag.NewFlagSet("map "+mode, flag.ContinueOnError)
	output := flags.String(
		"output",
		"",
		"generated stage directory",
	)
	if err := flags.Parse(arguments[1:]); err != nil {
		return err
	}
	switch mode {
	case "compile":
		return compileMaps(
			projectPath,
			flags.Args(),
			*output,
			true,
		)
	case "check":
		return compileMaps(
			projectPath,
			flags.Args(),
			*output,
			false,
		)
	default:
		return fmt.Errorf("unknown map command: %s", mode)
	}
}
