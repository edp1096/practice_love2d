package sim

import (
	"encoding/json"
	"reflect"
	"testing"
)

func TestNewDemoExposesDetachedSortedModels(t *testing.T) {
	simulation := NewDemo()
	snapshot := simulation.Snapshot()
	if snapshot.Tick != 0 || snapshot.WorldTick != 0 {
		t.Fatalf("unexpected initial clocks: %+v", snapshot)
	}
	wantIDs := []string{"actor.guide", "actor.hero", "actor.slime"}
	if len(snapshot.Entities) != len(wantIDs) {
		t.Fatalf("got %d entities, want %d", len(snapshot.Entities), len(wantIDs))
	}
	for index, want := range wantIDs {
		if snapshot.Entities[index].ID != want {
			t.Fatalf("entity %d ID = %q, want %q", index, snapshot.Entities[index].ID, want)
		}
	}
	if snapshot.Camera.ViewportWidth != Pixels(960) ||
		snapshot.Camera.ViewportHeight != Pixels(540) {
		t.Fatalf("unexpected demo viewport: %+v", snapshot.Camera)
	}

	snapshot.Entities[0].Position.X = -999
	snapshot.Quests[0].Progress = 999
	frame := simulation.RenderFrame()
	frame.Walls[0].Rect.MinX = -999
	frame.Actors[0].Position.X = -999
	frame.Quests[0].Progress = 999

	again := simulation.Snapshot()
	if again.Entities[0].Position.X == -999 || again.Quests[0].Progress == 999 {
		t.Fatal("Snapshot aliases mutable simulation state")
	}
	againFrame := simulation.RenderFrame()
	if againFrame.Walls[0].Rect.MinX == -999 ||
		againFrame.Actors[0].Position.X == -999 ||
		againFrame.Quests[0].Progress == 999 {
		t.Fatal("RenderFrame aliases mutable simulation state")
	}
}

func TestMovementSlidesAndStopsAtStageWalls(t *testing.T) {
	config := baseConfig()
	config.Entities = config.Entities[:1]
	config.Entities[0].MovePerTick = Pixels(10)
	config.Walls = []Wall{{
		ID: "barrier",
		Rect: Rect{
			MinX: Pixels(70),
			MinY: Pixels(20),
			MaxX: Pixels(80),
			MaxY: Pixels(120),
		},
	}}
	simulation := mustNew(t, config)

	simulation.Tick(Input{MoveX: 1})
	if got := entityByID(t, simulation.Snapshot(), "hero").Position.X; got != Pixels(60) {
		t.Fatalf("first movement X = %v, want %v", got, Pixels(60))
	}
	simulation.Tick(Input{MoveX: 1})
	if got := entityByID(t, simulation.Snapshot(), "hero").Position.X; got != Pixels(65) {
		t.Fatalf("wall-clamped X = %v, want %v", got, Pixels(65))
	}
	simulation.Tick(Input{MoveX: 1, MoveY: 1})
	got := entityByID(t, simulation.Snapshot(), "hero")
	if got.Position.X != Pixels(65) || got.Position.Y <= Pixels(50) {
		t.Fatalf("wall sliding failed: position=%+v", got.Position)
	}
}

func TestMovementNormalizationAndSweptCollisionPreventDiagonalBoostAndTunneling(
	t *testing.T,
) {
	config := baseConfig()
	config.Entities = config.Entities[:1]
	config.Entities[0].MovePerTick = Pixels(100)
	config.Walls = []Wall{{
		ID: "thin",
		Rect: Rect{
			MinX: Pixels(70),
			MinY: Pixels(20),
			MaxX: Pixels(71),
			MaxY: Pixels(120),
		},
	}}
	simulation := mustNew(t, config)
	simulation.Tick(Input{MoveX: 1})
	if got := entityByID(t, simulation.Snapshot(), "hero").Position.X; got != Pixels(65) {
		t.Fatalf("large movement tunneled through a thin wall: X=%v", got)
	}

	config.Walls = nil
	config.Entities[0].MovePerTick = Pixels(10)
	simulation = mustNew(t, config)
	simulation.Tick(Input{MoveX: 1, MoveY: 1})
	position := entityByID(t, simulation.Snapshot(), "hero").Position
	delta := Vec{X: position.X - Pixels(50), Y: position.Y - Pixels(50)}
	if squaredMagnitude(delta) > int64(Pixels(10))*int64(Pixels(10)) {
		t.Fatalf("diagonal movement exceeded configured speed: delta=%+v", delta)
	}
	if delta.X == 0 || delta.Y == 0 {
		t.Fatalf("diagonal input lost an axis: delta=%+v", delta)
	}
}

