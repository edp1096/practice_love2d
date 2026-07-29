// Package sim implements the deterministic, renderer-independent game
// simulation used by the Ebitengine spike.
//
// All distances are fixed-point Coord values and all durations are integral
// simulation ticks. The package deliberately does not import Ebitengine so it
// can be driven by tests, a debug server, or another renderer.
package sim

// UnitsPerPixel is the number of fixed-point coordinate units in one logical
// pixel. Converting to float is a presentation concern:
//
//	float64(coord) / float64(sim.UnitsPerPixel)
const UnitsPerPixel Coord = 1024

// TicksPerSecond is the fixed simulation rate expected by demo content.
const TicksPerSecond = 60

// MaxTickCount is the largest duration accepted by simulation configuration
// and session validation. Keeping this explicit lets content translators
// reject float-to-int overflow before it can vary by target architecture.
const MaxTickCount = 1_000_000

// MaxStatusStacks bounds both authored and restored status state. It keeps
// repeated fixed-point modifier application and periodic damage deterministic
// even for hostile or corrupted content.
const MaxStatusStacks = 99

// Coord is a deterministic fixed-point world coordinate.
type Coord int64

// Pixels converts a whole logical pixel count into fixed-point coordinates.
func Pixels(value int64) Coord {
	return Coord(value) * UnitsPerPixel
}

// Vec is a fixed-point two-dimensional vector.
type Vec struct {
	X Coord `json:"x"`
	Y Coord `json:"y"`
}

// Rect is an axis-aligned rectangle. Max coordinates are exclusive for point
// containment, while touching edges do not count as an overlap.
type Rect struct {
	MinX Coord `json:"min_x"`
	MinY Coord `json:"min_y"`
	MaxX Coord `json:"max_x"`
	MaxY Coord `json:"max_y"`
}

// Wall is immutable collision geometry with a stable authored identity.
// Rect is the collision rectangle for an axis-aligned wall and the exact
// bounds for a polygon wall. Points is empty for rectangles; otherwise it
// contains the authored, fixed-point vertices of a strictly convex polygon.
//
// Keeping Rect for both shapes preserves the original rectangle wire/API and
// gives broad-phase users bounds without discarding polygon geometry.
type Wall struct {
	ID     string `json:"id"`
	Rect   Rect   `json:"rect"`
	Points []Vec  `json:"points,omitempty"`
}

// Body describes an axis-aligned entity collision body.
type Body struct {
	HalfWidth  Coord `json:"half_width"`
	HalfHeight Coord `json:"half_height"`
	Solid      bool  `json:"solid"`
}

// AbilityConfig is one authored combat action. An ability may use an arc
// hitbox, spawn a projectile when it becomes active, or do both.
// ArcDegrees is the full facing arc and must be in [1, 360] when Reach is
// positive. MaxHits defaults to one; repeat hits require RepeatIntervalTicks.
type AbilityConfig struct {
	ID                  string `json:"id"`
	WindupTicks         int    `json:"windup_ticks"`
	ActiveTicks         int    `json:"active_ticks"`
	RecoveryTicks       int    `json:"recovery_ticks"`
	CooldownTicks       int    `json:"cooldown_ticks"`
	LockMovement        bool   `json:"lock_movement"`
	Reach               Coord  `json:"reach"`
	ArcDegrees          int    `json:"arc_degrees"`
	Damage              int    `json:"damage"`
	StaggerTicks        int    `json:"stagger_ticks"`
	Knockback           Coord  `json:"knockback"`
	KnockbackTicks      int    `json:"knockback_ticks"`
	HitstopTicks        int    `json:"hitstop_ticks"`
	CameraShake         Coord  `json:"camera_shake"`
	CameraShakeTicks    int    `json:"camera_shake_ticks"`
	MaxHits             int    `json:"max_hits,omitempty"`
	RepeatIntervalTicks int    `json:"repeat_interval_ticks,omitempty"`
	ProjectileID        string `json:"projectile_id,omitempty"`
}

// AbilityBinding maps an input meaning such as attack, special, or technique
// to a loadout ability. Device keys never appear in the deterministic sim.
type AbilityBinding struct {
	Input     string `json:"input"`
	AbilityID string `json:"ability_id"`
}

