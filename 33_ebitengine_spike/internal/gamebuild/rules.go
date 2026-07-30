package gamebuild

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

// RuleActionType is the closed set of content actions understood by the
// campaign rule runtime. An authored action outside this set is a compile
// error; it is never silently discarded.
type RuleActionType string

const (
	RuleActionStartQuest       RuleActionType = "start_quest"
	RuleActionGiveItem         RuleActionType = "give_item"
	RuleActionEquipItem        RuleActionType = "equip_item"
	RuleActionAddCurrency      RuleActionType = "add_currency"
	RuleActionSetFlag          RuleActionType = "set_flag"
	RuleActionFinishGame       RuleActionType = "finish_game"
	RuleActionOpenShop         RuleActionType = "open_shop"
	RuleActionStartDialogue    RuleActionType = "start_dialogue"
	RuleActionDamage           RuleActionType = "damage"
	RuleActionHeal             RuleActionType = "heal"
	RuleActionEmit             RuleActionType = "emit"
	RuleActionShowNotice       RuleActionType = "show_notice"
	RuleActionStartTurnBattle  RuleActionType = "start_turn_battle"
	RuleActionStartCutscene    RuleActionType = "start_cutscene"
	RuleActionSetWorldTime     RuleActionType = "set_world_time"
	RuleActionAdvanceWorldTime RuleActionType = "advance_world_time"
)

// RuleConditionType is the closed set of conditions understood by the
// campaign rule runtime.
type RuleConditionType string

const (
	RuleConditionAlways          RuleConditionType = "always"
	RuleConditionAll             RuleConditionType = "all"
	RuleConditionAny             RuleConditionType = "any"
	RuleConditionNot             RuleConditionType = "not"
	RuleConditionFlag            RuleConditionType = "flag"
	RuleConditionQuestState      RuleConditionType = "quest_state"
	RuleConditionTurnBattleState RuleConditionType = "turn_battle_state"
	RuleConditionCutsceneActive  RuleConditionType = "cutscene_active"
	RuleConditionTimeBetween     RuleConditionType = "time_between"
	RuleConditionRegionActive    RuleConditionType = "region_active"
)

type RuleQuestState string

const (
	RuleQuestInactive  RuleQuestState = "inactive"
	RuleQuestActive    RuleQuestState = "active"
	RuleQuestCompleted RuleQuestState = "completed"
)

type RuleTurnBattleState string

const (
	RuleTurnBattleNever   RuleTurnBattleState = "never"
	RuleTurnBattleActive  RuleTurnBattleState = "active"
	RuleTurnBattleWon     RuleTurnBattleState = "won"
	RuleTurnBattleLost    RuleTurnBattleState = "lost"
	RuleTurnBattleEscaped RuleTurnBattleState = "escaped"
)

// RuleCompilerCapabilities advertises the exact action and condition surface
// accepted by BuildContentRules. Returned capability slices are detached from
// compiler-owned storage.
type RuleCompilerCapabilities struct {
	Actions    []RuleActionType    `json:"actions"`
	Conditions []RuleConditionType `json:"conditions"`
}

var ruleCompilerCapabilities = RuleCompilerCapabilities{
	Actions: []RuleActionType{
		RuleActionStartQuest,
		RuleActionGiveItem,
		RuleActionEquipItem,
		RuleActionAddCurrency,
		RuleActionSetFlag,
		RuleActionFinishGame,
		RuleActionOpenShop,
		RuleActionStartDialogue,
		RuleActionDamage,
		RuleActionHeal,
		RuleActionEmit,
		RuleActionShowNotice,
		RuleActionStartTurnBattle,
		RuleActionStartCutscene,
		RuleActionSetWorldTime,
		RuleActionAdvanceWorldTime,
	},
	Conditions: []RuleConditionType{
		RuleConditionAlways,
		RuleConditionAll,
		RuleConditionAny,
		RuleConditionNot,
		RuleConditionFlag,
		RuleConditionQuestState,
		RuleConditionTurnBattleState,
		RuleConditionCutsceneActive,
		RuleConditionTimeBetween,
		RuleConditionRegionActive,
	},
}

func ContentRuleCapabilities() RuleCompilerCapabilities {
	return cloneRuleCapabilities(ruleCompilerCapabilities)
}

func (capabilities RuleCompilerCapabilities) SupportsAction(
	action RuleActionType,
) bool {
	for _, candidate := range capabilities.Actions {
		if candidate == action {
			return true
		}
	}
	return false
}

func (capabilities RuleCompilerCapabilities) SupportsCondition(
	condition RuleConditionType,
) bool {
	for _, candidate := range capabilities.Conditions {
		if candidate == condition {
			return true
		}
	}
	return false
}

// UnsupportedRuleCapabilityError identifies content that the rule compiler
// cannot execute yet. Callers can use errors.As to distinguish a feature gap
// from malformed content.
type UnsupportedRuleCapabilityError struct {
	Path       string
	Capability string
	Name       string
}

func (err *UnsupportedRuleCapabilityError) Error() string {
	if err == nil {
		return "<nil>"
	}
	return fmt.Sprintf(
		"%s uses unsupported %s capability %q",
		err.Path,
		err.Capability,
		err.Name,
	)
}

// RuleAction is a validated tagged union. Only fields appropriate for Type
// are populated by the compiler.
type RuleAction struct {
	Type         RuleActionType  `json:"type"`
	QuestID      string          `json:"quest_id,omitempty"`
	ItemID       string          `json:"item_id,omitempty"`
	DialogueID   string          `json:"dialogue_id,omitempty"`
	ShopID       string          `json:"shop_id,omitempty"`
	FlagName     string          `json:"flag_name,omitempty"`
	Reason       string          `json:"reason,omitempty"`
	Quantity     int             `json:"quantity,omitempty"`
	Currency     int             `json:"currency,omitempty"`
	FlagValue    bool            `json:"flag_value,omitempty"`
	DamageAmount float64         `json:"damage_amount,omitempty"`
	HealAmount   float64         `json:"heal_amount,omitempty"`
	EventName    string          `json:"event_name,omitempty"`
	EventData    json.RawMessage `json:"event_data,omitempty"`
	NoticeText   string          `json:"notice_text,omitempty"`
	NoticeKey    string          `json:"notice_key,omitempty"`
	NoticeTone   string          `json:"notice_tone,omitempty"`
	NoticeTicks  int             `json:"notice_ticks,omitempty"`
	BattleID     string          `json:"battle_id,omitempty"`
	CutsceneID   string          `json:"cutscene_id,omitempty"`
	WorldMinute  float64         `json:"world_minute,omitempty"`
	WorldDay     int64           `json:"world_day,omitempty"`
	WorldMinutes float64         `json:"world_minutes,omitempty"`
}

type RuleCondition struct {
	Type         RuleConditionType   `json:"type"`
	Conditions   []RuleCondition     `json:"conditions,omitempty"`
	Condition    *RuleCondition      `json:"condition,omitempty"`
	FlagName     string              `json:"flag_name,omitempty"`
	FlagValue    bool                `json:"flag_value,omitempty"`
	QuestID      string              `json:"quest_id,omitempty"`
	QuestState   RuleQuestState      `json:"quest_state,omitempty"`
	BattleID     string              `json:"battle_id,omitempty"`
	BattleState  RuleTurnBattleState `json:"battle_state,omitempty"`
	CutsceneID   string              `json:"cutscene_id,omitempty"`
	StartMinute  float64             `json:"start_minute,omitempty"`
	FinishMinute float64             `json:"finish_minute,omitempty"`
	RegionID     string              `json:"region_id,omitempty"`
}

type DialogueChoiceRule struct {
	ID        string         `json:"id"`
	Text      string         `json:"text,omitempty"`
	TextKey   string         `json:"text_key,omitempty"`
	Next      string         `json:"next,omitempty"`
	Condition *RuleCondition `json:"condition,omitempty"`
	Actions   []RuleAction   `json:"actions"`
}

type DialogueNodeRule struct {
	ID         string               `json:"id"`
	Speaker    string               `json:"speaker,omitempty"`
	SpeakerKey string               `json:"speaker_key,omitempty"`
	Text       string               `json:"text,omitempty"`
	TextKey    string               `json:"text_key,omitempty"`
	Next       string               `json:"next,omitempty"`
	Actions    []RuleAction         `json:"actions"`
	Choices    []DialogueChoiceRule `json:"choices"`
}

type DialogueRule struct {
	ID        string             `json:"id"`
	Name      string             `json:"name,omitempty"`
	NameKey   string             `json:"name_key,omitempty"`
	StartNode string             `json:"start_node"`
	Nodes     []DialogueNodeRule `json:"nodes"`
}

type CutsceneStepRule struct {
	ID            string       `json:"id"`
	Speaker       string       `json:"speaker,omitempty"`
	SpeakerKey    string       `json:"speaker_key,omitempty"`
	Text          string       `json:"text,omitempty"`
	TextKey       string       `json:"text_key,omitempty"`
	BackgroundID  string       `json:"background_id,omitempty"`
	DurationTicks int          `json:"duration_ticks,omitempty"`
	Actions       []RuleAction `json:"actions"`
}

type CutsceneRule struct {
	ID           string             `json:"id"`
	Name         string             `json:"name,omitempty"`
	NameKey      string             `json:"name_key,omitempty"`
	BackgroundID string             `json:"background_id,omitempty"`
	Skippable    bool               `json:"skippable"`
	Steps        []CutsceneStepRule `json:"steps"`
	OnComplete   []RuleAction       `json:"on_complete"`
}

type QuestObjectiveRule struct {
	ID      string         `json:"id"`
	Event   string         `json:"event"`
	Where   map[string]any `json:"where"`
	ActorID string         `json:"actor_id,omitempty"`
	Count   int            `json:"count"`
}