func TestSetWallUsesStableIDAndCurrentEntityPositions(t *testing.T) {
	t.Parallel()
	config := baseConfig()
	config.Walls = []Wall{{
		ID: "editable",
		Rect: Rect{
			MinX: Pixels(200),
			MinY: Pixels(20),
			MaxX: Pixels(210),
			MaxY: Pixels(120),
		},
	}}
	simulation := mustNew(t, config)
	for range 3 {
		simulation.Tick(Input{MoveX: 1})
	}
	replacement := Rect{
		MinX: Pixels(45),
		MinY: Pixels(20),
		MaxX: Pixels(55),
		MaxY: Pixels(120),
	}
	if err := simulation.SetWall("editable", replacement); err != nil {
		t.Fatalf("wall over the vacated authored spawn was rejected: %v", err)
	}
	frame := simulation.RenderFrame()
	if len(frame.Walls) != 1 ||
		frame.Walls[0].ID != "editable" ||
		frame.Walls[0].Rect != replacement {
		t.Fatalf("edited wall lost identity or geometry: %#v", frame.Walls)
	}
	before := frame.Walls[0]
	if err := simulation.SetWall("editable", Rect{
		MinX: Pixels(60),
		MinY: Pixels(20),
		MaxX: Pixels(70),
		MaxY: Pixels(120),
	}); err == nil {
		t.Fatal("wall overlapping the current entity position was accepted")
	}
	if after := simulation.RenderFrame().Walls[0]; !reflect.DeepEqual(after, before) {
		t.Fatalf("rejected wall edit was not transactional: %#v", after)
	}
}

func TestAttackPhasesLockMovementAndApplyTransactionalImpactOnce(t *testing.T) {
	config := baseConfig()
	config.Entities[0].Ability = &AbilityConfig{
		ID:               "slash",
		WindupTicks:      2,
		ActiveTicks:      2,
		RecoveryTicks:    2,
		CooldownTicks:    8,
		LockMovement:     true,
		Reach:            Pixels(20),
		ArcDegrees:       120,
		Damage:           10,
		StaggerTicks:     3,
		Knockback:        Pixels(12),
		KnockbackTicks:   3,
		HitstopTicks:     2,
		CameraShake:      Pixels(4),
		CameraShakeTicks: 5,
	}
	simulation := mustNew(t, config)

	events := simulation.Tick(Input{MoveX: 1, Attack: true})
	requireEvent(t, events, EventAttackStarted)
	first := simulation.Snapshot()
	hero := entityByID(t, first, "hero")
	if hero.Position.X != Pixels(50) || hero.Attack.Phase != AttackWindup ||
		hero.Attack.RemainingTicks != 2 {
		t.Fatalf("unexpected attack start: %+v", hero)
	}
	if enemy := entityByID(t, first, "enemy"); enemy.Health != 100 {
		t.Fatalf("windup dealt early damage: %+v", enemy)
	}

	simulation.Tick(Input{MoveX: 1})
	second := entityByID(t, simulation.Snapshot(), "hero")
	if second.Position.X != Pixels(50) || second.Attack.RemainingTicks != 1 {
		t.Fatalf("windup did not remain movement-locked: %+v", second)
	}

	events = simulation.Tick(Input{MoveX: 1})
	requireEvent(t, events, EventAttackActive)
	requireEvent(t, events, EventDamageApplied)
	requireEvent(t, events, EventActorStaggered)
	requireEvent(t, events, EventKnockbackStarted)
	requireEvent(t, events, EventHitstopStarted)
	impact := simulation.Snapshot()
	enemy := entityByID(t, impact, "enemy")
	if enemy.Health != 90 || enemy.StaggerTicks != 3 ||
		enemy.KnockbackTicks != 3 {
		t.Fatalf("impact state = %+v", enemy)
	}
	if impact.HitstopTicks != 2 || impact.Camera.ShakeTicks != 5 {
		t.Fatalf("impact presentation state = %+v", impact)
	}

	worldTick := impact.WorldTick
	shakeTicks := impact.Camera.ShakeTicks
	simulation.Tick(Input{})
	frozen := simulation.Snapshot()
	if frozen.WorldTick != worldTick || frozen.HitstopTicks != 1 ||
		frozen.Camera.ShakeTicks != shakeTicks-1 {
		t.Fatalf("hitstop/camera raw time mismatch: before=%+v after=%+v", impact, frozen)
	}
	simulation.Tick(Input{})
	if got := simulation.Snapshot().WorldTick; got != worldTick {
		t.Fatalf("second hitstop tick advanced world: got %d, want %d", got, worldTick)
	}
	simulation.Tick(Input{})
	after := simulation.Snapshot()
	enemy = entityByID(t, after, "enemy")
	if enemy.Health != 90 {
		t.Fatalf("multi-tick active attack hit twice: health=%d", enemy.Health)
	}
	if enemy.Position.X != Pixels(74) {
		t.Fatalf("first knockback step X=%v, want %v", enemy.Position.X, Pixels(74))
	}
}

