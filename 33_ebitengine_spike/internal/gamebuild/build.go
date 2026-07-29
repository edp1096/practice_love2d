// Package gamebuild translates the runtime-neutral content catalog into the
// small deterministic simulation used by the Ebitengine spike.
package gamebuild

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"sort"

	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

const (
	defaultStageID  = "stage.rpg_village"
	defaultLocaleID = "locale.ko"
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
	LocaleID string
	Impact   ImpactOptions
}

type InstanceMetadata struct {
	ID             string         `json:"id"`
	ActorID        string         `json:"actor_id"`
	SpriteID       string         `json:"sprite_id,omitempty"`
	PrimaryAbility string         `json:"primary_ability,omitempty"`
	Controlled     bool           `json:"controlled,omitempty"`
	Chase          *ChaseMetadata `json:"chase,omitempty"`
	Tags           []string       `json:"tags,omitempty"`
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
	return item, true
}

type Result struct {
	Config       sim.Config
	Presentation Presentation
}

type stageDefinition struct {
	SchemaVersion int          `json:"schema_version"`
	Kind          string       `json:"kind"`
	ID            string       `json:"id"`
	Name          string       `json:"name"`
	NameKey       string       `json:"name_key"`
	Width         float64      `json:"width"`
	Height        float64      `json:"height"`
	Background    []float64    `json:"background"`
	Camera        stageCamera  `json:"camera"`
	Spawns        []stageSpawn `json:"spawns"`
	Walls         []stageWall  `json:"walls"`
}

type stageCamera struct {
	FollowTag      string  `json:"follow_tag"`
	ViewportWidth  float64 `json:"viewport_width"`
	ViewportHeight float64 `json:"viewport_height"`
}

type stageSpawn struct {
	ID       string        `json:"id"`
	Actor    string        `json:"actor"`
	Position stagePosition `json:"position"`
}

type stagePosition struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

type stageWall struct {
	ID    string    `json:"id"`
	Shape shapeRect `json:"shape"`
}

type shapeRect struct {
	Type   string  `json:"type"`
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
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
	Solid  bool    `json:"solid"`
}

type healthComponent struct {
	Max int `json:"max"`
}

type movementComponent struct {
	Speed float64 `json:"speed"`
}

type combatComponent struct {
	Primary string `json:"primary"`
	Team    string `json:"team"`
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
	Sprite string `json:"sprite"`
}

type interactableComponent struct {
	Range   float64         `json:"range"`
	Actions []contentAction `json:"actions"`
}

type contentAction struct {
	Type     string `json:"type"`
	Dialogue string `json:"dialogue"`
	Quest    string `json:"quest"`
}

type abilityDefinition struct {
	SchemaVersion int             `json:"schema_version"`
	Kind          string          `json:"kind"`
	ID            string          `json:"id"`
	Windup        float64         `json:"windup"`
	Duration      float64         `json:"duration"`
	Recovery      float64         `json:"recovery"`
	Cooldown      float64         `json:"cooldown"`
	LockMovement  bool            `json:"lock_movement"`
	Hitbox        abilityHitbox   `json:"hitbox"`
	Effects       []abilityEffect `json:"effects"`
}

type abilityHitbox struct {
	Shape      string  `json:"shape"`
	Reach      float64 `json:"reach"`
	ArcDegrees int     `json:"arc_degrees"`
}

