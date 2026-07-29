package gameapp

import (
	"errors"
	"fmt"
	"math"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/rulesruntime"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

// DialogueChoiceState is one currently eligible authored choice.
type DialogueChoiceState struct {
	ID       string `json:"id"`
	Text     string `json:"text"`
	TextKey  string `json:"text_key,omitempty"`
	Selected bool   `json:"selected"`
}

// DialogueState is the gameapp-owned transient dialogue contract shared by
// presentation and debug adapters. It preserves the old simulation fields
// while exposing the authored graph node and eligible choices.
type DialogueState struct {
	Active        bool                  `json:"active"`
	ID            string                `json:"id,omitempty"`
	NPCID         string                `json:"npc_id,omitempty"`
	NodeID        string                `json:"node_id,omitempty"`
	Name          string                `json:"name,omitempty"`
	NameKey       string                `json:"name_key,omitempty"`
	Speaker       string                `json:"speaker,omitempty"`
	SpeakerKey    string                `json:"speaker_key,omitempty"`
	Text          string                `json:"text,omitempty"`
	TextKey       string                `json:"text_key,omitempty"`
	Choices       []DialogueChoiceState `json:"choices"`
	SelectedIndex int                   `json:"selected_index"`
}

func buildRuleRuntime(
	catalog *content.Catalog,
	config campaign.Config,
) (
	gamebuild.ContentRules,
	*rulesruntime.Executor,
	error,
) {
	rules, err := gamebuild.BuildContentRules(catalog)
	if err != nil {
		return gamebuild.ContentRules{}, nil, fmt.Errorf(
			"build campaign rules: %w",
			err,
		)
	}
	executor, err := rulesruntime.New(config, rules)
	if err != nil {
		return gamebuild.ContentRules{}, nil, fmt.Errorf(
			"construct campaign rule executor: %w",
			err,
		)
	}
	return rules, executor, nil
}

func (runtime *Runtime) resetRulePresentationLocked() {
	runtime.dialogue = nil
	runtime.dialogueSpeakerID = ""
	runtime.dialogueChoiceIndex = 0
	runtime.activeShopID = ""
	runtime.shopSelectedIndex = 0
	runtime.shopStatus = ""
	runtime.inventoryOpen = false
	runtime.inventorySelected = 0
	runtime.inventoryStatus = ""
	runtime.equipmentRebuildPending = false
}

// handleDomainInteractionLocked selects the nearest eligible authored
// interaction for the controlled actor. It is the common boundary for
// dialogue, shop, and later interaction intents. Preview entities deliberately
// remain on the legacy simulation path.
func (runtime *Runtime) handleDomainInteractionLocked(
	snapshot sim.Snapshot,
) (bool, error) {
	if runtime.ruleExecutor == nil || runtime.campaign == nil {
		return false, errors.New(
			"handle authored interaction: campaign rules are unavailable",
		)
	}
	entities := make(map[string]sim.EntitySnapshot, len(snapshot.Entities))
	for _, entity := range snapshot.Entities {
		entities[entity.ID] = entity
	}
	var controlled sim.EntitySnapshot
	controlledFound := false
	for _, metadata := range runtime.built.Presentation.Instances {
		if !metadata.Controlled {
			continue
		}
		entity, exists := entities[metadata.ID]
		if !exists || entity.Dead {
			return false, nil
		}
		controlled = entity
		controlledFound = true
		break
	}
	if !controlledFound || snapshot.HitstopTicks != 0 ||
		controlled.StaggerTicks != 0 ||
		controlled.KnockbackTicks != 0 ||
		controlled.DodgeTicks != 0 {
		return false, nil
	}

	type candidate struct {
		entity      sim.EntitySnapshot
		metadata    gamebuild.InstanceMetadata
		interaction gamebuild.ActorInteractionRule
		distance    uint64
	}
	var selected *candidate
	for _, metadata := range runtime.built.Presentation.Instances {
		if metadata.Controlled {
			continue
		}
		interaction, exists := runtime.contentRules.Interaction(
			metadata.ActorID,
		)
		if !exists || interaction.Input != "interact" {
			continue
		}
		entity, exists := entities[metadata.ID]
		if !exists || entity.Dead {
			continue
		}
		rangeLimit, err := fixedFromPixels(interaction.Range)
		if err != nil {
			return false, fmt.Errorf(
				"handle authored interaction %q: invalid range: %w",
				metadata.ActorID,
				err,
			)
		}
		deltaX := entity.Position.X - controlled.Position.X
		deltaY := entity.Position.Y - controlled.Position.Y
		distance := squaredCoords(deltaX, deltaY)
		if distance > squaredCoords(rangeLimit, 0) {
			continue
		}
		eligible, err := runtime.ruleExecutor.EvaluateCondition(
			runtime.campaign,
			interaction.Condition,
		)
		if err != nil {
			return false, fmt.Errorf(
				"handle authored interaction %q condition: %w",
				metadata.ActorID,
				err,
			)
		}
		if !eligible {
			continue
		}
		if selected == nil || distance < selected.distance ||
			(distance == selected.distance &&
				metadata.ID < selected.metadata.ID) {
			selected = &candidate{
				entity:      entity,
				metadata:    metadata,
				interaction: interaction,
				distance:    distance,
			}
		}
	}
	if selected == nil {
		return false, nil
	}

	result, err := runtime.ruleExecutor.Execute(
		runtime.campaign,
		selected.interaction.Actions,
	)
	if err != nil {
		return false, fmt.Errorf(
			"execute authored interaction for entity %q actor %q: %w",
			selected.metadata.ID,
			selected.metadata.ActorID,
			err,
		)
	}
	runtime.activeShopID = ""
	runtime.shopSelectedIndex = 0
	runtime.shopStatus = ""
	if err := runtime.applyRuleIntentsLocked(
		result.Intents,
		selected.metadata.ID,
	); err != nil {
		return false, fmt.Errorf(
			"apply authored interaction for entity %q actor %q: %w",
			selected.metadata.ID,
			selected.metadata.ActorID,
			err,
		)
	}
	return true, nil
}

// applyObjectiveEventsLocked translates the simulation's instance identity to
// the authored ActorID used by quest rules. Only current, active objectives
// with remaining capacity are forwarded; unrelated and already-consumed kills
// stay valid simulation events instead of turning a tick into an error.
func (runtime *Runtime) applyObjectiveEventsLocked(
	events []sim.Event,
) error {
	for _, event := range events {
		if event.Type != sim.EventActorKilled {
			continue
		}
		metadata, exists := runtime.metadata(event.TargetID)
		if !exists {
			return fmt.Errorf(
				"actor kill target %q has no instance metadata",
				event.TargetID,
			)
		}
		if !runtime.hasActiveObjectiveRemainingLocked(
			string(event.Type),
			metadata.ActorID,
		) {
			continue
		}
		result, err := runtime.ruleExecutor.ApplyObjectiveEvent(
			runtime.campaign,
			rulesruntime.ObjectiveEvent{
				Event:   string(event.Type),
				ActorID: metadata.ActorID,
				Count:   1,
			},
		)
		if err != nil {
			return fmt.Errorf(
				"apply kill of entity %q actor %q: %w",
				event.TargetID,
				metadata.ActorID,
				err,
			)
		}
		if err := runtime.applyRuleIntentsLocked(
			result.Intents,
			"",
		); err != nil {
			return fmt.Errorf(
				"apply completion intents after entity %q actor %q: %w",
				event.TargetID,
				metadata.ActorID,
				err,
			)
		}
		for range result.CompletedQuestIDs {
			runtime.queueAudioEventLocked("quest.completed")
		}
	}
	return nil
}

func (runtime *Runtime) hasActiveObjectiveRemainingLocked(
	event string,
	actorID string,
) bool {
	state := runtime.campaign.Snapshot()
	quests := make(map[string]campaign.QuestState, len(state.Quests))
	for _, quest := range state.Quests {
		quests[quest.ID] = quest
	}
	for _, rule := range runtime.contentRules.Quests {
		quest, exists := quests[rule.ID]
		if !exists || quest.Status != campaign.QuestActive {
			continue
		}
		objectives := make(
			map[string]campaign.ObjectiveState,
			len(quest.Objectives),
		)
		for _, objective := range quest.Objectives {
			objectives[objective.ID] = objective
		}
		for _, objective := range rule.Objectives {
			if objective.Event != event || objective.ActorID != actorID {
				continue
			}
			progress, exists := objectives[objective.ID]
			if exists && progress.Count < int64(objective.Count) {
				return true
			}
		}
	}
	return false
}

func (runtime *Runtime) applyRuleIntentsLocked(
	intents []rulesruntime.Intent,
	speakerID string,
) error {
	for _, intent := range intents {
		switch intent.Type {
		case rulesruntime.IntentStartDialogue:
			if runtime.dialogue != nil {
				return fmt.Errorf(
					"dialogue %q cannot start while another dialogue is active",
					intent.DialogueID,
				)
			}
			if runtime.activeShopID != "" {
				return fmt.Errorf(
					"dialogue %q cannot start while shop %q is active",
					intent.DialogueID,
					runtime.activeShopID,
				)
			}
			if runtime.inventoryOpen {
				return fmt.Errorf(
					"dialogue %q cannot start while inventory is active",
					intent.DialogueID,
				)
			}
			session, result, err := runtime.ruleExecutor.StartDialogue(
				runtime.campaign,
				intent.DialogueID,
			)
			if err != nil {
				return err
			}
			runtime.dialogue = session
			runtime.dialogueSpeakerID = speakerID
			runtime.dialogueChoiceIndex = 0
			if err := runtime.applyRuleIntentsLocked(
				result.Intents,
				speakerID,
			); err != nil {
				return err
			}

		case rulesruntime.IntentOpenShop:
			if runtime.dialogue != nil {
				return fmt.Errorf(
					"shop %q cannot open while a dialogue is active",
					intent.ShopID,
				)
			}
			if runtime.inventoryOpen {
				return fmt.Errorf(
					"shop %q cannot open while inventory is active",
					intent.ShopID,
				)
			}
			runtime.activeShopID = intent.ShopID
			runtime.shopSelectedIndex = 0
			runtime.shopStatus = ""

		case rulesruntime.IntentHeal:
			if err := runtime.applyHealIntentLocked(
				intent.HealAmount,
			); err != nil {
				return err
			}

		default:
			return fmt.Errorf("unsupported rule intent %q", intent.Type)
		}
	}
	return nil
}

func (runtime *Runtime) applyHealIntentLocked(amount float64) error {
	if math.IsNaN(amount) || math.IsInf(amount, 0) ||
		amount <= 0 || math.Trunc(amount) != amount ||
		amount > float64(math.MaxInt) {
		return fmt.Errorf("heal amount %v is invalid", amount)
	}
	state := runtime.simulation.SaveSession()
	controlledID := runtime.built.Config.Camera.TargetEntityID
	for index := range state.Entities {
		if state.Entities[index].ID != controlledID {
			continue
		}
		if state.Entities[index].Dead {
			return errors.New("heal intent cannot revive the controlled actor")
		}
		definition, exists := runtime.entityConfig(controlledID)
		if !exists {
			return fmt.Errorf(
				"heal intent controlled entity %q has no definition",
				controlledID,
			)
		}
		increment := int(amount)
		state.Entities[index].Health = min(
			definition.MaxHealth,
			state.Entities[index].Health+increment,
		)
		if err := runtime.simulation.LoadSession(state); err != nil {
			return fmt.Errorf("apply heal intent: %w", err)
		}
		return nil
	}
	return fmt.Errorf(
		"heal intent controlled entity %q is missing",
		controlledID,
	)
}

// DialogueState returns a detached transient dialogue view. When a Maker
// preview owns the old simulation dialogue, its legacy fields remain visible.
func (runtime *Runtime) DialogueState() (DialogueState, error) {
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	return runtime.dialogueStateLocked()
}

func (runtime *Runtime) dialogueStateLocked() (DialogueState, error) {
	if runtime.dialogue == nil {
		legacy := runtime.simulation.Snapshot().Dialogue
		return DialogueState{
			Active:  legacy.Active,
			ID:      legacy.ID,
			NPCID:   legacy.NPCID,
			Speaker: legacy.Speaker,
			Text:    legacy.Text,
			Choices: []DialogueChoiceState{},
		}, nil
	}
	view, err := runtime.dialogue.View()
	if err != nil {
		return DialogueState{}, err
	}
	selectedIndex := runtime.dialogueChoiceIndex
	if len(view.Choices) == 0 {
		selectedIndex = 0
	} else {
		selectedIndex = min(
			max(selectedIndex, 0),
			len(view.Choices)-1,
		)
	}
	result := DialogueState{
		Active:  true,
		ID:      view.DialogueID,
		NPCID:   runtime.dialogueSpeakerID,
		NodeID:  view.NodeID,
		Name:    runtime.localizeRuleTextLocked(view.Name, view.NameKey),
		NameKey: view.NameKey,
		Speaker: runtime.localizeRuleTextLocked(
			view.Speaker,
			view.SpeakerKey,
		),
		SpeakerKey:    view.SpeakerKey,
		Text:          runtime.localizeRuleTextLocked(view.Text, view.TextKey),
		TextKey:       view.TextKey,
		SelectedIndex: selectedIndex,
		Choices: make(
			[]DialogueChoiceState,
			len(view.Choices),
		),
	}
	for index, choice := range view.Choices {
		result.Choices[index] = DialogueChoiceState{
			ID:       choice.ID,
			Text:     runtime.localizeRuleTextLocked(choice.Text, choice.TextKey),
			TextKey:  choice.TextKey,
			Selected: index == selectedIndex,
		}
	}
	return result, nil
}

func (runtime *Runtime) localizeRuleTextLocked(
	literal string,
	key string,
) string {
	if key == "" {
		return literal
	}
	type localeDefinition struct {
		Strings map[string]string `json:"strings"`
	}
	localeIDs := []string{runtime.buildOptions.LocaleID}
	fallback := runtime.catalog.Project().Locale.Fallback
	if fallback != "" && fallback != runtime.buildOptions.LocaleID {
		localeIDs = append(localeIDs, fallback)
	}
	for _, localeID := range localeIDs {
		var locale localeDefinition
		if err := runtime.catalog.Decode(localeID, &locale); err != nil {
			continue
		}
		if value := locale.Strings[key]; value != "" {
			return value
		}
	}
	if literal != "" {
		return literal
	}
	return key
}

// MoveDialogueSelection updates only ephemeral UI selection and wraps in
// authored eligible-choice order.
func (runtime *Runtime) MoveDialogueSelection(delta int) (
	DialogueState,
	error,
) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	return runtime.moveDialogueSelectionLocked(delta)
}

