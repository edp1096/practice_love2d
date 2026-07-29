package sim

import (
	"errors"
	"fmt"
	"sort"
)

// SessionVersion is the current deterministic save-state schema.
const SessionVersion = 2

const legacySessionVersion = 1

// BurstSessionState is the serialized form of a fixed-duration motion burst.
type BurstSessionState struct {
	TotalX   Coord `json:"total_x"`
	TotalY   Coord `json:"total_y"`
	Duration int   `json:"duration"`
	Elapsed  int   `json:"elapsed"`
}

// AttackSessionState is the serialized primary attack state.
type AttackSessionState struct {
	Phase          AttackPhase `json:"phase"`
	PhaseStartTick uint64      `json:"phase_start_tick"`
	HitTargets     []string    `json:"hit_targets"`
	HitCount       int         `json:"hit_count"`
}

// EntitySessionState stores only mutable entity state. Immutable definitions
// are resolved from authored Config plus the session's preview topology.
type EntitySessionState struct {
	ID       string `json:"id"`
	Position Vec    `json:"position"`
	Facing   Vec    `json:"facing"`
	Health   int    `json:"health"`
	Dead     bool   `json:"dead"`

	Attack            *AttackSessionState `json:"attack,omitempty"`
	AttackCooldown    int                 `json:"attack_cooldown"`
	StaggerTicks      int                 `json:"stagger_ticks"`
	InvulnerableTicks int                 `json:"invulnerable_ticks"`
	FlashTicks        int                 `json:"flash_ticks"`
	Knockback         BurstSessionState   `json:"knockback"`
	Dodge             BurstSessionState   `json:"dodge"`
	DodgeCooldown     int                 `json:"dodge_cooldown"`
	ParryTicks        int                 `json:"parry_ticks"`
	ParryCooldown     int                 `json:"parry_cooldown"`
	ParryLastPerfect  bool                `json:"parry_last_perfect"`
}

// QuestSessionState stores mutable quest progress.
type QuestSessionState struct {
	ID       string      `json:"id"`
	Status   QuestStatus `json:"status"`
	Progress int         `json:"progress"`
}

// DialogueSessionState stores a currently open dialogue reference.
type DialogueSessionState struct {
	Active       bool                `json:"active"`
	DefinitionID string              `json:"definition_id,omitempty"`
	NPCID        string              `json:"npc_id,omitempty"`
	Definition   *DialogueDefinition `json:"definition,omitempty"`
}

// CameraSessionState stores deterministic shake state. Base and final centers
// are restored and then clamped against the immutable stage definition.
type CameraSessionState struct {
	BaseCenter     Vec    `json:"base_center"`
	Center         Vec    `json:"center"`
	Offset         Vec    `json:"offset"`
	ShakeMagnitude Coord  `json:"shake_magnitude"`
	ShakeDuration  int    `json:"shake_duration"`
	ShakeRemaining int    `json:"shake_remaining"`
	ShakeSequence  uint64 `json:"shake_sequence"`
}

// SessionState is a JSON-safe, detached full simulation save. Version 2 can
// round-trip temporary preview topology for transactions and tests; player-save
// policy remains a caller concern.
type SessionState struct {
	Version   int    `json:"version"`
	Tick      uint64 `json:"tick"`
	WorldTick uint64 `json:"world_tick"`
	Hitstop   int    `json:"hitstop"`

	PreviewEntities  []EntityPreviewConfig `json:"preview_entities,omitempty"`
	PreviewQuests    []QuestDefinition     `json:"preview_quests,omitempty"`
	RemovedEntityIDs []string              `json:"removed_entity_ids,omitempty"`
	Entities         []EntitySessionState  `json:"entities"`
	Quests           []QuestSessionState   `json:"quests"`
	Dialogue         DialogueSessionState  `json:"dialogue"`
	Camera           CameraSessionState    `json:"camera"`
}

