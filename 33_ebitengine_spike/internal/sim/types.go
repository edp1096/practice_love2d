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
// Keeping the ID inside the simulation avoids trying to recover editor
// identity from equal rectangle coordinates.
type Wall struct {
	ID   string `json:"id"`
	Rect Rect   `json:"rect"`
}

// Body describes an axis-aligned entity collision body.
type Body struct {
	HalfWidth  Coord `json:"half_width"`
	HalfHeight Coord `json:"half_height"`
	Solid      bool  `json:"solid"`
}

// AbilityConfig describes the single primary attack in this vertical slice.
// ArcDegrees is the full facing arc and must be in [1, 360].
type AbilityConfig struct {
	ID               string
	WindupTicks      int
	ActiveTicks      int
	RecoveryTicks    int
	CooldownTicks    int
	LockMovement     bool
	Reach            Coord
	ArcDegrees       int
	Damage           int
	StaggerTicks     int
	Knockback        Coord
	KnockbackTicks   int
	HitstopTicks     int
	CameraShake      Coord
	CameraShakeTicks int
}

// ReactionConfig controls hit invulnerability and presentation feedback.
type ReactionConfig struct {
	HitInvulnerabilityTicks int
	FlashTicks              int
}

// DodgeConfig controls deterministic burst motion and invulnerability.
type DodgeConfig struct {
	DurationTicks        int
	Distance             Coord
	InvulnerabilityTicks int
	CooldownTicks        int
}

// ParryConfig controls the guarding arc and perfect-parry window.
type ParryConfig struct {
	WindowTicks          int
	PerfectWindowTicks   int
	CooldownTicks        int
	SuccessCooldownTicks int
	ArcDegrees           int
	StaggerTicks         int
	PerfectStaggerTicks  int
	HitstopTicks         int
	PerfectHitstopTicks  int
	CameraShake          Coord
	CameraShakeTicks     int
}

// EntityConfig is immutable content used to construct an entity. Runtime state
// is deliberately kept out of this type.
type EntityConfig struct {
	ID          string
	Kind        string
	Name        string
	Team        string
	Position    Vec
	Body        Body
	MaxHealth   int
	MovePerTick Coord
	Facing      Vec
	Controlled  bool

	Ability  *AbilityConfig
	Reaction ReactionConfig
	Dodge    *DodgeConfig
	Parry    *ParryConfig

	// DialogueID makes the entity interactable. StartQuestID is started
	// transactionally when that dialogue opens.
	DialogueID   string
	StartQuestID string
}

// DialogueDefinition is a deliberately small data-authored dialogue node for
// the spike. A richer graph can be placed above this simulation boundary.
type DialogueDefinition struct {
	ID      string
	Speaker string
	Text    string
}

// QuestDefinition tracks defeat events for an actor ID or kind. Empty match
// fields are wildcards. Required must be positive.
type QuestDefinition struct {
	ID              string
	TargetEntityID  string
	TargetKind      string
	Required        int
	InitiallyActive bool
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
	Camera           CameraConfig
	InteractionRange Coord
}

// EntityInput is a semantic command for one entity. MoveX and MoveY are digital
// axes in [-1, 1]. Action booleans are press edges, not held states.
type EntityInput struct {
	EntityID string
	MoveX    int8
	MoveY    int8
	Attack   bool
	Parry    bool
	Dodge    bool
	Interact bool
}

// Input is one fixed-tick input frame. The top-level fields target the
// configured controlled entity. Commands allow tests, AI, and the debug
// backend to drive additional entities in the same tick. Commands are resolved
// in sorted entity-ID order; duplicate IDs use the last command.
type Input struct {
	MoveX    int8
	MoveY    int8
	Attack   bool
	Parry    bool
	Dodge    bool
	Interact bool
	Commands []EntityInput
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
	EventAttackStarted     EventType = "attack.started"
	EventAttackActive      EventType = "attack.active"
	EventAttackFinished    EventType = "attack.finished"
	EventAttackInterrupted EventType = "attack.interrupted"
	EventDamageApplied     EventType = "damage.applied"
	EventDamageBlocked     EventType = "damage.blocked"
	EventActorStaggered    EventType = "actor.staggered"
	EventActorKilled       EventType = "actor.killed"
	EventKnockbackStarted  EventType = "knockback.started"
	EventHitstopStarted    EventType = "hitstop.started"
	EventParryStarted      EventType = "parry.started"
	EventAttackParried     EventType = "attack.parried"
	EventDodgeStarted      EventType = "dodge.started"
	EventDialogueStarted   EventType = "dialogue.started"
	EventDialogueClosed    EventType = "dialogue.closed"
	EventQuestStarted      EventType = "quest.started"
	EventQuestProgress     EventType = "quest.progress"
	EventQuestCompleted    EventType = "quest.completed"
	EventInputRejected     EventType = "input.rejected"
)

// Event is an immutable-by-copy simulation event. Only fields relevant to Type
// are populated.
type Event struct {
	Tick       uint64    `json:"tick"`
	Type       EventType `json:"type"`
	EntityID   string    `json:"entity_id,omitempty"`
	SourceID   string    `json:"source_id,omitempty"`
	TargetID   string    `json:"target_id,omitempty"`
	QuestID    string    `json:"quest_id,omitempty"`
	DialogueID string    `json:"dialogue_id,omitempty"`
	Amount     int       `json:"amount,omitempty"`
	Progress   int       `json:"progress,omitempty"`
	Required   int       `json:"required,omitempty"`
	Blocked    bool      `json:"blocked,omitempty"`
	Perfect    bool      `json:"perfect,omitempty"`
	Reason     string    `json:"reason,omitempty"`
}

// AttackSnapshot is detached from mutable simulation state.
type AttackSnapshot struct {
	Phase          AttackPhase `json:"phase,omitempty"`
	RemainingTicks int         `json:"remaining_ticks"`
	CooldownTicks  int         `json:"cooldown_ticks"`
	HitCount       int         `json:"hit_count"`
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

	Attack             AttackSnapshot `json:"attack"`
	StaggerTicks       int            `json:"stagger_ticks"`
	InvulnerableTicks  int            `json:"invulnerable_ticks"`
	FlashTicks         int            `json:"flash_ticks"`
	KnockbackTicks     int            `json:"knockback_ticks"`
	DodgeTicks         int            `json:"dodge_ticks"`
	DodgeCooldownTicks int            `json:"dodge_cooldown_ticks"`
	ParryTicks         int            `json:"parry_ticks"`
	ParryCooldownTicks int            `json:"parry_cooldown_ticks"`
	LastParryPerfect   bool           `json:"last_parry_perfect"`
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
	Tick         uint64           `json:"tick"`
	WorldTick    uint64           `json:"world_tick"`
	HitstopTicks int              `json:"hitstop_ticks"`
	Entities     []EntitySnapshot `json:"entities"`
	Quests       []QuestSnapshot  `json:"quests"`
	Dialogue     DialogueSnapshot `json:"dialogue"`
	Camera       CameraSnapshot   `json:"camera"`
	Events       []Event          `json:"events"`
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
}

// RenderFrame is detached renderer input. Walls and Actors are sorted/copy
// values, so adapters may retain or modify a frame without affecting the sim.
type RenderFrame struct {
	Tick     uint64
	Stage    Rect
	Walls    []Wall
	Camera   CameraSnapshot
	Actors   []RenderEntity
	Dialogue DialogueSnapshot
	Quests   []QuestSnapshot
	Hitstop  bool
}