// CombatConfig is an actor's complete data-authored ability loadout.
// Abilities and Bindings are kept as sorted slices so snapshots, sessions, and
// debug payloads have deterministic ordering.
type CombatConfig struct {
	PrimaryAbilityID string           `json:"primary_ability_id"`
	Abilities        []AbilityConfig  `json:"abilities"`
	Bindings         []AbilityBinding `json:"bindings,omitempty"`
}

// ImpactConfig is the ordered combat-effect subset shared by melee abilities
// and projectiles. ApplyStatusID is resolved after damage and reaction effects
// only when the target survives.
type ImpactConfig struct {
	Damage           int    `json:"damage"`
	StaggerTicks     int    `json:"stagger_ticks"`
	ApplyStatusID    string `json:"apply_status_id,omitempty"`
	Knockback        Coord  `json:"knockback"`
	KnockbackTicks   int    `json:"knockback_ticks"`
	HitstopTicks     int    `json:"hitstop_ticks"`
	CameraShake      Coord  `json:"camera_shake"`
	CameraShakeTicks int    `json:"camera_shake_ticks"`
}

// ProjectileConfig is immutable continuous-collision content.
type ProjectileConfig struct {
	ID            string       `json:"id"`
	ActorKind     string       `json:"actor_kind"`
	Body          Body         `json:"body"`
	Tint          [4]uint8     `json:"tint"`
	SpeedPerTick  Coord        `json:"speed_per_tick"`
	LifetimeTicks int          `json:"lifetime_ticks"`
	SpawnOffset   Coord        `json:"spawn_offset"`
	Pierce        int          `json:"pierce"`
	DestroyOnWall bool         `json:"destroy_on_wall"`
	Impact        ImpactConfig `json:"impact"`
}

type StatusStacking string

const (
	StatusRefresh StatusStacking = "refresh"
	StatusStack   StatusStacking = "stack"
)

// StatusConfig stores deterministic duration, periodic damage, presentation,
// and multiplicative modifiers. Multipliers use UnitsPerPixel as 1.0.
type StatusConfig struct {
	ID                string         `json:"id"`
	DurationTicks     int            `json:"duration_ticks"`
	Stacking          StatusStacking `json:"stacking"`
	MaxStacks         int            `json:"max_stacks"`
	TickIntervalTicks int            `json:"tick_interval_ticks,omitempty"`
	TickDamage        int            `json:"tick_damage,omitempty"`
	MoveSpeed         Coord          `json:"move_speed"`
	DamageDealt       Coord          `json:"damage_dealt"`
	DamageTaken       Coord          `json:"damage_taken"`
	Color             [4]uint8       `json:"color"`
}

// StatusReceiverConfig enables reusable status state and lists immunities.
type StatusReceiverConfig struct {
	Immune []string `json:"immune,omitempty"`
}

// PlatformerConfig is an actor-local movement controller. Speeds are
// fixed-point distance per simulation tick; accelerations and gravity are the
// per-tick changes to velocity. Keeping this on the actor avoids a global
// topdown/platformer game-mode branch.
type PlatformerConfig struct {
	MaxSpeedPerTick     Coord `json:"max_speed_per_tick"`
	AccelerationPerTick Coord `json:"acceleration_per_tick"`
	AirAcceleration     Coord `json:"air_acceleration_per_tick"`
	DecelerationPerTick Coord `json:"deceleration_per_tick"`
	GravityPerTick      Coord `json:"gravity_per_tick"`
	JumpSpeedPerTick    Coord `json:"jump_speed_per_tick"`
	MaxFallSpeedPerTick Coord `json:"max_fall_speed_per_tick"`
	CoyoteTicks         int   `json:"coyote_ticks"`
	JumpBufferTicks     int   `json:"jump_buffer_ticks"`
}

type EncounterActionType string

const (
	EncounterEmit        EncounterActionType = "emit"
	EncounterApplyStatus EncounterActionType = "apply_status"
)

// EncounterActionConfig is the deterministic action subset used by authored
// wave and boss-phase fixtures. The content adapter rejects unsupported
// actions instead of silently discarding them.
type EncounterActionConfig struct {
	Type     EncounterActionType `json:"type"`
	Event    string              `json:"event,omitempty"`
	StatusID string              `json:"status_id,omitempty"`
}