func TestRenderFramePublishesContinuousAttackAnimationTime(t *testing.T) {
	t.Parallel()

	config := baseConfig()
	config.Entities = config.Entities[:1]
	config.Entities[0].Ability = &AbilityConfig{
		ID:            "animation",
		WindupTicks:   2,
		ActiveTicks:   2,
		RecoveryTicks: 2,
		CooldownTicks: 8,
		Reach:         Pixels(1),
		ArcDegrees:    90,
		Damage:        1,
	}
	simulation := mustNew(t, config)

	for tick, want := range []int{0, 1, 2, 3, 4, 5} {
		input := Input{}
		if tick == 0 {
			input.Attack = true
		}
		simulation.Tick(input)
		actor := simulation.RenderFrame().Actors[0]
		if actor.Attack == AttackIdle || actor.AttackTicks != want {
			t.Fatalf(
				"step %d attack=%q animation ticks=%d, want active/%d",
				tick,
				actor.Attack,
				actor.AttackTicks,
				want,
			)
		}
	}
	simulation.Tick(Input{})
	actor := simulation.RenderFrame().Actors[0]
	if actor.Attack != AttackIdle || actor.AttackTicks != 0 {
		t.Fatalf("finished attack presentation = %#v", actor)
	}
}

func TestAbilityIDUsesIndependentCooldownAndStableEvents(t *testing.T) {
	config := baseConfig()
	config.Entities[0].Combat = &CombatConfig{
		PrimaryAbilityID: "slash",
		Abilities: []AbilityConfig{
			{
				ID:            "bolt",
				ActiveTicks:   1,
				CooldownTicks: 9,
				Reach:         Pixels(30),
				ArcDegrees:    180,
				Damage:        2,
			},
			{
				ID:            "slash",
				ActiveTicks:   1,
				CooldownTicks: 4,
				Reach:         Pixels(30),
				ArcDegrees:    180,
				Damage:        1,
			},
		},
		Bindings: []AbilityBinding{
			{Input: "attack", AbilityID: "slash"},
			{Input: "special", AbilityID: "bolt"},
		},
	}
	simulation := mustNew(t, config)

	events := simulation.Tick(Input{AbilityID: "bolt"})
	started := requireEvent(t, events, EventAttackStarted)
	if started.AbilityID != "bolt" {
		t.Fatalf("started ability = %q, want bolt", started.AbilityID)
	}
	boltHit := requireEvent(t, events, EventDamageApplied)
	if boltHit.AbilityID != "bolt" || boltHit.Amount != 2 {
		t.Fatalf("bolt hit = %#v", boltHit)
	}
	simulation.Tick(Input{})
	events = simulation.Tick(Input{Attack: true})
	started = requireEvent(t, events, EventAttackStarted)
	if started.AbilityID != "slash" {
		t.Fatalf("primary ability = %q, want slash", started.AbilityID)
	}
	hero := entityByID(t, simulation.Snapshot(), "hero")
	if len(hero.AbilityCooldowns) != 2 ||
		hero.AbilityCooldowns[0].AbilityID != "bolt" ||
		hero.AbilityCooldowns[1].AbilityID != "slash" {
		t.Fatalf("independent cooldowns = %#v", hero.AbilityCooldowns)
	}
}

