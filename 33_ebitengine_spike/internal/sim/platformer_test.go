package sim

import (
	"reflect"
	"testing"
)

func TestPlatformerCoyoteTimeAndBufferedJump(t *testing.T) {
	t.Run("coyote time", func(t *testing.T) {
		simulation := mustNew(t, platformerConfig())
		simulation.Tick(Input{})
		if hero := simulation.entities["hero"]; !hero.grounded {
			t.Fatal("platformer did not settle on the floor")
		}
		for range 3 {
			simulation.Tick(Input{MoveX: 1})
		}
		hero := simulation.entities["hero"]
		if hero.grounded {
			t.Fatalf("platformer did not leave ledge: %#v", hero)
		}
		events := simulation.Tick(Input{Jump: true})
		if !hasEvent(events, EventPlatformerJumped) ||
			hero.velocity.Y >= 0 {
			t.Fatalf(
				"coyote jump failed: velocity=%#v events=%#v",
				hero.velocity,
				events,
			)
		}
	})

	t.Run("jump buffer", func(t *testing.T) {
		simulation := mustNew(t, platformerConfig())
		hero := simulation.entities["hero"]
		hero.position = Vec{X: Pixels(40), Y: Pixels(132)}
		hero.velocity.Y = Pixels(5)

		if events := simulation.Tick(Input{Jump: true}); hasEvent(events, EventPlatformerJumped) {
			t.Fatal("airborne buffered press jumped before landing")
		}
		landed := false
		jumped := false
		for range 4 {
			events := simulation.Tick(Input{})
			landed = landed || hasEvent(events, EventPlatformerLanded)
			jumped = jumped || hasEvent(events, EventPlatformerJumped)
			if jumped {
				break
			}
		}
		if !landed || !jumped || hero.velocity.Y >= 0 {
			t.Fatalf(
				"buffered landing jump failed: landed=%v jumped=%v hero=%#v",
				landed,
				jumped,
				hero,
			)
		}
	})
}

func TestPlatformerSessionRoundTripAndLegacyGuard(t *testing.T) {
	config := platformerConfig()
	source := mustNew(t, config)
	source.Tick(Input{})
	source.Tick(Input{MoveX: 1, Jump: true})
	saved := source.SaveSession()

	target := mustNew(t, config)
	if err := target.LoadSession(saved); err != nil {
		t.Fatalf("load platformer session: %v", err)
	}
	if got := target.SaveSession(); !reflect.DeepEqual(got, saved) {
		t.Fatalf("platformer session differs:\n got=%#v\nwant=%#v", got, saved)
	}

	legacy := saved
	legacy.Version = actionSessionVersion
	if err := target.LoadSession(legacy); err == nil {
		t.Fatal("legacy session accepted platformer physics fields")
	}
}

func platformerConfig() Config {
	config := baseConfig()
	config.Entities = config.Entities[:1]
	config.Entities[0].Position = Vec{X: Pixels(70), Y: Pixels(145)}
	config.Entities[0].MovePerTick = 0
	config.Entities[0].Platformer = &PlatformerConfig{
		MaxSpeedPerTick:     Pixels(5),
		AccelerationPerTick: Pixels(5),
		AirAcceleration:     Pixels(5),
		DecelerationPerTick: Pixels(5),
		GravityPerTick:      Pixels(1),
		JumpSpeedPerTick:    Pixels(10),
		MaxFallSpeedPerTick: Pixels(10),
		CoyoteTicks:         3,
		JumpBufferTicks:     3,
	}
	config.Walls = []Wall{{
		ID: "floor",
		Rect: Rect{
			MinX: 0,
			MinY: Pixels(150),
			MaxX: Pixels(80),
			MaxY: Pixels(170),
		},
	}}
	config.Camera.TargetEntityID = "hero"
	return config
}