type EncounterSpawnConfig struct {
	ID     string       `json:"id"`
	Entity EntityConfig `json:"entity"`
}

type BossPhaseConfig struct {
	ID                string                  `json:"id"`
	SpawnID           string                  `json:"spawn_id"`
	HealthRatioAtMost Coord                   `json:"health_ratio_at_most"`
	Actions           []EncounterActionConfig `json:"actions"`
}

type EncounterWaveConfig struct {
	ID         string                  `json:"id"`
	DelayTicks int                     `json:"delay_ticks"`
	Spawns     []EncounterSpawnConfig  `json:"spawns"`
	BossPhases []BossPhaseConfig       `json:"boss_phases,omitempty"`
	OnStart    []EncounterActionConfig `json:"on_start,omitempty"`
	OnComplete []EncounterActionConfig `json:"on_complete,omitempty"`
}

// EncounterConfig is one stage placement with already translated absolute
// spawn definitions. Wave order remains authored; placements are sorted by ID.
type EncounterConfig struct {
	ID             string                  `json:"id"`
	DefinitionID   string                  `json:"definition_id"`
	TargetEntityID string                  `json:"target_entity_id"`
	AutoStart      bool                    `json:"auto_start"`
	Waves          []EncounterWaveConfig   `json:"waves"`
	OnComplete     []EncounterActionConfig `json:"on_complete,omitempty"`
}

// Ability returns mutable configuration owned by this CombatConfig.
func (config *CombatConfig) Ability(id string) *AbilityConfig {
	if config == nil {
		return nil
	}
	for index := range config.Abilities {
		if config.Abilities[index].ID == id {
			return &config.Abilities[index]
		}
	}
	return nil
}

// PrimaryAbility returns the configured primary action.
func (config *CombatConfig) PrimaryAbility() *AbilityConfig {
	if config == nil {
		return nil
	}
	return config.Ability(config.PrimaryAbilityID)
}

// AbilityForInput resolves one semantic binding.
func (config *CombatConfig) AbilityForInput(input string) *AbilityConfig {
	if config == nil {
		return nil
	}
	for _, binding := range config.Bindings {
		if binding.Input == input {
			return config.Ability(binding.AbilityID)
		}
	}
	return nil
}

// ReactionConfig controls hit invulnerability and presentation feedback.
type ReactionConfig struct {
	HitInvulnerabilityTicks int `json:"hit_invulnerability_ticks"`
	FlashTicks              int `json:"flash_ticks"`
}

// DodgeConfig controls deterministic burst motion and invulnerability.
type DodgeConfig struct {
	DurationTicks        int   `json:"duration_ticks"`
	Distance             Coord `json:"distance"`
	InvulnerabilityTicks int   `json:"invulnerability_ticks"`
	CooldownTicks        int   `json:"cooldown_ticks"`
}

// ParryConfig controls the guarding arc and perfect-parry window.
type ParryConfig struct {
	WindowTicks          int   `json:"window_ticks"`
	PerfectWindowTicks   int   `json:"perfect_window_ticks"`
	CooldownTicks        int   `json:"cooldown_ticks"`
	SuccessCooldownTicks int   `json:"success_cooldown_ticks"`
	ArcDegrees           int   `json:"arc_degrees"`
	StaggerTicks         int   `json:"stagger_ticks"`
	PerfectStaggerTicks  int   `json:"perfect_stagger_ticks"`
	HitstopTicks         int   `json:"hitstop_ticks"`
	PerfectHitstopTicks  int   `json:"perfect_hitstop_ticks"`
	CameraShake          Coord `json:"camera_shake"`
	CameraShakeTicks     int   `json:"camera_shake_ticks"`
}

