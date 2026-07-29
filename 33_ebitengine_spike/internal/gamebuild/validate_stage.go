package gamebuild

import (
	"fmt"
	"math"

	"practice_love2d/33_ebitengine_spike/internal/content"
)

func validateStageSemantics(
	catalog *content.Catalog,
	data map[string]any,
	id string,
) error {
	if err := rejectUnknownKeys(
		data,
		id,
		"schema_version",
		"kind",
		"id",
		"name",
		"name_key",
		"width",
		"height",
		"mode",
		"background",
		"spawns",
		"metadata",
		"camera",
		"tilemap",
		"walls",
		"spawn_points",
		"triggers",
		"portals",
		"encounters",
	); err != nil {
		return err
	}
	width, err := requiredPositiveNumberValue(data["width"], id+".width")
	if err != nil {
		return err
	}
	height, err := requiredPositiveNumberValue(data["height"], id+".height")
	if err != nil {
		return err
	}
	for _, field := range []string{"name", "name_key", "mode"} {
		if err := optionalString(data[field], id+"."+field); err != nil {
			return err
		}
	}
	if _, _, err := optionalObject(data["metadata"], id+".metadata"); err != nil {
		return err
	}
	if err := validateColor(data["background"], id+".background", false); err != nil {
		return err
	}
	spawns, err := requiredArray(data["spawns"], id+".spawns")
	if err != nil {
		return err
	}
	seen := make(map[string]struct{}, len(spawns))
	for index, raw := range spawns {
		path := fmt.Sprintf("%s.spawns[%d]", id, index)
		spawn, err := requiredObject(raw, path)
		if err != nil {
			return err
		}
		spawnID, err := requiredString(spawn["id"], path+".id")
		if err != nil {
			return err
		}
		if _, duplicate := seen[spawnID]; duplicate {
			return fmt.Errorf("%s.id duplicates spawn %q", path, spawnID)
		}
		seen[spawnID] = struct{}{}
		actorID, err := requiredString(spawn["actor"], path+".actor")
		if err != nil {
			return err
		}
		actor, err := referencedDefinition(
			catalog,
			actorID,
			"actor",
			path+".actor",
		)
		if err != nil {
			return err
		}
		position, err := requiredObject(spawn["position"], path+".position")
		if err != nil {
			return err
		}
		for _, axis := range []string{"x", "y"} {
			if _, err := requiredNumber(
				position[axis],
				path+".position."+axis,
			); err != nil {
				return err
			}
		}
		if err := validateStringArray(spawn["tags"], path+".tags", false); err != nil {
			return err
		}
		if overrides, exists, err := optionalObject(
			spawn["components"],
			path+".components",
		); err != nil {
			return err
		} else if exists {
			for name, raw := range overrides {
				if _, ok := raw.(map[string]any); !ok {
					return fmt.Errorf(
						"%s.components.%s must be an object",
						path,
						name,
					)
				}
			}
		}
		if err := validateStringArray(
			actor["tags"],
			path+".actor.tags",
			false,
		); err != nil {
			return err
		}
	}

	camera, hasCamera, err := optionalObject(data["camera"], id+".camera")
	if err != nil {
		return err
	}
	if hasCamera {
		if _, err := requiredPositiveNumberValue(
			camera["viewport_width"],
			id+".camera.viewport_width",
		); err != nil {
			return err
		}
		if _, err := requiredPositiveNumberValue(
			camera["viewport_height"],
			id+".camera.viewport_height",
		); err != nil {
			return err
		}
		if camera["follow_tag"] != nil {
			if _, err := requiredString(
				camera["follow_tag"],
				id+".camera.follow_tag",
			); err != nil {
				return err
			}
		}
	}
	if err := validateStageWalls(data["walls"], id+".walls"); err != nil {
		return err
	}
	if err := validateStageSpawnPoints(
		data["spawn_points"],
		id+".spawn_points",
		width,
		height,
	); err != nil {
		return err
	}
	if err := validateStagePortals(
		catalog,
		data["portals"],
		id+".portals",
	); err != nil {
		return err
	}
	if err := validateStageTriggers(
		catalog,
		data["triggers"],
		id+".triggers",
	); err != nil {
		return err
	}
	if err := validateStageEncounters(
		catalog,
		data["encounters"],
		id+".encounters",
		data["spawns"],
	); err != nil {
		return err
	}
	if err := validateTilemap(
		catalog,
		data["tilemap"],
		id+".tilemap",
	); err != nil {
		return err
	}
	return nil
}