// Matches applies the same scalar event-filter semantics as the LÖVE quest
// feature. ActorID remains a compatibility projection for older adapters;
// newly compiled rules retain the complete authored where object.
func (rule QuestObjectiveRule) Matches(
	event string,
	payload map[string]any,
) bool {
	if rule.Event != event {
		return false
	}
	where := rule.Where
	if len(where) == 0 && rule.ActorID != "" {
		where = map[string]any{"actor_id": rule.ActorID}
	}
	for key, expected := range where {
		actual, exists := payload[key]
		if !exists || !sameRuleScalar(actual, expected) {
			return false
		}
	}
	return true
}

func sameRuleScalar(left, right any) bool {
	switch typed := left.(type) {
	case string:
		value, ok := right.(string)
		return ok && typed == value
	case float64:
		value, ok := right.(float64)
		return ok && typed == value
	case bool:
		value, ok := right.(bool)
		return ok && typed == value
	default:
		return false
	}
}

type QuestRule struct {
	ID              string               `json:"id"`
	Name            string               `json:"name,omitempty"`
	NameKey         string               `json:"name_key,omitempty"`
	Description     string               `json:"description,omitempty"`
	DescriptionKey  string               `json:"description_key,omitempty"`
	InitiallyActive bool                 `json:"initially_active"`
	Objectives      []QuestObjectiveRule `json:"objectives"`
	OnStart         []RuleAction         `json:"on_start"`
	OnComplete      []RuleAction         `json:"on_complete"`
}

type ItemEquipmentRule struct {
	Slot              string  `json:"slot"`
	AttackModifier    float64 `json:"attack_modifier"`
	DefenseModifier   float64 `json:"defense_modifier"`
	MoveSpeedModifier float64 `json:"move_speed_modifier"`
}

type ItemRule struct {
	ID             string             `json:"id"`
	Name           string             `json:"name,omitempty"`
	NameKey        string             `json:"name_key,omitempty"`
	Description    string             `json:"description,omitempty"`
	DescriptionKey string             `json:"description_key,omitempty"`
	StackLimit     int                `json:"stack_limit"`
	Value          int                `json:"value"`
	Consumable     bool               `json:"consumable"`
	Equipment      *ItemEquipmentRule `json:"equipment,omitempty"`
	Effects        []RuleAction       `json:"effects"`
}

type ShopOfferRule struct {
	ItemID    string `json:"item_id"`
	CanBuy    bool   `json:"can_buy"`
	BuyPrice  int    `json:"buy_price,omitempty"`
	CanSell   bool   `json:"can_sell"`
	SellPrice int    `json:"sell_price,omitempty"`
}

type ShopRule struct {
	ID      string          `json:"id"`
	Name    string          `json:"name,omitempty"`
	NameKey string          `json:"name_key,omitempty"`
	Offers  []ShopOfferRule `json:"offers"`
}

type TurnSkillRule struct {
	ID      string `json:"id"`
	Name    string `json:"name,omitempty"`
	NameKey string `json:"name_key,omitempty"`
	Effect  string `json:"effect"`
	Target  string `json:"target"`
	Power   int    `json:"power"`
}

type ActorTurnBattlerRule struct {
	ActorID string   `json:"actor_id"`
	Skills  []string `json:"skills"`
}

type TurnBattleEnemyRule struct {
	ID        string   `json:"id"`
	ActorID   string   `json:"actor_id"`
	Name      string   `json:"name"`
	MaxHealth int      `json:"max_health"`
	Attack    int      `json:"attack"`
	Defense   int      `json:"defense"`
	Skills    []string `json:"skills"`
}

type TurnBattleRule struct {
	ID          string                `json:"id"`
	Name        string                `json:"name,omitempty"`
	NameKey     string                `json:"name_key,omitempty"`
	AllowEscape bool                  `json:"allow_escape"`
	Repeatable  bool                  `json:"repeatable"`
	Enemies     []TurnBattleEnemyRule `json:"enemies"`
	OnStart     []RuleAction          `json:"on_start"`
	OnVictory   []RuleAction          `json:"on_victory"`
	OnEscape    []RuleAction          `json:"on_escape"`
	OnDefeat    []RuleAction          `json:"on_defeat"`
}

// ActorInteractionRule is the rule-bearing portion of rpg.interactable.
// Rendering, placement, and collision remain actor/stage builder concerns.
type ActorInteractionPageRule struct {
	ID        string         `json:"id"`
	Input     string         `json:"input"`
	Prompt    string         `json:"prompt,omitempty"`
	PromptKey string         `json:"prompt_key,omitempty"`
	Range     float64        `json:"range"`
	Condition *RuleCondition `json:"condition,omitempty"`
	Actions   []RuleAction   `json:"actions"`
}

type ActorInteractionRule struct {
	ActorID   string                     `json:"actor_id"`
	Input     string                     `json:"input"`
	Prompt    string                     `json:"prompt,omitempty"`
	PromptKey string                     `json:"prompt_key"`
	Range     float64                    `json:"range"`
	Condition *RuleCondition             `json:"condition,omitempty"`
	Actions   []RuleAction               `json:"actions"`
	Pages     []ActorInteractionPageRule `json:"pages,omitempty"`
}

// ContentRules is a deterministic, runtime-owned snapshot. All definitions
// are sorted by content ID; authored arrays (actions, choices, objectives,
// effects, and shop offers) retain their source order.
type ContentRules struct {
	Capabilities RuleCompilerCapabilities `json:"capabilities"`
	Dialogues    []DialogueRule           `json:"dialogues"`
	Cutscenes    []CutsceneRule           `json:"cutscenes"`
	Quests       []QuestRule              `json:"quests"`
	Items        []ItemRule               `json:"items"`
	Shops        []ShopRule               `json:"shops"`
	Interactions []ActorInteractionRule   `json:"interactions"`
	TurnSkills   []TurnSkillRule          `json:"turn_skills"`
	TurnBattlers []ActorTurnBattlerRule   `json:"turn_battlers"`
	TurnBattles  []TurnBattleRule         `json:"turn_battles"`
}

// Clone returns a recursively detached rules snapshot.
func (rules ContentRules) Clone() ContentRules {
	result := ContentRules{
		Capabilities: cloneRuleCapabilities(rules.Capabilities),
		Dialogues:    make([]DialogueRule, len(rules.Dialogues)),
		Cutscenes:    make([]CutsceneRule, len(rules.Cutscenes)),
		Quests:       make([]QuestRule, len(rules.Quests)),
		Items:        make([]ItemRule, len(rules.Items)),
		Shops:        make([]ShopRule, len(rules.Shops)),
		Interactions: make([]ActorInteractionRule, len(rules.Interactions)),
		TurnSkills:   append([]TurnSkillRule(nil), rules.TurnSkills...),
		TurnBattlers: make([]ActorTurnBattlerRule, len(rules.TurnBattlers)),
		TurnBattles:  make([]TurnBattleRule, len(rules.TurnBattles)),
	}
	for index, dialogue := range rules.Dialogues {
		result.Dialogues[index] = cloneDialogueRule(dialogue)
	}
	for index, cutscene := range rules.Cutscenes {
		result.Cutscenes[index] = cloneCutsceneRule(cutscene)
	}
	for index, quest := range rules.Quests {
		result.Quests[index] = cloneQuestRule(quest)
	}
	for index, item := range rules.Items {
		result.Items[index] = cloneItemRule(item)
	}
	for index, shop := range rules.Shops {
		result.Shops[index] = cloneShopRule(shop)
	}
	for index, interaction := range rules.Interactions {
		result.Interactions[index] = cloneActorInteractionRule(interaction)
	}
	for index, battler := range rules.TurnBattlers {
		result.TurnBattlers[index] = battler
		result.TurnBattlers[index].Skills = append(
			[]string(nil),
			battler.Skills...,
		)
	}
	for index, battle := range rules.TurnBattles {
		result.TurnBattles[index] = cloneTurnBattleRule(battle)
	}
	return result
}

func (rules ContentRules) Dialogue(id string) (DialogueRule, bool) {
	index := sort.Search(len(rules.Dialogues), func(index int) bool {
		return rules.Dialogues[index].ID >= id
	})
	if index == len(rules.Dialogues) || rules.Dialogues[index].ID != id {
		return DialogueRule{}, false
	}
	return cloneDialogueRule(rules.Dialogues[index]), true
}

func (rules ContentRules) Cutscene(id string) (CutsceneRule, bool) {
	index := sort.Search(len(rules.Cutscenes), func(index int) bool {
		return rules.Cutscenes[index].ID >= id
	})
	if index == len(rules.Cutscenes) || rules.Cutscenes[index].ID != id {
		return CutsceneRule{}, false
	}
	return cloneCutsceneRule(rules.Cutscenes[index]), true
}

func (rules ContentRules) Quest(id string) (QuestRule, bool) {
	index := sort.Search(len(rules.Quests), func(index int) bool {
		return rules.Quests[index].ID >= id
	})
	if index == len(rules.Quests) || rules.Quests[index].ID != id {
		return QuestRule{}, false
	}
	return cloneQuestRule(rules.Quests[index]), true
}

func (rules ContentRules) Item(id string) (ItemRule, bool) {
	index := sort.Search(len(rules.Items), func(index int) bool {
		return rules.Items[index].ID >= id
	})
	if index == len(rules.Items) || rules.Items[index].ID != id {
		return ItemRule{}, false
	}
	return cloneItemRule(rules.Items[index]), true
}

func (rules ContentRules) Shop(id string) (ShopRule, bool) {
	index := sort.Search(len(rules.Shops), func(index int) bool {
		return rules.Shops[index].ID >= id
	})
	if index == len(rules.Shops) || rules.Shops[index].ID != id {
		return ShopRule{}, false
	}
	return cloneShopRule(rules.Shops[index]), true
}

func (rules ContentRules) Interaction(
	actorID string,
) (ActorInteractionRule, bool) {
	index := sort.Search(len(rules.Interactions), func(index int) bool {
		return rules.Interactions[index].ActorID >= actorID
	})
	if index == len(rules.Interactions) ||
		rules.Interactions[index].ActorID != actorID {
		return ActorInteractionRule{}, false
	}
	return cloneActorInteractionRule(rules.Interactions[index]), true
}

