package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"math"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

type runtimeState struct {
	Project         string  `json:"project"`
	StageID         string  `json:"stage_id"`
	LoveVersion     string  `json:"love_version"`
	LuaVersion      string  `json:"lua_version"`
	JITVersion      string  `json:"jit_version"`
	SimulationSteps int     `json:"simulation_steps"`
	FixedDelta      float64 `json:"fixed_dt"`
	Transitions     int     `json:"transitions"`
	Simulation      struct {
		Paused        bool    `json:"paused"`
		PendingFrames int     `json:"pending_frames"`
		SteppedFrames int     `json:"stepped_frames"`
		StepDelta     float64 `json:"step_dt"`
	} `json:"simulation"`
}

// Lua's JSON encoder serializes an empty table as [] because Lua has no
// distinct object and array types. Non-empty flag tables are objects, so the
// protocol accepts either representation for the empty state.
type boolMap map[string]bool

func (values *boolMap) UnmarshalJSON(data []byte) error {
	if string(data) == "[]" || string(data) == "null" {
		*values = boolMap{}
		return nil
	}

	var decoded map[string]bool
	if err := json.Unmarshal(data, &decoded); err != nil {
		return err
	}
	*values = decoded
	return nil
}

type worldSnapshot struct {
	Available        bool    `json:"available"`
	HitstopRemaining float64 `json:"hitstop_remaining"`
	Stage            struct {
		ID     string  `json:"id"`
		Name   string  `json:"name"`
		Width  float64 `json:"width"`
		Height float64 `json:"height"`
	} `json:"stage"`
	Time     float64       `json:"time"`
	Ticks    int           `json:"ticks"`
	Count    int           `json:"count"`
	Entities []entityState `json:"entities"`
	Events   []eventState  `json:"recent_events"`
	Camera   struct {
		X        float64 `json:"x"`
		Y        float64 `json:"y"`
		Width    float64 `json:"width"`
		Height   float64 `json:"height"`
		TargetID string  `json:"target_id"`
	} `json:"camera"`
	Tilemap struct {
		Available    bool   `json:"available"`
		LayerCount   int    `json:"layer_count"`
		TilesetCount int    `json:"tileset_count"`
		Source       string `json:"source"`
	} `json:"tilemap"`
	Geometry struct {
		WallCount int `json:"wall_count"`
	} `json:"geometry"`
	Navigation struct {
		SpawnPointCount   int      `json:"spawn_point_count"`
		TriggerCount      int      `json:"trigger_count"`
		PortalCount       int      `json:"portal_count"`
		ActiveOverlaps    int      `json:"active_overlaps"`
		FiredTriggers     []string `json:"fired_triggers"`
		TransitionPending bool     `json:"transition_requested"`
	} `json:"navigation"`
	EncounterCount int              `json:"encounter_count"`
	Encounters     []encounterState `json:"encounters"`
	Flags          boolMap          `json:"flags"`
	Inventory      []inventoryState `json:"inventory"`
	Currency       struct {
		Balance int `json:"balance"`
	} `json:"currency"`
	Quests      []questState     `json:"quests"`
	Dialogue    dialogueState    `json:"dialogue"`
	Interaction interactionState `json:"interaction"`
	Shop        shopState        `json:"shop"`
	Locale      struct {
		ID   string `json:"id"`
		Code string `json:"code"`
	} `json:"locale"`
}

type eventState struct {
	Name    string          `json:"name"`
	Payload json.RawMessage `json:"payload"`
}

type hitboxState struct {
	Shape          string  `json:"shape"`
	Reach          float64 `json:"reach"`
	ArcDegrees     float64 `json:"arc_degrees"`
	RepeatInterval float64 `json:"repeat_interval"`
	MaxHits        int     `json:"max_hits"`
}

type statusState struct {
	ID            string  `json:"id"`
	Stacks        int     `json:"stacks"`
	Remaining     float64 `json:"remaining"`
	TickRemaining float64 `json:"tick_remaining"`
	SourceID      string  `json:"source_id"`
}

type encounterState struct {
	ID            string   `json:"id"`
	DefinitionID  string   `json:"definition_id"`
	Status        string   `json:"status"`
	WaveIndex     int      `json:"wave_index"`
	WaveID        string   `json:"wave_id"`
	Remaining     float64  `json:"remaining"`
	Living        int      `json:"living"`
	EnteredPhases []string `json:"entered_phases"`
}

type inventoryState struct {
	ItemID string `json:"item_id"`
	Name   string `json:"name"`
	Count  int    `json:"count"`
}

type questObjectiveState struct {
	ID    string `json:"id"`
	Event string `json:"event"`
	Count int    `json:"count"`
	Goal  int    `json:"goal"`
}

type questState struct {
	ID         string                `json:"id"`
	Name       string                `json:"name"`
	Status     string                `json:"status"`
	Objectives []questObjectiveState `json:"objectives"`
}

type dialogueChoiceState struct {
	ID   string `json:"id"`
	Text string `json:"text"`
}

type dialogueState struct {
	Active          bool                  `json:"active"`
	DialogueID      string                `json:"dialogue_id"`
	NodeID          string                `json:"node_id"`
	InteractorID    string                `json:"interactor_id"`
	SpeakerEntityID string                `json:"speaker_entity_id"`
	Speaker         string                `json:"speaker"`
	Text            string                `json:"text"`
	Selected        int                   `json:"selected"`
	Choices         []dialogueChoiceState `json:"choices"`
}

type interactionState struct {
	Active    bool   `json:"active"`
	TargetID  string `json:"target_id"`
	Prompt    string `json:"prompt"`
	PromptKey string `json:"prompt_key"`
}

type shopOfferState struct {
	ItemID    string `json:"item_id"`
	Name      string `json:"name"`
	BuyPrice  *int   `json:"buy_price"`
	SellPrice *int   `json:"sell_price"`
	Owned     int    `json:"owned"`
}

type shopState struct {
	Active   bool             `json:"active"`
	ShopID   string           `json:"shop_id"`
	Mode     string           `json:"mode"`
	Selected int              `json:"selected"`
	Message  string           `json:"message"`
	Balance  int              `json:"balance"`
	Offers   []shopOfferState `json:"offers"`
}

type statState struct {
	Attack    float64 `json:"attack"`
	Defense   float64 `json:"defense"`
	MoveSpeed float64 `json:"move_speed"`
}

type equipmentState struct {
	Slot   string `json:"slot"`
	ItemID string `json:"item_id"`
}

type entityState struct {
	ID                    string           `json:"id"`
	ActorID               string           `json:"actor_id"`
	Tags                  []string         `json:"tags"`
	Components            []string         `json:"components"`
	Dead                  bool             `json:"dead"`
	X                     float64          `json:"x"`
	Y                     float64          `json:"y"`
	Health                float64          `json:"health"`
	MaxHealth             float64          `json:"max_health"`
	HurtboxRadius         float64          `json:"hurtbox_radius"`
	AttackPhase           string           `json:"attack_phase"`
	AttackRemaining       float64          `json:"attack_remaining"`
	AttackHitCount        int              `json:"attack_hit_count"`
	AttackHitbox          hitboxState      `json:"attack_hitbox"`
	StaggerRemaining      float64          `json:"stagger_remaining"`
	InvulnerableRemaining float64          `json:"invulnerable_remaining"`
	KnockbackRemaining    float64          `json:"knockback_remaining"`
	DodgeActive           bool             `json:"dodge_active"`
	DodgeRemaining        float64          `json:"dodge_remaining"`
	DodgeCooldown         float64          `json:"dodge_cooldown"`
	ParryActive           bool             `json:"parry_active"`
	ParryRemaining        float64          `json:"parry_remaining"`
	ParryCooldown         float64          `json:"parry_cooldown"`
	ParrySuccessRemaining float64          `json:"parry_success_remaining"`
	ParryPerfect          bool             `json:"parry_perfect"`
	ProjectileID          string           `json:"projectile_id"`
	ProjectileSourceID    string           `json:"projectile_source_id"`
	ProjectileRemaining   float64          `json:"projectile_remaining"`
	ProjectileHits        int              `json:"projectile_hits"`
	ProjectileDirectionX  float64          `json:"projectile_direction_x"`
	ProjectileDirectionY  float64          `json:"projectile_direction_y"`
	StatusCount           int              `json:"status_count"`
	Statuses              []statusState    `json:"statuses"`
	BodyShape             string           `json:"body_shape"`
	BodyStatic            bool             `json:"body_static"`
	BodySolid             bool             `json:"body_solid"`
	CollisionLayer        string           `json:"collision_layer"`
	CollisionMask         []string         `json:"collision_mask"`
	VelocityX             float64          `json:"velocity_x"`
	VelocityY             float64          `json:"velocity_y"`
	Moving                bool             `json:"moving"`
	Grounded              bool             `json:"grounded"`
	PlatformerSpeed       float64          `json:"platformer_speed"`
	PlatformerGravity     float64          `json:"platformer_gravity"`
	PlatformerJumpSpeed   float64          `json:"platformer_jump_speed"`
	Stats                 statState        `json:"stats"`
	EquipmentLoadout      string           `json:"equipment_loadout"`
	Equipment             []equipmentState `json:"equipment"`
}

type visualReport struct {
	Runtime runtimeState `json:"runtime"`
	Stage   string       `json:"stage"`
	Counts  struct {
		Entities int `json:"entities"`
	} `json:"counts"`
	Player struct {
		ID              string  `json:"id"`
		StartX          float64 `json:"start_x"`
		EndX            float64 `json:"end_x"`
		MovementDelta   float64 `json:"movement_delta"`
		HealthAfterTest float64 `json:"health_after_test"`
	} `json:"player"`
	Enemy struct {
		ID               string  `json:"id"`
		HealthBefore     float64 `json:"health_before"`
		HealthAfter      float64 `json:"health_after"`
		Damage           float64 `json:"damage"`
		StaggerRemaining float64 `json:"stagger_remaining"`
	} `json:"enemy"`
	AttackCommitment struct {
		Phase               string  `json:"phase"`
		MovementWhileLocked float64 `json:"movement_while_locked"`
	} `json:"attack_commitment"`
	Hitbox struct {
		Shape        string  `json:"shape"`
		Reach        float64 `json:"reach"`
		ArcDegrees   float64 `json:"arc_degrees"`
		SourceRadius float64 `json:"source_hurtbox_radius"`
		TargetRadius float64 `json:"target_hurtbox_radius"`
		HitCount     int     `json:"hit_count"`
	} `json:"hitbox"`
	Hitstop struct {
		RemainingBefore float64 `json:"remaining_before"`
		TimeBefore      float64 `json:"world_time_before"`
		TimeAfter       float64 `json:"world_time_after"`
		FrozenFrames    int     `json:"frozen_frames"`
	} `json:"hitstop"`
	Knockback struct {
		StartX float64 `json:"start_x"`
		EndX   float64 `json:"end_x"`
		Delta  float64 `json:"delta"`
	} `json:"knockback"`
	Parry struct {
		PlayerHealthBefore      float64 `json:"player_health_before"`
		PlayerHealthAfter       float64 `json:"player_health_after"`
		EnemyStaggerRemaining   float64 `json:"enemy_stagger_remaining"`
		SuccessDisplayRemaining float64 `json:"success_display_remaining"`
		Perfect                 bool    `json:"perfect"`
	} `json:"parry"`
	Dodge struct {
		PlayerHealthBefore float64 `json:"player_health_before"`
		PlayerHealthAfter  float64 `json:"player_health_after"`
		MovementDelta      float64 `json:"movement_delta"`
		BlockedDamage      bool    `json:"blocked_damage"`
		Invulnerable       bool    `json:"invulnerable"`
	} `json:"dodge"`
	Projectile       projectileVisualReport `json:"projectile"`
	DynamicCollision dynamicCollisionReport `json:"dynamic_collision"`
	MultiHit         multiHitVisualReport   `json:"multi_hit"`
	Encounter        encounterVisualReport  `json:"encounter"`
	Platformer       platformerVisualReport `json:"platformer"`
	World            worldVisualReport      `json:"world"`
	RPG              rpgVisualReport        `json:"rpg"`
	Save             saveVisualReport       `json:"save"`
	Preview          previewProtocolReport  `json:"preview_protocol"`
	SteppedFrames    int                    `json:"stepped_frames"`
	Paused           bool                   `json:"paused"`
	ImpactScreenshot string                 `json:"impact_screenshot"`
	Screenshot       string                 `json:"screenshot"`
	DodgeScreenshot  string                 `json:"dodge_screenshot"`
	Log              string                 `json:"log"`
}

