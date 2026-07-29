package sim

import (
	"errors"
	"fmt"
	"math"
	"sort"
)

const maxAbsCoord Coord = 1 << 29

type attackRuntime struct {
	abilityID      string
	phase          AttackPhase
	phaseStartTick uint64
	hitTargets     map[string]attackHitRuntime
	hitCount       int
}

type attackHitRuntime struct {
	count           int
	repeatRemaining int
}

type burstRuntime struct {
	totalX   Coord
	totalY   Coord
	duration int
	elapsed  int
}

func (b burstRuntime) active() bool {
	return b.duration > 0 && b.elapsed < b.duration
}

func (b burstRuntime) remaining() int {
	if !b.active() {
		return 0
	}
	return b.duration - b.elapsed
}

func (b *burstRuntime) nextDelta() Vec {
	if !b.active() {
		return Vec{}
	}
	previousX := b.totalX * Coord(b.elapsed) / Coord(b.duration)
	previousY := b.totalY * Coord(b.elapsed) / Coord(b.duration)
	b.elapsed++
	currentX := b.totalX * Coord(b.elapsed) / Coord(b.duration)
	currentY := b.totalY * Coord(b.elapsed) / Coord(b.duration)
	return Vec{X: currentX - previousX, Y: currentY - previousY}
}

type entityRuntime struct {
	config EntityConfig

	position Vec
	facing   Vec
	health   int
	dead     bool

	attack           *attackRuntime
	abilityCooldowns map[string]int

	staggerTicks      int
	invulnerableTicks int
	flashTicks        int

	knockback     burstRuntime
	dodge         burstRuntime
	dodgeCooldown int

	parryTicks       int
	parryCooldown    int
	parryLastPerfect bool

	statuses map[string]*statusRuntime

	velocity        Vec
	grounded        bool
	coyoteTicks     int
	jumpBufferTicks int
}

type statusRuntime struct {
	id            string
	sourceID      string
	stacks        int
	remaining     int
	tickRemaining int
}

type projectileRuntime struct {
	id           string
	definitionID string
	abilityID    string
	sourceID     string
	team         string
	position     Vec
	previous     Vec
	direction    Vec
	remaining    int
	hits         int
	hitTargets   map[string]struct{}
}

type encounterRuntime struct {
	definition    EncounterConfig
	status        EncounterStatus
	waveIndex     int
	remaining     int
	liveIDs       []string
	spawnEntities map[string]string
	enteredPhases map[string]struct{}
	err           string
}

type questRuntime struct {
	definition QuestDefinition
	status     QuestStatus
	progress   int
}

type dialogueRuntime struct {
	active       bool
	definitionID string
	npcID        string
	direct       bool
	definition   DialogueDefinition
}

type cameraRuntime struct {
	baseCenter Vec
	center     Vec
	offset     Vec

	shakeMagnitude Coord
	shakeDuration  int
	shakeRemaining int
	shakeSequence  uint64
}

// Simulation owns all mutable fixed-tick state. It is not safe for concurrent
// use; callers should serialize Tick, LoadSession, and inspection calls.
type Simulation struct {
	config Config

	rawTick   uint64
	worldTick uint64
	hitstop   int

	entities              map[string]*entityRuntime
	entityOrder           []string
	controlledID          string
	authoredIDs           map[string]struct{}
	dynamicIDs            map[string]struct{}
	removedIDs            map[string]struct{}
	previewDefs           map[string]EntityPreviewConfig
	interactionRange      Coord
	directQuestDefs       map[string]QuestDefinition
	dialogues             map[string]DialogueDefinition
	quests                map[string]*questRuntime
	questOrder            []string
	dialogue              dialogueRuntime
	camera                cameraRuntime
	projectileDefinitions map[string]ProjectileConfig
	statusDefinitions     map[string]StatusConfig
	projectiles           map[string]*projectileRuntime
	projectileOrder       []string
	projectileSequence    uint64
	encounters            map[string]*encounterRuntime
	encounterOrder        []string
	lastEvents            []Event
}

// New validates and deep-copies content before constructing a simulation.
func New(config Config) (*Simulation, error) {
	copied := cloneConfig(config)
	normalizeCombatConfig(&copied)
	if err := validateConfig(copied); err != nil {
		return nil, err
	}
	sortConfig(&copied)

	simulation := &Simulation{
		config:           copied,
		entities:         make(map[string]*entityRuntime, len(copied.Entities)),
		dialogues:        make(map[string]DialogueDefinition, len(copied.Dialogues)),
		quests:           make(map[string]*questRuntime, len(copied.Quests)),
		authoredIDs:      make(map[string]struct{}, len(copied.Entities)),
		dynamicIDs:       make(map[string]struct{}),
		removedIDs:       make(map[string]struct{}),
		previewDefs:      make(map[string]EntityPreviewConfig),
		interactionRange: copied.InteractionRange,
		directQuestDefs:  make(map[string]QuestDefinition),
		entityOrder:      make([]string, 0, len(copied.Entities)),
		questOrder:       make([]string, 0, len(copied.Quests)),
		projectileDefinitions: make(
			map[string]ProjectileConfig,
			len(copied.Projectiles),
		),
		statusDefinitions: make(
			map[string]StatusConfig,
			len(copied.Statuses),
		),
		projectiles: make(map[string]*projectileRuntime),
		encounters:  make(map[string]*encounterRuntime, len(copied.Encounters)),
	}
	for _, definition := range copied.Projectiles {
		simulation.projectileDefinitions[definition.ID] = definition
	}
	for _, definition := range copied.Statuses {
		simulation.statusDefinitions[definition.ID] = definition
	}
	for _, definition := range copied.Dialogues {
		simulation.dialogues[definition.ID] = definition
	}
	for _, definition := range copied.Quests {
		status := QuestInactive
		if definition.InitiallyActive {
			status = QuestActive
		}
		simulation.quests[definition.ID] = &questRuntime{
			definition: definition,
			status:     status,
		}
		simulation.questOrder = append(simulation.questOrder, definition.ID)
	}
	for _, definition := range copied.Entities {
		entity := newEntityRuntime(definition)
		simulation.entities[definition.ID] = entity
		simulation.entityOrder = append(simulation.entityOrder, definition.ID)
		simulation.authoredIDs[definition.ID] = struct{}{}
		if definition.Controlled {
			simulation.controlledID = definition.ID
		}
	}
	for _, definition := range copied.Encounters {
		simulation.encounters[definition.ID] = &encounterRuntime{
			definition:    cloneEncounterConfig(definition),
			status:        EncounterIdle,
			waveIndex:     -1,
			spawnEntities: make(map[string]string),
			enteredPhases: make(map[string]struct{}),
		}
		simulation.encounterOrder = append(
			simulation.encounterOrder,
			definition.ID,
		)
		for _, wave := range definition.Waves {
			for _, spawn := range wave.Spawns {
				simulation.authoredIDs[spawn.Entity.ID] = struct{}{}
			}
		}
	}
	simulation.refreshCameraCenter()
	for _, id := range simulation.encounterOrder {
		if simulation.encounters[id].definition.AutoStart {
			if err := simulation.StartEncounter(id); err != nil {
				return nil, fmt.Errorf(
					"auto-start encounter %q: %w",
					id,
					err,
				)
			}
		}
	}
	return simulation, nil
}

// Clone returns an independent simulation with identical configuration,
// runtime state, and externally visible events. It is used to make batches of
// editor/debug operations transactional.
func (s *Simulation) Clone() *Simulation {
	result := &Simulation{
		config:           cloneConfig(s.config),
		rawTick:          s.rawTick,
		worldTick:        s.worldTick,
		hitstop:          s.hitstop,
		entities:         make(map[string]*entityRuntime, len(s.entities)),
		entityOrder:      append([]string(nil), s.entityOrder...),
		controlledID:     s.controlledID,
		authoredIDs:      cloneStringSet(s.authoredIDs),
		dynamicIDs:       cloneStringSet(s.dynamicIDs),
		removedIDs:       cloneStringSet(s.removedIDs),
		previewDefs:      clonePreviewDefinitions(s.previewDefs),
		interactionRange: s.interactionRange,
		directQuestDefs:  cloneQuestDefinitions(s.directQuestDefs),
		dialogues:        make(map[string]DialogueDefinition, len(s.dialogues)),
		quests:           make(map[string]*questRuntime, len(s.quests)),
		questOrder:       append([]string(nil), s.questOrder...),
		dialogue:         s.dialogue,
		camera:           s.camera,
		projectileDefinitions: cloneProjectileDefinitions(
			s.projectileDefinitions,
		),
		statusDefinitions:  cloneStatusDefinitions(s.statusDefinitions),
		projectiles:        cloneProjectiles(s.projectiles),
		projectileOrder:    append([]string(nil), s.projectileOrder...),
		projectileSequence: s.projectileSequence,
		encounters:         cloneEncounters(s.encounters),
		encounterOrder:     append([]string(nil), s.encounterOrder...),
		lastEvents:         cloneEvents(s.lastEvents),
	}
	for id, entity := range s.entities {
		result.entities[id] = cloneEntityRuntime(entity)
	}
	for id, definition := range s.dialogues {
		result.dialogues[id] = definition
	}
	for id, quest := range s.quests {
		copied := *quest
		result.quests[id] = &copied
	}
	return result
}

// Tick advances exactly one raw fixed tick and returns a detached event slice.
// During hitstop, only the raw tick, hitstop timer, and camera shake advance.
func (s *Simulation) Tick(input Input) []Event {
	s.rawTick++
	s.lastEvents = s.lastEvents[:0]
	s.advanceCameraRaw()

	if s.hitstop > 0 {
		s.hitstop--
		s.refreshCameraCenter()
		return cloneEvents(s.lastEvents)
	}

	s.worldTick++
	s.advanceTimers()
	s.advanceStatuses()
	commands, interactions := s.resolveInput(input)
	s.processActions(commands)
	s.processInteraction(interactions)
	s.integrateMotion(commands)
	s.advanceAttacks()
	s.advanceProjectiles()
	s.advanceEncounters()
	s.refreshCameraCenter()
	return cloneEvents(s.lastEvents)
}

