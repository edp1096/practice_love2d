package gameapp

import (
	"fmt"
	"image/color"
	"math"
	"sort"
	"strings"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func (runtime *Runtime) Tick(actions ebitapp.Actions) error {
	runtime.mu.Lock()
	if runtime.quit {
		runtime.mu.Unlock()
		return nil
	}
	if runtime.automationPaused {
		runtime.mu.Unlock()
		return nil
	}
	if runtime.campaign.Snapshot().Mode != campaign.ModePlaying {
		command, err := runtime.consumeFlowActionsLocked(actions)
		runtime.mu.Unlock()
		if err != nil {
			return err
		}
		return runtime.executeFlowCommand(command)
	}
	defer runtime.mu.Unlock()

	if err := runtime.publishPendingEquipmentRebuildLocked(); err != nil {
		return err
	}
	if actions.Pause {
		return runtime.pauseFlowLocked()
	}
	if actions.Restart {
		if err := runtime.resetLocked(); err != nil {
			return err
		}
	}
	if runtime.dialogue != nil {
		switch {
		case actions.DialogueCancel:
			_, err := runtime.cancelDialogueLocked()
			return err
		case actions.DialogueConfirm:
			_, err := runtime.confirmDialogueLocked()
			return err
		case actions.DialogueUp != actions.DialogueDown:
			delta := 1
			if actions.DialogueUp {
				delta = -1
			}
			_, err := runtime.moveDialogueSelectionLocked(delta)
			return err
		default:
			return nil
		}
	}
	if runtime.activeShopID != "" {
		switch {
		case actions.ShopCancel:
			_, err := runtime.closeShopLocked()
			return err
		case actions.ShopBuy:
			itemID, err := runtime.selectedShopItemLocked()
			if err != nil {
				runtime.shopStatus = err.Error()
				runtime.revision++
				return nil
			}
			if _, err := runtime.buyShopItemLocked(itemID, 1); err != nil {
				runtime.shopStatus = err.Error()
				runtime.revision++
			}
			return nil
		case actions.ShopSell:
			itemID, err := runtime.selectedShopItemLocked()
			if err != nil {
				runtime.shopStatus = err.Error()
				runtime.revision++
				return nil
			}
			if _, err := runtime.sellShopItemLocked(itemID, 1); err != nil {
				runtime.shopStatus = err.Error()
				runtime.revision++
			}
			return nil
		case actions.ShopUp != actions.ShopDown:
			delta := 1
			if actions.ShopUp {
				delta = -1
			}
			_, err := runtime.moveShopSelectionLocked(delta)
			return err
		default:
			return nil
		}
	}
	if runtime.inventoryOpen {
		switch {
		case actions.InventoryCancel || actions.InventoryToggle:
			runtime.closeInventoryLocked()
			return nil
		case actions.InventoryActivate:
			if err := runtime.activateInventorySelectionLocked(); err != nil {
				runtime.setInventoryFailureLocked(err)
			}
			return nil
		case actions.InventoryUnequip:
			if err := runtime.unequipInventorySelectionLocked(); err != nil {
				runtime.setInventoryFailureLocked(err)
			}
			return nil
		case actions.InventoryUp != actions.InventoryDown:
			delta := 1
			if actions.InventoryUp {
				delta = -1
			}
			if err := runtime.moveInventorySelectionLocked(delta); err != nil {
				runtime.setInventoryFailureLocked(err)
			}
			return nil
		default:
			return nil
		}
	}
	if actions.InventoryToggle {
		return runtime.openInventoryLocked()
	}
	legacyDialogue := runtime.simulation.Snapshot().Dialogue.Active
	if legacyDialogue {
		if actions.DialogueConfirm || actions.DialogueCancel {
			actions.Interact = true
		} else {
			return nil
		}
	}
	input := sim.Input{
		MoveX:    digitalAxis(actions.MoveX),
		MoveY:    digitalAxis(actions.MoveY),
		Attack:   actions.Attack,
		Parry:    actions.Parry,
		Dodge:    actions.Dodge,
		Jump:     actions.Jump,
		Interact: actions.Interact,
	}
	switch {
	case actions.Technique:
		input.AbilityID = runtime.controlledAbilityForInputLocked("technique")
	case actions.Special:
		input.AbilityID = runtime.controlledAbilityForInputLocked("special")
	}
	originalVirtual := cloneVirtualActions(runtime.virtual)
	runtime.mergeVirtualInputLocked(&input)
	if err := runtime.tickLocked(input); err != nil {
		runtime.virtual = originalVirtual
		return err
	}
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
	switch {
	case runtime.virtualPressed("technique"):
		input.AbilityID = runtime.controlledAbilityForInputLocked("technique")
	case runtime.virtualPressed("special"):
		input.AbilityID = runtime.controlledAbilityForInputLocked("special")
	}
	input.Parry = input.Parry || runtime.virtualPressed("parry")
	input.Dodge = input.Dodge || runtime.virtualPressed("dodge")
	input.Jump = input.Jump || runtime.virtualPressed("jump")
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

func (runtime *Runtime) tickLocked(input sim.Input) error {
	if runtime.campaign.Snapshot().Mode == campaign.ModePlaying {
		if err := runtime.publishPendingEquipmentRebuildLocked(); err != nil {
			return err
		}
	}
	// Authored dialogue and shops are modal: raw world steps remain no-ops
	// until an explicit modal operation resolves them.
	if runtime.dialogue != nil ||
		runtime.activeShopID != "" ||
		runtime.inventoryOpen {
		return nil
	}
	checkpoint := runtime.checkpointLocked()
	if err := runtime.detachMutableLocked(checkpoint); err != nil {
		return err
	}
	if len(runtime.pendingRemovals) != 0 {
		// Removal wins over interaction on its flush tick. This prevents a
		// queued speaker from becoming a new strong dialogue reference after
		// Entity.remove has already acknowledged the request.
		input.Interact = false
		for index := range input.Commands {
			input.Commands[index].Interact = false
		}
	}
	commands := make(map[string]sim.EntityInput)
	snapshot := runtime.simulation.Snapshot()
	entities := make(map[string]sim.EntitySnapshot, len(snapshot.Entities))
	for _, entity := range snapshot.Entities {
		entities[entity.ID] = entity
	}
	if input.Interact && len(runtime.pendingRemovals) == 0 {
		handled, err := runtime.handleDomainInteractionLocked(snapshot)
		if err != nil {
			runtime.restoreCheckpointLocked(checkpoint)
			return err
		}
		if handled {
			// The domain interaction consumed this semantic edge. The legacy
			// simulation dialogue/quest layer remains available only for Maker
			// preview compatibility and cannot duplicate the authored action.
			input.Interact = false
			if runtime.campaign.Snapshot().Mode != campaign.ModePlaying {
				runtime.revision++
				return nil
			}
		}
	}

	for _, metadata := range runtime.allMetadataLocked() {
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
			definition.PrimaryAbility() != nil {
			simulationReach := definition.PrimaryAbility().Reach +
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
	for id, abilityID := range runtime.pendingAbilities {
		if id == controlledID {
			// The controlled actor's semantic input lives in the top-level
			// fields. Adding a duplicate EntityInput would replace movement,
			// parry, dodge, and interaction in sim.resolveInput.
			input.AbilityID = abilityID
			continue
		}
		command := commands[id]
		command.EntityID = id
		command.AbilityID = abilityID
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
	if err := runtime.applyObjectiveEventsLocked(events); err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return err
	}
	if err := runtime.reconcileEquipmentChangeLocked(
		checkpoint.campaign,
		true,
	); err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return err
	}
	if runtime.controlledActorKilledLocked(events) {
		if err := runtime.enterGameOverLocked(); err != nil {
			runtime.restoreCheckpointLocked(checkpoint)
			return err
		}
	}
	for _, event := range events {
		if event.Type == sim.EventAttackStarted {
			if queued := runtime.pendingAbilities[event.EntityID]; queued == event.AbilityID {
				delete(runtime.pendingAbilities, event.EntityID)
			}
		}
	}
	for _, entity := range runtime.simulation.Snapshot().Entities {
		if entity.Dead {
			delete(runtime.pendingAbilities, entity.ID)
		}
	}
	if err := runtime.flushPendingRemovalsLocked(); err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return err
	}
	if runtime.campaign.Snapshot().Mode == campaign.ModePlaying {
		if err := runtime.updatePortalsLocked(); err != nil {
			runtime.restoreCheckpointLocked(checkpoint)
			return err
		}
	}
	runtime.publishAudioEventsLocked(events)
	runtime.revision++
	return nil
}

func (runtime *Runtime) controlledAbilityForInputLocked(input string) string {
	for index := range runtime.built.Config.Entities {
		entity := &runtime.built.Config.Entities[index]
		if !entity.Controlled {
			continue
		}
		ability := entity.Combat.AbilityForInput(input)
		if ability != nil {
			return ability.ID
		}
		return ""
	}
	return ""
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
	for _, metadata := range runtime.allMetadataLocked() {
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
	stats := make(map[string]sim.RPGStatsConfig, len(snapshot.Entities))
	for _, entity := range snapshot.Entities {
		flash[entity.ID] = entity.FlashTicks > 0
		stats[entity.ID] = entity.Stats
	}
	controlled := make(map[string]bool, len(runtime.built.Config.Entities))
	for _, entity := range runtime.built.Config.Entities {
		controlled[entity.ID] = entity.Controlled
	}

	viewportWidth := coordPixels(frame.Camera.ViewportWidth)
	viewportHeight := coordPixels(frame.Camera.ViewportHeight)
	zoom := math.Min(
		float64(ebitapp.ScreenWidth)/viewportWidth,
		float64(ebitapp.ScreenHeight)/viewportHeight,
	)
	showStats, help := runtime.hudPresentationLocked()
	view := ebitapp.View{
		Tick:             frame.Tick,
		Revision:         runtime.revision,
		AutomationPaused: runtime.automationPaused,
		Quit:             runtime.quit,
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
			Background: presentationColor(
				runtime.built.Presentation.Background,
			),
		},
		HUD: ebitapp.HUDView{
			Title:     runtime.built.Presentation.StageName,
			Help:      help,
			ShowStats: showStats,
		},
	}
	if music, exists := runtime.built.Presentation.Audio.Music(
		runtime.built.Presentation.StageID,
	); exists {
		view.Audio.MusicAssetID = music.AssetID
		view.Audio.MusicVolume = music.Volume
	}
	view.Audio.Cues = make(
		[]ebitapp.AudioCueView,
		len(runtime.audioCues),
	)
	for index, cue := range runtime.audioCues {
		view.Audio.Cues[index] = ebitapp.AudioCueView{
			Sequence: cue.sequence,
			Event:    cue.event,
			AssetID:  cue.assetID,
			Volume:   cue.volume,
		}
	}
	view.Tilemap = tilemapView(runtime.built.Presentation.Tilemap)
	if runtime.automationPaused {
		view.HUD.Status = fmt.Sprintf("일시정지 · tick %d", frame.Tick)
	} else {
		view.HUD.Status = fmt.Sprintf("tick %d · Ebitengine", frame.Tick)
	}
	view.Flow = runtime.flowViewLocked()
	for _, wall := range frame.Walls {
		rect := wall.Rect
		points := make([]ebitapp.PointView, len(wall.Points))
		for index, point := range wall.Points {
			points[index] = ebitapp.PointView{
				X: coordPixels(point.X),
				Y: coordPixels(point.Y),
			}
		}
		view.Walls = append(view.Walls, ebitapp.RectView{
			X:      coordPixels(rect.MinX),
			Y:      coordPixels(rect.MinY),
			Width:  coordPixels(rect.MaxX - rect.MinX),
			Height: coordPixels(rect.MaxY - rect.MinY),
			Color:  color.RGBA{R: 57, G: 69, B: 76, A: 255},
			Points: points,
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
		entityView := ebitapp.EntityView{
			ID:            actor.ID,
			Controlled:    controlled[actor.ID],
			SpriteID:      metadata.SpriteID,
			State:         state,
			AnimationTick: snapshot.WorldTick,
			SpriteScale:   metadata.SpriteScale,
			SpriteTint:    presentationColor(metadata.SpriteTint),
			SpriteTintSet: metadata.SpriteTintSet,
			X:             coordPixels(actor.Position.X),
			Y:             coordPixels(actor.Position.Y),
			Radius:        coordPixels(actor.Body.HalfWidth),
			Width:         coordPixels(actor.Body.HalfWidth * 2),
			Height:        coordPixels(actor.Body.HalfHeight * 2),
			FacingX:       coordPixels(actor.Facing.X),
			FacingY:       coordPixels(actor.Facing.Y),
			Layer:         10,
			Health:        float64(actor.Health),
			MaxHealth:     float64(actor.MaxHealth),
			Attack:        stats[actor.ID].Attack,
			Defense:       stats[actor.ID].Defense,
			MoveSpeed: coordPixels(
				stats[actor.ID].MoveSpeed,
			),
			Flash: flash[actor.ID],
			Tint:  statusTint(actor.Statuses),
		}
		if entityView.Controlled {
			// The HUD reads the same effective snapshot consumed by combat,
			// never a separately re-derived presentation value.
			view.HUD.Attack = entityView.Attack
			view.HUD.Defense = entityView.Defense
			view.HUD.MoveSpeed = entityView.MoveSpeed
		}
		if actor.Attack != sim.AttackIdle {
			entityView.AnimationTick = uint64(max(0, actor.AttackTicks))
		}
		if metadata.Shape != nil {
			entityView.Shape = metadata.Shape.Kind
			entityView.Tint = color.RGBA{
				R: metadata.Shape.Color[0],
				G: metadata.Shape.Color[1],
				B: metadata.Shape.Color[2],
				A: metadata.Shape.Color[3],
			}
			entityView.Outline = color.RGBA{
				R: metadata.Shape.Outline[0],
				G: metadata.Shape.Outline[1],
				B: metadata.Shape.Outline[2],
				A: metadata.Shape.Outline[3],
			}
		}
		view.Entities = append(view.Entities, entityView)
		if actor.Attack == sim.AttackActive {
			visual, exists := runtime.built.Presentation.AbilityVisual(
				actor.AbilityID,
			)
			if !exists {
				continue
			}
			angle := math.Atan2(
				coordPixels(actor.Facing.Y),
				coordPixels(actor.Facing.X),
			)
			distance := visual.Distance
			if distance == 0 {
				distance = entityView.Radius * 0.55
			}
			view.Effects = append(view.Effects, ebitapp.EffectView{
				Kind:    "ability",
				AssetID: visual.AssetID,
				X: coordPixels(actor.Position.X) +
					math.Cos(angle)*distance,
				Y: coordPixels(actor.Position.Y) +
					math.Sin(angle)*distance,
				Rotation: angle + visual.RotationOffset,
				Scale:    visual.Scale,
				Opacity:  0.95,
			})
		}
	}
	for _, projectile := range frame.Projectiles {
		view.Entities = append(view.Entities, ebitapp.EntityView{
			ID:      projectile.ID,
			State:   "projectile",
			X:       coordPixels(projectile.Position.X),
			Y:       coordPixels(projectile.Position.Y),
			Radius:  coordPixels(projectile.Body.HalfWidth),
			FacingX: coordPixels(projectile.Direction.X),
			FacingY: coordPixels(projectile.Direction.Y),
			Layer:   20,
			Tint: color.RGBA{
				R: projectile.Tint[0],
				G: projectile.Tint[1],
				B: projectile.Tint[2],
				A: projectile.Tint[3],
			},
		})
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
	dialogue, dialogueErr := runtime.dialogueStateLocked()
	if dialogueErr != nil {
		message := "대화 오류: " + dialogueErr.Error()
		view.Dialogue = ebitapp.DialogueView{
			Active:  true,
			Speaker: "System",
			Text:    message,
			Choices: []ebitapp.DialogueChoiceView{},
		}
		view.HUD.Dialogue = message
	} else if dialogue.Active {
		view.Dialogue = ebitapp.DialogueView{
			Active:        true,
			Speaker:       dialogue.Speaker,
			Text:          dialogue.Text,
			SelectedIndex: dialogue.SelectedIndex,
			Choices: make(
				[]ebitapp.DialogueChoiceView,
				len(dialogue.Choices),
			),
		}
		for index, choice := range dialogue.Choices {
			view.Dialogue.Choices[index] = ebitapp.DialogueChoiceView{
				ID:   choice.ID,
				Text: choice.Text,
			}
		}
		view.HUD.Dialogue = dialogue.Speaker + "\n" + dialogue.Text
	}
	shop, shopErr := runtime.shopStateLocked()
	if shopErr != nil {
		if runtime.activeShopID != "" {
			view.Shop = ebitapp.ShopView{
				Active:        true,
				Name:          "Shop error",
				Offers:        []ebitapp.ShopOfferView{},
				SelectedIndex: -1,
				Status:        shopErr.Error(),
			}
		}
	} else if shop.Active {
		view.Shop = ebitapp.ShopView{
			Active:        true,
			Name:          shop.Name,
			Currency:      shop.Balance,
			Offers:        make([]ebitapp.ShopOfferView, len(shop.Offers)),
			SelectedIndex: shop.SelectedIndex,
			Status:        shop.Status,
		}
		for index, offer := range shop.Offers {
			presentation := ebitapp.ShopOfferView{
				ID:      offer.ItemID,
				Name:    offer.Name,
				Owned:   offer.Owned,
				CanBuy:  offer.CanBuy,
				CanSell: offer.CanSell,
			}
			if item, exists := runtime.contentRules.Item(
				offer.ItemID,
			); exists {
				presentation.ModifierSummary =
					equipmentModifierSummary(item.Equipment)
			}
			if offer.BuyPrice != nil {
				presentation.BuyPrice = *offer.BuyPrice
			}
			if offer.SellPrice != nil {
				presentation.SellPrice = *offer.SellPrice
			}
			view.Shop.Offers[index] = presentation
		}
	}
	inventory, inventoryErr := runtime.inventoryViewLocked()
	if inventoryErr != nil {
		if runtime.inventoryOpen {
			view.Inventory = ebitapp.InventoryView{
				Active:        true,
				Title:         "소지품 오류",
				Items:         []ebitapp.InventoryItemView{},
				SelectedIndex: -1,
				Status:        inventoryErr.Error(),
			}
		}
	} else {
		view.Inventory = inventory
	}
	campaignState := runtime.campaign.Snapshot()
	view.HUD.Currency = campaignState.Currency
	for _, quest := range campaignState.Quests {
		if quest.Status == campaign.QuestInactive {
			continue
		}
		label := "진행"
		if quest.Status == campaign.QuestCompleted {
			label = "완료"
		}
		progress := int64(0)
		required := 0
		for _, objective := range quest.Objectives {
			progress += objective.Count
		}
		if rule, exists := runtime.contentRules.Quest(quest.ID); exists {
			for _, objective := range rule.Objectives {
				required += objective.Count
			}
		}
		view.HUD.Quest = fmt.Sprintf(
			"%s [%s] %d/%d",
			quest.ID,
			label,
			progress,
			required,
		)
		break
	}
	if view.HUD.Quest == "" {
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
	}
	return view
}

func (runtime *Runtime) hudPresentationLocked() (bool, string) {
	parts := []string{}
	showStats := false
	for _, entity := range runtime.built.Config.Entities {
		if !entity.Controlled {
			continue
		}
		showStats = entity.Stats != nil
		if entity.Platformer != nil {
			parts = append(parts, "A/D 이동", "W/↑ 점프")
		} else if entity.MovePerTick > 0 {
			parts = append(parts, "WASD 이동")
		}
		for _, binding := range []struct {
			input string
			label string
		}{
			{input: "attack", label: "Space 공격"},
			{input: "special", label: "F 특수"},
			{input: "technique", label: "Q 기술"},
		} {
			if entity.Combat.AbilityForInput(binding.input) != nil {
				parts = append(parts, binding.label)
			}
		}
		if entity.Parry != nil {
			parts = append(parts, "C 패링")
		}
		if entity.Dodge != nil {
			parts = append(parts, "X 회피")
		}
		break
	}
	if len(runtime.contentRules.Interactions) > 0 {
		parts = append(parts, "E 상호작용")
	}
	if len(runtime.contentRules.Items) > 0 {
		parts = append(parts, "I 소지품")
		showStats = true
	}
	return showStats, strings.Join(parts, " · ")
}

func (runtime *Runtime) publishAudioEventsLocked(events []sim.Event) {
	for _, event := range events {
		runtime.queueAudioEventLocked(string(event.Type))
	}
}

func (runtime *Runtime) queueAudioEvent(event string) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	runtime.queueAudioEventLocked(event)
}

func (runtime *Runtime) queueAudioEventLocked(event string) {
	const retainedCueLimit = 128
	mapping, exists := runtime.built.Presentation.Audio.Cue(event)
	if !exists {
		return
	}
	runtime.audioSequence++
	runtime.audioCues = append(
		runtime.audioCues,
		queuedAudioCue{
			sequence: runtime.audioSequence,
			event:    event,
			assetID:  mapping.AssetID,
			volume:   mapping.Volume,
		},
	)
	if overflow := len(runtime.audioCues) - retainedCueLimit; overflow > 0 {
		copy(runtime.audioCues, runtime.audioCues[overflow:])
		runtime.audioCues = runtime.audioCues[:retainedCueLimit]
	}
}

func statusTint(statuses []sim.StatusSnapshot) color.RGBA {
	if len(statuses) == 0 {
		return color.RGBA{}
	}
	rgba := statuses[0].Color
	return color.RGBA{
		R: rgba[0],
		G: rgba[1],
		B: rgba[2],
		A: max(uint8(128), rgba[3]),
	}
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