type projectileVisualReport struct {
	ID               string      `json:"id"`
	DefinitionID     string      `json:"definition_id"`
	SourceID         string      `json:"source_id"`
	StartX           float64     `json:"start_x"`
	CapturedX        float64     `json:"captured_x"`
	DirectionX       float64     `json:"direction_x"`
	HealthBefore     float64     `json:"health_before"`
	HealthAfter      float64     `json:"health_after"`
	Damage           float64     `json:"damage"`
	PeriodicDamage   float64     `json:"periodic_damage"`
	Spawned          bool        `json:"spawned"`
	Hit              bool        `json:"hit"`
	RemovedAfterHit  bool        `json:"removed_after_hit"`
	Screenshot       string      `json:"screenshot"`
	StatusScreenshot string      `json:"status_screenshot"`
	Status           statusState `json:"status"`
}

type dynamicCollisionReport struct {
	PlayerStartX  float64 `json:"player_start_x"`
	PlayerEndX    float64 `json:"player_end_x"`
	ObstacleX     float64 `json:"obstacle_x"`
	Separation    float64 `json:"separation"`
	PlayerLayer   string  `json:"player_layer"`
	ObstacleLayer string  `json:"obstacle_layer"`
}

type multiHitVisualReport struct {
	AbilityID      string  `json:"ability_id"`
	HealthBefore   float64 `json:"health_before"`
	HealthAfter    float64 `json:"health_after"`
	Damage         float64 `json:"damage"`
	HitCount       int     `json:"hit_count"`
	RepeatInterval float64 `json:"repeat_interval"`
	MaxHits        int     `json:"max_hits"`
	Screenshot     string  `json:"screenshot"`
}

type encounterVisualReport struct {
	Stage           string  `json:"stage"`
	ID              string  `json:"id"`
	FirstWave       string  `json:"first_wave"`
	FirstWaveActors int     `json:"first_wave_actors"`
	BossWave        string  `json:"boss_wave"`
	BossID          string  `json:"boss_id"`
	BossHealth      float64 `json:"boss_health_at_phase"`
	Phase           string  `json:"phase"`
	StatusID        string  `json:"status_id"`
	Completed       bool    `json:"completed"`
	Screenshot      string  `json:"screenshot"`
}

type platformerVisualReport struct {
	Stage           string  `json:"stage"`
	PlayerID        string  `json:"player_id"`
	StartX          float64 `json:"start_x"`
	StartY          float64 `json:"start_y"`
	ApexY           float64 `json:"apex_y"`
	LandingX        float64 `json:"landing_x"`
	LandingY        float64 `json:"landing_y"`
	HorizontalDelta float64 `json:"horizontal_delta"`
	Jumped          bool    `json:"jumped"`
	Landed          bool    `json:"landed"`
	Grounded        bool    `json:"grounded"`
	Screenshot      string  `json:"screenshot"`
}

type worldVisualReport struct {
	HubStage          string  `json:"hub_stage"`
	GroveStage        string  `json:"grove_stage"`
	ReturnStage       string  `json:"return_stage"`
	TileLayers        int     `json:"tile_layers"`
	Tilesets          int     `json:"tilesets"`
	Walls             int     `json:"walls"`
	SpawnPoints       int     `json:"spawn_points"`
	Triggers          int     `json:"triggers"`
	Portals           int     `json:"portals"`
	CameraStartX      float64 `json:"camera_start_x"`
	CameraScrolledX   float64 `json:"camera_scrolled_x"`
	CollisionStartX   float64 `json:"collision_start_x"`
	CollisionEndX     float64 `json:"collision_end_x"`
	HealthBefore      float64 `json:"health_before_trigger"`
	HealthAfter       float64 `json:"health_after_trigger"`
	TriggerFired      bool    `json:"trigger_fired"`
	PortalTransitions int     `json:"portal_transitions"`
	ReturnX           float64 `json:"return_x"`
	ReturnY           float64 `json:"return_y"`
	HubScreenshot     string  `json:"hub_screenshot"`
	GroveScreenshot   string  `json:"grove_screenshot"`
}

type rpgVisualReport struct {
	Stage                   string  `json:"stage"`
	Locale                  string  `json:"locale"`
	DialogueID              string  `json:"dialogue_id"`
	DialogueNode            string  `json:"dialogue_node"`
	DialogueText            string  `json:"dialogue_text"`
	QuestID                 string  `json:"quest_id"`
	QuestStatus             string  `json:"quest_status"`
	QuestProgress           int     `json:"quest_progress"`
	QuestGoal               int     `json:"quest_goal"`
	EquippedItem            string  `json:"equipped_item"`
	AttackStat              float64 `json:"attack_stat"`
	EquippedAttackDamage    float64 `json:"equipped_attack_damage"`
	Currency                int     `json:"currency"`
	PotionCount             int     `json:"potion_count"`
	ShopPurchased           bool    `json:"shop_purchased"`
	EquippedSaleBlocked     bool    `json:"equipped_sale_blocked"`
	SessionPersisted        bool    `json:"session_persisted"`
	DialogueScreenshot      string  `json:"dialogue_screenshot"`
	QuestScreenshot         string  `json:"quest_screenshot"`
	QuestCompleteScreenshot string  `json:"quest_complete_screenshot"`
	ShopScreenshot          string  `json:"shop_screenshot"`
}

type saveVisualReport struct {
	Slot              string `json:"slot"`
	Path              string `json:"path"`
	SchemaVersion     int    `json:"schema_version"`
	SectionCount      int    `json:"section_count"`
	SectionsVersioned bool   `json:"sections_versioned"`
	Mutated           bool   `json:"mutated_after_save"`
	Restored          bool   `json:"restored"`
	Stage             string `json:"stage"`
	Currency          int    `json:"currency"`
	PotionCount       int    `json:"potion_count"`
	QuestStatus       string `json:"quest_status"`
	EquippedItem      string `json:"equipped_item"`
	Screenshot        string `json:"screenshot"`
}

type previewProtocolReport struct {
	Definition bool `json:"definition"`
	Graph      bool `json:"graph"`
	Dialogue   bool `json:"dialogue"`
	Spawn      bool `json:"spawn"`
	Ability    bool `json:"ability"`
	Remove     bool `json:"remove"`
}

type loveProcess struct {
	command *exec.Cmd
	done    chan error
}

func runVisualTest(
	options globalOptions,
	projectPath string,
	arguments []string,
) error {
	flags := flag.NewFlagSet("test", flag.ContinueOnError)
	artifactArgument := flags.String(
		"artifacts",
		"",
		"directory for screenshot, report, and log",
	)
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if len(flags.Args()) != 0 {
		return errors.New("usage: lovectl test [--artifacts PATH]")
	}

	artifacts, err := prepareArtifacts(*artifactArgument)
	if err != nil {
		return err
	}
	port, err := availablePort()
	if err != nil {
		return err
	}

	logPath := filepath.Join(artifacts, "love.log")
	logFile, err := os.Create(logPath)
	if err != nil {
		return err
	}
	defer logFile.Close()

	process, err := startLove(
		options.lovePath,
		projectPath,
		port,
		logFile,
	)
	if err != nil {
		return err
	}
	defer forceStop(process)

	client := newProtocolClient("127.0.0.1", port, 20*time.Second)
	if err := waitForBridge(client, process, 20*time.Second); err != nil {
		return visualFailure(err, logPath)
	}

	report, err := runActionScenario(client, artifacts)
	if err != nil {
		return visualFailure(err, logPath)
	}
	report.Log = logPath

	var quitResult map[string]any
	if err := client.call("App.quit", nil, &quitResult); err != nil {
		return visualFailure(err, logPath)
	}
	select {
	case waitError := <-process.done:
		process.command = nil
		if waitError != nil {
			return visualFailure(
				fmt.Errorf("LÖVE exited unsuccessfully: %w", waitError),
				logPath,
			)
		}
	case <-time.After(10 * time.Second):
		return visualFailure(errors.New("LÖVE did not quit within 10s"), logPath)
	}

	reportPath := filepath.Join(artifacts, "report.json")
	encoded, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return err
	}
	encoded = append(encoded, '\n')
	if err := os.WriteFile(reportPath, encoded, 0o644); err != nil {
		return err
	}

	fmt.Printf("Visual action test passed: %s\n", artifacts)
	fmt.Printf(
		"  moved %.2f, hitbox dealt %.0f and knocked back %.0f, "+
			"hitstop froze %d frames, recovery locked movement, "+
			"perfect parry kept HP %.0f, dodge blocked a hit over %.2f px, "+
			"projectile dealt %.0f + %.0f burn damage, "+
			"dynamic bodies held %.0f px and multihit dealt %.0f, "+
			"encounter completed through boss phase %s, "+
			"platformer jumped %.0f px onto a %.0f Y ledge, "+
			"TMX camera scrolled %.0f and crossed %d portals "+
			"and RPG quest %s finished with %d currency "+
			"(%d deterministic frames)\n",
		report.Player.MovementDelta,
		report.Enemy.Damage,
		report.Knockback.Delta,
		report.Hitstop.FrozenFrames,
		report.Parry.PlayerHealthAfter,
		report.Dodge.MovementDelta,
		report.Projectile.Damage,
		report.Projectile.PeriodicDamage,
		report.DynamicCollision.Separation,
		report.MultiHit.Damage,
		report.Encounter.Phase,
		report.Platformer.StartY-report.Platformer.ApexY,
		report.Platformer.LandingY,
		report.World.CameraScrolledX-report.World.CameraStartX,
		report.World.PortalTransitions,
		report.RPG.QuestStatus,
		report.RPG.Currency,
		report.SteppedFrames,
	)
	return nil
}