// StartQuest starts an inactive quest. It is intended for content actions and
// debug automation. Completed quests are never reset by this method.
func (s *Simulation) StartQuest(id string) error {
	quest := s.quests[id]
	if quest == nil {
		return fmt.Errorf("unknown quest %q", id)
	}
	if quest.status == QuestInactive {
		quest.status = QuestActive
		s.emit(Event{Type: EventQuestStarted, QuestID: id})
	}
	return nil
}

// SetWall replaces one identified wall with an axis-aligned rectangle against
// the current runtime state. Replacing a polygon intentionally clears its
// authored points: this original rectangle mutation API edits bounds as a
// rectangle, rather than silently stretching a polygon. A rejected edit leaves
// both geometry and entities unchanged.
func (s *Simulation) SetWall(id string, replacement Rect) error {
	if id == "" {
		return errors.New("wall ID is required")
	}
	if err := validateRect(replacement, fmt.Sprintf("wall %q", id)); err != nil {
		return err
	}
	if !containsRect(s.config.StageBounds, replacement) {
		return fmt.Errorf("wall %q lies outside stage bounds", id)
	}
	index := -1
	for candidate := range s.config.Walls {
		if s.config.Walls[candidate].ID == id {
			index = candidate
			break
		}
	}
	if index < 0 {
		return fmt.Errorf("unknown wall %q", id)
	}
	for _, entityID := range s.entityOrder {
		entity := s.entities[entityID]
		if !entity.config.Body.Solid {
			continue
		}
		if overlaps(
			entityRect(entity.position, entity.config.Body),
			replacement,
		) {
			return fmt.Errorf(
				"wall %q overlaps entity %q",
				id,
				entityID,
			)
		}
	}
	s.config.Walls[index] = Wall{
		ID:   id,
		Rect: replacement,
	}
	return nil
}

