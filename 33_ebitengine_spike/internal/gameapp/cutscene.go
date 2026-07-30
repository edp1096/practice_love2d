package gameapp

import (
	"errors"
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

type cutsceneSession struct {
	CutsceneID     string
	StepIndex      int
	RemainingTicks int
	SpeakerID      string
	HealTargetID   string
	TriggerID      string
}

func cloneCutsceneSession(session *cutsceneSession) *cutsceneSession {
	if session == nil {
		return nil
	}
	result := *session
	return &result
}

// CutsceneState is the transient, presentation-neutral cutscene contract
// shared by the renderer and debug protocol.
type CutsceneState struct {
	Active         bool   `json:"active"`
	ID             string `json:"id,omitempty"`
	Name           string `json:"name,omitempty"`
	NameKey        string `json:"name_key,omitempty"`
	StepID         string `json:"step_id,omitempty"`
	StepIndex      int    `json:"step_index"`
	StepCount      int    `json:"step_count"`
	Speaker        string `json:"speaker,omitempty"`
	SpeakerKey     string `json:"speaker_key,omitempty"`
	Text           string `json:"text,omitempty"`
	TextKey        string `json:"text_key,omitempty"`
	BackgroundID   string `json:"background_id,omitempty"`
	RemainingTicks int    `json:"remaining_ticks"`
	Skippable      bool   `json:"skippable"`
	ContinueLabel  string `json:"continue_label,omitempty"`
	SkipLabel      string `json:"skip_label,omitempty"`
	Revision       uint64 `json:"revision"`
}

func (runtime *Runtime) CutsceneState() CutsceneState {
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	return runtime.cutsceneStateLocked()
}

func (runtime *Runtime) cutsceneStateLocked() CutsceneState {
	state := CutsceneState{
		StepIndex: -1,
		Revision:  runtime.revision,
	}
	if runtime.cutscene == nil {
		return state
	}
	rule, exists := runtime.contentRules.Cutscene(
		runtime.cutscene.CutsceneID,
	)
	if !exists ||
		runtime.cutscene.StepIndex < 0 ||
		runtime.cutscene.StepIndex >= len(rule.Steps) {
		return state
	}
	session := runtime.cutscene
	step := rule.Steps[session.StepIndex]
	backgroundID := step.BackgroundID
	if backgroundID == "" {
		backgroundID = rule.BackgroundID
	}
	state.Active = true
	state.ID = rule.ID
	state.Name = runtime.localizeRuleTextLocked(rule.Name, rule.NameKey)
	state.NameKey = rule.NameKey
	state.StepID = step.ID
	state.StepIndex = session.StepIndex
	state.StepCount = len(rule.Steps)
	state.Speaker = runtime.localizeRuleTextLocked(
		step.Speaker,
		step.SpeakerKey,
	)
	state.SpeakerKey = step.SpeakerKey
	state.Text = runtime.localizeRuleTextLocked(step.Text, step.TextKey)
	state.TextKey = step.TextKey
	state.BackgroundID = backgroundID
	state.RemainingTicks = session.RemainingTicks
	state.Skippable = rule.Skippable
	state.ContinueLabel = runtime.localizeRuleTextLocked(
		"Enter / Space Continue",
		"ui.cutscene.continue",
	)
	state.SkipLabel = runtime.localizeRuleTextLocked(
		"Esc Skip",
		"ui.cutscene.skip",
	)
	return state
}

func (runtime *Runtime) cutsceneViewLocked() ebitapp.CutsceneView {
	state := runtime.cutsceneStateLocked()
	return ebitapp.CutsceneView{
		Active:         state.Active,
		ID:             state.ID,
		Name:           state.Name,
		StepID:         state.StepID,
		StepIndex:      state.StepIndex,
		StepCount:      state.StepCount,
		Speaker:        state.Speaker,
		Text:           state.Text,
		BackgroundID:   state.BackgroundID,
		RemainingTicks: state.RemainingTicks,
		Skippable:      state.Skippable,
		ContinueLabel:  state.ContinueLabel,
		SkipLabel:      state.SkipLabel,
	}
}

func (runtime *Runtime) handleCutsceneActionsLocked(
	actions ebitapp.Actions,
) (bool, error) {
	if runtime.cutscene == nil {
		return false, nil
	}
	cancel := actions.MenuCancel || runtime.virtualPressed("menu_cancel")
	confirm := actions.MenuConfirm || runtime.virtualPressed("menu_confirm")
	runtime.advanceVirtualLocked()

	if cancel {
		rule, exists := runtime.contentRules.Cutscene(
			runtime.cutscene.CutsceneID,
		)
		if exists && rule.Skippable {
			return true, runtime.skipCutsceneLocked()
		}
		return true, nil
	}
	if confirm {
		return true, runtime.advanceCutsceneLocked()
	}
	if runtime.cutscene.RemainingTicks > 0 {
		runtime.cutscene.RemainingTicks--
		if runtime.cutscene.RemainingTicks == 0 {
			return true, runtime.advanceCutsceneLocked()
		}
		runtime.revision++
	}
	return true, nil
}

func (runtime *Runtime) startCutsceneLocked(
	cutsceneID string,
	speakerID string,
	healTargetID string,
	triggerID string,
) error {
	if runtime.cutscene != nil {
		return errors.New("another cutscene is already active")
	}
	if runtime.campaign.Snapshot().Mode != campaign.ModePlaying {
		return errors.New("cutscene can only start during gameplay")
	}
	if runtime.turnBattle != nil ||
		runtime.dialogue != nil ||
		runtime.activeShopID != "" ||
		runtime.inventoryOpen {
		return errors.New("cutscene cannot start while another modal is active")
	}
	rule, exists := runtime.contentRules.Cutscene(cutsceneID)
	if !exists {
		return fmt.Errorf("unknown cutscene %q", cutsceneID)
	}
	if len(rule.Steps) == 0 {
		return fmt.Errorf("cutscene %q has no steps", cutsceneID)
	}

	checkpoint := runtime.checkpointLocked()
	if err := runtime.detachMutableLocked(checkpoint); err != nil {
		return err
	}
	runtime.cutscene = &cutsceneSession{
		CutsceneID:   cutsceneID,
		StepIndex:    0,
		SpeakerID:    speakerID,
		HealTargetID: healTargetID,
		TriggerID:    triggerID,
	}
	if err := runtime.enterCutsceneStepLocked(rule, 0); err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return fmt.Errorf("start cutscene %q: %w", cutsceneID, err)
	}
	runtime.queueAudioEventLocked("cutscene.started")
	runtime.revision++
	return nil
}