func (rules ContentRules) TurnSkill(id string) (TurnSkillRule, bool) {
	index := sort.Search(len(rules.TurnSkills), func(index int) bool {
		return rules.TurnSkills[index].ID >= id
	})
	if index == len(rules.TurnSkills) || rules.TurnSkills[index].ID != id {
		return TurnSkillRule{}, false
	}
	return rules.TurnSkills[index], true
}

func (rules ContentRules) TurnBattler(
	actorID string,
) (ActorTurnBattlerRule, bool) {
	index := sort.Search(len(rules.TurnBattlers), func(index int) bool {
		return rules.TurnBattlers[index].ActorID >= actorID
	})
	if index == len(rules.TurnBattlers) ||
		rules.TurnBattlers[index].ActorID != actorID {
		return ActorTurnBattlerRule{}, false
	}
	result := rules.TurnBattlers[index]
	result.Skills = append([]string(nil), result.Skills...)
	return result, true
}

func (rules ContentRules) TurnBattle(id string) (TurnBattleRule, bool) {
	index := sort.Search(len(rules.TurnBattles), func(index int) bool {
		return rules.TurnBattles[index].ID >= id
	})
	if index == len(rules.TurnBattles) || rules.TurnBattles[index].ID != id {
		return TurnBattleRule{}, false
	}
	return cloneTurnBattleRule(rules.TurnBattles[index]), true
}

// BuildContentRules compiles all campaign-domain definitions and NPC
// interactions from catalog. The result contains no maps or slices shared with
// the catalog.
func BuildContentRules(catalog *content.Catalog) (ContentRules, error) {
	compiler, err := newContentRuleCompiler(catalog)
	if err != nil {
		return ContentRules{}, err
	}
	result := ContentRules{
		Capabilities: ContentRuleCapabilities(),
		Dialogues:    []DialogueRule{},
		Cutscenes:    []CutsceneRule{},
		Quests:       []QuestRule{},
		Items:        []ItemRule{},
		Shops:        []ShopRule{},
		Interactions: []ActorInteractionRule{},
		TurnSkills:   []TurnSkillRule{},
		TurnBattlers: []ActorTurnBattlerRule{},
		TurnBattles:  []TurnBattleRule{},
	}

	for _, header := range compiler.headers {
		switch header.kind {
		case "dialogue":
			value, err := compiler.compileDialogue(header.id)
			if err != nil {
				return ContentRules{}, err
			}
			result.Dialogues = append(result.Dialogues, value)
		case "cutscene":
			value, err := compiler.compileCutscene(header.id)
			if err != nil {
				return ContentRules{}, err
			}
			result.Cutscenes = append(result.Cutscenes, value)
		case "quest":
			value, err := compiler.compileQuest(header.id)
			if err != nil {
				return ContentRules{}, err
			}
			result.Quests = append(result.Quests, value)
		case "item":
			value, err := compiler.compileItem(header.id)
			if err != nil {
				return ContentRules{}, err
			}
			result.Items = append(result.Items, value)
		case "shop":
			value, err := compiler.compileShop(header.id)
			if err != nil {
				return ContentRules{}, err
			}
			result.Shops = append(result.Shops, value)
		case "actor":
			value, exists, err := compiler.compileInteraction(header.id)
			if err != nil {
				return ContentRules{}, err
			}
			if exists {
				result.Interactions = append(result.Interactions, value)
			}
			battler, exists, err := compiler.compileTurnBattler(header.id)
			if err != nil {
				return ContentRules{}, err
			}
			if exists {
				result.TurnBattlers = append(result.TurnBattlers, battler)
			}
		case "turn_skill":
			value, err := compiler.compileTurnSkill(header.id)
			if err != nil {
				return ContentRules{}, err
			}
			result.TurnSkills = append(result.TurnSkills, value)
		case "turn_battle":
			value, err := compiler.compileTurnBattle(header.id)
			if err != nil {
				return ContentRules{}, err
			}
			result.TurnBattles = append(result.TurnBattles, value)
		}
	}
	return result, nil
}

type contentRuleDefinition struct {
	id   string
	kind string
	data map[string]any
}

type contentRuleCompiler struct {
	catalog     *content.Catalog
	headers     []contentRuleDefinition
	definitions map[string]contentRuleDefinition
}

func newContentRuleCompiler(
	catalog *content.Catalog,
) (*contentRuleCompiler, error) {
	if catalog == nil {
		return nil, fmt.Errorf("build content rules: catalog is nil")
	}
	if catalog.SchemaVersion != content.CatalogSchemaVersion {
		return nil, fmt.Errorf(
			"build content rules: catalog schema_version must be %d, got %d",
			content.CatalogSchemaVersion,
			catalog.SchemaVersion,
		)
	}
	compiler := &contentRuleCompiler{
		catalog:     catalog,
		headers:     make([]contentRuleDefinition, 0, len(catalog.Definitions)),
		definitions: make(map[string]contentRuleDefinition, len(catalog.Definitions)),
	}
	for index, definition := range catalog.Definitions {
		path := fmt.Sprintf("definitions[%d]", index)
		data, err := detachRuleDefinition(definition.Data)
		if err != nil {
			return nil, fmt.Errorf("build content rules: %s: %w", path, err)
		}
		id, err := requiredString(data["id"], path+".id")
		if err != nil {
			return nil, fmt.Errorf("build content rules: %w", err)
		}
		kind, err := requiredString(data["kind"], id+".kind")
		if err != nil {
			return nil, fmt.Errorf("build content rules: %w", err)
		}
		version, err := ruleInteger(data["schema_version"], id+".schema_version", 1)
		if err != nil || version != 1 {
			if err != nil {
				return nil, fmt.Errorf("build content rules: %w", err)
			}
			return nil, fmt.Errorf(
				"build content rules: %s.schema_version must be 1",
				id,
			)
		}
		if _, duplicate := compiler.definitions[id]; duplicate {
			return nil, fmt.Errorf(
				"build content rules: duplicate definition id %q",
				id,
			)
		}
		header := contentRuleDefinition{id: id, kind: kind, data: data}
		compiler.headers = append(compiler.headers, header)
		compiler.definitions[id] = header
	}
	sort.Slice(compiler.headers, func(i, j int) bool {
		return compiler.headers[i].id < compiler.headers[j].id
	})
	return compiler, nil
}

func detachRuleDefinition(data map[string]any) (map[string]any, error) {
	encoded, err := json.Marshal(data)
	if err != nil {
		return nil, fmt.Errorf("encode definition: %w", err)
	}
	var result map[string]any
	if err := json.Unmarshal(encoded, &result); err != nil {
		return nil, fmt.Errorf("decode definition: %w", err)
	}
	if result == nil {
		return nil, errors.New("definition must be an object")
	}
	return result, nil
}

func (compiler *contentRuleCompiler) validate(id string) error {
	if _, err := ValidateDefinition(compiler.catalog, id); err != nil {
		return fmt.Errorf("build content rules: %w", err)
	}
	return nil
}

func (compiler *contentRuleCompiler) compileCutscene(
	id string,
) (CutsceneRule, error) {
	if err := compiler.validate(id); err != nil {
		return CutsceneRule{}, err
	}
	data := compiler.definitions[id].data
	if err := rejectUnknownKeys(
		data,
		id,
		"schema_version",
		"kind",
		"id",
		"name",
		"name_key",
		"background",
		"skippable",
		"steps",
		"on_complete",
	); err != nil {
		return CutsceneRule{}, fmt.Errorf("build content rules: %w", err)
	}
	backgroundID := ruleOptionalString(data, "background")
	if backgroundID != "" {
		if err := compiler.requireReference(
			backgroundID,
			"asset",
			id+".background",
		); err != nil {
			return CutsceneRule{}, err
		}
	}
	skippable := true
	var err error
	if data["skippable"] != nil {
		skippable, err = ruleOptionalBool(
			data,
			"skippable",
			id+".skippable",
		)
		if err != nil {
			return CutsceneRule{}, fmt.Errorf(
				"build content rules: %w",
				err,
			)
		}
	}
	rawSteps, err := requiredArray(data["steps"], id+".steps")
	if err != nil {
		return CutsceneRule{}, fmt.Errorf("build content rules: %w", err)
	}
	if len(rawSteps) == 0 {
		return CutsceneRule{}, fmt.Errorf(
			"build content rules: %s.steps must not be empty",
			id,
		)
	}
	result := CutsceneRule{
		ID:           id,
		Name:         ruleOptionalString(data, "name"),
		NameKey:      ruleOptionalString(data, "name_key"),
		BackgroundID: backgroundID,
		Skippable:    skippable,
		Steps:        make([]CutsceneStepRule, len(rawSteps)),
	}
	seen := make(map[string]struct{}, len(rawSteps))
	for index, rawStep := range rawSteps {
		path := fmt.Sprintf("%s.steps[%d]", id, index)
		step, err := requiredObject(rawStep, path)
		if err != nil {
			return CutsceneRule{}, fmt.Errorf(
				"build content rules: %w",
				err,
			)
		}
		if err := rejectUnknownKeys(
			step,
			path,
			"id",
			"speaker",
			"speaker_key",
			"text",
			"text_key",
			"background",
			"duration",
			"actions",
		); err != nil {
			return CutsceneRule{}, fmt.Errorf(
				"build content rules: %w",
				err,
			)
		}
		stepID, err := requiredString(step["id"], path+".id")
		if err != nil {
			return CutsceneRule{}, fmt.Errorf(
				"build content rules: %w",
				err,
			)
		}
		if _, duplicate := seen[stepID]; duplicate {
			return CutsceneRule{}, fmt.Errorf(
				"build content rules: %s.id duplicates step %q",
				path,
				stepID,
			)
		}
		seen[stepID] = struct{}{}
		text, err := ruleOptionalStringChecked(
			step,
			"text",
			path+".text",
		)
		if err != nil {
			return CutsceneRule{}, fmt.Errorf(
				"build content rules: %w",
				err,
			)
		}
		textKey, err := ruleOptionalStringChecked(
			step,
			"text_key",
			path+".text_key",
		)
		if err != nil {
			return CutsceneRule{}, fmt.Errorf(
				"build content rules: %w",
				err,
			)
		}
		if text == "" && textKey == "" {
			return CutsceneRule{}, fmt.Errorf(
				"build content rules: %s requires text or text_key",
				path,
			)
		}
		stepBackground := ruleOptionalString(step, "background")
		if stepBackground != "" {
			if err := compiler.requireReference(
				stepBackground,
				"asset",
				path+".background",
			); err != nil {
				return CutsceneRule{}, err
			}
		}
		durationTicks := 0
		if step["duration"] != nil {
			duration, err := requiredPositiveNumberValue(
				step["duration"],
				path+".duration",
			)
			if err != nil {
				return CutsceneRule{}, fmt.Errorf(
					"build content rules: %w",
					err,
				)
			}
			if !durationFitsPortableTicks(duration) {
				return CutsceneRule{}, fmt.Errorf(
					"build content rules: %s.duration exceeds the supported duration",
					path,
				)
			}
			durationTicks = secondsToTicks(duration)
		}
		actions, err := compiler.compileOptionalActions(
			step["actions"],
			path+".actions",
		)
		if err != nil {
			return CutsceneRule{}, err
		}
		result.Steps[index] = CutsceneStepRule{
			ID:            stepID,
			Speaker:       ruleOptionalString(step, "speaker"),
			SpeakerKey:    ruleOptionalString(step, "speaker_key"),
			Text:          text,
			TextKey:       textKey,
			BackgroundID:  stepBackground,
			DurationTicks: durationTicks,
			Actions:       actions,
		}
	}
	result.OnComplete, err = compiler.compileOptionalActions(
		data["on_complete"],
		id+".on_complete",
	)
	if err != nil {
		return CutsceneRule{}, err
	}
	return result, nil
}