// SaveSession returns a detached, deterministic full-session save value.
func (s *Simulation) SaveSession() SessionState {
	state := SessionState{
		Version:   SessionVersion,
		Tick:      s.rawTick,
		WorldTick: s.worldTick,
		Hitstop:   s.hitstop,
		Entities:  make([]EntitySessionState, 0, len(s.entityOrder)),
		Quests:    make([]QuestSessionState, 0, len(s.questOrder)),
		Dialogue: DialogueSessionState{
			Active:       s.dialogue.active,
			DefinitionID: s.dialogue.definitionID,
			NPCID:        s.dialogue.npcID,
		},
		Camera: CameraSessionState{
			BaseCenter:     s.camera.baseCenter,
			Center:         s.camera.center,
			Offset:         s.camera.offset,
			ShakeMagnitude: s.camera.shakeMagnitude,
			ShakeDuration:  s.camera.shakeDuration,
			ShakeRemaining: s.camera.shakeRemaining,
			ShakeSequence:  s.camera.shakeSequence,
		},
	}
	for _, id := range sortedPreviewIDs(s.previewDefs) {
		state.PreviewEntities = append(
			state.PreviewEntities,
			cloneEntityPreviewConfig(s.previewDefs[id]),
		)
	}
	directQuestIDs := make([]string, 0, len(s.directQuestDefs))
	for id := range s.directQuestDefs {
		directQuestIDs = append(directQuestIDs, id)
	}
	sort.Strings(directQuestIDs)
	for _, id := range directQuestIDs {
		state.PreviewQuests = append(
			state.PreviewQuests,
			s.directQuestDefs[id],
		)
	}
	for id := range s.removedIDs {
		state.RemovedEntityIDs = append(state.RemovedEntityIDs, id)
	}
	sort.Strings(state.RemovedEntityIDs)
	if s.dialogue.direct {
		definition := s.dialogue.definition
		state.Dialogue.Definition = &definition
	}
	for _, id := range s.entityOrder {
		entity := s.entities[id]
		saved := EntitySessionState{
			ID:                id,
			Position:          entity.position,
			Facing:            entity.facing,
			Health:            entity.health,
			Dead:              entity.dead,
			AttackCooldown:    entity.attackCooldown,
			StaggerTicks:      entity.staggerTicks,
			InvulnerableTicks: entity.invulnerableTicks,
			FlashTicks:        entity.flashTicks,
			Knockback:         saveBurst(entity.knockback),
			Dodge:             saveBurst(entity.dodge),
			DodgeCooldown:     entity.dodgeCooldown,
			ParryTicks:        entity.parryTicks,
			ParryCooldown:     entity.parryCooldown,
			ParryLastPerfect:  entity.parryLastPerfect,
		}
		if entity.attack != nil {
			hitTargets := make([]string, 0, len(entity.attack.hitTargets))
			for targetID := range entity.attack.hitTargets {
				hitTargets = append(hitTargets, targetID)
			}
			sort.Strings(hitTargets)
			saved.Attack = &AttackSessionState{
				Phase:          entity.attack.phase,
				PhaseStartTick: entity.attack.phaseStartTick,
				HitTargets:     hitTargets,
				HitCount:       entity.attack.hitCount,
			}
		}
		state.Entities = append(state.Entities, saved)
	}
	for _, id := range s.questOrder {
		quest := s.quests[id]
		state.Quests = append(state.Quests, QuestSessionState{
			ID:       id,
			Status:   quest.status,
			Progress: quest.progress,
		})
	}
	return state
}

// LoadSession validates the entire save before replacing any runtime state.
// A rejected load leaves the simulation byte-for-byte equivalent at its public
// snapshot boundary.
func (s *Simulation) LoadSession(state SessionState) error {
	prepared, err := s.prepareSession(state)
	if err != nil {
		return err
	}
	s.rawTick = state.Tick
	s.worldTick = state.WorldTick
	s.hitstop = state.Hitstop
	s.entities = prepared.entities
	s.entityOrder = prepared.topology.entityOrder
	s.dynamicIDs = prepared.topology.dynamicIDs
	s.removedIDs = prepared.topology.removedIDs
	s.previewDefs = prepared.topology.previewDefs
	s.directQuestDefs = prepared.topology.directQuestDefs
	s.dialogues = prepared.topology.dialogues
	s.interactionRange = prepared.topology.interactionRange
	s.quests = prepared.quests
	s.questOrder = prepared.topology.questOrder
	s.dialogue = prepared.dialogue
	s.camera = prepared.camera
	s.lastEvents = nil
	s.refreshCameraCenter()
	return nil
}