func TestMultiHitHonorsRepeatIntervalAndMaximumPerTarget(t *testing.T) {
	config := baseConfig()
	config.Entities[1].Reaction.HitInvulnerabilityTicks = 0
	config.Entities[0].Combat = &CombatConfig{
		PrimaryAbilityID: "whirlwind",
		Abilities: []AbilityConfig{{
			ID:                  "whirlwind",
			ActiveTicks:         7,
			Reach:               Pixels(30),
			ArcDegrees:          360,
			Damage:              6,
			MaxHits:             3,
			RepeatIntervalTicks: 2,
		}},
		Bindings: []AbilityBinding{{
			Input:     "technique",
			AbilityID: "whirlwind",
		}},
	}
	simulation := mustNew(t, config)

	hitTicks := make([]uint64, 0, 3)
	for tick := 0; tick < 8; tick++ {
		input := Input{}
		if tick == 0 {
			input.AbilityID = "whirlwind"
		}
		for _, event := range simulation.Tick(input) {
			if event.Type == EventDamageApplied {
				hitTicks = append(hitTicks, event.Tick)
			}
		}
	}
	if want := []uint64{1, 3, 5}; !reflect.DeepEqual(hitTicks, want) {
		t.Fatalf("multi-hit ticks = %v, want %v", hitTicks, want)
	}
	enemy := entityByID(t, simulation.Snapshot(), "enemy")
	if enemy.Health != 82 {
		t.Fatalf("multi-hit health = %d, want 82", enemy.Health)
	}
}

func TestPerfectParryChecksFacingAndStaggersAttacker(t *testing.T) {
	config := parryConfig()
	simulation := mustNew(t, config)
	events := simulation.Tick(Input{
		Parry: true,
		Commands: []EntityInput{{
			EntityID: "enemy",
			Attack:   true,
		}},
	})
	parried := requireEvent(t, events, EventAttackParried)
	if !parried.Perfect || !parried.Blocked || parried.Amount != 10 {
		t.Fatalf("unexpected parry event: %+v", parried)
	}
	snapshot := simulation.Snapshot()
	hero := entityByID(t, snapshot, "hero")
	enemy := entityByID(t, snapshot, "enemy")
	if hero.Health != hero.MaxHealth || !hero.LastParryPerfect {
		t.Fatalf("perfect parry did not protect hero: %+v", hero)
	}
	if enemy.StaggerTicks != 6 || enemy.Attack.Phase != AttackIdle {
		t.Fatalf("perfect parry did not interrupt/stagger attacker: %+v", enemy)
	}
	if snapshot.HitstopTicks != 2 {
		t.Fatalf("perfect parry hitstop = %d, want 2", snapshot.HitstopTicks)
	}
}

func TestParryBehindFacingArcIsConsumedAndDamageApplies(t *testing.T) {
	config := parryConfig()
	config.Entities[0].Position.X = Pixels(50)
	config.Entities[0].Facing = Vec{X: UnitsPerPixel}
	config.Entities[1].Position.X = Pixels(30)
	config.Entities[1].Facing = Vec{X: UnitsPerPixel}
	config.Entities[1].Ability.ArcDegrees = 360
	simulation := mustNew(t, config)

	events := simulation.Tick(Input{
		Parry: true,
		Commands: []EntityInput{{
			EntityID: "enemy",
			Attack:   true,
		}},
	})
	if hasEvent(events, EventAttackParried) {
		t.Fatalf("rear attack was incorrectly parried: %+v", events)
	}
	requireEvent(t, events, EventDamageApplied)
	hero := entityByID(t, simulation.Snapshot(), "hero")
	if hero.Health != 90 || hero.ParryTicks != 0 ||
		hero.ParryCooldownTicks != 5 {
		t.Fatalf("rear hit/parry consumption state = %+v", hero)
	}
}

