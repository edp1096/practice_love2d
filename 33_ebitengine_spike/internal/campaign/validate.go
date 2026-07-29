package campaign

import (
	"fmt"
	"regexp"
	"strings"
)

var (
	identifierPattern = regexp.MustCompile(
		`^[A-Za-z][A-Za-z0-9_.-]{0,127}$`,
	)
	identityPattern = regexp.MustCompile(
		`^[A-Za-z0-9][A-Za-z0-9._:+@/-]{0,255}$`,
	)
)

// Validate verifies the complete configuration without mutating it.
func (config Config) Validate() error {
	if config.Version != CurrentConfigVersion {
		return fmt.Errorf(
			"campaign config version %d is unsupported",
			config.Version,
		)
	}
	if err := validateIdentifier("project id", config.ProjectID); err != nil {
		return err
	}
	if err := validateIdentity("content id", config.ContentID); err != nil {
		return err
	}
	if len(config.Locales) == 0 {
		if config.DefaultLocale != "" {
			return fmt.Errorf(
				"default locale %q is configured without locales",
				config.DefaultLocale,
			)
		}
	} else {
		if err := validateUniqueIdentifiers(
			"locale",
			config.Locales,
		); err != nil {
			return err
		}
		if !containsString(config.Locales, config.DefaultLocale) {
			return fmt.Errorf(
				"default locale %q is not configured",
				config.DefaultLocale,
			)
		}
	}

	if len(config.Stages) == 0 {
		return fmt.Errorf("campaign config requires at least one stage")
	}
	stageIndexes := make(map[string]int, len(config.Stages))
	for index, stage := range config.Stages {
		if err := validateIdentifier("stage id", stage.ID); err != nil {
			return fmt.Errorf("stages[%d]: %w", index, err)
		}
		if _, exists := stageIndexes[stage.ID]; exists {
			return fmt.Errorf("duplicate stage id %q", stage.ID)
		}
		stageIndexes[stage.ID] = index
		if len(stage.EntrySpawns) == 0 {
			return fmt.Errorf(
				"stage %q requires at least one entry spawn",
				stage.ID,
			)
		}
		if err := validateUniqueIdentifiers(
			"entry spawn",
			stage.EntrySpawns,
		); err != nil {
			return fmt.Errorf("stage %q: %w", stage.ID, err)
		}
	}
	initialStageIndex, exists := stageIndexes[config.InitialStageID]
	if !exists {
		return fmt.Errorf(
			"initial stage %q is not configured",
			config.InitialStageID,
		)
	}
	if !containsString(
		config.Stages[initialStageIndex].EntrySpawns,
		config.InitialEntrySpawnID,
	) {
		return fmt.Errorf(
			"initial entry spawn %q is not configured for stage %q",
			config.InitialEntrySpawnID,
			config.InitialStageID,
		)
	}

	if err := validateUniqueIdentifiers("flag", config.Flags); err != nil {
		return err
	}
	if err := validateUniqueIdentifiers(
		"equipment slot",
		config.EquipmentSlots,
	); err != nil {
		return err
	}
	slotSet := stringSet(config.EquipmentSlots)

	itemSet := make(map[string]struct{}, len(config.Items))
	for index, item := range config.Items {
		if err := validateIdentifier("item id", item.ID); err != nil {
			return fmt.Errorf("items[%d]: %w", index, err)
		}
		if _, exists := itemSet[item.ID]; exists {
			return fmt.Errorf("duplicate item id %q", item.ID)
		}
		itemSet[item.ID] = struct{}{}
		if item.MaxQuantity <= 0 ||
			item.MaxQuantity > MaxJSONInteger {
			return fmt.Errorf(
				"item %q max quantity must be in [1, %d]",
				item.ID,
				MaxJSONInteger,
			)
		}
		if item.EquipmentSlot != "" {
			if _, exists := slotSet[item.EquipmentSlot]; !exists {
				return fmt.Errorf(
					"item %q references unknown equipment slot %q",
					item.ID,
					item.EquipmentSlot,
				)
			}
		}
	}

	questSet := make(map[string]struct{}, len(config.Quests))
	for questIndex, quest := range config.Quests {
		if err := validateIdentifier("quest id", quest.ID); err != nil {
			return fmt.Errorf("quests[%d]: %w", questIndex, err)
		}
		if _, exists := questSet[quest.ID]; exists {
			return fmt.Errorf("duplicate quest id %q", quest.ID)
		}
		questSet[quest.ID] = struct{}{}
		if len(quest.Objectives) == 0 {
			return fmt.Errorf(
				"quest %q requires at least one objective",
				quest.ID,
			)
		}
		objectiveSet := make(
			map[string]struct{},
			len(quest.Objectives),
		)
		for objectiveIndex, objective := range quest.Objectives {
			if err := validateIdentifier(
				"objective id",
				objective.ID,
			); err != nil {
				return fmt.Errorf(
					"quest %q objectives[%d]: %w",
					quest.ID,
					objectiveIndex,
					err,
				)
			}
			if _, exists := objectiveSet[objective.ID]; exists {
				return fmt.Errorf(
					"quest %q has duplicate objective id %q",
					quest.ID,
					objective.ID,
				)
			}
			objectiveSet[objective.ID] = struct{}{}
			if objective.Required <= 0 ||
				objective.Required > MaxJSONInteger {
				return fmt.Errorf(
					"quest %q objective %q required count "+
						"must be in [1, %d]",
					quest.ID,
					objective.ID,
					MaxJSONInteger,
				)
			}
		}
	}
	return nil
}

