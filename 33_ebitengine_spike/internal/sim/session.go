package sim

import (
	"errors"
	"fmt"
	"sort"
)

// SessionVersion is the current deterministic save-state schema.
const SessionVersion = 4

const legacySessionVersion = 1
const topologySessionVersion = 2
const actionSessionVersion = 3

// BurstSessionState is the serialized form of a fixed-duration motion burst.
type BurstSessionState struct {
	TotalX   Coord `json:"total_x"`
	TotalY   Coord `json:"total_y"`
	Duration int   `json:"duration"`
	Elapsed  int   `json:"elapsed"`
}

// AttackHitSessionState preserves per-target multi-hit timing.
type AttackHitSessionState struct {
	TargetID        string `json:"target_id"`
	Count           int    `json:"count"`
	RepeatRemaining int    `json:"repeat_remaining"`
}

// AttackSessionState is the serialized active ability state.
type AttackSessionState struct {
	AbilityID      string      `json:"ability_id,omitempty"`
	Phase          AttackPhase `json:"phase"`
	PhaseStartTick uint64      `json:"phase_start_tick"`
	// HitTargets is retained only to load version 1/2 sessions.
	HitTargets []string                `json:"hit_targets,omitempty"`
	Hits       []AttackHitSessionState `json:"hits,omitempty"`
	HitCount   int                     `json:"hit_count"`
}

type AbilityCooldownSessionState struct {
	AbilityID      string `json:"ability_id"`
	RemainingTicks int    `json:"remaining_ticks"`
}

type StatusSessionState struct {
	ID            string `json:"id"`
	SourceID      string `json:"source_id,omitempty"`
	Stacks        int    `json:"stacks"`
	Remaining     int    `json:"remaining"`
	TickRemaining int    `json:"tick_remaining,omitempty"`
}

type ProjectileSessionState struct {
	ID           string   `json:"id"`
	DefinitionID string   `json:"definition_id"`
	AbilityID    string   `json:"ability_id"`
	SourceID     string   `json:"source_id"`
	Team         string   `json:"team"`
	Position     Vec      `json:"position"`
	Previous     Vec      `json:"previous"`
	Direction    Vec      `json:"direction"`
	Remaining    int      `json:"remaining"`
	Hits         int      `json:"hits"`
	HitTargets   []string `json:"hit_targets,omitempty"`
}