// EntityConfig is immutable content used to construct an entity. Runtime state
// is deliberately kept out of this type.
type EntityConfig struct {
	ID          string `json:"id"`
	Kind        string `json:"kind"`
	Name        string `json:"name"`
	Team        string `json:"team,omitempty"`
	Position    Vec    `json:"position"`
	Body        Body   `json:"body"`
	MaxHealth   int    `json:"max_health"`
	MovePerTick Coord  `json:"move_per_tick"`
	Facing      Vec    `json:"facing"`
	Controlled  bool   `json:"controlled,omitempty"`

	Combat *CombatConfig `json:"combat,omitempty"`
	// Ability accepts protocol-v8 and test fixtures authored before loadouts
	// existed. Simulation construction normalizes it into Combat and clears
	// this field; new content must use Combat.
	Ability    *AbilityConfig        `json:"ability,omitempty"`
	Reaction   ReactionConfig        `json:"reaction"`
	Dodge      *DodgeConfig          `json:"dodge,omitempty"`
	Parry      *ParryConfig          `json:"parry,omitempty"`
	Status     *StatusReceiverConfig `json:"status,omitempty"`
	Platformer *PlatformerConfig     `json:"platformer,omitempty"`

	// DialogueID makes the entity interactable. StartQuestID is started
	// transactionally when that dialogue opens.
	DialogueID   string `json:"dialogue_id,omitempty"`
	StartQuestID string `json:"start_quest_id,omitempty"`
}

// PrimaryAbility is a convenience for systems which intentionally operate on
// the loadout's primary action, such as basic enemy AI and weapon modifiers.
func (config *EntityConfig) PrimaryAbility() *AbilityConfig {
	if config == nil {
		return nil
	}
	return config.Combat.PrimaryAbility()
}

// EntityPreviewConfig is one atomic Maker-preview bundle. Dialogue and Quest
// are optional definitions needed when content is not authored by the current
// stage. Quest may be Entity.StartQuestID or a choice-only dependency anchored
// by Entity.DialogueID. InteractionRange raises (but never lowers) the authored
// range while this preview entity exists.
type EntityPreviewConfig struct {
	Entity           EntityConfig        `json:"entity"`
	Dialogue         *DialogueDefinition `json:"dialogue,omitempty"`
	Quest            *QuestDefinition    `json:"quest,omitempty"`
	InteractionRange Coord               `json:"interaction_range,omitempty"`
}

// DialoguePreviewConfig atomically previews a dialogue and an optional quest
// started by its entry node.
type DialoguePreviewConfig struct {
	Dialogue   DialogueDefinition `json:"dialogue"`
	Quest      *QuestDefinition   `json:"quest,omitempty"`
	StartQuest bool               `json:"start_quest,omitempty"`
}

// DialogueDefinition is a deliberately small data-authored dialogue node for
// the spike. A richer graph can be placed above this simulation boundary.
type DialogueDefinition struct {
	ID      string `json:"id"`
	Speaker string `json:"speaker"`
	Text    string `json:"text"`
}

// QuestDefinition tracks defeat events for an actor ID or kind. Empty match
// fields are wildcards. Required must be positive.
type QuestDefinition struct {
	ID              string `json:"id"`
	TargetEntityID  string `json:"target_entity_id,omitempty"`
	TargetKind      string `json:"target_kind,omitempty"`
	Required        int    `json:"required"`
	InitiallyActive bool   `json:"initially_active,omitempty"`
}

// CameraConfig controls follow, viewport clamping, and deterministic shake.
type CameraConfig struct {
	TargetEntityID string
	ViewportWidth  Coord
	ViewportHeight Coord
}

// Config contains immutable simulation content.
type Config struct {
	StageBounds      Rect
	Walls            []Wall
	Entities         []EntityConfig
	Dialogues        []DialogueDefinition
	Quests           []QuestDefinition
	Projectiles      []ProjectileConfig
	Statuses         []StatusConfig
	Encounters       []EncounterConfig
	Camera           CameraConfig
	InteractionRange Coord
}

// EntityInput is a semantic command for one entity. MoveX and MoveY are digital
// axes in [-1, 1]. Action booleans are press edges, not held states.
type EntityInput struct {
	EntityID  string
	MoveX     int8
	MoveY     int8
	Attack    bool
	AbilityID string
	Parry     bool
	Dodge     bool
	Jump      bool
	Interact  bool
}

// Input is one fixed-tick input frame. The top-level fields target the
// configured controlled entity. Commands allow tests, AI, and the debug
// backend to drive additional entities in the same tick. Commands are resolved
// in sorted entity-ID order; duplicate IDs use the last command.
type Input struct {
	MoveX     int8
	MoveY     int8
	Attack    bool
	AbilityID string
	Parry     bool
	Dodge     bool
	Jump      bool
	Interact  bool
	Commands  []EntityInput
}

// AttackPhase is a stable externally visible attack state.
type AttackPhase string

