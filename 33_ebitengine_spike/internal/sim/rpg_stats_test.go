package sim

import "testing"

func TestRPGStatsAdjustDirectDamageAtTheSharedImpactBoundary(t *testing.T) {
	config := baseConfig()
	config.Entities[0].Stats = &RPGStatsConfig{
		Attack:    7,
		MoveSpeed: UnitsPerPixel,
	}
	config.Entities[1].Stats = &RPGStatsConfig{
		Defense:   3,
		MoveSpeed: UnitsPerPixel,
	}
	config.Entities[0].Ability = &AbilityConfig{
		ID:            "slash",
		ActiveTicks:   1,
		RecoveryTicks: 1,
		CooldownTicks: 1,
		Reach:         Pixels(30),
		ArcDegrees:    180,
		Damage:        10,
	}
	simulation := mustNew(t, config)

	events := simulation.Tick(Input{Attack: true})
	damage := requireEvent(t, events, EventDamageApplied)
	target := entityByID(t, simulation.Snapshot(), "enemy")
	if damage.Amount != 14 || target.Health != 86 {
		t.Fatalf("stat damage event=%#v target=%#v", damage, target)
	}
	if target.Stats.Defense != 3 ||
		entityByID(t, simulation.Snapshot(), "hero").Stats.Attack != 7 {
		t.Fatalf("stats were not exposed in snapshot: %#v", simulation.Snapshot())
	}
}

func TestRPGStatsDoNotAdjustPeriodicDamage(t *testing.T) {
	config := baseConfig()
	config.Entities[0].Stats = &RPGStatsConfig{
		Attack:    99,
		MoveSpeed: UnitsPerPixel,
	}
	config.Entities[1].Stats = &RPGStatsConfig{
		Defense:   99,
		MoveSpeed: UnitsPerPixel,
	}
	simulation := mustNew(t, config)
	target := simulation.entities["enemy"]

	if err := simulation.applyImpact(
		"hero",
		simulation.entities["hero"].position,
		simulation.entities["hero"].facing,
		"enemy",
		target,
		"",
		ImpactConfig{Damage: 3},
		true,
	); err != nil {
		t.Fatal(err)
	}
	if target.health != 97 {
		t.Fatalf("periodic damage after RPG stats = %d, want 97", target.health)
	}
}

func TestRPGStatsApplyToProjectileDamageFromItsOwningActor(
	t *testing.T,
) {
	config := projectileConfig()
	config.Entities[0].Stats = &RPGStatsConfig{
		Attack:    7,
		MoveSpeed: UnitsPerPixel,
	}
	config.Entities[1].Stats = &RPGStatsConfig{
		Defense:   3,
		MoveSpeed: UnitsPerPixel,
	}
	simulation := mustNew(t, config)

	events := simulation.Tick(Input{AbilityID: "bolt"})
	damage := requireEvent(t, events, EventDamageApplied)
	enemy := entityByID(t, simulation.Snapshot(), "enemy")
	if damage.AbilityID != "bolt" ||
		damage.Amount != 22 ||
		enemy.Health != 78 {
		t.Fatalf("projectile stat damage=%#v enemy=%#v", damage, enemy)
	}
}

func TestRPGStatsApplyToEverySecondaryMultiHit(t *testing.T) {
	config := baseConfig()
	config.Entities[0].Stats = &RPGStatsConfig{
		Attack:    4,
		MoveSpeed: UnitsPerPixel,
	}
	config.Entities[1].Stats = &RPGStatsConfig{
		Defense:   1,
		MoveSpeed: UnitsPerPixel,
	}
	config.Entities[1].Reaction.HitInvulnerabilityTicks = 0
	config.Entities[0].Combat = &CombatConfig{
		PrimaryAbilityID: "slash",
		Abilities: []AbilityConfig{
			{
				ID:          "slash",
				ActiveTicks: 1,
				Reach:       Pixels(30),
				ArcDegrees:  180,
				Damage:      1,
			},
			{
				ID:                  "whirlwind",
				ActiveTicks:         7,
				Reach:               Pixels(30),
				ArcDegrees:          360,
				Damage:              6,
				MaxHits:             3,
				RepeatIntervalTicks: 2,
			},
		},
		Bindings: []AbilityBinding{
			{Input: "attack", AbilityID: "slash"},
			{Input: "technique", AbilityID: "whirlwind"},
		},
	}
	simulation := mustNew(t, config)

	hits := 0
	for tick := 0; tick < 8; tick++ {
		input := Input{}
		if tick == 0 {
			input.AbilityID = "whirlwind"
		}
		for _, event := range simulation.Tick(input) {
			if event.Type != EventDamageApplied {
				continue
			}
			hits++
			if event.AbilityID != "whirlwind" || event.Amount != 9 {
				t.Fatalf("secondary multi-hit event = %#v", event)
			}
		}
	}
	if enemy := entityByID(t, simulation.Snapshot(), "enemy"); hits != 3 ||
		enemy.Health != 73 {
		t.Fatalf("secondary hits=%d enemy=%#v", hits, enemy)
	}
}

func TestRPGMoveSpeedComposesBeforeStatusMultipliers(t *testing.T) {
	config := baseConfig()
	config.Entities[0].Stats = &RPGStatsConfig{
		MoveSpeed: UnitsPerPixel / 2,
	}
	config.Entities[0].Status = &StatusReceiverConfig{}
	config.Statuses = []StatusConfig{{
		ID:            "slow",
		DurationTicks: 60,
		Stacking:      StatusRefresh,
		MaxStacks:     1,
		MoveSpeed:     UnitsPerPixel / 2,
		DamageDealt:   UnitsPerPixel,
		DamageTaken:   UnitsPerPixel,
	}}
	simulation := mustNew(t, config)
	hero := simulation.entities["hero"]
	if err := simulation.applyStatus("hero", hero, "slow", 1); err != nil {
		t.Fatal(err)
	}
	start := hero.position.X

	simulation.Tick(Input{MoveX: -1})
	want := start - config.Entities[0].MovePerTick/4
	if hero.position.X != want {
		t.Fatalf("composed movement X = %d, want %d", hero.position.X, want)
	}
}

func TestRPGMoveSpeedAlsoControlsPlatformerMaximumSpeed(t *testing.T) {
	config := platformerConfig()
	config.Walls = nil
	config.Entities[0].Position = Vec{X: Pixels(50), Y: Pixels(50)}
	config.Entities[0].Stats = &RPGStatsConfig{
		MoveSpeed: UnitsPerPixel * 3 / 2,
	}
	simulation := mustNew(t, config)
	start := simulation.entities["hero"].position.X

	simulation.Tick(Input{MoveX: 1})
	simulation.Tick(Input{MoveX: 1})
	if moved := simulation.entities["hero"].position.X - start; moved !=
		Pixels(5)+Pixels(15)/2 {
		t.Fatalf("platformer stat movement = %d", moved)
	}
}

func TestRPGStatsValidationRejectsInvalidEffectiveValues(t *testing.T) {
	for _, stats := range []RPGStatsConfig{
		{Attack: -1, MoveSpeed: UnitsPerPixel},
		{Defense: -1, MoveSpeed: UnitsPerPixel},
		{MoveSpeed: -1},
		{MoveSpeed: maxAbsCoord + 1},
	} {
		config := baseConfig()
		copy := stats
		config.Entities[0].Stats = &copy
		if _, err := New(config); err == nil {
			t.Fatalf("invalid stats passed: %#v", stats)
		}
	}
}