func (compiler *contentRuleCompiler) compileDialogue(
	id string,
) (DialogueRule, error) {
	if err := compiler.validate(id); err != nil {
		return DialogueRule{}, err
	}
	data := compiler.definitions[id].data
	if err := rejectUnknownKeys(
		data,
		id,
		"schema_version",
		"kind",
		"id",
		"name",
		"name_key",
		"start",
		"nodes",
	); err != nil {
		return DialogueRule{}, fmt.Errorf("build content rules: %w", err)
	}
	start, err := requiredString(data["start"], id+".start")
	if err != nil {
		return DialogueRule{}, fmt.Errorf("build content rules: %w", err)
	}
	nodes, err := requiredObject(data["nodes"], id+".nodes")
	if err != nil {
		return DialogueRule{}, fmt.Errorf("build content rules: %w", err)
	}
	if _, exists := nodes[start]; !exists {
		return DialogueRule{}, fmt.Errorf(
			"build content rules: %s.start references missing node %q",
			id,
			start,
		)
	}
	nodeIDs := make([]string, 0, len(nodes))
	for nodeID := range nodes {
		if strings.TrimSpace(nodeID) == "" {
			return DialogueRule{}, fmt.Errorf(
				"build content rules: %s.nodes contains an empty node id",
				id,
			)
		}
		nodeIDs = append(nodeIDs, nodeID)
	}
	sort.Strings(nodeIDs)
	result := DialogueRule{
		ID:        id,
		Name:      ruleOptionalString(data, "name"),
		NameKey:   ruleOptionalString(data, "name_key"),
		StartNode: start,
		Nodes:     make([]DialogueNodeRule, 0, len(nodeIDs)),
	}
	for _, nodeID := range nodeIDs {
		node, err := compiler.compileDialogueNode(id, nodeID, nodes)
		if err != nil {
			return DialogueRule{}, err
		}
		result.Nodes = append(result.Nodes, node)
	}
	return result, nil
}

func (compiler *contentRuleCompiler) compileDialogueNode(
	dialogueID string,
	nodeID string,
	allNodes map[string]any,
) (DialogueNodeRule, error) {
	path := dialogueID + ".nodes." + nodeID
	node, err := requiredObject(allNodes[nodeID], path)
	if err != nil {
		return DialogueNodeRule{}, fmt.Errorf("build content rules: %w", err)
	}
	if err := rejectUnknownKeys(
		node,
		path,
		"speaker",
		"speaker_key",
		"text",
		"text_key",
		"next",
		"actions",
		"choices",
	); err != nil {
		return DialogueNodeRule{}, fmt.Errorf("build content rules: %w", err)
	}
	text := ruleOptionalString(node, "text")
	textKey := ruleOptionalString(node, "text_key")
	if text == "" && textKey == "" {
		return DialogueNodeRule{}, fmt.Errorf(
			"build content rules: %s requires text or text_key",
			path,
		)
	}
	next := ruleOptionalString(node, "next")
	if next != "" {
		if _, exists := allNodes[next]; !exists {
			return DialogueNodeRule{}, fmt.Errorf(
				"build content rules: %s.next references missing node %q",
				path,
				next,
			)
		}
	}
	actions, err := compiler.compileOptionalActions(
		node["actions"],
		path+".actions",
	)
	if err != nil {
		return DialogueNodeRule{}, err
	}
	rawChoices, hasChoices, err := optionalArray(
		node["choices"],
		path+".choices",
	)
	if err != nil {
		return DialogueNodeRule{}, fmt.Errorf("build content rules: %w", err)
	}
	if hasChoices && next != "" {
		return DialogueNodeRule{}, fmt.Errorf(
			"build content rules: %s cannot define both next and choices",
			path,
		)
	}
	choices := make([]DialogueChoiceRule, 0, len(rawChoices))
	seenChoices := make(map[string]struct{}, len(rawChoices))
	for index, rawChoice := range rawChoices {
		choicePath := fmt.Sprintf("%s.choices[%d]", path, index)
		choice, err := compiler.compileDialogueChoice(
			rawChoice,
			choicePath,
			allNodes,
		)
		if err != nil {
			return DialogueNodeRule{}, err
		}
		if _, duplicate := seenChoices[choice.ID]; duplicate {
			return DialogueNodeRule{}, fmt.Errorf(
				"build content rules: %s.id duplicates choice %q",
				choicePath,
				choice.ID,
			)
		}
		seenChoices[choice.ID] = struct{}{}
		choices = append(choices, choice)
	}
	return DialogueNodeRule{
		ID:         nodeID,
		Speaker:    ruleOptionalString(node, "speaker"),
		SpeakerKey: ruleOptionalString(node, "speaker_key"),
		Text:       text,
		TextKey:    textKey,
		Next:       next,
		Actions:    actions,
		Choices:    choices,
	}, nil
}

func (compiler *contentRuleCompiler) compileDialogueChoice(
	raw any,
	path string,
	allNodes map[string]any,
) (DialogueChoiceRule, error) {
	choice, err := requiredObject(raw, path)
	if err != nil {
		return DialogueChoiceRule{}, fmt.Errorf("build content rules: %w", err)
	}
	if err := rejectUnknownKeys(
		choice,
		path,
		"id",
		"text",
		"text_key",
		"next",
		"condition",
		"actions",
	); err != nil {
		return DialogueChoiceRule{}, fmt.Errorf("build content rules: %w", err)
	}
	id, err := requiredString(choice["id"], path+".id")
	if err != nil {
		return DialogueChoiceRule{}, fmt.Errorf("build content rules: %w", err)
	}
	text := ruleOptionalString(choice, "text")
	textKey := ruleOptionalString(choice, "text_key")
	if text == "" && textKey == "" {
		return DialogueChoiceRule{}, fmt.Errorf(
			"build content rules: %s requires text or text_key",
			path,
		)
	}
	next := ruleOptionalString(choice, "next")
	if next != "" {
		if _, exists := allNodes[next]; !exists {
			return DialogueChoiceRule{}, fmt.Errorf(
				"build content rules: %s.next references missing node %q",
				path,
				next,
			)
		}
	}
	var condition *RuleCondition
	if choice["condition"] != nil {
		compiled, err := compiler.compileCondition(
			choice["condition"],
			path+".condition",
		)
		if err != nil {
			return DialogueChoiceRule{}, err
		}
		condition = &compiled
	}
	actions, err := compiler.compileOptionalActions(
		choice["actions"],
		path+".actions",
	)
	if err != nil {
		return DialogueChoiceRule{}, err
	}
	return DialogueChoiceRule{
		ID:        id,
		Text:      text,
		TextKey:   textKey,
		Next:      next,
		Condition: condition,
		Actions:   actions,
	}, nil
}

func (compiler *contentRuleCompiler) compileQuest(
	id string,
) (QuestRule, error) {
	if err := compiler.validate(id); err != nil {
		return QuestRule{}, err
	}
	data := compiler.definitions[id].data
	if err := rejectUnknownKeys(
		data,
		id,
		"schema_version",
		"kind",
		"id",
		"name",
		"name_key",
		"description",
		"description_key",
		"initially_active",
		"objectives",
		"on_start",
		"on_complete",
	); err != nil {
		return QuestRule{}, fmt.Errorf("build content rules: %w", err)
	}
	rawObjectives, err := requiredArray(data["objectives"], id+".objectives")
	if err != nil {
		return QuestRule{}, fmt.Errorf("build content rules: %w", err)
	}
	if len(rawObjectives) == 0 {
		return QuestRule{}, fmt.Errorf(
			"build content rules: %s.objectives must not be empty",
			id,
		)
	}
	objectives := make([]QuestObjectiveRule, 0, len(rawObjectives))
	seen := make(map[string]struct{}, len(rawObjectives))
	for index, raw := range rawObjectives {
		path := fmt.Sprintf("%s.objectives[%d]", id, index)
		objective, err := compiler.compileQuestObjective(raw, path)
		if err != nil {
			return QuestRule{}, err
		}
		if _, duplicate := seen[objective.ID]; duplicate {
			return QuestRule{}, fmt.Errorf(
				"build content rules: %s.id duplicates objective %q",
				path,
				objective.ID,
			)
		}
		seen[objective.ID] = struct{}{}
		objectives = append(objectives, objective)
	}
	onStart, err := compiler.compileOptionalActions(
		data["on_start"],
		id+".on_start",
	)
	if err != nil {
		return QuestRule{}, err
	}
	onComplete, err := compiler.compileOptionalActions(
		data["on_complete"],
		id+".on_complete",
	)
	if err != nil {
		return QuestRule{}, err
	}
	initiallyActive, err := ruleOptionalBool(
		data,
		"initially_active",
		id+".initially_active",
	)
	if err != nil {
		return QuestRule{}, fmt.Errorf("build content rules: %w", err)
	}
	return QuestRule{
		ID:              id,
		Name:            ruleOptionalString(data, "name"),
		NameKey:         ruleOptionalString(data, "name_key"),
		Description:     ruleOptionalString(data, "description"),
		DescriptionKey:  ruleOptionalString(data, "description_key"),
		InitiallyActive: initiallyActive,
		Objectives:      objectives,
		OnStart:         onStart,
		OnComplete:      onComplete,
	}, nil
}

