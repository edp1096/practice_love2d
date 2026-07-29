package sim

import (
	"reflect"
	"testing"
)

func TestProjectileSweepsTargetAppliesStatusAndPeriodicDamage(t *testing.T) {
	config := projectileConfig()
	simulation := mustNew(t, config)

	events := simulation.Tick(Input{AbilityID: "bolt"})
	for _, eventType := range []EventType{
		EventProjectileSpawned,
		EventDamageApplied,
		EventStatusApplied,
		EventProjectileHit,
	} {
		requireEvent(t, events, eventType)
	}
	snapshot := simulation.Snapshot()
	if len(snapshot.Projectiles) != 0 {
		t.Fatalf("non-piercing projectile remained: %#v", snapshot.Projectiles)
	}
	enemy := entityByID(t, snapshot, "enemy")
	if enemy.Health != 82 || len(enemy.Statuses) != 1 ||
		enemy.Statuses[0].ID != "burning" ||
		enemy.Statuses[0].Stacks != 1 {
		t.Fatalf("projectile impact = %#v", enemy)
	}

	var ticked Event
	for tick := 0; tick < 30; tick++ {
		for _, event := range simulation.Tick(Input{}) {
			if event.Type == EventStatusTicked {
				ticked = event
			}
		}
	}
	enemy = entityByID(t, simulation.Snapshot(), "enemy")
	if ticked.StatusID != "burning" || ticked.Amount != 3 ||
		enemy.Health != 79 {
		t.Fatalf("periodic result: event=%#v enemy=%#v", ticked, enemy)
	}
}

func TestProjectileOrdersTargetAndWallByContinuousImpactTime(t *testing.T) {
	t.Run("wall first", func(t *testing.T) {
		config := projectileConfig()
		config.Walls = []Wall{{
			ID: "barrier",
			Rect: Rect{
				MinX: Pixels(80),
				MinY: Pixels(20),
				MaxX: Pixels(84),
				MaxY: Pixels(80),
			},
		}}
		simulation := mustNew(t, config)
		events := simulation.Tick(Input{AbilityID: "bolt"})
		blocked := requireEvent(t, events, EventProjectileBlocked)
		if blocked.TargetID != "barrier" ||
			hasEvent(events, EventProjectileHit) {
			t.Fatalf("wall ordering events = %#v", events)
		}
		if enemy := entityByID(t, simulation.Snapshot(), "enemy"); enemy.Health != 100 {
			t.Fatalf("wall-first projectile damaged target: %#v", enemy)
		}
	})

	t.Run("target first", func(t *testing.T) {
		config := projectileConfig()
		config.Walls = []Wall{{
			ID: "later",
			Rect: Rect{
				MinX: Pixels(150),
				MinY: Pixels(20),
				MaxX: Pixels(154),
				MaxY: Pixels(80),
			},
		}}
		simulation := mustNew(t, config)
		events := simulation.Tick(Input{AbilityID: "bolt"})
		requireEvent(t, events, EventProjectileHit)
		if hasEvent(events, EventProjectileBlocked) {
			t.Fatalf("later wall won before target: %#v", events)
		}
	})
}

func TestProjectilePierceUsesDistanceThenStableEntityID(t *testing.T) {
	config := projectileConfig()
	config.Projectiles[0].Pierce = 1
	config.Entities[1].ID = "enemy.b"
	enemyA := config.Entities[1]
	enemyA.ID = "enemy.a"
	config.Entities = append(config.Entities, enemyA)
	simulation := mustNew(t, config)

	events := simulation.Tick(Input{AbilityID: "bolt"})
	hitIDs := make([]string, 0, 2)
	for _, event := range events {
		if event.Type == EventProjectileHit {
			hitIDs = append(hitIDs, event.TargetID)
		}
	}
	if want := []string{"enemy.a", "enemy.b"}; !reflect.DeepEqual(hitIDs, want) {
		t.Fatalf("pierce hit order = %v, want %v", hitIDs, want)
	}
	if len(simulation.Snapshot().Projectiles) != 0 {
		t.Fatal("pierce=1 projectile survived two hits")
	}
}