// Validate verifies a complete detached state against a Config.
func (state State) Validate(config Config) error {
	prepared, err := prepareConfig(config)
	if err != nil {
		return fmt.Errorf("validate campaign state config: %w", err)
	}
	return validateState(state, prepared)
}

func validateState(state State, config Config) error {
	if state.Version != CurrentStateVersion {
		return fmt.Errorf(
			"campaign state version %d is unsupported",
			state.Version,
		)
	}
	if state.ProjectID != config.ProjectID {
		return fmt.Errorf(
			"state project id %q does not match %q",
			state.ProjectID,
			config.ProjectID,
		)
	}
	if state.ContentID != config.ContentID {
		return fmt.Errorf(
			"state content id %q does not match %q",
			state.ContentID,
			config.ContentID,
		)
	}
	if !validMode(state.Mode) {
		return fmt.Errorf("invalid campaign mode %q", state.Mode)
	}
	if err := validateFlow(state.Flow, state.Mode); err != nil {
		return err
	}
	if len(config.Locales) == 0 {
		if state.Locale != "" {
			return fmt.Errorf(
				"state locale %q is configured without locales",
				state.Locale,
			)
		}
	} else if !containsString(config.Locales, state.Locale) {
		return fmt.Errorf("state locale %q is not configured", state.Locale)
	}
	if err := validateLocation(state, config); err != nil {
		return err
	}
	if state.Currency < 0 || state.Currency > MaxJSONInteger {
		return fmt.Errorf(
			"currency must be in [0, %d]",
			MaxJSONInteger,
		)
	}

	if len(state.Flags) != len(config.Flags) {
		return fmt.Errorf(
			"state has %d flags; expected %d",
			len(state.Flags),
			len(config.Flags),
		)
	}
	seenFlags := make(map[string]struct{}, len(state.Flags))
	for index, flag := range state.Flags {
		if _, exists := seenFlags[flag.ID]; exists {
			return fmt.Errorf("state has duplicate flag id %q", flag.ID)
		}
		seenFlags[flag.ID] = struct{}{}
		if flag.ID != config.Flags[index] {
			return fmt.Errorf(
				"state flag %d is %q; expected %q",
				index,
				flag.ID,
				config.Flags[index],
			)
		}
	}

	if len(state.Inventory) != len(config.Items) {
		return fmt.Errorf(
			"state has %d inventory entries; expected %d",
			len(state.Inventory),
			len(config.Items),
		)
	}
	itemQuantities := make(map[string]int64, len(state.Inventory))
	for index, entry := range state.Inventory {
		if _, exists := itemQuantities[entry.ItemID]; exists {
			return fmt.Errorf(
				"state has duplicate inventory item id %q",
				entry.ItemID,
			)
		}
		itemDefinition := config.Items[index]
		if entry.ItemID != itemDefinition.ID {
			return fmt.Errorf(
				"state inventory entry %d is %q; expected %q",
				index,
				entry.ItemID,
				itemDefinition.ID,
			)
		}
		if entry.Quantity < 0 ||
			entry.Quantity > itemDefinition.MaxQuantity {
			return fmt.Errorf(
				"inventory item %q quantity must be in [0, %d]",
				entry.ItemID,
				itemDefinition.MaxQuantity,
			)
		}
		itemQuantities[entry.ItemID] = entry.Quantity
	}

	if len(state.Equipment) != len(config.EquipmentSlots) {
		return fmt.Errorf(
			"state has %d equipment entries; expected %d",
			len(state.Equipment),
			len(config.EquipmentSlots),
		)
	}
	itemDefinitions := make(map[string]ItemDefinition, len(config.Items))
	for _, item := range config.Items {
		itemDefinitions[item.ID] = item
	}
	seenSlots := make(map[string]struct{}, len(state.Equipment))
	for index, entry := range state.Equipment {
		if _, exists := seenSlots[entry.SlotID]; exists {
			return fmt.Errorf(
				"state has duplicate equipment slot id %q",
				entry.SlotID,
			)
		}
		seenSlots[entry.SlotID] = struct{}{}
		if entry.SlotID != config.EquipmentSlots[index] {
			return fmt.Errorf(
				"state equipment entry %d is slot %q; expected %q",
				index,
				entry.SlotID,
				config.EquipmentSlots[index],
			)
		}
		if entry.ItemID == "" {
			continue
		}
		item, exists := itemDefinitions[entry.ItemID]
		if !exists {
			return fmt.Errorf(
				"equipment slot %q references unknown item %q",
				entry.SlotID,
				entry.ItemID,
			)
		}
		if item.EquipmentSlot != entry.SlotID {
			return fmt.Errorf(
				"item %q cannot be equipped in slot %q",
				entry.ItemID,
				entry.SlotID,
			)
		}
		if itemQuantities[entry.ItemID] < 1 {
			return fmt.Errorf(
				"equipped item %q is not present in inventory",
				entry.ItemID,
			)
		}
	}

	if len(state.Quests) != len(config.Quests) {
		return fmt.Errorf(
			"state has %d quests; expected %d",
			len(state.Quests),
			len(config.Quests),
		)
	}
	seenQuests := make(map[string]struct{}, len(state.Quests))
	for questIndex, quest := range state.Quests {
		if _, exists := seenQuests[quest.ID]; exists {
			return fmt.Errorf("state has duplicate quest id %q", quest.ID)
		}
		seenQuests[quest.ID] = struct{}{}
		definition := config.Quests[questIndex]
		if quest.ID != definition.ID {
			return fmt.Errorf(
				"state quest %d is %q; expected %q",
				questIndex,
				quest.ID,
				definition.ID,
			)
		}
		if err := validateQuestState(quest, definition); err != nil {
			return err
		}
		if state.Flow.Started &&
			definition.InitiallyActive &&
			quest.Status == QuestInactive {
			return fmt.Errorf(
				"initially active quest %q cannot be inactive "+
					"during gameplay",
				quest.ID,
			)
		}
	}

	if !state.Flow.Started {
		if err := validatePristineCampaign(state); err != nil {
			return err
		}
	}
	return nil
}