// EntitySessionState stores only mutable entity state. Immutable definitions
// are resolved from authored Config plus the session's preview topology.
type EntitySessionState struct {
	ID       string `json:"id"`
	Position Vec    `json:"position"`
	Facing   Vec    `json:"facing"`
	Health   int    `json:"health"`
	Dead     bool   `json:"dead"`

	Attack *AttackSessionState `json:"attack,omitempty"`
	// AttackCooldown is retained only to load version 1/2 sessions.
	AttackCooldown    int                           `json:"attack_cooldown,omitempty"`
	AbilityCooldowns  []AbilityCooldownSessionState `json:"ability_cooldowns,omitempty"`
	Statuses          []StatusSessionState          `json:"statuses,omitempty"`
	StaggerTicks      int                           `json:"stagger_ticks"`
	InvulnerableTicks int                           `json:"invulnerable_ticks"`
	FlashTicks        int                           `json:"flash_ticks"`
	Knockback         BurstSessionState             `json:"knockback"`
	Dodge             BurstSessionState             `json:"dodge"`
	DodgeCooldown     int                           `json:"dodge_cooldown"`
	ParryTicks        int                           `json:"parry_ticks"`
	ParryCooldown     int                           `json:"parry_cooldown"`
	ParryLastPerfect  bool                          `json:"parry_last_perfect"`
	Velocity          Vec                           `json:"velocity"`
	Grounded          bool                          `json:"grounded"`
	CoyoteTicks       int                           `json:"coyote_ticks"`
	JumpBufferTicks   int                           `json:"jump_buffer_ticks"`
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

// SessionState is a JSON-safe, detached full simulation save. Version 4
// round-trips temporary preview topology, multi-ability cooldowns, projectiles,
// statuses, and platformer physics for transactions and tests; player-save
// policy remains a caller concern.
type SessionState struct {
	Version            int    `json:"version"`
	Tick               uint64 `json:"tick"`
	WorldTick          uint64 `json:"world_tick"`
	Hitstop            int    `json:"hitstop"`
	ProjectileSequence uint64 `json:"projectile_sequence,omitempty"`

	PreviewEntities  []EntityPreviewConfig    `json:"preview_entities,omitempty"`
	PreviewQuests    []QuestDefinition        `json:"preview_quests,omitempty"`
	RemovedEntityIDs []string                 `json:"removed_entity_ids,omitempty"`
	Entities         []EntitySessionState     `json:"entities"`
	Projectiles      []ProjectileSessionState `json:"projectiles,omitempty"`
	Quests           []QuestSessionState      `json:"quests"`
	Dialogue         DialogueSessionState     `json:"dialogue"`
	Camera           CameraSessionState       `json:"camera"`
}

// SaveSession returns a detached, deterministic full-session save value.
func (s *Simulation) SaveSession() SessionState {
	state := SessionState{
		Version:            SessionVersion,
		Tick:               s.rawTick,
		WorldTick:          s.worldTick,
		Hitstop:            s.hitstop,
		ProjectileSequence: s.projectileSequence,
		Entities:           make([]EntitySessionState, 0, len(s.entityOrder)),
		Quests:             make([]QuestSessionState, 0, len(s.questOrder)),
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
			StaggerTicks:      entity.staggerTicks,
			InvulnerableTicks: entity.invulnerableTicks,
			FlashTicks:        entity.flashTicks,
			Knockback:         saveBurst(entity.knockback),
			Dodge:             saveBurst(entity.dodge),
			DodgeCooldown:     entity.dodgeCooldown,
			ParryTicks:        entity.parryTicks,
			ParryCooldown:     entity.parryCooldown,
			ParryLastPerfect:  entity.parryLastPerfect,
			Velocity:          entity.velocity,
			Grounded:          entity.grounded,
			CoyoteTicks:       entity.coyoteTicks,
			JumpBufferTicks:   entity.jumpBufferTicks,
		}
		for abilityID, remaining := range entity.abilityCooldowns {
			if remaining <= 0 {
				continue
			}
			saved.AbilityCooldowns = append(
				saved.AbilityCooldowns,
				AbilityCooldownSessionState{
					AbilityID:      abilityID,
					RemainingTicks: remaining,
				},
			)
		}
		sort.Slice(saved.AbilityCooldowns, func(left, right int) bool {
			return saved.AbilityCooldowns[left].AbilityID <
				saved.AbilityCooldowns[right].AbilityID
		})
		if entity.attack != nil {
			hits := make(
				[]AttackHitSessionState,
				0,
				len(entity.attack.hitTargets),
			)
			for targetID, record := range entity.attack.hitTargets {
				hits = append(hits, AttackHitSessionState{
					TargetID:        targetID,
					Count:           record.count,
					RepeatRemaining: record.repeatRemaining,
				})
			}
			sort.Slice(hits, func(left, right int) bool {
				return hits[left].TargetID < hits[right].TargetID
			})
			saved.Attack = &AttackSessionState{
				AbilityID:      entity.attack.abilityID,
				Phase:          entity.attack.phase,
				PhaseStartTick: entity.attack.phaseStartTick,
				Hits:           hits,
				HitCount:       entity.attack.hitCount,
			}
		}
		statusIDs := make([]string, 0, len(entity.statuses))
		for statusID := range entity.statuses {
			statusIDs = append(statusIDs, statusID)
		}
		sort.Strings(statusIDs)
		for _, statusID := range statusIDs {
			status := entity.statuses[statusID]
			saved.Statuses = append(saved.Statuses, StatusSessionState{
				ID:            statusID,
				SourceID:      status.sourceID,
				Stacks:        status.stacks,
				Remaining:     status.remaining,
				TickRemaining: status.tickRemaining,
			})
		}
		state.Entities = append(state.Entities, saved)
	}
	for _, id := range s.projectileOrder {
		projectile := s.projectiles[id]
		hitTargets := make([]string, 0, len(projectile.hitTargets))
		for targetID := range projectile.hitTargets {
			hitTargets = append(hitTargets, targetID)
		}
		sort.Strings(hitTargets)
		state.Projectiles = append(
			state.Projectiles,
			ProjectileSessionState{
				ID:           projectile.id,
				DefinitionID: projectile.definitionID,
				AbilityID:    projectile.abilityID,
				SourceID:     projectile.sourceID,
				Team:         projectile.team,
				Position:     projectile.position,
				Previous:     projectile.previous,
				Direction:    projectile.direction,
				Remaining:    projectile.remaining,
				Hits:         projectile.hits,
				HitTargets:   hitTargets,
			},
		)
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
	s.projectiles = prepared.projectiles
	s.projectileOrder = prepared.projectileOrder
	s.projectileSequence = state.ProjectileSequence
	s.lastEvents = nil
	s.refreshCameraCenter()
	return nil
}

func (s *Simulation) restoreEntitySession(
	config EntityConfig,
	saved EntitySessionState,
	worldTick uint64,
	sessionVersion int,
) (*entityRuntime, error) {
	if !validCoord(saved.Position.X) || !validCoord(saved.Position.Y) ||
		!containsRect(
			s.config.StageBounds,
			entityRect(saved.Position, config.Body),
		) {
		return nil, errors.New("position is outside stage bounds")
	}
	if config.Body.Solid {
		for _, wall := range s.config.Walls {
			if wallOverlapsRect(
				wall,
				entityRect(saved.Position, config.Body),
			) {
				return nil, errors.New("position overlaps a wall")
			}
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
	abilityCooldowns := make(map[string]int)
	if sessionVersion < actionSessionVersion {
		if saved.AttackCooldown < 0 || saved.AttackCooldown > MaxTickCount {
			return nil, errors.New("attack cooldown timer is invalid")
		}
		if primary := config.PrimaryAbility(); primary != nil &&
			saved.AttackCooldown > 0 {
			abilityCooldowns[primary.ID] = saved.AttackCooldown
		}
	} else {
		for _, cooldown := range saved.AbilityCooldowns {
			if cooldown.AbilityID == "" ||
				config.Combat == nil ||
				config.Combat.Ability(cooldown.AbilityID) == nil ||
				cooldown.RemainingTicks <= 0 ||
				cooldown.RemainingTicks > MaxTickCount {
				return nil, errors.New("ability cooldown is invalid")
			}
			if _, duplicate := abilityCooldowns[cooldown.AbilityID]; duplicate {
				return nil, errors.New("ability cooldown is duplicated")
			}
			abilityCooldowns[cooldown.AbilityID] = cooldown.RemainingTicks
		}
		if saved.AttackCooldown != 0 {
			return nil, errors.New("current session contains legacy attack cooldown")
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
		saved.InvulnerableTicks > 0 || saved.ParryTicks > 0 ||
		len(saved.Statuses) != 0) {
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
		abilityCooldowns:  abilityCooldowns,
		staggerTicks:      saved.StaggerTicks,
		invulnerableTicks: saved.InvulnerableTicks,
		flashTicks:        saved.FlashTicks,
		knockback:         knockback,
		dodge:             dodge,
		dodgeCooldown:     saved.DodgeCooldown,
		parryTicks:        saved.ParryTicks,
		parryCooldown:     saved.ParryCooldown,
		parryLastPerfect:  saved.ParryLastPerfect,
		statuses:          make(map[string]*statusRuntime),
	}
	if sessionVersion < actionSessionVersion && len(saved.Statuses) != 0 {
		return nil, errors.New("legacy entity contains statuses")
	}
	for _, status := range saved.Statuses {
		definition, exists := s.statusDefinitions[status.ID]
		if !exists || config.Status == nil ||
			status.Stacks <= 0 ||
			status.Stacks > definition.MaxStacks ||
			status.Remaining <= 0 ||
			status.Remaining > definition.DurationTicks ||
			status.TickRemaining < 0 ||
			status.TickRemaining > definition.TickIntervalTicks {
			return nil, errors.New("status state is invalid")
		}
		if definition.TickIntervalTicks == 0 && status.TickRemaining != 0 {
			return nil, errors.New("unticked status has a tick timer")
		}
		if _, duplicate := entity.statuses[status.ID]; duplicate {
			return nil, errors.New("status state is duplicated")
		}
		for _, immune := range config.Status.Immune {
			if immune == status.ID {
				return nil, errors.New("entity retains an immune status")
			}
		}
		entity.statuses[status.ID] = &statusRuntime{
			id:            status.ID,
			sourceID:      status.SourceID,
			stacks:        status.Stacks,
			remaining:     status.Remaining,
			tickRemaining: status.TickRemaining,
		}
	}
	if saved.Attack != nil {
		abilityID := saved.Attack.AbilityID
		if sessionVersion < actionSessionVersion {
			abilityID = config.Combat.PrimaryAbilityID
		}
		ability := config.Combat.Ability(abilityID)
		if ability == nil ||
			(saved.Attack.Phase != AttackWindup &&
				saved.Attack.Phase != AttackActive &&
				saved.Attack.Phase != AttackRecovery) ||
			saved.Attack.PhaseStartTick > worldTick {
			return nil, errors.New("attack state is invalid")
		}
		var phaseDuration int
		switch saved.Attack.Phase {
		case AttackWindup:
			phaseDuration = ability.WindupTicks
		case AttackActive:
			phaseDuration = ability.ActiveTicks
		case AttackRecovery:
			phaseDuration = ability.RecoveryTicks
		}
		if phaseDuration <= 0 ||
			worldTick-saved.Attack.PhaseStartTick >= uint64(phaseDuration) {
			return nil, errors.New("attack phase has already expired")
		}
		hitTargets := make(map[string]attackHitRuntime)
		if sessionVersion < actionSessionVersion {
			for _, id := range saved.Attack.HitTargets {
				if s.entities[id] == nil {
					return nil, fmt.Errorf(
						"attack references unknown target %q",
						id,
					)
				}
				if _, duplicate := hitTargets[id]; duplicate {
					return nil, fmt.Errorf("attack duplicates target %q", id)
				}
				hitTargets[id] = attackHitRuntime{
					count:           1,
					repeatRemaining: MaxTickCount,
				}
			}
			if saved.Attack.HitCount != len(saved.Attack.HitTargets) {
				return nil, errors.New("attack hit count is invalid")
			}
		} else {
			totalHits := 0
			for _, hit := range saved.Attack.Hits {
				if hit.TargetID == "" || s.entities[hit.TargetID] == nil ||
					hit.Count <= 0 ||
					hit.Count > maxInt(1, ability.MaxHits) ||
					hit.RepeatRemaining < 0 ||
					hit.RepeatRemaining > MaxTickCount {
					return nil, errors.New("attack hit record is invalid")
				}
				if _, duplicate := hitTargets[hit.TargetID]; duplicate {
					return nil, fmt.Errorf(
						"attack duplicates target %q",
						hit.TargetID,
					)
				}
				hitTargets[hit.TargetID] = attackHitRuntime{
					count:           hit.Count,
					repeatRemaining: hit.RepeatRemaining,
				}
				totalHits += hit.Count
			}
			if len(saved.Attack.HitTargets) != 0 ||
				saved.Attack.HitCount != totalHits {
				return nil, errors.New("attack hit count is invalid")
			}
		}
		entity.attack = &attackRuntime{
			abilityID:      abilityID,
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
	if sessionVersion < SessionVersion {
		if saved.Velocity != (Vec{}) || saved.Grounded ||
			saved.CoyoteTicks != 0 || saved.JumpBufferTicks != 0 {
			return nil, errors.New(
				"legacy entity contains platformer state",
			)
		}
	} else if config.Platformer == nil {
		if saved.Velocity != (Vec{}) || saved.Grounded ||
			saved.CoyoteTicks != 0 || saved.JumpBufferTicks != 0 {
			return nil, errors.New(
				"non-platformer entity contains platformer state",
			)
		}
	} else {
		if !validCoord(saved.Velocity.X) ||
			!validCoord(saved.Velocity.Y) ||
			saved.CoyoteTicks < 0 ||
			saved.CoyoteTicks > config.Platformer.CoyoteTicks ||
			saved.JumpBufferTicks < 0 ||
			saved.JumpBufferTicks > config.Platformer.JumpBufferTicks ||
			(saved.Grounded && saved.Velocity.Y != 0) {
			return nil, errors.New("platformer state is invalid")
		}
		entity.velocity = saved.Velocity
		entity.grounded = saved.Grounded
		entity.coyoteTicks = saved.CoyoteTicks
		entity.jumpBufferTicks = saved.JumpBufferTicks
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