func TestParryOutsidePerfectWindowStillBlocksWithNormalStagger(t *testing.T) {
	config := parryConfig()
	simulation := mustNew(t, config)
	simulation.Tick(Input{Parry: true})
	simulation.Tick(Input{})
	simulation.Tick(Input{})
	events := simulation.Tick(Input{Commands: []EntityInput{{
		EntityID: "enemy",
		Attack:   true,
	}}})
	parried := requireEvent(t, events, EventAttackParried)
	if parried.Perfect || !parried.Blocked {
		t.Fatalf("late parry result = %+v", parried)
	}
	snapshot := simulation.Snapshot()
	if enemy := entityByID(t, snapshot, "enemy"); enemy.StaggerTicks != 3 {
		t.Fatalf("normal parry stagger = %d, want 3", enemy.StaggerTicks)
	}
	if snapshot.HitstopTicks != 1 {
		t.Fatalf("normal parry hitstop = %d, want 1", snapshot.HitstopTicks)
	}
}

func TestDodgeMovesAndBlocksDamageThroughWallCollision(t *testing.T) {
	config := baseConfig()
	config.Entities[0].Dodge = &DodgeConfig{
		DurationTicks:        3,
		Distance:             Pixels(30),
		InvulnerabilityTicks: 3,
		CooldownTicks:        5,
	}
	config.Entities[1].Ability = immediateEnemyAbility()
	config.Walls = []Wall{{
		ID: "dodge-stop",
		Rect: Rect{
			MinX: Pixels(75),
			MinY: Pixels(20),
			MaxX: Pixels(85),
			MaxY: Pixels(120),
		},
	}}
	simulation := mustNew(t, config)

	events := simulation.Tick(Input{
		MoveX: 1,
		Dodge: true,
		Commands: []EntityInput{{
			EntityID: "enemy",
			Attack:   true,
		}},
	})
	requireEvent(t, events, EventDodgeStarted)
	blocked := requireEvent(t, events, EventDamageBlocked)
	if blocked.Reason != "invulnerable" {
		t.Fatalf("damage block reason = %q", blocked.Reason)
	}
	if hero := entityByID(t, simulation.Snapshot(), "hero"); hero.Health != 100 {
		t.Fatalf("dodge did not block damage: %+v", hero)
	}
	simulation.Tick(Input{})
	simulation.Tick(Input{})
	hero := entityByID(t, simulation.Snapshot(), "hero")
	if hero.Position.X != Pixels(70) {
		t.Fatalf("dodge did not share wall collision, X=%v want %v", hero.Position.X, Pixels(70))
	}
	if hero.DodgeTicks != 0 {
		t.Fatalf("dodge did not finish: %+v", hero)
	}
}

func TestDialogueStartsQuestAndKillCompletesIt(t *testing.T) {
	simulation := NewDemo()
	events := simulation.Tick(Input{Interact: true})
	requireEvent(t, events, EventQuestStarted)
	requireEvent(t, events, EventDialogueStarted)
	snapshot := simulation.Snapshot()
	if !snapshot.Dialogue.Active || snapshot.Dialogue.ID != "dialogue.guide" {
		t.Fatalf("dialogue did not open: %+v", snapshot.Dialogue)
	}
	if snapshot.Quests[0].Status != QuestActive {
		t.Fatalf("quest did not start: %+v", snapshot.Quests[0])
	}

	state := simulation.SaveSession()
	for index := range state.Entities {
		if state.Entities[index].ID == "actor.slime" {
			state.Entities[index].Health = 34
		}
	}
	if err := simulation.LoadSession(state); err != nil {
		t.Fatalf("prepare one-hit quest state: %v", err)
	}
	events = simulation.Tick(Input{Attack: true})
	requireEvent(t, events, EventActorKilled)
	requireEvent(t, events, EventQuestProgress)
	requireEvent(t, events, EventQuestCompleted)
	snapshot = simulation.Snapshot()
	if got := snapshot.Quests[0]; got.Status != QuestCompleted ||
		got.Progress != got.Required {
		t.Fatalf("quest did not complete: %+v", got)
	}
}

