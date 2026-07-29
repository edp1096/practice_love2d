package sim

import (
	"fmt"
	"math"
	"sort"
)

const sweepFractionScale int64 = 1_000_000_000

type projectileCollisionKind uint8

const (
	projectileCollisionActor projectileCollisionKind = iota
	projectileCollisionWall
)

type projectileCollision struct {
	kind     projectileCollisionKind
	id       string
	fraction int64
	target   *entityRuntime
}

func (s *Simulation) activateAbility(
	source *entityRuntime,
	ability *AbilityConfig,
) {
	if source == nil || ability == nil || ability.ProjectileID == "" {
		return
	}
	if err := s.spawnProjectile(source, ability); err != nil {
		s.interruptAttack(source, err.Error())
	}
}

func (s *Simulation) spawnProjectile(
	source *entityRuntime,
	ability *AbilityConfig,
) error {
	definition, exists := s.projectileDefinitions[ability.ProjectileID]
	if !exists {
		return fmt.Errorf("unknown projectile %q", ability.ProjectileID)
	}
	direction := normalize(source.facing)
	if direction == (Vec{}) {
		return fmt.Errorf("projectile %q source has no facing", definition.ID)
	}
	position := Vec{
		X: source.position.X +
			direction.X*definition.SpawnOffset/UnitsPerPixel,
		Y: source.position.Y +
			direction.Y*definition.SpawnOffset/UnitsPerPixel,
	}
	if !containsRect(
		s.config.StageBounds,
		entityRect(position, definition.Body),
	) {
		return fmt.Errorf("projectile %q spawns outside stage", definition.ID)
	}
	s.projectileSequence++
	id := fmt.Sprintf(
		"%s.projectile.%d",
		source.config.ID,
		s.projectileSequence,
	)
	projectile := &projectileRuntime{
		id:           id,
		definitionID: definition.ID,
		abilityID:    ability.ID,
		sourceID:     source.config.ID,
		team:         source.config.Team,
		position:     position,
		previous:     position,
		direction:    direction,
		remaining:    definition.LifetimeTicks,
		hitTargets:   make(map[string]struct{}),
	}
	s.projectiles[id] = projectile
	s.projectileOrder = append(s.projectileOrder, id)
	sort.Strings(s.projectileOrder)
	s.emit(Event{
		Type:         EventProjectileSpawned,
		EntityID:     id,
		SourceID:     source.config.ID,
		AbilityID:    ability.ID,
		ProjectileID: definition.ID,
	})
	return nil
}

func (s *Simulation) advanceProjectiles() {
	for _, id := range append([]string(nil), s.projectileOrder...) {
		projectile := s.projectiles[id]
		if projectile == nil {
			continue
		}
		definition := s.projectileDefinitions[projectile.definitionID]
		projectile.previous = projectile.position
		delta := Vec{
			X: projectile.direction.X *
				definition.SpeedPerTick / UnitsPerPixel,
			Y: projectile.direction.Y *
				definition.SpeedPerTick / UnitsPerPixel,
		}
		collisions := s.projectileCollisions(
			projectile,
			definition,
			delta,
		)
		travelFraction := sweepFractionScale
		consumed := false
		for _, collision := range collisions {
			if collision.kind == projectileCollisionWall {
				travelFraction = collision.fraction
				if definition.DestroyOnWall || collision.id == "stage.bounds" {
					projectile.position = interpolateSweep(
						projectile.previous,
						delta,
						travelFraction,
					)
					s.emit(Event{
						Type:         EventProjectileBlocked,
						EntityID:     projectile.id,
						SourceID:     projectile.sourceID,
						AbilityID:    projectile.abilityID,
						ProjectileID: projectile.definitionID,
						TargetID:     collision.id,
					})
					s.removeProjectile(projectile.id)
					consumed = true
				}
				break
			}
			if collision.fraction >= travelFraction {
				continue
			}
			if err := s.projectileHit(
				projectile,
				definition,
				collision,
				delta,
			); err != nil {
				s.removeProjectile(projectile.id)
				consumed = true
				break
			}
			if projectile.hits > definition.Pierce {
				travelFraction = collision.fraction
				projectile.position = interpolateSweep(
					projectile.previous,
					delta,
					travelFraction,
				)
				s.removeProjectile(projectile.id)
				consumed = true
				break
			}
		}
		if consumed {
			continue
		}
		projectile.position = interpolateSweep(
			projectile.previous,
			delta,
			travelFraction,
		)
		projectile.remaining = countdown(projectile.remaining)
		if projectile.remaining == 0 {
			s.emit(Event{
				Type:         EventProjectileExpired,
				EntityID:     projectile.id,
				SourceID:     projectile.sourceID,
				AbilityID:    projectile.abilityID,
				ProjectileID: projectile.definitionID,
			})
			s.removeProjectile(projectile.id)
		}
	}
}

