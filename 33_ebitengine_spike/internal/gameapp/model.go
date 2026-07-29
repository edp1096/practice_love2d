package gameapp

import (
	"fmt"
	"image/color"
	"math"
	"sort"
	"strings"

	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func (runtime *Runtime) Tick(actions ebitapp.Actions) error {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()

	if runtime.quit {
		return nil
	}
	if actions.Restart {
		if err := runtime.resetLocked(); err != nil {
			return err
		}
	}
	if actions.Pause {
		runtime.paused = !runtime.paused
		runtime.revision++
	}
	if runtime.paused {
		return nil
	}
	input := sim.Input{
		MoveX:    digitalAxis(actions.MoveX),
		MoveY:    digitalAxis(actions.MoveY),
		Attack:   actions.Attack,
		Parry:    actions.Parry,
		Dodge:    actions.Dodge,
		Interact: actions.Interact,
	}
	runtime.mergeVirtualInputLocked(&input)
	runtime.tickLocked(input)
	return nil
}

func digitalAxis(value float64) int8 {
	switch {
	case value < -0.2:
		return -1
	case value > 0.2:
		return 1
	default:
		return 0
	}
}

func clampDigital(value int) int8 {
	switch {
	case value < 0:
		return -1
	case value > 0:
		return 1
	default:
		return 0
	}
}

func (runtime *Runtime) mergeVirtualInputLocked(input *sim.Input) {
	value := func(names ...string) float64 {
		var result float64
		for _, name := range names {
			result += runtime.virtual[name].value
		}
		return result
	}
	input.MoveX = clampDigital(
		int(input.MoveX) +
			int(digitalAxis(value("right", "move_right"))) -
			int(digitalAxis(value("left", "move_left"))) +
			int(digitalAxis(value("move_x"))),
	)
	input.MoveY = clampDigital(
		int(input.MoveY) +
			int(digitalAxis(value("down", "move_down"))) -
			int(digitalAxis(value("up", "move_up"))) +
			int(digitalAxis(value("move_y"))),
	)
	input.Attack = input.Attack || runtime.virtualPressed("attack")
	input.Parry = input.Parry || runtime.virtualPressed("parry")
	input.Dodge = input.Dodge || runtime.virtualPressed("dodge")
	input.Interact = input.Interact || runtime.virtualPressed("interact")
	runtime.advanceVirtualLocked()
}

func (runtime *Runtime) virtualPressed(name string) bool {
	action, exists := runtime.virtual[name]
	return exists && action.value > 0 && action.fresh
}

func (runtime *Runtime) advanceVirtualLocked() {
	for name, action := range runtime.virtual {
		action.fresh = false
		action.remaining--
		if action.remaining <= 0 {
			delete(runtime.virtual, name)
			continue
		}
		runtime.virtual[name] = action
	}
}

func (runtime *Runtime) tickLocked(input sim.Input) {
	commands := make(map[string]sim.EntityInput)
	snapshot := runtime.simulation.Snapshot()
	entities := make(map[string]sim.EntitySnapshot, len(snapshot.Entities))
	for _, entity := range snapshot.Entities {
		entities[entity.ID] = entity
	}

	for _, metadata := range runtime.built.Presentation.Instances {
		if metadata.Chase == nil {
			continue
		}
		enemy, exists := entities[metadata.ID]
		if !exists || enemy.Dead {
			continue
		}
		target, found := runtime.chaseTargetLocked(
			metadata.Chase.TargetTag,
			entities,
		)
		if !found {
			continue
		}
		deltaX := target.Position.X - enemy.Position.X
		deltaY := target.Position.Y - enemy.Position.Y
		distanceSquared := squaredCoords(deltaX, deltaY)
		aggroRange := pixelsCoord(metadata.Chase.AggroRange)
		if distanceSquared > squaredCoords(aggroRange, 0) {
			continue
		}
		attackDistance := pixelsCoord(metadata.Chase.AttackDistance)
		if definition, exists := runtime.entityConfig(metadata.ID); exists &&
			definition.Ability != nil {
			simulationReach := definition.Ability.Reach +
				max(target.Body.HalfWidth, target.Body.HalfHeight)
			attackDistance = min(attackDistance, simulationReach)
		}
		command := sim.EntityInput{EntityID: metadata.ID}
		if distanceSquared <= squaredCoords(attackDistance, 0) {
			command.Attack = true
		} else {
			command.MoveX = signCoord(deltaX)
			command.MoveY = signCoord(deltaY)
		}
		commands[metadata.ID] = command
	}
	controlledID := ""
	for _, definition := range runtime.built.Config.Entities {
		if definition.Controlled {
			controlledID = definition.ID
			break
		}
	}
	for id := range runtime.pendingAbilities {
		if id == controlledID {
			// The controlled actor's semantic input lives in the top-level
			// fields. Adding a duplicate EntityInput would replace movement,
			// parry, dodge, and interaction in sim.resolveInput.
			input.Attack = true
			continue
		}
		command := commands[id]
		command.EntityID = id
		command.Attack = true
		commands[id] = command
	}

	ids := make([]string, 0, len(commands))
	for id := range commands {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	input.Commands = make([]sim.EntityInput, 0, len(ids))
	runtime.moving = make(map[string]bool, len(ids)+1)
	if controlledID != "" {
		runtime.moving[controlledID] =
			input.MoveX != 0 || input.MoveY != 0
	}
	for _, id := range ids {
		command := commands[id]
		runtime.moving[id] = command.MoveX != 0 || command.MoveY != 0
		input.Commands = append(input.Commands, command)
	}
	events := runtime.simulation.Tick(input)
	for _, event := range events {
		if event.Type == sim.EventAttackStarted {
			delete(runtime.pendingAbilities, event.EntityID)
		}
	}
	for _, entity := range runtime.simulation.Snapshot().Entities {
		if entity.Dead {
			delete(runtime.pendingAbilities, entity.ID)
		}
	}
	runtime.revision++
}

func pixelsCoord(value float64) sim.Coord {
	return sim.Coord(math.Round(value * float64(sim.UnitsPerPixel)))
}

func squaredCoords(x, y sim.Coord) uint64 {
	absolute := func(value sim.Coord) uint64 {
		if value < 0 {
			return uint64(-value)
		}
		return uint64(value)
	}
	absoluteX := absolute(x)
	absoluteY := absolute(y)
	return absoluteX*absoluteX + absoluteY*absoluteY
}

func (runtime *Runtime) chaseTargetLocked(
	tag string,
	entities map[string]sim.EntitySnapshot,
) (sim.EntitySnapshot, bool) {
	for _, metadata := range runtime.built.Presentation.Instances {
		if !contains(metadata.Tags, tag) {
			continue
		}
		entity, exists := entities[metadata.ID]
		if exists && !entity.Dead {
			return entity, true
		}
	}
	return sim.EntitySnapshot{}, false
}

func contains(values []string, wanted string) bool {
	for _, value := range values {
		if value == wanted {
			return true
		}
	}
	return false
}

func signCoord(value sim.Coord) int8 {
	switch {
	case value < 0:
		return -1
	case value > 0:
		return 1
	default:
		return 0
	}
}

func coordPixels(value sim.Coord) float64 {
	return float64(value) / float64(sim.UnitsPerPixel)
}

func (runtime *Runtime) View() ebitapp.View {
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()

	frame := runtime.simulation.RenderFrame()
	snapshot := runtime.simulation.Snapshot()
	flash := make(map[string]bool, len(snapshot.Entities))
	for _, entity := range snapshot.Entities {
		flash[entity.ID] = entity.FlashTicks > 0
	}

	viewportWidth := coordPixels(frame.Camera.ViewportWidth)
	viewportHeight := coordPixels(frame.Camera.ViewportHeight)
	zoom := math.Min(
		float64(ebitapp.ScreenWidth)/viewportWidth,
		float64(ebitapp.ScreenHeight)/viewportHeight,
	)
	view := ebitapp.View{
		Tick:     frame.Tick,
		Revision: runtime.revision,
		Paused:   runtime.paused,
		Quit:     runtime.quit,
		Camera: ebitapp.CameraView{
			X: coordPixels(
				frame.Camera.BaseCenter.X -
					frame.Camera.ViewportWidth/2,
			),
			Y: coordPixels(
				frame.Camera.BaseCenter.Y -
					frame.Camera.ViewportHeight/2,
			),
			ShakeX: -coordPixels(frame.Camera.ShakeOffset.X),
			ShakeY: -coordPixels(frame.Camera.ShakeOffset.Y),
			Zoom:   zoom,
		},
		World: ebitapp.WorldView{
			Width:  coordPixels(frame.Stage.MaxX - frame.Stage.MinX),
			Height: coordPixels(frame.Stage.MaxY - frame.Stage.MinY),
			Stage:  runtime.built.Presentation.StageID,
		},
		HUD: ebitapp.HUDView{
			Title: runtime.built.Presentation.StageName,
			Help:  "WASD 이동 · Space 공격 · C 패링 · X 회피 · E 대화",
		},
	}
	if runtime.paused {
		view.HUD.Status = fmt.Sprintf("일시정지 · tick %d", frame.Tick)
	} else {
		view.HUD.Status = fmt.Sprintf("tick %d · Ebitengine", frame.Tick)
	}
	for _, wall := range frame.Walls {
		rect := wall.Rect
		view.Walls = append(view.Walls, ebitapp.RectView{
			X:      coordPixels(rect.MinX),
			Y:      coordPixels(rect.MinY),
			Width:  coordPixels(rect.MaxX - rect.MinX),
			Height: coordPixels(rect.MaxY - rect.MinY),
			Color:  color.RGBA{R: 57, G: 69, B: 76, A: 255},
		})
	}
	positions := make(map[string]sim.Vec, len(frame.Actors))
	for _, actor := range frame.Actors {
		positions[actor.ID] = actor.Position
		if actor.Dead {
			continue
		}
		metadata, _ := runtime.metadata(actor.ID)
		direction := facingDirection(actor.Facing)
		state := "idle_" + direction
		if actor.Attack != sim.AttackIdle {
			state = "attack_" + direction
		} else if runtime.moving[actor.ID] {
			state = "move_" + direction
		}
		view.Entities = append(view.Entities, ebitapp.EntityView{
			ID:        actor.ID,
			SpriteID:  metadata.SpriteID,
			State:     state,
			X:         coordPixels(actor.Position.X),
			Y:         coordPixels(actor.Position.Y),
			Radius:    coordPixels(actor.Body.HalfWidth),
			FacingX:   coordPixels(actor.Facing.X),
			FacingY:   coordPixels(actor.Facing.Y),
			Layer:     10,
			Health:    float64(actor.Health),
			MaxHealth: float64(actor.MaxHealth),
			Flash:     flash[actor.ID],
		})
		if actor.Attack == sim.AttackActive &&
			metadata.SpriteID == "sprite.hero" {
			angle := math.Atan2(
				coordPixels(actor.Facing.Y),
				coordPixels(actor.Facing.X),
			)
			view.Effects = append(view.Effects, ebitapp.EffectView{
				Kind:     "slash",
				X:        coordPixels(actor.Position.X) + math.Cos(angle)*31,
				Y:        coordPixels(actor.Position.Y) + math.Sin(angle)*31,
				Rotation: angle,
				Scale:    1.2,
				Opacity:  0.9,
			})
		}
	}
	for _, event := range snapshot.Events {
		position, exists := positions[event.TargetID]
		if !exists {
			continue
		}
		switch event.Type {
		case sim.EventAttackParried:
			scale := 1.0
			if event.Perfect {
				scale = 1.35
			}
			view.Effects = append(view.Effects, ebitapp.EffectView{
				Kind:    "parry",
				X:       coordPixels(position.X),
				Y:       coordPixels(position.Y),
				Scale:   scale,
				Opacity: 1,
			})
		case sim.EventDamageApplied:
			view.Effects = append(view.Effects, ebitapp.EffectView{
				Kind:    "hit",
				X:       coordPixels(position.X),
				Y:       coordPixels(position.Y),
				Scale:   1,
				Opacity: 0.9,
			})
		}
	}
	if frame.Dialogue.Active {
		view.HUD.Dialogue = frame.Dialogue.Speaker + "\n" +
			frame.Dialogue.Text
	}
	for _, quest := range frame.Quests {
		if quest.Status == sim.QuestInactive {
			continue
		}
		label := "진행"
		if quest.Status == sim.QuestCompleted {
			label = "완료"
		}
		view.HUD.Quest = fmt.Sprintf(
			"%s [%s] %d/%d",
			quest.ID,
			label,
			quest.Progress,
			quest.Required,
		)
		break
	}
	return view
}

func facingDirection(facing sim.Vec) string {
	x, y := coordPixels(facing.X), coordPixels(facing.Y)
	if math.Abs(x) >= math.Abs(y) {
		if x < 0 {
			return "left"
		}
		return "right"
	}
	if y < 0 {
		return "up"
	}
	return "down"
}

func normalizeActionName(value string) string {
	return strings.ToLower(strings.TrimSpace(value))
}