func (runtime *Runtime) enterCutsceneStepLocked(
	rule gamebuild.CutsceneRule,
	index int,
) error {
	if runtime.cutscene == nil {
		return errors.New("no active cutscene")
	}
	if index < 0 || index >= len(rule.Steps) {
		return fmt.Errorf("cutscene step %d is unavailable", index)
	}
	step := rule.Steps[index]
	runtime.cutscene.StepIndex = index
	runtime.cutscene.RemainingTicks = step.DurationTicks
	result, err := runtime.ruleExecutor.Execute(
		runtime.campaign,
		step.Actions,
	)
	if err != nil {
		return fmt.Errorf("step %q actions: %w", step.ID, err)
	}
	if err := runtime.applyRuleIntentsForTargetLocked(
		result.Intents,
		runtime.cutscene.SpeakerID,
		runtime.cutscene.HealTargetID,
		runtime.cutscene.TriggerID,
	); err != nil {
		return fmt.Errorf("step %q intents: %w", step.ID, err)
	}
	if runtime.campaign.Snapshot().Mode != campaign.ModePlaying {
		runtime.cutscene = nil
	}
	return nil
}

func (runtime *Runtime) advanceCutsceneLocked() error {
	if runtime.cutscene == nil {
		return errors.New("no active cutscene")
	}
	rule, exists := runtime.contentRules.Cutscene(
		runtime.cutscene.CutsceneID,
	)
	if !exists {
		return fmt.Errorf("unknown cutscene %q", runtime.cutscene.CutsceneID)
	}
	checkpoint := runtime.checkpointLocked()
	if err := runtime.detachMutableLocked(checkpoint); err != nil {
		return err
	}
	next := runtime.cutscene.StepIndex + 1
	if next < len(rule.Steps) {
		if err := runtime.enterCutsceneStepLocked(rule, next); err != nil {
			runtime.restoreCheckpointLocked(checkpoint)
			return fmt.Errorf("advance cutscene %q: %w", rule.ID, err)
		}
		runtime.queueAudioEventLocked("cutscene.step_entered")
		runtime.revision++
		return nil
	}
	if err := runtime.completeCutsceneLocked(rule.OnComplete); err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return fmt.Errorf("complete cutscene %q: %w", rule.ID, err)
	}
	runtime.queueAudioEventLocked("cutscene.completed")
	runtime.revision++
	return nil
}

func (runtime *Runtime) skipCutsceneLocked() error {
	if runtime.cutscene == nil {
		return errors.New("no active cutscene")
	}
	rule, exists := runtime.contentRules.Cutscene(
		runtime.cutscene.CutsceneID,
	)
	if !exists {
		return fmt.Errorf("unknown cutscene %q", runtime.cutscene.CutsceneID)
	}
	if !rule.Skippable {
		return fmt.Errorf("cutscene %q is not skippable", rule.ID)
	}
	checkpoint := runtime.checkpointLocked()
	if err := runtime.detachMutableLocked(checkpoint); err != nil {
		return err
	}
	actions := make([]gamebuild.RuleAction, 0)
	for index := runtime.cutscene.StepIndex + 1; index < len(rule.Steps); index++ {
		actions = append(actions, rule.Steps[index].Actions...)
	}
	actions = append(actions, rule.OnComplete...)
	if err := runtime.completeCutsceneLocked(actions); err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return fmt.Errorf("skip cutscene %q: %w", rule.ID, err)
	}
	runtime.queueAudioEventLocked("cutscene.skipped")
	runtime.revision++
	return nil
}

func (runtime *Runtime) completeCutsceneLocked(
	actions []gamebuild.RuleAction,
) error {
	session := cloneCutsceneSession(runtime.cutscene)
	if session == nil {
		return errors.New("no active cutscene")
	}
	runtime.cutscene = nil
	result, err := runtime.ruleExecutor.Execute(runtime.campaign, actions)
	if err != nil {
		return err
	}
	if err := runtime.applyRuleIntentsForTargetLocked(
		result.Intents,
		session.SpeakerID,
		session.HealTargetID,
		session.TriggerID,
	); err != nil {
		return err
	}
	return nil
}
