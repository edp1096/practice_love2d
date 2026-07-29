package sim

import "sort"

// Snapshot returns a complete detached debug model. The ordering of Entities
// and Quests is stable by ID.
func (s *Simulation) Snapshot() Snapshot {
	entities := make([]EntitySnapshot, 0, len(s.entityOrder))
	for _, id := range s.entityOrder {
		entity := s.entities[id]
		entities = append(entities, s.entitySnapshot(entity))
	}
	return Snapshot{
		Tick:         s.rawTick,
		WorldTick:    s.worldTick,
		HitstopTicks: s.hitstop,
		Entities:     entities,
		Quests:       s.questSnapshots(),
		Dialogue:     s.dialogueSnapshot(),
		Camera:       s.cameraSnapshot(),
		Events:       cloneEvents(s.lastEvents),
		Projectiles:  s.projectileSnapshots(),
	}
}

// RenderFrame returns a detached, renderer-oriented view with no Ebitengine
// dependency. Actor and quest ordering is stable by ID.
func (s *Simulation) RenderFrame() RenderFrame {
	actors := make([]RenderEntity, 0, len(s.entityOrder))
	for _, id := range s.entityOrder {
		entity := s.entities[id]
		phase := AttackIdle
		if entity.attack != nil {
			phase = entity.attack.phase
		}
		actors = append(actors, RenderEntity{
			ID:        entity.config.ID,
			Kind:      entity.config.Kind,
			Name:      entity.config.Name,
			Position:  entity.position,
			Body:      entity.config.Body,
			Facing:    entity.facing,
			Health:    entity.health,
			MaxHealth: entity.config.MaxHealth,
			Dead:      entity.dead,
			Attack:    phase,
			Staggered: entity.staggerTicks > 0,
			Dodging:   entity.dodge.active(),
			Parrying:  entity.parryTicks > 0,
			Statuses:  s.statusSnapshots(entity),
		})
	}
	projectiles := make([]RenderProjectile, 0, len(s.projectileOrder))
	for _, id := range s.projectileOrder {
		projectile := s.projectiles[id]
		definition := s.projectileDefinitions[projectile.definitionID]
		projectiles = append(projectiles, RenderProjectile{
			ID:        projectile.id,
			Kind:      definition.ActorKind,
			Position:  projectile.position,
			Direction: projectile.direction,
			Body:      definition.Body,
			Tint:      definition.Tint,
		})
	}
	return RenderFrame{
		Tick:        s.rawTick,
		Stage:       s.config.StageBounds,
		Walls:       cloneWalls(s.config.Walls),
		Camera:      s.cameraSnapshot(),
		Actors:      actors,
		Projectiles: projectiles,
		Dialogue:    s.dialogueSnapshot(),
		Quests:      s.questSnapshots(),
		Hitstop:     s.hitstop > 0,
	}
}

func (s *Simulation) entitySnapshot(entity *entityRuntime) EntitySnapshot {
	attack := AttackSnapshot{}
	if entity.attack != nil {
		attack.AbilityID = entity.attack.abilityID
		attack.Phase = entity.attack.phase
		attack.RemainingTicks = s.attackRemaining(entity)
		attack.HitCount = entity.attack.hitCount
	}
	if entity.config.Combat != nil {
		cooldownID := entity.config.Combat.PrimaryAbilityID
		if attack.AbilityID != "" {
			cooldownID = attack.AbilityID
		}
		attack.CooldownTicks = entity.abilityCooldowns[cooldownID]
	}
	cooldowns := make(
		[]AbilityCooldownSnapshot,
		0,
		len(entity.abilityCooldowns),
	)
	for abilityID, remaining := range entity.abilityCooldowns {
		if remaining <= 0 {
			continue
		}
		cooldowns = append(cooldowns, AbilityCooldownSnapshot{
			AbilityID:      abilityID,
			RemainingTicks: remaining,
		})
	}
	sort.Slice(cooldowns, func(left, right int) bool {
		return cooldowns[left].AbilityID < cooldowns[right].AbilityID
	})
	return EntitySnapshot{
		ID:                 entity.config.ID,
		Kind:               entity.config.Kind,
		Name:               entity.config.Name,
		Team:               entity.config.Team,
		Position:           entity.position,
		Body:               entity.config.Body,
		Facing:             entity.facing,
		Health:             entity.health,
		MaxHealth:          entity.config.MaxHealth,
		Dead:               entity.dead,
		Attack:             attack,
		AbilityCooldowns:   cooldowns,
		Statuses:           s.statusSnapshots(entity),
		StaggerTicks:       entity.staggerTicks,
		InvulnerableTicks:  entity.invulnerableTicks,
		FlashTicks:         entity.flashTicks,
		KnockbackTicks:     entity.knockback.remaining(),
		DodgeTicks:         entity.dodge.remaining(),
		DodgeCooldownTicks: entity.dodgeCooldown,
		ParryTicks:         entity.parryTicks,
		ParryCooldownTicks: entity.parryCooldown,
		LastParryPerfect:   entity.parryLastPerfect,
	}
}