func TestSessionRoundTripAndRejectedLoadAreTransactional(t *testing.T) {
	source := NewDemo()
	source.Tick(Input{Interact: true})
	source.Tick(Input{Dodge: true, MoveY: -1})
	saved := source.SaveSession()

	encoded, err := json.Marshal(saved)
	if err != nil {
		t.Fatalf("marshal session: %v", err)
	}
	var decoded SessionState
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatalf("unmarshal session: %v", err)
	}
	target := NewDemo()
	if err := target.LoadSession(decoded); err != nil {
		t.Fatalf("load valid session: %v", err)
	}
	if got := target.SaveSession(); !reflect.DeepEqual(got, saved) {
		t.Fatalf("session round trip differs:\n got: %#v\nwant: %#v", got, saved)
	}

	before := target.SaveSession()
	corrupt := deepCopySession(t, before)
	corrupt.Entities[0].Health = -1
	if err := target.LoadSession(corrupt); err == nil {
		t.Fatal("invalid session load unexpectedly succeeded")
	}
	if after := target.SaveSession(); !reflect.DeepEqual(after, before) {
		t.Fatalf("rejected load mutated simulation:\n before=%#v\n after=%#v", before, after)
	}

	detached := target.SaveSession()
	detached.Entities[0].Position.X = -999
	detached.Quests[0].Progress = 999
	if reflect.DeepEqual(detached, target.SaveSession()) {
		t.Fatal("SaveSession returned aliased data")
	}
}

func TestSessionRoundTripPreservesConcurrentStaggerAndKnockback(t *testing.T) {
	config := baseConfig()
	config.Entities[0].Ability = &AbilityConfig{
		ID:             "impact",
		ActiveTicks:    1,
		Reach:          Pixels(20),
		ArcDegrees:     180,
		Damage:         1,
		StaggerTicks:   4,
		Knockback:      Pixels(9),
		KnockbackTicks: 3,
	}
	source := mustNew(t, config)
	source.Tick(Input{Attack: true})
	saved := source.SaveSession()
	target := mustNew(t, config)
	if err := target.LoadSession(saved); err != nil {
		t.Fatalf("load simultaneous reaction state: %v", err)
	}
	if got := target.SaveSession(); !reflect.DeepEqual(got, saved) {
		t.Fatalf("reaction state round trip differs:\n got=%#v\nwant=%#v", got, saved)
	}
}

func TestCameraShakeIsBoundedAndAdvancesDuringHitstop(t *testing.T) {
	config := baseConfig()
	config.Entities[0].Ability = &AbilityConfig{
		ID:               "impact",
		ActiveTicks:      1,
		RecoveryTicks:    1,
		Reach:            Pixels(20),
		ArcDegrees:       180,
		Damage:           1,
		HitstopTicks:     3,
		CameraShake:      Pixels(12),
		CameraShakeTicks: 5,
	}
	simulation := mustNew(t, config)
	simulation.Tick(Input{Attack: true})
	initial := simulation.Snapshot()
	if initial.HitstopTicks != 3 || initial.Camera.ShakeTicks != 5 {
		t.Fatalf("impact did not schedule freeze/shake: %+v", initial)
	}
	worldTick := initial.WorldTick
	previousShake := initial.Camera.ShakeTicks
	for index := 0; index < 3; index++ {
		simulation.Tick(Input{})
		snapshot := simulation.Snapshot()
		if snapshot.WorldTick != worldTick {
			t.Fatalf("hitstop frame %d advanced world tick", index)
		}
		if snapshot.Camera.ShakeTicks != previousShake-1 {
			t.Fatalf(
				"hitstop frame %d shake=%d want=%d",
				index,
				snapshot.Camera.ShakeTicks,
				previousShake-1,
			)
		}
		previousShake = snapshot.Camera.ShakeTicks
		assertCameraBounded(t, snapshot.Camera, config.StageBounds)
	}
}