func validateStageWalls(value any, path string) error {
	walls, exists, err := optionalArray(value, path)
	if err != nil || !exists {
		return err
	}
	seen := make(map[string]struct{}, len(walls))
	for index, raw := range walls {
		itemPath := fmt.Sprintf("%s[%d]", path, index)
		wall, err := requiredObject(raw, itemPath)
		if err != nil {
			return err
		}
		wallID, err := requiredString(wall["id"], itemPath+".id")
		if err != nil {
			return err
		}
		if _, duplicate := seen[wallID]; duplicate {
			return fmt.Errorf("%s.id duplicates wall %q", itemPath, wallID)
		}
		seen[wallID] = struct{}{}
		shape, err := requiredObject(wall["shape"], itemPath+".shape")
		if err != nil {
			return err
		}
		shapeType, err := requiredString(
			shape["type"],
			itemPath+".shape.type",
		)
		if err != nil {
			return err
		}
		switch shapeType {
		case "rectangle":
			for _, field := range []string{"x", "y"} {
				if _, err := requiredNumber(
					shape[field],
					itemPath+".shape."+field,
				); err != nil {
					return err
				}
			}
			for _, field := range []string{"width", "height"} {
				if err := requiredPositiveNumber(
					shape[field],
					itemPath+".shape."+field,
				); err != nil {
					return err
				}
			}
		case "polygon":
			points, err := requiredArray(
				shape["points"],
				itemPath+".shape.points",
			)
			if err != nil {
				return err
			}
			if len(points) < 3 {
				return fmt.Errorf(
					"%s.shape.points requires at least three points",
					itemPath,
				)
			}
			for pointIndex, rawPoint := range points {
				pointPath := fmt.Sprintf(
					"%s.shape.points[%d]",
					itemPath,
					pointIndex,
				)
				point, err := requiredObject(rawPoint, pointPath)
				if err != nil {
					return err
				}
				for _, axis := range []string{"x", "y"} {
					if _, err := requiredNumber(
						point[axis],
						pointPath+"."+axis,
					); err != nil {
						return err
					}
				}
			}
		default:
			return fmt.Errorf(
				"%s.shape.type has unsupported value %q",
				itemPath,
				shapeType,
			)
		}
	}
	return nil
}

func validateStageSpawnPoints(
	value any,
	path string,
	stageWidth float64,
	stageHeight float64,
) error {
	points, exists, err := optionalArray(value, path)
	if err != nil || !exists {
		return err
	}
	seen := make(map[string]struct{}, len(points))
	for index, raw := range points {
		itemPath := fmt.Sprintf("%s[%d]", path, index)
		point, err := requiredObject(raw, itemPath)
		if err != nil {
			return err
		}
		if err := rejectUnknownKeys(point, itemPath, "id", "x", "y"); err != nil {
			return err
		}
		pointID, err := requiredString(point["id"], itemPath+".id")
		if err != nil {
			return err
		}
		if _, duplicate := seen[pointID]; duplicate {
			return fmt.Errorf("%s.id duplicates spawn point %q", itemPath, pointID)
		}
		seen[pointID] = struct{}{}
		x, err := requiredNumber(point["x"], itemPath+".x")
		if err != nil {
			return err
		}
		y, err := requiredNumber(point["y"], itemPath+".y")
		if err != nil {
			return err
		}
		if x < 0 || x > stageWidth || y < 0 || y > stageHeight {
			return fmt.Errorf("%s lies outside stage bounds", itemPath)
		}
	}
	return nil
}

func validateStagePortals(
	catalog *content.Catalog,
	value any,
	path string,
) error {
	portals, exists, err := optionalArray(value, path)
	if err != nil || !exists {
		return err
	}
	seen := make(map[string]struct{}, len(portals))
	for index, raw := range portals {
		itemPath := fmt.Sprintf("%s[%d]", path, index)
		portal, err := requiredObject(raw, itemPath)
		if err != nil {
			return err
		}
		if err := rejectUnknownKeys(
			portal,
			itemPath,
			"id",
			"shape",
			"actor_tag",
			"target_stage",
			"target_spawn",
			"cooldown",
		); err != nil {
			return err
		}
		portalID, err := requiredString(portal["id"], itemPath+".id")
		if err != nil {
			return err
		}
		if _, duplicate := seen[portalID]; duplicate {
			return fmt.Errorf("%s.id duplicates portal %q", itemPath, portalID)
		}
		seen[portalID] = struct{}{}
		shape, err := validateGeometryShape(portal["shape"], itemPath+".shape")
		if err != nil {
			return err
		}
		_ = shape
		if err := optionalString(portal["actor_tag"], itemPath+".actor_tag"); err != nil {
			return err
		}
		target, err := referenceField(
			catalog,
			portal,
			"target_stage",
			"stage",
			itemPath,
			true,
		)
		if err != nil {
			return err
		}
		targetSpawn, err := requiredString(
			portal["target_spawn"],
			itemPath+".target_spawn",
		)
		if err != nil {
			return err
		}
		found := false
		for _, rawPoint := range anySlice(target["spawn_points"]) {
			point, _ := rawPoint.(map[string]any)
			if point["id"] == targetSpawn {
				found = true
				break
			}
		}
		if !found {
			return fmt.Errorf(
				"%s.target_spawn references missing spawn point %q",
				itemPath,
				targetSpawn,
			)
		}
		if err := optionalNonNegativeNumber(
			portal["cooldown"],
			itemPath+".cooldown",
		); err != nil {
			return err
		}
	}
	return nil
}