func (s *Simulation) restoreEntitySession(
	config EntityConfig,
	saved EntitySessionState,
	worldTick uint64,
) (*entityRuntime, error) {
	if !validCoord(saved.Position.X) || !validCoord(saved.Position.Y) ||
		!containsRect(
			s.config.StageBounds,
			entityRect(saved.Position, config.Body),
		) {
		return nil, errors.New("position is outside stage bounds")
	}
	for _, wall := range s.config.Walls {
		if overlaps(entityRect(saved.Position, config.Body), wall.Rect) {
			return nil, errors.New("position overlaps a wall")
		}
	}
	if saved.Facing == (Vec{}) || !validCoord(saved.Facing.X) ||
		!validCoord(saved.Facing.Y) {
		return nil, errors.New("facing is invalid")
	}
	facingMagnitude := int64(integerSqrt(uint64(squaredMagnitude(saved.Facing))))
	if facingMagnitude < int64(UnitsPerPixel)-2 ||
		facingMagnitude > int64(UnitsPerPixel)+2 {
		return nil, errors.New("facing must be a normalized vector")
	}
	if saved.Health < 0 || saved.Health > config.MaxHealth ||
		saved.Dead != (saved.Health == 0) {
		return nil, errors.New("health/dead state is inconsistent")
	}
	for label, timer := range map[string]int{
		"attack cooldown": saved.AttackCooldown,
		"stagger":         saved.StaggerTicks,
		"invulnerability": saved.InvulnerableTicks,
		"flash":           saved.FlashTicks,
		"dodge cooldown":  saved.DodgeCooldown,
		"parry":           saved.ParryTicks,
		"parry cooldown":  saved.ParryCooldown,
	} {
		if timer < 0 || timer > 1_000_000 {
			return nil, fmt.Errorf("%s timer is invalid", label)
		}
	}
	knockback, err := restoreBurst(saved.Knockback)
	if err != nil {
		return nil, fmt.Errorf("knockback: %w", err)
	}
	dodge, err := restoreBurst(saved.Dodge)
	if err != nil {
		return nil, fmt.Errorf("dodge: %w", err)
	}
	if saved.Dead && (saved.Attack != nil || knockback.active() ||
		dodge.active() || saved.StaggerTicks > 0 ||
		saved.InvulnerableTicks > 0 || saved.ParryTicks > 0) {
		return nil, errors.New("dead entity contains active action state")
	}
	if saved.ParryTicks > 0 &&
		(config.Parry == nil || saved.ParryTicks > config.Parry.WindowTicks) {
		return nil, errors.New("parry state exceeds content definition")
	}
	if dodge.active() && config.Dodge == nil {
		return nil, errors.New("dodge state requires dodge content")
	}
	if config.Dodge == nil && saved.Dodge.Duration != 0 {
		return nil, errors.New("dodge history requires dodge content")
	}
	if config.Dodge != nil && saved.Dodge.Duration != 0 &&
		(saved.Dodge.Duration != config.Dodge.DurationTicks ||
			squaredMagnitude(Vec{
				X: saved.Dodge.TotalX,
				Y: saved.Dodge.TotalY,
			}) > int64(config.Dodge.Distance)*int64(config.Dodge.Distance)) {
		return nil, errors.New("dodge state exceeds content definition")
	}

	entity := &entityRuntime{
		config:            cloneEntityConfig(config),
		position:          saved.Position,
		facing:            saved.Facing,
		health:            saved.Health,
		dead:              saved.Dead,
		attackCooldown:    saved.AttackCooldown,
		staggerTicks:      saved.StaggerTicks,
		invulnerableTicks: saved.InvulnerableTicks,
		flashTicks:        saved.FlashTicks,
		knockback:         knockback,
		dodge:             dodge,
		dodgeCooldown:     saved.DodgeCooldown,
		parryTicks:        saved.ParryTicks,
		parryCooldown:     saved.ParryCooldown,
		parryLastPerfect:  saved.ParryLastPerfect,
	}
	if saved.Attack != nil {
		if config.Ability == nil ||
			(saved.Attack.Phase != AttackWindup &&
				saved.Attack.Phase != AttackActive &&
				saved.Attack.Phase != AttackRecovery) ||
			saved.Attack.PhaseStartTick > worldTick ||
			saved.Attack.HitCount != len(saved.Attack.HitTargets) {
			return nil, errors.New("attack state is invalid")
		}
		var phaseDuration int
		switch saved.Attack.Phase {
		case AttackWindup:
			phaseDuration = config.Ability.WindupTicks
		case AttackActive:
			phaseDuration = config.Ability.ActiveTicks
		case AttackRecovery:
			phaseDuration = config.Ability.RecoveryTicks
		}
		if phaseDuration <= 0 ||
			worldTick-saved.Attack.PhaseStartTick >= uint64(phaseDuration) {
			return nil, errors.New("attack phase has already expired")
		}
		hitTargets := make(map[string]struct{}, len(saved.Attack.HitTargets))
		for _, id := range saved.Attack.HitTargets {
			if s.entities[id] == nil {
				return nil, fmt.Errorf("attack references unknown target %q", id)
			}
			if _, duplicate := hitTargets[id]; duplicate {
				return nil, fmt.Errorf("attack duplicates target %q", id)
			}
			hitTargets[id] = struct{}{}
		}
		entity.attack = &attackRuntime{
			phase:          saved.Attack.Phase,
			phaseStartTick: saved.Attack.PhaseStartTick,
			hitTargets:     hitTargets,
			hitCount:       saved.Attack.HitCount,
		}
	}
	blocked := entity.knockback.active() || entity.staggerTicks > 0
	if (entity.attack != nil &&
		(entity.dodge.active() || entity.parryTicks > 0 || blocked)) ||
		(entity.dodge.active() && (entity.parryTicks > 0 || blocked)) ||
		(entity.parryTicks > 0 && blocked) {
		return nil, errors.New("mutually exclusive action states overlap")
	}
	return entity, nil
}