func TestDeterministicReplayAndStableCommandOrdering(t *testing.T) {
	left := NewDemo()
	right := NewDemo()
	for tick := 0; tick < 240; tick++ {
		input := scriptedInput(tick)
		leftEvents := left.Tick(input)
		rightEvents := right.Tick(input)
		if !reflect.DeepEqual(leftEvents, rightEvents) {
			t.Fatalf("events diverged at tick %d:\nleft=%#v\nright=%#v", tick, leftEvents, rightEvents)
		}
		if !reflect.DeepEqual(left.Snapshot(), right.Snapshot()) {
			t.Fatalf("snapshots diverged at tick %d", tick)
		}
		leftJSON, _ := json.Marshal(left.SaveSession())
		rightJSON, _ := json.Marshal(right.SaveSession())
		if string(leftJSON) != string(rightJSON) {
			t.Fatalf("save serialization diverged at tick %d", tick)
		}
	}

	first := mustNew(t, simultaneousConfig())
	second := mustNew(t, simultaneousConfig())
	commands := []EntityInput{
		{EntityID: "enemy.b", Attack: true},
		{EntityID: "enemy.a", Attack: true},
	}
	reversed := []EntityInput{commands[1], commands[0]}
	first.Tick(Input{Commands: commands})
	second.Tick(Input{Commands: reversed})
	if !reflect.DeepEqual(first.Snapshot(), second.Snapshot()) {
		t.Fatal("command slice order changed deterministic resolution")
	}
}

func TestConfigValidationAndDeepCopy(t *testing.T) {
	config := baseConfig()
	simulation := mustNew(t, config)
	config.Entities[0].Position.X = -999
	config.Walls = append(config.Walls, Wall{ID: "mutated"})
	if got := entityByID(t, simulation.Snapshot(), "hero").Position.X; got != Pixels(50) {
		t.Fatalf("New retained caller config aliases: X=%v", got)
	}

	duplicateWall := baseConfig()
	duplicateWall.Walls = []Wall{
		{
			ID: "same",
			Rect: Rect{
				MinX: Pixels(100),
				MinY: Pixels(10),
				MaxX: Pixels(110),
				MaxY: Pixels(20),
			},
		},
		{
			ID: "same",
			Rect: Rect{
				MinX: Pixels(120),
				MinY: Pixels(10),
				MaxX: Pixels(130),
				MaxY: Pixels(20),
			},
		},
	}
	if _, err := New(duplicateWall); err == nil {
		t.Fatal("duplicate wall ID was accepted")
	}

	invalid := baseConfig()
	invalid.Entities[0].Parry = &ParryConfig{
		WindowTicks:        2,
		PerfectWindowTicks: 3,
		ArcDegrees:         90,
	}
	if _, err := New(invalid); err == nil {
		t.Fatal("invalid perfect-parry window was accepted")
	}
}

func baseConfig() Config {
	return Config{
		StageBounds: Rect{
			MinX: 0,
			MinY: 0,
			MaxX: Pixels(300),
			MaxY: Pixels(200),
		},
		Entities: []EntityConfig{
			{
				ID:          "hero",
				Kind:        "hero",
				Name:        "Hero",
				Team:        "player",
				Position:    Vec{X: Pixels(50), Y: Pixels(50)},
				Body:        Body{HalfWidth: Pixels(5), HalfHeight: Pixels(5), Solid: true},
				MaxHealth:   100,
				MovePerTick: Pixels(5),
				Facing:      Vec{X: UnitsPerPixel},
				Controlled:  true,
				Reaction: ReactionConfig{
					HitInvulnerabilityTicks: 3,
					FlashTicks:              2,
				},
			},
			{
				ID:        "enemy",
				Kind:      "slime",
				Name:      "Enemy",
				Team:      "enemy",
				Position:  Vec{X: Pixels(70), Y: Pixels(50)},
				Body:      Body{HalfWidth: Pixels(5), HalfHeight: Pixels(5), Solid: true},
				MaxHealth: 100,
				Facing:    Vec{X: -UnitsPerPixel},
				Reaction: ReactionConfig{
					HitInvulnerabilityTicks: 1,
					FlashTicks:              1,
				},
			},
		},
		Camera: CameraConfig{
			TargetEntityID: "hero",
			ViewportWidth:  Pixels(100),
			ViewportHeight: Pixels(100),
		},
		InteractionRange: Pixels(30),
	}
}

func parryConfig() Config {
	config := baseConfig()
	config.Entities[0].Parry = &ParryConfig{
		WindowTicks:          5,
		PerfectWindowTicks:   2,
		CooldownTicks:        5,
		SuccessCooldownTicks: 2,
		ArcDegrees:           90,
		StaggerTicks:         3,
		PerfectStaggerTicks:  6,
		HitstopTicks:         1,
		PerfectHitstopTicks:  2,
		CameraShake:          Pixels(2),
		CameraShakeTicks:     3,
	}
	config.Entities[1].Ability = immediateEnemyAbility()
	return config
}