func (runtime *Runtime) moveDialogueSelectionLocked(delta int) (
	DialogueState,
	error,
) {
	if runtime.dialogue == nil {
		return DialogueState{}, errors.New("move dialogue selection: no dialogue")
	}
	view, err := runtime.dialogue.View()
	if err != nil {
		return DialogueState{}, err
	}
	if len(view.Choices) != 0 && delta != 0 {
		index := (runtime.dialogueChoiceIndex + delta) % len(view.Choices)
		if index < 0 {
			index += len(view.Choices)
		}
		runtime.dialogueChoiceIndex = index
		runtime.revision++
	}
	return runtime.dialogueStateLocked()
}

func (runtime *Runtime) ChooseDialogue(choiceID string) (
	DialogueState,
	error,
) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	return runtime.chooseDialogueLocked(choiceID)
}

func (runtime *Runtime) chooseDialogueLocked(
	choiceID string,
) (DialogueState, error) {
	if runtime.dialogue == nil {
		return DialogueState{}, errors.New("choose dialogue: no dialogue")
	}
	checkpoint := runtime.checkpointLocked()
	if err := runtime.detachMutableLocked(checkpoint); err != nil {
		return DialogueState{}, err
	}
	session := runtime.dialogue
	result, err := session.Choose(choiceID)
	if err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return DialogueState{}, err
	}
	speakerID := runtime.dialogueSpeakerID
	if session.Closed() {
		runtime.dialogue = nil
		runtime.dialogueSpeakerID = ""
		runtime.dialogueChoiceIndex = 0
	}
	if err := runtime.applyRuleIntentsLocked(
		result.Intents,
		speakerID,
	); err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return DialogueState{}, err
	}
	if err := runtime.reconcileEquipmentChangeLocked(
		checkpoint.campaign,
		true,
	); err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return DialogueState{}, err
	}
	if runtime.dialogue == session {
		runtime.dialogueChoiceIndex = 0
	}
	runtime.queueAudioEventLocked("ui.confirm")
	runtime.revision++
	return runtime.dialogueStateLocked()
}