func validateCameraSession(state CameraSessionState) error {
	if !validCoord(state.BaseCenter.X) || !validCoord(state.BaseCenter.Y) ||
		!validCoord(state.Center.X) || !validCoord(state.Center.Y) ||
		!validCoord(state.Offset.X) || !validCoord(state.Offset.Y) ||
		state.ShakeMagnitude < 0 || !validCoord(state.ShakeMagnitude) ||
		state.ShakeDuration < 0 ||
		state.ShakeRemaining < 0 ||
		state.ShakeRemaining > state.ShakeDuration ||
		!validTickCount(state.ShakeDuration, state.ShakeRemaining) {
		return errors.New("camera session state is invalid")
	}
	if state.ShakeDuration == 0 &&
		(state.ShakeMagnitude != 0 || state.ShakeRemaining != 0 ||
			state.Offset != (Vec{})) {
		return errors.New("idle camera shake contains active state")
	}
	return nil
}

func saveBurst(burst burstRuntime) BurstSessionState {
	return BurstSessionState{
		TotalX:   burst.totalX,
		TotalY:   burst.totalY,
		Duration: burst.duration,
		Elapsed:  burst.elapsed,
	}
}

func restoreBurst(state BurstSessionState) (burstRuntime, error) {
	if state.Duration < 0 || state.Elapsed < 0 ||
		state.Elapsed > state.Duration ||
		state.Duration > 1_000_000 ||
		!validCoord(state.TotalX) || !validCoord(state.TotalY) {
		return burstRuntime{}, errors.New("motion burst is invalid")
	}
	if state.Duration == 0 &&
		(state.Elapsed != 0 || state.TotalX != 0 || state.TotalY != 0) {
		return burstRuntime{}, errors.New("empty motion burst contains movement")
	}
	return burstRuntime{
		totalX:   state.TotalX,
		totalY:   state.TotalY,
		duration: state.Duration,
		elapsed:  state.Elapsed,
	}, nil
}