func validateStageTriggers(
	catalog *content.Catalog,
	value any,
	path string,
) error {
	triggers, exists, err := optionalArray(value, path)
	if err != nil || !exists {
		return err
	}
	seen := make(map[string]struct{}, len(triggers))
	for index, raw := range triggers {
		itemPath := fmt.Sprintf("%s[%d]", path, index)
		trigger, err := requiredObject(raw, itemPath)
		if err != nil {
			return err
		}
		if err := rejectUnknownKeys(
			trigger,
			itemPath,
			"id",
			"shape",
			"actor_tag",
			"once",
			"cooldown",
			"condition",
			"actions",
		); err != nil {
			return err
		}
		triggerID, err := requiredString(trigger["id"], itemPath+".id")
		if err != nil {
			return err
		}
		if _, duplicate := seen[triggerID]; duplicate {
			return fmt.Errorf("%s.id duplicates trigger %q", itemPath, triggerID)
		}
		seen[triggerID] = struct{}{}
		shape, err := validateGeometryShape(trigger["shape"], itemPath+".shape")
		if err != nil {
			return err
		}
		_ = shape
		if err := optionalString(
			trigger["actor_tag"],
			itemPath+".actor_tag",
		); err != nil {
			return err
		}
		if err := optionalBoolean(trigger["once"], itemPath+".once"); err != nil {
			return err
		}
		if err := optionalNonNegativeNumber(
			trigger["cooldown"],
			itemPath+".cooldown",
		); err != nil {
			return err
		}
		if trigger["condition"] != nil {
			if err := validateCondition(
				catalog,
				trigger["condition"],
				itemPath+".condition",
			); err != nil {
				return err
			}
		}
		if err := validateActions(
			catalog,
			trigger["actions"],
			itemPath+".actions",
			true,
		); err != nil {
			return err
		}
	}
	return nil
}

func validateStageEncounters(
	catalog *content.Catalog,
	value any,
	path string,
	stageSpawns any,
) error {
	placements, exists, err := optionalArray(value, path)
	if err != nil || !exists {
		return err
	}
	seen := make(map[string]struct{}, len(placements))
	generatedIDs := make(map[string]struct{})
	for _, raw := range anySlice(stageSpawns) {
		spawn, _ := raw.(map[string]any)
		if id, ok := spawn["id"].(string); ok {
			generatedIDs[id] = struct{}{}
		}
	}
	for index, raw := range placements {
		itemPath := fmt.Sprintf("%s[%d]", path, index)
		placement, err := requiredObject(raw, itemPath)
		if err != nil {
			return err
		}
		if err := rejectUnknownKeys(
			placement,
			itemPath,
			"id",
			"encounter",
			"position",
			"auto_start",
		); err != nil {
			return err
		}
		placementID, err := requiredString(placement["id"], itemPath+".id")
		if err != nil {
			return err
		}
		if _, duplicate := seen[placementID]; duplicate {
			return fmt.Errorf(
				"%s.id duplicates encounter placement %q",
				itemPath,
				placementID,
			)
		}
		seen[placementID] = struct{}{}
		encounter, err := referenceField(
			catalog,
			placement,
			"encounter",
			"encounter",
			itemPath,
			true,
		)
		if err != nil {
			return err
		}
		for waveIndex, rawWave := range anySlice(encounter["waves"]) {
			wave, _ := rawWave.(map[string]any)
			for _, rawSpawn := range anySlice(wave["spawns"]) {
				spawn, _ := rawSpawn.(map[string]any)
				spawnID, _ := spawn["id"].(string)
				entityID := fmt.Sprintf(
					"encounter.%s.wave.%d.%s",
					placementID,
					waveIndex+1,
					spawnID,
				)
				if _, duplicate := generatedIDs[entityID]; duplicate {
					return fmt.Errorf(
						"%s generates duplicate entity id %q",
						itemPath,
						entityID,
					)
				}
				generatedIDs[entityID] = struct{}{}
			}
		}
		if position, hasPosition, err := optionalObject(
			placement["position"],
			itemPath+".position",
		); err != nil {
			return err
		} else if hasPosition {
			if err := rejectUnknownKeys(position, itemPath+".position", "x", "y"); err != nil {
				return err
			}
			x, err := requiredNumber(position["x"], itemPath+".position.x")
			if err != nil {
				return err
			}
			y, err := requiredNumber(position["y"], itemPath+".position.y")
			if err != nil {
				return err
			}
			_, _ = x, y
		}
		if err := optionalBoolean(
			placement["auto_start"],
			itemPath+".auto_start",
		); err != nil {
			return err
		}
	}
	return nil
}