func validateFlow(flow FlowProgress, mode Mode) error {
	if flow.Completed && !flow.Started {
		return fmt.Errorf("completed campaign flow requires started")
	}
	if !flow.Started {
		if mode != ModeTitle {
			return fmt.Errorf(
				"unstarted campaign flow requires title mode",
			)
		}
		return nil
	}
	if flow.Completed {
		if mode != ModeEnding && mode != ModeTitle {
			return fmt.Errorf(
				"completed campaign flow requires ending or title mode",
			)
		}
		return nil
	}
	if mode == ModeEnding {
		return fmt.Errorf(
			"ending mode requires completed campaign flow",
		)
	}
	return nil
}

func validateLocation(state State, config Config) error {
	if !state.Flow.Started {
		if state.CurrentStageID != "" || state.EntrySpawnID != "" {
			return fmt.Errorf(
				"unstarted campaign cannot reference a current stage " +
					"or entry spawn",
			)
		}
		return nil
	}
	if state.CurrentStageID == "" || state.EntrySpawnID == "" {
		return fmt.Errorf(
			"started campaign requires a current stage and entry spawn",
		)
	}
	for _, stage := range config.Stages {
		if stage.ID != state.CurrentStageID {
			continue
		}
		if !containsString(stage.EntrySpawns, state.EntrySpawnID) {
			return fmt.Errorf(
				"entry spawn %q is not configured for stage %q",
				state.EntrySpawnID,
				state.CurrentStageID,
			)
		}
		return nil
	}
	return fmt.Errorf(
		"current stage %q is not configured",
		state.CurrentStageID,
	)
}