func runActionScenario(
	client *protocolClient,
	artifacts string,
) (visualReport, error) {
	var report visualReport
	if err := client.call("Runtime.getState", nil, &report.Runtime); err != nil {
		return report, err
	}

	var pauseResult map[string]any
	if err := client.call(
		"Test.setPaused",
		map[string]any{"enabled": true},
		&pauseResult,
	); err != nil {
		return report, err
	}

	var initial worldSnapshot
	if err := client.call("World.getSnapshot", nil, &initial); err != nil {
		return report, err
	}
	if !initial.Available {
		return report, errors.New("semantic world is unavailable")
	}
	player, err := entityWithTag(initial.Entities, "player")
	if err != nil {
		return report, err
	}
	enemy, err := entityWithTag(initial.Entities, "enemy")
	if err != nil {
		return report, err
	}

	report.Stage = initial.Stage.ID
	report.Counts.Entities = initial.Count
	report.Player.ID = player.ID
	report.Player.StartX = player.X
	report.Enemy.ID = enemy.ID

	var actionResult map[string]any
	if err := client.call(
		"Input.action",
		map[string]any{
			"action": "move_right",
			"value":  1,
			"frames": 30,
		},
		&actionResult,
	); err != nil {
		return report, err
	}

	startSteps := report.Runtime.Simulation.SteppedFrames
	if err := requestAndWaitSteps(client, startSteps, 30); err != nil {
		return report, err
	}

	var moved entityState
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": player.ID},
		&moved,
	); err != nil {
		return report, err
	}
	report.Player.EndX = moved.X
	report.Player.MovementDelta = moved.X - player.X
	if report.Player.MovementDelta < 80 {
		return report, fmt.Errorf(
			"semantic movement was too small: %.2f",
			report.Player.MovementDelta,
		)
	}

	var positioned entityState
	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": enemy.ID,
			"x":        moved.X + 52,
			"y":        moved.Y,
		},
		&positioned,
	); err != nil {
		return report, err
	}
	report.Enemy.HealthBefore = positioned.Health

	if err := client.call(
		"Input.action",
		map[string]any{
			"action": "attack",
			"value":  1,
			"frames": 1,
		},
		&actionResult,
	); err != nil {
		return report, err
	}

	var beforeAttack runtimeState
	if err := client.call("Runtime.getState", nil, &beforeAttack); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(
		client,
		beforeAttack.Simulation.SteppedFrames,
		2,
	); err != nil {
		return report, err
	}

	var attacked entityState
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": enemy.ID},
		&attacked,
	); err != nil {
		return report, err
	}
	report.Enemy.HealthAfter = attacked.Health
	report.Enemy.Damage =
		report.Enemy.HealthBefore - report.Enemy.HealthAfter
	report.Enemy.StaggerRemaining = attacked.StaggerRemaining
	if report.Enemy.Damage <= 0 {
		return report, errors.New("attack did not damage the enemy")
	}
	if report.Enemy.StaggerRemaining <= 0 {
		return report, errors.New("attack did not stagger the enemy")
	}

	var attackingPlayer entityState
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": player.ID},
		&attackingPlayer,
	); err != nil {
		return report, err
	}
	report.Hitbox.Shape = attackingPlayer.AttackHitbox.Shape
	report.Hitbox.Reach = attackingPlayer.AttackHitbox.Reach
	report.Hitbox.ArcDegrees =
		attackingPlayer.AttackHitbox.ArcDegrees
	report.Hitbox.SourceRadius = attackingPlayer.HurtboxRadius
	report.Hitbox.TargetRadius = attacked.HurtboxRadius
	report.Hitbox.HitCount = attackingPlayer.AttackHitCount
	if report.Hitbox.Shape != "arc" || report.Hitbox.HitCount != 1 ||
		report.Hitbox.SourceRadius <= 0 || report.Hitbox.TargetRadius <= 0 {
		return report, errors.New("semantic hitbox/hurtbox state is incomplete")
	}
	if err := client.call(
		"Overlay.set",
		map[string]any{
			"enabled":  true,
			"entities": true,
			"labels":   true,
		},
		&actionResult,
	); err != nil {
		return report, err
	}
	impactScreenshot := filepath.Join(artifacts, "impact_slice.png")
	if err := captureScreenshot(client, impactScreenshot); err != nil {
		return report, err
	}
	report.ImpactScreenshot = impactScreenshot

	var hitstopBefore worldSnapshot
	if err := client.call(
		"World.getSnapshot",
		nil,
		&hitstopBefore,
	); err != nil {
		return report, err
	}
	report.Hitstop.RemainingBefore = hitstopBefore.HitstopRemaining
	report.Hitstop.TimeBefore = hitstopBefore.Time
	if report.Hitstop.RemainingBefore <= 0 {
		return report, errors.New("attack did not start hitstop")
	}

	attackSteps := beforeAttack.Simulation.SteppedFrames + 2
	var frozenState worldSnapshot
	for attempt := 0; attempt < 10; attempt++ {
		if hitstopBefore.HitstopRemaining <= 0 {
			frozenState = hitstopBefore
			break
		}
		if err := requestAndWaitSteps(client, attackSteps, 1); err != nil {
			return report, err
		}
		attackSteps++
		report.Hitstop.FrozenFrames++
		if err := client.call(
			"World.getSnapshot",
			nil,
			&frozenState,
		); err != nil {
			return report, err
		}
		if frozenState.Time != report.Hitstop.TimeBefore {
			return report, fmt.Errorf(
				"world time advanced during hitstop: %.6f -> %.6f",
				report.Hitstop.TimeBefore,
				frozenState.Time,
			)
		}
		hitstopBefore = frozenState
	}
	if frozenState.HitstopRemaining > 0 {
		return report, errors.New("hitstop did not finish within 10 frames")
	}
	report.Hitstop.TimeAfter = frozenState.Time

	report.Knockback.StartX = attacked.X
	if err := requestAndWaitSteps(client, attackSteps, 8); err != nil {
		return report, err
	}
	attackSteps += 8
	var knockedBack entityState
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": enemy.ID},
		&knockedBack,
	); err != nil {
		return report, err
	}
	report.Knockback.EndX = knockedBack.X
	report.Knockback.Delta =
		report.Knockback.EndX - report.Knockback.StartX
	if report.Knockback.Delta < 20 {
		return report, fmt.Errorf(
			"knockback displacement was too small: %.2f",
			report.Knockback.Delta,
		)
	}

	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": player.ID},
		&attackingPlayer,
	); err != nil {
		return report, err
	}
	report.AttackCommitment.Phase = attackingPlayer.AttackPhase
	if report.AttackCommitment.Phase != "recovery" {
		return report, fmt.Errorf(
			"expected recovery commitment, got %q",
			report.AttackCommitment.Phase,
		)
	}
	if err := client.call(
		"Input.action",
		map[string]any{
			"action": "move_right",
			"value":  1,
			"frames": 1,
		},
		&actionResult,
	); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(
		client,
		attackSteps,
		1,
	); err != nil {
		return report, err
	}
	attackSteps++

	var attackLockedPlayer entityState
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": player.ID},
		&attackLockedPlayer,
	); err != nil {
		return report, err
	}
	report.AttackCommitment.MovementWhileLocked =
		attackLockedPlayer.X - attackingPlayer.X
	if report.AttackCommitment.MovementWhileLocked != 0 {
		return report, fmt.Errorf(
			"player moved %.2f during attack commitment",
			report.AttackCommitment.MovementWhileLocked,
		)
	}

	var reloadResult runtimeState
	if err := client.call("App.reloadStage", nil, &reloadResult); err != nil {
		return report, err
	}

	var parryInitial worldSnapshot
	if err := client.call("World.getSnapshot", nil, &parryInitial); err != nil {
		return report, err
	}
	parryPlayer, err := entityWithTag(parryInitial.Entities, "player")
	if err != nil {
		return report, err
	}
	parryEnemy, err := entityWithTag(parryInitial.Entities, "enemy")
	if err != nil {
		return report, err
	}
	report.Parry.PlayerHealthBefore = parryPlayer.Health

	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": parryEnemy.ID,
			"x":        parryPlayer.X + 35,
			"y":        parryPlayer.Y,
		},
		&positioned,
	); err != nil {
		return report, err
	}

	var parryRuntime runtimeState
	if err := client.call("Runtime.getState", nil, &parryRuntime); err != nil {
		return report, err
	}
	parrySteps := parryRuntime.Simulation.SteppedFrames
	if err := requestAndWaitSteps(client, parrySteps, 1); err != nil {
		return report, err
	}
	parrySteps++

	var windingUp entityState
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": parryEnemy.ID},
		&windingUp,
	); err != nil {
		return report, err
	}
	if windingUp.AttackPhase != "windup" {
		return report, fmt.Errorf(
			"enemy did not enter attack windup: got %q",
			windingUp.AttackPhase,
		)
	}

	if err := stepUntilWindupRemaining(
		client,
		parryEnemy.ID,
		&parrySteps,
		0.07,
	); err != nil {
		return report, err
	}
	if err := client.call(
		"Input.action",
		map[string]any{
			"action": "parry",
			"value":  1,
			"frames": 1,
		},
		&actionResult,
	); err != nil {
		return report, err
	}

	var parryResultPlayer entityState
	var parryResultEnemy entityState
	parried := false
	for attempt := 0; attempt < 10; attempt++ {
		if err := requestAndWaitSteps(client, parrySteps, 1); err != nil {
			return report, err
		}
		parrySteps++
		if err := client.call(
			"Entity.get",
			map[string]any{"entityId": parryPlayer.ID},
			&parryResultPlayer,
		); err != nil {
			return report, err
		}
		if err := client.call(
			"Entity.get",
			map[string]any{"entityId": parryEnemy.ID},
			&parryResultEnemy,
		); err != nil {
			return report, err
		}
		if parryResultPlayer.ParrySuccessRemaining > 0 {
			parried = true
			break
		}
	}
	if !parried {
		return report, errors.New("enemy attack was not parried")
	}

	report.Parry.PlayerHealthAfter = parryResultPlayer.Health
	report.Parry.EnemyStaggerRemaining =
		parryResultEnemy.StaggerRemaining
	report.Parry.SuccessDisplayRemaining =
		parryResultPlayer.ParrySuccessRemaining
	report.Parry.Perfect = parryResultPlayer.ParryPerfect
	report.Player.HealthAfterTest = parryResultPlayer.Health
	if report.Parry.PlayerHealthAfter != report.Parry.PlayerHealthBefore {
		return report, fmt.Errorf(
			"parry did not prevent damage: %.0f -> %.0f",
			report.Parry.PlayerHealthBefore,
			report.Parry.PlayerHealthAfter,
		)
	}
	if report.Parry.EnemyStaggerRemaining <= 0 {
		return report, errors.New("parry did not stagger the attacker")
	}
	if !report.Parry.Perfect {
		return report, errors.New("timed parry was not classified as perfect")
	}

	var beforeCapture worldSnapshot
	if err := client.call(
		"World.getSnapshot",
		nil,
		&beforeCapture,
	); err != nil {
		return report, err
	}

	screenshot := filepath.Join(artifacts, "action_slice.png")
	if err := captureScreenshot(client, screenshot); err != nil {
		return report, err
	}
	report.Screenshot = screenshot

	var finalState runtimeState
	if err := client.call("Runtime.getState", nil, &finalState); err != nil {
		return report, err
	}
	report.SteppedFrames =
		finalState.Simulation.SteppedFrames - startSteps
	report.Paused = finalState.Simulation.Paused
	if !report.Paused {
		return report, errors.New("simulation resumed during visual capture")
	}

	var afterCapture worldSnapshot
	if err := client.call(
		"World.getSnapshot",
		nil,
		&afterCapture,
	); err != nil {
		return report, err
	}
	if afterCapture.Ticks != beforeCapture.Ticks {
		return report, fmt.Errorf(
			"world advanced while paused: ticks %d -> %d",
			beforeCapture.Ticks,
			afterCapture.Ticks,
		)
	}

	var capturedPlayer entityState
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": parryPlayer.ID},
		&capturedPlayer,
	); err != nil {
		return report, err
	}
	if capturedPlayer.Health != report.Player.HealthAfterTest {
		return report, fmt.Errorf(
			"player health changed while paused: %.0f -> %.0f "+
				"(ticks %d -> %d, pending %d)",
			report.Player.HealthAfterTest,
			capturedPlayer.Health,
			beforeCapture.Ticks,
			afterCapture.Ticks,
			finalState.Simulation.PendingFrames,
		)
	}

	if err := client.call("App.reloadStage", nil, &reloadResult); err != nil {
		return report, err
	}
	var dodgeInitial worldSnapshot
	if err := client.call("World.getSnapshot", nil, &dodgeInitial); err != nil {
		return report, err
	}
	dodgePlayer, err := entityWithTag(dodgeInitial.Entities, "player")
	if err != nil {
		return report, err
	}
	dodgeEnemy, err := entityWithTag(dodgeInitial.Entities, "enemy")
	if err != nil {
		return report, err
	}
	report.Dodge.PlayerHealthBefore = dodgePlayer.Health
	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": dodgeEnemy.ID,
			"x":        dodgePlayer.X + 35,
			"y":        dodgePlayer.Y,
		},
		&positioned,
	); err != nil {
		return report, err
	}

	var dodgeRuntime runtimeState
	if err := client.call("Runtime.getState", nil, &dodgeRuntime); err != nil {
		return report, err
	}
	dodgeSteps := dodgeRuntime.Simulation.SteppedFrames
	if err := requestAndWaitSteps(client, dodgeSteps, 1); err != nil {
		return report, err
	}
	dodgeSteps++
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": dodgeEnemy.ID},
		&windingUp,
	); err != nil {
		return report, err
	}
	if windingUp.AttackPhase != "windup" {
		return report, errors.New("dodge attacker did not enter windup")
	}
	if err := stepUntilWindupRemaining(
		client,
		dodgeEnemy.ID,
		&dodgeSteps,
		0.035,
	); err != nil {
		return report, err
	}
	if err := client.call(
		"Input.action",
		map[string]any{
			"action": "dodge",
			"value":  1,
			"frames": 1,
		},
		&actionResult,
	); err != nil {
		return report, err
	}

	var dodgeResultPlayer entityState
	var dodgeResultEnemy entityState
	var dodgeSnapshot worldSnapshot
	for attempt := 0; attempt < 10; attempt++ {
		if err := requestAndWaitSteps(client, dodgeSteps, 1); err != nil {
			return report, err
		}
		dodgeSteps++
		if err := client.call(
			"World.getSnapshot",
			nil,
			&dodgeSnapshot,
		); err != nil {
			return report, err
		}
		dodgeResultEnemy, err =
			entityByID(dodgeSnapshot.Entities, dodgeEnemy.ID)
		if err != nil {
			return report, err
		}
		if err := client.call(
			"Entity.get",
			map[string]any{"entityId": dodgePlayer.ID},
			&dodgeResultPlayer,
		); err != nil {
			return report, err
		}
		if snapshotHasEvent(
			dodgeSnapshot,
			"actor.damage_blocked",
			dodgePlayer.ID,
		) {
			report.Dodge.BlockedDamage = true
			break
		}
	}
	report.Dodge.PlayerHealthAfter = dodgeResultPlayer.Health
	report.Player.HealthAfterTest = dodgeResultPlayer.Health
	if !report.Dodge.BlockedDamage ||
		report.Dodge.PlayerHealthAfter != report.Dodge.PlayerHealthBefore {
		return report, fmt.Errorf(
			"dodge did not block the incoming hit: blocked=%t, "+
				"HP %.0f -> %.0f, player=(%.2f, %.2f), "+
				"enemy=(%.2f, %.2f) phase=%q remaining=%.3f, "+
				"dodge=%t invuln=%.3f",
			report.Dodge.BlockedDamage,
			report.Dodge.PlayerHealthBefore,
			report.Dodge.PlayerHealthAfter,
			dodgeResultPlayer.X,
			dodgeResultPlayer.Y,
			dodgeResultEnemy.X,
			dodgeResultEnemy.Y,
			dodgeResultEnemy.AttackPhase,
			dodgeResultEnemy.AttackRemaining,
			dodgeResultPlayer.DodgeActive,
			dodgeResultPlayer.InvulnerableRemaining,
		)
	}

	if err := client.call("App.reloadStage", nil, &reloadResult); err != nil {
		return report, err
	}
	var freeDodgeInitial worldSnapshot
	if err := client.call(
		"World.getSnapshot",
		nil,
		&freeDodgeInitial,
	); err != nil {
		return report, err
	}
	freeDodgePlayer, err :=
		entityWithTag(freeDodgeInitial.Entities, "player")
	if err != nil {
		return report, err
	}
	if err := client.call(
		"Input.action",
		map[string]any{
			"action": "move_up",
			"value":  1,
			"frames": 1,
		},
		&actionResult,
	); err != nil {
		return report, err
	}
	if err := client.call(
		"Input.action",
		map[string]any{
			"action": "dodge",
			"value":  1,
			"frames": 1,
		},
		&actionResult,
	); err != nil {
		return report, err
	}
	var freeDodgeRuntime runtimeState
	if err := client.call(
		"Runtime.getState",
		nil,
		&freeDodgeRuntime,
	); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(
		client,
		freeDodgeRuntime.Simulation.SteppedFrames,
		6,
	); err != nil {
		return report, err
	}
	var freeDodgePlayerAfter entityState
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": freeDodgePlayer.ID},
		&freeDodgePlayerAfter,
	); err != nil {
		return report, err
	}
	report.Dodge.MovementDelta = math.Hypot(
		freeDodgePlayerAfter.X-freeDodgePlayer.X,
		freeDodgePlayerAfter.Y-freeDodgePlayer.Y,
	)
	report.Dodge.Invulnerable =
		freeDodgePlayerAfter.InvulnerableRemaining > 0
	if !freeDodgePlayerAfter.DodgeActive ||
		!report.Dodge.Invulnerable ||
		report.Dodge.MovementDelta < 30 {
		return report, errors.New("dodge movement/invulnerability state is incomplete")
	}

	var beforeDodgeCapture worldSnapshot
	if err := client.call(
		"World.getSnapshot",
		nil,
		&beforeDodgeCapture,
	); err != nil {
		return report, err
	}
	dodgeScreenshot := filepath.Join(artifacts, "dodge_slice.png")
	if err := captureScreenshot(client, dodgeScreenshot); err != nil {
		return report, err
	}
	report.DodgeScreenshot = dodgeScreenshot
	var afterDodgeCapture worldSnapshot
	if err := client.call(
		"World.getSnapshot",
		nil,
		&afterDodgeCapture,
	); err != nil {
		return report, err
	}
	if afterDodgeCapture.Ticks != beforeDodgeCapture.Ticks {
		return report, errors.New("world advanced during dodge screenshot")
	}

	if err := client.call("Runtime.getState", nil, &finalState); err != nil {
		return report, err
	}
	report.SteppedFrames =
		finalState.Simulation.SteppedFrames - startSteps
	report.Paused = finalState.Simulation.Paused
	projectileReport, err := runProjectileScenario(client, artifacts)
	if err != nil {
		return report, err
	}
	report.Projectile = projectileReport
	collisionReport, multiHitReport, err :=
		runCollisionAndMultiHitScenario(client, artifacts)
	if err != nil {
		return report, err
	}
	report.DynamicCollision = collisionReport
	report.MultiHit = multiHitReport
	encounterReport, err := runEncounterScenario(client, artifacts)
	if err != nil {
		return report, err
	}
	report.Encounter = encounterReport
	platformerReport, err :=
		runPlatformerScenario(client, artifacts)
	if err != nil {
		return report, err
	}
	report.Platformer = platformerReport
	worldReport, err := runWorldScenario(client, artifacts)
	if err != nil {
		return report, err
	}
	report.World = worldReport
	rpgReport, err := runRPGScenario(client, artifacts)
	if err != nil {
		return report, err
	}
	report.RPG = rpgReport
	saveReport, err := runSaveScenario(client, artifacts)
	if err != nil {
		return report, err
	}
	report.Save = saveReport
	previewReport, err := runPreviewProtocolScenario(client)
	if err != nil {
		return report, err
	}
	report.Preview = previewReport
	if err := client.call("Runtime.getState", nil, &finalState); err != nil {
		return report, err
	}
	report.SteppedFrames =
		finalState.Simulation.SteppedFrames - startSteps
	return report, nil
}