func validateGeometryShape(value any, path string) (map[string]any, error) {
	shape, err := requiredObject(value, path)
	if err != nil {
		return nil, err
	}
	if err := rejectUnknownKeys(
		shape,
		path,
		"type",
		"x",
		"y",
		"width",
		"height",
		"points",
	); err != nil {
		return nil, err
	}
	shapeType, err := requiredString(shape["type"], path+".type")
	if err != nil {
		return nil, err
	}
	switch shapeType {
	case "rectangle":
		for _, field := range []string{"x", "y"} {
			if _, err := requiredNumber(shape[field], path+"."+field); err != nil {
				return nil, err
			}
		}
		for _, field := range []string{"width", "height"} {
			if err := requiredPositiveNumber(shape[field], path+"."+field); err != nil {
				return nil, err
			}
		}
	case "polygon":
		points, err := requiredArray(shape["points"], path+".points")
		if err != nil {
			return nil, err
		}
		if len(points) < 3 {
			return nil, fmt.Errorf("%s.points requires at least three points", path)
		}
		for index, raw := range points {
			pointPath := fmt.Sprintf("%s.points[%d]", path, index)
			point, err := requiredObject(raw, pointPath)
			if err != nil {
				return nil, err
			}
			if err := rejectUnknownKeys(point, pointPath, "x", "y"); err != nil {
				return nil, err
			}
			for _, axis := range []string{"x", "y"} {
				if _, err := requiredNumber(point[axis], pointPath+"."+axis); err != nil {
					return nil, err
				}
			}
		}
	default:
		return nil, fmt.Errorf("%s.type has unsupported value %q", path, shapeType)
	}
	return shape, nil
}

func validateShapeInsideStage(
	shape map[string]any,
	path string,
	stageWidth float64,
	stageHeight float64,
) error {
	minX, minY, maxX, maxY, err := shapeBounds(shape, path)
	if err != nil {
		return err
	}
	if minX < 0 || minY < 0 || maxX > stageWidth || maxY > stageHeight {
		return fmt.Errorf("%s lies outside stage bounds", path)
	}
	return nil
}

type validatedTileset struct {
	id        string
	firstGID  int
	tileCount int
}