func validateQuestState(
	state QuestState,
	definition QuestDefinition,
) error {
	switch state.Status {
	case QuestInactive, QuestActive, QuestCompleted:
	default:
		return fmt.Errorf(
			"quest %q has invalid status %q",
			state.ID,
			state.Status,
		)
	}
	if len(state.Objectives) != len(definition.Objectives) {
		return fmt.Errorf(
			"quest %q has %d objectives; expected %d",
			state.ID,
			len(state.Objectives),
			len(definition.Objectives),
		)
	}
	seen := make(map[string]struct{}, len(state.Objectives))
	allComplete := true
	for index, objective := range state.Objectives {
		if _, exists := seen[objective.ID]; exists {
			return fmt.Errorf(
				"quest %q has duplicate objective id %q",
				state.ID,
				objective.ID,
			)
		}
		seen[objective.ID] = struct{}{}
		expected := definition.Objectives[index]
		if objective.ID != expected.ID {
			return fmt.Errorf(
				"quest %q objective %d is %q; expected %q",
				state.ID,
				index,
				objective.ID,
				expected.ID,
			)
		}
		if objective.Count < 0 || objective.Count > expected.Required {
			return fmt.Errorf(
				"quest %q objective %q count must be in [0, %d]",
				state.ID,
				objective.ID,
				expected.Required,
			)
		}
		if objective.Count != expected.Required {
			allComplete = false
		}
		if state.Status == QuestInactive && objective.Count != 0 {
			return fmt.Errorf(
				"inactive quest %q cannot have objective progress",
				state.ID,
			)
		}
	}
	if state.Status == QuestActive && allComplete {
		return fmt.Errorf(
			"active quest %q has all objectives complete",
			state.ID,
		)
	}
	if state.Status == QuestCompleted && !allComplete {
		return fmt.Errorf(
			"completed quest %q has incomplete objectives",
			state.ID,
		)
	}
	return nil
}

func validatePristineCampaign(state State) error {
	if state.Currency != 0 {
		return fmt.Errorf("unstarted campaign cannot retain currency")
	}
	for _, flag := range state.Flags {
		if flag.Value {
			return fmt.Errorf(
				"unstarted campaign cannot retain flag %q",
				flag.ID,
			)
		}
	}
	for _, item := range state.Inventory {
		if item.Quantity != 0 {
			return fmt.Errorf(
				"unstarted campaign cannot retain inventory item %q",
				item.ItemID,
			)
		}
	}
	for _, entry := range state.Equipment {
		if entry.ItemID != "" {
			return fmt.Errorf(
				"unstarted campaign cannot retain equipped item %q",
				entry.ItemID,
			)
		}
	}
	for _, quest := range state.Quests {
		if quest.Status != QuestInactive {
			return fmt.Errorf(
				"unstarted campaign cannot retain quest %q status %q",
				quest.ID,
				quest.Status,
			)
		}
	}
	return nil
}

func validateIdentifier(label, value string) error {
	if !identifierPattern.MatchString(value) {
		return fmt.Errorf("%s %q is invalid", label, value)
	}
	return nil
}

func validateIdentity(label, value string) error {
	if strings.TrimSpace(value) != value ||
		!identityPattern.MatchString(value) {
		return fmt.Errorf("%s %q is invalid", label, value)
	}
	return nil
}

func validateUniqueIdentifiers(label string, values []string) error {
	seen := make(map[string]struct{}, len(values))
	for index, value := range values {
		if err := validateIdentifier(label, value); err != nil {
			return fmt.Errorf("%ss[%d]: %w", label, index, err)
		}
		if _, exists := seen[value]; exists {
			return fmt.Errorf("duplicate %s id %q", label, value)
		}
		seen[value] = struct{}{}
	}
	return nil
}

func validMode(mode Mode) bool {
	switch mode {
	case ModeTitle, ModePlaying, ModePaused, ModeGameOver, ModeEnding:
		return true
	default:
		return false
	}
}

func stringSet(values []string) map[string]struct{} {
	result := make(map[string]struct{}, len(values))
	for _, value := range values {
		result[value] = struct{}{}
	}
	return result
}

func containsString(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}