func TestStatusStackingRefreshAndMoveModifierAreDeterministic(t *testing.T) {
	config := projectileConfig()
	config.Entities = config.Entities[:1]
	config.Camera.TargetEntityID = "hero"
	simulation := mustNew(t, config)
	hero := simulation.entities["hero"]

	if err := simulation.applyStatus("enemy", hero, "burning", 1); err != nil {
		t.Fatal(err)
	}
	if err := simulation.applyStatus("enemy", hero, "burning", 1); err != nil {
		t.Fatal(err)
	}
	before := hero.position.X
	simulation.Tick(Input{MoveX: 1})
	moved := hero.position.X - before
	// 5 px/tick × 0.85², rounded at each fixed-point multiplication.
	if moved != 3696 {
		t.Fatalf("stacked move delta = %d fixed units, want 3696", moved)
	}
	status := entityByID(t, simulation.Snapshot(), "hero").Statuses[0]
	if status.Stacks != 2 ||
		status.RemainingTicks != config.Statuses[0].DurationTicks-1 {
		t.Fatalf("stacked status = %#v", status)
	}
}

func TestStatusArithmeticSaturatesAndStackCountIsBounded(t *testing.T) {
	limit := maxInt64Value()
	if got := scaleFixedSaturated(
		limit,
		UnitsPerPixel*16,
		limit,
	); got != limit {
		t.Fatalf("fixed multiplier overflow = %d, want %d", got, limit)
	}
	if got := saturatingProductInt(int(limit), 2); got != int(limit) {
		t.Fatalf("periodic damage overflow = %d, want %d", got, limit)
	}

	config := projectileConfig()
	config.Statuses[0].MaxStacks = MaxStatusStacks + 1
	if _, err := New(config); err == nil {
		t.Fatal("status stack count above deterministic bound was accepted")
	}
}

func TestProjectileAndStatusSessionRoundTripIsDetached(t *testing.T) {
	config := projectileConfig()
	config.Projectiles[0].Pierce = 2
	source := mustNew(t, config)
	source.Tick(Input{AbilityID: "bolt"})
	if snapshot := source.Snapshot(); len(snapshot.Projectiles) != 1 ||
		len(entityByID(t, snapshot, "enemy").Statuses) != 1 {
		t.Fatalf("fixture did not retain runtime action state: %#v", snapshot)
	}

	saved := source.SaveSession()
	target := mustNew(t, config)
	if err := target.LoadSession(saved); err != nil {
		t.Fatalf("load projectile/status session: %v", err)
	}
	if got := target.SaveSession(); !reflect.DeepEqual(got, saved) {
		t.Fatalf("session round trip differs:\n got=%#v\nwant=%#v", got, saved)
	}
	gotSnapshot := target.Snapshot()
	wantSnapshot := source.Snapshot()
	wantSnapshot.Events = nil
	if !reflect.DeepEqual(gotSnapshot, wantSnapshot) {
		t.Fatalf("snapshot round trip differs:\n got=%#v\nwant=%#v", gotSnapshot, wantSnapshot)
	}

	saved.Projectiles[0].Position.X = -1
	for index := range saved.Entities {
		if saved.Entities[index].ID == "enemy" {
			saved.Entities[index].Statuses[0].Stacks = 99
		}
	}
	if reflect.DeepEqual(saved, target.SaveSession()) {
		t.Fatal("saved projectile/status data aliases simulation state")
	}
}

func projectileConfig() Config {
	config := baseConfig()
	config.Entities[0].Combat = &CombatConfig{
		PrimaryAbilityID: "bolt",
		Abilities: []AbilityConfig{{
			ID:           "bolt",
			ActiveTicks:  1,
			ProjectileID: "projectile.bolt",
		}},
		Bindings: []AbilityBinding{{
			Input:     "special",
			AbilityID: "bolt",
		}},
	}
	config.Entities[0].Status = &StatusReceiverConfig{}
	config.Entities[1].Status = &StatusReceiverConfig{}
	config.Entities[1].Position.X = Pixels(120)
	config.Entities[1].Reaction.HitInvulnerabilityTicks = 3
	config.Projectiles = []ProjectileConfig{{
		ID:            "projectile.bolt",
		ActorKind:     "actor.bolt",
		Body:          Body{HalfWidth: Pixels(2), HalfHeight: Pixels(2), Solid: true},
		Tint:          [4]uint8{51, 217, 255, 242},
		SpeedPerTick:  Pixels(100),
		LifetimeTicks: 30,
		SpawnOffset:   Pixels(10),
		DestroyOnWall: true,
		Impact: ImpactConfig{
			Damage:        18,
			StaggerTicks:  2,
			ApplyStatusID: "burning",
		},
	}}
	config.Statuses = []StatusConfig{{
		ID:                "burning",
		DurationTicks:     90,
		Stacking:          StatusStack,
		MaxStacks:         3,
		TickIntervalTicks: 30,
		TickDamage:        3,
		MoveSpeed:         870,
		DamageDealt:       UnitsPerPixel,
		DamageTaken:       UnitsPerPixel,
		Color:             [4]uint8{255, 89, 20, 255},
	}}
	return config
}
