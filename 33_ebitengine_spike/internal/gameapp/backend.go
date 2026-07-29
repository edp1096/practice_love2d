package gameapp

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	goruntime "runtime"
	"runtime/debug"
	"sort"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/protocol"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

// Call implements protocol.Backend.
func (runtime *Runtime) Call(
	ctx context.Context,
	call protocol.Call,
) (any, error) {
	if ctx == nil {
		return nil, errors.New("gameapp: protocol context is required")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	switch call.Method {
	case protocol.MethodRuntimeGetState:
		runtime.mu.RLock()
		snapshot := runtime.simulation.Snapshot()
		result := runtimeStateDTO{
			Engine:      ebitengineVersion(),
			Go:          goruntime.Version(),
			Protocol:    protocol.Version,
			StageID:     runtime.built.Presentation.StageID,
			StageName:   runtime.built.Presentation.StageName,
			Tick:        snapshot.Tick,
			WorldTick:   snapshot.WorldTick,
			Revision:    runtime.revision,
			Paused:      runtime.automationPaused,
			Mode:        string(runtime.campaign.Snapshot().Mode),
			Quit:        runtime.quit,
			QuitPending: runtime.quitPending,
			Hitstop:     snapshot.HitstopTicks,
			Definitions: len(runtime.catalog.IDs()),
			Entities:    len(snapshot.Entities),
		}
		runtime.mu.RUnlock()
		return result, nil

	case protocol.MethodContentGetGraph:
		runtime.mu.RLock()
		result := runtime.catalog.Graph()
		runtime.mu.RUnlock()
		return result, nil

	case protocol.MethodContentGetDefinition:
		params, ok := call.Params.(protocol.ContentIDParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		runtime.mu.RLock()
		raw, found := runtime.catalog.Definition(params.ContentID)
		source := runtime.contentSourceLocked(params.ContentID)
		runtime.mu.RUnlock()
		if !found {
			return nil, fmt.Errorf(
				"content definition %q does not exist",
				params.ContentID,
			)
		}
		var header struct {
			Kind string `json:"kind"`
		}
		if err := json.Unmarshal(raw, &header); err != nil {
			return nil, err
		}
		return struct {
			ID         string          `json:"id"`
			Kind       string          `json:"kind"`
			Source     string          `json:"source"`
			Definition json.RawMessage `json:"definition"`
		}{
			ID:         params.ContentID,
			Kind:       header.Kind,
			Source:     source,
			Definition: raw,
		}, nil

	case protocol.MethodContentValidateDefinition:
		params, ok := call.Params.(protocol.ValidateDefinitionParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.validateDefinition(ctx, params)

	case protocol.MethodWorldGetSnapshot:
		runtime.mu.RLock()
		result := runtime.worldSnapshotLocked()
		runtime.mu.RUnlock()
		return result, nil

	case protocol.MethodWorldSetWall:
		params, ok := call.Params.(protocol.SetWallParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.setWall(params)

	case protocol.MethodEntitySpawn:
		params, ok := call.Params.(protocol.SpawnEntityParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.spawnEntity(params)

	case protocol.MethodEntityRemove:
		params, ok := call.Params.(protocol.RemoveEntityParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.queueEntityRemoval(params)

	case protocol.MethodEntitySetPosition:
		params, ok := call.Params.(protocol.SetPositionParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.setPosition(params)

	case protocol.MethodEntitySetHealth:
		params, ok := call.Params.(protocol.SetHealthParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.setHealth(params)

	case protocol.MethodEntityRequestAbility:
		params, ok := call.Params.(protocol.RequestAbilityParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.requestAbility(params)

	case protocol.MethodFlowGetState:
		if _, ok := call.Params.(protocol.EmptyParams); !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.FlowState()

	case protocol.MethodFlowMove:
		params, ok := call.Params.(protocol.FlowMoveParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.MoveFlowSelection(params.Delta)

	case protocol.MethodFlowActivate:
		params, ok := call.Params.(protocol.FlowActivateParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.ActivateFlowOption(params.OptionID)

	case protocol.MethodDialogueStart:
		params, ok := call.Params.(protocol.StartDialogueParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.startDialogue(params)

	case protocol.MethodDialogueGetState:
		if _, ok := call.Params.(protocol.EmptyParams); !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.DialogueState()

	case protocol.MethodDialogueChoose:
		params, ok := call.Params.(protocol.ChooseDialogueParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.ChooseDialogue(params.ChoiceID)

	case protocol.MethodDialogueAdvance:
		if _, ok := call.Params.(protocol.EmptyParams); !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.AdvanceDialogue()

	case protocol.MethodCampaignGetState:
		if _, ok := call.Params.(protocol.EmptyParams); !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.CampaignGetState()

	case protocol.MethodShopGetState:
		if _, ok := call.Params.(protocol.EmptyParams); !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.ShopState()

	case protocol.MethodShopBuy:
		params, ok := call.Params.(protocol.ShopTradeParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.BuyShopItem(params.ItemID, params.Quantity)

	case protocol.MethodShopSell:
		params, ok := call.Params.(protocol.ShopTradeParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.SellShopItem(params.ItemID, params.Quantity)

	case protocol.MethodShopClose:
		if _, ok := call.Params.(protocol.EmptyParams); !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.CloseShop()

	case protocol.MethodInventoryUse:
		params, ok := call.Params.(protocol.InventoryUseParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.UseInventoryItem(params.ItemID)

	case protocol.MethodEquipmentEquip:
		params, ok := call.Params.(protocol.EquipmentEquipParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.EquipCampaignItem(params.ItemID)

	case protocol.MethodEquipmentUnequip:
		params, ok := call.Params.(protocol.EquipmentUnequipParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.UnequipCampaignItem(params.SlotID)

	case protocol.MethodInputAction:
		params, ok := call.Params.(protocol.InputActionParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.scheduleAction(params)

	case protocol.MethodEmulationSetPaused:
		params, ok := call.Params.(protocol.SetPausedParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		runtime.mu.Lock()
		if runtime.automationPaused != params.Enabled {
			runtime.automationPaused = params.Enabled
			runtime.revision++
		}
		tick := runtime.simulation.Snapshot().Tick
		revision := runtime.revision
		runtime.mu.Unlock()
		return struct {
			Paused   bool   `json:"paused"`
			Tick     uint64 `json:"tick"`
			Revision uint64 `json:"revision"`
		}{Paused: params.Enabled, Tick: tick, Revision: revision}, nil

	case protocol.MethodEmulationStep:
		params, ok := call.Params.(protocol.StepParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.step(ctx, params.Frames)

	case protocol.MethodPageCaptureScreenshot:
		runtime.mu.RLock()
		minimumRevision := runtime.revision
		runtime.mu.RUnlock()
		capture, err := runtime.capturePNG(ctx)
		if err != nil {
			return nil, err
		}
		if capture.Revision < minimumRevision {
			return nil, fmt.Errorf(
				"captured stale presentation revision %d; expected at least %d",
				capture.Revision,
				minimumRevision,
			)
		}
		return struct {
			Data     string `json:"data"`
			Format   string `json:"format"`
			Width    int    `json:"width"`
			Height   int    `json:"height"`
			Tick     uint64 `json:"tick"`
			Revision uint64 `json:"revision"`
		}{
			Data:     base64.StdEncoding.EncodeToString(capture.PNG),
			Format:   "png",
			Width:    960,
			Height:   540,
			Tick:     capture.Tick,
			Revision: capture.Revision,
		}, nil

	case protocol.MethodAppReloadContent:
		if err := runtime.reloadContent(ctx); err != nil {
			return nil, err
		}
		runtime.mu.RLock()
		snapshot := runtime.simulation.Snapshot()
		count := len(runtime.catalog.IDs())
		runtime.mu.RUnlock()
		return struct {
			Reloaded    bool   `json:"reloaded"`
			Tick        uint64 `json:"tick"`
			Definitions int    `json:"definitions"`
		}{true, snapshot.Tick, count}, nil

	case protocol.MethodAppStartNewGame:
		if err := runtime.startNewGame(ctx); err != nil {
			return nil, err
		}
		runtime.mu.RLock()
		snapshot := runtime.simulation.Snapshot()
		revision := runtime.revision
		runtime.mu.RUnlock()
		return struct {
			Started  bool   `json:"started"`
			Tick     uint64 `json:"tick"`
			Revision uint64 `json:"revision"`
		}{true, snapshot.Tick, revision}, nil

	case protocol.MethodAppSave:
		params, ok := call.Params.(protocol.SaveSlotParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.save(ctx, params.Slot)

	case protocol.MethodAppLoad:
		params, ok := call.Params.(protocol.SaveSlotParams)
		if !ok {
			return nil, invalidBackendParams(call.Method)
		}
		return runtime.load(ctx, params.Slot)

	case protocol.MethodAppQuit:
		runtime.mu.Lock()
		if !runtime.quit && !runtime.quitPending {
			runtime.quitPending = true
			runtime.revision++
		}
		tick := runtime.simulation.Snapshot().Tick
		runtime.mu.Unlock()
		return struct {
			Quitting bool   `json:"quitting"`
			Tick     uint64 `json:"tick"`
		}{true, tick}, nil

	default:
		return nil, fmt.Errorf("unsupported runtime method %q", call.Method)
	}
}

func invalidBackendParams(method string) error {
	return fmt.Errorf("%s received unexpected validated params", method)
}

func (runtime *Runtime) contentSourceLocked(id string) string {
	for _, node := range runtime.catalog.Graph().Nodes {
		if node.ID == id {
			return node.Source
		}
	}
	return ""
}

func (runtime *Runtime) validateDefinition(
	ctx context.Context,
	params protocol.ValidateDefinitionParams,
) (any, error) {
	runtime.mu.RLock()
	candidate, err := runtime.catalog.WithDefinition(
		params.ContentID,
		params.Definition,
	)
	options := runtime.buildOptions
	runtime.mu.RUnlock()
	if err != nil {
		return nil, err
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	validation, err := gamebuild.ValidateDefinition(
		candidate,
		params.ContentID,
	)
	if err != nil {
		return nil, err
	}

	built, simulation, buildErr := buildValidationSimulation(
		candidate,
		options,
	)
	runtimeCompatible := buildErr == nil
	runtimeError := ""
	entities := 0
	var tick uint64
	if buildErr != nil {
		validation.FullyApplied = false
		runtimeError = buildErr.Error()
		validation.Warnings = append(
			validation.Warnings,
			"Ebitengine runtime preview rejected this schema-valid definition: "+
				runtimeError,
		)
		sort.Strings(validation.Warnings)
	} else {
		entities = len(built.Config.Entities)
		tick = simulation.Snapshot().Tick
	}
	return definitionValidationResult{
		Valid:             validation.SchemaValid,
		SchemaValid:       validation.SchemaValid,
		FullyApplied:      validation.FullyApplied,
		RuntimeCompatible: runtimeCompatible,
		RuntimeError:      runtimeError,
		Warnings:          validation.Warnings,
		ContentID:         params.ContentID,
		Definitions:       candidate.Graph().Total,
		GraphEdges:        candidate.Graph().EdgeCount,
		Entities:          entities,
		Tick:              tick,
	}, nil
}

type definitionValidationResult struct {
	Valid             bool     `json:"valid"`
	SchemaValid       bool     `json:"schema_valid"`
	FullyApplied      bool     `json:"fully_applied"`
	RuntimeCompatible bool     `json:"runtime_compatible"`
	RuntimeError      string   `json:"runtime_error,omitempty"`
	Warnings          []string `json:"warnings"`
	ContentID         string   `json:"content_id"`
	Definitions       int      `json:"definitions"`
	GraphEdges        int      `json:"graph_edges"`
	Entities          int      `json:"entities"`
	Tick              uint64   `json:"tick"`
}

func fixedFromPixels(value float64) (sim.Coord, error) {
	scaled := value * float64(sim.UnitsPerPixel)
	if math.IsNaN(scaled) || math.IsInf(scaled, 0) ||
		scaled > math.MaxInt64 || scaled < math.MinInt64 {
		return 0, errors.New("coordinate is outside the fixed-point range")
	}
	return sim.Coord(math.Round(scaled)), nil
}

func (runtime *Runtime) setWall(
	params protocol.SetWallParams,
) (any, error) {
	minX, err := fixedFromPixels(params.X)
	if err != nil {
		return nil, err
	}
	minY, err := fixedFromPixels(params.Y)
	if err != nil {
		return nil, err
	}
	maxX, err := fixedFromPixels(params.X + params.Width)
	if err != nil {
		return nil, err
	}
	maxY, err := fixedFromPixels(params.Y + params.Height)
	if err != nil {
		return nil, err
	}
	if maxX <= minX || maxY <= minY {
		return nil, errors.New("wall dimensions are below fixed-point precision")
	}
	replacement := sim.Rect{
		MinX: minX,
		MinY: minY,
		MaxX: maxX,
		MaxY: maxY,
	}

	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	if err := runtime.rejectMakerMutationWhileEquipmentPendingLocked(
		"set wall",
	); err != nil {
		return nil, err
	}
	if err := runtime.simulation.SetWall(params.WallID, replacement); err != nil {
		return nil, fmt.Errorf("set wall: %w", err)
	}
	runtime.revision++
	return struct {
		WallID string  `json:"wall_id"`
		X      float64 `json:"x"`
		Y      float64 `json:"y"`
		Width  float64 `json:"width"`
		Height float64 `json:"height"`
	}{
		WallID: params.WallID,
		X:      coordPixels(replacement.MinX),
		Y:      coordPixels(replacement.MinY),
		Width:  coordPixels(replacement.MaxX - replacement.MinX),
		Height: coordPixels(replacement.MaxY - replacement.MinY),
	}, nil
}

func (runtime *Runtime) setPosition(
	params protocol.SetPositionParams,
) (any, error) {
	x, err := fixedFromPixels(params.X)
	if err != nil {
		return nil, err
	}
	y, err := fixedFromPixels(params.Y)
	if err != nil {
		return nil, err
	}
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	state := runtime.simulation.SaveSession()
	found := false
	for index := range state.Entities {
		if state.Entities[index].ID != params.EntityID {
			continue
		}
		state.Entities[index].Position = sim.Vec{X: x, Y: y}
		found = true
		break
	}
	if !found {
		return nil, fmt.Errorf("unknown entity %q", params.EntityID)
	}
	if params.EntityID == runtime.built.Config.Camera.TargetEntityID {
		center := clampCameraTarget(
			sim.Vec{X: x, Y: y},
			runtime.built.Config.StageBounds,
			runtime.built.Config.Camera,
		)
		state.Camera = sim.CameraSessionState{
			BaseCenter: center,
			Center:     center,
		}
	}
	if err := runtime.simulation.LoadSession(state); err != nil {
		return nil, fmt.Errorf("set entity position: %w", err)
	}
	runtime.revision++
	return struct {
		EntityID string  `json:"entity_id"`
		X        float64 `json:"x"`
		Y        float64 `json:"y"`
	}{
		EntityID: params.EntityID,
		X:        params.X,
		Y:        params.Y,
	}, nil
}

func (runtime *Runtime) setHealth(
	params protocol.SetHealthParams,
) (any, error) {
	if math.Trunc(params.Value) != params.Value ||
		params.Value > float64(math.MaxInt) ||
		params.Value < float64(math.MinInt) {
		return nil, errors.New("health must be a whole number")
	}
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	state := runtime.simulation.SaveSession()
	found := false
	value := int(params.Value)
	for index := range state.Entities {
		if state.Entities[index].ID != params.EntityID {
			continue
		}
		definition, _ := runtime.entityConfig(params.EntityID)
		if value < 0 || value > definition.MaxHealth {
			return nil, fmt.Errorf(
				"health must be between 0 and %d",
				definition.MaxHealth,
			)
		}
		state.Entities[index].Health = value
		state.Entities[index].Dead = value == 0
		if value == 0 {
			state.Entities[index].Attack = nil
			state.Entities[index].StaggerTicks = 0
			state.Entities[index].InvulnerableTicks = 0
			state.Entities[index].FlashTicks = 0
			state.Entities[index].Knockback = sim.BurstSessionState{}
			state.Entities[index].Dodge = sim.BurstSessionState{}
			state.Entities[index].ParryTicks = 0
			state.Entities[index].Statuses = nil
			state.Entities[index].Velocity = sim.Vec{}
			state.Entities[index].Grounded = false
			state.Entities[index].CoyoteTicks = 0
			state.Entities[index].JumpBufferTicks = 0
			if state.Dialogue.Active &&
				state.Dialogue.NPCID == params.EntityID {
				state.Dialogue = sim.DialogueSessionState{}
			}
		}
		found = true
		break
	}
	if !found {
		return nil, fmt.Errorf("unknown entity %q", params.EntityID)
	}
	if err := runtime.simulation.LoadSession(state); err != nil {
		return nil, fmt.Errorf("set entity health: %w", err)
	}
	runtime.revision++
	return struct {
		EntityID string `json:"entity_id"`
		Health   int    `json:"health"`
	}{
		EntityID: params.EntityID,
		Health:   value,
	}, nil
}

func clampCameraTarget(
	target sim.Vec,
	stage sim.Rect,
	camera sim.CameraConfig,
) sim.Vec {
	return sim.Vec{
		X: clampCoord(
			target.X,
			stage.MinX+camera.ViewportWidth/2,
			stage.MaxX-camera.ViewportWidth/2,
		),
		Y: clampCoord(
			target.Y,
			stage.MinY+camera.ViewportHeight/2,
			stage.MaxY-camera.ViewportHeight/2,
		),
	}
}

func clampCoord(value, minimum, maximum sim.Coord) sim.Coord {
	if minimum > maximum {
		return (minimum + maximum) / 2
	}
	if value < minimum {
		return minimum
	}
	if value > maximum {
		return maximum
	}
	return value
}

func (runtime *Runtime) requestAbility(
	params protocol.RequestAbilityParams,
) (any, error) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	var live *sim.EntitySnapshot
	snapshot := runtime.simulation.Snapshot()
	for index := range snapshot.Entities {
		if snapshot.Entities[index].ID == params.EntityID {
			live = &snapshot.Entities[index]
			break
		}
	}
	if live == nil {
		return nil, fmt.Errorf("unknown entity %q", params.EntityID)
	}
	if live.Dead {
		return nil, fmt.Errorf("entity %q is dead", params.EntityID)
	}
	definition, exists := runtime.entityConfig(params.EntityID)
	if !exists {
		return nil, fmt.Errorf("unknown entity %q", params.EntityID)
	}
	if definition.Combat == nil ||
		definition.Combat.Ability(params.AbilityID) == nil {
		return nil, fmt.Errorf(
			"entity %q cannot request ability %q",
			params.EntityID,
			params.AbilityID,
		)
	}
	runtime.pendingAbilities[params.EntityID] = params.AbilityID
	return struct {
		EntityID  string `json:"entity_id"`
		AbilityID string `json:"ability_id"`
		Queued    bool   `json:"queued"`
	}{params.EntityID, params.AbilityID, true}, nil
}

var supportedActions = map[string]struct{}{
	"left": {}, "right": {}, "up": {}, "down": {},
	"move_left": {}, "move_right": {}, "move_up": {}, "move_down": {},
	"move_x": {}, "move_y": {},
	"attack": {}, "special": {}, "technique": {},
	"parry": {}, "dodge": {}, "jump": {}, "interact": {},
}

func (runtime *Runtime) scheduleAction(
	params protocol.InputActionParams,
) (any, error) {
	name := normalizeActionName(params.Action)
	if _, exists := supportedActions[name]; !exists {
		names := make([]string, 0, len(supportedActions))
		for candidate := range supportedActions {
			names = append(names, candidate)
		}
		sort.Strings(names)
		return nil, fmt.Errorf(
			"unknown input action %q; supported: %v",
			params.Action,
			names,
		)
	}
	if (name == "attack" || name == "parry" ||
		name == "dodge" || name == "interact") &&
		(params.Value < 0 || params.Value > 1) {
		return nil, fmt.Errorf("%s value must be between 0 and 1", name)
	}
	runtime.mu.Lock()
	if params.Value == 0 {
		delete(runtime.virtual, name)
	} else {
		previous, active := runtime.virtual[name]
		runtime.virtual[name] = virtualAction{
			value:     params.Value,
			remaining: params.Frames,
			fresh:     !active || previous.value <= 0,
		}
	}
	runtime.mu.Unlock()
	return struct {
		Action string  `json:"action"`
		Value  float64 `json:"value"`
		Frames int     `json:"frames"`
	}{
		Action: name,
		Value:  params.Value,
		Frames: params.Frames,
	}, nil
}

func (runtime *Runtime) step(ctx context.Context, frames int) (any, error) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()

	if mode := runtime.campaign.Snapshot().Mode; mode != campaign.ModePlaying {
		return nil, fmt.Errorf(
			"Emulation.step is unavailable while game flow mode %q is active; use Flow.getState and Flow.activate",
			mode,
		)
	}
	checkpoint := runtime.checkpointLocked()
	originalPaused := runtime.automationPaused

	// mergeVirtualInputLocked consumes this map before tickLocked creates its
	// own candidate. Detach just this pre-tick mutable so the outer batch
	// checkpoint remains intact without rebinding an active DialogueSession.
	runtime.virtual = cloneVirtualActions(checkpoint.virtual)
	runtime.automationPaused = true
	for frame := range frames {
		if err := ctx.Err(); err != nil {
			runtime.restoreCheckpointLocked(checkpoint)
			runtime.automationPaused = originalPaused
			return nil, err
		}
		if mode := runtime.campaign.Snapshot().Mode; mode != campaign.ModePlaying {
			runtime.restoreCheckpointLocked(checkpoint)
			runtime.automationPaused = originalPaused
			return nil, fmt.Errorf(
				"Emulation.step frame %d entered game flow mode %q before the requested batch completed",
				frame,
				mode,
			)
		}
		input := sim.Input{}
		if runtime.dialogue == nil &&
			runtime.activeShopID == "" &&
			!runtime.inventoryOpen {
			runtime.mergeVirtualInputLocked(&input)
		}
		if err := runtime.tickLocked(input); err != nil {
			runtime.restoreCheckpointLocked(checkpoint)
			runtime.automationPaused = originalPaused
			return nil, err
		}
	}
	runtime.automationPaused = originalPaused
	snapshot := runtime.simulation.Snapshot()
	return struct {
		Paused    bool    `json:"paused"`
		Frames    int     `json:"frames"`
		DT        float64 `json:"dt"`
		Tick      uint64  `json:"tick"`
		WorldTick uint64  `json:"world_tick"`
	}{
		Paused:    originalPaused,
		Frames:    frames,
		DT:        1.0 / sim.TicksPerSecond,
		Tick:      snapshot.Tick,
		WorldTick: snapshot.WorldTick,
	}, nil
}

func cloneVirtualActions(
	source map[string]virtualAction,
) map[string]virtualAction {
	result := make(map[string]virtualAction, len(source))
	for id, action := range source {
		result[id] = action
	}
	return result
}

func cloneBoolMap(source map[string]bool) map[string]bool {
	result := make(map[string]bool, len(source))
	for id, value := range source {
		result[id] = value
	}
	return result
}

func cloneStringMap(source map[string]string) map[string]string {
	result := make(map[string]string, len(source))
	for id, value := range source {
		result[id] = value
	}
	return result
}

type campaignSaveResult struct {
	Slot   string `json:"slot"`
	Saved  bool   `json:"saved"`
	Stage  string `json:"stage"`
	Spawn  string `json:"spawn"`
	Locale string `json:"locale"`
	Bytes  int    `json:"bytes"`
}

type campaignLoadResult struct {
	Slot   string        `json:"slot"`
	Loaded bool          `json:"loaded"`
	Stage  string        `json:"stage"`
	Spawn  string        `json:"spawn"`
	Locale string        `json:"locale"`
	Mode   campaign.Mode `json:"mode"`
	Bytes  int           `json:"bytes"`
}

func (runtime *Runtime) save(ctx context.Context, slot string) (any, error) {
	runtime.mu.RLock()
	if runtime.equipmentRebuildPending {
		runtime.mu.RUnlock()
		return nil, errors.New(
			"save is unavailable while an authored equipment rebuild is pending",
		)
	}
	if runtime.simulation.HasTemporaryPreview() ||
		len(runtime.pendingRemovals) != 0 {
		runtime.mu.RUnlock()
		return nil, errors.New(
			"temporary Maker preview state cannot be written to a player save; start a new game first",
		)
	}
	data, err := runtime.campaign.Marshal()
	if err != nil {
		runtime.mu.RUnlock()
		return nil, fmt.Errorf("encode save slot %q: %w", slot, err)
	}
	savedCampaign, err := campaign.Decode(runtime.campaignConfig, data)
	if err != nil {
		runtime.mu.RUnlock()
		return nil, fmt.Errorf(
			"verify save slot %q campaign payload: %w",
			slot,
			err,
		)
	}
	state := savedCampaign.Snapshot()
	if !state.Flow.Started ||
		state.CurrentStageID == "" ||
		state.EntrySpawnID == "" {
		runtime.mu.RUnlock()
		return nil, fmt.Errorf(
			"save slot %q requires a started campaign with a stage entry",
			slot,
		)
	}
	runtime.mu.RUnlock()
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if err := runtime.store.Save(slot, data); err != nil {
		return nil, err
	}
	runtime.mu.Lock()
	if !runtime.continueAvailable {
		runtime.continueAvailable = true
		runtime.revision++
	}
	runtime.mu.Unlock()
	return campaignSaveResult{
		Slot:   slot,
		Saved:  true,
		Stage:  state.CurrentStageID,
		Spawn:  state.EntrySpawnID,
		Locale: state.Locale,
		Bytes:  len(data),
	}, nil
}

func (runtime *Runtime) load(ctx context.Context, slot string) (any, error) {
	data, err := runtime.store.Load(slot)
	if err != nil {
		return nil, err
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}

	runtime.mu.Lock()
	defer runtime.mu.Unlock()

	if runtime.simulation.HasTemporaryPreview() ||
		len(runtime.pendingRemovals) != 0 {
		return nil, errors.New(
			"temporary Maker preview state cannot be replaced by a player save; start a new game first",
		)
	}
	activeCampaign, err := campaign.Decode(runtime.campaignConfig, data)
	if err != nil {
		return nil, fmt.Errorf("decode save slot %q: %w", slot, err)
	}
	state := activeCampaign.Snapshot()
	if !state.Flow.Started {
		return nil, fmt.Errorf(
			"load save slot %q: campaign has not started",
			slot,
		)
	}
	if state.CurrentStageID == "" || state.EntrySpawnID == "" {
		return nil, fmt.Errorf(
			"load save slot %q: started campaign has no stage entry",
			slot,
		)
	}

	resolved := runtime.buildOptions
	resolved.StageID = state.CurrentStageID
	resolved.SpawnID = state.EntrySpawnID
	resolved.LocaleID = state.Locale
	built, candidate, err := buildCampaignSimulation(
		runtime.catalog,
		resolved,
		state,
		runtime.contentRules,
	)
	if err != nil {
		return nil, fmt.Errorf(
			"load save slot %q stage %s/%s: %w",
			slot,
			state.CurrentStageID,
			state.EntrySpawnID,
			err,
		)
	}
	if built.Stage.ID != state.CurrentStageID {
		return nil, fmt.Errorf(
			"load save slot %q built stage %q, want %q",
			slot,
			built.Stage.ID,
			state.CurrentStageID,
		)
	}
	entrySpawnID, err := campaignEntrySpawn(built, resolved)
	if err != nil {
		return nil, fmt.Errorf(
			"load save slot %q resolve stage entry: %w",
			slot,
			err,
		)
	}
	if entrySpawnID != state.EntrySpawnID {
		return nil, fmt.Errorf(
			"load save slot %q built spawn %q, want %q",
			slot,
			entrySpawnID,
			state.EntrySpawnID,
		)
	}
	portalInside, err := portalOverlaps(built, candidate)
	if err != nil {
		return nil, fmt.Errorf("load save slot %q portal latch: %w", slot, err)
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}

	// All decoding, topology validation, stage construction, and portal-latch
	// validation above operate on detached candidates. These assignments are
	// the single no-fail commit boundary.
	runtime.buildOptions = resolved
	runtime.built = built
	runtime.simulation = candidate
	runtime.campaign = activeCampaign
	runtime.virtual = make(map[string]virtualAction)
	runtime.pendingAbilities = make(map[string]string)
	runtime.pendingRemovals = make(map[string]bool)
	runtime.moving = make(map[string]bool)
	runtime.resetPreviewLocked()
	runtime.resetRulePresentationLocked()
	runtime.resetFlowPresentationLocked()
	runtime.portalCooldownTicks = 0
	runtime.portalInside = portalInside
	runtime.revision++

	return campaignLoadResult{
		Slot:   slot,
		Loaded: true,
		Stage:  state.CurrentStageID,
		Spawn:  state.EntrySpawnID,
		Locale: state.Locale,
		Mode:   state.Mode,
		Bytes:  len(data),
	}, nil
}

func ebitengineVersion() string {
	info, ok := debug.ReadBuildInfo()
	if ok {
		for _, dependency := range info.Deps {
			if dependency.Path == "github.com/hajimehoshi/ebiten/v2" {
				return "Ebitengine " + dependency.Version
			}
		}
	}
	return "Ebitengine"
}

func (runtime *Runtime) ProtocolResponseWritten(method string) {
	if method != protocol.MethodAppQuit {
		return
	}
	runtime.mu.Lock()
	if runtime.quitPending {
		runtime.quitPending = false
		runtime.quit = true
		runtime.revision++
	}
	runtime.mu.Unlock()
}

var _ protocol.Backend = (*Runtime)(nil)
var _ protocol.ResponseObserver = (*Runtime)(nil)