func (compiler *contentRuleCompiler) compileQuestObjective(
	raw any,
	path string,
) (QuestObjectiveRule, error) {
	objective, err := requiredObject(raw, path)
	if err != nil {
		return QuestObjectiveRule{}, fmt.Errorf("build content rules: %w", err)
	}
	if err := rejectUnknownKeys(
		objective,
		path,
		"id",
		"event",
		"where",
		"count",
	); err != nil {
		return QuestObjectiveRule{}, fmt.Errorf("build content rules: %w", err)
	}
	id, err := requiredString(objective["id"], path+".id")
	if err != nil {
		return QuestObjectiveRule{}, fmt.Errorf("build content rules: %w", err)
	}
	event, err := requiredString(objective["event"], path+".event")
	if err != nil {
		return QuestObjectiveRule{}, fmt.Errorf("build content rules: %w", err)
	}
	where := map[string]any{}
	if rawWhere, exists := objective["where"]; exists {
		where, err = requiredObject(rawWhere, path+".where")
		if err != nil {
			return QuestObjectiveRule{}, fmt.Errorf(
				"build content rules: %w",
				err,
			)
		}
		for key, value := range where {
			if strings.TrimSpace(key) == "" {
				return QuestObjectiveRule{}, fmt.Errorf(
					"build content rules: %s.where has an empty filter key",
					path,
				)
			}
			switch value.(type) {
			case string, float64, bool:
			default:
				return QuestObjectiveRule{}, fmt.Errorf(
					"build content rules: %s.where.%s must be a string, number, or boolean",
					path,
					key,
				)
			}
		}
	}
	actorID, _ := where["actor_id"].(string)
	if _, exists := where["actor_id"]; exists {
		if actorID == "" {
			return QuestObjectiveRule{}, fmt.Errorf(
				"build content rules: %s.where.actor_id must be a non-empty string",
				path,
			)
		}
		if err := compiler.requireReference(
			actorID,
			"actor",
			path+".where.actor_id",
		); err != nil {
			return QuestObjectiveRule{}, err
		}
	}
	count, err := ruleInteger(objective["count"], path+".count", 1)
	if err != nil {
		return QuestObjectiveRule{}, fmt.Errorf("build content rules: %w", err)
	}
	return QuestObjectiveRule{
		ID:      id,
		Event:   event,
		Where:   cloneRuleFilter(where),
		ActorID: actorID,
		Count:   count,
	}, nil
}

func (compiler *contentRuleCompiler) compileItem(
	id string,
) (ItemRule, error) {
	if err := compiler.validate(id); err != nil {
		return ItemRule{}, err
	}
	data := compiler.definitions[id].data
	if err := rejectUnknownKeys(
		data,
		id,
		"schema_version",
		"kind",
		"id",
		"name",
		"name_key",
		"description",
		"description_key",
		"stack_limit",
		"value",
		"consumable",
		"effects",
		"equipment",
	); err != nil {
		return ItemRule{}, fmt.Errorf("build content rules: %w", err)
	}
	stackLimit, err := ruleInteger(data["stack_limit"], id+".stack_limit", 1)
	if err != nil {
		return ItemRule{}, fmt.Errorf("build content rules: %w", err)
	}
	value, err := ruleInteger(data["value"], id+".value", 0)
	if err != nil {
		return ItemRule{}, fmt.Errorf("build content rules: %w", err)
	}
	consumable, err := ruleOptionalBool(
		data,
		"consumable",
		id+".consumable",
	)
	if err != nil {
		return ItemRule{}, fmt.Errorf("build content rules: %w", err)
	}
	effects, err := compiler.compileOptionalActions(
		data["effects"],
		id+".effects",
	)
	if err != nil {
		return ItemRule{}, err
	}
	if consumable && len(effects) == 0 {
		return ItemRule{}, fmt.Errorf(
			"build content rules: %s consumable item requires effects",
			id,
		)
	}
	if !consumable && len(effects) != 0 {
		return ItemRule{}, fmt.Errorf(
			"build content rules: %s.effects requires consumable=true",
			id,
		)
	}
	var equipment *ItemEquipmentRule
	if data["equipment"] != nil {
		compiled, err := compiler.compileItemEquipment(
			data["equipment"],
			id+".equipment",
		)
		if err != nil {
			return ItemRule{}, err
		}
		equipment = &compiled
	}
	return ItemRule{
		ID:             id,
		Name:           ruleOptionalString(data, "name"),
		NameKey:        ruleOptionalString(data, "name_key"),
		Description:    ruleOptionalString(data, "description"),
		DescriptionKey: ruleOptionalString(data, "description_key"),
		StackLimit:     stackLimit,
		Value:          value,
		Consumable:     consumable,
		Equipment:      equipment,
		Effects:        effects,
	}, nil
}

func (compiler *contentRuleCompiler) compileItemEquipment(
	raw any,
	path string,
) (ItemEquipmentRule, error) {
	equipment, err := requiredObject(raw, path)
	if err != nil {
		return ItemEquipmentRule{}, fmt.Errorf("build content rules: %w", err)
	}
	if err := rejectUnknownKeys(equipment, path, "slot", "modifiers"); err != nil {
		return ItemEquipmentRule{}, fmt.Errorf("build content rules: %w", err)
	}
	slot, err := requiredString(equipment["slot"], path+".slot")
	if err != nil {
		return ItemEquipmentRule{}, fmt.Errorf("build content rules: %w", err)
	}
	modifiers, err := requiredObject(equipment["modifiers"], path+".modifiers")
	if err != nil {
		return ItemEquipmentRule{}, fmt.Errorf("build content rules: %w", err)
	}
	for name := range modifiers {
		switch name {
		case "attack", "defense", "move_speed":
		default:
			return ItemEquipmentRule{}, &UnsupportedRuleCapabilityError{
				Path:       path + ".modifiers." + name,
				Capability: "equipment modifier",
				Name:       name,
			}
		}
	}
	integerModifier := func(name string) (float64, error) {
		raw, exists := modifiers[name]
		if !exists {
			return 0, nil
		}
		value, err := ruleSignedInteger(raw, path+".modifiers."+name)
		if err != nil {
			return 0, err
		}
		return float64(value), nil
	}
	attack, err := integerModifier("attack")
	if err != nil {
		return ItemEquipmentRule{}, fmt.Errorf("build content rules: %w", err)
	}
	defense, err := integerModifier("defense")
	if err != nil {
		return ItemEquipmentRule{}, fmt.Errorf("build content rules: %w", err)
	}
	moveSpeed := 0.0
	if raw, exists := modifiers["move_speed"]; exists {
		moveSpeed, err = requiredNumber(raw, path+".modifiers.move_speed")
		if err != nil {
			return ItemEquipmentRule{}, fmt.Errorf(
				"build content rules: %w",
				err,
			)
		}
		if math.Abs(moveSpeed) > 16 {
			return ItemEquipmentRule{}, fmt.Errorf(
				"build content rules: %s.modifiers.move_speed "+
					"must be between -16 and 16",
				path,
			)
		}
	}
	return ItemEquipmentRule{
		Slot:              slot,
		AttackModifier:    attack,
		DefenseModifier:   defense,
		MoveSpeedModifier: moveSpeed,
	}, nil
}

func (compiler *contentRuleCompiler) compileShop(
	id string,
) (ShopRule, error) {
	if err := compiler.validate(id); err != nil {
		return ShopRule{}, err
	}
	data := compiler.definitions[id].data
	if err := rejectUnknownKeys(
		data,
		id,
		"schema_version",
		"kind",
		"id",
		"name",
		"name_key",
		"offers",
	); err != nil {
		return ShopRule{}, fmt.Errorf("build content rules: %w", err)
	}
	rawOffers, err := requiredArray(data["offers"], id+".offers")
	if err != nil {
		return ShopRule{}, fmt.Errorf("build content rules: %w", err)
	}
	if len(rawOffers) == 0 {
		return ShopRule{}, fmt.Errorf(
			"build content rules: %s.offers must not be empty",
			id,
		)
	}
	offers := make([]ShopOfferRule, 0, len(rawOffers))
	seen := make(map[string]struct{}, len(rawOffers))
	for index, raw := range rawOffers {
		path := fmt.Sprintf("%s.offers[%d]", id, index)
		offer, err := compiler.compileShopOffer(raw, path)
		if err != nil {
			return ShopRule{}, err
		}
		if _, duplicate := seen[offer.ItemID]; duplicate {
			return ShopRule{}, fmt.Errorf(
				"build content rules: %s.item duplicates offer %q",
				path,
				offer.ItemID,
			)
		}
		seen[offer.ItemID] = struct{}{}
		offers = append(offers, offer)
	}
	return ShopRule{
		ID:      id,
		Name:    ruleOptionalString(data, "name"),
		NameKey: ruleOptionalString(data, "name_key"),
		Offers:  offers,
	}, nil
}