const (
	AttackIdle     AttackPhase = ""
	AttackWindup   AttackPhase = "windup"
	AttackActive   AttackPhase = "active"
	AttackRecovery AttackPhase = "recovery"
)

// QuestStatus is a stable externally visible quest state.
type QuestStatus string

const (
	QuestInactive  QuestStatus = "inactive"
	QuestActive    QuestStatus = "active"
	QuestCompleted QuestStatus = "completed"
)

// EventType values form the debug/event protocol for the simulation.
type EventType string

const (
	EventAttackStarted          EventType = "attack.started"
	EventAttackActive           EventType = "attack.active"
	EventAttackFinished         EventType = "attack.finished"
	EventAttackInterrupted      EventType = "attack.interrupted"
	EventDamageApplied          EventType = "damage.applied"
	EventDamageBlocked          EventType = "damage.blocked"
	EventActorStaggered         EventType = "actor.staggered"
	EventActorKilled            EventType = "actor.killed"
	EventKnockbackStarted       EventType = "knockback.started"
	EventHitstopStarted         EventType = "hitstop.started"
	EventParryStarted           EventType = "parry.started"
	EventAttackParried          EventType = "attack.parried"
	EventDodgeStarted           EventType = "dodge.started"
	EventProjectileSpawned      EventType = "projectile.spawned"
	EventProjectileHit          EventType = "projectile.hit"
	EventProjectileBlocked      EventType = "projectile.blocked"
	EventProjectileExpired      EventType = "projectile.expired"
	EventStatusApplied          EventType = "status.applied"
	EventStatusStacked          EventType = "status.stacked"
	EventStatusRefreshed        EventType = "status.refreshed"
	EventStatusTicked           EventType = "status.ticked"
	EventStatusExpired          EventType = "status.expired"
	EventStatusResisted         EventType = "status.resisted"
	EventPlatformerJumped       EventType = "platformer.jumped"
	EventPlatformerLanded       EventType = "platformer.landed"
	EventEncounterStarted       EventType = "encounter.started"
	EventEncounterWaveStarted   EventType = "encounter.wave_started"
	EventEncounterWaveCompleted EventType = "encounter.wave_completed"
	EventEncounterCompleted     EventType = "encounter.completed"
	EventEncounterActionFailed  EventType = "encounter.action_failed"
	EventBossPhaseEntered       EventType = "boss.phase_entered"
	EventEntitySpawned          EventType = "entity.spawned"
	EventEntityRemoved          EventType = "entity.removed"
	EventDialogueStarted        EventType = "dialogue.started"
	EventDialogueClosed         EventType = "dialogue.closed"
	EventQuestStarted           EventType = "quest.started"
	EventQuestProgress          EventType = "quest.progress"
	EventQuestCompleted         EventType = "quest.completed"
	EventInputRejected          EventType = "input.rejected"
)

// IsReservedEventType reports event names owned by the engine contract.
// Authored emit actions must not impersonate these events because gameapp
// assigns gameplay meaning to fields such as TargetID.
func IsReservedEventType(eventType EventType) bool {
	switch eventType {
	case EventAttackStarted,
		EventAttackActive,
		EventAttackFinished,
		EventAttackInterrupted,
		EventDamageApplied,
		EventDamageBlocked,
		EventActorStaggered,
		EventActorKilled,
		EventKnockbackStarted,
		EventHitstopStarted,
		EventParryStarted,
		EventAttackParried,
		EventDodgeStarted,
		EventProjectileSpawned,
		EventProjectileHit,
		EventProjectileBlocked,
		EventProjectileExpired,
		EventStatusApplied,
		EventStatusStacked,
		EventStatusRefreshed,
		EventStatusTicked,
		EventStatusExpired,
		EventStatusResisted,
		EventPlatformerJumped,
		EventPlatformerLanded,
		EventEncounterStarted,
		EventEncounterWaveStarted,
		EventEncounterWaveCompleted,
		EventEncounterCompleted,
		EventEncounterActionFailed,
		EventBossPhaseEntered,
		EventEntitySpawned,
		EventEntityRemoved,
		EventDialogueStarted,
		EventDialogueClosed,
		EventQuestStarted,
		EventQuestProgress,
		EventQuestCompleted,
		EventInputRejected:
		return true
	default:
		return false
	}
}