func validateTilemap(
	catalog *content.Catalog,
	value any,
	path string,
) error {
	tilemap, exists, err := optionalObject(value, path)
	if err != nil || !exists {
		return err
	}
	if err := rejectUnknownKeys(
		tilemap,
		path,
		"source",
		"tile_width",
		"tile_height",
		"tilesets",
		"layers",
	); err != nil {
		return err
	}
	if err := optionalString(tilemap["source"], path+".source"); err != nil {
		return err
	}
	if err := requiredPositiveInteger(
		tilemap["tile_width"],
		path+".tile_width",
	); err != nil {
		return err
	}
	if err := requiredPositiveInteger(
		tilemap["tile_height"],
		path+".tile_height",
	); err != nil {
		return err
	}
	rawTilesets, err := requiredArray(tilemap["tilesets"], path+".tilesets")
	if err != nil {
		return err
	}
	if len(rawTilesets) == 0 {
		return fmt.Errorf("%s.tilesets must not be empty", path)
	}
	tilesets := make([]validatedTileset, 0, len(rawTilesets))
	seenTilesets := make(map[string]struct{}, len(rawTilesets))
	for index, raw := range rawTilesets {
		itemPath := fmt.Sprintf("%s.tilesets[%d]", path, index)
		tileset, err := requiredObject(raw, itemPath)
		if err != nil {
			return err
		}
		if err := rejectUnknownKeys(
			tileset,
			itemPath,
			"id",
			"first_gid",
			"tile_count",
			"columns",
			"tile_width",
			"tile_height",
			"asset",
		); err != nil {
			return err
		}
		tilesetID, err := requiredString(tileset["id"], itemPath+".id")
		if err != nil {
			return err
		}
		if _, duplicate := seenTilesets[tilesetID]; duplicate {
			return fmt.Errorf("%s.id duplicates tileset %q", itemPath, tilesetID)
		}
		seenTilesets[tilesetID] = struct{}{}
		firstGID, err := requiredPositiveIntegerValue(
			tileset["first_gid"],
			itemPath+".first_gid",
		)
		if err != nil {
			return err
		}
		tileCount, err := requiredPositiveIntegerValue(
			tileset["tile_count"],
			itemPath+".tile_count",
		)
		if err != nil {
			return err
		}
		if _, err := requiredPositiveIntegerValue(
			tileset["columns"],
			itemPath+".columns",
		); err != nil {
			return err
		}
		for _, field := range []string{"tile_width", "tile_height"} {
			if err := requiredPositiveNumber(
				tileset[field],
				itemPath+"."+field,
			); err != nil {
				return err
			}
		}
		asset, err := referenceField(
			catalog,
			tileset,
			"asset",
			"asset",
			itemPath,
			true,
		)
		if err != nil {
			return err
		}
		if asset["asset_type"] != "image" {
			return fmt.Errorf("%s.asset must reference an image asset", itemPath)
		}
		tilesets = append(tilesets, validatedTileset{
			id:        tilesetID,
			firstGID:  firstGID,
			tileCount: tileCount,
		})
	}
	for left := 0; left < len(tilesets); left++ {
		leftLast := tilesets[left].firstGID + tilesets[left].tileCount - 1
		for right := left + 1; right < len(tilesets); right++ {
			rightLast := tilesets[right].firstGID +
				tilesets[right].tileCount - 1
			if tilesets[left].firstGID <= rightLast &&
				tilesets[right].firstGID <= leftLast {
				return fmt.Errorf(
					"%s.tilesets gid ranges overlap between %q and %q",
					path,
					tilesets[left].id,
					tilesets[right].id,
				)
			}
		}
	}
	layers, err := requiredArray(tilemap["layers"], path+".layers")
	if err != nil {
		return err
	}
	seenLayers := make(map[string]struct{}, len(layers))
	for index, raw := range layers {
		itemPath := fmt.Sprintf("%s.layers[%d]", path, index)
		layer, err := requiredObject(raw, itemPath)
		if err != nil {
			return err
		}
		if err := rejectUnknownKeys(
			layer,
			itemPath,
			"id",
			"name",
			"width",
			"height",
			"visible",
			"opacity",
			"offset_x",
			"offset_y",
			"data",
		); err != nil {
			return err
		}
		layerID, err := requiredString(layer["id"], itemPath+".id")
		if err != nil {
			return err
		}
		if _, duplicate := seenLayers[layerID]; duplicate {
			return fmt.Errorf("%s.id duplicates layer %q", itemPath, layerID)
		}
		seenLayers[layerID] = struct{}{}
		if err := optionalString(layer["name"], itemPath+".name"); err != nil {
			return err
		}
		layerWidth, err := requiredPositiveIntegerValue(
			layer["width"],
			itemPath+".width",
		)
		if err != nil {
			return err
		}
		layerHeight, err := requiredPositiveIntegerValue(
			layer["height"],
			itemPath+".height",
		)
		if err != nil {
			return err
		}
		if err := optionalBoolean(layer["visible"], itemPath+".visible"); err != nil {
			return err
		}
		if layer["opacity"] != nil {
			opacity, err := requiredNumber(layer["opacity"], itemPath+".opacity")
			if err != nil {
				return err
			}
			if opacity < 0 || opacity > 1 {
				return fmt.Errorf("%s.opacity must be between 0 and 1", itemPath)
			}
		}
		for _, field := range []string{"offset_x", "offset_y"} {
			if layer[field] != nil {
				if _, err := requiredNumber(
					layer[field],
					itemPath+"."+field,
				); err != nil {
					return err
				}
			}
		}
		gids, err := requiredArray(layer["data"], itemPath+".data")
		if err != nil {
			return err
		}
		if len(gids) != layerWidth*layerHeight {
			return fmt.Errorf(
				"%s.data contains %d gids, expected %d",
				itemPath,
				len(gids),
				layerWidth*layerHeight,
			)
		}
		for tileIndex, rawGID := range gids {
			gidPath := fmt.Sprintf("%s.data[%d]", itemPath, tileIndex)
			encoded, err := requiredNumber(rawGID, gidPath)
			if err != nil {
				return err
			}
			if math.Trunc(encoded) != encoded ||
				encoded < 0 ||
				encoded >= 4294967296 {
				return fmt.Errorf("%s must be an unsigned 32-bit gid", gidPath)
			}
			gid := decodeTileGID(uint64(encoded))
			if gid == 0 {
				continue
			}
			found := false
			for _, tileset := range tilesets {
				if int(gid) >= tileset.firstGID &&
					int(gid) < tileset.firstGID+tileset.tileCount {
					found = true
					break
				}
			}
			if !found {
				return fmt.Errorf(
					"%s gid %d belongs to no declared tileset",
					gidPath,
					gid,
				)
			}
		}
	}
	return nil
}

