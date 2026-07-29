package gameapp

import (
	"path/filepath"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/protocol"
	"practice_love2d/33_ebitengine_spike/internal/sim"
	"practice_love2d/33_ebitengine_spike/internal/storage"
)

func TestAuthoredSpecialProjectileIsVisibleControllableAndBurns(t *testing.T) {
	store, err := storage.NewFileStore(filepath.Join(t.TempDir(), "saves"))
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{
		CatalogPath: filepath.Join("..", "..", "game", "catalog.json"),
		Build: gamebuild.Options{
			StageID:  "stage.action_room",
			LocaleID: "locale.ko",
		},
		Store: store,
	})
	if err != nil {
		t.Fatal(err)
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: "enemy.slime.1",
			X:        350,
			Y:        270,
		},
	)

	if err := runtime.Tick(ebitapp.Actions{Special: true}); err != nil {
		t.Fatal(err)
	}
	for tick := 0; tick < 7; tick++ {
		if err := runtime.Tick(ebitapp.Actions{}); err != nil {
			t.Fatal(err)
		}
	}
	runtime.mu.RLock()
	inFlight := runtime.worldSnapshotLocked()
	runtime.mu.RUnlock()
	if inFlight.ProjectileCount != 1 ||
		len(inFlight.Projectiles) != 1 {
		t.Fatalf(
			"special projectile is not inspectable: projectiles=%#v events=%#v entities=%#v",
			inFlight.Projectiles,
			inFlight.RecentEvents,
			inFlight.Entities,
		)
	}
	projectile := inFlight.Projectiles[0]
	if projectile.ProjectileID != "projectile.fire_bolt" ||
		projectile.AbilityID != "ability.fire_bolt" ||
		projectile.SourceID != "player" ||
		!projectile.Visible ||
		projectile.X <= 205 {
		t.Fatalf("in-flight projectile DTO = %#v", projectile)
	}
	view := runtime.View()
	rendered := false
	for _, entity := range view.Entities {
		if entity.ID == projectile.ID {
			rendered = entity.Layer == 20 &&
				entity.Radius == 6 &&
				entity.Tint.R != 0 &&
				entity.Tint.A != 0
		}
	}
	if !rendered {
		t.Fatalf("projectile is absent from render View: %#v", view.Entities)
	}

	hit := false
	for tick := 0; tick < 45 && !hit; tick++ {
		if err := runtime.Tick(ebitapp.Actions{}); err != nil {
			t.Fatal(err)
		}
		snapshot := runtime.simulation.Snapshot()
		for _, event := range snapshot.Events {
			if event.Type == sim.EventProjectileHit &&
				event.TargetID == "enemy.slime.1" {
				hit = true
			}
		}
	}
	if !hit {
		t.Fatal("authored fire bolt did not hit aligned slime")
	}
	target := entitySnapshot(t, runtime, "enemy.slime.1")
	if target.Health != 50 || len(target.Statuses) != 1 ||
		target.Statuses[0].ID != "status.burning" {
		t.Fatalf("fire bolt impact = %#v", target)
	}

	ticked := false
	for tick := 0; tick < 40 && !ticked; tick++ {
		if err := runtime.Tick(ebitapp.Actions{}); err != nil {
			t.Fatal(err)
		}
		for _, event := range runtime.simulation.Snapshot().Events {
			if event.Type == sim.EventStatusTicked &&
				event.TargetID == "enemy.slime.1" {
				ticked = true
			}
		}
	}
	target = entitySnapshot(t, runtime, "enemy.slime.1")
	if !ticked || target.Health != 47 {
		t.Fatalf("burn tick: ticked=%v target=%#v", ticked, target)
	}
}

func TestProtocolCanQueueSecondaryAbilityByExactID(t *testing.T) {
	runtime := newTestRuntime(t)
	result := callRuntime(
		t,
		runtime,
		protocol.MethodEntityRequestAbility,
		protocol.RequestAbilityParams{
			EntityID:  "player",
			AbilityID: "ability.fire_bolt",
		},
	)
	if result == nil {
		t.Fatal("secondary ability request returned no result")
	}
	runtime.mu.RLock()
	queued := runtime.pendingAbilities["player"]
	runtime.mu.RUnlock()
	if queued != "ability.fire_bolt" {
		t.Fatalf("queued ability = %q", queued)
	}
}

func TestAuthoredTechniqueExecutesThreeTimedHits(t *testing.T) {
	store, err := storage.NewFileStore(filepath.Join(t.TempDir(), "saves"))
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{
		CatalogPath: filepath.Join("..", "..", "game", "catalog.json"),
		Build: gamebuild.Options{
			StageID:  "stage.action_room",
			LocaleID: "locale.ko",
		},
		Store: store,
	})
	if err != nil {
		t.Fatal(err)
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: "enemy.slime.1",
			X:        210,
			Y:        270,
		},
	)
	if err := runtime.Tick(ebitapp.Actions{Technique: true}); err != nil {
		t.Fatal(err)
	}
	hits := 0
	for tick := 0; tick < 80; tick++ {
		if err := runtime.Tick(ebitapp.Actions{}); err != nil {
			t.Fatal(err)
		}
		for _, event := range runtime.simulation.Snapshot().Events {
			if event.Type == sim.EventDamageApplied &&
				event.AbilityID == "ability.whirlwind" &&
				event.TargetID == "enemy.slime.1" {
				hits++
			}
		}
	}
	target := entitySnapshot(t, runtime, "enemy.slime.1")
	if hits != 3 || target.Health != 50 {
		t.Fatalf("whirlwind hits=%d target=%#v", hits, target)
	}
}