// Event is an immutable-by-copy simulation event. Only fields relevant to Type
// are populated.
type Event struct {
	Tick         uint64    `json:"tick"`
	Type         EventType `json:"type"`
	EntityID     string    `json:"entity_id,omitempty"`
	SourceID     string    `json:"source_id,omitempty"`
	TargetID     string    `json:"target_id,omitempty"`
	QuestID      string    `json:"quest_id,omitempty"`
	DialogueID   string    `json:"dialogue_id,omitempty"`
	AbilityID    string    `json:"ability_id,omitempty"`
	ProjectileID string    `json:"projectile_id,omitempty"`
	StatusID     string    `json:"status_id,omitempty"`
	EncounterID  string    `json:"encounter_id,omitempty"`
	DefinitionID string    `json:"definition_id,omitempty"`
	WaveID       string    `json:"wave_id,omitempty"`
	WaveIndex    int       `json:"wave_index,omitempty"`
	PhaseID      string    `json:"phase_id,omitempty"`
	Scope        string    `json:"scope,omitempty"`
	ActionIndex  int       `json:"action_index,omitempty"`
	ActionType   string    `json:"action_type,omitempty"`
	Stacks       int       `json:"stacks,omitempty"`
	Amount       int       `json:"amount,omitempty"`
	Progress     int       `json:"progress,omitempty"`
	Required     int       `json:"required,omitempty"`
	Blocked      bool      `json:"blocked,omitempty"`
	Perfect      bool      `json:"perfect,omitempty"`
	Reason       string    `json:"reason,omitempty"`
}

// AttackSnapshot is detached from mutable simulation state.
type AttackSnapshot struct {
	AbilityID      string      `json:"ability_id,omitempty"`
	Phase          AttackPhase `json:"phase,omitempty"`
	RemainingTicks int         `json:"remaining_ticks"`
	CooldownTicks  int         `json:"cooldown_ticks"`
	HitCount       int         `json:"hit_count"`
}

// AbilityCooldownSnapshot exposes every loadout cooldown in stable ID order.
type AbilityCooldownSnapshot struct {
	AbilityID      string `json:"ability_id"`
	RemainingTicks int    `json:"remaining_ticks"`
}

type StatusSnapshot struct {
	ID             string   `json:"id"`
	SourceID       string   `json:"source_id,omitempty"`
	Stacks         int      `json:"stacks"`
	RemainingTicks int      `json:"remaining_ticks"`
	TickRemaining  int      `json:"tick_remaining,omitempty"`
	Color          [4]uint8 `json:"color"`
}

type ProjectileSnapshot struct {
	ID             string   `json:"id"`
	DefinitionID   string   `json:"definition_id"`
	ActorKind      string   `json:"actor_kind"`
	SourceID       string   `json:"source_id"`
	AbilityID      string   `json:"ability_id"`
	Team           string   `json:"team"`
	Position       Vec      `json:"position"`
	Previous       Vec      `json:"previous"`
	Direction      Vec      `json:"direction"`
	Body           Body     `json:"body"`
	Tint           [4]uint8 `json:"tint"`
	RemainingTicks int      `json:"remaining_ticks"`
	Hits           int      `json:"hits"`
}

type EncounterStatus string

const (
	EncounterIdle      EncounterStatus = "idle"
	EncounterPending   EncounterStatus = "pending"
	EncounterActive    EncounterStatus = "active"
	EncounterCompleted EncounterStatus = "completed"
	EncounterFailed    EncounterStatus = "failed"
)

type EncounterSnapshot struct {
	ID             string          `json:"id"`
	DefinitionID   string          `json:"definition_id"`
	Status         EncounterStatus `json:"status"`
	WaveIndex      int             `json:"wave_index"`
	WaveID         string          `json:"wave_id,omitempty"`
	RemainingTicks int             `json:"remaining_ticks"`
	Living         int             `json:"living"`
	EnteredPhases  []string        `json:"entered_phases,omitempty"`
	Error          string          `json:"error,omitempty"`
}

