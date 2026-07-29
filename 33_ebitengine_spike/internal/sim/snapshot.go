package sim

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
		})
	}
	return RenderFrame{
		Tick:     s.rawTick,
		Stage:    s.config.StageBounds,
		Walls:    append([]Wall(nil), s.config.Walls...),
		Camera:   s.cameraSnapshot(),
		Actors:   actors,
		Dialogue: s.dialogueSnapshot(),
		Quests:   s.questSnapshots(),
		Hitstop:  s.hitstop > 0,
	}
}

func (s *Simulation) entitySnapshot(entity *entityRuntime) EntitySnapshot {
	attack := AttackSnapshot{CooldownTicks: entity.attackCooldown}
	if entity.attack != nil {
		attack.Phase = entity.attack.phase
		attack.RemainingTicks = s.attackRemaining(entity)
		attack.HitCount = entity.attack.hitCount
	}
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

func (s *Simulation) attackRemaining(entity *entityRuntime) int {
	if entity.attack == nil || entity.config.Ability == nil {
		return 0
	}
	var duration int
	switch entity.attack.phase {
	case AttackWindup:
		duration = entity.config.Ability.WindupTicks
	case AttackActive:
		duration = entity.config.Ability.ActiveTicks
	case AttackRecovery:
		duration = entity.config.Ability.RecoveryTicks
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
	definition := s.dialogues[s.dialogue.definitionID]
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