func immediateEnemyAbility() *AbilityConfig {
	return &AbilityConfig{
		ID:             "bump",
		ActiveTicks:    2,
		RecoveryTicks:  1,
		CooldownTicks:  5,
		LockMovement:   true,
		Reach:          Pixels(20),
		ArcDegrees:     180,
		Damage:         10,
		StaggerTicks:   2,
		Knockback:      Pixels(3),
		KnockbackTicks: 1,
		HitstopTicks:   1,
	}
}

func simultaneousConfig() Config {
	config := baseConfig()
	config.Entities[0].Position = Vec{X: Pixels(150), Y: Pixels(100)}
	config.Entities[1] = EntityConfig{
		ID:        "enemy.a",
		Kind:      "slime",
		Name:      "A",
		Team:      "enemy",
		Position:  Vec{X: Pixels(100), Y: Pixels(100)},
		Body:      Body{HalfWidth: Pixels(5), HalfHeight: Pixels(5), Solid: true},
		MaxHealth: 100,
		Facing:    Vec{X: UnitsPerPixel},
		Ability:   immediateEnemyAbility(),
	}
	enemyB := config.Entities[1]
	enemyB.ID = "enemy.b"
	enemyB.Name = "B"
	enemyB.Position = Vec{X: Pixels(200), Y: Pixels(100)}
	enemyB.Facing = Vec{X: -UnitsPerPixel}
	config.Entities = append(config.Entities, enemyB)
	return config
}

func scriptedInput(tick int) Input {
	input := Input{}
	switch {
	case tick < 20:
		input.MoveX = 1
	case tick < 40:
		input.MoveY = 1
	case tick < 60:
		input.MoveX = -1
	default:
		input.MoveY = -1
	}
	if tick == 2 || tick == 90 || tick == 180 {
		input.Attack = true
	}
	if tick == 25 || tick == 130 {
		input.Dodge = true
	}
	if tick == 70 || tick == 160 {
		input.Parry = true
	}
	if tick == 5 || tick == 80 {
		input.Interact = true
	}
	if tick == 100 {
		input.Commands = []EntityInput{
			{EntityID: "missing", Attack: true},
			{EntityID: "actor.slime", Attack: true},
		}
	}
	return input
}

func mustNew(t *testing.T, config Config) *Simulation {
	t.Helper()
	simulation, err := New(config)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	return simulation
}

func entityByID(t *testing.T, snapshot Snapshot, id string) EntitySnapshot {
	t.Helper()
	for _, entity := range snapshot.Entities {
		if entity.ID == id {
			return entity
		}
	}
	t.Fatalf("entity %q missing from snapshot", id)
	return EntitySnapshot{}
}

func requireEvent(t *testing.T, events []Event, eventType EventType) Event {
	t.Helper()
	for _, event := range events {
		if event.Type == eventType {
			return event
		}
	}
	t.Fatalf("event %q missing from %#v", eventType, events)
	return Event{}
}

func hasEvent(events []Event, eventType EventType) bool {
	for _, event := range events {
		if event.Type == eventType {
			return true
		}
	}
	return false
}

func assertCameraBounded(t *testing.T, camera CameraSnapshot, bounds Rect) {
	t.Helper()
	halfWidth := camera.ViewportWidth / 2
	halfHeight := camera.ViewportHeight / 2
	if camera.Center.X < bounds.MinX+halfWidth ||
		camera.Center.X > bounds.MaxX-halfWidth ||
		camera.Center.Y < bounds.MinY+halfHeight ||
		camera.Center.Y > bounds.MaxY-halfHeight {
		t.Fatalf("camera escaped bounds: camera=%+v stage=%+v", camera, bounds)
	}
}

func deepCopySession(t *testing.T, state SessionState) SessionState {
	t.Helper()
	encoded, err := json.Marshal(state)
	if err != nil {
		t.Fatalf("marshal session copy: %v", err)
	}
	var result SessionState
	if err := json.Unmarshal(encoded, &result); err != nil {
		t.Fatalf("unmarshal session copy: %v", err)
	}
	return result
}