func runSaveScenario(
	client *protocolClient,
	artifacts string,
) (saveVisualReport, error) {
	var report saveVisualReport
	var exported struct {
		SchemaVersion int    `json:"schema_version"`
		Project       string `json:"project"`
		Stage         struct {
			ID string `json:"id"`
		} `json:"stage"`
		Sections map[string]struct {
			Version int            `json:"version"`
			Data    map[string]any `json:"data"`
		} `json:"sections"`
	}
	if err := client.call("Save.export", nil, &exported); err != nil {
		return report, err
	}
	report.SchemaVersion = exported.SchemaVersion
	report.SectionCount = len(exported.Sections)
	report.SectionsVersioned = report.SectionCount == 6
	for _, section := range exported.Sections {
		if section.Version != 1 || section.Data == nil {
			report.SectionsVersioned = false
		}
	}
	if exported.SchemaVersion != 1 ||
		exported.Project != "recreate.maker_runtime" ||
		exported.Stage.ID != "stage.action_room" ||
		!report.SectionsVersioned {
		return report, fmt.Errorf(
			"versioned save export is incomplete: %#v",
			exported,
		)
	}

	var written struct {
		Slot          string `json:"slot"`
		Path          string `json:"path"`
		StageID       string `json:"stage_id"`
		SchemaVersion int    `json:"schema_version"`
	}
	if err := client.call(
		"Save.write",
		map[string]any{"slot": "visual_regression"},
		&written,
	); err != nil {
		return report, err
	}
	report.Slot = written.Slot
	report.Path = written.Path
	if written.Slot != "visual_regression" ||
		written.Path != "saves/visual_regression.lua" ||
		written.StageID != "stage.action_room" ||
		written.SchemaVersion != 1 {
		return report, fmt.Errorf(
			"atomic save write response is incomplete: %#v",
			written,
		)
	}

	var mutation map[string]any
	if err := client.call(
		"Economy.add",
		map[string]any{"amount": 25},
		&mutation,
	); err != nil {
		return report, err
	}
	if err := client.call(
		"Inventory.give",
		map[string]any{
			"itemId": "item.potion",
			"amount": 1,
		},
		&mutation,
	); err != nil {
		return report, err
	}
	var snapshot worldSnapshot
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	report.Mutated =
		snapshot.Currency.Balance == 100 &&
			inventoryCount(snapshot.Inventory, "item.potion") == 3
	if !report.Mutated {
		return report, fmt.Errorf(
			"post-save mutations were not observable: currency=%d inventory=%#v",
			snapshot.Currency.Balance,
			snapshot.Inventory,
		)
	}

	var runtime runtimeState
	if err := client.call(
		"App.loadStage",
		map[string]any{"stageId": "stage.platformer_room"},
		&runtime,
	); err != nil {
		return report, err
	}
	if runtime.StageID != "stage.platformer_room" {
		return report, fmt.Errorf(
			"pre-load stage mutation failed: %#v",
			runtime,
		)
	}
	if err := client.call(
		"Save.load",
		map[string]any{"slot": "visual_regression"},
		&runtime,
	); err != nil {
		return report, err
	}
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	quest, questErr := questByID(
		snapshot.Quests,
		"quest.slime_patrol",
	)
	player, playerErr := entityWithTag(snapshot.Entities, "player")
	report.Stage = snapshot.Stage.ID
	report.Currency = snapshot.Currency.Balance
	report.PotionCount =
		inventoryCount(snapshot.Inventory, "item.potion")
	if questErr == nil {
		report.QuestStatus = quest.Status
	}
	if playerErr == nil {
		report.EquippedItem = equippedItem(player, "weapon")
	}
	report.Restored =
		runtime.StageID == "stage.action_room" &&
			report.Stage == "stage.action_room" &&
			report.Currency == 75 &&
			report.PotionCount == 2 &&
			questErr == nil &&
			report.QuestStatus == "completed" &&
			playerErr == nil &&
			report.EquippedItem == "item.training_sword" &&
			player.Stats.Attack == 5 &&
			snapshot.Flags["quest.slime_patrol.rewarded"]
	if !report.Restored {
		return report, fmt.Errorf(
			"save did not restore RPG progression transactionally: "+
				"runtime=%#v quest=%#v player=%#v snapshot=%#v",
			runtime,
			quest,
			player,
			snapshot,
		)
	}
	report.Screenshot = filepath.Join(artifacts, "save_restored.png")
	if err := captureScreenshot(client, report.Screenshot); err != nil {
		return report, err
	}
	return report, nil
}