func (compiler *contentRuleCompiler) compileShopOffer(
	raw any,
	path string,
) (ShopOfferRule, error) {
	offer, err := requiredObject(raw, path)
	if err != nil {
		return ShopOfferRule{}, fmt.Errorf("build content rules: %w", err)
	}
	if err := rejectUnknownKeys(
		offer,
		path,
		"item",
		"buy_price",
		"sell_price",
	); err != nil {
		return ShopOfferRule{}, fmt.Errorf("build content rules: %w", err)
	}
	itemID, err := requiredString(offer["item"], path+".item")
	if err != nil {
		return ShopOfferRule{}, fmt.Errorf("build content rules: %w", err)
	}
	if err := compiler.requireReference(itemID, "item", path+".item"); err != nil {
		return ShopOfferRule{}, err
	}
	result := ShopOfferRule{ItemID: itemID}
	if offer["buy_price"] != nil {
		result.CanBuy = true
		result.BuyPrice, err = ruleInteger(
			offer["buy_price"],
			path+".buy_price",
			0,
		)
		if err != nil {
			return ShopOfferRule{}, fmt.Errorf("build content rules: %w", err)
		}
	}
	if offer["sell_price"] != nil {
		result.CanSell = true
		result.SellPrice, err = ruleInteger(
			offer["sell_price"],
			path+".sell_price",
			0,
		)
		if err != nil {
			return ShopOfferRule{}, fmt.Errorf("build content rules: %w", err)
		}
	}
	if !result.CanBuy && !result.CanSell {
		return ShopOfferRule{}, fmt.Errorf(
			"build content rules: %s requires buy_price or sell_price",
			path,
		)
	}
	return result, nil
}

func (compiler *contentRuleCompiler) compileInteraction(
	actorID string,
) (ActorInteractionRule, bool, error) {
	data := compiler.definitions[actorID].data
	components, _ := data["components"].(map[string]any)
	raw, exists := components["rpg.interactable"]
	if !exists {
		return ActorInteractionRule{}, false, nil
	}
	if err := compiler.validate(actorID); err != nil {
		return ActorInteractionRule{}, false, err
	}
	path := actorID + ".components.rpg.interactable"
	interaction, err := requiredObject(raw, path)
	if err != nil {
		return ActorInteractionRule{}, false, fmt.Errorf(
			"build content rules: %w",
			err,
		)
	}
	if err := rejectUnknownKeys(
		interaction,
		path,
		"input",
		"prompt",
		"prompt_key",
		"range",
		"condition",
		"actions",
		"pages",
	); err != nil {
		return ActorInteractionRule{}, false, fmt.Errorf(
			"build content rules: %w",
			err,
		)
	}
	input := "interact"
	if interaction["input"] != nil {
		input, err = requiredString(interaction["input"], path+".input")
		if err != nil {
			return ActorInteractionRule{}, false, fmt.Errorf(
				"build content rules: %w",
				err,
			)
		}
	}
	prompt := ruleOptionalString(interaction, "prompt")
	promptKey := ruleOptionalString(interaction, "prompt_key")
	distance := 56.0
	if interaction["range"] != nil {
		distance, err = requiredPositiveNumberValue(
			interaction["range"],
			path+".range",
		)
		if err != nil {
			return ActorInteractionRule{}, false, fmt.Errorf(
				"build content rules: %w",
				err,
			)
		}
	}
	var condition *RuleCondition
	if interaction["condition"] != nil {
		compiled, err := compiler.compileCondition(
			interaction["condition"],
			path+".condition",
		)
		if err != nil {
			return ActorInteractionRule{}, false, err
		}
		condition = &compiled
	}
	var actions []RuleAction
	if interaction["actions"] != nil {
		actions, err = compiler.compileRequiredActions(
			interaction["actions"],
			path+".actions",
		)
		if err != nil {
			return ActorInteractionRule{}, false, err
		}
	}
	rawPages, pagesExist, err := optionalArray(
		interaction["pages"],
		path+".pages",
	)
	if err != nil {
		return ActorInteractionRule{}, false, fmt.Errorf(
			"build content rules: %w",
			err,
		)
	}
	pages := make([]ActorInteractionPageRule, len(rawPages))
	seenPages := make(map[string]struct{}, len(rawPages))
	for index, rawPage := range rawPages {
		pagePath := fmt.Sprintf("%s.pages[%d]", path, index)
		page, err := requiredObject(rawPage, pagePath)
		if err != nil {
			return ActorInteractionRule{}, false, fmt.Errorf(
				"build content rules: %w",
				err,
			)
		}
		pageID, err := requiredString(page["id"], pagePath+".id")
		if err != nil {
			return ActorInteractionRule{}, false, fmt.Errorf(
				"build content rules: %w",
				err,
			)
		}
		if _, duplicate := seenPages[pageID]; duplicate {
			return ActorInteractionRule{}, false, fmt.Errorf(
				"build content rules: %s.id duplicates page %q",
				pagePath,
				pageID,
			)
		}
		seenPages[pageID] = struct{}{}
		pageInput := input
		if page["input"] != nil {
			pageInput, err = requiredString(
				page["input"],
				pagePath+".input",
			)
			if err != nil {
				return ActorInteractionRule{}, false, fmt.Errorf(
					"build content rules: %w",
					err,
				)
			}
		}
		pageRange := distance
		if page["range"] != nil {
			pageRange, err = requiredPositiveNumberValue(
				page["range"],
				pagePath+".range",
			)
			if err != nil {
				return ActorInteractionRule{}, false, fmt.Errorf(
					"build content rules: %w",
					err,
				)
			}
		}
		var pageCondition *RuleCondition
		if page["condition"] != nil {
			compiled, err := compiler.compileCondition(
				page["condition"],
				pagePath+".condition",
			)
			if err != nil {
				return ActorInteractionRule{}, false, err
			}
			pageCondition = &compiled
		}
		pageActions, err := compiler.compileRequiredActions(
			page["actions"],
			pagePath+".actions",
		)
		if err != nil {
			return ActorInteractionRule{}, false, err
		}
		pagePrompt := prompt
		if page["prompt"] != nil {
			pagePrompt, err = requiredString(
				page["prompt"],
				pagePath+".prompt",
			)
			if err != nil {
				return ActorInteractionRule{}, false, fmt.Errorf(
					"build content rules: %w",
					err,
				)
			}
		}
		pagePromptKey := promptKey
		if page["prompt_key"] != nil {
			pagePromptKey, err = requiredString(
				page["prompt_key"],
				pagePath+".prompt_key",
			)
			if err != nil {
				return ActorInteractionRule{}, false, fmt.Errorf(
					"build content rules: %w",
					err,
				)
			}
		}
		pages[index] = ActorInteractionPageRule{
			ID:        pageID,
			Input:     pageInput,
			Prompt:    pagePrompt,
			PromptKey: pagePromptKey,
			Range:     pageRange,
			Condition: pageCondition,
			Actions:   pageActions,
		}
	}
	if len(actions) == 0 && (!pagesExist || len(pages) == 0) {
		return ActorInteractionRule{}, false, fmt.Errorf(
			"build content rules: %s requires actions or pages",
			path,
		)
	}
	return ActorInteractionRule{
		ActorID:   actorID,
		Input:     input,
		Prompt:    prompt,
		PromptKey: promptKey,
		Range:     distance,
		Condition: condition,
		Actions:   actions,
		Pages:     pages,
	}, true, nil
}