func (s *Simulation) projectileHit(
	projectile *projectileRuntime,
	definition ProjectileConfig,
	collision projectileCollision,
	delta Vec,
) (err error) {
	target := collision.target
	if target == nil || target.dead {
		return fmt.Errorf("projectile target %q is unavailable", collision.id)
	}
	targetBefore := cloneEntityRuntime(target)
	hitstopBefore := s.hitstop
	cameraBefore := s.camera
	dialogueBefore := s.dialogue
	questsBefore := s.cloneQuestRuntime()
	eventCount := len(s.lastEvents)
	defer func() {
		if recovered := recover(); recovered != nil {
			err = fmt.Errorf("projectile transaction panicked: %v", recovered)
		}
		if err == nil {
			return
		}
		*target = *targetBefore
		s.hitstop = hitstopBefore
		s.camera = cameraBefore
		s.dialogue = dialogueBefore
		s.restoreQuestRuntime(questsBefore)
		s.lastEvents = s.lastEvents[:eventCount]
	}()

	if _, duplicate := projectile.hitTargets[target.config.ID]; duplicate {
		return fmt.Errorf("projectile target %q was already hit", target.config.ID)
	}
	projectile.hitTargets[target.config.ID] = struct{}{}
	projectile.hits++
	impactPosition := interpolateSweep(
		projectile.previous,
		delta,
		collision.fraction,
	)
	if err := s.applyImpact(
		projectile.sourceID,
		impactPosition,
		projectile.direction,
		target.config.ID,
		target,
		projectile.abilityID,
		definition.Impact,
		false,
	); err != nil {
		return err
	}
	s.emit(Event{
		Type:         EventProjectileHit,
		EntityID:     projectile.id,
		SourceID:     projectile.sourceID,
		TargetID:     target.config.ID,
		AbilityID:    projectile.abilityID,
		ProjectileID: projectile.definitionID,
		Amount:       projectile.hits,
	})
	return nil
}

func (s *Simulation) projectileCollisions(
	projectile *projectileRuntime,
	definition ProjectileConfig,
	delta Vec,
) []projectileCollision {
	result := make([]projectileCollision, 0)
	blockerFraction := sweepFractionScale + 1
	blockerID := ""
	if fraction, hit := sweepExitBounds(
		projectile.position,
		definition.Body,
		delta,
		s.config.StageBounds,
	); hit {
		blockerFraction = fraction
		blockerID = "stage.bounds"
	}
	if definition.DestroyOnWall {
		for _, wall := range s.config.Walls {
			fraction, hit := sweptBodyFraction(
				projectile.position,
				definition.Body,
				delta,
				wallVertices(wall),
			)
			if hit && (fraction < blockerFraction ||
				(fraction == blockerFraction && wall.ID < blockerID)) {
				blockerFraction = fraction
				blockerID = wall.ID
			}
		}
		for _, entityID := range s.entityOrder {
			entity := s.entities[entityID]
			if entity.dead || !entity.config.Body.Solid ||
				entity.config.Team != "" ||
				entity.config.ID == projectile.sourceID {
				continue
			}
			fraction, hit := sweptBodyFraction(
				projectile.position,
				definition.Body,
				delta,
				rectVertices(entityRect(entity.position, entity.config.Body)),
			)
			if hit && (fraction < blockerFraction ||
				(fraction == blockerFraction && entityID < blockerID)) {
				blockerFraction = fraction
				blockerID = entityID
			}
		}
	}
	if blockerID != "" {
		result = append(result, projectileCollision{
			kind:     projectileCollisionWall,
			id:       blockerID,
			fraction: blockerFraction,
		})
	}
	for _, targetID := range s.entityOrder {
		target := s.entities[targetID]
		if target.dead || target.config.Team == "" ||
			target.config.Team == projectile.team ||
			target.config.ID == projectile.sourceID {
			continue
		}
		if _, duplicate := projectile.hitTargets[targetID]; duplicate {
			continue
		}
		fraction, hit := sweptBodyFraction(
			projectile.position,
			definition.Body,
			delta,
			rectVertices(entityRect(target.position, target.config.Body)),
		)
		if !hit || fraction >= blockerFraction {
			continue
		}
		result = append(result, projectileCollision{
			kind:     projectileCollisionActor,
			id:       targetID,
			fraction: fraction,
			target:   target,
		})
	}
	sort.Slice(result, func(left, right int) bool {
		if result[left].fraction != result[right].fraction {
			return result[left].fraction < result[right].fraction
		}
		if result[left].kind != result[right].kind {
			return result[left].kind == projectileCollisionWall
		}
		return result[left].id < result[right].id
	})
	return result
}

func (s *Simulation) removeProjectile(id string) {
	delete(s.projectiles, id)
	s.projectileOrder = removeSortedID(s.projectileOrder, id)
}

func interpolateSweep(start Vec, delta Vec, fraction int64) Vec {
	fraction = max(int64(0), min(sweepFractionScale, fraction))
	return Vec{
		X: start.X + Coord(int64(delta.X)*fraction/sweepFractionScale),
		Y: start.Y + Coord(int64(delta.Y)*fraction/sweepFractionScale),
	}
}