func runPreviewProtocolScenario(
	client *protocolClient,
) (previewProtocolReport, error) {
	var report previewProtocolReport
	var definition struct {
		ID         string         `json:"id"`
		Kind       string         `json:"kind"`
		Source     string         `json:"source"`
		Definition map[string]any `json:"definition"`
	}
	if err := client.call(
		"Content.getDefinition",
		map[string]any{"contentId": "actor.slime"},
		&definition,
	); err != nil {
		return report, err
	}
	report.Definition =
		definition.ID == "actor.slime" &&
			definition.Kind == "actor" &&
			definition.Source == "game/content/actors/slime.lua" &&
			definition.Definition["id"] == "actor.slime"
	if !report.Definition {
		return report, fmt.Errorf(
			"content definition preview is incomplete: %#v",
			definition,
		)
	}

	var graph contentGraph
	if err := client.call("Content.getGraph", nil, &graph); err != nil {
		return report, err
	}
	node, found := findContentGraphNode(graph, "item.training_sword")
	report.Graph = found && len(node.Dependents) >= 3
	if !report.Graph {
		return report, fmt.Errorf(
			"live dependency graph is incomplete: %#v",
			node,
		)
	}

	var dialogueResult map[string]any
	if err := client.call(
		"Dialogue.start",
		map[string]any{"dialogueId": "dialogue.guide"},
		&dialogueResult,
	); err != nil {
		return report, err
	}
	var snapshot worldSnapshot
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	report.Dialogue =
		snapshot.Dialogue.Active &&
			snapshot.Dialogue.DialogueID == "dialogue.guide"
	if !report.Dialogue {
		return report, fmt.Errorf(
			"dialogue preview did not open: %#v",
			snapshot.Dialogue,
		)
	}
	var runtime runtimeState
	if err := client.call("Runtime.getState", nil, &runtime); err != nil {
		return report, err
	}
	steps := runtime.Simulation.SteppedFrames
	if err := performSemanticInput(
		client,
		&steps,
		"menu_cancel",
		1,
	); err != nil {
		return report, err
	}

	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	player, err := entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return report, err
	}
	var spawned entityState
	if err := client.call(
		"Entity.spawn",
		map[string]any{
			"actorId":  "actor.slime",
			"entityId": "debug.preview.slime",
			"x":        player.X + 140,
			"y":        player.Y,
		},
		&spawned,
	); err != nil {
		return report, err
	}
	report.Spawn =
		spawned.ID == "debug.preview.slime" &&
			spawned.ActorID == "actor.slime"
	if !report.Spawn {
		return report, fmt.Errorf(
			"actor preview spawn is incomplete: %#v",
			spawned,
		)
	}

	var queued map[string]any
	if err := client.call(
		"Entity.requestAbility",
		map[string]any{
			"entityId":  player.ID,
			"abilityId": "ability.sword_slash",
		},
		&queued,
	); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(client, steps, 1); err != nil {
		return report, err
	}
	steps++
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	report.Ability = snapshotHasEventName(snapshot, "ability.started")
	if !report.Ability {
		return report, errors.New("ability preview did not start")
	}

	if err := client.call(
		"Entity.remove",
		map[string]any{"entityId": spawned.ID},
		&queued,
	); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(client, steps, 1); err != nil {
		return report, err
	}
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": spawned.ID},
		&spawned,
	); err == nil {
		return report, errors.New("removed preview actor is still available")
	}
	report.Remove = true
	return report, nil
}

func runProjectileScenario(
	client *protocolClient,
	artifacts string,
) (projectileVisualReport, error) {
	var report projectileVisualReport
	var runtime runtimeState
	if err := client.call("App.reloadStage", nil, &runtime); err != nil {
		return report, err
	}

	var initial worldSnapshot
	if err := client.call("World.getSnapshot", nil, &initial); err != nil {
		return report, err
	}
	player, err := entityWithTag(initial.Entities, "player")
	if err != nil {
		return report, err
	}
	enemy, err := entityWithTag(initial.Entities, "enemy")
	if err != nil {
		return report, err
	}
	report.StartX = player.X + 25

	var positioned entityState
	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": enemy.ID,
			"x":        350,
			"y":        player.Y,
		},
		&positioned,
	); err != nil {
		return report, err
	}
	report.HealthBefore = positioned.Health

	var actionResult map[string]any
	if err := client.call(
		"Input.action",
		map[string]any{
			"action": "special",
			"value":  1,
			"frames": 1,
		},
		&actionResult,
	); err != nil {
		return report, err
	}
	steps := runtime.Simulation.SteppedFrames
	if err := requestAndWaitSteps(client, steps, 9); err != nil {
		return report, err
	}
	steps += 9

	var inFlight worldSnapshot
	if err := client.call("World.getSnapshot", nil, &inFlight); err != nil {
		return report, err
	}
	projectile, err := entityWithTag(inFlight.Entities, "projectile")
	if err != nil {
		return report, errors.New("special ability did not spawn a projectile")
	}
	report.ID = projectile.ID
	report.DefinitionID = projectile.ProjectileID
	report.SourceID = projectile.ProjectileSourceID
	report.CapturedX = projectile.X
	report.DirectionX = projectile.ProjectileDirectionX
	report.Spawned = snapshotHasEventName(inFlight, "projectile.spawned")
	if report.DefinitionID != "projectile.fire_bolt" ||
		report.SourceID != player.ID ||
		report.CapturedX <= report.StartX ||
		report.DirectionX < 0.99 ||
		!report.Spawned {
		return report, fmt.Errorf(
			"projectile semantic state is incomplete: %#v",
			projectile,
		)
	}

	report.Screenshot = filepath.Join(artifacts, "projectile_slice.png")
	if err := captureScreenshot(client, report.Screenshot); err != nil {
		return report, err
	}

	var afterHit worldSnapshot
	for attempt := 0; attempt < 45; attempt++ {
		if err := requestAndWaitSteps(client, steps, 1); err != nil {
			return report, err
		}
		steps++
		if err := client.call(
			"World.getSnapshot",
			nil,
			&afterHit,
		); err != nil {
			return report, err
		}
		if snapshotHasEvent(
			afterHit,
			"projectile.hit",
			enemy.ID,
		) {
			report.Hit = true
			break
		}
	}
	if !report.Hit {
		return report, errors.New("projectile did not hit the target")
	}

	hitEnemy, err := entityByID(afterHit.Entities, enemy.ID)
	if err != nil {
		return report, err
	}
	report.HealthAfter = hitEnemy.Health
	report.Damage = report.HealthBefore - report.HealthAfter
	if report.Damage != 18 {
		return report, fmt.Errorf(
			"projectile damage mismatch: got %.0f, want 18",
			report.Damage,
		)
	}
	_, projectileError := entityByID(afterHit.Entities, report.ID)
	report.RemovedAfterHit = projectileError != nil
	if !report.RemovedAfterHit {
		return report, errors.New("projectile remained after a non-piercing hit")
	}
	if hitEnemy.StatusCount != 1 ||
		len(hitEnemy.Statuses) != 1 ||
		hitEnemy.Statuses[0].ID != "status.burning" ||
		hitEnemy.Statuses[0].Stacks != 1 ||
		hitEnemy.Statuses[0].SourceID != player.ID {
		return report, fmt.Errorf(
			"projectile did not apply burning status: %#v",
			hitEnemy.Statuses,
		)
	}
	report.Status = hitEnemy.Statuses[0]
	report.StatusScreenshot = filepath.Join(
		artifacts,
		"status_slice.png",
	)
	if err := captureScreenshot(client, report.StatusScreenshot); err != nil {
		return report, err
	}

	var afterTick worldSnapshot
	for attempt := 0; attempt < 40; attempt++ {
		if err := requestAndWaitSteps(client, steps, 1); err != nil {
			return report, err
		}
		steps++
		if err := client.call(
			"World.getSnapshot",
			nil,
			&afterTick,
		); err != nil {
			return report, err
		}
		if snapshotHasEvent(
			afterTick,
			"status.ticked",
			enemy.ID,
		) {
			break
		}
	}
	if !snapshotHasEvent(afterTick, "status.ticked", enemy.ID) {
		return report, errors.New("burning status did not tick")
	}
	tickedEnemy, err := entityByID(afterTick.Entities, enemy.ID)
	if err != nil {
		return report, err
	}
	report.PeriodicDamage = report.HealthAfter - tickedEnemy.Health
	if report.PeriodicDamage != 3 {
		return report, fmt.Errorf(
			"burning periodic damage mismatch: got %.0f, want 3",
			report.PeriodicDamage,
		)
	}
	return report, nil
}

func runCollisionAndMultiHitScenario(
	client *protocolClient,
	artifacts string,
) (dynamicCollisionReport, multiHitVisualReport, error) {
	var collisionReport dynamicCollisionReport
	var multiHitReport multiHitVisualReport
	var runtime runtimeState
	if err := client.call("App.reloadStage", nil, &runtime); err != nil {
		return collisionReport, multiHitReport, err
	}

	var initial worldSnapshot
	if err := client.call("World.getSnapshot", nil, &initial); err != nil {
		return collisionReport, multiHitReport, err
	}
	player, err := entityWithTag(initial.Entities, "player")
	if err != nil {
		return collisionReport, multiHitReport, err
	}
	enemy, err := entityWithTag(initial.Entities, "enemy")
	if err != nil {
		return collisionReport, multiHitReport, err
	}
	collisionReport.PlayerStartX = player.X
	collisionReport.PlayerLayer = player.CollisionLayer

	var positioned entityState
	if err := client.call(
		"Entity.setHealth",
		map[string]any{
			"entityId": enemy.ID,
			"value":    0,
		},
		&positioned,
	); err != nil {
		return collisionReport, multiHitReport, err
	}
	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": enemy.ID,
			"x":        230,
			"y":        player.Y,
		},
		&positioned,
	); err != nil {
		return collisionReport, multiHitReport, err
	}
	collisionReport.ObstacleLayer = positioned.CollisionLayer

	var actionResult map[string]any
	if err := client.call(
		"Input.action",
		map[string]any{
			"action": "move_right",
			"value":  1,
			"frames": 10,
		},
		&actionResult,
	); err != nil {
		return collisionReport, multiHitReport, err
	}
	steps := runtime.Simulation.SteppedFrames
	if err := requestAndWaitSteps(client, steps, 10); err != nil {
		return collisionReport, multiHitReport, err
	}
	steps += 10

	var blocked worldSnapshot
	if err := client.call("World.getSnapshot", nil, &blocked); err != nil {
		return collisionReport, multiHitReport, err
	}
	blockedPlayer, err := entityByID(blocked.Entities, player.ID)
	if err != nil {
		return collisionReport, multiHitReport, err
	}
	blockedEnemy, err := entityByID(blocked.Entities, enemy.ID)
	if err != nil {
		return collisionReport, multiHitReport, err
	}
	collisionReport.PlayerEndX = blockedPlayer.X
	collisionReport.ObstacleX = blockedEnemy.X
	collisionReport.Separation =
		blockedEnemy.X - blockedPlayer.X
	minimumSeparation :=
		blockedPlayer.HurtboxRadius + blockedEnemy.HurtboxRadius
	if collisionReport.PlayerEndX <= collisionReport.PlayerStartX ||
		collisionReport.Separation < minimumSeparation ||
		collisionReport.Separation > minimumSeparation+4 ||
		collisionReport.PlayerLayer != "actor" ||
		collisionReport.ObstacleLayer != "actor" {
		return collisionReport, multiHitReport, fmt.Errorf(
			"dynamic actor collision failed: %#v",
			collisionReport,
		)
	}

	if err := client.call("App.reloadStage", nil, &runtime); err != nil {
		return collisionReport, multiHitReport, err
	}
	if err := client.call("World.getSnapshot", nil, &initial); err != nil {
		return collisionReport, multiHitReport, err
	}
	player, err = entityWithTag(initial.Entities, "player")
	if err != nil {
		return collisionReport, multiHitReport, err
	}
	enemy, err = entityWithTag(initial.Entities, "enemy")
	if err != nil {
		return collisionReport, multiHitReport, err
	}
	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": enemy.ID,
			"x":        235,
			"y":        player.Y,
		},
		&positioned,
	); err != nil {
		return collisionReport, multiHitReport, err
	}
	multiHitReport.AbilityID = "ability.whirlwind"
	multiHitReport.HealthBefore = positioned.Health

	if err := client.call(
		"Input.action",
		map[string]any{
			"action": "technique",
			"value":  1,
			"frames": 1,
		},
		&actionResult,
	); err != nil {
		return collisionReport, multiHitReport, err
	}
	steps = runtime.Simulation.SteppedFrames
	var active worldSnapshot
	var activePlayer entityState
	var activeEnemy entityState
	for attempt := 0; attempt < 60; attempt++ {
		if err := requestAndWaitSteps(client, steps, 1); err != nil {
			return collisionReport, multiHitReport, err
		}
		steps++
		if err := client.call(
			"World.getSnapshot",
			nil,
			&active,
		); err != nil {
			return collisionReport, multiHitReport, err
		}
		activePlayer, err = entityByID(active.Entities, player.ID)
		if err != nil {
			return collisionReport, multiHitReport, err
		}
		activeEnemy, err = entityByID(active.Entities, enemy.ID)
		if err != nil {
			return collisionReport, multiHitReport, err
		}
		if activePlayer.AttackHitCount == 3 {
			break
		}
	}
	multiHitReport.HealthAfter = activeEnemy.Health
	multiHitReport.Damage =
		multiHitReport.HealthBefore - multiHitReport.HealthAfter
	multiHitReport.HitCount = activePlayer.AttackHitCount
	multiHitReport.RepeatInterval =
		activePlayer.AttackHitbox.RepeatInterval
	multiHitReport.MaxHits = activePlayer.AttackHitbox.MaxHits
	if multiHitReport.Damage != 18 ||
		multiHitReport.HitCount != 3 ||
		multiHitReport.RepeatInterval != 0.15 ||
		multiHitReport.MaxHits != 3 ||
		countAbilityHits(
			active,
			multiHitReport.AbilityID,
			enemy.ID,
		) != 3 {
		return collisionReport, multiHitReport, fmt.Errorf(
			"multi-hit ability failed: %#v",
			multiHitReport,
		)
	}
	multiHitReport.Screenshot =
		filepath.Join(artifacts, "multihit_slice.png")
	if err := captureScreenshot(
		client,
		multiHitReport.Screenshot,
	); err != nil {
		return collisionReport, multiHitReport, err
	}
	return collisionReport, multiHitReport, nil
}

