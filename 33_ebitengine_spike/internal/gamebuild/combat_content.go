package gamebuild

import (
	"encoding/json"
	"fmt"
	"math"
	"sort"

	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func buildRuntimeCombatContent(
	catalog *content.Catalog,
	impactOptions ImpactOptions,
) ([]sim.StatusConfig, []sim.ProjectileConfig, error) {
	statuses := make([]sim.StatusConfig, 0)
	projectiles := make([]sim.ProjectileConfig, 0)
	for _, definition := range catalog.Definitions {
		kind, _ := definition.Data["kind"].(string)
		id, _ := definition.Data["id"].(string)
		if kind != "status" {
			continue
		}
		status, err := buildStatus(catalog, id)
		if err != nil {
			return nil, nil, err
		}
		statuses = append(statuses, status)
	}
	for _, definition := range catalog.Definitions {
		kind, _ := definition.Data["kind"].(string)
		id, _ := definition.Data["id"].(string)
		if kind != "projectile" {
			continue
		}
		projectile, err := buildProjectile(
			catalog,
			id,
			impactOptions,
		)
		if err != nil {
			return nil, nil, err
		}
		projectiles = append(projectiles, projectile)
	}
	sort.Slice(statuses, func(left, right int) bool {
		return statuses[left].ID < statuses[right].ID
	})
	sort.Slice(projectiles, func(left, right int) bool {
		return projectiles[left].ID < projectiles[right].ID
	})
	return statuses, projectiles, nil
}

func buildStatus(
	catalog *content.Catalog,
	id string,
) (sim.StatusConfig, error) {
	var authored statusDefinition
	if err := catalog.Decode(id, &authored); err != nil {
		return sim.StatusConfig{}, err
	}
	if err := validateHeader(
		authored.SchemaVersion,
		authored.Kind,
		authored.ID,
		"status",
		id,
	); err != nil {
		return sim.StatusConfig{}, err
	}
	result := sim.StatusConfig{
		ID:            id,
		DurationTicks: secondsToTicks(authored.Duration),
		Stacking:      sim.StatusStacking(authored.Stacking),
		MaxStacks:     authored.MaxStacks,
		MoveSpeed:     sim.UnitsPerPixel,
		DamageDealt:   sim.UnitsPerPixel,
		DamageTaken:   sim.UnitsPerPixel,
	}
	if result.Stacking == sim.StatusRefresh {
		result.MaxStacks = 1
	}
	if result.Stacking == sim.StatusStack && result.MaxStacks == 0 {
		result.MaxStacks = sim.MaxStatusStacks
	}
	if authored.TickInterval > 0 {
		result.TickIntervalTicks = secondsToTicks(authored.TickInterval)
	}
	for _, action := range authored.TickActions {
		if action.Type != "damage" || action.Amount <= 0 ||
			result.TickDamage != 0 {
			return sim.StatusConfig{}, fmt.Errorf(
				"%s has unsupported tick action %q",
				id,
				action.Type,
			)
		}
		result.TickDamage = action.Amount
	}
	var err error
	if authored.Modifiers.MoveSpeed != 0 {
		result.MoveSpeed, err = statusMultiplier(
			authored.Modifiers.MoveSpeed,
		)
		if err != nil {
			return sim.StatusConfig{}, fmt.Errorf("%s move_speed: %w", id, err)
		}
	}
	if authored.Modifiers.DamageDealt != 0 {
		result.DamageDealt, err = statusMultiplier(
			authored.Modifiers.DamageDealt,
		)
		if err != nil {
			return sim.StatusConfig{}, fmt.Errorf("%s damage_dealt: %w", id, err)
		}
	}
	if authored.Modifiers.DamageTaken != 0 {
		result.DamageTaken, err = statusMultiplier(
			authored.Modifiers.DamageTaken,
		)
		if err != nil {
			return sim.StatusConfig{}, fmt.Errorf("%s damage_taken: %w", id, err)
		}
	}
	result.Color, err = rgba8(authored.Color)
	if err != nil {
		return sim.StatusConfig{}, fmt.Errorf("%s color: %w", id, err)
	}
	return result, nil
}

func buildProjectile(
	catalog *content.Catalog,
	id string,
	impactOptions ImpactOptions,
) (sim.ProjectileConfig, error) {
	var authored projectileDefinition
	if err := catalog.Decode(id, &authored); err != nil {
		return sim.ProjectileConfig{}, err
	}
	if err := validateHeader(
		authored.SchemaVersion,
		authored.Kind,
		authored.ID,
		"projectile",
		id,
	); err != nil {
		return sim.ProjectileConfig{}, err
	}
	var actor actorDefinition
	if err := catalog.Decode(authored.Actor, &actor); err != nil {
		return sim.ProjectileConfig{}, err
	}
	if err := validateHeader(
		actor.SchemaVersion,
		actor.Kind,
		actor.ID,
		"actor",
		authored.Actor,
	); err != nil {
		return sim.ProjectileConfig{}, err
	}
	body, err := projectileBody(actor)
	if err != nil {
		return sim.ProjectileConfig{}, fmt.Errorf("%s: %w", id, err)
	}
	tint := [4]uint8{
		defaultProjectileRed,
		defaultProjectileGreen,
		defaultProjectileBlue,
		255,
	}
	if raw := actor.Components["render.shape"]; raw != nil {
		var renderer renderShapeComponent
		if err := json.Unmarshal(raw, &renderer); err != nil {
			return sim.ProjectileConfig{}, fmt.Errorf(
				"%s render.shape: %w",
				id,
				err,
			)
		}
		tint, err = rgba8(renderer.Color)
		if err != nil {
			return sim.ProjectileConfig{}, fmt.Errorf(
				"%s render.shape color: %w",
				id,
				err,
			)
		}
	}
	destroyOnWall := true
	if authored.DestroyOnWall != nil {
		destroyOnWall = *authored.DestroyOnWall
	}
	result := sim.ProjectileConfig{
		ID:            id,
		ActorKind:     authored.Actor,
		Body:          body,
		Tint:          tint,
		SpeedPerTick:  rateToCoord(authored.Speed),
		LifetimeTicks: secondsToTicks(authored.Lifetime),
		SpawnOffset:   pixels(authored.SpawnOffset),
		Pierce:        authored.Pierce,
		DestroyOnWall: destroyOnWall,
		Impact: sim.ImpactConfig{
			CameraShake: pixels(impactOptions.DamageShakePixels),
			CameraShakeTicks: secondsToTicks(
				impactOptions.DamageShakeSeconds,
			),
		},
	}
	for _, effect := range authored.Effects {
		switch effect.Type {
		case "damage":
			result.Impact.Damage = effect.Amount
		case "stagger":
			result.Impact.StaggerTicks = secondsToTicks(effect.Duration)
		case "apply_status":
			result.Impact.ApplyStatusID = effect.Status
		case "knockback":
			result.Impact.Knockback = pixels(effect.Distance)
			result.Impact.KnockbackTicks = secondsToTicks(effect.Duration)
		case "hitstop":
			result.Impact.HitstopTicks = secondsToTicks(effect.Duration)
		default:
			return sim.ProjectileConfig{}, fmt.Errorf(
				"%s has unsupported effect %q",
				id,
				effect.Type,
			)
		}
	}
	return result, nil
}

const (
	defaultProjectileRed   = 120
	defaultProjectileGreen = 220
	defaultProjectileBlue  = 255
)

func projectileBody(actor actorDefinition) (sim.Body, error) {
	raw := actor.Components["body"]
	if raw == nil {
		return sim.Body{}, fmt.Errorf("projectile actor has no body")
	}
	var body bodyComponent
	if err := json.Unmarshal(raw, &body); err != nil {
		return sim.Body{}, fmt.Errorf("decode projectile body: %w", err)
	}
	if body.Shape != "circle" || !positiveFinite(body.Radius) {
		return sim.Body{}, fmt.Errorf(
			"projectile actor requires a positive circle body",
		)
	}
	result := sim.Body{
		HalfWidth:  pixels(body.Radius),
		HalfHeight: pixels(body.Radius),
		Solid:      body.Solid,
	}
	if err := sim.ValidateBody(result); err != nil {
		return sim.Body{}, err
	}
	return result, nil
}

func statusMultiplier(value float64) (sim.Coord, error) {
	if !finite(value) || value <= 0 || value > 16 {
		return 0, fmt.Errorf("multiplier %.6g is outside (0, 16]", value)
	}
	return sim.Coord(math.Round(
		value * float64(sim.UnitsPerPixel),
	)), nil
}

func rgba8(values []float64) ([4]uint8, error) {
	if len(values) != 4 {
		return [4]uint8{}, fmt.Errorf("RGBA requires four channels")
	}
	var result [4]uint8
	for index, value := range values {
		if !finite(value) || value < 0 || value > 1 {
			return [4]uint8{}, fmt.Errorf(
				"channel %d is outside [0, 1]",
				index,
			)
		}
		result[index] = uint8(math.Round(value * 255))
	}
	return result, nil
}