func (s *Simulation) statusSnapshots(
	entity *entityRuntime,
) []StatusSnapshot {
	result := make([]StatusSnapshot, 0, len(entity.statuses))
	for statusID, status := range entity.statuses {
		definition := s.statusDefinitions[statusID]
		result = append(result, StatusSnapshot{
			ID:             statusID,
			SourceID:       status.sourceID,
			Stacks:         status.stacks,
			RemainingTicks: status.remaining,
			TickRemaining:  status.tickRemaining,
			Color:          definition.Color,
		})
	}
	sort.Slice(result, func(left, right int) bool {
		return result[left].ID < result[right].ID
	})
	return result
}

func (s *Simulation) projectileSnapshots() []ProjectileSnapshot {
	result := make([]ProjectileSnapshot, 0, len(s.projectileOrder))
	for _, id := range s.projectileOrder {
		projectile := s.projectiles[id]
		definition := s.projectileDefinitions[projectile.definitionID]
		result = append(result, ProjectileSnapshot{
			ID:             projectile.id,
			DefinitionID:   projectile.definitionID,
			ActorKind:      definition.ActorKind,
			SourceID:       projectile.sourceID,
			AbilityID:      projectile.abilityID,
			Team:           projectile.team,
			Position:       projectile.position,
			Previous:       projectile.previous,
			Direction:      projectile.direction,
			Body:           definition.Body,
			Tint:           definition.Tint,
			RemainingTicks: projectile.remaining,
			Hits:           projectile.hits,
		})
	}
	return result
}

func (s *Simulation) attackRemaining(entity *entityRuntime) int {
	ability := activeAbility(entity)
	if entity.attack == nil || ability == nil {
		return 0
	}
	var duration int
	switch entity.attack.phase {
	case AttackWindup:
		duration = ability.WindupTicks
	case AttackActive:
		duration = ability.ActiveTicks
	case AttackRecovery:
		duration = ability.RecoveryTicks
	default:
		return 0
	}
	elapsed := int(s.worldTick - entity.attack.phaseStartTick)
	return maxInt(0, duration-elapsed)
}

func (s *Simulation) questSnapshots() []QuestSnapshot {
	result := make([]QuestSnapshot, 0, len(s.questOrder))
	for _, id := range s.questOrder {
		quest := s.quests[id]
		result = append(result, QuestSnapshot{
			ID:       id,
			Status:   quest.status,
			Progress: quest.progress,
			Required: quest.definition.Required,
		})
	}
	return result
}

func (s *Simulation) dialogueSnapshot() DialogueSnapshot {
	if !s.dialogue.active {
		return DialogueSnapshot{}
	}
	definition := s.dialogue.definition
	if !s.dialogue.direct {
		definition = s.dialogues[s.dialogue.definitionID]
	}
	return DialogueSnapshot{
		Active:  true,
		ID:      definition.ID,
		NPCID:   s.dialogue.npcID,
		Speaker: definition.Speaker,
		Text:    definition.Text,
	}
}

func (s *Simulation) cameraSnapshot() CameraSnapshot {
	return CameraSnapshot{
		BaseCenter:     s.camera.baseCenter,
		Center:         s.camera.center,
		ShakeOffset:    s.camera.offset,
		ShakeTicks:     s.camera.shakeRemaining,
		ViewportWidth:  s.config.Camera.ViewportWidth,
		ViewportHeight: s.config.Camera.ViewportHeight,
	}
}
