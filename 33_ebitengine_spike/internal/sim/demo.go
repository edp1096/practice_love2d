package sim

// DemoConfig returns the complete data-authored vertical-slice configuration:
// a controllable hero, a hostile slime, an interactable guide, stage walls,
// combat actions, dialogue, quest progression, and a bounded camera.
func DemoConfig() Config {
	return Config{
		StageBounds: Rect{
			MinX: 0,
			MinY: 0,
			MaxX: Pixels(1440),
			MaxY: Pixels(900),
		},
		Walls: []Wall{
			{
				ID: "demo.vertical",
				Rect: Rect{
					MinX: Pixels(760),
					MinY: Pixels(120),
					MaxX: Pixels(790),
					MaxY: Pixels(650),
				},
			},
			{
				ID: "demo.horizontal",
				Rect: Rect{
					MinX: Pixels(980),
					MinY: Pixels(570),
					MaxX: Pixels(1260),
					MaxY: Pixels(600),
				},
			},
		},
		Entities: []EntityConfig{
			{
				ID:          "actor.hero",
				Kind:        "hero",
				Name:        "Hero",
				Team:        "player",
				Position:    Vec{X: Pixels(520), Y: Pixels(350)},
				Body:        Body{HalfWidth: Pixels(15), HalfHeight: Pixels(15), Solid: true},
				MaxHealth:   100,
				MovePerTick: Pixels(190) / TicksPerSecond,
				Facing:      Vec{X: UnitsPerPixel},
				Controlled:  true,
				Ability: &AbilityConfig{
					ID:               "ability.sword_slash",
					WindupTicks:      0,
					ActiveTicks:      7,
					RecoveryTicks:    8,
					CooldownTicks:    17,
					LockMovement:     true,
					Reach:            Pixels(48),
					ArcDegrees:       105,
					Damage:           34,
					StaggerTicks:     13,
					Knockback:        Pixels(24),
					KnockbackTicks:   7,
					HitstopTicks:     3,
					CameraShake:      Pixels(5),
					CameraShakeTicks: 8,
				},
				Reaction: ReactionConfig{
					HitInvulnerabilityTicks: 21,
					FlashTicks:              11,
				},
				Dodge: &DodgeConfig{
					DurationTicks:        13,
					Distance:             Pixels(78),
					InvulnerabilityTicks: 11,
					CooldownTicks:        29,
				},
				Parry: &ParryConfig{
					WindowTicks:          19,
					PerfectWindowTicks:   7,
					CooldownTicks:        45,
					SuccessCooldownTicks: 11,
					ArcDegrees:           170,
					StaggerTicks:         33,
					PerfectStaggerTicks:  66,
					HitstopTicks:         2,
					PerfectHitstopTicks:  4,
					CameraShake:          Pixels(7),
					CameraShakeTicks:     10,
				},
			},
			{
				ID:          "actor.slime",
				Kind:        "slime",
				Name:        "Slime",
				Team:        "enemy",
				Position:    Vec{X: Pixels(576), Y: Pixels(350)},
				Body:        Body{HalfWidth: Pixels(13), HalfHeight: Pixels(13), Solid: true},
				MaxHealth:   68,
				MovePerTick: Pixels(72) / TicksPerSecond,
				Facing:      Vec{X: -UnitsPerPixel},
				Ability: &AbilityConfig{
					ID:               "ability.slime_bump",
					WindupTicks:      21,
					ActiveTicks:      6,
					RecoveryTicks:    10,
					CooldownTicks:    51,
					LockMovement:     true,
					Reach:            Pixels(10),
					ArcDegrees:       180,
					Damage:           8,
					StaggerTicks:     11,
					Knockback:        Pixels(18),
					KnockbackTicks:   6,
					HitstopTicks:     2,
					CameraShake:      Pixels(4),
					CameraShakeTicks: 7,
				},
				Reaction: ReactionConfig{
					HitInvulnerabilityTicks: 7,
					FlashTicks:              10,
				},
			},
			{
				ID:           "actor.guide",
				Kind:         "npc",
				Name:         "Guide",
				Position:     Vec{X: Pixels(520), Y: Pixels(405)},
				Body:         Body{HalfWidth: Pixels(14), HalfHeight: Pixels(14), Solid: true},
				MaxHealth:    1,
				Facing:       Vec{Y: -UnitsPerPixel},
				DialogueID:   "dialogue.guide",
				StartQuestID: "quest.slime_patrol",
			},
		},
		Dialogues: []DialogueDefinition{
			{
				ID:      "dialogue.guide",
				Speaker: "Guide",
				Text:    "Defeat the slime near the village gate.",
			},
		},
		Quests: []QuestDefinition{
			{
				ID:         "quest.slime_patrol",
				TargetKind: "slime",
				Required:   1,
			},
		},
		Camera: CameraConfig{
			TargetEntityID: "actor.hero",
			ViewportWidth:  Pixels(960),
			ViewportHeight: Pixels(540),
		},
		InteractionRange: Pixels(64),
	}
}

// NewDemo constructs the built-in vertical slice. DemoConfig is compile-time
// owned content, so a validation failure indicates a programmer error and
// intentionally panics.
func NewDemo() *Simulation {
	simulation, err := New(DemoConfig())
	if err != nil {
		panic(err)
	}
	return simulation
}