func decodeTileGID(encoded uint64) uint64 {
	const (
		flipHorizontal = uint64(2147483648)
		flipVertical   = uint64(1073741824)
		flipDiagonal   = uint64(536870912)
	)
	for _, flag := range []uint64{flipHorizontal, flipVertical, flipDiagonal} {
		if encoded >= flag {
			encoded -= flag
		}
	}
	return encoded
}

type validationPoint struct {
	x float64
	y float64
}

type validationCollisionShape struct {
	circle bool
	center validationPoint
	radius float64
	points []validationPoint
}

func stageRuntimeCoverageIssues(
	catalog *content.Catalog,
	data map[string]any,
	id string,
) []string {
	issues := make([]string, 0, 5)
	width, _ := number(data["width"])
	height, _ := number(data["height"])
	if camera, ok := data["camera"].(map[string]any); ok {
		viewportWidth, _ := number(camera["viewport_width"])
		viewportHeight, _ := number(camera["viewport_height"])
		if viewportWidth > width || viewportHeight > height {
			issues = append(
				issues,
				"Ebitengine adapter requires camera viewport within stage bounds",
			)
		}
		if followTag, ok := camera["follow_tag"].(string); ok {
			matches := 0
			for _, raw := range anySlice(data["spawns"]) {
				spawn, _ := raw.(map[string]any)
				actorID, _ := spawn["actor"].(string)
				actor, err := referencedDefinition(
					catalog,
					actorID,
					"actor",
					id+".camera.follow_tag",
				)
				if err != nil {
					continue
				}
				tags, _ := stringArray(
					actor["tags"],
					id+".camera.follow_tag",
					false,
				)
				instanceTags, _ := stringArray(
					spawn["tags"],
					id+".camera.follow_tag",
					false,
				)
				if containsString(append(tags, instanceTags...), followTag) {
					matches++
				}
			}
			if matches == 0 {
				issues = append(issues, fmt.Sprintf(
					"Ebitengine adapter camera follow_tag %q matches no actor in this stage",
					followTag,
				))
			} else if matches > 1 {
				issues = append(issues, fmt.Sprintf(
					"Ebitengine adapter camera follow_tag %q matches more than one actor in this stage",
					followTag,
				))
			}
		}
	}
	controlledActors := 0
	controlledTags := []string{}
	for _, raw := range anySlice(data["spawns"]) {
		spawn, _ := raw.(map[string]any)
		actorID, _ := spawn["actor"].(string)
		actor, err := referencedDefinition(
			catalog,
			actorID,
			"actor",
			id+".portals.actor_tag",
		)
		if err != nil {
			continue
		}
		components, _ := actor["components"].(map[string]any)
		_, controlled := components["control.player"]
		if overrides, ok := spawn["components"].(map[string]any); ok {
			if _, exists := overrides["control.player"]; exists {
				controlled = true
			}
		}
		if !controlled {
			continue
		}
		controlledActors++
		actorTags, _ := stringArray(
			actor["tags"],
			id+".portals.actor_tag",
			false,
		)
		instanceTags, _ := stringArray(
			spawn["tags"],
			id+".portals.actor_tag",
			false,
		)
		controlledTags = append(controlledTags, actorTags...)
		controlledTags = append(controlledTags, instanceTags...)
	}
	if controlledActors != 1 {
		issues = append(issues, fmt.Sprintf(
			"Ebitengine adapter requires exactly one controlled actor; got %d",
			controlledActors,
		))
	} else {
		for index, raw := range anySlice(data["portals"]) {
			portal, _ := raw.(map[string]any)
			actorTag, _ := portal["actor_tag"].(string)
			if actorTag == "" {
				actorTag = DefaultPortalActorTag
			}
			if !containsString(controlledTags, actorTag) {
				issues = append(issues, fmt.Sprintf(
					"Ebitengine adapter portal %d actor_tag %q "+
						"matches no controlled actor",
					index,
					actorTag,
				))
			}
		}
	}
	if err := validateStagePhysicalLayout(
		catalog,
		data,
		id,
		width,
		height,
	); err != nil {
		issues = append(issues, "Ebitengine adapter: "+err.Error())
	}
	return issues
}