// EntitySnapshot is the complete debug-facing runtime view of an entity.
type EntitySnapshot struct {
	ID        string `json:"id"`
	Kind      string `json:"kind"`
	Name      string `json:"name"`
	Team      string `json:"team,omitempty"`
	Position  Vec    `json:"position"`
	Body      Body   `json:"body"`
	Facing    Vec    `json:"facing"`
	Health    int    `json:"health"`
	MaxHealth int    `json:"max_health"`
	Dead      bool   `json:"dead"`

	Attack             AttackSnapshot            `json:"attack"`
	AbilityCooldowns   []AbilityCooldownSnapshot `json:"ability_cooldowns,omitempty"`
	Statuses           []StatusSnapshot          `json:"statuses,omitempty"`
	StaggerTicks       int                       `json:"stagger_ticks"`
	InvulnerableTicks  int                       `json:"invulnerable_ticks"`
	FlashTicks         int                       `json:"flash_ticks"`
	KnockbackTicks     int                       `json:"knockback_ticks"`
	DodgeTicks         int                       `json:"dodge_ticks"`
	DodgeCooldownTicks int                       `json:"dodge_cooldown_ticks"`
	ParryTicks         int                       `json:"parry_ticks"`
	ParryCooldownTicks int                       `json:"parry_cooldown_ticks"`
	LastParryPerfect   bool                      `json:"last_parry_perfect"`
	Velocity           Vec                       `json:"velocity"`
	Grounded           bool                      `json:"grounded"`
	CoyoteTicks        int                       `json:"coyote_ticks"`
	JumpBufferTicks    int                       `json:"jump_buffer_ticks"`
	Platformer         *PlatformerConfig         `json:"platformer,omitempty"`
}

// QuestSnapshot is detached from mutable quest state.
type QuestSnapshot struct {
	ID       string      `json:"id"`
	Status   QuestStatus `json:"status"`
	Progress int         `json:"progress"`
	Required int         `json:"required"`
}

// DialogueSnapshot is detached from mutable dialogue state.
type DialogueSnapshot struct {
	Active  bool   `json:"active"`
	ID      string `json:"id,omitempty"`
	NPCID   string `json:"npc_id,omitempty"`
	Speaker string `json:"speaker,omitempty"`
	Text    string `json:"text,omitempty"`
}

// CameraSnapshot contains both the followed base center and the final,
// stage-bounded render center.
type CameraSnapshot struct {
	BaseCenter     Vec   `json:"base_center"`
	Center         Vec   `json:"center"`
	ShakeOffset    Vec   `json:"shake_offset"`
	ShakeTicks     int   `json:"shake_ticks"`
	ViewportWidth  Coord `json:"viewport_width"`
	ViewportHeight Coord `json:"viewport_height"`
}

// Snapshot is a complete, detached simulation inspection value. Mutating any
// returned slice cannot mutate Simulation.
type Snapshot struct {
	Tick         uint64               `json:"tick"`
	WorldTick    uint64               `json:"world_tick"`
	HitstopTicks int                  `json:"hitstop_ticks"`
	Entities     []EntitySnapshot     `json:"entities"`
	Quests       []QuestSnapshot      `json:"quests"`
	Dialogue     DialogueSnapshot     `json:"dialogue"`
	Camera       CameraSnapshot       `json:"camera"`
	Events       []Event              `json:"events"`
	Projectiles  []ProjectileSnapshot `json:"projectiles,omitempty"`
	Encounters   []EncounterSnapshot  `json:"encounters,omitempty"`
}

// RenderEntity is the renderer-facing subset of EntitySnapshot.
type RenderEntity struct {
	ID        string
	Kind      string
	Name      string
	Position  Vec
	Body      Body
	Facing    Vec
	Health    int
	MaxHealth int
	Dead      bool
	Attack    AttackPhase
	Staggered bool
	Dodging   bool
	Parrying  bool
	Statuses  []StatusSnapshot
}

type RenderProjectile struct {
	ID        string
	Kind      string
	Position  Vec
	Direction Vec
	Body      Body
	Tint      [4]uint8
}

// RenderFrame is detached renderer input. Walls and Actors are sorted/copy
// values, so adapters may retain or modify a frame without affecting the sim.
type RenderFrame struct {
	Tick        uint64
	Stage       Rect
	Walls       []Wall
	Camera      CameraSnapshot
	Actors      []RenderEntity
	Projectiles []RenderProjectile
	Dialogue    DialogueSnapshot
	Quests      []QuestSnapshot
	Hitstop     bool
}
