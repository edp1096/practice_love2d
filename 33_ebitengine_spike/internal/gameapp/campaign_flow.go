package gameapp

import (
	"context"
	"errors"
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

// FlowOptionState is one authored game-flow menu operation.
type FlowOptionState struct {
	ID      string `json:"id"`
	Label   string `json:"label"`
	Enabled bool   `json:"enabled"`
}

// FlowState is the presentation/debug contract for title, pause, game-over,
// and ending. It contains no renderer or platform-specific input state.
type FlowState struct {
	Active        bool                           `json:"active"`
	Mode          campaign.Mode                  `json:"mode"`
	Heading       string                         `json:"heading"`
	Message       string                         `json:"message"`
	Options       []FlowOptionState              `json:"options"`
	SelectedIndex int                            `json:"selected_index"`
	HasSave       bool                           `json:"has_save"`
	Status        string                         `json:"status,omitempty"`
	Panel         string                         `json:"panel,omitempty"`
	Accessibility campaign.AccessibilitySettings `json:"accessibility"`
	Revision      uint64                         `json:"revision"`
}

type flowCommand string

const (
	flowCommandNewGame               flowCommand = "new_game"
	flowCommandContinue              flowCommand = "continue"
	flowCommandQuit                  flowCommand = "quit"
	flowCommandResume                flowCommand = "resume"
	flowCommandSave                  flowCommand = "save"
	flowCommandTitle                 flowCommand = "title"
	flowCommandRetry                 flowCommand = "retry"
	flowCommandAccessibility         flowCommand = "accessibility"
	flowCommandAccessibilityMotion   flowCommand = "accessibility_motion"
	flowCommandAccessibilityHitFlash flowCommand = "accessibility_hit_flash"
	flowCommandAccessibilityNotice   flowCommand = "accessibility_notice_duration"
	flowCommandAccessibilityBack     flowCommand = "accessibility_back"
)

func authoredFlowCopy(value string, fallback string) string {
	if value != "" {
		return value
	}
	return fallback
}

func (runtime *Runtime) FlowState() (FlowState, error) {
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	return runtime.flowStateLocked()
}

// MoveFlowSelection drives the same semantic selection state as keyboard menu
// navigation without synthesizing platform key events.
func (runtime *Runtime) MoveFlowSelection(delta int) (FlowState, error) {
	if delta != -1 && delta != 1 {
		return FlowState{}, errors.New(
			"move game-flow selection: delta must be -1 or 1",
		)
	}
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	if err := runtime.moveFlowSelectionLocked(delta); err != nil {
		return FlowState{}, err
	}
	return runtime.flowStateLocked()
}

// ActivateFlowOption invokes one visible semantic menu option by ID. This
// keeps automation stable when localized labels or option ordering change.
func (runtime *Runtime) ActivateFlowOption(
	optionID string,
) (FlowState, error) {
	runtime.mu.Lock()
	state, err := runtime.flowStateLocked()
	if err != nil {
		runtime.mu.Unlock()
		return FlowState{}, err
	}
	if !state.Active {
		runtime.mu.Unlock()
		return FlowState{}, errors.New(
			"activate game-flow option: menu is not active",
		)
	}
	var command flowCommand
	for _, option := range state.Options {
		if option.ID != optionID {
			continue
		}
		if !option.Enabled {
			runtime.mu.Unlock()
			return FlowState{}, fmt.Errorf(
				"activate game-flow option: option %q is disabled",
				optionID,
			)
		}
		command = flowCommand(option.ID)
		break
	}
	runtime.mu.Unlock()
	if command == "" {
		return FlowState{}, fmt.Errorf(
			"activate game-flow option: option %q is not visible",
			optionID,
		)
	}
	if err := runtime.executeFlowCommand(command); err != nil {
		return FlowState{}, err
	}
	return runtime.FlowState()
}

func (runtime *Runtime) flowStateLocked() (FlowState, error) {
	if runtime.campaign == nil {
		return FlowState{}, errors.New("game flow: campaign is unavailable")
	}
	state := runtime.campaign.Snapshot()
	result := FlowState{
		Active:        state.Mode != campaign.ModePlaying,
		Mode:          state.Mode,
		Options:       []FlowOptionState{},
		SelectedIndex: -1,
		HasSave:       runtime.continueAvailable,
		Status:        runtime.flowStatus,
		Panel:         runtime.flowPanel,
		Accessibility: state.Accessibility,
		Revision:      runtime.revision,
	}
	if !result.Active {
		return result, nil
	}

	project := runtime.catalog.Project()
	if runtime.flowPanel == "accessibility" {
		result.Heading = runtime.localizeRuleTextLocked(
			"Accessibility",
			"accessibility.heading",
		)
		result.Message = runtime.localizeRuleTextLocked(
			"Adjust visual feedback and message duration.",
			"accessibility.message",
		)
		settings := state.Accessibility
		hitFlashKey := "accessibility.value.off"
		hitFlashFallback := "Off"
		if settings.HitFlash {
			hitFlashKey = "accessibility.value.on"
			hitFlashFallback = "On"
		}
		result.Options = []FlowOptionState{
			runtime.accessibilityFlowOptionLocked(
				flowCommandAccessibilityMotion,
				"accessibility.motion",
				"Camera motion",
				"accessibility.motion."+settings.Motion,
				settings.Motion,
			),
			runtime.accessibilityFlowOptionLocked(
				flowCommandAccessibilityHitFlash,
				"accessibility.hit_flash",
				"Hit flash",
				hitFlashKey,
				hitFlashFallback,
			),
			runtime.accessibilityFlowOptionLocked(
				flowCommandAccessibilityNotice,
				"accessibility.notice_duration",
				"Message duration",
				"accessibility.notice_duration."+
					settings.NoticeDuration,
				settings.NoticeDuration,
			),
			runtime.flowOptionLocked(
				flowCommandAccessibilityBack,
				"flow.menu.back",
				"Back",
			),
		}
		result.SelectedIndex = normalizedFlowIndex(
			result.Options,
			runtime.flowSelectedIndex,
		)
		return result, nil
	}
	switch state.Mode {
	case campaign.ModeTitle:
		result.Heading = runtime.localizeRuleTextLocked(
			authoredFlowCopy(project.Flow.Title.Heading, project.Title),
			project.Flow.Title.HeadingKey,
		)
		result.Message = runtime.localizeRuleTextLocked(
			project.Flow.Title.Message,
			project.Flow.Title.MessageKey,
		)
		result.Options = append(result.Options, runtime.flowOptionLocked(
			flowCommandNewGame,
			"flow.menu.new_game",
			"New Game",
		))
		if runtime.continueAvailable {
			result.Options = append(
				result.Options,
				runtime.flowOptionLocked(
					flowCommandContinue,
					"flow.menu.continue",
					"Continue",
				),
			)
		}
		result.Options = append(result.Options, runtime.flowOptionLocked(
			flowCommandAccessibility,
			"flow.menu.accessibility",
			"Accessibility",
		))
		result.Options = append(result.Options, runtime.flowOptionLocked(
			flowCommandQuit,
			"flow.menu.quit",
			"Quit",
		))

	case campaign.ModePaused:
		result.Heading = runtime.localizeRuleTextLocked(
			"Paused",
			"flow.pause.heading",
		)
		result.Options = []FlowOptionState{
			runtime.flowOptionLocked(
				flowCommandResume,
				"flow.menu.resume",
				"Resume",
			),
			runtime.flowOptionLocked(
				flowCommandSave,
				"flow.menu.save",
				"Save",
			),
			runtime.flowOptionLocked(
				flowCommandAccessibility,
				"flow.menu.accessibility",
				"Accessibility",
			),
			runtime.flowOptionLocked(
				flowCommandTitle,
				"flow.menu.title",
				"Return to Title",
			),
		}

	case campaign.ModeGameOver:
		result.Heading = runtime.localizeRuleTextLocked(
			authoredFlowCopy(project.Flow.GameOver.Heading, "Game Over"),
			project.Flow.GameOver.HeadingKey,
		)
		result.Message = runtime.localizeRuleTextLocked(
			project.Flow.GameOver.Message,
			project.Flow.GameOver.MessageKey,
		)
		result.Options = append(result.Options, runtime.flowOptionLocked(
			flowCommandRetry,
			"flow.menu.retry",
			"Retry",
		))
		if runtime.continueAvailable {
			result.Options = append(
				result.Options,
				runtime.flowOptionLocked(
					flowCommandContinue,
					"flow.menu.continue",
					"Continue",
				),
			)
		}
		result.Options = append(result.Options, runtime.flowOptionLocked(
			flowCommandTitle,
			"flow.menu.title",
			"Return to Title",
		))

	case campaign.ModeEnding:
		result.Heading = runtime.localizeRuleTextLocked(
			authoredFlowCopy(project.Flow.Ending.Heading, "The End"),
			project.Flow.Ending.HeadingKey,
		)
		result.Message = runtime.localizeRuleTextLocked(
			project.Flow.Ending.Message,
			project.Flow.Ending.MessageKey,
		)
		result.Options = []FlowOptionState{
			runtime.flowOptionLocked(
				flowCommandNewGame,
				"flow.menu.new_game",
				"New Game",
			),
			runtime.flowOptionLocked(
				flowCommandTitle,
				"flow.menu.title",
				"Return to Title",
			),
		}

	default:
		return FlowState{}, fmt.Errorf(
			"game flow: unsupported campaign mode %q",
			state.Mode,
		)
	}
	if runtime.flowStatus != "" {
		if result.Message != "" {
			result.Message += "\n"
		}
		result.Message += runtime.flowStatus
	}
	result.SelectedIndex = normalizedFlowIndex(
		result.Options,
		runtime.flowSelectedIndex,
	)
	return result, nil
}

func (runtime *Runtime) flowOptionLocked(
	id flowCommand,
	key string,
	fallback string,
) FlowOptionState {
	return FlowOptionState{
		ID:      string(id),
		Label:   runtime.localizeRuleTextLocked(fallback, key),
		Enabled: true,
	}
}

func (runtime *Runtime) accessibilityFlowOptionLocked(
	id flowCommand,
	labelKey string,
	labelFallback string,
	valueKey string,
	valueFallback string,
) FlowOptionState {
	return FlowOptionState{
		ID: string(id),
		Label: runtime.localizeRuleTextLocked(
			labelFallback,
			labelKey,
		) + ": " + runtime.localizeRuleTextLocked(
			valueFallback,
			valueKey,
		),
		Enabled: true,
	}
}

func normalizedFlowIndex(options []FlowOptionState, selected int) int {
	if len(options) == 0 {
		return -1
	}
	if selected >= 0 && selected < len(options) &&
		options[selected].Enabled {
		return selected
	}
	for index, option := range options {
		if option.Enabled {
			return index
		}
	}
	return -1
}

func (runtime *Runtime) flowViewLocked() ebitapp.FlowView {
	state, err := runtime.flowStateLocked()
	if err != nil {
		return ebitapp.FlowView{
			Active:        true,
			Mode:          string(campaign.ModeTitle),
			Heading:       "Game flow error",
			Message:       err.Error(),
			Options:       []ebitapp.FlowOptionView{},
			SelectedIndex: -1,
		}
	}
	result := ebitapp.FlowView{
		Active:        state.Active,
		Mode:          string(state.Mode),
		Heading:       state.Heading,
		Message:       state.Message,
		Options:       make([]ebitapp.FlowOptionView, len(state.Options)),
		SelectedIndex: state.SelectedIndex,
	}
	if state.Panel == "accessibility" {
		result.Mode = "accessibility"
	}
	for index, option := range state.Options {
		result.Options[index] = ebitapp.FlowOptionView{
			ID:      option.ID,
			Label:   option.Label,
			Enabled: option.Enabled,
		}
	}
	return result
}

func (runtime *Runtime) moveFlowSelectionLocked(delta int) error {
	state, err := runtime.flowStateLocked()
	if err != nil {
		return err
	}
	if !state.Active {
		return errors.New("move game-flow selection: menu is not active")
	}
	if len(state.Options) == 0 || delta == 0 {
		return nil
	}
	index := state.SelectedIndex
	for range state.Options {
		index = (index + delta) % len(state.Options)
		if index < 0 {
			index += len(state.Options)
		}
		if state.Options[index].Enabled {
			if runtime.flowSelectedIndex != index ||
				runtime.flowStatus != "" {
				runtime.flowSelectedIndex = index
				runtime.flowStatus = ""
				runtime.revision++
			}
			return nil
		}
	}
	return nil
}

func (runtime *Runtime) selectedFlowCommandLocked() (
	flowCommand,
	error,
) {
	state, err := runtime.flowStateLocked()
	if err != nil {
		return "", err
	}
	if !state.Active {
		return "", errors.New("activate game-flow option: menu is not active")
	}
	index := normalizedFlowIndex(state.Options, runtime.flowSelectedIndex)
	if index < 0 {
		return "", errors.New("activate game-flow option: no enabled option")
	}
	return flowCommand(state.Options[index].ID), nil
}

func (runtime *Runtime) consumeFlowActionsLocked(
	actions ebitapp.Actions,
) (flowCommand, error) {
	state := runtime.campaign.Snapshot()
	if state.Mode == campaign.ModePlaying {
		return "", nil
	}
	if runtime.flowPanel == "accessibility" &&
		(actions.FlowCancel || actions.Pause) {
		return flowCommandAccessibilityBack, nil
	}
	switch {
	case (actions.FlowCancel || actions.Pause) &&
		state.Mode == campaign.ModePaused:
		return flowCommandResume, nil
	case actions.FlowUp != actions.FlowDown:
		delta := 1
		if actions.FlowUp {
			delta = -1
		}
		return "", runtime.moveFlowSelectionLocked(delta)
	case actions.FlowConfirm:
		return runtime.selectedFlowCommandLocked()
	default:
		return "", nil
	}
}

func (runtime *Runtime) executeFlowCommand(command flowCommand) (err error) {
	ctx := context.Background()
	if command != "" {
		defer func() {
			if err == nil {
				runtime.queueAudioEvent("ui.confirm")
			}
		}()
	}
	switch command {
	case "":
		return nil
	case flowCommandNewGame:
		if err := runtime.startNewGame(ctx); err != nil {
			return err
		}
		runtime.clearFlowPresentation()
		return nil
	case flowCommandContinue:
		slot := runtime.flowSaveSlot()
		if _, err := runtime.load(ctx, slot); err != nil {
			runtime.setFlowFailure(err, true)
			return nil
		}
		runtime.clearFlowPresentation()
		return nil
	case flowCommandSave:
		slot := runtime.flowSaveSlot()
		if _, err := runtime.save(ctx, slot); err != nil {
			runtime.setFlowFailure(err, false)
			return nil
		}
		runtime.mu.Lock()
		runtime.continueAvailable = true
		runtime.flowStatus = "saved"
		runtime.revision++
		runtime.mu.Unlock()
		return nil
	case flowCommandResume:
		return runtime.resumeFlow()
	case flowCommandTitle:
		return runtime.returnToTitle()
	case flowCommandRetry:
		return runtime.retryStage()
	case flowCommandQuit:
		runtime.mu.Lock()
		if !runtime.quit {
			runtime.quit = true
			runtime.revision++
		}
		runtime.mu.Unlock()
		return nil
	case flowCommandAccessibility:
		runtime.mu.Lock()
		runtime.flowPanel = "accessibility"
		runtime.flowSelectedIndex = 0
		runtime.flowStatus = ""
		runtime.revision++
		runtime.mu.Unlock()
		return nil
	case flowCommandAccessibilityBack:
		runtime.mu.Lock()
		runtime.flowPanel = ""
		runtime.flowSelectedIndex = 0
		runtime.flowStatus = ""
		runtime.revision++
		runtime.mu.Unlock()
		return nil
	case flowCommandAccessibilityMotion,
		flowCommandAccessibilityHitFlash,
		flowCommandAccessibilityNotice:
		return runtime.cycleAccessibility(command)
	default:
		return fmt.Errorf("execute game-flow command: unknown option %q", command)
	}
}

func (runtime *Runtime) flowSaveSlot() string {
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	return runtime.catalog.Project().Flow.SaveSlot
}

func (runtime *Runtime) setFlowFailure(err error, invalidateSave bool) {
	if err == nil {
		return
	}
	runtime.mu.Lock()
	runtime.flowStatus = err.Error()
	if invalidateSave {
		runtime.continueAvailable = false
	}
	runtime.flowSelectedIndex = 0
	runtime.revision++
	runtime.mu.Unlock()
}

func (runtime *Runtime) clearFlowPresentation() {
	runtime.mu.Lock()
	runtime.resetFlowPresentationLocked()
	runtime.mu.Unlock()
}

func (runtime *Runtime) resetFlowPresentationLocked() {
	runtime.flowSelectedIndex = 0
	runtime.flowStatus = ""
	runtime.flowPanel = ""
}

func (runtime *Runtime) cycleAccessibility(command flowCommand) error {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()

	if runtime.flowPanel != "accessibility" {
		return errors.New(
			"change accessibility setting: accessibility menu is not active",
		)
	}
	if err := runtime.campaign.Transaction(
		func(state *campaign.State) error {
			switch command {
			case flowCommandAccessibilityMotion:
				switch state.Accessibility.Motion {
				case "full":
					state.Accessibility.Motion = "reduced"
				case "reduced":
					state.Accessibility.Motion = "off"
				default:
					state.Accessibility.Motion = "full"
				}
			case flowCommandAccessibilityHitFlash:
				state.Accessibility.HitFlash =
					!state.Accessibility.HitFlash
			case flowCommandAccessibilityNotice:
				if state.Accessibility.NoticeDuration == "normal" {
					state.Accessibility.NoticeDuration = "long"
				} else {
					state.Accessibility.NoticeDuration = "normal"
				}
			default:
				return fmt.Errorf(
					"change accessibility setting: unknown command %q",
					command,
				)
			}
			return nil
		},
	); err != nil {
		return fmt.Errorf("change accessibility setting: %w", err)
	}
	runtime.flowStatus = ""
	runtime.revision++
	return nil
}

func (runtime *Runtime) pauseFlowLocked() error {
	if runtime.campaign.Snapshot().Mode != campaign.ModePlaying {
		return nil
	}
	if runtime.equipmentRebuildPending {
		// Keep the World clock running until the authored loadout can be
		// published without changing an active attack or hitstop session.
		return nil
	}
	if err := runtime.campaign.Transaction(func(state *campaign.State) error {
		state.Mode = campaign.ModePaused
		return nil
	}); err != nil {
		return fmt.Errorf("pause game flow: %w", err)
	}
	runtime.resetFlowPresentationLocked()
	runtime.queueAudioEventLocked("ui.confirm")
	runtime.revision++
	return nil
}

func (runtime *Runtime) resumeFlow() error {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	if runtime.campaign.Snapshot().Mode != campaign.ModePaused {
		return errors.New("resume game flow: game is not paused")
	}
	if err := runtime.campaign.Transaction(func(state *campaign.State) error {
		state.Mode = campaign.ModePlaying
		return nil
	}); err != nil {
		return fmt.Errorf("resume game flow: %w", err)
	}
	runtime.resetFlowPresentationLocked()
	runtime.revision++
	return nil
}

func (runtime *Runtime) returnToTitle() error {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()

	title, err := campaign.NewTitle(runtime.campaignConfig)
	if err != nil {
		return err
	}
	accessibility := runtime.campaign.Snapshot().Accessibility
	if err := title.Transaction(func(state *campaign.State) error {
		state.Accessibility = accessibility
		return nil
	}); err != nil {
		return fmt.Errorf(
			"return to title accessibility settings: %w",
			err,
		)
	}
	resolved := resolveBuildOptions(runtime.catalog, runtime.buildOverrides)
	built, candidate, err := buildCampaignSimulation(
		runtime.catalog,
		resolved,
		title.Snapshot(),
		runtime.contentRules,
	)
	if err != nil {
		return err
	}
	portalInside, err := portalOverlaps(built, candidate)
	if err != nil {
		return fmt.Errorf("return to title portal latch: %w", err)
	}

	runtime.buildOptions = resolved
	runtime.built = built
	runtime.simulation = candidate
	runtime.campaign = title
	runtime.virtual = make(map[string]virtualAction)
	runtime.pendingAbilities = make(map[string]string)
	runtime.behaviorAI = make(map[string]behaviorAIState)
	runtime.pendingRemovals = make(map[string]bool)
	runtime.moving = make(map[string]bool)
	runtime.resetPreviewLocked()
	runtime.resetRulePresentationLocked()
	runtime.resetFlowPresentationLocked()
	runtime.portalCooldownTicks = 0
	runtime.portalInside = portalInside
	runtime.resetTriggerStateLocked()
	runtime.continueAvailable = runtime.hasValidContinueLocked()
	runtime.revision++
	return nil
}

func (runtime *Runtime) retryStage() error {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()

	state := runtime.campaign.Snapshot()
	if state.Mode != campaign.ModeGameOver {
		return errors.New("retry stage: game is not over")
	}
	candidateCampaign, err := campaign.Restore(
		runtime.campaignConfig,
		state,
	)
	if err != nil {
		return err
	}
	if err := candidateCampaign.Transaction(
		func(candidate *campaign.State) error {
			candidate.Mode = campaign.ModePlaying
			return nil
		},
	); err != nil {
		return fmt.Errorf("retry stage campaign: %w", err)
	}
	resolved := runtime.buildOptions
	resolved.StageID = state.CurrentStageID
	resolved.SpawnID = state.EntrySpawnID
	resolved.LocaleID = state.Locale
	built, candidate, err := buildCampaignSimulation(
		runtime.catalog,
		resolved,
		candidateCampaign.Snapshot(),
		runtime.contentRules,
	)
	if err != nil {
		return err
	}
	portalInside, err := portalOverlaps(built, candidate)
	if err != nil {
		return fmt.Errorf("retry stage portal latch: %w", err)
	}

	runtime.buildOptions = resolved
	runtime.built = built
	runtime.simulation = candidate
	runtime.campaign = candidateCampaign
	runtime.virtual = make(map[string]virtualAction)
	runtime.pendingAbilities = make(map[string]string)
	runtime.behaviorAI = make(map[string]behaviorAIState)
	runtime.pendingRemovals = make(map[string]bool)
	runtime.moving = make(map[string]bool)
	runtime.resetPreviewLocked()
	runtime.resetRulePresentationLocked()
	runtime.resetFlowPresentationLocked()
	runtime.portalCooldownTicks = 0
	runtime.portalInside = portalInside
	runtime.resetTriggerStateLocked()
	runtime.revision++
	return nil
}

func (runtime *Runtime) hasValidContinueLocked() bool {
	_, valid := runtime.validContinueCampaignLocked()
	return valid
}

func (runtime *Runtime) validContinueCampaignLocked() (
	*campaign.Campaign,
	bool,
) {
	slot := runtime.catalog.Project().Flow.SaveSlot
	data, err := runtime.store.Load(slot)
	if err != nil {
		return nil, false
	}
	saved, err := campaign.Decode(runtime.campaignConfig, data)
	if err != nil {
		return nil, false
	}
	state := saved.Snapshot()
	if !state.Flow.Started ||
		state.CurrentStageID == "" ||
		state.EntrySpawnID == "" {
		return nil, false
	}
	options := runtime.buildOptions
	options.StageID = state.CurrentStageID
	options.SpawnID = state.EntrySpawnID
	options.LocaleID = state.Locale
	built, candidate, err := buildCampaignSimulation(
		runtime.catalog,
		options,
		state,
		runtime.contentRules,
	)
	if err != nil {
		return nil, false
	}
	_, err = portalOverlaps(built, candidate)
	if err != nil {
		return nil, false
	}
	return saved, true
}

func (runtime *Runtime) controlledActorKilledLocked(
	events []sim.Event,
) bool {
	controlledID := runtime.built.Config.Camera.TargetEntityID
	for _, event := range events {
		if event.Type == sim.EventActorKilled &&
			event.TargetID == controlledID {
			return true
		}
	}
	for _, entity := range runtime.simulation.Snapshot().Entities {
		if entity.ID == controlledID {
			return entity.Dead
		}
	}
	return false
}

func (runtime *Runtime) enterGameOverLocked() error {
	state := runtime.campaign.Snapshot()
	if state.Mode != campaign.ModePlaying ||
		state.Flow.Completed {
		return nil
	}
	if err := runtime.campaign.Transaction(func(candidate *campaign.State) error {
		candidate.Mode = campaign.ModeGameOver
		return nil
	}); err != nil {
		return fmt.Errorf("enter game over: %w", err)
	}
	runtime.resetFlowPresentationLocked()
	return nil
}