func validateStagePhysicalLayout(
	catalog *content.Catalog,
	data map[string]any,
	id string,
	stageWidth float64,
	stageHeight float64,
) error {
	walls := anySlice(data["walls"])
	wallShapes := make([]validationCollisionShape, 0, len(walls))
	wallIDs := make([]string, 0, len(walls))
	for index, raw := range walls {
		wall, _ := raw.(map[string]any)
		shape, _ := wall["shape"].(map[string]any)
		path := fmt.Sprintf("%s.walls[%d].shape", id, index)
		if err := validateShapeInsideStage(
			shape,
			path,
			stageWidth,
			stageHeight,
		); err != nil {
			return err
		}
		converted, err := collisionShapeFromGeometry(shape, path)
		if err != nil {
			return err
		}
		wallShapes = append(wallShapes, converted)
		wallID, _ := wall["id"].(string)
		wallIDs = append(wallIDs, wallID)
	}

	for index, raw := range anySlice(data["spawns"]) {
		spawn, _ := raw.(map[string]any)
		path := fmt.Sprintf("%s.spawns[%d]", id, index)
		actorID, _ := spawn["actor"].(string)
		actor, err := referencedDefinition(
			catalog,
			actorID,
			"actor",
			path+".actor",
		)
		if err != nil {
			return err
		}
		components, _ := actor["components"].(map[string]any)
		baseBody, hasBody := components["body"].(map[string]any)
		if !hasBody {
			return fmt.Errorf("%s actor has no body", path)
		}
		body := make(map[string]any, len(baseBody))
		for key, value := range baseBody {
			body[key] = value
		}
		if overrides, ok := spawn["components"].(map[string]any); ok {
			if bodyOverride, ok := overrides["body"].(map[string]any); ok {
				for key, value := range bodyOverride {
					body[key] = value
				}
			}
		}
		if err := validateBody(body, path+".body"); err != nil {
			return err
		}
		position, _ := spawn["position"].(map[string]any)
		x, _ := number(position["x"])
		y, _ := number(position["y"])
		spawnShape, err := collisionShapeFromBody(body, x, y, path+".body")
		if err != nil {
			return err
		}
		minX, minY, maxX, maxY := collisionShapeBounds(spawnShape)
		if minX < 0 || minY < 0 ||
			maxX > stageWidth || maxY > stageHeight {
			return fmt.Errorf("%s body lies outside stage bounds", path)
		}
		for wallIndex, wallShape := range wallShapes {
			if collisionShapesOverlap(spawnShape, wallShape) {
				return fmt.Errorf(
					"%s body overlaps wall %q",
					path,
					wallIDs[wallIndex],
				)
			}
		}
	}
	return nil
}

func shapeBounds(
	shape map[string]any,
	path string,
) (float64, float64, float64, float64, error) {
	shapeType, _ := shape["type"].(string)
	if shapeType == "rectangle" {
		x, xOK := number(shape["x"])
		y, yOK := number(shape["y"])
		width, widthOK := number(shape["width"])
		height, heightOK := number(shape["height"])
		if !xOK || !yOK || !widthOK || !heightOK {
			return 0, 0, 0, 0, fmt.Errorf("%s rectangle is incomplete", path)
		}
		return x - width/2, y - height/2,
			x + width/2, y + height/2, nil
	}
	points := anySlice(shape["points"])
	if shapeType != "polygon" || len(points) < 3 {
		return 0, 0, 0, 0, fmt.Errorf("%s polygon is incomplete", path)
	}
	minX, minY := math.Inf(1), math.Inf(1)
	maxX, maxY := math.Inf(-1), math.Inf(-1)
	for _, raw := range points {
		point, _ := raw.(map[string]any)
		x, xOK := number(point["x"])
		y, yOK := number(point["y"])
		if !xOK || !yOK {
			return 0, 0, 0, 0, fmt.Errorf("%s polygon has an invalid point", path)
		}
		minX = math.Min(minX, x)
		minY = math.Min(minY, y)
		maxX = math.Max(maxX, x)
		maxY = math.Max(maxY, y)
	}
	return minX, minY, maxX, maxY, nil
}

func collisionShapeFromGeometry(
	shape map[string]any,
	path string,
) (validationCollisionShape, error) {
	if shape["type"] == "rectangle" {
		x, _ := number(shape["x"])
		y, _ := number(shape["y"])
		width, _ := number(shape["width"])
		height, _ := number(shape["height"])
		return validationCollisionShape{
			points: rectanglePoints(x, y, width, height),
		}, nil
	}
	rawPoints := anySlice(shape["points"])
	if len(rawPoints) < 3 {
		return validationCollisionShape{}, fmt.Errorf("%s has no polygon", path)
	}
	points := make([]validationPoint, 0, len(rawPoints))
	for _, raw := range rawPoints {
		point, _ := raw.(map[string]any)
		x, _ := number(point["x"])
		y, _ := number(point["y"])
		points = append(points, validationPoint{x: x, y: y})
	}
	return validationCollisionShape{points: points}, nil
}

