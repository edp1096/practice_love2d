// Package gamebuild translates the runtime-neutral content catalog into the
// small deterministic simulation used by the Ebitengine spike.
package gamebuild

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"sort"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

const (
	defaultStageID        = "stage.rpg_village"
	defaultLocaleID       = "locale.ko"
	defaultViewportWidth  = 800
	defaultViewportHeight = 450
	// DefaultPortalActorTag is the semantic input owner used when authored
	// portal content omits actor_tag.
	DefaultPortalActorTag = "player"
)

// ImpactOptions contains presentation policy that currently lives in
// 32_recreate/game/game.lua rather than a content definition.
type ImpactOptions struct {
	DamageShakePixels  float64
	DamageShakeSeconds float64
	ParryShakePixels   float64
	ParryShakeSeconds  float64
}

type Options struct {
	StageID  string
	SpawnID  string
	LocaleID string
	Impact   ImpactOptions
}

// SpawnPoint is a named player-entry location inside one authored stage.
// Coordinates are fixed-point simulation values so a stage transition can
// construct its candidate World without involving a renderer.
type SpawnPoint struct {
	ID       string  `json:"id"`
	Position sim.Vec `json:"position"`
}

// Portal is immutable stage navigation data. Portal overlap and cooldown are
// runtime concerns; target references are validated by the content compiler.
type Portal struct {
	ID            string    `json:"id"`
	Rect          sim.Rect  `json:"rect"`
	Points        []sim.Vec `json:"points,omitempty"`
	ActorTag      string    `json:"actor_tag,omitempty"`
	TargetStageID string    `json:"target_stage_id"`
	TargetSpawnID string    `json:"target_spawn_id"`
	CooldownTicks int       `json:"cooldown_ticks"`
}

// StageBlueprint contains navigation data that must survive independently of
// an individual Simulation instance.
type StageBlueprint struct {
	ID          string       `json:"id"`
	SpawnPoints []SpawnPoint `json:"spawn_points"`
	Portals     []Portal     `json:"portals"`
}

type InstanceMetadata struct {
	ID             string         `json:"id"`
	ActorID        string         `json:"actor_id"`
	SpriteID       string         `json:"sprite_id,omitempty"`
	SpriteScale    float64        `json:"sprite_scale,omitempty"`
	SpriteTint     [4]float64     `json:"sprite_tint,omitempty"`
	SpriteTintSet  bool           `json:"sprite_tint_set,omitempty"`
	Shape          *ShapeMetadata `json:"shape,omitempty"`
	PrimaryAbility string         `json:"primary_ability,omitempty"`
	Controlled     bool           `json:"controlled,omitempty"`
	Chase          *ChaseMetadata `json:"chase,omitempty"`
	Tags           []string       `json:"tags,omitempty"`
}

type ShapeMetadata struct {
	Kind    string   `json:"kind"`
	Color   [4]uint8 `json:"color"`
	Outline [4]uint8 `json:"outline"`
}

type ChaseMetadata struct {
	TargetTag      string  `json:"target_tag"`
	AggroRange     float64 `json:"aggro_range"`
	AttackDistance float64 `json:"attack_distance"`
}

type Presentation struct {
	StageID    string             `json:"stage_id"`
	StageName  string             `json:"stage_name"`
	Background [4]float64         `json:"background"`
	Images     []ImageAsset       `json:"images"`
	Sprites    []SpriteDefinition `json:"sprites"`
	Abilities  []AbilityVisual    `json:"ability_visuals"`
	Audio      AudioPresentation  `json:"audio"`
	Tilemap    *Tilemap           `json:"tilemap,omitempty"`
	Instances  []InstanceMetadata `json:"instances"`
}

func (presentation Presentation) Instance(id string) (InstanceMetadata, bool) {
	index := sort.Search(len(presentation.Instances), func(index int) bool {
		return presentation.Instances[index].ID >= id
	})
	if index == len(presentation.Instances) ||
		presentation.Instances[index].ID != id {
		return InstanceMetadata{}, false
	}
	item := presentation.Instances[index]
	item.Tags = append([]string(nil), item.Tags...)
	if item.Shape != nil {
		shape := *item.Shape
		item.Shape = &shape
	}
	return item, true
}

func (presentation Presentation) AbilityVisual(
	id string,
) (AbilityVisual, bool) {
	index := sort.Search(len(presentation.Abilities), func(index int) bool {
		return presentation.Abilities[index].AbilityID >= id
	})
	if index == len(presentation.Abilities) ||
		presentation.Abilities[index].AbilityID != id {
		return AbilityVisual{}, false
	}
	return presentation.Abilities[index], true
}

type Result struct {
	Config       sim.Config
	Presentation Presentation
	Stage        StageBlueprint
}

type stageDefinition struct {
	SchemaVersion int               `json:"schema_version"`
	Kind          string            `json:"kind"`
	ID            string            `json:"id"`
	Name          string            `json:"name"`
	NameKey       string            `json:"name_key"`
	Width         float64           `json:"width"`
	Height        float64           `json:"height"`
	Background    []float64         `json:"background"`
	Camera        stageCamera       `json:"camera"`
	Spawns        []stageSpawn      `json:"spawns"`
	Walls         []stageWall       `json:"walls"`
	SpawnPoints   []stageSpawnPoint `json:"spawn_points"`
	Portals       []stagePortal     `json:"portals"`
	Encounters    []stageEncounter  `json:"encounters"`
	Tilemap       *stageTilemap     `json:"tilemap,omitempty"`
}

type stageCamera struct {
	FollowTag      string  `json:"follow_tag"`
	ViewportWidth  float64 `json:"viewport_width"`
	ViewportHeight float64 `json:"viewport_height"`
}

type stageSpawn struct {
	ID         string                     `json:"id"`
	Actor      string                     `json:"actor"`
	Name       string                     `json:"name"`
	Tags       []string                   `json:"tags"`
	Components map[string]json.RawMessage `json:"components"`
	Position   stagePosition              `json:"position"`
}

type stagePosition struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

type stageSpawnPoint struct {
	ID string  `json:"id"`
	X  float64 `json:"x"`
	Y  float64 `json:"y"`
}

type stagePortal struct {
	ID          string    `json:"id"`
	Shape       shapeRect `json:"shape"`
	ActorTag    string    `json:"actor_tag"`
	TargetStage string    `json:"target_stage"`
	TargetSpawn string    `json:"target_spawn"`
	Cooldown    float64   `json:"cooldown"`
}

type stageWall struct {
	ID    string    `json:"id"`
	Shape shapeRect `json:"shape"`
}

type stageEncounter struct {
	ID        string        `json:"id"`
	Encounter string        `json:"encounter"`
	Position  stagePosition `json:"position"`
	AutoStart *bool         `json:"auto_start"`
}

type shapePoint struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

type shapeRect struct {
	Type   string       `json:"type"`
	X      float64      `json:"x"`
	Y      float64      `json:"y"`
	Width  float64      `json:"width"`
	Height float64      `json:"height"`
	Points []shapePoint `json:"points"`
}