type abilityEffect struct {
	Type     string  `json:"type"`
	Amount   int     `json:"amount"`
	Duration float64 `json:"duration"`
	Distance float64 `json:"distance"`
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
	applyDefaults(&options)

	var stage stageDefinition
	if err := catalog.Decode(options.StageID, &stage); err != nil {
		return nil, err
	}
	if err := validateHeader(stage.SchemaVersion, stage.Kind, stage.ID,
		"stage", options.StageID); err != nil {
		return nil, err
	}
	var locale localeDefinition
	if err := catalog.Decode(options.LocaleID, &locale); err != nil {
		return nil, err
	}
	if err := validateHeader(locale.SchemaVersion, locale.Kind, locale.ID,
		"locale", options.LocaleID); err != nil {
		return nil, err
	}
	if !positiveFinite(stage.Width) || !positiveFinite(stage.Height) {
		return nil, fmt.Errorf("%s has invalid dimensions", stage.ID)
	}
	if !positiveFinite(stage.Camera.ViewportWidth) ||
		!positiveFinite(stage.Camera.ViewportHeight) {
		return nil, fmt.Errorf("%s has invalid camera viewport", stage.ID)
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
			StageName: localized(locale.Strings, stage.NameKey, stage.Name),
		},
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
		result.Config.Walls = append(result.Config.Walls, sim.Wall{
			ID:   wall.ID,
			Rect: converted,
		})
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
			buildEntity(catalog, locale.Strings, spawn, options.Impact)
		if err != nil {
			return nil, fmt.Errorf("%s spawn %q: %w", stage.ID, spawn.ID, err)
		}
		result.Config.Entities = append(result.Config.Entities, entity)
		result.Presentation.Instances = append(
			result.Presentation.Instances,
			metadata,
		)
		if entity.Controlled {
			if controlledID != "" {
				return nil, fmt.Errorf("%s has more than one controlled actor", stage.ID)
			}
			controlledID = entity.ID
		}
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
	if body.Shape != "circle" || !positiveFinite(body.Radius) {
		return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
			fmt.Errorf("only positive circle bodies are supported, got %q", body.Shape)
	}
	entity := sim.EntityConfig{
		ID:       spawn.ID,
		Kind:     actor.ID,
		Name:     actor.Name,
		Position: sim.Vec{X: pixels(spawn.Position.X), Y: pixels(spawn.Position.Y)},
		Body: sim.Body{
			HalfWidth:  pixels(body.Radius),
			HalfHeight: pixels(body.Radius),
			Solid:      body.Solid,
		},
		MaxHealth: 1,
		Facing:    sim.Vec{X: sim.UnitsPerPixel},
	}
	metadata := InstanceMetadata{
		ID:      spawn.ID,
		ActorID: actor.ID,
		Tags:    append([]string(nil), actor.Tags...),
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
	if raw := actor.Components["action.combat"]; raw != nil {
		var combat combatComponent
		if err := json.Unmarshal(raw, &combat); err != nil ||
			combat.Primary == "" || combat.Team == "" {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0,
				fmt.Errorf("invalid action.combat")
		}
		ability, err := buildAbility(catalog, combat.Primary, impact)
		if err != nil {
			return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0, err
		}
		entity.Team = combat.Team
		entity.Ability = ability
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
			var err error
			dialogue, entity.StartQuestID, err = buildDialogue(
				catalog,
				strings,
				entity.DialogueID,
			)
			if err != nil {
				return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0, err
			}
			if entity.StartQuestID != "" {
				quest, err = buildQuest(catalog, entity.StartQuestID)
				if err != nil {
					return sim.EntityConfig{}, InstanceMetadata{}, nil, nil, 0, err
				}
			}
		}
	}
	return entity, metadata, dialogue, quest, interactionRange, nil
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
	if ability.Hitbox.Shape != "arc" ||
		!positiveFinite(ability.Hitbox.Reach) ||
		ability.Hitbox.ArcDegrees < 1 ||
		ability.Hitbox.ArcDegrees > 360 {
		return nil, fmt.Errorf("%s has unsupported hitbox", id)
	}
	result := &sim.AbilityConfig{
		ID:               id,
		WindupTicks:      secondsToTicks(ability.Windup),
		ActiveTicks:      secondsToTicks(ability.Duration),
		RecoveryTicks:    secondsToTicks(ability.Recovery),
		CooldownTicks:    secondsToTicks(ability.Cooldown),
		LockMovement:     ability.LockMovement,
		Reach:            pixels(ability.Hitbox.Reach),
		ArcDegrees:       ability.Hitbox.ArcDegrees,
		CameraShake:      pixels(impact.DamageShakePixels),
		CameraShakeTicks: secondsToTicks(impact.DamageShakeSeconds),
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
	if result.Damage <= 0 || result.ActiveTicks <= 0 {
		return nil, fmt.Errorf("%s has no positive damage or active duration", id)
	}
	return result, nil
}

func buildDialogue(
	catalog *content.Catalog,
	strings map[string]string,
	id string,
) (*sim.DialogueDefinition, string, error) {
	var authored dialogueDefinition
	if err := catalog.Decode(id, &authored); err != nil {
		return nil, "", err
	}
	if err := validateHeader(authored.SchemaVersion, authored.Kind, authored.ID,
		"dialogue", id); err != nil {
		return nil, "", err
	}
	node, exists := authored.Nodes[authored.Start]
	if !exists {
		return nil, "", fmt.Errorf("%s has unknown start node %q", id, authored.Start)
	}
	questID := questAction(node.Actions)
	if questID == "" {
		for _, choice := range node.Choices {
			if questID = questAction(choice.Actions); questID != "" {
				break
			}
		}
	}
	return &sim.DialogueDefinition{
		ID:      id,
		Speaker: localized(strings, node.SpeakerKey, node.SpeakerKey),
		Text:    localized(strings, node.TextKey, node.TextKey),
	}, questID, nil
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

func convertWall(stageID string, wall stageWall) (sim.Rect, error) {
	shape := wall.Shape
	if wall.ID == "" || shape.Type != "rectangle" ||
		!finite(shape.X) || !finite(shape.Y) ||
		!positiveFinite(shape.Width) || !positiveFinite(shape.Height) {
		return sim.Rect{}, fmt.Errorf("%s has invalid wall %q", stageID, wall.ID)
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
	return max(1, int(math.Round(seconds*sim.TicksPerSecond)))
}

func rateToCoord(pixelsPerSecond float64) sim.Coord {
	return sim.Coord(math.Round(
		pixelsPerSecond * float64(sim.UnitsPerPixel) / sim.TicksPerSecond,
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