func collisionShapeFromBody(
	body map[string]any,
	x float64,
	y float64,
	path string,
) (validationCollisionShape, error) {
	switch body["shape"] {
	case "circle":
		radius, _ := number(body["radius"])
		return validationCollisionShape{
			circle: true,
			center: validationPoint{x: x, y: y},
			radius: radius,
		}, nil
	case "rectangle":
		width, _ := number(body["width"])
		height, _ := number(body["height"])
		return validationCollisionShape{
			points: rectanglePoints(x, y, width, height),
		}, nil
	case "polygon":
		points := make([]validationPoint, 0, len(anySlice(body["points"])))
		for _, raw := range anySlice(body["points"]) {
			point, _ := raw.(map[string]any)
			pointX, _ := number(point["x"])
			pointY, _ := number(point["y"])
			points = append(points, validationPoint{
				x: x + pointX,
				y: y + pointY,
			})
		}
		return validationCollisionShape{points: points}, nil
	default:
		return validationCollisionShape{}, fmt.Errorf("%s has unknown shape", path)
	}
}

func rectanglePoints(
	x float64,
	y float64,
	width float64,
	height float64,
) []validationPoint {
	halfWidth := width / 2
	halfHeight := height / 2
	return []validationPoint{
		{x: x - halfWidth, y: y - halfHeight},
		{x: x + halfWidth, y: y - halfHeight},
		{x: x + halfWidth, y: y + halfHeight},
		{x: x - halfWidth, y: y + halfHeight},
	}
}

func collisionShapeBounds(
	shape validationCollisionShape,
) (float64, float64, float64, float64) {
	if shape.circle {
		return shape.center.x - shape.radius,
			shape.center.y - shape.radius,
			shape.center.x + shape.radius,
			shape.center.y + shape.radius
	}
	minX, minY := math.Inf(1), math.Inf(1)
	maxX, maxY := math.Inf(-1), math.Inf(-1)
	for _, point := range shape.points {
		minX = math.Min(minX, point.x)
		minY = math.Min(minY, point.y)
		maxX = math.Max(maxX, point.x)
		maxY = math.Max(maxY, point.y)
	}
	return minX, minY, maxX, maxY
}

func collisionShapesOverlap(
	left validationCollisionShape,
	right validationCollisionShape,
) bool {
	if left.circle && right.circle {
		dx := left.center.x - right.center.x
		dy := left.center.y - right.center.y
		radius := left.radius + right.radius
		return dx*dx+dy*dy < radius*radius
	}
	if left.circle {
		return circleOverlapsPolygon(left, right.points)
	}
	if right.circle {
		return circleOverlapsPolygon(right, left.points)
	}
	return polygonsOverlap(left.points, right.points)
}

func circleOverlapsPolygon(
	circle validationCollisionShape,
	points []validationPoint,
) bool {
	if pointInsidePolygon(circle.center, points) {
		return true
	}
	radiusSquared := circle.radius * circle.radius
	for index, start := range points {
		end := points[(index+1)%len(points)]
		if squaredDistanceToSegment(circle.center, start, end) <
			radiusSquared {
			return true
		}
	}
	return false
}

func polygonsOverlap(left []validationPoint, right []validationPoint) bool {
	for leftIndex, leftStart := range left {
		leftEnd := left[(leftIndex+1)%len(left)]
		for rightIndex, rightStart := range right {
			rightEnd := right[(rightIndex+1)%len(right)]
			if segmentsProperlyIntersect(
				leftStart,
				leftEnd,
				rightStart,
				rightEnd,
			) {
				return true
			}
		}
	}
	return pointInsidePolygon(left[0], right) ||
		pointInsidePolygon(right[0], left)
}

func segmentsProperlyIntersect(
	a validationPoint,
	b validationPoint,
	c validationPoint,
	d validationPoint,
) bool {
	orientation := func(p, q, r validationPoint) float64 {
		return (q.x-p.x)*(r.y-p.y) - (q.y-p.y)*(r.x-p.x)
	}
	abC := orientation(a, b, c)
	abD := orientation(a, b, d)
	cdA := orientation(c, d, a)
	cdB := orientation(c, d, b)
	return abC*abD < 0 && cdA*cdB < 0
}

func pointInsidePolygon(point validationPoint, polygon []validationPoint) bool {
	inside := false
	for index, start := range polygon {
		end := polygon[(index+1)%len(polygon)]
		crosses := (start.y > point.y) != (end.y > point.y)
		if crosses &&
			point.x < (end.x-start.x)*(point.y-start.y)/
				(end.y-start.y)+start.x {
			inside = !inside
		}
	}
	return inside
}

func squaredDistanceToSegment(
	point validationPoint,
	start validationPoint,
	end validationPoint,
) float64 {
	dx := end.x - start.x
	dy := end.y - start.y
	if dx == 0 && dy == 0 {
		dx = point.x - start.x
		dy = point.y - start.y
		return dx*dx + dy*dy
	}
	t := ((point.x-start.x)*dx + (point.y-start.y)*dy) /
		(dx*dx + dy*dy)
	t = math.Max(0, math.Min(1, t))
	nearestX := start.x + t*dx
	nearestY := start.y + t*dy
	dx = point.x - nearestX
	dy = point.y - nearestY
	return dx*dx + dy*dy
}
