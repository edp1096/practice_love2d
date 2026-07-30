package gameapp

import (
	"math"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

type runtimeStateDTO struct {
	Engine      string `json:"engine"`
	Go          string `json:"go"`
	Protocol    int    `json:"protocol"`
	Project     string `json:"project"`
	Profile     string `json:"profile"`
	Title       string `json:"title"`
	StageID     string `json:"stage_id"`
	StageName   string `json:"stage_name"`
	Tick        uint64 `json:"tick"`
	WorldTick   uint64 `json:"world_tick"`
	Revision    uint64 `json:"revision"`
	Paused      bool   `json:"paused"`
	Mode        string `json:"mode"`
	Quit        bool   `json:"quit"`
	QuitPending bool   `json:"quit_pending"`
	Hitstop     int    `json:"hitstop_ticks"`
	Definitions int    `json:"definitions"`
	Entities    int    `json:"entities"`
}

type stageDTO struct {
	ID     string  `json:"id"`
	Name   string  `json:"name"`
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}

type wallDTO struct {
	ID     string     `json:"id"`
	X      float64    `json:"x"`
	Y      float64    `json:"y"`
	Width  float64    `json:"width"`
	Height float64    `json:"height"`
	Points []pointDTO `json:"points,omitempty"`
}

type pointDTO struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

type cameraDTO struct {
	X              float64 `json:"x"`
	Y              float64 `json:"y"`
	CenterX        float64 `json:"center_x"`
	CenterY        float64 `json:"center_y"`
	ShakeX         float64 `json:"shake_x"`
	ShakeY         float64 `json:"shake_y"`
	ShakeTicks     int     `json:"shake_ticks"`
	ViewportWidth  float64 `json:"viewport_width"`
	ViewportHeight float64 `json:"viewport_height"`
	Zoom           float64 `json:"zoom"`
}

type rpgStatsDTO struct {
	Attack    int     `json:"attack"`
	Defense   int     `json:"defense"`
	MoveSpeed float64 `json:"move_speed"`
}

type entityDTO struct {
	ID                    string                        `json:"id"`
	ActorID               string                        `json:"actor_id"`
	Name                  string                        `json:"name"`
	Tags                  []string                      `json:"tags"`
	Team                  string                        `json:"team,omitempty"`
	Dead                  bool                          `json:"dead"`
	X                     float64                       `json:"x"`
	Y                     float64                       `json:"y"`
	ScreenX               float64                       `json:"screen_x"`
	ScreenY               float64                       `json:"screen_y"`
	Visible               bool                          `json:"visible"`
	InViewport            bool                          `json:"in_viewport"`
	RadiusX               float64                       `json:"radius_x"`
	RadiusY               float64                       `json:"radius_y"`
	Health                int                           `json:"health"`
	MaxHealth             int                           `json:"max_health"`
	Stats                 rpgStatsDTO                   `json:"stats"`
	FacingX               float64                       `json:"facing_x"`
	FacingY               float64                       `json:"facing_y"`
	AttackPhase           sim.AttackPhase               `json:"attack_phase"`
	AbilityID             string                        `json:"ability_id,omitempty"`
	AttackRemaining       int                           `json:"attack_remaining"`
	AttackCooldown        int                           `json:"attack_cooldown"`
	AbilityCooldowns      []sim.AbilityCooldownSnapshot `json:"ability_cooldowns,omitempty"`
	AttackHitCount        int                           `json:"attack_hit_count"`
	Statuses              []sim.StatusSnapshot          `json:"statuses,omitempty"`
	StaggerRemaining      int                           `json:"stagger_remaining"`
	InvulnerableRemaining int                           `json:"invulnerable_remaining"`
	FlashRemaining        int                           `json:"flash_remaining"`
	KnockbackRemaining    int                           `json:"knockback_remaining"`
	ParryActive           bool                          `json:"parry_active"`
	ParryRemaining        int                           `json:"parry_remaining"`
	ParryCooldown         int                           `json:"parry_cooldown"`
	ParryPerfect          bool                          `json:"parry_perfect"`
	DodgeActive           bool                          `json:"dodge_active"`
	DodgeRemaining        int                           `json:"dodge_remaining"`
	DodgeCooldown         int                           `json:"dodge_cooldown"`
	Platformer            bool                          `json:"platformer"`
	VelocityX             float64                       `json:"velocity_x"`
	VelocityY             float64                       `json:"velocity_y"`
	Grounded              bool                          `json:"grounded"`
	CoyoteRemaining       int                           `json:"coyote_remaining"`
	JumpBufferRemaining   int                           `json:"jump_buffer_remaining"`
	PlatformerSpeed       float64                       `json:"platformer_speed_per_tick,omitempty"`
	PlatformerGravity     float64                       `json:"platformer_gravity_per_tick,omitempty"`
	PlatformerJumpSpeed   float64                       `json:"platformer_jump_speed_per_tick,omitempty"`
	AITargetTag           string                        `json:"ai_target_tag,omitempty"`
	AIPattern             string                        `json:"ai_pattern,omitempty"`
	AIAttackIndex         int                           `json:"ai_attack_index,omitempty"`
	AINextAbility         string                        `json:"ai_next_ability,omitempty"`
}

type projectileDTO struct {
	ID             string  `json:"id"`
	ProjectileID   string  `json:"projectile_id"`
	ActorID        string  `json:"actor_id"`
	SourceID       string  `json:"source_id"`
	AbilityID      string  `json:"ability_id"`
	Team           string  `json:"team"`
	X              float64 `json:"x"`
	Y              float64 `json:"y"`
	PreviousX      float64 `json:"previous_x"`
	PreviousY      float64 `json:"previous_y"`
	ScreenX        float64 `json:"screen_x"`
	ScreenY        float64 `json:"screen_y"`
	Visible        bool    `json:"visible"`
	RadiusX        float64 `json:"radius_x"`
	RadiusY        float64 `json:"radius_y"`
	DirectionX     float64 `json:"direction_x"`
	DirectionY     float64 `json:"direction_y"`
	RemainingTicks int     `json:"remaining_ticks"`
	Hits           int     `json:"hits"`
}

type worldSnapshotDTO struct {
	Available       bool                    `json:"available"`
	Time            float64                 `json:"time"`
	Tick            uint64                  `json:"tick"`
	WorldTick       uint64                  `json:"world_tick"`
	Revision        uint64                  `json:"revision"`
	HitstopTicks    int                     `json:"hitstop_ticks"`
	Stage           stageDTO                `json:"stage"`
	Walls           []wallDTO               `json:"walls"`
	Camera          cameraDTO               `json:"camera"`
	Count           int                     `json:"count"`
	Entities        []entityDTO             `json:"entities"`
	ProjectileCount int                     `json:"projectile_count"`
	Projectiles     []projectileDTO         `json:"projectiles"`
	EncounterCount  int                     `json:"encounter_count"`
	Encounters      []sim.EncounterSnapshot `json:"encounters"`
	Quests          []sim.QuestSnapshot     `json:"quests"`
	Campaign        campaign.State          `json:"campaign"`
	WorldState      authoredWorldStateDTO   `json:"world_state"`
	Dialogue        DialogueState           `json:"dialogue"`
	Cutscene        CutsceneState           `json:"cutscene"`
	Notice          ebitapp.NoticeView      `json:"notice"`
	TurnBattle      TurnBattleState         `json:"turn_battle"`
	RecentEvents    []sim.Event             `json:"recent_events"`
}

type authoredWorldStateDTO struct {
	Day           int64    `json:"day"`
	Minute        float64  `json:"minute"`
	Clock         string   `json:"clock"`
	ActivePage    string   `json:"active_page,omitempty"`
	ActiveRegions []string `json:"active_regions"`
	RegionCount   int      `json:"region_count"`
	PageCount     int      `json:"page_count"`
	SecondsPerDay float64  `json:"seconds_per_day"`
}

func (runtime *Runtime) worldSnapshotLocked() worldSnapshotDTO {
	snapshot := runtime.simulation.Snapshot()
	frame := runtime.simulation.RenderFrame()
	viewportWidth := coordPixels(frame.Camera.ViewportWidth)
	viewportHeight := coordPixels(frame.Camera.ViewportHeight)
	zoom := math.Min(
		960/viewportWidth,
		540/viewportHeight,
	)
	topLeftX := coordPixels(
		frame.Camera.BaseCenter.X - frame.Camera.ViewportWidth/2,
	)
	topLeftY := coordPixels(
		frame.Camera.BaseCenter.Y - frame.Camera.ViewportHeight/2,
	)
	campaignState := runtime.campaign.Snapshot()
	cameraMotionScale := motionScale(campaignState.Accessibility)
	shakeX := -coordPixels(frame.Camera.ShakeOffset.X) *
		cameraMotionScale
	shakeY := -coordPixels(frame.Camera.ShakeOffset.Y) *
		cameraMotionScale
	dialogue, dialogueErr := runtime.dialogueStateLocked()
	if dialogueErr != nil {
		dialogue = DialogueState{
			Active:  true,
			Text:    "dialogue state error: " + dialogueErr.Error(),
			Choices: []DialogueChoiceState{},
		}
	}
	activeRegions := sortedActiveWorldRegions(runtime.worldActiveRegions)
	result := worldSnapshotDTO{
		Available:    true,
		Time:         float64(snapshot.WorldTick) / sim.TicksPerSecond,
		Tick:         snapshot.Tick,
		WorldTick:    snapshot.WorldTick,
		Revision:     runtime.revision,
		HitstopTicks: snapshot.HitstopTicks,
		Stage: stageDTO{
			ID:     runtime.built.Presentation.StageID,
			Name:   runtime.built.Presentation.StageName,
			X:      coordPixels(frame.Stage.MinX),
			Y:      coordPixels(frame.Stage.MinY),
			Width:  coordPixels(frame.Stage.MaxX - frame.Stage.MinX),
			Height: coordPixels(frame.Stage.MaxY - frame.Stage.MinY),
		},
		Camera: cameraDTO{
			X:       topLeftX,
			Y:       topLeftY,
			CenterX: coordPixels(frame.Camera.Center.X),
			CenterY: coordPixels(frame.Camera.Center.Y),
			ShakeX:  shakeX,
			ShakeY:  shakeY,
			ShakeTicks: func() int {
				if cameraMotionScale == 0 {
					return 0
				}
				return frame.Camera.ShakeTicks
			}(),
			ViewportWidth:  viewportWidth,
			ViewportHeight: viewportHeight,
			Zoom:           zoom,
		},
		Count:    len(snapshot.Entities),
		Quests:   snapshot.Quests,
		Campaign: campaignState,
		WorldState: authoredWorldStateDTO{
			Day:           campaignState.World.Day,
			Minute:        campaignState.World.Minute,
			Clock:         formatWorldClock(campaignState.World.Minute),
			ActivePage:    runtime.worldActivePage,
			ActiveRegions: activeRegions,
			RegionCount:   len(runtime.built.Stage.Regions),
			PageCount:     len(runtime.built.Stage.WorldPages),
			SecondsPerDay: runtime.campaignConfig.WorldSecondsPerDay,
		},
		Dialogue:        dialogue,
		Cutscene:        runtime.cutsceneStateLocked(),
		Notice:          runtime.notice,
		TurnBattle:      runtime.turnBattleStateLocked(),
		RecentEvents:    snapshot.Events,
		Walls:           make([]wallDTO, 0, len(frame.Walls)),
		Entities:        make([]entityDTO, 0, len(snapshot.Entities)),
		ProjectileCount: len(snapshot.Projectiles),
		EncounterCount:  len(snapshot.Encounters),
		Encounters: append(
			[]sim.EncounterSnapshot(nil),
			snapshot.Encounters...,
		),
		Projectiles: make(
			[]projectileDTO,
			0,
			len(snapshot.Projectiles),
		),
	}
	for _, wall := range frame.Walls {
		rect := wall.Rect
		points := make([]pointDTO, len(wall.Points))
		for index, point := range wall.Points {
			points[index] = pointDTO{
				X: coordPixels(point.X),
				Y: coordPixels(point.Y),
			}
		}
		result.Walls = append(result.Walls, wallDTO{
			ID:     wall.ID,
			X:      coordPixels(rect.MinX),
			Y:      coordPixels(rect.MinY),
			Width:  coordPixels(rect.MaxX - rect.MinX),
			Height: coordPixels(rect.MaxY - rect.MinY),
			Points: points,
		})
	}
	for _, entity := range snapshot.Entities {
		metadata, _ := runtime.metadata(entity.ID)
		x := coordPixels(entity.Position.X)
		y := coordPixels(entity.Position.Y)
		screenX := (x - topLeftX + shakeX) * zoom
		screenY := (y - topLeftY + shakeY) * zoom
		radiusX := coordPixels(entity.Body.HalfWidth)
		radiusY := coordPixels(entity.Body.HalfHeight)
		inViewport := screenX+radiusX*zoom >= 0 &&
			screenX-radiusX*zoom <= 960 &&
			screenY+radiusY*zoom >= 0 &&
			screenY-radiusY*zoom <= 540
		dto := entityDTO{
			ID:         entity.ID,
			ActorID:    entity.Kind,
			Name:       entity.Name,
			Tags:       append([]string(nil), metadata.Tags...),
			Team:       entity.Team,
			Dead:       entity.Dead,
			X:          x,
			Y:          y,
			ScreenX:    screenX,
			ScreenY:    screenY,
			Visible:    !entity.Dead && inViewport,
			InViewport: inViewport,
			RadiusX:    radiusX,
			RadiusY:    radiusY,
			Health:     entity.Health,
			MaxHealth:  entity.MaxHealth,
			Stats: rpgStatsDTO{
				Attack:    entity.Stats.Attack,
				Defense:   entity.Stats.Defense,
				MoveSpeed: coordPixels(entity.Stats.MoveSpeed),
			},
			FacingX:         coordPixels(entity.Facing.X),
			FacingY:         coordPixels(entity.Facing.Y),
			AttackPhase:     entity.Attack.Phase,
			AbilityID:       entity.Attack.AbilityID,
			AttackRemaining: entity.Attack.RemainingTicks,
			AttackCooldown:  entity.Attack.CooldownTicks,
			AbilityCooldowns: append(
				[]sim.AbilityCooldownSnapshot(nil),
				entity.AbilityCooldowns...,
			),
			AttackHitCount: entity.Attack.HitCount,
			Statuses: append(
				[]sim.StatusSnapshot(nil),
				entity.Statuses...,
			),
			StaggerRemaining:      entity.StaggerTicks,
			InvulnerableRemaining: entity.InvulnerableTicks,
			FlashRemaining: func() int {
				if !campaignState.Accessibility.HitFlash {
					return 0
				}
				return entity.FlashTicks
			}(),
			KnockbackRemaining:  entity.KnockbackTicks,
			ParryActive:         entity.ParryTicks > 0,
			ParryRemaining:      entity.ParryTicks,
			ParryCooldown:       entity.ParryCooldownTicks,
			ParryPerfect:        entity.LastParryPerfect,
			DodgeActive:         entity.DodgeTicks > 0,
			DodgeRemaining:      entity.DodgeTicks,
			DodgeCooldown:       entity.DodgeCooldownTicks,
			Platformer:          entity.Platformer != nil,
			VelocityX:           coordPixels(entity.Velocity.X),
			VelocityY:           coordPixels(entity.Velocity.Y),
			Grounded:            entity.Grounded,
			CoyoteRemaining:     entity.CoyoteTicks,
			JumpBufferRemaining: entity.JumpBufferTicks,
		}
		if entity.Platformer != nil {
			dto.PlatformerSpeed = coordPixels(
				entity.Platformer.MaxSpeedPerTick,
			)
			dto.PlatformerGravity = coordPixels(
				entity.Platformer.GravityPerTick,
			)
			dto.PlatformerJumpSpeed = coordPixels(
				entity.Platformer.JumpSpeedPerTick,
			)
		}
		if metadata.BehaviorAI != nil {
			pattern := activeBehaviorPattern(entity, metadata.BehaviorAI)
			state := runtime.behaviorAI[entity.ID]
			if state.PatternID != pattern.ID ||
				state.AttackIndex < 0 ||
				state.AttackIndex >= len(pattern.Attacks) {
				state.PatternID = pattern.ID
				state.AttackIndex = 0
			}
			dto.AITargetTag = metadata.BehaviorAI.TargetTag
			dto.AIPattern = pattern.ID
			dto.AIAttackIndex = state.AttackIndex + 1
			if len(pattern.Attacks) > 0 {
				dto.AINextAbility =
					pattern.Attacks[state.AttackIndex].AbilityID
			}
		}
		result.Entities = append(result.Entities, dto)
	}
	for _, projectile := range snapshot.Projectiles {
		x := coordPixels(projectile.Position.X)
		y := coordPixels(projectile.Position.Y)
		screenX := (x - topLeftX + shakeX) * zoom
		screenY := (y - topLeftY + shakeY) * zoom
		radiusX := coordPixels(projectile.Body.HalfWidth)
		radiusY := coordPixels(projectile.Body.HalfHeight)
		visible := screenX+radiusX*zoom >= 0 &&
			screenX-radiusX*zoom <= 960 &&
			screenY+radiusY*zoom >= 0 &&
			screenY-radiusY*zoom <= 540
		result.Projectiles = append(result.Projectiles, projectileDTO{
			ID:             projectile.ID,
			ProjectileID:   projectile.DefinitionID,
			ActorID:        projectile.ActorKind,
			SourceID:       projectile.SourceID,
			AbilityID:      projectile.AbilityID,
			Team:           projectile.Team,
			X:              x,
			Y:              y,
			PreviousX:      coordPixels(projectile.Previous.X),
			PreviousY:      coordPixels(projectile.Previous.Y),
			ScreenX:        screenX,
			ScreenY:        screenY,
			Visible:        visible,
			RadiusX:        radiusX,
			RadiusY:        radiusY,
			DirectionX:     coordPixels(projectile.Direction.X),
			DirectionY:     coordPixels(projectile.Direction.Y),
			RemainingTicks: projectile.RemainingTicks,
			Hits:           projectile.Hits,
		})
	}
	return result
}