func runEncounterScenario(
	client *protocolClient,
	artifacts string,
) (encounterVisualReport, error) {
	var report encounterVisualReport
	var runtime runtimeState
	var err error
	if err := client.call(
		"App.loadStage",
		map[string]any{"stageId": "stage.encounter_room"},
		&runtime,
	); err != nil {
		return report, err
	}
	steps := runtime.Simulation.SteppedFrames

	var snapshot worldSnapshot
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	report.Stage = snapshot.Stage.ID
	report.ID = "arena"
	if report.Stage != "stage.encounter_room" ||
		snapshot.EncounterCount != 1 {
		return report, fmt.Errorf(
			"encounter stage snapshot is incomplete: %#v",
			snapshot,
		)
	}

	var state encounterState
	for attempt := 0; attempt < 20; attempt++ {
		var stateError error
		state, stateError = encounterByID(snapshot.Encounters, report.ID)
		if stateError == nil &&
			state.Status == "active" &&
			state.WaveID == "scouts" {
			break
		}
		if err := requestAndWaitSteps(client, steps, 1); err != nil {
			return report, err
		}
		steps++
		if err := client.call(
			"World.getSnapshot",
			nil,
			&snapshot,
		); err != nil {
			return report, err
		}
	}
	if state.Status != "active" || state.WaveID != "scouts" {
		return report, errors.New("encounter did not start its first wave")
	}
	report.FirstWave = state.WaveID
	report.FirstWaveActors = state.Living
	enemies := liveEntitiesWithTag(snapshot.Entities, "enemy")
	if report.FirstWaveActors != 2 || len(enemies) != 2 {
		return report, fmt.Errorf(
			"first encounter wave has %d living actors and %d entities",
			report.FirstWaveActors,
			len(enemies),
		)
	}
	var changed entityState
	for _, enemy := range enemies {
		if err := client.call(
			"Entity.setHealth",
			map[string]any{
				"entityId": enemy.ID,
				"value":    0,
			},
			&changed,
		); err != nil {
			return report, err
		}
	}
	if err := requestAndWaitSteps(client, steps, 1); err != nil {
		return report, err
	}
	steps++

	for attempt := 0; attempt < 24; attempt++ {
		if err := client.call(
			"World.getSnapshot",
			nil,
			&snapshot,
		); err != nil {
			return report, err
		}
		state, err = encounterByID(snapshot.Encounters, report.ID)
		if err != nil {
			return report, err
		}
		if state.Status == "active" && state.WaveID == "boss" {
			break
		}
		if err := requestAndWaitSteps(client, steps, 1); err != nil {
			return report, err
		}
		steps++
	}
	if state.Status != "active" || state.WaveID != "boss" {
		return report, errors.New("encounter did not advance to boss wave")
	}
	report.BossWave = state.WaveID
	boss, err := entityWithTag(snapshot.Entities, "boss")
	if err != nil {
		return report, err
	}
	report.BossID = boss.ID
	if boss.MaxHealth != 120 || state.Living != 1 {
		return report, fmt.Errorf(
			"boss wave semantic state is incomplete: %#v",
			boss,
		)
	}

	if err := client.call(
		"Entity.setHealth",
		map[string]any{
			"entityId": boss.ID,
			"value":    60,
		},
		&changed,
	); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(client, steps, 1); err != nil {
		return report, err
	}
	steps++
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	state, err = encounterByID(snapshot.Encounters, report.ID)
	if err != nil {
		return report, err
	}
	boss, err = entityByID(snapshot.Entities, boss.ID)
	if err != nil {
		return report, err
	}
	report.BossHealth = boss.Health
	if len(state.EnteredPhases) == 1 {
		report.Phase = state.EnteredPhases[0]
	}
	if len(boss.Statuses) == 1 {
		report.StatusID = boss.Statuses[0].ID
	}
	if report.Phase != "enraged" ||
		report.StatusID != "status.enraged" ||
		!snapshotHasEventName(snapshot, "boss.phase_entered") {
		return report, fmt.Errorf(
			"boss phase did not enter: state=%#v boss=%#v",
			state,
			boss,
		)
	}

	if err := requestAndWaitSteps(client, steps, 12); err != nil {
		return report, err
	}
	steps += 12
	report.Screenshot =
		filepath.Join(artifacts, "encounter_slice.png")
	if err := captureScreenshot(client, report.Screenshot); err != nil {
		return report, err
	}
	if err := client.call(
		"Entity.setHealth",
		map[string]any{
			"entityId": boss.ID,
			"value":    0,
		},
		&changed,
	); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(client, steps, 1); err != nil {
		return report, err
	}
	steps++
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	state, err = encounterByID(snapshot.Encounters, report.ID)
	if err != nil {
		return report, err
	}
	report.Completed =
		state.Status == "completed" &&
			snapshotHasEventName(snapshot, "encounter.completed") &&
			snapshotHasEventName(
				snapshot,
				"encounter.slime_trial_completed",
			)
	if !report.Completed {
		return report, fmt.Errorf(
			"encounter did not complete after boss defeat: %#v",
			state,
		)
	}
	return report, nil
}

func runPlatformerScenario(
	client *protocolClient,
	artifacts string,
) (platformerVisualReport, error) {
	var report platformerVisualReport
	var runtime runtimeState
	if err := client.call(
		"App.loadStage",
		map[string]any{"stageId": "stage.platformer_room"},
		&runtime,
	); err != nil {
		return report, err
	}
	steps := runtime.Simulation.SteppedFrames

	var snapshot worldSnapshot
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	player, err := entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return report, err
	}
	report.Stage = snapshot.Stage.ID
	report.PlayerID = player.ID
	if report.Stage != "stage.platformer_room" ||
		!hasComponent(player, "movement.platformer") ||
		hasComponent(player, "movement.topdown") ||
		snapshot.Geometry.WallCount != 2 {
		return report, fmt.Errorf(
			"platformer composition is incomplete: %#v",
			player,
		)
	}

	if err := requestAndWaitSteps(client, steps, 1); err != nil {
		return report, err
	}
	steps++
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	player, err = entityByID(snapshot.Entities, player.ID)
	if err != nil {
		return report, err
	}
	report.StartX = player.X
	report.StartY = player.Y
	report.ApexY = player.Y
	if !player.Grounded ||
		math.Abs(report.StartY-485) > 0.01 ||
		player.PlatformerGravity != 1500 ||
		player.PlatformerJumpSpeed != 600 {
		return report, fmt.Errorf(
			"platformer did not settle on the floor: %#v",
			player,
		)
	}

	var actionResult map[string]any
	if err := client.call(
		"Input.action",
		map[string]any{
			"action": "move_right",
			"value":  1,
			"frames": 25,
		},
		&actionResult,
	); err != nil {
		return report, err
	}
	if err := client.call(
		"Input.action",
		map[string]any{
			"action": "jump",
			"value":  1,
			"frames": 1,
		},
		&actionResult,
	); err != nil {
		return report, err
	}

	for attempt := 0; attempt < 120; attempt++ {
		if err := requestAndWaitSteps(client, steps, 1); err != nil {
			return report, err
		}
		steps++
		if err := client.call(
			"World.getSnapshot",
			nil,
			&snapshot,
		); err != nil {
			return report, err
		}
		player, err = entityByID(snapshot.Entities, report.PlayerID)
		if err != nil {
			return report, err
		}
		report.ApexY = math.Min(report.ApexY, player.Y)
		if !player.Grounded {
			report.Jumped = true
		}
		if report.Jumped &&
			report.Screenshot == "" &&
			player.Y < 405 {
			report.Screenshot =
				filepath.Join(artifacts, "platformer_slice.png")
			if err := captureScreenshot(
				client,
				report.Screenshot,
			); err != nil {
				return report, err
			}
		}
		if report.Jumped && player.Grounded {
			report.Landed = true
			report.Grounded = true
			report.LandingX = player.X
			report.LandingY = player.Y
			break
		}
	}
	report.HorizontalDelta = report.LandingX - report.StartX
	if !report.Jumped ||
		!report.Landed ||
		report.Screenshot == "" ||
		report.StartY-report.ApexY < 105 ||
		math.Abs(report.LandingY-375) > 0.02 ||
		report.HorizontalDelta < 60 ||
		!snapshotHasEventName(snapshot, "platformer.jumped") ||
		!snapshotHasEventName(snapshot, "platformer.landed") {
		return report, fmt.Errorf(
			"platformer jump/ledge landing failed: %#v",
			report,
		)
	}
	return report, nil
}