type actorDefinition struct {
	SchemaVersion int                        `json:"schema_version"`
	Kind          string                     `json:"kind"`
	ID            string                     `json:"id"`
	Name          string                     `json:"name"`
	Tags          []string                   `json:"tags"`
	Components    map[string]json.RawMessage `json:"components"`
}

type bodyComponent struct {
	Shape  string  `json:"shape"`
	Radius float64 `json:"radius"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
	Solid  bool    `json:"solid"`
}

type healthComponent struct {
	Max int `json:"max"`
}

type movementComponent struct {
	Speed float64 `json:"speed"`
}

type platformerComponent struct {
	Speed           float64 `json:"speed"`
	Acceleration    float64 `json:"acceleration"`
	AirAcceleration float64 `json:"air_acceleration"`
	Deceleration    float64 `json:"deceleration"`
	Gravity         float64 `json:"gravity"`
	JumpSpeed       float64 `json:"jump_speed"`
	MaxFallSpeed    float64 `json:"max_fall_speed"`
	CoyoteTime      float64 `json:"coyote_time"`
	JumpBuffer      float64 `json:"jump_buffer"`
}

type combatComponent struct {
	Primary   string   `json:"primary"`
	Team      string   `json:"team"`
	Abilities []string `json:"abilities"`
}

type combatInputComponent struct {
	Bindings []abilityBindingDefinition `json:"bindings"`
}

type abilityBindingDefinition struct {
	Input   string `json:"input"`
	Ability string `json:"ability"`
}

type chaseAIComponent struct {
	TargetTag      string  `json:"target_tag"`
	AggroRange     float64 `json:"aggro_range"`
	AttackDistance float64 `json:"attack_distance"`
}

type reactionComponent struct {
	HitInvulnerability float64 `json:"hit_invulnerability"`
	FlashDuration      float64 `json:"flash_duration"`
}

type dodgeComponent struct {
	Duration        float64 `json:"duration"`
	Distance        float64 `json:"distance"`
	Invulnerability float64 `json:"invulnerability"`
	Cooldown        float64 `json:"cooldown"`
}

type parryComponent struct {
	Window          float64 `json:"window"`
	PerfectWindow   float64 `json:"perfect_window"`
	Cooldown        float64 `json:"cooldown"`
	SuccessCooldown float64 `json:"success_cooldown"`
	ArcDegrees      int     `json:"arc_degrees"`
	Stagger         float64 `json:"stagger"`
	PerfectStagger  float64 `json:"perfect_stagger"`
	Hitstop         float64 `json:"hitstop"`
	PerfectHitstop  float64 `json:"perfect_hitstop"`
}

type renderSpriteComponent struct {
	Sprite string    `json:"sprite"`
	Scale  float64   `json:"scale"`
	Tint   []float64 `json:"tint"`
}

type renderShapeComponent struct {
	Color   []float64 `json:"color"`
	Outline []float64 `json:"outline"`
}

type statusReceiverComponent struct {
	Immune []string `json:"immune"`
}

type rpgStatsComponent struct {
	Attack    *float64 `json:"attack"`
	Defense   *float64 `json:"defense"`
	MoveSpeed *float64 `json:"move_speed"`
}

type interactableComponent struct {
	Range   float64         `json:"range"`
	Actions []contentAction `json:"actions"`
}

type contentAction struct {
	Type     string `json:"type"`
	Dialogue string `json:"dialogue"`
	Quest    string `json:"quest"`
	Name     string `json:"name"`
	Status   string `json:"status"`
}

type encounterDefinition struct {
	SchemaVersion int             `json:"schema_version"`
	Kind          string          `json:"kind"`
	ID            string          `json:"id"`
	TargetTag     string          `json:"target_tag"`
	Waves         []encounterWave `json:"waves"`
	OnComplete    []contentAction `json:"on_complete"`
}

type encounterWave struct {
	ID         string               `json:"id"`
	Delay      float64              `json:"delay"`
	Spawns     []stageSpawn         `json:"spawns"`
	BossPhases []encounterBossPhase `json:"boss_phases"`
	OnStart    []contentAction      `json:"on_start"`
	OnComplete []contentAction      `json:"on_complete"`
}

type encounterBossPhase struct {
	ID                string          `json:"id"`
	Spawn             string          `json:"spawn"`
	HealthRatioAtMost float64         `json:"health_ratio_at_most"`
	Actions           []contentAction `json:"actions"`
}

type abilityDefinition struct {
	SchemaVersion int                    `json:"schema_version"`
	Kind          string                 `json:"kind"`
	ID            string                 `json:"id"`
	Windup        float64                `json:"windup"`
	Duration      float64                `json:"duration"`
	Recovery      float64                `json:"recovery"`
	Cooldown      float64                `json:"cooldown"`
	LockMovement  bool                   `json:"lock_movement"`
	Hitbox        abilityHitbox          `json:"hitbox"`
	Effects       []abilityEffect        `json:"effects"`
	Activation    []abilityActivation    `json:"activation"`
	Visual        *authoredAbilityVisual `json:"visual"`
}

type authoredAbilityVisual struct {
	Asset          string  `json:"asset"`
	Scale          float64 `json:"scale"`
	Distance       float64 `json:"distance"`
	RotationOffset float64 `json:"rotation_offset"`
}

type abilityHitbox struct {
	Shape          string  `json:"shape"`
	Reach          float64 `json:"reach"`
	ArcDegrees     int     `json:"arc_degrees"`
	RepeatInterval float64 `json:"repeat_interval"`
	MaxHits        int     `json:"max_hits"`
}

type abilityActivation struct {
	Type       string `json:"type"`
	Projectile string `json:"projectile"`
}

type abilityEffect struct {
	Type     string  `json:"type"`
	Amount   int     `json:"amount"`
	Duration float64 `json:"duration"`
	Distance float64 `json:"distance"`
	Status   string  `json:"status"`
}

type projectileDefinition struct {
	SchemaVersion int             `json:"schema_version"`
	Kind          string          `json:"kind"`
	ID            string          `json:"id"`
	Actor         string          `json:"actor"`
	Speed         float64         `json:"speed"`
	Lifetime      float64         `json:"lifetime"`
	SpawnOffset   float64         `json:"spawn_offset"`
	Pierce        int             `json:"pierce"`
	DestroyOnWall *bool           `json:"destroy_on_wall"`
	Effects       []abilityEffect `json:"effects"`
}

type statusDefinition struct {
	SchemaVersion int             `json:"schema_version"`
	Kind          string          `json:"kind"`
	ID            string          `json:"id"`
	Duration      float64         `json:"duration"`
	Stacking      string          `json:"stacking"`
	MaxStacks     int             `json:"max_stacks"`
	TickInterval  float64         `json:"tick_interval"`
	TickActions   []abilityEffect `json:"tick_actions"`
	Modifiers     struct {
		MoveSpeed   float64 `json:"move_speed"`
		DamageDealt float64 `json:"damage_dealt"`
		DamageTaken float64 `json:"damage_taken"`
	} `json:"modifiers"`
	Color []float64 `json:"color"`
}

type dialogueDefinition struct {
	SchemaVersion int                     `json:"schema_version"`
	Kind          string                  `json:"kind"`
	ID            string                  `json:"id"`
	Start         string                  `json:"start"`
	Nodes         map[string]dialogueNode `json:"nodes"`
}

type dialogueNode struct {
	SpeakerKey string           `json:"speaker_key"`
	TextKey    string           `json:"text_key"`
	Actions    []contentAction  `json:"actions"`
	Choices    []dialogueChoice `json:"choices"`
}

type dialogueChoice struct {
	Actions []contentAction `json:"actions"`
}

type questDefinition struct {
	SchemaVersion int              `json:"schema_version"`
	Kind          string           `json:"kind"`
	ID            string           `json:"id"`
	Objectives    []questObjective `json:"objectives"`
}

type questObjective struct {
	Event string `json:"event"`
	Count int    `json:"count"`
	Where struct {
		ActorID string `json:"actor_id"`
	} `json:"where"`
}

type localeDefinition struct {
	SchemaVersion int               `json:"schema_version"`
	Kind          string            `json:"kind"`
	ID            string            `json:"id"`
	Strings       map[string]string `json:"strings"`
}

// Build resolves one authored stage into deterministic simulation data.
func Build(catalog *content.Catalog, options Options) (*Result, error) {
	if catalog == nil {
		return nil, errors.New("gamebuild: catalog is required")
	}
	if err := catalog.ValidateProjectReferences(); err != nil {
		return nil, fmt.Errorf("gamebuild: invalid project manifest: %w", err)
	}
	applyDefaults(&options)

	var stage stageDefinition
	if err := catalog.Decode(options.StageID, &stage); err != nil {
		return nil, err
	}
	if err := validateHeader(stage.SchemaVersion, stage.Kind, stage.ID,
		"stage", options.StageID); err != nil {
		return nil, err
	}
	strings, err := loadLocaleStrings(catalog, options.LocaleID)
	if err != nil {
		return nil, err
	}
	if !positiveFinite(stage.Width) || !positiveFinite(stage.Height) {
		return nil, fmt.Errorf("%s has invalid dimensions", stage.ID)
	}
	if stage.Camera == (stageCamera{}) {
		stage.Camera.ViewportWidth = defaultViewportWidth
		stage.Camera.ViewportHeight = defaultViewportHeight
	}
	if !positiveFinite(stage.Camera.ViewportWidth) ||
		!positiveFinite(stage.Camera.ViewportHeight) {
		return nil, fmt.Errorf("%s has invalid camera viewport", stage.ID)
	}
	if stage.Camera.ViewportWidth > stage.Width ||
		stage.Camera.ViewportHeight > stage.Height {
		return nil, fmt.Errorf(
			"%s camera viewport %.6gx%.6g exceeds stage bounds %.6gx%.6g",
			stage.ID,
			stage.Camera.ViewportWidth,
			stage.Camera.ViewportHeight,
			stage.Width,
			stage.Height,
		)
	}

	result := &Result{
		Config: sim.Config{
			StageBounds: sim.Rect{
				MaxX: pixels(stage.Width),
				MaxY: pixels(stage.Height),
			},
			Camera: sim.CameraConfig{
				ViewportWidth:  pixels(stage.Camera.ViewportWidth),
				ViewportHeight: pixels(stage.Camera.ViewportHeight),
			},
		},
		Presentation: Presentation{
			StageID:   stage.ID,
			StageName: localized(strings, stage.NameKey, stage.Name),
		},
		Stage: StageBlueprint{ID: stage.ID},
	}
	result.Presentation.Images, err = buildImageAssets(catalog)
	if err != nil {
		return nil, fmt.Errorf("%s image resources: %w", stage.ID, err)
	}
	result.Presentation.Sprites, err = buildSpriteDefinitions(catalog)
	if err != nil {
		return nil, fmt.Errorf("%s sprite resources: %w", stage.ID, err)
	}
	result.Presentation.Abilities, err = buildAbilityVisuals(catalog)
	if err != nil {
		return nil, fmt.Errorf("%s ability visuals: %w", stage.ID, err)
	}
	result.Presentation.Audio, err = buildAudioPresentation(catalog)
	if err != nil {
		return nil, fmt.Errorf("%s audio presentation: %w", stage.ID, err)
	}
	result.Presentation.Tilemap, err = buildTilemap(
		stage.Tilemap,
		result.Presentation.Images,
	)
	if err != nil {
		return nil, fmt.Errorf("%s tilemap: %w", stage.ID, err)
	}
	result.Config.Statuses, result.Config.Projectiles, err =
		buildRuntimeCombatContent(catalog, options.Impact)
	if err != nil {
		return nil, fmt.Errorf("%s action content: %w", stage.ID, err)
	}
	for index := range min(len(stage.Background), 4) {
		value := stage.Background[index]
		if !finite(value) || value < 0 || value > 1 {
			return nil, fmt.Errorf("%s background[%d] is invalid", stage.ID, index)
		}
		result.Presentation.Background[index] = value
	}
	if result.Presentation.Background[3] == 0 {
		result.Presentation.Background[3] = 1
	}

	var selectedSpawn *SpawnPoint
	seenSpawnPoints := make(map[string]struct{}, len(stage.SpawnPoints))
	for _, authored := range stage.SpawnPoints {
		if authored.ID == "" || !finite(authored.X) || !finite(authored.Y) {
			return nil, fmt.Errorf("%s has an invalid spawn point", stage.ID)
		}
		if _, duplicate := seenSpawnPoints[authored.ID]; duplicate {
			return nil, fmt.Errorf(
				"%s duplicates spawn point %q",
				stage.ID,
				authored.ID,
			)
		}
		seenSpawnPoints[authored.ID] = struct{}{}
		converted := SpawnPoint{
			ID: authored.ID,
			Position: sim.Vec{
				X: pixels(authored.X),
				Y: pixels(authored.Y),
			},
		}
		result.Stage.SpawnPoints = append(result.Stage.SpawnPoints, converted)
		if options.SpawnID == authored.ID {
			copy := converted
			selectedSpawn = &copy
		}
	}
	implicitAuthoredSpawn := options.SpawnID == implicitEntrySpawnID &&
		len(stage.SpawnPoints) == 0
	if options.SpawnID != "" && selectedSpawn == nil && !implicitAuthoredSpawn {
		return nil, fmt.Errorf(
			"%s has no spawn point %q",
			stage.ID,
			options.SpawnID,
		)
	}
	sort.Slice(result.Stage.SpawnPoints, func(i, j int) bool {
		return result.Stage.SpawnPoints[i].ID < result.Stage.SpawnPoints[j].ID
	})

	seenPortals := make(map[string]struct{}, len(stage.Portals))
	for _, authored := range stage.Portals {
		if authored.ID == "" || authored.TargetStage == "" ||
			authored.TargetSpawn == "" || !finite(authored.Cooldown) ||
			authored.Cooldown < 0 ||
			!durationFitsPortableTicks(authored.Cooldown) {
			return nil, fmt.Errorf("%s has an invalid portal %q", stage.ID, authored.ID)
		}
		if _, duplicate := seenPortals[authored.ID]; duplicate {
			return nil, fmt.Errorf(
				"%s duplicates portal %q",
				stage.ID,
				authored.ID,
			)
		}
		seenPortals[authored.ID] = struct{}{}
		geometry, err := convertShape(
			stage.ID+" portal "+authored.ID,
			authored.ID,
			authored.Shape,
		)
		if err != nil {
			return nil, err
		}
		result.Stage.Portals = append(result.Stage.Portals, Portal{
			ID:            authored.ID,
			Rect:          geometry.Rect,
			Points:        geometry.Points,
			ActorTag:      authored.ActorTag,
			TargetStageID: authored.TargetStage,
			TargetSpawnID: authored.TargetSpawn,
			CooldownTicks: secondsToTicks(authored.Cooldown),
		})
	}
	sort.Slice(result.Stage.Portals, func(i, j int) bool {
		return result.Stage.Portals[i].ID < result.Stage.Portals[j].ID
	})

	seenWalls := make(map[string]struct{}, len(stage.Walls))
	for _, wall := range stage.Walls {
		if _, duplicate := seenWalls[wall.ID]; duplicate {
			return nil, fmt.Errorf(
				"%s duplicates wall %q",
				stage.ID,
				wall.ID,
			)
		}
		seenWalls[wall.ID] = struct{}{}
		converted, err := convertWall(stage.ID, wall)
		if err != nil {
			return nil, err
		}
		result.Config.Walls = append(result.Config.Walls, converted)
	}

	dialogues := make(map[string]sim.DialogueDefinition)
	quests := make(map[string]sim.QuestDefinition)
	seenInstances := make(map[string]struct{}, len(stage.Spawns))
	controlledID := ""
	for _, spawn := range stage.Spawns {
		if spawn.ID == "" || spawn.Actor == "" {
			return nil, fmt.Errorf("%s has a spawn without id or actor", stage.ID)
		}
		if _, exists := seenInstances[spawn.ID]; exists {
			return nil, fmt.Errorf("%s duplicates spawn %q", stage.ID, spawn.ID)
		}
		seenInstances[spawn.ID] = struct{}{}
		entity, metadata, dialogue, quest, interactionRange, err :=
			buildEntity(catalog, strings, spawn, options.Impact)
		if err != nil {
			return nil, fmt.Errorf("%s spawn %q: %w", stage.ID, spawn.ID, err)
		}
		if entity.Controlled {
			if controlledID != "" {
				return nil, fmt.Errorf("%s has more than one controlled actor", stage.ID)
			}
			if selectedSpawn != nil {
				entity.Position = selectedSpawn.Position
			}
			controlledID = entity.ID
		}
		result.Config.Entities = append(result.Config.Entities, entity)
		result.Presentation.Instances = append(
			result.Presentation.Instances,
			metadata,
		)
		if interactionRange > result.Config.InteractionRange {
			result.Config.InteractionRange = interactionRange
		}
		if dialogue != nil {
			dialogues[dialogue.ID] = *dialogue
		}
		if quest != nil {
			quests[quest.ID] = *quest
		}
	}
	if controlledID == "" {
		return nil, fmt.Errorf("%s has no controlled actor", stage.ID)
	}
	var controlledMetadata InstanceMetadata
	for _, metadata := range result.Presentation.Instances {
		if metadata.ID == controlledID {
			controlledMetadata = metadata
			break
		}
	}
	for _, portal := range result.Stage.Portals {
		actorTag := portal.ActorTag
		if actorTag == "" {
			actorTag = DefaultPortalActorTag
		}
		if !containsTag(controlledMetadata.Tags, actorTag) {
			return nil, fmt.Errorf(
				"%s portal %q actor_tag %q does not match controlled actor %q",
				stage.ID,
				portal.ID,
				actorTag,
				controlledID,
			)
		}
	}
	cameraTarget := controlledID
	if stage.Camera.FollowTag != "" {
		cameraTarget = ""
		for _, metadata := range result.Presentation.Instances {
			if !containsTag(metadata.Tags, stage.Camera.FollowTag) {
				continue
			}
			if cameraTarget != "" {
				return nil, fmt.Errorf(
					"%s camera follow_tag %q matches more than one actor",
					stage.ID,
					stage.Camera.FollowTag,
				)
			}
			cameraTarget = metadata.ID
		}
		if cameraTarget == "" {
			return nil, fmt.Errorf(
				"%s camera follow_tag %q matches no actor",
				stage.ID,
				stage.Camera.FollowTag,
			)
		}
	}
	result.Config.Camera.TargetEntityID = cameraTarget
	encounters, encounterMetadata, encounterRange, err :=
		buildEncounterPlacements(
			catalog,
			strings,
			stage.Encounters,
			options.Impact,
			seenInstances,
			result.Presentation.Instances,
			dialogues,
			quests,
		)
	if err != nil {
		return nil, fmt.Errorf("%s encounters: %w", stage.ID, err)
	}
	result.Config.Encounters = encounters
	result.Presentation.Instances = append(
		result.Presentation.Instances,
		encounterMetadata...,
	)
	result.Config.InteractionRange = max(
		result.Config.InteractionRange,
		encounterRange,
	)
	for _, value := range dialogues {
		result.Config.Dialogues = append(result.Config.Dialogues, value)
	}
	for _, value := range quests {
		result.Config.Quests = append(result.Config.Quests, value)
	}
	sort.Slice(result.Config.Dialogues, func(i, j int) bool {
		return result.Config.Dialogues[i].ID < result.Config.Dialogues[j].ID
	})
	sort.Slice(result.Config.Quests, func(i, j int) bool {
		return result.Config.Quests[i].ID < result.Config.Quests[j].ID
	})
	sort.Slice(result.Presentation.Instances, func(i, j int) bool {
		return result.Presentation.Instances[i].ID <
			result.Presentation.Instances[j].ID
	})
	return result, nil
}

func containsTag(tags []string, wanted string) bool {
	for _, tag := range tags {
		if tag == wanted {
			return true
		}
	}
	return false
}

func mergeTags(base []string, overrides []string) ([]string, error) {
	seen := make(map[string]struct{}, len(base)+len(overrides))
	result := make([]string, 0, len(base)+len(overrides))
	for _, values := range [][]string{base, overrides} {
		for _, tag := range values {
			if tag == "" {
				return nil, errors.New("entity tag must not be empty")
			}
			if _, duplicate := seen[tag]; duplicate {
				continue
			}
			seen[tag] = struct{}{}
			result = append(result, tag)
		}
	}
	sort.Strings(result)
	return result, nil
}

func cloneRawMessages(
	source map[string]json.RawMessage,
) map[string]json.RawMessage {
	if source == nil {
		return nil
	}
	result := make(map[string]json.RawMessage, len(source))
	for key, value := range source {
		result[key] = append(json.RawMessage(nil), value...)
	}
	return result
}

func mergeComponentConfigs(
	base map[string]json.RawMessage,
	overrides map[string]json.RawMessage,
) (map[string]json.RawMessage, error) {
	result := cloneRawMessages(base)
	if result == nil {
		result = make(map[string]json.RawMessage)
	}
	for name, overrideRaw := range overrides {
		if name == "" {
			return nil, errors.New("component override name must not be empty")
		}
		override, err := decodeJSONObject(
			overrideRaw,
			fmt.Sprintf("component override %q", name),
		)
		if err != nil {
			return nil, err
		}
		baseRaw, exists := result[name]
		if !exists {
			encoded, err := json.Marshal(override)
			if err != nil {
				return nil, fmt.Errorf(
					"encode component override %q: %w",
					name,
					err,
				)
			}
			result[name] = encoded
			continue
		}
		baseObject, err := decodeJSONObject(
			baseRaw,
			fmt.Sprintf("actor component %q", name),
		)
		if err != nil {
			return nil, err
		}
		merged := mergeJSONValue(baseObject, override)
		encoded, err := json.Marshal(merged)
		if err != nil {
			return nil, fmt.Errorf(
				"encode merged component %q: %w",
				name,
				err,
			)
		}
		result[name] = encoded
	}
	return result, nil
}

func decodeJSONObject(
	raw json.RawMessage,
	label string,
) (map[string]any, error) {
	var result map[string]any
	if len(raw) == 0 {
		return nil, fmt.Errorf("%s must be a JSON object", label)
	}
	if err := json.Unmarshal(raw, &result); err != nil {
		return nil, fmt.Errorf("%s must be a JSON object: %w", label, err)
	}
	if result == nil {
		return nil, fmt.Errorf("%s must be a JSON object", label)
	}
	return result, nil
}

// mergeJSONValue mirrors the recursive table merge used by 32_recreate.
// Objects merge by key and arrays merge by index; other values replace.
func mergeJSONValue(base any, override any) any {
	switch typed := override.(type) {
	case map[string]any:
		result := make(map[string]any, len(typed))
		if baseObject, ok := base.(map[string]any); ok {
			for key, value := range baseObject {
				result[key] = value
			}
		}
		for key, value := range typed {
			if current, exists := result[key]; exists {
				result[key] = mergeJSONValue(current, value)
			} else {
				result[key] = value
			}
		}
		return result
	case []any:
		result := make([]any, 0, len(typed))
		if baseArray, ok := base.([]any); ok {
			result = append(result, baseArray...)
		}
		if len(result) < len(typed) {
			result = append(result, make([]any, len(typed)-len(result))...)
		}
		for index, value := range typed {
			if index < len(result) && result[index] != nil {
				result[index] = mergeJSONValue(result[index], value)
			} else {
				result[index] = value
			}
		}
		return result
	default:
		return override
	}
}

func applyDefaults(options *Options) {
	if options.StageID == "" {
		options.StageID = defaultStageID
	}
	if options.LocaleID == "" {
		options.LocaleID = defaultLocaleID
	}
	if options.Impact.DamageShakePixels == 0 {
		options.Impact.DamageShakePixels = 5
	}
	if options.Impact.DamageShakeSeconds == 0 {
		options.Impact.DamageShakeSeconds = 0.13
	}
	if options.Impact.ParryShakePixels == 0 {
		options.Impact.ParryShakePixels = 7
	}
	if options.Impact.ParryShakeSeconds == 0 {
		options.Impact.ParryShakeSeconds = 0.17
	}
}

func loadLocaleStrings(
	catalog *content.Catalog,
	id string,
) (map[string]string, error) {
	var locale localeDefinition
	if err := catalog.Decode(id, &locale); err != nil {
		return nil, err
	}
	if err := validateHeader(
		locale.SchemaVersion,
		locale.Kind,
		locale.ID,
		"locale",
		id,
	); err != nil {
		return nil, err
	}
	result := make(map[string]string, len(locale.Strings))
	for key, value := range locale.Strings {
		result[key] = value
	}
	return result, nil
}

func buildEntity(
	catalog *content.Catalog,
	strings map[string]string,
	spawn stageSpawn,
	impact ImpactOptions,
) (
	sim.EntityConfig,
	InstanceMetadata,
	*sim.DialogueDefinition,
	*sim.QuestDefinition,
	sim.Coord,
	error,
) {
	var actor actorDefinition
	if err := catalog.Decode(spawn.Actor, &actor); err != nil {
		return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0, err
	}
	if err := validateHeader(actor.SchemaVersion, actor.Kind, actor.ID,
		"actor", spawn.Actor); err != nil {
		return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0, err
	}
	if !finite(spawn.Position.X) || !finite(spawn.Position.Y) {
		return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
			errors.New("entity position must be finite")
	}
	components, err := mergeComponentConfigs(
		actor.Components,
		spawn.Components,
	)
	if err != nil {
		return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0, err
	}
	actor.Components = components
	bodyRaw, exists := actor.Components["body"]
	if !exists {
		return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
			errors.New("actor has no body component")
	}
	var body bodyComponent
	if err := json.Unmarshal(bodyRaw, &body); err != nil {
		return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
			fmt.Errorf("decode body: %w", err)
	}
	var halfWidth, halfHeight sim.Coord
	switch body.Shape {
	case "circle":
		if !positiveFinite(body.Radius) {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
				fmt.Errorf("circle body requires a positive radius")
		}
		halfWidth = pixels(body.Radius)
		halfHeight = pixels(body.Radius)
	case "rectangle":
		if !positiveFinite(body.Width) || !positiveFinite(body.Height) {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
				fmt.Errorf("rectangle body requires positive width and height")
		}
		halfWidth = pixels(body.Width / 2)
		halfHeight = pixels(body.Height / 2)
	default:
		return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
			fmt.Errorf("unsupported body shape %q", body.Shape)
	}
	convertedBody := sim.Body{
		HalfWidth:  halfWidth,
		HalfHeight: halfHeight,
		Solid:      body.Solid,
	}
	if err := sim.ValidateBody(convertedBody); err != nil {
		return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
			fmt.Errorf("invalid %s body: %w", body.Shape, err)
	}
	entity := sim.EntityConfig{
		ID:        spawn.ID,
		Kind:      actor.ID,
		Name:      actor.Name,
		Position:  sim.Vec{X: pixels(spawn.Position.X), Y: pixels(spawn.Position.Y)},
		Body:      convertedBody,
		MaxHealth: 1,
		Facing:    sim.Vec{X: sim.UnitsPerPixel},
	}
	if spawn.Name != "" {
		entity.Name = spawn.Name
	}
	if entity.Name == "" {
		entity.Name = spawn.ID
	}
	tags, err := mergeTags(actor.Tags, spawn.Tags)
	if err != nil {
		return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0, err
	}
	metadata := InstanceMetadata{
		ID:      spawn.ID,
		ActorID: actor.ID,
		Tags:    tags,
	}
	if _, exists := actor.Components["control.player"]; exists {
		entity.Controlled = true
		metadata.Controlled = true
	}
	if raw := actor.Components["action.health"]; raw != nil {
		var health healthComponent
		if err := json.Unmarshal(raw, &health); err != nil || health.Max <= 0 {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
				fmt.Errorf("invalid action.health")
		}
		entity.MaxHealth = health.Max
	}
	if raw := actor.Components["movement.topdown"]; raw != nil {
		var movement movementComponent
		if err := json.Unmarshal(raw, &movement); err != nil ||
			!positiveFinite(movement.Speed) {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
				fmt.Errorf("invalid movement.topdown")
		}
		entity.MovePerTick = rateToCoord(movement.Speed)
	}
	if raw := actor.Components["movement.platformer"]; raw != nil {
		var movement platformerComponent
		if err := json.Unmarshal(raw, &movement); err != nil ||
			!positiveFinite(movement.Speed) ||
			!positiveFinite(movement.Acceleration) ||
			!positiveFinite(movement.AirAcceleration) ||
			!positiveFinite(movement.Deceleration) ||
			!positiveFinite(movement.Gravity) ||
			!positiveFinite(movement.JumpSpeed) ||
			!positiveFinite(movement.MaxFallSpeed) ||
			!durationFitsPortableTicks(movement.CoyoteTime) ||
			!durationFitsPortableTicks(movement.JumpBuffer) {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
				fmt.Errorf("invalid movement.platformer")
		}
		if entity.MovePerTick != 0 {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
				fmt.Errorf(
					"actor cannot combine movement.topdown and movement.platformer",
				)
		}
		entity.Platformer = &sim.PlatformerConfig{
			MaxSpeedPerTick:     rateToCoord(movement.Speed),
			AccelerationPerTick: accelerationToCoord(movement.Acceleration),
			AirAcceleration:     accelerationToCoord(movement.AirAcceleration),
			DecelerationPerTick: accelerationToCoord(movement.Deceleration),
			GravityPerTick:      accelerationToCoord(movement.Gravity),
			JumpSpeedPerTick:    rateToCoord(movement.JumpSpeed),
			MaxFallSpeedPerTick: rateToCoord(movement.MaxFallSpeed),
			CoyoteTicks:         secondsToTicks(movement.CoyoteTime),
			JumpBufferTicks:     secondsToTicks(movement.JumpBuffer),
		}
	}
	if raw := actor.Components["render.sprite"]; raw != nil {
		var renderer renderSpriteComponent
		if err := json.Unmarshal(raw, &renderer); err != nil ||
			renderer.Sprite == "" {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
				fmt.Errorf("invalid render.sprite")
		}
		if _, exists := catalog.Definition(renderer.Sprite); !exists {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
				fmt.Errorf("unknown sprite %q", renderer.Sprite)
		}
		metadata.SpriteID = renderer.Sprite
		metadata.SpriteScale = renderer.Scale
		if len(renderer.Tint) != 0 {
			tint, err := rgba(renderer.Tint)
			if err != nil {
				return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
					fmt.Errorf("invalid render.sprite tint: %w", err)
			}
			metadata.SpriteTint = tint
			metadata.SpriteTintSet = true
		}
	}
	if raw := actor.Components["render.shape"]; raw != nil {
		var renderer renderShapeComponent
		if err := json.Unmarshal(raw, &renderer); err != nil {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
				fmt.Errorf("invalid render.shape")
		}
		fill, err := rgba8(renderer.Color)
		if err != nil {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
				fmt.Errorf("invalid render.shape color: %w", err)
		}
		outline := [4]uint8{}
		if len(renderer.Outline) != 0 {
			outline, err = rgba8(renderer.Outline)
			if err != nil {
				return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
					fmt.Errorf("invalid render.shape outline: %w", err)
			}
		}
		metadata.Shape = &ShapeMetadata{
			Kind:    body.Shape,
			Color:   fill,
			Outline: outline,
		}
	}
	if raw := actor.Components["action.reaction"]; raw != nil {
		var reaction reactionComponent
		if err := json.Unmarshal(raw, &reaction); err != nil {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0, err
		}
		entity.Reaction = sim.ReactionConfig{
			HitInvulnerabilityTicks: secondsToTicks(reaction.HitInvulnerability),
			FlashTicks:              secondsToTicks(reaction.FlashDuration),
		}
	}
	if raw := actor.Components["action.dodge"]; raw != nil {
		var dodge dodgeComponent
		if err := json.Unmarshal(raw, &dodge); err != nil {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0, err
		}
		entity.Dodge = &sim.DodgeConfig{
			DurationTicks:        secondsToTicks(dodge.Duration),
			Distance:             pixels(dodge.Distance),
			InvulnerabilityTicks: secondsToTicks(dodge.Invulnerability),
			CooldownTicks:        secondsToTicks(dodge.Cooldown),
		}
	}
	if raw := actor.Components["action.parry"]; raw != nil {
		var parry parryComponent
		if err := json.Unmarshal(raw, &parry); err != nil {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0, err
		}
		entity.Parry = &sim.ParryConfig{
			WindowTicks:          secondsToTicks(parry.Window),
			PerfectWindowTicks:   secondsToTicks(parry.PerfectWindow),
			CooldownTicks:        secondsToTicks(parry.Cooldown),
			SuccessCooldownTicks: secondsToTicks(parry.SuccessCooldown),
			ArcDegrees:           parry.ArcDegrees,
			StaggerTicks:         secondsToTicks(parry.Stagger),
			PerfectStaggerTicks:  secondsToTicks(parry.PerfectStagger),
			HitstopTicks:         secondsToTicks(parry.Hitstop),
			PerfectHitstopTicks:  secondsToTicks(parry.PerfectHitstop),
			CameraShake:          pixels(impact.ParryShakePixels),
			CameraShakeTicks:     secondsToTicks(impact.ParryShakeSeconds),
		}
	}
	if raw := actor.Components["action.status"]; raw != nil {
		var receiver statusReceiverComponent
		if err := json.Unmarshal(raw, &receiver); err != nil {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
				fmt.Errorf("invalid action.status")
		}
		entity.Status = &sim.StatusReceiverConfig{
			Immune: append([]string(nil), receiver.Immune...),
		}
	}
	if raw := actor.Components["rpg.stats"]; raw != nil {
		var authored rpgStatsComponent
		if err := json.Unmarshal(raw, &authored); err != nil {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
				fmt.Errorf("invalid rpg.stats: %w", err)
		}
		stats, err := buildRPGStats(authored)
		if err != nil {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
				fmt.Errorf("invalid rpg.stats: %w", err)
		}
		entity.Stats = &stats
	}
	if raw := actor.Components["action.combat"]; raw != nil {
		var combat combatComponent
		if err := json.Unmarshal(raw, &combat); err != nil ||
			combat.Primary == "" || combat.Team == "" {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
				fmt.Errorf("invalid action.combat")
		}
		abilityIDs := append([]string(nil), combat.Abilities...)
		if len(abilityIDs) == 0 {
			abilityIDs = []string{combat.Primary}
		}
		loadout := &sim.CombatConfig{
			PrimaryAbilityID: combat.Primary,
		}
		for _, abilityID := range abilityIDs {
			ability, err := buildAbility(catalog, abilityID, impact)
			if err != nil {
				return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0, err
			}
			loadout.Abilities = append(loadout.Abilities, *ability)
		}
		if raw := actor.Components["action.combat_input"]; raw != nil {
			var input combatInputComponent
			if err := json.Unmarshal(raw, &input); err != nil {
				return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
					fmt.Errorf("invalid action.combat_input")
			}
			for _, binding := range input.Bindings {
				loadout.Bindings = append(loadout.Bindings, sim.AbilityBinding{
					Input:     binding.Input,
					AbilityID: binding.Ability,
				})
			}
		}
		if len(loadout.Bindings) == 0 {
			loadout.Bindings = []sim.AbilityBinding{{
				Input:     "attack",
				AbilityID: combat.Primary,
			}}
		}
		entity.Team = combat.Team
		entity.Combat = loadout
		metadata.PrimaryAbility = combat.Primary
		if combat.Team == "enemy" {
			entity.Facing = sim.Vec{X: -sim.UnitsPerPixel}
		}
	}
	if raw := actor.Components["action.chase_ai"]; raw != nil {
		var chase chaseAIComponent
		if err := json.Unmarshal(raw, &chase); err != nil ||
			chase.TargetTag == "" ||
			!positiveFinite(chase.AggroRange) ||
			!positiveFinite(chase.AttackDistance) ||
			chase.AttackDistance > chase.AggroRange {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
				fmt.Errorf("invalid action.chase_ai")
		}
		metadata.Chase = &ChaseMetadata{
			TargetTag:      chase.TargetTag,
			AggroRange:     chase.AggroRange,
			AttackDistance: chase.AttackDistance,
		}
	}

	var dialogue *sim.DialogueDefinition
	var quest *sim.QuestDefinition
	var interactionRange sim.Coord
	if raw := actor.Components["rpg.interactable"]; raw != nil {
		var interaction interactableComponent
		if err := json.Unmarshal(raw, &interaction); err != nil ||
			!positiveFinite(interaction.Range) {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
				fmt.Errorf("invalid rpg.interactable")
		}
		interactionRange = pixels(interaction.Range)
		for _, action := range interaction.Actions {
			if action.Type == "start_dialogue" {
				entity.DialogueID = action.Dialogue
				break
			}
		}
		if entity.DialogueID != "" {
			bundle, err := buildDialoguePreview(
				catalog,
				strings,
				entity.DialogueID,
			)
			if err != nil {
				return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0, err
			}
			dialogue = &bundle.Dialogue
			quest = bundle.Quest
			if quest != nil && bundle.StartQuestOnOpen {
				entity.StartQuestID = quest.ID
			}
		}
	}
	return entity, metadata, dialogue, quest, interactionRange, nil
}

func buildRPGStats(authored rpgStatsComponent) (
	sim.RPGStatsConfig,
	error,
) {
	result := sim.RPGStatsConfig{MoveSpeed: sim.UnitsPerPixel}
	for _, field := range []struct {
		name   string
		value  *float64
		target *int
	}{
		{name: "attack", value: authored.Attack, target: &result.Attack},
		{name: "defense", value: authored.Defense, target: &result.Defense},
	} {
		if field.value == nil {
			continue
		}
		if !finite(*field.value) ||
			*field.value < 0 ||
			math.Trunc(*field.value) != *field.value ||
			*field.value > float64(campaign.MaxJSONInteger) ||
			*field.value > float64(1<<31-1) {
			return sim.RPGStatsConfig{}, fmt.Errorf(
				"%s must be a non-negative portable integer",
				field.name,
			)
		}
		*field.target = int(*field.value)
	}
	if authored.MoveSpeed != nil {
		if !finite(*authored.MoveSpeed) ||
			*authored.MoveSpeed <= 0 ||
			*authored.MoveSpeed > 16 {
			return sim.RPGStatsConfig{}, errors.New(
				"move_speed must be positive, finite, and at most 16",
			)
		}
		result.MoveSpeed = sim.Coord(math.Round(
			*authored.MoveSpeed * float64(sim.UnitsPerPixel),
		))
		if result.MoveSpeed <= 0 {
			return sim.RPGStatsConfig{}, errors.New(
				"move_speed is below fixed-point precision",
			)
		}
	}
	return result, nil
}

func buildAbility(
	catalog *content.Catalog,
	id string,
	impact ImpactOptions,
) (*sim.AbilityConfig, error) {
	var ability abilityDefinition
	if err := catalog.Decode(id, &ability); err != nil {
		return nil, err
	}
	if err := validateHeader(ability.SchemaVersion, ability.Kind, ability.ID,
		"ability", id); err != nil {
		return nil, err
	}
	result := &sim.AbilityConfig{
		ID:               id,
		WindupTicks:      secondsToTicks(ability.Windup),
		ActiveTicks:      secondsToTicks(ability.Duration),
		RecoveryTicks:    secondsToTicks(ability.Recovery),
		CooldownTicks:    secondsToTicks(ability.Cooldown),
		LockMovement:     ability.LockMovement,
		CameraShake:      pixels(impact.DamageShakePixels),
		CameraShakeTicks: secondsToTicks(impact.DamageShakeSeconds),
		MaxHits:          1,
	}
	if ability.Hitbox.Shape != "" {
		if ability.Hitbox.Shape != "arc" ||
			!positiveFinite(ability.Hitbox.Reach) ||
			ability.Hitbox.ArcDegrees < 1 ||
			ability.Hitbox.ArcDegrees > 360 {
			return nil, fmt.Errorf("%s has unsupported hitbox", id)
		}
		result.Reach = pixels(ability.Hitbox.Reach)
		result.ArcDegrees = ability.Hitbox.ArcDegrees
		if ability.Hitbox.MaxHits > 0 {
			result.MaxHits = ability.Hitbox.MaxHits
		}
		if ability.Hitbox.RepeatInterval > 0 {
			result.RepeatIntervalTicks = secondsToTicks(
				ability.Hitbox.RepeatInterval,
			)
		}
	}
	for _, activation := range ability.Activation {
		if activation.Type != "spawn_projectile" ||
			activation.Projectile == "" ||
			result.ProjectileID != "" {
			return nil, fmt.Errorf("%s has unsupported activation", id)
		}
		var header struct {
			Kind string `json:"kind"`
			ID   string `json:"id"`
		}
		if err := catalog.Decode(activation.Projectile, &header); err != nil {
			return nil, err
		}
		if header.Kind != "projectile" || header.ID != activation.Projectile {
			return nil, fmt.Errorf(
				"%s references invalid projectile %q",
				id,
				activation.Projectile,
			)
		}
		result.ProjectileID = activation.Projectile
	}
	for _, effect := range ability.Effects {
		switch effect.Type {
		case "damage":
			result.Damage = effect.Amount
		case "stagger":
			result.StaggerTicks = secondsToTicks(effect.Duration)
		case "knockback":
			result.Knockback = pixels(effect.Distance)
			result.KnockbackTicks = secondsToTicks(effect.Duration)
		case "hitstop":
			result.HitstopTicks = secondsToTicks(effect.Duration)
		}
	}
	if (result.Damage <= 0 && result.ProjectileID == "") ||
		result.ActiveTicks <= 0 {
		return nil, fmt.Errorf("%s has no executable effect or active duration", id)
	}
	return result, nil
}

type translatedDialogue struct {
	definition       sim.DialogueDefinition
	startNodeID      string
	questID          string
	startQuestOnOpen bool
}

func buildDialogue(
	catalog *content.Catalog,
	strings map[string]string,
	id string,
) (*translatedDialogue, error) {
	var authored dialogueDefinition
	if err := catalog.Decode(id, &authored); err != nil {
		return nil, err
	}
	if err := validateHeader(authored.SchemaVersion, authored.Kind, authored.ID,
		"dialogue", id); err != nil {
		return nil, err
	}
	node, exists := authored.Nodes[authored.Start]
	if !exists {
		return nil, fmt.Errorf(
			"%s has unknown start node %q",
			id,
			authored.Start,
		)
	}
	questID := questAction(node.Actions)
	startQuestOnOpen := questID != ""
	if questID == "" {
		for _, choice := range node.Choices {
			if questID = questAction(choice.Actions); questID != "" {
				break
			}
		}
	}
	return &translatedDialogue{
		definition: sim.DialogueDefinition{
			ID:      id,
			Speaker: localized(strings, node.SpeakerKey, node.SpeakerKey),
			Text:    localized(strings, node.TextKey, node.TextKey),
		},
		startNodeID:      authored.Start,
		questID:          questID,
		startQuestOnOpen: startQuestOnOpen,
	}, nil
}

func buildDialoguePreview(
	catalog *content.Catalog,
	strings map[string]string,
	id string,
) (*DialoguePreview, error) {
	translated, err := buildDialogue(catalog, strings, id)
	if err != nil {
		return nil, err
	}
	result := &DialoguePreview{
		Dialogue:         translated.definition,
		StartNodeID:      translated.startNodeID,
		StartQuestOnOpen: translated.startQuestOnOpen,
	}
	if translated.questID == "" {
		return result, nil
	}
	result.Quest, err = buildQuest(catalog, translated.questID)
	if err != nil {
		return nil, err
	}
	return result, nil
}

func questAction(actions []contentAction) string {
	for _, action := range actions {
		if action.Type == "start_quest" {
			return action.Quest
		}
	}
	return ""
}

func buildQuest(
	catalog *content.Catalog,
	id string,
) (*sim.QuestDefinition, error) {
	var authored questDefinition
	if err := catalog.Decode(id, &authored); err != nil {
		return nil, err
	}
	if err := validateHeader(authored.SchemaVersion, authored.Kind, authored.ID,
		"quest", id); err != nil {
		return nil, err
	}
	for _, objective := range authored.Objectives {
		if objective.Event == "actor.killed" &&
			objective.Where.ActorID != "" &&
			objective.Count > 0 {
			return &sim.QuestDefinition{
				ID:         id,
				TargetKind: objective.Where.ActorID,
				Required:   objective.Count,
			}, nil
		}
	}
	return nil, fmt.Errorf("%s has no supported actor.killed objective", id)
}

func convertWall(stageID string, wall stageWall) (sim.Wall, error) {
	if wall.ID == "" {
		return sim.Wall{}, fmt.Errorf(
			"%s has invalid wall %q",
			stageID,
			wall.ID,
		)
	}
	return convertShape(stageID+" wall "+wall.ID, wall.ID, wall.Shape)
}

func convertShape(
	label string,
	id string,
	shape shapeRect,
) (sim.Wall, error) {
	if shape.Type == "rectangle" {
		rect, err := convertRectangle(label, shape)
		if err != nil {
			return sim.Wall{}, err
		}
		result := sim.Wall{ID: id, Rect: rect}
		if err := sim.ValidateWall(result); err != nil {
			return sim.Wall{}, fmt.Errorf("%s: %w", label, err)
		}
		return result, nil
	}
	if shape.Type != "polygon" || len(shape.Points) < 3 {
		return sim.Wall{}, fmt.Errorf("%s has an invalid polygon", label)
	}
	points := make([]sim.Vec, len(shape.Points))
	for index, point := range shape.Points {
		if !finite(point.X) || !finite(point.Y) {
			return sim.Wall{}, fmt.Errorf(
				"%s has an invalid polygon point %d",
				label,
				index,
			)
		}
		points[index] = sim.Vec{
			X: pixels(point.X),
			Y: pixels(point.Y),
		}
	}
	result := sim.Wall{
		ID:     id,
		Points: points,
		Rect: sim.Rect{
			MinX: points[0].X,
			MinY: points[0].Y,
			MaxX: points[0].X,
			MaxY: points[0].Y,
		},
	}
	for _, point := range points[1:] {
		result.Rect.MinX = min(result.Rect.MinX, point.X)
		result.Rect.MinY = min(result.Rect.MinY, point.Y)
		result.Rect.MaxX = max(result.Rect.MaxX, point.X)
		result.Rect.MaxY = max(result.Rect.MaxY, point.Y)
	}
	if err := sim.ValidateWall(result); err != nil {
		return sim.Wall{}, fmt.Errorf("%s: %w", label, err)
	}
	return result, nil
}

func convertRectangle(label string, shape shapeRect) (sim.Rect, error) {
	if shape.Type != "rectangle" ||
		!finite(shape.X) || !finite(shape.Y) ||
		!positiveFinite(shape.Width) || !positiveFinite(shape.Height) {
		return sim.Rect{}, fmt.Errorf("%s has an invalid rectangle", label)
	}
	return sim.Rect{
		MinX: pixels(shape.X - shape.Width/2),
		MinY: pixels(shape.Y - shape.Height/2),
		MaxX: pixels(shape.X + shape.Width/2),
		MaxY: pixels(shape.Y + shape.Height/2),
	}, nil
}

func validateHeader(
	version int,
	kind string,
	id string,
	wantKind string,
	wantID string,
) error {
	if version != 1 || kind != wantKind || id != wantID {
		return fmt.Errorf(
			"%s header mismatch: version=%d kind=%q id=%q",
			wantID,
			version,
			kind,
			id,
		)
	}
	return nil
}

func localized(strings map[string]string, key string, fallback string) string {
	if key != "" {
		if value := strings[key]; value != "" {
			return value
		}
	}
	return fallback
}

// secondsToTicks uses nearest-tick rounding. Positive authored durations never
// disappear: values below half a tick become one tick.
func secondsToTicks(seconds float64) int {
	if !finite(seconds) || seconds <= 0 {
		return 0
	}
	ticks := math.Round(seconds * sim.TicksPerSecond)
	if ticks > sim.MaxTickCount {
		// Return an architecture-independent invalid sentinel. Simulation
		// validation will reject it; callers without simulation validation
		// must first call durationFitsPortableTicks.
		return sim.MaxTickCount + 1
	}
	return max(1, int(ticks))
}

// durationFitsPortableTicks keeps authored durations inside the simulation's
// supported range. Console toolchains must not observe a different overflow
// result from desktop builds.
func durationFitsPortableTicks(seconds float64) bool {
	return finite(seconds) &&
		seconds >= 0 &&
		seconds <= float64(sim.MaxTickCount)/sim.TicksPerSecond
}

func rateToCoord(pixelsPerSecond float64) sim.Coord {
	return sim.Coord(math.Round(
		pixelsPerSecond * float64(sim.UnitsPerPixel) / sim.TicksPerSecond,
	))
}

func accelerationToCoord(pixelsPerSecondSquared float64) sim.Coord {
	ticks := float64(sim.TicksPerSecond * sim.TicksPerSecond)
	return sim.Coord(math.Round(
		pixelsPerSecondSquared * float64(sim.UnitsPerPixel) / ticks,
	))
}

func pixels(value float64) sim.Coord {
	return sim.Coord(math.Round(value * float64(sim.UnitsPerPixel)))
}

func positiveFinite(value float64) bool {
	return finite(value) && value > 0
}

func finite(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0)
}