func (s *Simulation) resolveInput(input Input) (map[string]EntityInput, []string) {
	commands := make(map[string]EntityInput, len(input.Commands)+1)
	if s.controlledID != "" {
		commands[s.controlledID] = EntityInput{
			EntityID:  s.controlledID,
			MoveX:     clampAxis(input.MoveX),
			MoveY:     clampAxis(input.MoveY),
			Attack:    input.Attack,
			AbilityID: input.AbilityID,
			Parry:     input.Parry,
			Dodge:     input.Dodge,
			Jump:      input.Jump,
			Interact:  input.Interact,
		}
	}
	for _, item := range input.Commands {
		item.MoveX = clampAxis(item.MoveX)
		item.MoveY = clampAxis(item.MoveY)
		commands[item.EntityID] = item
	}

	ids := make([]string, 0, len(commands))
	for id := range commands {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	interactions := make([]string, 0, len(ids))
	for _, id := range ids {
		command := commands[id]
		if id == "" || s.entities[id] == nil {
			s.emit(Event{
				Type:     EventInputRejected,
				EntityID: id,
				Reason:   "unknown entity",
			})
			delete(commands, id)
			continue
		}
		if command.Interact {
			interactions = append(interactions, id)
		}
	}
	return commands, interactions
}

func (s *Simulation) processActions(commands map[string]EntityInput) {
	ids := sortedCommandIDs(commands)
	for _, id := range ids {
		entity := s.entities[id]
		command := commands[id]
		if entity.dead {
			continue
		}

		// This matches the source engine's system ordering: parry is resolved
		// before dodge, and either can gate the later attack request.
		if command.Parry {
			s.tryStartParry(entity)
		}
		if command.Dodge {
			s.tryStartDodge(entity, command)
		}
		if command.AbilityID != "" {
			s.tryStartAttack(entity, command.AbilityID)
		} else if command.Attack {
			s.tryStartAttack(entity, "")
		}
	}
}

func (s *Simulation) tryStartParry(entity *entityRuntime) {
	config := entity.config.Parry
	if config == nil || entity.parryCooldown > 0 || entity.parryTicks > 0 ||
		entity.attack != nil || !canAct(entity) {
		return
	}
	entity.parryTicks = config.WindowTicks
	entity.parryLastPerfect = false
	s.emit(Event{Type: EventParryStarted, EntityID: entity.config.ID})
}

func (s *Simulation) tryStartDodge(entity *entityRuntime, command EntityInput) {
	config := entity.config.Dodge
	if config == nil || entity.dodgeCooldown > 0 || entity.dodge.active() ||
		entity.attack != nil || !canAct(entity) {
		return
	}
	direction := normalize(Vec{
		X: Coord(command.MoveX),
		Y: Coord(command.MoveY),
	})
	if direction == (Vec{}) {
		direction = entity.facing
	}
	entity.facing = direction
	entity.dodge = makeBurst(direction, config.Distance, config.DurationTicks)
	entity.dodgeCooldown = config.CooldownTicks
	entity.invulnerableTicks = maxInt(
		entity.invulnerableTicks,
		config.InvulnerabilityTicks,
	)
	s.emit(Event{Type: EventDodgeStarted, EntityID: entity.config.ID})
}

func (s *Simulation) tryStartAttack(entity *entityRuntime, abilityID string) {
	combat := entity.config.Combat
	if combat == nil {
		return
	}
	if abilityID == "" {
		abilityID = combat.PrimaryAbilityID
	}
	ability := combat.Ability(abilityID)
	if ability == nil || entity.attack != nil ||
		entity.abilityCooldowns[abilityID] > 0 ||
		!canAct(entity) {
		return
	}
	phase := AttackWindup
	if ability.WindupTicks == 0 {
		phase = AttackActive
	}
	entity.attack = &attackRuntime{
		abilityID:      ability.ID,
		phase:          phase,
		phaseStartTick: s.worldTick,
		hitTargets:     make(map[string]attackHitRuntime),
	}
	entity.abilityCooldowns[abilityID] = ability.CooldownTicks
	s.emit(Event{
		Type:      EventAttackStarted,
		EntityID:  entity.config.ID,
		AbilityID: ability.ID,
	})
	if phase == AttackActive {
		s.emit(Event{
			Type:      EventAttackActive,
			EntityID:  entity.config.ID,
			AbilityID: ability.ID,
		})
		s.activateAbility(entity, ability)
	}
}

func (s *Simulation) processInteraction(entityIDs []string) {
	if len(entityIDs) == 0 {
		return
	}
	sort.Strings(entityIDs)
	actor := s.entities[entityIDs[0]]
	if actor == nil || actor.dead || !canAct(actor) {
		return
	}
	if s.dialogue.active {
		closed := s.dialogue
		s.dialogue = dialogueRuntime{}
		s.emit(Event{
			Type:       EventDialogueClosed,
			EntityID:   actor.config.ID,
			TargetID:   closed.npcID,
			DialogueID: closed.definitionID,
		})
		return
	}

	rangeLimit := s.interactionRange
	var best *entityRuntime
	var bestDistance int64
	for _, id := range s.entityOrder {
		candidate := s.entities[id]
		if candidate.dead || candidate.config.DialogueID == "" ||
			candidate.config.ID == actor.config.ID {
			continue
		}
		distance := squaredDistance(actor.position, candidate.position)
		if distance > int64(rangeLimit)*int64(rangeLimit) {
			continue
		}
		if best == nil || distance < bestDistance ||
			(distance == bestDistance && candidate.config.ID < best.config.ID) {
			best = candidate
			bestDistance = distance
		}
	}
	if best == nil {
		return
	}
	if best.config.StartQuestID != "" {
		if err := s.StartQuest(best.config.StartQuestID); err != nil {
			return
		}
	}
	s.dialogue = dialogueRuntime{
		active:       true,
		definitionID: best.config.DialogueID,
		npcID:        best.config.ID,
	}
	s.emit(Event{
		Type:       EventDialogueStarted,
		EntityID:   actor.config.ID,
		TargetID:   best.config.ID,
		DialogueID: best.config.DialogueID,
	})
}

func (s *Simulation) integrateMotion(commands map[string]EntityInput) {
	for _, id := range s.entityOrder {
		entity := s.entities[id]
		if entity.dead {
			continue
		}
		if entity.knockback.active() {
			s.moveEntity(entity, entity.knockback.nextDelta())
			continue
		}
		if entity.dodge.active() {
			s.moveEntity(entity, entity.dodge.nextDelta())
			continue
		}
		command, commanded := commands[id]
		if entity.config.Platformer != nil {
			s.integratePlatformer(entity, command, commanded)
			continue
		}
		if !commanded || !canMove(entity) {
			continue
		}
		direction := normalize(Vec{
			X: Coord(command.MoveX),
			Y: Coord(command.MoveY),
		})
		if direction == (Vec{}) {
			continue
		}
		entity.facing = direction
		movePerTick := s.modifiedMovePerTick(entity)
		delta := Vec{
			X: direction.X * movePerTick / UnitsPerPixel,
			Y: direction.Y * movePerTick / UnitsPerPixel,
		}
		s.moveEntity(entity, delta)
	}
}

func (s *Simulation) integratePlatformer(
	entity *entityRuntime,
	command EntityInput,
	commanded bool,
) {
	config := entity.config.Platformer
	if config == nil {
		return
	}
	canControl := commanded && canMove(entity)
	if canControl && command.Jump {
		entity.jumpBufferTicks = config.JumpBufferTicks
	} else {
		entity.jumpBufferTicks = countdown(entity.jumpBufferTicks)
	}
	if entity.grounded {
		entity.coyoteTicks = config.CoyoteTicks
	} else {
		entity.coyoteTicks = countdown(entity.coyoteTicks)
	}
	if canControl && entity.jumpBufferTicks > 0 &&
		entity.coyoteTicks > 0 {
		entity.velocity.Y = -config.JumpSpeedPerTick
		entity.grounded = false
		entity.coyoteTicks = 0
		entity.jumpBufferTicks = 0
		s.emit(Event{
			Type:     EventPlatformerJumped,
			EntityID: entity.config.ID,
		})
	}

	targetX := Coord(0)
	if canControl && command.MoveX != 0 {
		targetX = Coord(command.MoveX) *
			s.modifiedSpeed(entity, config.MaxSpeedPerTick)
		entity.facing = Vec{
			X: Coord(command.MoveX) * UnitsPerPixel,
		}
	}
	acceleration := config.AccelerationPerTick
	if !entity.grounded {
		acceleration = config.AirAcceleration
	}
	if targetX == 0 {
		acceleration = config.DecelerationPerTick
	}
	entity.velocity.X = approachCoord(
		entity.velocity.X,
		targetX,
		acceleration,
	)
	entity.velocity.Y = minCoord(
		entity.velocity.Y+config.GravityPerTick,
		config.MaxFallSpeedPerTick,
	)

	requested := entity.velocity
	actual := s.moveEntity(entity, requested)
	if actual.X != requested.X {
		entity.velocity.X = 0
	}
	wasGrounded := entity.grounded
	if requested.Y > 0 && actual.Y != requested.Y {
		entity.grounded = true
		entity.coyoteTicks = config.CoyoteTicks
		entity.velocity.Y = 0
		if !wasGrounded {
			s.emit(Event{
				Type:     EventPlatformerLanded,
				EntityID: entity.config.ID,
			})
		}
		if canControl && entity.jumpBufferTicks > 0 {
			entity.velocity.Y = -config.JumpSpeedPerTick
			entity.grounded = false
			entity.coyoteTicks = 0
			entity.jumpBufferTicks = 0
			s.emit(Event{
				Type:     EventPlatformerJumped,
				EntityID: entity.config.ID,
			})
		}
	} else {
		entity.grounded = false
		if actual.Y != requested.Y {
			entity.velocity.Y = 0
		}
	}
}

func (s *Simulation) modifiedMovePerTick(entity *entityRuntime) Coord {
	return s.modifiedSpeed(entity, entity.config.MovePerTick)
}

func (s *Simulation) modifiedSpeed(
	entity *entityRuntime,
	base Coord,
) Coord {
	result := base
	stats := effectiveRPGStats(entity)
	result = Coord(scaleFixedSaturated(
		int64(result),
		stats.MoveSpeed,
		int64(maxAbsCoord),
	))
	statusIDs := make([]string, 0, len(entity.statuses))
	for statusID := range entity.statuses {
		statusIDs = append(statusIDs, statusID)
	}
	sort.Strings(statusIDs)
	for _, statusID := range statusIDs {
		status := entity.statuses[statusID]
		multiplier := s.statusDefinitions[statusID].MoveSpeed
		if multiplier == 0 {
			multiplier = UnitsPerPixel
		}
		for stack := 0; stack < status.stacks; stack++ {
			result = Coord(scaleFixedSaturated(
				int64(result),
				multiplier,
				int64(maxAbsCoord),
			))
			if result == maxAbsCoord {
				break
			}
		}
	}
	return result
}

func (s *Simulation) advanceTimers() {
	for _, id := range s.entityOrder {
		entity := s.entities[id]
		for abilityID, ticks := range entity.abilityCooldowns {
			entity.abilityCooldowns[abilityID] = countdown(ticks)
		}
		entity.dodgeCooldown = countdown(entity.dodgeCooldown)
		entity.staggerTicks = countdown(entity.staggerTicks)
		entity.invulnerableTicks = countdown(entity.invulnerableTicks)
		entity.flashTicks = countdown(entity.flashTicks)
		entity.parryCooldown = countdown(entity.parryCooldown)
		if entity.parryTicks > 0 {
			entity.parryTicks--
			if entity.parryTicks == 0 && entity.config.Parry != nil {
				entity.parryCooldown = entity.config.Parry.CooldownTicks
			}
		}
	}
}

func (s *Simulation) applyStatus(
	sourceID string,
	target *entityRuntime,
	statusID string,
	stacks int,
) error {
	definition, exists := s.statusDefinitions[statusID]
	if !exists {
		return fmt.Errorf("unknown status %q", statusID)
	}
	if target == nil || target.dead || target.config.Status == nil {
		return fmt.Errorf("target cannot receive status %q", statusID)
	}
	for _, immune := range target.config.Status.Immune {
		if immune == statusID {
			s.emit(Event{
				Type:     EventStatusResisted,
				SourceID: sourceID,
				TargetID: target.config.ID,
				StatusID: statusID,
			})
			return nil
		}
	}
	if stacks <= 0 {
		return errors.New("status stacks must be positive")
	}
	current := target.statuses[statusID]
	eventType := EventStatusApplied
	if current == nil {
		current = &statusRuntime{
			id:            statusID,
			sourceID:      sourceID,
			stacks:        minInt(stacks, definition.MaxStacks),
			remaining:     definition.DurationTicks,
			tickRemaining: definition.TickIntervalTicks,
		}
		target.statuses[statusID] = current
	} else {
		previousStacks := current.stacks
		if definition.Stacking == StatusStack {
			current.stacks = minInt(
				definition.MaxStacks,
				current.stacks+stacks,
			)
		} else {
			current.stacks = 1
		}
		current.remaining = definition.DurationTicks
		current.sourceID = sourceID
		if current.stacks > previousStacks {
			eventType = EventStatusStacked
		} else {
			eventType = EventStatusRefreshed
		}
	}
	s.emit(Event{
		Type:     eventType,
		SourceID: sourceID,
		TargetID: target.config.ID,
		StatusID: statusID,
		Stacks:   current.stacks,
	})
	return nil
}

func (s *Simulation) advanceStatuses() {
	for _, entityID := range s.entityOrder {
		entity := s.entities[entityID]
		if entity.dead || len(entity.statuses) == 0 {
			continue
		}
		statusIDs := make([]string, 0, len(entity.statuses))
		for statusID := range entity.statuses {
			statusIDs = append(statusIDs, statusID)
		}
		sort.Strings(statusIDs)
		for _, statusID := range statusIDs {
			status := entity.statuses[statusID]
			if status == nil || entity.dead {
				break
			}
			definition := s.statusDefinitions[statusID]
			status.remaining = countdown(status.remaining)
			if definition.TickIntervalTicks > 0 {
				status.tickRemaining = countdown(status.tickRemaining)
				if status.tickRemaining == 0 {
					damage := saturatingProductInt(
						definition.TickDamage,
						status.stacks,
					)
					if damage > 0 {
						if err := s.applyImpact(
							status.sourceID,
							entity.position,
							entity.facing,
							entity.config.ID,
							entity,
							"",
							ImpactConfig{Damage: damage},
							true,
						); err != nil {
							continue
						}
					}
					s.emit(Event{
						Type:     EventStatusTicked,
						SourceID: status.sourceID,
						TargetID: entity.config.ID,
						StatusID: statusID,
						Stacks:   status.stacks,
						Amount:   damage,
					})
					if entity.dead {
						break
					}
					status.tickRemaining = definition.TickIntervalTicks
				}
			}
			if status.remaining == 0 {
				delete(entity.statuses, statusID)
				s.emit(Event{
					Type:     EventStatusExpired,
					SourceID: status.sourceID,
					TargetID: entity.config.ID,
					StatusID: statusID,
					Stacks:   status.stacks,
				})
			}
		}
	}
}

func (s *Simulation) modifiedDamage(
	sourceID string,
	target *entityRuntime,
	base int,
	periodic bool,
) int {
	result := base
	if !periodic {
		result = directRPGDamage(s.entities[sourceID], target, result)
	}
	if source := s.entities[sourceID]; source != nil {
		result = applyStatusModifier(
			result,
			source.statuses,
			s.statusDefinitions,
			func(definition StatusConfig) Coord {
				return definition.DamageDealt
			},
		)
	}
	return applyStatusModifier(
		result,
		target.statuses,
		s.statusDefinitions,
		func(definition StatusConfig) Coord {
			return definition.DamageTaken
		},
	)
}

func directRPGDamage(
	source *entityRuntime,
	target *entityRuntime,
	base int,
) int {
	result := int64(base)
	result += int64(effectiveRPGStats(source).Attack)
	result -= int64(effectiveRPGStats(target).Defense)
	if result < 1 {
		return 1
	}
	maximum := maxInt64Value()
	if result > maximum {
		return int(maximum)
	}
	return int(result)
}

func effectiveRPGStats(entity *entityRuntime) RPGStatsConfig {
	if entity == nil || entity.config.Stats == nil {
		return RPGStatsConfig{MoveSpeed: UnitsPerPixel}
	}
	return *entity.config.Stats
}

func applyStatusModifier(
	value int,
	statuses map[string]*statusRuntime,
	definitions map[string]StatusConfig,
	selectMultiplier func(StatusConfig) Coord,
) int {
	ids := make([]string, 0, len(statuses))
	for id := range statuses {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	result := int64(value)
	for _, id := range ids {
		status := statuses[id]
		multiplier := selectMultiplier(definitions[id])
		if multiplier == 0 {
			multiplier = UnitsPerPixel
		}
		for stack := 0; stack < status.stacks; stack++ {
			result = scaleFixedSaturated(
				result,
				multiplier,
				maxInt64Value(),
			)
			if result == maxInt64Value() {
				break
			}
		}
	}
	return int(result)
}

func scaleFixedSaturated(value int64, multiplier Coord, limit int64) int64 {
	if value <= 0 || multiplier <= 0 || limit <= 0 {
		return 0
	}
	factor := int64(multiplier)
	half := int64(UnitsPerPixel) / 2
	if value > (maxInt64Value()-half)/factor {
		return limit
	}
	result := (value*factor + half) / int64(UnitsPerPixel)
	return min(result, limit)
}

func saturatingProductInt(left, right int) int {
	if left <= 0 || right <= 0 {
		return 0
	}
	limit := maxInt64Value()
	if int64(left) > limit/int64(right) {
		return int(limit)
	}
	return left * right
}

func maxInt64Value() int64 {
	return int64(^uint(0) >> 1)
}

func (s *Simulation) advanceAttacks() {
	for _, id := range s.entityOrder {
		source := s.entities[id]
		if source.attack == nil {
			continue
		}
		if source.dead || !canActIgnoringAttack(source) {
			s.interruptAttack(source, "blocked")
			continue
		}
		s.transitionAttack(source)
		if source.attack == nil || source.attack.phase != AttackActive {
			continue
		}
		s.advanceAttackHitTimers(source.attack)
		s.applyActiveHits(source)
	}
}

func (s *Simulation) transitionAttack(entity *entityRuntime) {
	ability := activeAbility(entity)
	if ability == nil {
		s.interruptAttack(entity, "unknown active ability")
		return
	}
	for entity.attack != nil {
		elapsed := int(s.worldTick - entity.attack.phaseStartTick)
		switch entity.attack.phase {
		case AttackWindup:
			if elapsed < ability.WindupTicks {
				return
			}
			entity.attack.phase = AttackActive
			entity.attack.phaseStartTick = s.worldTick
			s.emit(Event{
				Type:      EventAttackActive,
				EntityID:  entity.config.ID,
				AbilityID: ability.ID,
			})
			s.activateAbility(entity, ability)
		case AttackActive:
			if elapsed < ability.ActiveTicks {
				return
			}
			if ability.RecoveryTicks > 0 {
				entity.attack.phase = AttackRecovery
				entity.attack.phaseStartTick = s.worldTick
			} else {
				s.finishAttack(entity)
			}
		case AttackRecovery:
			if elapsed < ability.RecoveryTicks {
				return
			}
			s.finishAttack(entity)
		default:
			s.interruptAttack(entity, "invalid phase")
		}
	}
}

func (s *Simulation) finishAttack(entity *entityRuntime) {
	if entity.attack == nil {
		return
	}
	abilityID := entity.attack.abilityID
	entity.attack = nil
	s.emit(Event{
		Type:      EventAttackFinished,
		EntityID:  entity.config.ID,
		AbilityID: abilityID,
	})
}

func (s *Simulation) interruptAttack(entity *entityRuntime, reason string) {
	if entity.attack == nil {
		return
	}
	abilityID := entity.attack.abilityID
	entity.attack = nil
	s.emit(Event{
		Type:      EventAttackInterrupted,
		EntityID:  entity.config.ID,
		AbilityID: abilityID,
		Reason:    reason,
	})
}

func (s *Simulation) applyActiveHits(source *entityRuntime) {
	ability := activeAbility(source)
	if ability == nil {
		s.interruptAttack(source, "unknown active ability")
		return
	}
	// Projectile-only abilities do their work on the transition into active.
	if ability.Reach <= 0 {
		return
	}
	for _, targetID := range s.entityOrder {
		if source.attack == nil {
			return
		}
		target := s.entities[targetID]
		if target == source || target.dead || target.config.Team == "" ||
			target.config.Team == source.config.Team {
			continue
		}
		if !attackTargetCanBeHit(source.attack, targetID, ability) {
			continue
		}
		if !s.attackContains(source, target, ability) {
			continue
		}
		if err := s.applyHitTransactional(source, target, ability); err != nil {
			s.interruptAttack(source, err.Error())
			return
		}
	}
}

func (s *Simulation) applyHitTransactional(
	source *entityRuntime,
	target *entityRuntime,
	ability *AbilityConfig,
) (err error) {
	sourceBefore := cloneEntityRuntime(source)
	targetBefore := cloneEntityRuntime(target)
	hitstopBefore := s.hitstop
	cameraBefore := s.camera
	dialogueBefore := s.dialogue
	questsBefore := s.cloneQuestRuntime()
	eventCount := len(s.lastEvents)

	defer func() {
		if recovered := recover(); recovered != nil {
			err = fmt.Errorf("combat transaction panicked: %v", recovered)
		}
		if err == nil {
			return
		}
		*source = *sourceBefore
		*target = *targetBefore
		s.hitstop = hitstopBefore
		s.camera = cameraBefore
		s.dialogue = dialogueBefore
		s.restoreQuestRuntime(questsBefore)
		s.lastEvents = s.lastEvents[:eventCount]
	}()

	if source.dead || target.dead || ability.Damage <= 0 {
		return errors.New("invalid combat transaction")
	}
	if source.attack == nil {
		return errors.New("attack ended before hit resolution")
	}
	if !attackTargetCanBeHit(source.attack, target.config.ID, ability) {
		return errors.New("target cannot be hit again by this attack")
	}
	record := source.attack.hitTargets[target.config.ID]
	record.count++
	if ability.RepeatIntervalTicks > 0 {
		record.repeatRemaining = ability.RepeatIntervalTicks
	} else {
		record.repeatRemaining = MaxTickCount
	}
	source.attack.hitTargets[target.config.ID] = record
	source.attack.hitCount++
	if target.config.Parry != nil && target.parryTicks > 0 {
		if s.inFacingArc(target, source, target.config.Parry.ArcDegrees) {
			s.resolveParry(source, target)
			return nil
		}
		target.parryTicks = 0
		target.parryCooldown = target.config.Parry.CooldownTicks
	}
	return s.applyImpact(
		source.config.ID,
		source.position,
		source.facing,
		target.config.ID,
		target,
		ability.ID,
		ImpactConfig{
			Damage:           ability.Damage,
			StaggerTicks:     ability.StaggerTicks,
			Knockback:        ability.Knockback,
			KnockbackTicks:   ability.KnockbackTicks,
			HitstopTicks:     ability.HitstopTicks,
			CameraShake:      ability.CameraShake,
			CameraShakeTicks: ability.CameraShakeTicks,
		},
		false,
	)
}

func (s *Simulation) applyImpact(
	sourceID string,
	sourcePosition Vec,
	sourceFacing Vec,
	targetID string,
	target *entityRuntime,
	abilityID string,
	impact ImpactConfig,
	periodic bool,
) error {
	if target == nil || target.dead || impact.Damage <= 0 {
		return errors.New("invalid impact")
	}
	if !periodic && target.invulnerableTicks > 0 {
		s.emit(Event{
			Type:      EventDamageBlocked,
			SourceID:  sourceID,
			TargetID:  targetID,
			AbilityID: abilityID,
			Blocked:   true,
			Reason:    "invulnerable",
		})
		return nil
	}

	damage := s.modifiedDamage(sourceID, target, impact.Damage, periodic)
	damage = minInt(maxInt(1, damage), target.health)
	target.health -= damage
	s.emit(Event{
		Type:      EventDamageApplied,
		SourceID:  sourceID,
		TargetID:  targetID,
		AbilityID: abilityID,
		Amount:    damage,
	})
	if target.health == 0 {
		s.killEntity(sourceID, target)
		return nil
	}
	if periodic {
		return nil
	}

	target.invulnerableTicks = maxInt(
		target.invulnerableTicks,
		target.config.Reaction.HitInvulnerabilityTicks,
	)
	target.flashTicks = maxInt(
		target.flashTicks,
		target.config.Reaction.FlashTicks,
	)
	if impact.StaggerTicks > 0 {
		target.staggerTicks = maxInt(target.staggerTicks, impact.StaggerTicks)
		s.interruptAttack(target, "staggered")
		s.emit(Event{
			Type:      EventActorStaggered,
			SourceID:  sourceID,
			TargetID:  targetID,
			AbilityID: abilityID,
		})
	}
	if impact.ApplyStatusID != "" {
		if err := s.applyStatus(
			sourceID,
			target,
			impact.ApplyStatusID,
			1,
		); err != nil {
			return err
		}
	}
	if impact.Knockback > 0 && impact.KnockbackTicks > 0 {
		direction := directionBetween(sourcePosition, target.position)
		if direction == (Vec{}) {
			direction = sourceFacing
		}
		target.knockback = makeBurst(
			direction,
			impact.Knockback,
			impact.KnockbackTicks,
		)
		s.emit(Event{
			Type:      EventKnockbackStarted,
			SourceID:  sourceID,
			TargetID:  targetID,
			AbilityID: abilityID,
		})
	}
	s.startImpact(
		impact.HitstopTicks,
		impact.CameraShake,
		impact.CameraShakeTicks,
		sourceID,
		targetID,
	)
	return nil
}

func (s *Simulation) resolveParry(source, target *entityRuntime) {
	config := target.config.Parry
	abilityID := activeAbilityID(source)
	abilityDamage := activeAbilityDamage(source)
	elapsed := config.WindowTicks - target.parryTicks
	perfect := elapsed <= config.PerfectWindowTicks
	target.parryTicks = 0
	target.parryLastPerfect = perfect
	target.parryCooldown = config.SuccessCooldownTicks

	stagger := config.StaggerTicks
	hitstop := config.HitstopTicks
	if perfect {
		stagger = config.PerfectStaggerTicks
		hitstop = config.PerfectHitstopTicks
	}
	source.staggerTicks = maxInt(source.staggerTicks, stagger)
	s.interruptAttack(source, "parried")
	s.emit(Event{
		Type:     EventActorStaggered,
		SourceID: target.config.ID,
		TargetID: source.config.ID,
		Perfect:  perfect,
	})
	s.emit(Event{
		Type:      EventAttackParried,
		SourceID:  source.config.ID,
		TargetID:  target.config.ID,
		AbilityID: abilityID,
		Amount:    abilityDamage,
		Blocked:   true,
		Perfect:   perfect,
	})
	s.startImpact(
		hitstop,
		config.CameraShake,
		config.CameraShakeTicks,
		target.config.ID,
		source.config.ID,
	)
}

func (s *Simulation) killEntity(sourceID string, target *entityRuntime) {
	target.dead = true
	target.health = 0
	target.attack = nil
	target.staggerTicks = 0
	target.invulnerableTicks = 0
	target.flashTicks = 0
	target.knockback = burstRuntime{}
	target.dodge = burstRuntime{}
	target.parryTicks = 0
	target.statuses = make(map[string]*statusRuntime)
	target.velocity = Vec{}
	target.grounded = false
	target.coyoteTicks = 0
	target.jumpBufferTicks = 0
	s.emit(Event{
		Type:     EventActorKilled,
		SourceID: sourceID,
		TargetID: target.config.ID,
	})
	if s.dialogue.active && s.dialogue.npcID == target.config.ID {
		closed := s.dialogue
		s.dialogue = dialogueRuntime{}
		s.emit(Event{
			Type:       EventDialogueClosed,
			EntityID:   sourceID,
			TargetID:   target.config.ID,
			DialogueID: closed.definitionID,
			Reason:     "speaker killed",
		})
	}
	s.progressQuests(target)
}

func (s *Simulation) progressQuests(target *entityRuntime) {
	for _, id := range s.questOrder {
		quest := s.quests[id]
		definition := quest.definition
		if quest.status != QuestActive ||
			(definition.TargetEntityID != "" &&
				definition.TargetEntityID != target.config.ID) ||
			(definition.TargetKind != "" &&
				definition.TargetKind != target.config.Kind) {
			continue
		}
		quest.progress = minInt(quest.progress+1, definition.Required)
		s.emit(Event{
			Type:     EventQuestProgress,
			QuestID:  id,
			Progress: quest.progress,
			Required: definition.Required,
		})
		if quest.progress == definition.Required {
			quest.status = QuestCompleted
			s.emit(Event{
				Type:     EventQuestCompleted,
				QuestID:  id,
				Progress: quest.progress,
				Required: definition.Required,
			})
		}
	}
}

func (s *Simulation) startImpact(
	hitstop int,
	shake Coord,
	shakeTicks int,
	sourceID string,
	targetID string,
) {
	if hitstop > s.hitstop {
		s.hitstop = hitstop
	}
	if hitstop > 0 {
		s.emit(Event{
			Type:     EventHitstopStarted,
			SourceID: sourceID,
			TargetID: targetID,
			Amount:   hitstop,
		})
	}
	if shake <= 0 || shakeTicks <= 0 {
		return
	}
	s.camera.shakeMagnitude = maxCoord(s.camera.shakeMagnitude, shake)
	s.camera.shakeDuration = maxInt(s.camera.shakeDuration, shakeTicks)
	s.camera.shakeRemaining = maxInt(s.camera.shakeRemaining, shakeTicks)
	s.camera.shakeSequence++
}

func (s *Simulation) advanceCameraRaw() {
	camera := &s.camera
	if camera.shakeRemaining <= 0 || camera.shakeDuration <= 0 {
		camera.offset = Vec{}
		camera.shakeMagnitude = 0
		camera.shakeDuration = 0
		camera.shakeRemaining = 0
		return
	}
	amplitude := camera.shakeMagnitude *
		Coord(camera.shakeRemaining) / Coord(camera.shakeDuration)
	camera.offset = Vec{
		X: deterministicShake(
			s.rawTick,
			camera.shakeSequence,
			0x9e3779b97f4a7c15,
			amplitude,
		),
		Y: deterministicShake(
			s.rawTick,
			camera.shakeSequence,
			0xd1b54a32d192ed03,
			amplitude,
		),
	}
	camera.shakeRemaining--
}

func (s *Simulation) refreshCameraCenter() {
	target := s.entities[s.config.Camera.TargetEntityID]
	if target != nil {
		s.camera.baseCenter = clampCamera(
			target.position,
			s.config.StageBounds,
			s.config.Camera,
		)
	}
	desired := Vec{
		X: s.camera.baseCenter.X + s.camera.offset.X,
		Y: s.camera.baseCenter.Y + s.camera.offset.Y,
	}
	s.camera.center = clampCamera(
		desired,
		s.config.StageBounds,
		s.config.Camera,
	)
	s.camera.offset = Vec{
		X: s.camera.center.X - s.camera.baseCenter.X,
		Y: s.camera.center.Y - s.camera.baseCenter.Y,
	}
}

func (s *Simulation) moveEntity(entity *entityRuntime, delta Vec) Vec {
	start := entity.position
	if delta.X != 0 {
		nextX := entity.position.X + delta.X
		nextX = clampEntityX(nextX, entity.config.Body, s.config.StageBounds)
		if entity.config.Body.Solid {
			for _, wall := range s.config.Walls {
				nextX = clampAxisAgainstWall(
					wall,
					entity.config.Body,
					entity.position.X,
					nextX,
					entity.position.Y,
					true,
				)
			}
		}
		entity.position.X = clampEntityX(
			nextX,
			entity.config.Body,
			s.config.StageBounds,
		)
	}
	if delta.Y != 0 {
		nextY := entity.position.Y + delta.Y
		nextY = clampEntityY(nextY, entity.config.Body, s.config.StageBounds)
		if entity.config.Body.Solid {
			for _, wall := range s.config.Walls {
				nextY = clampAxisAgainstWall(
					wall,
					entity.config.Body,
					entity.position.Y,
					nextY,
					entity.position.X,
					false,
				)
			}
		}
		entity.position.Y = clampEntityY(
			nextY,
			entity.config.Body,
			s.config.StageBounds,
		)
	}
	return Vec{
		X: entity.position.X - start.X,
		Y: entity.position.Y - start.Y,
	}
}

func (s *Simulation) attackContains(
	source *entityRuntime,
	target *entityRuntime,
	ability *AbilityConfig,
) bool {
	delta := Vec{
		X: target.position.X - source.position.X,
		Y: target.position.Y - source.position.Y,
	}
	targetRadius := maxCoord(
		target.config.Body.HalfWidth,
		target.config.Body.HalfHeight,
	)
	reach := ability.Reach + targetRadius
	if squaredMagnitude(delta) > int64(reach)*int64(reach) {
		return false
	}
	return withinArc(source.facing, delta, ability.ArcDegrees)
}

func activeAbility(entity *entityRuntime) *AbilityConfig {
	if entity == nil || entity.attack == nil || entity.config.Combat == nil {
		return nil
	}
	return entity.config.Combat.Ability(entity.attack.abilityID)
}

func activeAbilityID(entity *entityRuntime) string {
	if entity == nil || entity.attack == nil {
		return ""
	}
	return entity.attack.abilityID
}

func activeAbilityDamage(entity *entityRuntime) int {
	ability := activeAbility(entity)
	if ability == nil {
		return 0
	}
	return ability.Damage
}

func attackTargetCanBeHit(
	attack *attackRuntime,
	targetID string,
	ability *AbilityConfig,
) bool {
	if attack == nil || ability == nil {
		return false
	}
	record, exists := attack.hitTargets[targetID]
	if !exists {
		return true
	}
	return record.count < maxInt(1, ability.MaxHits) &&
		record.repeatRemaining <= 0
}

func (s *Simulation) advanceAttackHitTimers(attack *attackRuntime) {
	if attack == nil {
		return
	}
	for targetID, record := range attack.hitTargets {
		record.repeatRemaining = countdown(record.repeatRemaining)
		attack.hitTargets[targetID] = record
	}
}

func (s *Simulation) inFacingArc(
	target *entityRuntime,
	source *entityRuntime,
	degrees int,
) bool {
	return withinArc(
		target.facing,
		Vec{
			X: source.position.X - target.position.X,
			Y: source.position.Y - target.position.Y,
		},
		degrees,
	)
}

func (s *Simulation) emit(event Event) {
	event.Tick = s.rawTick
	s.lastEvents = append(s.lastEvents, event)
}

func canAct(entity *entityRuntime) bool {
	return canActIgnoringAttack(entity) && entity.attack == nil
}

func canActIgnoringAttack(entity *entityRuntime) bool {
	return !entity.dead &&
		entity.staggerTicks == 0 &&
		!entity.knockback.active() &&
		!entity.dodge.active() &&
		entity.parryTicks == 0
}

func canMove(entity *entityRuntime) bool {
	if !canActIgnoringAttack(entity) {
		return false
	}
	ability := activeAbility(entity)
	return entity.attack == nil || ability == nil || !ability.LockMovement
}

func validateConfig(config Config) error {
	if err := validateRect(config.StageBounds, "stage bounds"); err != nil {
		return err
	}
	if config.InteractionRange < 0 {
		return errors.New("interaction range cannot be negative")
	}
	if !validCoord(config.InteractionRange) {
		return errors.New("interaction range is outside deterministic range")
	}
	if config.Camera.ViewportWidth <= 0 ||
		config.Camera.ViewportHeight <= 0 {
		return errors.New("camera viewport dimensions must be positive")
	}
	if !validCoord(config.Camera.ViewportWidth) ||
		!validCoord(config.Camera.ViewportHeight) {
		return errors.New("camera viewport is outside deterministic range")
	}
	walls := make(map[string]struct{}, len(config.Walls))
	for index, wall := range config.Walls {
		if wall.ID == "" {
			return fmt.Errorf("wall %d requires an ID", index)
		}
		if _, duplicate := walls[wall.ID]; duplicate {
			return fmt.Errorf("duplicate wall %q", wall.ID)
		}
		walls[wall.ID] = struct{}{}
		if err := validateWallGeometry(
			wall,
			fmt.Sprintf("wall %q", wall.ID),
		); err != nil {
			return err
		}
		if !containsRect(config.StageBounds, wall.Rect) {
			return fmt.Errorf("wall %q lies outside stage bounds", wall.ID)
		}
	}

	dialogues := make(map[string]struct{}, len(config.Dialogues))
	for _, definition := range config.Dialogues {
		if definition.ID == "" {
			return errors.New("dialogue ID is required")
		}
		if _, duplicate := dialogues[definition.ID]; duplicate {
			return fmt.Errorf("duplicate dialogue %q", definition.ID)
		}
		dialogues[definition.ID] = struct{}{}
	}
	quests := make(map[string]struct{}, len(config.Quests))
	for _, definition := range config.Quests {
		if definition.ID == "" || definition.Required <= 0 {
			return fmt.Errorf("quest %q requires an ID and positive target count", definition.ID)
		}
		if _, duplicate := quests[definition.ID]; duplicate {
			return fmt.Errorf("duplicate quest %q", definition.ID)
		}
		quests[definition.ID] = struct{}{}
	}
	statuses := make(map[string]struct{}, len(config.Statuses))
	for _, definition := range config.Statuses {
		if _, duplicate := statuses[definition.ID]; duplicate {
			return fmt.Errorf("duplicate status %q", definition.ID)
		}
		if definition.ID == "" ||
			definition.DurationTicks <= 0 ||
			(definition.Stacking != StatusRefresh &&
				definition.Stacking != StatusStack) ||
			definition.MaxStacks <= 0 ||
			definition.MaxStacks > MaxStatusStacks ||
			(definition.Stacking == StatusRefresh &&
				definition.MaxStacks != 1) ||
			definition.TickIntervalTicks < 0 ||
			definition.TickDamage < 0 ||
			(definition.TickIntervalTicks > 0) !=
				(definition.TickDamage > 0) ||
			!validTickCount(
				definition.DurationTicks,
				definition.TickIntervalTicks,
			) ||
			!validStatusMultiplier(definition.MoveSpeed) ||
			!validStatusMultiplier(definition.DamageDealt) ||
			!validStatusMultiplier(definition.DamageTaken) {
			return fmt.Errorf("status %q has invalid configuration", definition.ID)
		}
		statuses[definition.ID] = struct{}{}
	}
	projectiles := make(map[string]struct{}, len(config.Projectiles))
	for _, definition := range config.Projectiles {
		if _, duplicate := projectiles[definition.ID]; duplicate {
			return fmt.Errorf("duplicate projectile %q", definition.ID)
		}
		if definition.ID == "" || definition.ActorKind == "" ||
			definition.SpeedPerTick <= 0 ||
			!validCoord(definition.SpeedPerTick) ||
			definition.LifetimeTicks <= 0 ||
			definition.SpawnOffset < 0 ||
			!validCoord(definition.SpawnOffset) ||
			definition.Pierce < 0 ||
			!validTickCount(definition.LifetimeTicks) ||
			definition.Impact.Damage <= 0 {
			return fmt.Errorf(
				"projectile %q has invalid configuration",
				definition.ID,
			)
		}
		if err := validateBody(
			definition.Body,
			fmt.Sprintf("projectile %q body", definition.ID),
		); err != nil {
			return err
		}
		if err := validateImpact(definition.Impact); err != nil {
			return fmt.Errorf("projectile %q: %w", definition.ID, err)
		}
		if definition.Impact.ApplyStatusID != "" {
			if _, exists := statuses[definition.Impact.ApplyStatusID]; !exists {
				return fmt.Errorf(
					"projectile %q references unknown status %q",
					definition.ID,
					definition.Impact.ApplyStatusID,
				)
			}
		}
		projectiles[definition.ID] = struct{}{}
	}

	entities := make(map[string]struct{}, len(config.Entities))
	controlled := 0
	hasInteractable := false
	for _, definition := range config.Entities {
		if _, duplicate := entities[definition.ID]; duplicate {
			return fmt.Errorf("duplicate entity %q", definition.ID)
		}
		entities[definition.ID] = struct{}{}
		if definition.Controlled {
			controlled++
		}
		if definition.MaxHealth <= 0 {
			return fmt.Errorf("entity %q maximum health must be positive", definition.ID)
		}
		if err := validateBody(
			definition.Body,
			fmt.Sprintf("entity %q body", definition.ID),
		); err != nil {
			return err
		}
		if definition.MovePerTick < 0 || !validCoord(definition.MovePerTick) {
			return fmt.Errorf("entity %q move speed cannot be negative", definition.ID)
		}
		if !validCoord(definition.Position.X) ||
			!validCoord(definition.Position.Y) {
			return fmt.Errorf("entity %q position is outside deterministic range", definition.ID)
		}
		if !containsRect(
			config.StageBounds,
			entityRect(definition.Position, definition.Body),
		) {
			return fmt.Errorf("entity %q starts outside stage bounds", definition.ID)
		}
		if definition.Body.Solid {
			for wallIndex, wall := range config.Walls {
				if wallOverlapsRect(
					wall,
					entityRect(definition.Position, definition.Body),
				) {
					return fmt.Errorf(
						"entity %q overlaps wall %q at index %d",
						definition.ID,
						wall.ID,
						wallIndex,
					)
				}
			}
		}
		if definition.DialogueID != "" {
			hasInteractable = true
		}
		if err := validateEntityDefinition(
			config,
			definition,
			dialogues,
			quests,
		); err != nil {
			return err
		}
		if definition.Status != nil {
			seenImmune := make(map[string]struct{}, len(definition.Status.Immune))
			for _, statusID := range definition.Status.Immune {
				if _, exists := statuses[statusID]; !exists {
					return fmt.Errorf(
						"entity %q is immune to unknown status %q",
						definition.ID,
						statusID,
					)
				}
				if _, duplicate := seenImmune[statusID]; duplicate {
					return fmt.Errorf(
						"entity %q duplicates status immunity %q",
						definition.ID,
						statusID,
					)
				}
				seenImmune[statusID] = struct{}{}
			}
		}
		if definition.Combat != nil {
			for _, ability := range definition.Combat.Abilities {
				if ability.ProjectileID == "" {
					continue
				}
				if _, exists := projectiles[ability.ProjectileID]; !exists {
					return fmt.Errorf(
						"entity %q ability %q references unknown projectile %q",
						definition.ID,
						ability.ID,
						ability.ProjectileID,
					)
				}
			}
		}
	}
	if err := validateEncounters(
		config,
		entities,
		dialogues,
		quests,
		statuses,
		projectiles,
	); err != nil {
		return err
	}
	if hasInteractable && config.InteractionRange == 0 {
		return errors.New("interactable entities require a positive interaction range")
	}
	if controlled != 1 {
		return fmt.Errorf("config requires exactly one controlled entity, got %d", controlled)
	}
	if _, exists := entities[config.Camera.TargetEntityID]; !exists {
		return fmt.Errorf(
			"camera references unknown entity %q",
			config.Camera.TargetEntityID,
		)
	}
	for _, definition := range config.Quests {
		if definition.TargetEntityID != "" {
			if _, exists := entities[definition.TargetEntityID]; !exists {
				return fmt.Errorf(
					"quest %q references unknown entity %q",
					definition.ID,
					definition.TargetEntityID,
				)
			}
		}
	}
	return nil
}

func validStatusMultiplier(value Coord) bool {
	return value > 0 && value <= UnitsPerPixel*16 && validCoord(value)
}

func validatePlatformerConfig(config *PlatformerConfig) error {
	if config == nil ||
		config.MaxSpeedPerTick <= 0 ||
		config.AccelerationPerTick <= 0 ||
		config.AirAcceleration <= 0 ||
		config.DecelerationPerTick <= 0 ||
		config.GravityPerTick <= 0 ||
		config.JumpSpeedPerTick <= 0 ||
		config.MaxFallSpeedPerTick <= 0 ||
		config.CoyoteTicks < 0 ||
		config.JumpBufferTicks < 0 ||
		!validCoord(config.MaxSpeedPerTick) ||
		!validCoord(config.AccelerationPerTick) ||
		!validCoord(config.AirAcceleration) ||
		!validCoord(config.DecelerationPerTick) ||
		!validCoord(config.GravityPerTick) ||
		!validCoord(config.JumpSpeedPerTick) ||
		!validCoord(config.MaxFallSpeedPerTick) ||
		!validTickCount(config.CoyoteTicks, config.JumpBufferTicks) {
		return errors.New("invalid platformer movement configuration")
	}
	return nil
}

func validateImpact(impact ImpactConfig) error {
	if impact.Damage <= 0 ||
		impact.StaggerTicks < 0 ||
		impact.Knockback < 0 ||
		!validCoord(impact.Knockback) ||
		impact.KnockbackTicks < 0 ||
		(impact.Knockback > 0) != (impact.KnockbackTicks > 0) ||
		impact.HitstopTicks < 0 ||
		impact.CameraShake < 0 ||
		!validCoord(impact.CameraShake) ||
		impact.CameraShakeTicks < 0 ||
		(impact.CameraShake > 0) != (impact.CameraShakeTicks > 0) ||
		!validTickCount(
			impact.StaggerTicks,
			impact.KnockbackTicks,
			impact.HitstopTicks,
			impact.CameraShakeTicks,
		) {
		return errors.New("invalid impact configuration")
	}
	return nil
}

func validateEntityDefinition(
	config Config,
	definition EntityConfig,
	dialogues map[string]struct{},
	quests map[string]struct{},
) error {
	return validateEntityDefinitionWithPlacement(
		config,
		definition,
		dialogues,
		quests,
		true,
	)
}

func validateEntityDefinitionWithPlacement(
	config Config,
	definition EntityConfig,
	dialogues map[string]struct{},
	quests map[string]struct{},
	validatePlacement bool,
) error {
	if definition.ID == "" || definition.Kind == "" {
		return errors.New("entity ID and kind are required")
	}
	if definition.MaxHealth <= 0 {
		return fmt.Errorf("entity %q maximum health must be positive", definition.ID)
	}
	if err := validateBody(
		definition.Body,
		fmt.Sprintf("entity %q body", definition.ID),
	); err != nil {
		return err
	}
	if definition.MovePerTick < 0 || !validCoord(definition.MovePerTick) {
		return fmt.Errorf("entity %q move speed cannot be negative", definition.ID)
	}
	if stats := definition.Stats; stats != nil {
		if stats.Attack < 0 ||
			stats.Defense < 0 ||
			stats.MoveSpeed < 0 ||
			!validCoord(stats.MoveSpeed) {
			return fmt.Errorf(
				"entity %q has invalid RPG stats",
				definition.ID,
			)
		}
	}
	if definition.Platformer != nil {
		if definition.MovePerTick != 0 {
			return fmt.Errorf(
				"entity %q cannot combine topdown and platformer movement",
				definition.ID,
			)
		}
		if err := validatePlatformerConfig(definition.Platformer); err != nil {
			return fmt.Errorf("entity %q: %w", definition.ID, err)
		}
	}
	if !validCoord(definition.Position.X) ||
		!validCoord(definition.Position.Y) {
		return fmt.Errorf("entity %q position is outside deterministic range", definition.ID)
	}
	if validatePlacement {
		if !containsRect(
			config.StageBounds,
			entityRect(definition.Position, definition.Body),
		) {
			return fmt.Errorf(
				"entity %q starts outside stage bounds",
				definition.ID,
			)
		}
		if definition.Body.Solid {
			for wallIndex, wall := range config.Walls {
				if wallOverlapsRect(
					wall,
					entityRect(definition.Position, definition.Body),
				) {
					return fmt.Errorf(
						"entity %q overlaps wall %q at index %d",
						definition.ID,
						wall.ID,
						wallIndex,
					)
				}
			}
		}
	}
	if definition.DialogueID != "" {
		if _, exists := dialogues[definition.DialogueID]; !exists {
			return fmt.Errorf(
				"entity %q references unknown dialogue %q",
				definition.ID,
				definition.DialogueID,
			)
		}
	}
	if definition.StartQuestID != "" {
		if _, exists := quests[definition.StartQuestID]; !exists {
			return fmt.Errorf(
				"entity %q references unknown quest %q",
				definition.ID,
				definition.StartQuestID,
			)
		}
	}
	return validateEntityActionConfig(definition)
}

func validateEntityActionConfig(definition EntityConfig) error {
	if definition.Combat != nil {
		if definition.Team == "" ||
			definition.Combat.PrimaryAbilityID == "" ||
			len(definition.Combat.Abilities) == 0 {
			return fmt.Errorf("entity %q has invalid combat loadout", definition.ID)
		}
		seenAbilities := make(map[string]struct{}, len(definition.Combat.Abilities))
		for index := range definition.Combat.Abilities {
			ability := &definition.Combat.Abilities[index]
			if _, duplicate := seenAbilities[ability.ID]; duplicate {
				return fmt.Errorf(
					"entity %q duplicates ability %q",
					definition.ID,
					ability.ID,
				)
			}
			seenAbilities[ability.ID] = struct{}{}
			if err := validateAbilityConfig(ability); err != nil {
				return fmt.Errorf(
					"entity %q ability %q: %w",
					definition.ID,
					ability.ID,
					err,
				)
			}
		}
		if definition.Combat.PrimaryAbility() == nil {
			return fmt.Errorf(
				"entity %q has unknown primary ability %q",
				definition.ID,
				definition.Combat.PrimaryAbilityID,
			)
		}
		seenInputs := make(map[string]struct{}, len(definition.Combat.Bindings))
		for _, binding := range definition.Combat.Bindings {
			if binding.Input == "" ||
				definition.Combat.Ability(binding.AbilityID) == nil {
				return fmt.Errorf(
					"entity %q has invalid ability binding",
					definition.ID,
				)
			}
			if _, duplicate := seenInputs[binding.Input]; duplicate {
				return fmt.Errorf(
					"entity %q duplicates ability input %q",
					definition.ID,
					binding.Input,
				)
			}
			seenInputs[binding.Input] = struct{}{}
		}
	}
	if reaction := definition.Reaction; reaction.HitInvulnerabilityTicks < 0 ||
		reaction.FlashTicks < 0 ||
		!validTickCount(
			reaction.HitInvulnerabilityTicks,
			reaction.FlashTicks,
		) {
		return fmt.Errorf("entity %q has invalid reaction configuration", definition.ID)
	}
	if dodge := definition.Dodge; dodge != nil {
		if dodge.DurationTicks <= 0 || dodge.Distance <= 0 ||
			!validCoord(dodge.Distance) ||
			dodge.InvulnerabilityTicks < 0 ||
			dodge.InvulnerabilityTicks > dodge.DurationTicks ||
			dodge.CooldownTicks < 0 ||
			!validTickCount(
				dodge.DurationTicks,
				dodge.InvulnerabilityTicks,
				dodge.CooldownTicks,
			) {
			return fmt.Errorf("entity %q has invalid dodge configuration", definition.ID)
		}
	}
	if parry := definition.Parry; parry != nil {
		if parry.WindowTicks <= 0 || parry.PerfectWindowTicks < 0 ||
			parry.PerfectWindowTicks > parry.WindowTicks ||
			parry.CooldownTicks < 0 || parry.SuccessCooldownTicks < 0 ||
			parry.ArcDegrees < 1 || parry.ArcDegrees > 360 ||
			parry.StaggerTicks < 0 || parry.PerfectStaggerTicks < 0 ||
			parry.HitstopTicks < 0 || parry.PerfectHitstopTicks < 0 ||
			parry.CameraShake < 0 || !validCoord(parry.CameraShake) ||
			parry.CameraShakeTicks < 0 ||
			!validTickCount(
				parry.WindowTicks,
				parry.PerfectWindowTicks,
				parry.CooldownTicks,
				parry.SuccessCooldownTicks,
				parry.StaggerTicks,
				parry.PerfectStaggerTicks,
				parry.HitstopTicks,
				parry.PerfectHitstopTicks,
				parry.CameraShakeTicks,
			) ||
			(parry.CameraShake > 0) != (parry.CameraShakeTicks > 0) {
			return fmt.Errorf("entity %q has invalid parry configuration", definition.ID)
		}
	}
	return nil
}

func validateAbilityConfig(ability *AbilityConfig) error {
	if ability == nil {
		return errors.New("configuration is required")
	}
	hasMelee := ability.Reach > 0
	hasProjectile := ability.ProjectileID != ""
	maxHits := maxInt(1, ability.MaxHits)
	if ability.ID == "" || ability.ActiveTicks <= 0 ||
		ability.WindupTicks < 0 || ability.RecoveryTicks < 0 ||
		ability.CooldownTicks < 0 ||
		(!hasMelee && !hasProjectile) ||
		ability.Reach < 0 || !validCoord(ability.Reach) ||
		(hasMelee && (ability.ArcDegrees < 1 ||
			ability.ArcDegrees > 360 || ability.Damage <= 0)) ||
		(!hasMelee && (ability.ArcDegrees != 0 || ability.Damage != 0)) ||
		ability.StaggerTicks < 0 ||
		ability.Knockback < 0 || !validCoord(ability.Knockback) ||
		ability.KnockbackTicks < 0 ||
		(ability.Knockback > 0) != (ability.KnockbackTicks > 0) ||
		ability.HitstopTicks < 0 ||
		ability.CameraShake < 0 || !validCoord(ability.CameraShake) ||
		ability.CameraShakeTicks < 0 ||
		ability.MaxHits < 0 ||
		ability.RepeatIntervalTicks < 0 ||
		(maxHits > 1) != (ability.RepeatIntervalTicks > 0) ||
		!validTickCount(
			ability.WindupTicks,
			ability.ActiveTicks,
			ability.RecoveryTicks,
			ability.CooldownTicks,
			ability.StaggerTicks,
			ability.KnockbackTicks,
			ability.HitstopTicks,
			ability.CameraShakeTicks,
			ability.RepeatIntervalTicks,
		) ||
		(ability.CameraShake > 0) != (ability.CameraShakeTicks > 0) {
		return errors.New("invalid configuration")
	}
	return nil
}

func validateRect(rect Rect, label string) error {
	if rect.MinX >= rect.MaxX || rect.MinY >= rect.MaxY {
		return fmt.Errorf("%s must have positive dimensions", label)
	}
	if !validCoord(rect.MinX) || !validCoord(rect.MinY) ||
		!validCoord(rect.MaxX) || !validCoord(rect.MaxY) {
		return fmt.Errorf("%s is outside deterministic range", label)
	}
	return nil
}

func cloneConfig(config Config) Config {
	result := config
	result.Walls = cloneWalls(config.Walls)
	result.Dialogues = append([]DialogueDefinition(nil), config.Dialogues...)
	result.Quests = append([]QuestDefinition(nil), config.Quests...)
	result.Projectiles = append([]ProjectileConfig(nil), config.Projectiles...)
	result.Statuses = append([]StatusConfig(nil), config.Statuses...)
	result.Encounters = make([]EncounterConfig, len(config.Encounters))
	for index, encounter := range config.Encounters {
		result.Encounters[index] = cloneEncounterConfig(encounter)
	}
	result.Entities = make([]EntityConfig, len(config.Entities))
	for index, entity := range config.Entities {
		result.Entities[index] = cloneEntityConfig(entity)
	}
	return result
}

func cloneEntityConfig(config EntityConfig) EntityConfig {
	result := config
	if config.Combat != nil {
		combat := *config.Combat
		combat.Abilities = append([]AbilityConfig(nil), config.Combat.Abilities...)
		combat.Bindings = append([]AbilityBinding(nil), config.Combat.Bindings...)
		result.Combat = &combat
	}
	if config.Ability != nil {
		ability := *config.Ability
		result.Ability = &ability
	}
	if config.Dodge != nil {
		copied := *config.Dodge
		result.Dodge = &copied
	}
	if config.Parry != nil {
		copied := *config.Parry
		result.Parry = &copied
	}
	if config.Status != nil {
		status := *config.Status
		status.Immune = append([]string(nil), config.Status.Immune...)
		result.Status = &status
	}
	if config.Stats != nil {
		stats := *config.Stats
		result.Stats = &stats
	}
	if config.Platformer != nil {
		platformer := *config.Platformer
		result.Platformer = &platformer
	}
	return result
}

func normalizeCombatConfig(config *Config) {
	for index := range config.Entities {
		normalizeEntityCombat(&config.Entities[index])
	}
	for encounterIndex := range config.Encounters {
		for waveIndex := range config.Encounters[encounterIndex].Waves {
			wave := &config.Encounters[encounterIndex].Waves[waveIndex]
			for spawnIndex := range wave.Spawns {
				normalizeEntityCombat(
					&wave.Spawns[spawnIndex].Entity,
				)
			}
		}
	}
}

func normalizeEntityCombat(entity *EntityConfig) {
	if entity == nil || entity.Ability == nil {
		return
	}
	if entity.Combat == nil {
		ability := *entity.Ability
		entity.Combat = &CombatConfig{
			PrimaryAbilityID: ability.ID,
			Abilities:        []AbilityConfig{ability},
			Bindings: []AbilityBinding{{
				Input:     "attack",
				AbilityID: ability.ID,
			}},
		}
	}
	entity.Ability = nil
}

func sortConfig(config *Config) {
	sort.Slice(config.Walls, func(left, right int) bool {
		a, b := config.Walls[left], config.Walls[right]
		return a.ID < b.ID
	})
	sort.Slice(config.Entities, func(left, right int) bool {
		return config.Entities[left].ID < config.Entities[right].ID
	})
	for index := range config.Entities {
		sortEntityConfig(&config.Entities[index])
	}
	sort.Slice(config.Dialogues, func(left, right int) bool {
		return config.Dialogues[left].ID < config.Dialogues[right].ID
	})
	sort.Slice(config.Quests, func(left, right int) bool {
		return config.Quests[left].ID < config.Quests[right].ID
	})
	sort.Slice(config.Projectiles, func(left, right int) bool {
		return config.Projectiles[left].ID < config.Projectiles[right].ID
	})
	sort.Slice(config.Statuses, func(left, right int) bool {
		return config.Statuses[left].ID < config.Statuses[right].ID
	})
	sort.Slice(config.Encounters, func(left, right int) bool {
		return config.Encounters[left].ID < config.Encounters[right].ID
	})
	for encounterIndex := range config.Encounters {
		for waveIndex := range config.Encounters[encounterIndex].Waves {
			wave := &config.Encounters[encounterIndex].Waves[waveIndex]
			for spawnIndex := range wave.Spawns {
				sortEntityConfig(&wave.Spawns[spawnIndex].Entity)
			}
		}
	}
}

func sortEntityConfig(entity *EntityConfig) {
	if entity == nil {
		return
	}
	combat := entity.Combat
	if combat != nil {
		sort.Slice(combat.Abilities, func(left, right int) bool {
			return combat.Abilities[left].ID < combat.Abilities[right].ID
		})
		sort.Slice(combat.Bindings, func(left, right int) bool {
			return combat.Bindings[left].Input < combat.Bindings[right].Input
		})
	}
	if entity.Status != nil {
		sort.Strings(entity.Status.Immune)
	}
}

func cloneEntityRuntime(source *entityRuntime) *entityRuntime {
	result := *source
	result.config = cloneEntityConfig(source.config)
	if source.attack != nil {
		attack := *source.attack
		attack.hitTargets = make(
			map[string]attackHitRuntime,
			len(source.attack.hitTargets),
		)
		for id, record := range source.attack.hitTargets {
			attack.hitTargets[id] = record
		}
		result.attack = &attack
	}
	result.abilityCooldowns = cloneCooldowns(source.abilityCooldowns)
	result.statuses = cloneStatuses(source.statuses)
	return &result
}

func cloneCooldowns(source map[string]int) map[string]int {
	result := make(map[string]int, len(source))
	for id, ticks := range source {
		result[id] = ticks
	}
	return result
}

func cloneStatuses(source map[string]*statusRuntime) map[string]*statusRuntime {
	result := make(map[string]*statusRuntime, len(source))
	for id, status := range source {
		copy := *status
		result[id] = &copy
	}
	return result
}

func (s *Simulation) cloneQuestRuntime() map[string]questRuntime {
	result := make(map[string]questRuntime, len(s.quests))
	for id, quest := range s.quests {
		result[id] = *quest
	}
	return result
}

func (s *Simulation) restoreQuestRuntime(state map[string]questRuntime) {
	for id, saved := range state {
		*s.quests[id] = saved
	}
}

func sortedCommandIDs(commands map[string]EntityInput) []string {
	ids := make([]string, 0, len(commands))
	for id := range commands {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	return ids
}

func cloneEvents(events []Event) []Event {
	return append([]Event(nil), events...)
}

func makeBurst(direction Vec, distance Coord, duration int) burstRuntime {
	direction = normalize(direction)
	return burstRuntime{
		totalX:   direction.X * distance / UnitsPerPixel,
		totalY:   direction.Y * distance / UnitsPerPixel,
		duration: duration,
	}
}

func directionBetween(source, target Vec) Vec {
	return normalize(Vec{X: target.X - source.X, Y: target.Y - source.Y})
}

func normalize(value Vec) Vec {
	if value == (Vec{}) {
		return Vec{}
	}
	const normalizationLimit Coord = 1 << 20
	maximum := maxCoord(absCoord(value.X), absCoord(value.Y))
	divisor := Coord(1)
	if maximum > normalizationLimit {
		divisor = (maximum + normalizationLimit - 1) / normalizationLimit
	}
	reduced := Vec{X: value.X / divisor, Y: value.Y / divisor}
	scaledSquared := uint64(squaredMagnitude(reduced)) *
		uint64(UnitsPerPixel) * uint64(UnitsPerPixel)
	scaledMagnitude := integerSqrt(scaledSquared)
	if scaledMagnitude == 0 {
		return Vec{}
	}
	return Vec{
		X: reduced.X * UnitsPerPixel * UnitsPerPixel /
			Coord(scaledMagnitude),
		Y: reduced.Y * UnitsPerPixel * UnitsPerPixel /
			Coord(scaledMagnitude),
	}
}

func withinArc(facing, delta Vec, degrees int) bool {
	if delta == (Vec{}) || degrees >= 360 {
		return true
	}
	facing = normalize(facing)
	direction := normalize(delta)
	dot := facing.X*direction.X + facing.Y*direction.Y
	threshold := Coord(math.Round(
		math.Cos(float64(degrees)*math.Pi/360) *
			float64(UnitsPerPixel),
	))
	return dot >= threshold*UnitsPerPixel
}

func squaredMagnitude(value Vec) int64 {
	return int64(value.X)*int64(value.X) +
		int64(value.Y)*int64(value.Y)
}

func squaredDistance(left, right Vec) int64 {
	return squaredMagnitude(Vec{X: right.X - left.X, Y: right.Y - left.Y})
}

func integerSqrt(value uint64) uint64 {
	if value < 2 {
		return value
	}
	x := value
	y := (x + 1) / 2
	for y < x {
		x = y
		y = (x + value/x) / 2
	}
	return x
}

func clampAxis(value int8) int8 {
	if value < 0 {
		return -1
	}
	if value > 0 {
		return 1
	}
	return 0
}

func approachCoord(current, target, delta Coord) Coord {
	if delta <= 0 || current == target {
		return current
	}
	if current < target {
		return minCoord(current+delta, target)
	}
	return maxCoord(current-delta, target)
}

func countdown(value int) int {
	if value > 0 {
		return value - 1
	}
	return 0
}

func minInt(left, right int) int {
	if left < right {
		return left
	}
	return right
}

func maxInt(left, right int) int {
	if left > right {
		return left
	}
	return right
}

func maxCoord(left, right Coord) Coord {
	if left > right {
		return left
	}
	return right
}

func minCoord(left, right Coord) Coord {
	if left < right {
		return left
	}
	return right
}

func absCoord(value Coord) Coord {
	if value < 0 {
		return -value
	}
	return value
}

func validTickCount(values ...int) bool {
	for _, value := range values {
		if value < 0 || value > MaxTickCount {
			return false
		}
	}
	return true
}

func validCoord(value Coord) bool {
	return value >= -maxAbsCoord && value <= maxAbsCoord
}

func entityRect(position Vec, body Body) Rect {
	return Rect{
		MinX: position.X - body.HalfWidth,
		MinY: position.Y - body.HalfHeight,
		MaxX: position.X + body.HalfWidth,
		MaxY: position.Y + body.HalfHeight,
	}
}

func overlaps(left, right Rect) bool {
	return left.MinX < right.MaxX && left.MaxX > right.MinX &&
		left.MinY < right.MaxY && left.MaxY > right.MinY
}

func containsRect(outer, inner Rect) bool {
	return inner.MinX >= outer.MinX && inner.MinY >= outer.MinY &&
		inner.MaxX <= outer.MaxX && inner.MaxY <= outer.MaxY
}

func clampEntityX(value Coord, body Body, bounds Rect) Coord {
	return clampCoord(
		value,
		bounds.MinX+body.HalfWidth,
		bounds.MaxX-body.HalfWidth,
	)
}

func clampEntityY(value Coord, body Body, bounds Rect) Coord {
	return clampCoord(
		value,
		bounds.MinY+body.HalfHeight,
		bounds.MaxY-body.HalfHeight,
	)
}

func clampCoord(value, minimum, maximum Coord) Coord {
	if minimum > maximum {
		return minimum + (maximum-minimum)/2
	}
	if value < minimum {
		return minimum
	}
	if value > maximum {
		return maximum
	}
	return value
}

func clampCamera(center Vec, bounds Rect, config CameraConfig) Vec {
	halfWidth := config.ViewportWidth / 2
	halfHeight := config.ViewportHeight / 2
	minimumX, maximumX := bounds.MinX+halfWidth, bounds.MaxX-halfWidth
	minimumY, maximumY := bounds.MinY+halfHeight, bounds.MaxY-halfHeight
	if minimumX > maximumX {
		center.X = bounds.MinX + (bounds.MaxX-bounds.MinX)/2
	} else {
		center.X = clampCoord(center.X, minimumX, maximumX)
	}
	if minimumY > maximumY {
		center.Y = bounds.MinY + (bounds.MaxY-bounds.MinY)/2
	} else {
		center.Y = clampCoord(center.Y, minimumY, maximumY)
	}
	return center
}

func deterministicShake(
	tick uint64,
	sequence uint64,
	salt uint64,
	amplitude Coord,
) Coord {
	if amplitude <= 0 {
		return 0
	}
	value := tick ^ (sequence * 0x9e3779b97f4a7c15) ^ salt
	value ^= value >> 30
	value *= 0xbf58476d1ce4e5b9
	value ^= value >> 27
	value *= 0x94d049bb133111eb
	value ^= value >> 31
	span := uint64(amplitude)*2 + 1
	return Coord(value%span) - amplitude
}