func (runtime *Runtime) AdvanceDialogue() (DialogueState, error) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	return runtime.advanceDialogueLocked()
}

func (runtime *Runtime) advanceDialogueLocked() (
	DialogueState,
	error,
) {
	if runtime.dialogue == nil {
		return DialogueState{}, errors.New("advance dialogue: no dialogue")
	}
	checkpoint := runtime.checkpointLocked()
	if err := runtime.detachMutableLocked(checkpoint); err != nil {
		return DialogueState{}, err
	}
	session := runtime.dialogue
	result, err := session.Advance()
	if err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return DialogueState{}, err
	}
	speakerID := runtime.dialogueSpeakerID
	if session.Closed() {
		runtime.dialogue = nil
		runtime.dialogueSpeakerID = ""
		runtime.dialogueChoiceIndex = 0
	}
	if err := runtime.applyRuleIntentsLocked(
		result.Intents,
		speakerID,
	); err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return DialogueState{}, err
	}
	if err := runtime.reconcileEquipmentChangeLocked(
		checkpoint.campaign,
		true,
	); err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return DialogueState{}, err
	}
	runtime.queueAudioEventLocked("ui.confirm")
	runtime.revision++
	return runtime.dialogueStateLocked()
}

func (runtime *Runtime) ConfirmDialogue() (DialogueState, error) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	return runtime.confirmDialogueLocked()
}

