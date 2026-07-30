package gameapp

import (
	"context"
	"sort"
	"strings"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/rulesruntime"
)

func TestTurnBattleFreezesWorldCompletesHooksAndPersistsOutcome(
	t *testing.T,
) {
	runtime := newTestRuntime(t)
	installTurnBattleTestRules(t, runtime, gamebuild.TurnBattleRule{
		ID:   "turn_battle.test",
		Name: "Test Battle",
		Enemies: []gamebuild.TurnBattleEnemyRule{
			{
				ID:        "slime",
				ActorID:   "actor.turn_slime",
				Name:      "Slime",
				MaxHealth: 1,
				Skills:    []string{"turn_skill.nibble"},
			},
		},
		OnVictory: []gamebuild.RuleAction{
			{
				Type:     gamebuild.RuleActionAddCurrency,
				Currency: 7,
			},
		},
	})

	runtime.mu.Lock()
	if err := runtime.startTurnBattleLocked("turn_battle.test"); err != nil {
		runtime.mu.Unlock()
		t.Fatal(err)
	}
	runtime.mu.Unlock()
	before := runtime.simulation.Snapshot().WorldTick
	if err := runtime.Tick(ebitapp.Actions{MoveX: 1}); err != nil {
		t.Fatal(err)
	}
	if got := runtime.simulation.Snapshot().WorldTick; got != before {
		t.Fatalf("turn battle advanced world tick from %d to %d", before, got)
	}
	if _, err := runtime.save(context.Background(), "during-battle"); err == nil ||
		!strings.Contains(err.Error(), "turn battle is active") {
		t.Fatalf("active battle save error = %v", err)
	}

	if err := runtime.Tick(ebitapp.Actions{MenuConfirm: true}); err != nil {
		t.Fatal(err)
	}
	battle := runtime.TurnBattleState()
	if battle.Active {
		t.Fatalf("completed battle remained active: %#v", battle)
	}
	state := runtime.CampaignState()
	if got := turnBattleOutcome(t, state, "turn_battle.test"); got !=
		campaign.TurnBattleWon {
		t.Fatalf("turn battle outcome = %q", got)
	}
	if state.Currency != 7 {
		t.Fatalf("victory hook currency = %d, want 7", state.Currency)
	}
	data, err := runtime.campaign.Marshal()
	if err != nil {
		t.Fatal(err)
	}
	restored, err := campaign.Decode(runtime.campaignConfig, data)
	if err != nil {
		t.Fatal(err)
	}
	if got := turnBattleOutcome(
		t,
		restored.Snapshot(),
		"turn_battle.test",
	); got != campaign.TurnBattleWon {
		t.Fatalf("restored turn battle outcome = %q", got)
	}

	runtime.mu.Lock()
	err = runtime.startTurnBattleLocked("turn_battle.test")
	active := runtime.turnBattle != nil
	runtime.mu.Unlock()
	if err != nil || active {
		t.Fatalf("non-repeatable won battle restart = active %v err %v", active, err)
	}
}

func TestTurnBattleEscapeCanRetryAndDefeatEntersGameOver(t *testing.T) {
	runtime := newTestRuntime(t)
	installTurnBattleTestRules(t, runtime, gamebuild.TurnBattleRule{
		ID:          "turn_battle.test",
		Name:        "Test Battle",
		AllowEscape: true,
		Enemies: []gamebuild.TurnBattleEnemyRule{
			{
				ID:        "slime",
				ActorID:   "actor.turn_slime",
				Name:      "Slime",
				MaxHealth: 999,
				Skills:    []string{"turn_skill.nibble"},
			},
		},
	})
	runtime.mu.Lock()
	if err := runtime.startTurnBattleLocked("turn_battle.test"); err != nil {
		runtime.mu.Unlock()
		t.Fatal(err)
	}
	runtime.mu.Unlock()
	if err := runtime.Tick(ebitapp.Actions{MenuCancel: true}); err != nil {
		t.Fatal(err)
	}
	if got := turnBattleOutcome(
		t,
		runtime.CampaignState(),
		"turn_battle.test",
	); got != campaign.TurnBattleEscaped {
		t.Fatalf("escaped battle outcome = %q", got)
	}

	runtime.mu.Lock()
	if err := runtime.startTurnBattleLocked("turn_battle.test"); err != nil {
		runtime.mu.Unlock()
		t.Fatal(err)
	}
	runtime.mu.Unlock()
	if err := runtime.Tick(ebitapp.Actions{MenuConfirm: true}); err != nil {
		t.Fatal(err)
	}
	state := runtime.CampaignState()
	if got := turnBattleOutcome(t, state, "turn_battle.test"); got !=
		campaign.TurnBattleLost {
		t.Fatalf("lost battle outcome = %q", got)
	}
	if state.Mode != campaign.ModeGameOver {
		t.Fatalf("lost battle mode = %q", state.Mode)
	}
}

func installTurnBattleTestRules(
	t *testing.T,
	runtime *Runtime,
	battle gamebuild.TurnBattleRule,
) {
	t.Helper()
	runtime.mu.Lock()
	defer runtime.mu.Unlock()

	playerID := runtime.built.Config.Camera.TargetEntityID
	metadata, exists := runtime.metadata(playerID)
	if !exists {
		t.Fatalf("controlled metadata %q is missing", playerID)
	}
	rules := runtime.contentRules.Clone()
	rules.TurnSkills = []gamebuild.TurnSkillRule{
		{
			ID:     "turn_skill.hit",
			Name:   "Hit",
			Effect: "damage",
			Target: "enemy",
			Power:  5,
		},
		{
			ID:     "turn_skill.nibble",
			Name:   "Nibble",
			Effect: "damage",
			Target: "enemy",
			Power:  1000,
		},
	}
	rules.TurnBattlers = []gamebuild.ActorTurnBattlerRule{
		{
			ActorID: metadata.ActorID,
			Skills:  []string{"turn_skill.hit"},
		},
	}
	rules.TurnBattles = []gamebuild.TurnBattleRule{battle}
	sort.Slice(rules.TurnBattlers, func(i, j int) bool {
		return rules.TurnBattlers[i].ActorID < rules.TurnBattlers[j].ActorID
	})

	config := runtime.campaignConfig.Clone()
	config.TurnBattles = []campaign.TurnBattleDefinition{
		{ID: battle.ID},
	}
	state := runtime.campaign.Snapshot()
	state.TurnBattles = []campaign.TurnBattleState{
		{ID: battle.ID},
	}
	active, err := campaign.Restore(config, state)
	if err != nil {
		t.Fatal(err)
	}
	executor, err := rulesruntime.New(config, rules)
	if err != nil {
		t.Fatal(err)
	}
	runtime.campaignConfig = config
	runtime.campaign = active
	runtime.contentRules = rules
	runtime.ruleExecutor = executor
}

func turnBattleOutcome(
	t *testing.T,
	state campaign.State,
	id string,
) campaign.TurnBattleOutcome {
	t.Helper()
	for _, battle := range state.TurnBattles {
		if battle.ID == id {
			return battle.Outcome
		}
	}
	t.Fatalf("turn battle %q is missing", id)
	return campaign.TurnBattleNever
}