func (compiler *contentRuleCompiler) compileCondition(
	raw any,
	path string,
) (RuleCondition, error) {
	condition, err := requiredObject(raw, path)
	if err != nil {
		return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
	}
	conditionType, err := requiredString(condition["type"], path+".type")
	if err != nil {
		return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
	}
	typed := RuleConditionType(conditionType)
	if !ruleCompilerCapabilities.SupportsCondition(typed) {
		return RuleCondition{}, &UnsupportedRuleCapabilityError{
			Path:       path,
			Capability: "condition",
			Name:       conditionType,
		}
	}
	switch typed {
	case RuleConditionAlways:
		if err := rejectUnknownKeys(
			condition,
			path,
			"type",
		); err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		return RuleCondition{Type: RuleConditionAlways}, nil

	case RuleConditionAll, RuleConditionAny:
		if err := rejectUnknownKeys(
			condition,
			path,
			"type",
			"conditions",
		); err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		children, err := requiredArray(
			condition["conditions"],
			path+".conditions",
		)
		if err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		compiled := make([]RuleCondition, len(children))
		for index, child := range children {
			compiled[index], err = compiler.compileCondition(
				child,
				fmt.Sprintf("%s.conditions[%d]", path, index),
			)
			if err != nil {
				return RuleCondition{}, err
			}
		}
		return RuleCondition{
			Type:       typed,
			Conditions: compiled,
		}, nil

	case RuleConditionNot:
		if err := rejectUnknownKeys(
			condition,
			path,
			"type",
			"condition",
		); err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		child, err := compiler.compileCondition(
			condition["condition"],
			path+".condition",
		)
		if err != nil {
			return RuleCondition{}, err
		}
		return RuleCondition{
			Type:      RuleConditionNot,
			Condition: &child,
		}, nil

	case RuleConditionFlag:
		if err := rejectUnknownKeys(
			condition,
			path,
			"type",
			"name",
			"value",
		); err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		name, err := requiredString(condition["name"], path+".name")
		if err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		value := true
		if condition["value"] != nil {
			value, err = ruleOptionalBool(
				condition,
				"value",
				path+".value",
			)
			if err != nil {
				return RuleCondition{}, fmt.Errorf(
					"build content rules: %w",
					err,
				)
			}
		}
		return RuleCondition{
			Type:      RuleConditionFlag,
			FlagName:  name,
			FlagValue: value,
		}, nil

	case RuleConditionQuestState:
		if err := rejectUnknownKeys(
			condition,
			path,
			"type",
			"quest",
			"state",
		); err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		questID, err := requiredString(condition["quest"], path+".quest")
		if err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		if err := compiler.requireReference(
			questID,
			"quest",
			path+".quest",
		); err != nil {
			return RuleCondition{}, err
		}
		stateText, err := requiredString(condition["state"], path+".state")
		if err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		state := RuleQuestState(stateText)
		switch state {
		case RuleQuestInactive, RuleQuestActive, RuleQuestCompleted:
		default:
			return RuleCondition{}, fmt.Errorf(
				"build content rules: %s.state has unsupported value %q",
				path,
				stateText,
			)
		}
		return RuleCondition{
			Type:       RuleConditionQuestState,
			QuestID:    questID,
			QuestState: state,
		}, nil

	case RuleConditionTurnBattleState:
		if err := rejectUnknownKeys(
			condition,
			path,
			"type",
			"battle",
			"state",
		); err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		battleID, err := requiredString(
			condition["battle"],
			path+".battle",
		)
		if err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		if err := compiler.requireReference(
			battleID,
			"turn_battle",
			path+".battle",
		); err != nil {
			return RuleCondition{}, err
		}
		stateText, err := requiredString(condition["state"], path+".state")
		if err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		state := RuleTurnBattleState(stateText)
		switch state {
		case RuleTurnBattleNever,
			RuleTurnBattleActive,
			RuleTurnBattleWon,
			RuleTurnBattleLost,
			RuleTurnBattleEscaped:
		default:
			return RuleCondition{}, fmt.Errorf(
				"build content rules: %s.state has unsupported value %q",
				path,
				stateText,
			)
		}
		return RuleCondition{
			Type:        RuleConditionTurnBattleState,
			BattleID:    battleID,
			BattleState: state,
		}, nil
	case RuleConditionCutsceneActive:
		if err := rejectUnknownKeys(
			condition,
			path,
			"type",
			"cutscene",
		); err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		cutsceneID := ruleOptionalString(condition, "cutscene")
		if cutsceneID != "" {
			if err := compiler.requireReference(
				cutsceneID,
				"cutscene",
				path+".cutscene",
			); err != nil {
				return RuleCondition{}, err
			}
		}
		return RuleCondition{
			Type:       RuleConditionCutsceneActive,
			CutsceneID: cutsceneID,
		}, nil
	case RuleConditionTimeBetween:
		if err := rejectUnknownKeys(
			condition,
			path,
			"type",
			"start",
			"finish",
		); err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		start, err := requiredString(condition["start"], path+".start")
		if err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		finish, err := requiredString(condition["finish"], path+".finish")
		if err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		startMinute, err := parseRuleClock(start, path+".start")
		if err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		finishMinute, err := parseRuleClock(finish, path+".finish")
		if err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		return RuleCondition{
			Type:         RuleConditionTimeBetween,
			StartMinute:  startMinute,
			FinishMinute: finishMinute,
		}, nil
	case RuleConditionRegionActive:
		if err := rejectUnknownKeys(
			condition,
			path,
			"type",
			"id",
		); err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		regionID, err := requiredString(condition["id"], path+".id")
		if err != nil {
			return RuleCondition{}, fmt.Errorf("build content rules: %w", err)
		}
		return RuleCondition{
			Type:     RuleConditionRegionActive,
			RegionID: regionID,
		}, nil
	default:
		panic("unreachable rule condition type")
	}
}

func (compiler *contentRuleCompiler) compileRequiredActions(
	raw any,
	path string,
) ([]RuleAction, error) {
	actions, err := requiredArray(raw, path)
	if err != nil {
		return nil, fmt.Errorf("build content rules: %w", err)
	}
	if len(actions) == 0 {
		return nil, fmt.Errorf(
			"build content rules: %s must not be empty",
			path,
		)
	}
	return compiler.compileActions(actions, path)
}

func (compiler *contentRuleCompiler) compileOptionalActions(
	raw any,
	path string,
) ([]RuleAction, error) {
	actions, exists, err := optionalArray(raw, path)
	if err != nil {
		return nil, fmt.Errorf("build content rules: %w", err)
	}
	if !exists {
		return []RuleAction{}, nil
	}
	return compiler.compileActions(actions, path)
}

func (compiler *contentRuleCompiler) compileActions(
	raw []any,
	path string,
) ([]RuleAction, error) {
	result := make([]RuleAction, 0, len(raw))
	for index, item := range raw {
		action, err := compiler.compileAction(
			item,
			fmt.Sprintf("%s[%d]", path, index),
		)
		if err != nil {
			return nil, err
		}
		result = append(result, action)
	}
	return result, nil
}

func (compiler *contentRuleCompiler) compileAction(
	raw any,
	path string,
) (RuleAction, error) {
	action, err := requiredObject(raw, path)
	if err != nil {
		return RuleAction{}, fmt.Errorf("build content rules: %w", err)
	}
	actionType, err := requiredString(action["type"], path+".type")
	if err != nil {
		return RuleAction{}, fmt.Errorf("build content rules: %w", err)
	}
	typed := RuleActionType(actionType)
	if !ruleCompilerCapabilities.SupportsAction(typed) {
		return RuleAction{}, &UnsupportedRuleCapabilityError{
			Path:       path,
			Capability: "action",
			Name:       actionType,
		}
	}
	result := RuleAction{Type: typed}
	switch typed {
	case RuleActionStartQuest:
		if err := rejectUnknownKeys(action, path, "type", "quest"); err != nil {
			return RuleAction{}, fmt.Errorf("build content rules: %w", err)
		}
		result.QuestID, err = requiredString(action["quest"], path+".quest")
		if err == nil {
			err = compiler.requireReference(
				result.QuestID,
				"quest",
				path+".quest",
			)
		}
	case RuleActionGiveItem:
		if err := rejectUnknownKeys(
			action,
			path,
			"type",
			"item",
			"amount",
		); err != nil {
			return RuleAction{}, fmt.Errorf("build content rules: %w", err)
		}
		result.ItemID, err = requiredString(action["item"], path+".item")
		if err == nil {
			err = compiler.requireReference(result.ItemID, "item", path+".item")
		}
		if err == nil {
			result.Quantity = 1
			if action["amount"] != nil {
				result.Quantity, err = ruleInteger(
					action["amount"],
					path+".amount",
					1,
				)
			}
		}
	case RuleActionEquipItem:
		if err := rejectUnknownKeys(action, path, "type", "item"); err != nil {
			return RuleAction{}, fmt.Errorf("build content rules: %w", err)
		}
		result.ItemID, err = requiredString(action["item"], path+".item")
		if err == nil {
			err = compiler.requireReference(result.ItemID, "item", path+".item")
		}
		if err == nil {
			item := compiler.definitions[result.ItemID].data
			if _, equipment := item["equipment"].(map[string]any); !equipment {
				err = fmt.Errorf(
					"%s.item references non-equipment item %q",
					path,
					result.ItemID,
				)
			}
		}
	case RuleActionAddCurrency:
		if err := rejectUnknownKeys(
			action,
			path,
			"type",
			"amount",
			"reason",
		); err != nil {
			return RuleAction{}, fmt.Errorf("build content rules: %w", err)
		}
		result.Currency, err = ruleInteger(action["amount"], path+".amount", 0)
		if err == nil {
			result.Reason, err = ruleOptionalStringChecked(
				action,
				"reason",
				path+".reason",
			)
		}
	case RuleActionSetFlag:
		if err := rejectUnknownKeys(
			action,
			path,
			"type",
			"name",
			"value",
		); err != nil {
			return RuleAction{}, fmt.Errorf("build content rules: %w", err)
		}
		result.FlagName, err = requiredString(action["name"], path+".name")
		result.FlagValue = true
		if err == nil && action["value"] != nil {
			result.FlagValue, err = ruleOptionalBool(
				action,
				"value",
				path+".value",
			)
		}
	case RuleActionFinishGame:
		err = rejectUnknownKeys(action, path, "type")
	case RuleActionOpenShop:
		if err := rejectUnknownKeys(action, path, "type", "shop"); err != nil {
			return RuleAction{}, fmt.Errorf("build content rules: %w", err)
		}
		result.ShopID, err = requiredString(action["shop"], path+".shop")
		if err == nil {
			err = compiler.requireReference(result.ShopID, "shop", path+".shop")
		}
	case RuleActionStartDialogue:
		if err := rejectUnknownKeys(
			action,
			path,
			"type",
			"dialogue",
		); err != nil {
			return RuleAction{}, fmt.Errorf("build content rules: %w", err)
		}
		result.DialogueID, err = requiredString(
			action["dialogue"],
			path+".dialogue",
		)
		if err == nil {
			err = compiler.requireReference(
				result.DialogueID,
				"dialogue",
				path+".dialogue",
			)
		}
	case RuleActionStartCutscene:
		if err := rejectUnknownKeys(
			action,
			path,
			"type",
			"cutscene",
		); err != nil {
			return RuleAction{}, fmt.Errorf("build content rules: %w", err)
		}
		result.CutsceneID, err = requiredString(
			action["cutscene"],
			path+".cutscene",
		)
		if err == nil {
			err = compiler.requireReference(
				result.CutsceneID,
				"cutscene",
				path+".cutscene",
			)
		}
	case RuleActionDamage:
		if err := rejectUnknownKeys(action, path, "type", "amount"); err != nil {
			return RuleAction{}, fmt.Errorf("build content rules: %w", err)
		}
		result.DamageAmount, err = requiredPositiveNumberValue(
			action["amount"],
			path+".amount",
		)
	case RuleActionHeal:
		if err := rejectUnknownKeys(action, path, "type", "amount"); err != nil {
			return RuleAction{}, fmt.Errorf("build content rules: %w", err)
		}
		result.HealAmount, err = requiredPositiveNumberValue(
			action["amount"],
			path+".amount",
		)
	case RuleActionEmit:
		if err := rejectUnknownKeys(
			action,
			path,
			"type",
			"name",
			"data",
		); err != nil {
			return RuleAction{}, fmt.Errorf("build content rules: %w", err)
		}
		result.EventName, err = requiredString(action["name"], path+".name")
		if err == nil && sim.IsReservedEventType(sim.EventType(result.EventName)) {
			err = fmt.Errorf(
				"%s.name %q is reserved by the engine",
				path,
				result.EventName,
			)
		}
		if err == nil && action["data"] != nil {
			var data map[string]any
			data, err = requiredObject(action["data"], path+".data")
			if err == nil {
				result.EventData, err = json.Marshal(data)
			}
		}
	case RuleActionShowNotice:
		if err := rejectUnknownKeys(
			action,
			path,
			"type",
			"text",
			"text_key",
			"duration",
			"tone",
		); err != nil {
			return RuleAction{}, fmt.Errorf("build content rules: %w", err)
		}
		result.NoticeText, err = ruleOptionalStringChecked(
			action,
			"text",
			path+".text",
		)
		if err == nil {
			result.NoticeKey, err = ruleOptionalStringChecked(
				action,
				"text_key",
				path+".text_key",
			)
		}
		if err == nil && result.NoticeText == "" && result.NoticeKey == "" {
			err = fmt.Errorf("%s requires text or text_key", path)
		}
		duration := 3.0
		if err == nil && action["duration"] != nil {
			duration, err = requiredPositiveNumberValue(
				action["duration"],
				path+".duration",
			)
		}
		if err == nil && !durationFitsPortableTicks(duration) {
			err = fmt.Errorf(
				"%s.duration exceeds the supported duration",
				path,
			)
		}
		if err == nil {
			result.NoticeTicks = secondsToTicks(duration)
			result.NoticeTone = "info"
			if action["tone"] != nil {
				result.NoticeTone, err = requiredString(
					action["tone"],
					path+".tone",
				)
			}
		}
		if err == nil &&
			result.NoticeTone != "info" &&
			result.NoticeTone != "success" &&
			result.NoticeTone != "warning" {
			err = fmt.Errorf(
				"%s.tone must be one of info, success, warning",
				path,
			)
		}
	case RuleActionStartTurnBattle:
		if err := rejectUnknownKeys(
			action,
			path,
			"type",
			"battle",
		); err != nil {
			return RuleAction{}, fmt.Errorf("build content rules: %w", err)
		}
		result.BattleID, err = requiredString(
			action["battle"],
			path+".battle",
		)
		if err == nil {
			err = compiler.requireReference(
				result.BattleID,
				"turn_battle",
				path+".battle",
			)
		}
	case RuleActionSetWorldTime:
		if err := rejectUnknownKeys(
			action,
			path,
			"type",
			"time",
			"day",
		); err != nil {
			return RuleAction{}, fmt.Errorf("build content rules: %w", err)
		}
		clock, clockErr := requiredString(action["time"], path+".time")
		if clockErr != nil {
			err = clockErr
			break
		}
		result.WorldMinute, err = parseRuleClock(clock, path+".time")
		if err == nil && action["day"] != nil {
			var day int
			day, err = ruleInteger(action["day"], path+".day", 1)
			result.WorldDay = int64(day)
		}
	case RuleActionAdvanceWorldTime:
		if err := rejectUnknownKeys(
			action,
			path,
			"type",
			"minutes",
		); err != nil {
			return RuleAction{}, fmt.Errorf("build content rules: %w", err)
		}
		result.WorldMinutes, err = requiredPositiveNumberValue(
			action["minutes"],
			path+".minutes",
		)
	}
	if err != nil {
		return RuleAction{}, fmt.Errorf("build content rules: %w", err)
	}
	return result, nil
}