func runWorldScenario(
	client *protocolClient,
	artifacts string,
) (worldVisualReport, error) {
	var report worldVisualReport
	var runtime runtimeState
	if err := client.call(
		"App.loadStage",
		map[string]any{
			"stageId": "stage.world_hub",
			"spawnId": "default",
		},
		&runtime,
	); err != nil {
		return report, err
	}

	var hub worldSnapshot
	if err := client.call("World.getSnapshot", nil, &hub); err != nil {
		return report, err
	}
	report.HubStage = hub.Stage.ID
	report.TileLayers = hub.Tilemap.LayerCount
	report.Tilesets = hub.Tilemap.TilesetCount
	report.Walls = hub.Geometry.WallCount
	report.SpawnPoints = hub.Navigation.SpawnPointCount
	report.Triggers = hub.Navigation.TriggerCount
	report.Portals = hub.Navigation.PortalCount
	report.CameraStartX = hub.Camera.X
	if report.HubStage != "stage.world_hub" ||
		!hub.Tilemap.Available ||
		report.TileLayers < 1 ||
		report.Tilesets < 1 ||
		report.Walls < 1 ||
		report.SpawnPoints < 1 ||
		report.Triggers < 1 ||
		report.Portals < 1 {
		return report, fmt.Errorf(
			"canonical hub snapshot is incomplete: %#v",
			hub,
		)
	}
	player, err := entityWithTag(hub.Entities, "player")
	if err != nil {
		return report, err
	}

	var positioned entityState
	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": player.ID,
			"x":        900,
			"y":        288,
		},
		&positioned,
	); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(
		client,
		runtime.Simulation.SteppedFrames,
		1,
	); err != nil {
		return report, err
	}
	runtime.Simulation.SteppedFrames++
	var scrolled worldSnapshot
	if err := client.call("World.getSnapshot", nil, &scrolled); err != nil {
		return report, err
	}
	report.CameraScrolledX = scrolled.Camera.X
	if report.CameraScrolledX <= report.CameraStartX {
		return report, fmt.Errorf(
			"camera did not follow across large map: %.2f -> %.2f",
			report.CameraStartX,
			report.CameraScrolledX,
		)
	}
	var screenPoint struct {
		X     float64 `json:"x"`
		Y     float64 `json:"y"`
		Scale float64 `json:"scale"`
	}
	if err := client.call(
		"World.worldToScreen",
		map[string]any{"x": 900, "y": 288},
		&screenPoint,
	); err != nil {
		return report, err
	}
	if screenPoint.X < 0 || screenPoint.X > 960 ||
		screenPoint.Y < 0 || screenPoint.Y > 540 ||
		screenPoint.Scale <= 1 {
		return report, fmt.Errorf(
			"camera world-to-screen transform is invalid: %#v",
			screenPoint,
		)
	}

	report.CollisionStartX = 990
	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": player.ID,
			"x":        report.CollisionStartX,
			"y":        100,
		},
		&positioned,
	); err != nil {
		return report, err
	}
	var result map[string]any
	if err := client.call(
		"Input.action",
		map[string]any{
			"action": "move_right",
			"value":  1,
			"frames": 30,
		},
		&result,
	); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(
		client,
		runtime.Simulation.SteppedFrames,
		30,
	); err != nil {
		return report, err
	}
	runtime.Simulation.SteppedFrames += 30
	var collided entityState
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": player.ID},
		&collided,
	); err != nil {
		return report, err
	}
	report.CollisionEndX = collided.X
	if report.CollisionEndX > 1042 {
		return report, fmt.Errorf(
			"stage wall did not block player: %.2f -> %.2f",
			report.CollisionStartX,
			report.CollisionEndX,
		)
	}

	if err := client.call(
		"Entity.setHealth",
		map[string]any{"entityId": player.ID, "value": 40},
		&positioned,
	); err != nil {
		return report, err
	}
	report.HealthBefore = positioned.Health
	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": player.ID,
			"x":        200,
			"y":        180,
		},
		&positioned,
	); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(
		client,
		runtime.Simulation.SteppedFrames,
		1,
	); err != nil {
		return report, err
	}
	runtime.Simulation.SteppedFrames++
	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": player.ID,
			"x":        314,
			"y":        286,
		},
		&positioned,
	); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(
		client,
		runtime.Simulation.SteppedFrames,
		1,
	); err != nil {
		return report, err
	}
	runtime.Simulation.SteppedFrames++
	var triggered worldSnapshot
	if err := client.call("World.getSnapshot", nil, &triggered); err != nil {
		return report, err
	}
	triggeredPlayer, err := entityWithTag(triggered.Entities, "player")
	if err != nil {
		return report, err
	}
	report.HealthAfter = triggeredPlayer.Health
	report.TriggerFired = snapshotHasEventName(triggered, "trigger.entered")
	if report.HealthAfter-report.HealthBefore != 15 || !report.TriggerFired {
		return report, fmt.Errorf(
			"healing trigger failed: HP %.0f -> %.0f, event=%t",
			report.HealthBefore,
			report.HealthAfter,
			report.TriggerFired,
		)
	}

	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": player.ID,
			"x":        900,
			"y":        288,
		},
		&positioned,
	); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(
		client,
		runtime.Simulation.SteppedFrames,
		1,
	); err != nil {
		return report, err
	}
	runtime.Simulation.SteppedFrames++
	if err := client.call(
		"Overlay.set",
		map[string]any{
			"enabled":  true,
			"entities": true,
			"labels":   true,
		},
		&result,
	); err != nil {
		return report, err
	}
	report.HubScreenshot = filepath.Join(artifacts, "world_hub.png")
	if err := captureScreenshot(client, report.HubScreenshot); err != nil {
		return report, err
	}

	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": player.ID,
			"x":        1000,
			"y":        288,
		},
		&positioned,
	); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(
		client,
		runtime.Simulation.SteppedFrames,
		1,
	); err != nil {
		return report, err
	}
	runtime.Simulation.SteppedFrames++
	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": player.ID,
			"x":        1072,
			"y":        288,
		},
		&positioned,
	); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(
		client,
		runtime.Simulation.SteppedFrames,
		1,
	); err != nil {
		return report, err
	}
	runtime.Simulation.SteppedFrames++

	var grove worldSnapshot
	if err := client.call("World.getSnapshot", nil, &grove); err != nil {
		return report, err
	}
	report.GroveStage = grove.Stage.ID
	grovePlayer, err := entityWithTag(grove.Entities, "player")
	if err != nil {
		return report, err
	}
	if report.GroveStage != "stage.world_grove" ||
		math.Abs(grovePlayer.X-96) > 0.001 ||
		math.Abs(grovePlayer.Y-288) > 0.001 ||
		!grove.Tilemap.Available {
		return report, fmt.Errorf(
			"portal did not enter grove spawn: stage=%s position=(%.2f, %.2f)",
			report.GroveStage,
			grovePlayer.X,
			grovePlayer.Y,
		)
	}

	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": grovePlayer.ID,
			"x":        630,
			"y":        410,
		},
		&positioned,
	); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(
		client,
		runtime.Simulation.SteppedFrames,
		1,
	); err != nil {
		return report, err
	}
	runtime.Simulation.SteppedFrames++
	var discovered worldSnapshot
	if err := client.call("World.getSnapshot", nil, &discovered); err != nil {
		return report, err
	}
	if !snapshotHasEventName(discovered, "world.grove_discovered") {
		return report, errors.New("generic emit trigger did not fire in grove")
	}
	report.GroveScreenshot = filepath.Join(artifacts, "world_grove.png")
	if err := captureScreenshot(client, report.GroveScreenshot); err != nil {
		return report, err
	}

	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": grovePlayer.ID,
			"x":        60,
			"y":        288,
		},
		&positioned,
	); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(
		client,
		runtime.Simulation.SteppedFrames,
		1,
	); err != nil {
		return report, err
	}
	runtime.Simulation.SteppedFrames++
	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": grovePlayer.ID,
			"x":        16,
			"y":        288,
		},
		&positioned,
	); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(
		client,
		runtime.Simulation.SteppedFrames,
		1,
	); err != nil {
		return report, err
	}
	runtime.Simulation.SteppedFrames++

	var returned worldSnapshot
	if err := client.call("World.getSnapshot", nil, &returned); err != nil {
		return report, err
	}
	report.ReturnStage = returned.Stage.ID
	returnedPlayer, err := entityWithTag(returned.Entities, "player")
	if err != nil {
		return report, err
	}
	report.ReturnX = returnedPlayer.X
	report.ReturnY = returnedPlayer.Y
	if report.ReturnStage != "stage.world_hub" ||
		math.Abs(report.ReturnX-980) > 0.001 ||
		math.Abs(report.ReturnY-288) > 0.001 {
		return report, fmt.Errorf(
			"return portal did not apply hub spawn: stage=%s position=(%.2f, %.2f)",
			report.ReturnStage,
			report.ReturnX,
			report.ReturnY,
		)
	}
	if err := client.call("Runtime.getState", nil, &runtime); err != nil {
		return report, err
	}
	report.PortalTransitions = runtime.Transitions
	if report.PortalTransitions != 2 {
		return report, fmt.Errorf(
			"expected 2 portal transitions, got %d",
			report.PortalTransitions,
		)
	}
	return report, nil
}