func (runtime *Runtime) confirmDialogueLocked() (DialogueState, error) {
	if runtime.dialogue == nil {
		return DialogueState{}, errors.New("confirm dialogue: no dialogue")
	}
	view, err := runtime.dialogue.View()
	if err != nil {
		return DialogueState{}, err
	}
	if len(view.Choices) == 0 {
		return runtime.advanceDialogueLocked()
	}
	index := min(max(runtime.dialogueChoiceIndex, 0), len(view.Choices)-1)
	return runtime.chooseDialogueLocked(view.Choices[index].ID)
}

func (runtime *Runtime) CancelDialogue() (DialogueState, error) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	return runtime.cancelDialogueLocked()
}

func (runtime *Runtime) cancelDialogueLocked() (DialogueState, error) {
	if runtime.dialogue == nil {
		return DialogueState{}, errors.New("cancel dialogue: no dialogue")
	}
	view, err := runtime.dialogue.View()
	if err != nil {
		return DialogueState{}, err
	}
	for _, choice := range view.Choices {
		if choice.ID == "leave" {
			return runtime.chooseDialogueLocked(choice.ID)
		}
	}
	runtime.dialogue = nil
	runtime.dialogueSpeakerID = ""
	runtime.dialogueChoiceIndex = 0
	runtime.queueAudioEventLocked("ui.cancel")
	runtime.revision++
	return runtime.dialogueStateLocked()
}

// CampaignState returns a detached durable debug view without exposing the
// mutable Campaign object.
func (runtime *Runtime) CampaignState() campaign.State {
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	return runtime.campaign.Snapshot()
}