func parseRuleClock(value string, path string) (float64, error) {
	var hour, minute int
	if _, err := fmt.Sscanf(value, "%d:%d", &hour, &minute); err != nil ||
		value != fmt.Sprintf("%02d:%02d", hour, minute) ||
		hour < 0 || hour > 23 || minute < 0 || minute > 59 {
		return 0, fmt.Errorf("%s must use 24-hour HH:MM time", path)
	}
	return float64(hour*60 + minute), nil
}

func (compiler *contentRuleCompiler) requireReference(
	id string,
	kind string,
	path string,
) error {
	definition, exists := compiler.definitions[id]
	if !exists {
		return fmt.Errorf(
			"build content rules: %s references missing definition %q",
			path,
			id,
		)
	}
	if definition.kind != kind {
		return fmt.Errorf(
			"build content rules: %s must reference %s content, got %q (%s)",
			path,
			kind,
			id,
			definition.kind,
		)
	}
	return nil
}

func ruleInteger(value any, path string, minimum int) (int, error) {
	number, err := requiredNumber(value, path)
	if err != nil {
		return 0, err
	}
	if math.Trunc(number) != number || number < float64(minimum) {
		if minimum == 0 {
			return 0, fmt.Errorf("%s must be a non-negative integer", path)
		}
		return 0, fmt.Errorf(
			"%s must be an integer of at least %d",
			path,
			minimum,
		)
	}
	if number > float64(campaign.MaxJSONInteger) {
		return 0, fmt.Errorf(
			"%s exceeds the JSON-safe integer range",
			path,
		)
	}
	// int conversion at the positive boundary is implementation-dependent.
	if number >= math.Ldexp(1, strconv.IntSize-1) {
		return 0, fmt.Errorf("%s exceeds the supported integer range", path)
	}
	return int(number), nil
}

func ruleSignedInteger(value any, path string) (int, error) {
	number, err := requiredNumber(value, path)
	if err != nil {
		return 0, err
	}
	if math.Trunc(number) != number {
		return 0, fmt.Errorf("%s must be an integer", path)
	}
	if math.Abs(number) > float64(campaign.MaxJSONInteger) {
		return 0, fmt.Errorf(
			"%s exceeds the JSON-safe integer range",
			path,
		)
	}
	limit := math.Ldexp(1, strconv.IntSize-1)
	if number >= limit || number < -limit {
		return 0, fmt.Errorf("%s exceeds the supported integer range", path)
	}
	return int(number), nil
}

func ruleOptionalString(object map[string]any, key string) string {
	value, _ := object[key].(string)
	return value
}

func ruleOptionalStringChecked(
	object map[string]any,
	key string,
	path string,
) (string, error) {
	if object[key] == nil {
		return "", nil
	}
	return requiredString(object[key], path)
}

func ruleOptionalBool(
	object map[string]any,
	key string,
	path string,
) (bool, error) {
	if object[key] == nil {
		return false, nil
	}
	value, ok := object[key].(bool)
	if !ok {
		return false, fmt.Errorf("%s must be a boolean", path)
	}
	return value, nil
}

func cloneRuleCapabilities(
	value RuleCompilerCapabilities,
) RuleCompilerCapabilities {
	return RuleCompilerCapabilities{
		Actions:    append([]RuleActionType(nil), value.Actions...),
		Conditions: append([]RuleConditionType(nil), value.Conditions...),
	}
}

func cloneDialogueRule(value DialogueRule) DialogueRule {
	result := value
	result.Nodes = make([]DialogueNodeRule, len(value.Nodes))
	for index, node := range value.Nodes {
		result.Nodes[index] = cloneDialogueNodeRule(node)
	}
	return result
}

func cloneDialogueNodeRule(value DialogueNodeRule) DialogueNodeRule {
	result := value
	result.Actions = cloneRuleActions(value.Actions)
	result.Choices = make([]DialogueChoiceRule, len(value.Choices))
	for index, choice := range value.Choices {
		result.Choices[index] = cloneDialogueChoiceRule(choice)
	}
	return result
}

func cloneDialogueChoiceRule(value DialogueChoiceRule) DialogueChoiceRule {
	result := value
	result.Actions = cloneRuleActions(value.Actions)
	result.Condition = cloneRuleConditionPointer(value.Condition)
	return result
}

func cloneCutsceneRule(value CutsceneRule) CutsceneRule {
	result := value
	result.Steps = make([]CutsceneStepRule, len(value.Steps))
	for index, step := range value.Steps {
		result.Steps[index] = step
		result.Steps[index].Actions = cloneRuleActions(step.Actions)
	}
	result.OnComplete = cloneRuleActions(value.OnComplete)
	return result
}

func cloneQuestRule(value QuestRule) QuestRule {
	result := value
	result.Objectives = append([]QuestObjectiveRule(nil), value.Objectives...)
	for index := range result.Objectives {
		result.Objectives[index].Where = cloneRuleFilter(
			result.Objectives[index].Where,
		)
	}
	result.OnStart = cloneRuleActions(value.OnStart)
	result.OnComplete = cloneRuleActions(value.OnComplete)
	return result
}

func cloneRuleFilter(value map[string]any) map[string]any {
	result := make(map[string]any, len(value))
	for key, item := range value {
		result[key] = item
	}
	return result
}

func cloneItemRule(value ItemRule) ItemRule {
	result := value
	result.Effects = cloneRuleActions(value.Effects)
	if value.Equipment != nil {
		equipment := *value.Equipment
		result.Equipment = &equipment
	}
	return result
}

func cloneShopRule(value ShopRule) ShopRule {
	result := value
	result.Offers = append([]ShopOfferRule(nil), value.Offers...)
	return result
}

func cloneActorInteractionRule(
	value ActorInteractionRule,
) ActorInteractionRule {
	result := value
	result.Actions = cloneRuleActions(value.Actions)
	result.Condition = cloneRuleConditionPointer(value.Condition)
	result.Pages = make(
		[]ActorInteractionPageRule,
		len(value.Pages),
	)
	for index, page := range value.Pages {
		result.Pages[index] = page
		result.Pages[index].Condition =
			cloneRuleConditionPointer(page.Condition)
		result.Pages[index].Actions =
			cloneRuleActions(page.Actions)
	}
	return result
}

func cloneRuleConditionPointer(value *RuleCondition) *RuleCondition {
	if value == nil {
		return nil
	}
	result := cloneRuleCondition(*value)
	return &result
}

func cloneRuleCondition(value RuleCondition) RuleCondition {
	result := value
	result.Conditions = make([]RuleCondition, len(value.Conditions))
	for index, child := range value.Conditions {
		result.Conditions[index] = cloneRuleCondition(child)
	}
	result.Condition = cloneRuleConditionPointer(value.Condition)
	return result
}

func cloneRuleActions(value []RuleAction) []RuleAction {
	result := append([]RuleAction(nil), value...)
	for index := range result {
		result[index].EventData = append(
			json.RawMessage(nil),
			value[index].EventData...,
		)
	}
	return result
}