func runRPGScenario(
	client *protocolClient,
	artifacts string,
) (rpgVisualReport, error) {
	var report rpgVisualReport
	var runtime runtimeState
	if err := client.call(
		"App.loadStage",
		map[string]any{"stageId": "stage.rpg_village"},
		&runtime,
	); err != nil {
		return report, err
	}
	steps := runtime.Simulation.SteppedFrames

	var snapshot worldSnapshot
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	report.Stage = snapshot.Stage.ID
	report.Locale = snapshot.Locale.Code
	if report.Stage != "stage.rpg_village" || report.Locale != "ko" {
		return report, fmt.Errorf(
			"RPG stage or locale is incomplete: stage=%q locale=%q",
			report.Stage,
			report.Locale,
		)
	}
	player, err := entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return report, err
	}
	var changed entityState
	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": player.ID,
			"x":        205,
			"y":        240,
		},
		&changed,
	); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(client, steps, 1); err != nil {
		return report, err
	}
	steps++
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	if snapshot.Interaction.TargetID != "guide" {
		return report, fmt.Errorf(
			"guide interaction was not discoverable: %#v",
			snapshot.Interaction,
		)
	}

	if err := performSemanticInput(client, &steps, "interact", 1); err != nil {
		return report, err
	}
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	report.DialogueID = snapshot.Dialogue.DialogueID
	report.DialogueNode = snapshot.Dialogue.NodeID
	report.DialogueText = snapshot.Dialogue.Text
	if !snapshot.Dialogue.Active ||
		report.DialogueID != "dialogue.guide" ||
		report.DialogueNode != "greeting" ||
		!strings.Contains(report.DialogueText, "슬라임") ||
		len(snapshot.Dialogue.Choices) < 2 ||
		snapshot.Dialogue.Choices[0].ID != "accept" {
		return report, fmt.Errorf(
			"localized dialogue did not open correctly: %#v",
			snapshot.Dialogue,
		)
	}
	report.DialogueScreenshot =
		filepath.Join(artifacts, "rpg_dialogue.png")
	if err := captureScreenshot(
		client,
		report.DialogueScreenshot,
	); err != nil {
		return report, err
	}

	if err := performSemanticInput(
		client,
		&steps,
		"menu_confirm",
		1,
	); err != nil {
		return report, err
	}
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	quest, err := questByID(snapshot.Quests, "quest.slime_patrol")
	if err != nil {
		return report, err
	}
	player, err = entityByID(snapshot.Entities, player.ID)
	if err != nil {
		return report, err
	}
	report.QuestID = quest.ID
	report.QuestStatus = quest.Status
	report.EquippedItem = equippedItem(player, "weapon")
	report.AttackStat = player.Stats.Attack
	if snapshot.Dialogue.NodeID != "accepted" ||
		quest.Status != "active" ||
		inventoryCount(snapshot.Inventory, "item.training_sword") != 1 ||
		report.EquippedItem != "item.training_sword" ||
		report.AttackStat != 5 {
		return report, fmt.Errorf(
			"dialogue actions did not start/equip quest state: quest=%#v player=%#v",
			quest,
			player,
		)
	}
	report.QuestScreenshot =
		filepath.Join(artifacts, "rpg_quest_started.png")
	if err := captureScreenshot(
		client,
		report.QuestScreenshot,
	); err != nil {
		return report, err
	}
	if err := performSemanticInput(
		client,
		&steps,
		"menu_confirm",
		1,
	); err != nil {
		return report, err
	}

	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": "quest.slime.1",
			"x":        player.X + 50,
			"y":        player.Y,
		},
		&changed,
	); err != nil {
		return report, err
	}
	if err := client.call(
		"Entity.setHealth",
		map[string]any{
			"entityId": "quest.slime.1",
			"value":    68,
		},
		&changed,
	); err != nil {
		return report, err
	}
	if err := performSemanticInput(client, &steps, "attack", 1); err != nil {
		return report, err
	}
	var damaged entityState
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": "quest.slime.1"},
		&damaged,
	); err != nil {
		return report, err
	}
	report.EquippedAttackDamage = 68 - damaged.Health
	if report.EquippedAttackDamage != 39 {
		return report, fmt.Errorf(
			"equipped stat did not modify actual attack: damage %.0f",
			report.EquippedAttackDamage,
		)
	}
	if err := requestAndWaitSteps(client, steps, 18); err != nil {
		return report, err
	}
	steps += 18
	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": "quest.slime.1",
			"x":        player.X + 50,
			"y":        player.Y,
		},
		&changed,
	); err != nil {
		return report, err
	}
	if err := performSemanticInput(client, &steps, "attack", 1); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(client, steps, 22); err != nil {
		return report, err
	}
	steps += 22

	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": "quest.slime.2",
			"x":        player.X + 50,
			"y":        player.Y,
		},
		&changed,
	); err != nil {
		return report, err
	}
	if err := client.call(
		"Entity.setHealth",
		map[string]any{
			"entityId": "quest.slime.2",
			"value":    1,
		},
		&changed,
	); err != nil {
		return report, err
	}
	if err := performSemanticInput(client, &steps, "attack", 1); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(client, steps, 30); err != nil {
		return report, err
	}
	steps += 30
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	quest, err = questByID(snapshot.Quests, report.QuestID)
	if err != nil {
		return report, err
	}
	report.QuestStatus = quest.Status
	if len(quest.Objectives) != 1 {
		return report, errors.New("RPG quest objective snapshot is incomplete")
	}
	report.QuestProgress = quest.Objectives[0].Count
	report.QuestGoal = quest.Objectives[0].Goal
	report.Currency = snapshot.Currency.Balance
	report.PotionCount = inventoryCount(snapshot.Inventory, "item.potion")
	if report.QuestStatus != "completed" ||
		report.QuestProgress != 2 ||
		report.QuestGoal != 2 ||
		report.Currency != 100 ||
		report.PotionCount != 1 ||
		!snapshot.Flags["quest.slime_patrol.rewarded"] {
		return report, fmt.Errorf(
			"quest completion/reward failed: quest=%#v currency=%d potion=%d flags=%#v",
			quest,
			report.Currency,
			report.PotionCount,
			snapshot.Flags,
		)
	}
	report.QuestCompleteScreenshot =
		filepath.Join(artifacts, "rpg_quest_complete.png")
	if err := captureScreenshot(
		client,
		report.QuestCompleteScreenshot,
	); err != nil {
		return report, err
	}

	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": player.ID,
			"x":        340,
			"y":        240,
		},
		&changed,
	); err != nil {
		return report, err
	}
	if err := requestAndWaitSteps(client, steps, 1); err != nil {
		return report, err
	}
	steps++
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	if snapshot.Interaction.TargetID != "merchant" {
		return report, fmt.Errorf(
			"merchant interaction was not discoverable: %#v",
			snapshot.Interaction,
		)
	}
	if err := performSemanticInput(client, &steps, "interact", 1); err != nil {
		return report, err
	}
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	if !snapshot.Shop.Active ||
		snapshot.Shop.ShopID != "shop.village" ||
		snapshot.Shop.Balance != 100 {
		return report, fmt.Errorf(
			"shop did not open: %#v",
			snapshot.Shop,
		)
	}
	if err := performSemanticInput(
		client,
		&steps,
		"menu_confirm",
		1,
	); err != nil {
		return report, err
	}
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	report.Currency = snapshot.Shop.Balance
	report.PotionCount = inventoryCount(snapshot.Inventory, "item.potion")
	report.ShopPurchased = report.Currency == 75 &&
		report.PotionCount == 2 &&
		snapshot.Shop.Message == "Purchased"
	if !report.ShopPurchased {
		return report, fmt.Errorf(
			"shop purchase failed: shop=%#v potion=%d",
			snapshot.Shop,
			report.PotionCount,
		)
	}
	report.ShopScreenshot = filepath.Join(artifacts, "rpg_shop.png")
	if err := captureScreenshot(client, report.ShopScreenshot); err != nil {
		return report, err
	}

	if err := performSemanticInput(
		client,
		&steps,
		"menu_right",
		1,
	); err != nil {
		return report, err
	}
	if err := performSemanticInput(
		client,
		&steps,
		"menu_down",
		1,
	); err != nil {
		return report, err
	}
	if err := performSemanticInput(
		client,
		&steps,
		"menu_confirm",
		1,
	); err != nil {
		return report, err
	}
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	report.EquippedSaleBlocked =
		strings.Contains(snapshot.Shop.Message, "equipped item") &&
			snapshot.Shop.Balance == 75 &&
			inventoryCount(
				snapshot.Inventory,
				"item.training_sword",
			) == 1
	if !report.EquippedSaleBlocked {
		return report, fmt.Errorf(
			"equipped item sale was not blocked: %#v",
			snapshot.Shop,
		)
	}
	if err := performSemanticInput(
		client,
		&steps,
		"menu_cancel",
		1,
	); err != nil {
		return report, err
	}

	if err := client.call(
		"App.loadStage",
		map[string]any{"stageId": "stage.action_room"},
		&runtime,
	); err != nil {
		return report, err
	}
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return report, err
	}
	persistedQuest, questError :=
		questByID(snapshot.Quests, report.QuestID)
	persistedPlayer, playerError :=
		entityWithTag(snapshot.Entities, "player")
	report.SessionPersisted =
		questError == nil &&
			playerError == nil &&
			persistedQuest.Status == "completed" &&
			snapshot.Currency.Balance == 75 &&
			inventoryCount(snapshot.Inventory, "item.potion") == 2 &&
			equippedItem(persistedPlayer, "weapon") ==
				"item.training_sword" &&
			persistedPlayer.Stats.Attack == 5
	if !report.SessionPersisted {
		return report, fmt.Errorf(
			"RPG session did not persist across stage load: quest=%#v player=%#v snapshot=%#v",
			persistedQuest,
			persistedPlayer,
			snapshot,
		)
	}
	return report, nil
}

func performSemanticInput(
	client *protocolClient,
	steps *int,
	action string,
	frames int,
) error {
	var result map[string]any
	if err := client.call(
		"Input.action",
		map[string]any{
			"action": action,
			"value":  1,
			"frames": frames,
		},
		&result,
	); err != nil {
		return err
	}
	if err := requestAndWaitSteps(client, *steps, frames); err != nil {
		return err
	}
	*steps += frames
	return nil
}

func requestAndWaitSteps(
	client *protocolClient,
	start int,
	frames int,
) error {
	var result map[string]any
	if err := client.call(
		"Test.step",
		map[string]any{"frames": frames, "dt": 1.0 / 60.0},
		&result,
	); err != nil {
		return err
	}

	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		var state runtimeState
		if err := client.call("Runtime.getState", nil, &state); err == nil {
			if state.Simulation.SteppedFrames >= start+frames {
				return nil
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	return fmt.Errorf("timed out waiting for %d simulation frames", frames)
}

func stepUntilWindupRemaining(
	client *protocolClient,
	entityID string,
	steps *int,
	threshold float64,
) error {
	for attempt := 0; attempt < 30; attempt++ {
		var entity entityState
		if err := client.call(
			"Entity.get",
			map[string]any{"entityId": entityID},
			&entity,
		); err != nil {
			return err
		}
		if entity.AttackPhase != "windup" {
			return fmt.Errorf(
				"expected %s windup, got %q with %.4fs remaining",
				entityID,
				entity.AttackPhase,
				entity.AttackRemaining,
			)
		}
		if entity.AttackRemaining <= threshold {
			return nil
		}
		if err := requestAndWaitSteps(client, *steps, 1); err != nil {
			return err
		}
		*steps++
	}
	return fmt.Errorf(
		"%s windup did not reach %.3fs",
		entityID,
		threshold,
	)
}

func entityWithTag(entities []entityState, tag string) (entityState, error) {
	for _, entity := range entities {
		for _, candidate := range entity.Tags {
			if candidate == tag {
				return entity, nil
			}
		}
	}
	return entityState{}, fmt.Errorf("no entity has tag %q", tag)
}

func entityByID(entities []entityState, id string) (entityState, error) {
	for _, entity := range entities {
		if entity.ID == id {
			return entity, nil
		}
	}
	return entityState{}, fmt.Errorf("no entity has id %q", id)
}

func liveEntitiesWithTag(
	entities []entityState,
	tag string,
) []entityState {
	result := make([]entityState, 0)
	for _, entity := range entities {
		if entity.Dead {
			continue
		}
		for _, candidate := range entity.Tags {
			if candidate == tag {
				result = append(result, entity)
				break
			}
		}
	}
	return result
}

func hasComponent(entity entityState, name string) bool {
	for _, component := range entity.Components {
		if component == name {
			return true
		}
	}
	return false
}

func encounterByID(
	encounters []encounterState,
	id string,
) (encounterState, error) {
	for _, encounter := range encounters {
		if encounter.ID == id {
			return encounter, nil
		}
	}
	return encounterState{}, fmt.Errorf("no encounter has id %q", id)
}

func inventoryCount(entries []inventoryState, itemID string) int {
	for _, entry := range entries {
		if entry.ItemID == itemID {
			return entry.Count
		}
	}
	return 0
}

func questByID(quests []questState, id string) (questState, error) {
	for _, quest := range quests {
		if quest.ID == id {
			return quest, nil
		}
	}
	return questState{}, fmt.Errorf("no quest has id %q", id)
}

func equippedItem(entity entityState, slot string) string {
	for _, entry := range entity.Equipment {
		if entry.Slot == slot {
			return entry.ItemID
		}
	}
	return ""
}

func snapshotHasEvent(
	snapshot worldSnapshot,
	name string,
	targetID string,
) bool {
	for _, event := range snapshot.Events {
		if event.Name != name {
			continue
		}
		var payload map[string]any
		if err := json.Unmarshal(event.Payload, &payload); err != nil {
			continue
		}
		target, ok := payload["target_id"].(string)
		if ok && target == targetID {
			return true
		}
	}
	return false
}

func snapshotHasEventName(snapshot worldSnapshot, name string) bool {
	for _, event := range snapshot.Events {
		if event.Name == name {
			return true
		}
	}
	return false
}

func countAbilityHits(
	snapshot worldSnapshot,
	abilityID string,
	targetID string,
) int {
	count := 0
	for _, event := range snapshot.Events {
		if event.Name != "ability.hit" {
			continue
		}
		var payload map[string]any
		if err := json.Unmarshal(event.Payload, &payload); err != nil {
			continue
		}
		if payload["ability_id"] == abilityID &&
			payload["target_id"] == targetID {
			count++
		}
	}
	return count
}

func prepareArtifacts(argument string) (string, error) {
	if argument == "" {
		return os.MkdirTemp("", "32_recreate_visual_")
	}
	absolute, err := filepath.Abs(argument)
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(absolute, 0o755); err != nil {
		return "", err
	}
	return absolute, nil
}

func availablePort() (int, error) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer listener.Close()
	return listener.Addr().(*net.TCPAddr).Port, nil
}

func startLove(
	lovePath string,
	projectPath string,
	port int,
	logFile *os.File,
) (*loveProcess, error) {
	command := exec.Command(lovePath, projectPath)
	command.Dir = projectPath
	command.Env = append(
		debugEnvironment(port),
		"RECREATE_AUTOMATION=1",
		"LIBGL_ALWAYS_SOFTWARE=1",
	)
	command.Stdout = logFile
	command.Stderr = logFile
	if err := command.Start(); err != nil {
		return nil, err
	}
	process := &loveProcess{
		command: command,
		done:    make(chan error, 1),
	}
	go func() {
		process.done <- command.Wait()
	}()
	return process, nil
}

func waitForBridge(
	client *protocolClient,
	process *loveProcess,
	timeout time.Duration,
) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		select {
		case err := <-process.done:
			process.command = nil
			return fmt.Errorf("LÖVE exited before debug bridge: %w", err)
		default:
		}

		var result struct {
			Pong bool `json:"pong"`
		}
		if err := client.call("Runtime.ping", nil, &result); err == nil &&
			result.Pong {
			return nil
		}
		time.Sleep(25 * time.Millisecond)
	}
	return errors.New("timed out waiting for debug bridge")
}

func forceStop(process *loveProcess) {
	if process == nil || process.command == nil ||
		process.command.Process == nil {
		return
	}
	_ = process.command.Process.Kill()
	select {
	case <-process.done:
	case <-time.After(3 * time.Second):
	}
	process.command = nil
}

func visualFailure(err error, logPath string) error {
	return fmt.Errorf("%w (LÖVE log: %s)", err, logPath)
}