func sweptBodyFraction(
	start Vec,
	body Body,
	delta Vec,
	staticPoints []Vec,
) (int64, bool) {
	if len(staticPoints) < 3 {
		return 0, false
	}
	moving := rectVertices(entityRect(start, body))
	axes := []Vec{
		{X: UnitsPerPixel},
		{Y: UnitsPerPixel},
	}
	for index := range staticPoints {
		next := (index + 1) % len(staticPoints)
		edge := Vec{
			X: staticPoints[next].X - staticPoints[index].X,
			Y: staticPoints[next].Y - staticPoints[index].Y,
		}
		if edge != (Vec{}) {
			axes = append(axes, Vec{X: -edge.Y, Y: edge.X})
		}
	}
	enter, exit := 0.0, 1.0
	for _, axis := range axes {
		movingMin, movingMax := projectedRange(moving, axis)
		staticMin, staticMax := projectedRange(staticPoints, axis)
		velocity := float64(dotVec(delta, axis))
		if velocity == 0 {
			if movingMax < staticMin || staticMax < movingMin {
				return 0, false
			}
			continue
		}
		first := (float64(staticMin) - float64(movingMax)) / velocity
		last := (float64(staticMax) - float64(movingMin)) / velocity
		if first > last {
			first, last = last, first
		}
		enter = math.Max(enter, first)
		exit = math.Min(exit, last)
		if enter > exit {
			return 0, false
		}
	}
	if exit < 0 || enter > 1 {
		return 0, false
	}
	enter = math.Max(0, enter)
	fraction := int64(math.Ceil(
		enter*float64(sweepFractionScale) - 1e-9,
	))
	return max(int64(0), min(sweepFractionScale, fraction)), true
}

func sweepExitBounds(
	start Vec,
	body Body,
	delta Vec,
	bounds Rect,
) (int64, bool) {
	allowed := Rect{
		MinX: bounds.MinX + body.HalfWidth,
		MinY: bounds.MinY + body.HalfHeight,
		MaxX: bounds.MaxX - body.HalfWidth,
		MaxY: bounds.MaxY - body.HalfHeight,
	}
	end := Vec{X: start.X + delta.X, Y: start.Y + delta.Y}
	if end.X >= allowed.MinX && end.X <= allowed.MaxX &&
		end.Y >= allowed.MinY && end.Y <= allowed.MaxY {
		return 0, false
	}
	fraction := sweepFractionScale
	for _, axis := range []struct {
		start Coord
		delta Coord
		min   Coord
		max   Coord
	}{
		{start.X, delta.X, allowed.MinX, allowed.MaxX},
		{start.Y, delta.Y, allowed.MinY, allowed.MaxY},
	} {
		if axis.delta > 0 && axis.start+axis.delta > axis.max {
			candidate := int64(axis.max-axis.start) *
				sweepFractionScale / int64(axis.delta)
			fraction = min(fraction, candidate)
		}
		if axis.delta < 0 && axis.start+axis.delta < axis.min {
			candidate := int64(axis.min-axis.start) *
				sweepFractionScale / int64(axis.delta)
			fraction = min(fraction, candidate)
		}
	}
	return max(int64(0), fraction), true
}

func projectedRange(points []Vec, axis Vec) (int64, int64) {
	minimum := dotVec(points[0], axis)
	maximum := minimum
	for _, point := range points[1:] {
		value := dotVec(point, axis)
		minimum = min(minimum, value)
		maximum = max(maximum, value)
	}
	return minimum, maximum
}

func dotVec(left Vec, right Vec) int64 {
	return int64(left.X)*int64(right.X) +
		int64(left.Y)*int64(right.Y)
}

func wallVertices(wall Wall) []Vec {
	if len(wall.Points) != 0 {
		return wall.Points
	}
	return rectVertices(wall.Rect)
}

func rectVertices(rect Rect) []Vec {
	return []Vec{
		{X: rect.MinX, Y: rect.MinY},
		{X: rect.MaxX, Y: rect.MinY},
		{X: rect.MaxX, Y: rect.MaxY},
		{X: rect.MinX, Y: rect.MaxY},
	}
}

func cloneProjectileDefinitions(
	source map[string]ProjectileConfig,
) map[string]ProjectileConfig {
	result := make(map[string]ProjectileConfig, len(source))
	for id, definition := range source {
		result[id] = definition
	}
	return result
}

func cloneStatusDefinitions(
	source map[string]StatusConfig,
) map[string]StatusConfig {
	result := make(map[string]StatusConfig, len(source))
	for id, definition := range source {
		result[id] = definition
	}
	return result
}

func cloneProjectiles(
	source map[string]*projectileRuntime,
) map[string]*projectileRuntime {
	result := make(map[string]*projectileRuntime, len(source))
	for id, projectile := range source {
		copy := *projectile
		copy.hitTargets = make(map[string]struct{}, len(projectile.hitTargets))
		for targetID := range projectile.hitTargets {
			copy.hitTargets[targetID] = struct{}{}
		}
		result[id] = &copy
	}
	return result
}
