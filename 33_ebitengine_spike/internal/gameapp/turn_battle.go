package gameapp

import (
	"encoding/json"
	"errors"
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/rulesruntime"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

type turnBattleEnemyState struct {
	ID        string
	ActorID   string
	Name      string
	Health    int
	MaxHealth int
	Attack    int
	Defense   int
	Skills    []string
}

type turnBattleSession struct {
	BattleID string
	PlayerID string
	Turn     int
	Selected int
	Message  string
	Enemies  []turnBattleEnemyState
}

func cloneTurnBattleSession(
	session *turnBattleSession,
) *turnBattleSession {
	if session == nil {
		return nil
	}
	result := *session
	result.Enemies = make([]turnBattleEnemyState, len(session.Enemies))
	for index, enemy := range session.Enemies {
		result.Enemies[index] = enemy
		result.Enemies[index].Skills = append(
			[]string(nil),
			enemy.Skills...,
		)
	}
	return &result
}

type TurnBattleState struct {
	Active        bool                       `json:"active"`
	BattleID      string                     `json:"battle_id,omitempty"`
	Name          string                     `json:"name,omitempty"`
	Turn          int                        `json:"turn,omitempty"`
	SelectedIndex int                        `json:"selected_index"`
	Message       string                     `json:"message,omitempty"`
	PlayerID      string                     `json:"player_id,omitempty"`
	PlayerHealth  int                        `json:"player_health,omitempty"`
	PlayerMax     int                        `json:"player_max_health,omitempty"`
	Enemies       []TurnBattleEnemyState     `json:"enemies"`
	Options       []TurnBattleOptionState    `json:"options"`
	Results       []campaign.TurnBattleState `json:"results"`
	Revision      uint64                     `json:"revision"`
}

type TurnBattleEnemyState struct {
	ID        string `json:"id"`
	ActorID   string `json:"actor_id"`
	Name      string `json:"name"`
	Health    int    `json:"health"`
	MaxHealth int    `json:"max_health"`
}

type TurnBattleOptionState struct {
	ID    string `json:"id"`
	Type  string `json:"type"`
	Label string `json:"label"`
}

func (runtime *Runtime) TurnBattleState() TurnBattleState {
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	return runtime.turnBattleStateLocked()
}

func (runtime *Runtime) handleTurnBattleActionsLocked(
	actions ebitapp.Actions,
) (bool, error) {
	if runtime.turnBattle == nil {
		return false, nil
	}
	options := runtime.turnBattleOptionsLocked()
	pause := actions.Pause || runtime.virtualPressed("pause")
	cancel := actions.MenuCancel || runtime.virtualPressed("menu_cancel")
	confirm := actions.MenuConfirm || runtime.virtualPressed("menu_confirm")
	up := actions.MenuUp || runtime.virtualPressed("menu_up")
	down := actions.MenuDown || runtime.virtualPressed("menu_down")
	runtime.advanceVirtualLocked()
	switch {
	case pause:
		runtime.turnBattle.Message = runtime.localizeRuleTextLocked(
			"Finish the battle before pausing.",
			"ui.battle.pause_blocked",
		)
		runtime.revision++
	case cancel:
		battle, _ := runtime.contentRules.TurnBattle(
			runtime.turnBattle.BattleID,
		)
		if battle.AllowEscape {
			return true, runtime.chooseTurnBattleLocked(len(options) - 1)
		}
		runtime.turnBattle.Message = runtime.localizeRuleTextLocked(
			"You cannot escape this battle.",
			"ui.battle.escape_blocked",
		)
		runtime.revision++
	case len(options) != 0 && up != down:
		if up {
			runtime.turnBattle.Selected--
		} else {
			runtime.turnBattle.Selected++
		}
		if runtime.turnBattle.Selected < 0 {
			runtime.turnBattle.Selected = len(options) - 1
		}
		if runtime.turnBattle.Selected >= len(options) {
			runtime.turnBattle.Selected = 0
		}
		runtime.revision++
	case len(options) != 0 && confirm:
		return true, runtime.chooseTurnBattleLocked(
			runtime.turnBattle.Selected,
		)
	}
	return true, nil
}

func (runtime *Runtime) turnBattleStateLocked() TurnBattleState {
	state := TurnBattleState{
		SelectedIndex: -1,
		Enemies:       []TurnBattleEnemyState{},
		Options:       []TurnBattleOptionState{},
		Results: append(
			[]campaign.TurnBattleState(nil),
			runtime.campaign.Snapshot().TurnBattles...,
		),
		Revision: runtime.revision,
	}
	if runtime.turnBattle == nil {
		return state
	}
	session := runtime.turnBattle
	state.Active = true
	state.BattleID = session.BattleID
	state.Turn = session.Turn
	state.SelectedIndex = session.Selected
	state.Message = session.Message
	state.PlayerID = session.PlayerID
	if rule, exists := runtime.contentRules.TurnBattle(session.BattleID); exists {
		state.Name = runtime.localizeRuleTextLocked(rule.Name, rule.NameKey)
	}
	if player, exists := runtime.entitySnapshotLocked(session.PlayerID); exists {
		state.PlayerHealth = player.Health
		state.PlayerMax = player.MaxHealth
	}
	for _, enemy := range session.Enemies {
		state.Enemies = append(state.Enemies, TurnBattleEnemyState{
			ID:        enemy.ID,
			ActorID:   enemy.ActorID,
			Name:      enemy.Name,
			Health:    enemy.Health,
			MaxHealth: enemy.MaxHealth,
		})
	}
	for _, option := range runtime.turnBattleOptionsLocked() {
		state.Options = append(state.Options, TurnBattleOptionState{
			ID:    option.ID,
			Type:  option.Type,
			Label: option.Label,
		})
	}
	return state
}

type turnBattleOption struct {
	ID    string
	Type  string
	Label string
}

func (runtime *Runtime) turnBattleOptionsLocked() []turnBattleOption {
	if runtime.turnBattle == nil {
		return []turnBattleOption{}
	}
	metadata, exists := runtime.metadata(runtime.turnBattle.PlayerID)
	if !exists {
		return []turnBattleOption{}
	}
	battler, exists := runtime.contentRules.TurnBattler(metadata.ActorID)
	if !exists {
		return []turnBattleOption{}
	}
	result := make([]turnBattleOption, 0, len(battler.Skills)+1)
	for _, skillID := range battler.Skills {
		skill, exists := runtime.contentRules.TurnSkill(skillID)
		if !exists {
			continue
		}
		result = append(result, turnBattleOption{
			ID:   skill.ID,
			Type: "skill",
			Label: runtime.localizeRuleTextLocked(
				skill.Name,
				skill.NameKey,
			),
		})
	}
	battle, exists := runtime.contentRules.TurnBattle(
		runtime.turnBattle.BattleID,
	)
	if exists && battle.AllowEscape {
		result = append(result, turnBattleOption{
			ID:   "escape",
			Type: "escape",
			Label: runtime.localizeRuleTextLocked(
				"Escape",
				"ui.battle.escape",
			),
		})
	}
	return result
}

func (runtime *Runtime) startTurnBattleLocked(battleID string) error {
	if runtime.turnBattle != nil {
		return errors.New("another turn battle is already active")
	}
	if runtime.campaign.Snapshot().Mode != campaign.ModePlaying {
		return errors.New("turn battle can only start during gameplay")
	}
	if runtime.dialogue != nil ||
		runtime.activeShopID != "" ||
		runtime.inventoryOpen ||
		runtime.cutscene != nil {
		return errors.New("turn battle cannot start while another modal is active")
	}
	rule, exists := runtime.contentRules.TurnBattle(battleID)
	if !exists {
		return fmt.Errorf("unknown turn battle %q", battleID)
	}
	for _, result := range runtime.campaign.Snapshot().TurnBattles {
		if result.ID == battleID &&
			result.Outcome == campaign.TurnBattleWon &&
			!rule.Repeatable {
			return nil
		}
	}
	playerID := runtime.built.Config.Camera.TargetEntityID
	player, exists := runtime.entitySnapshotLocked(playerID)
	if !exists || player.Dead {
		return errors.New("turn battle requires a live controlled actor")
	}
	metadata, exists := runtime.metadata(playerID)
	if !exists {
		return errors.New("turn battle controlled actor metadata is missing")
	}
	if _, exists := runtime.contentRules.TurnBattler(metadata.ActorID); !exists {
		return fmt.Errorf(
			"controlled actor %q is not a turn battler",
			metadata.ActorID,
		)
	}
	session := &turnBattleSession{
		BattleID: battleID,
		PlayerID: playerID,
		Turn:     1,
		Selected: 0,
		Enemies:  make([]turnBattleEnemyState, 0, len(rule.Enemies)),
	}
	for _, enemy := range rule.Enemies {
		name := enemy.Name
		if name == "" {
			name = enemy.ActorID
		}
		session.Enemies = append(session.Enemies, turnBattleEnemyState{
			ID:        enemy.ID,
			ActorID:   enemy.ActorID,
			Name:      name,
			Health:    enemy.MaxHealth,
			MaxHealth: enemy.MaxHealth,
			Attack:    enemy.Attack,
			Defense:   enemy.Defense,
			Skills:    append([]string(nil), enemy.Skills...),
		})
	}
	checkpoint := runtime.checkpointLocked()
	if err := runtime.detachMutableLocked(checkpoint); err != nil {
		return err
	}
	runtime.turnBattle = session
	result, err := runtime.ruleExecutor.Execute(
		runtime.campaign,
		rule.OnStart,
	)
	if err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return fmt.Errorf("start turn battle %q hooks: %w", battleID, err)
	}
	if err := runtime.applyRuleIntentsLocked(result.Intents, playerID); err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return fmt.Errorf("start turn battle %q intents: %w", battleID, err)
	}
	runtime.queueAudioEventLocked("turn_battle.started")
	runtime.revision++
	return nil
}

func (runtime *Runtime) chooseTurnBattleLocked(selector int) error {
	if runtime.turnBattle == nil {
		return errors.New("no active turn battle")
	}
	options := runtime.turnBattleOptionsLocked()
	if selector < 0 || selector >= len(options) {
		return fmt.Errorf("turn battle option %d is unavailable", selector)
	}
	option := options[selector]
	if option.Type == "escape" {
		return runtime.finishTurnBattleLocked(campaign.TurnBattleEscaped)
	}

	checkpoint := runtime.checkpointLocked()
	if err := runtime.detachMutableLocked(checkpoint); err != nil {
		return err
	}
	session := runtime.turnBattle
	skill, exists := runtime.contentRules.TurnSkill(option.ID)
	if !exists {
		runtime.restoreCheckpointLocked(checkpoint)
		return fmt.Errorf("turn battle skill %q is missing", option.ID)
	}
	if skill.Effect == "damage" {
		enemy := firstLivingTurnEnemy(session)
		if enemy == nil {
			runtime.restoreCheckpointLocked(checkpoint)
			return errors.New("turn battle has no living enemy")
		}
		player, _ := runtime.entitySnapshotLocked(session.PlayerID)
		amount := max(1, skill.Power+player.Stats.Attack-enemy.Defense)
		enemy.Health = max(0, enemy.Health-amount)
		session.Message = fmt.Sprintf("%s -%d", enemy.Name, amount)
		runtime.queueAudioEventLocked("turn_battle.skill_used")
	} else {
		if err := runtime.changeTurnPlayerHealthLocked(
			session.PlayerID,
			skill.Power,
		); err != nil {
			runtime.restoreCheckpointLocked(checkpoint)
			return err
		}
		session.Message = fmt.Sprintf("%s +%d", session.PlayerID, skill.Power)
		runtime.queueAudioEventLocked("turn_battle.skill_used")
	}
	if firstLivingTurnEnemy(session) == nil {
		if err := runtime.finishTurnBattleLocked(campaign.TurnBattleWon); err != nil {
			runtime.restoreCheckpointLocked(checkpoint)
			return err
		}
		return nil
	}
	if err := runtime.runTurnEnemyActionsLocked(); err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return err
	}
	player, _ := runtime.entitySnapshotLocked(session.PlayerID)
	if player.Dead {
		if err := runtime.finishTurnBattleLocked(campaign.TurnBattleLost); err != nil {
			runtime.restoreCheckpointLocked(checkpoint)
			return err
		}
		return nil
	}
	session.Turn++
	runtime.revision++
	return nil
}

func firstLivingTurnEnemy(
	session *turnBattleSession,
) *turnBattleEnemyState {
	if session == nil {
		return nil
	}
	for index := range session.Enemies {
		if session.Enemies[index].Health > 0 {
			return &session.Enemies[index]
		}
	}
	return nil
}

func (runtime *Runtime) runTurnEnemyActionsLocked() error {
	session := runtime.turnBattle
	for index := range session.Enemies {
		enemy := &session.Enemies[index]
		if enemy.Health <= 0 {
			continue
		}
		player, exists := runtime.entitySnapshotLocked(session.PlayerID)
		if !exists || player.Dead {
			break
		}
		skill, exists := runtime.enemyTurnSkillLocked(*enemy)
		if !exists {
			return fmt.Errorf("enemy %q has no usable turn skill", enemy.ID)
		}
		if skill.Effect == "heal" {
			amount := min(skill.Power, enemy.MaxHealth-enemy.Health)
			enemy.Health += amount
			session.Message = fmt.Sprintf("%s +%d", enemy.Name, amount)
		} else {
			amount := max(
				1,
				skill.Power+enemy.Attack-player.Stats.Defense,
			)
			if err := runtime.changeTurnPlayerHealthLocked(
				session.PlayerID,
				-amount,
			); err != nil {
				return err
			}
			session.Message = fmt.Sprintf("%s -%d", session.PlayerID, amount)
		}
		runtime.queueAudioEventLocked("turn_battle.skill_used")
	}
	return nil
}

func (runtime *Runtime) enemyTurnSkillLocked(
	enemy turnBattleEnemyState,
) (gamebuild.TurnSkillRule, bool) {
	var healing *gamebuild.TurnSkillRule
	for _, skillID := range enemy.Skills {
		skill, exists := runtime.contentRules.TurnSkill(skillID)
		if !exists {
			continue
		}
		if skill.Effect == "damage" {
			return skill, true
		}
		if skill.Effect == "heal" && enemy.Health < enemy.MaxHealth &&
			healing == nil {
			candidate := skill
			healing = &candidate
		}
	}
	if healing != nil {
		return *healing, true
	}
	if len(enemy.Skills) != 0 {
		return runtime.contentRules.TurnSkill(enemy.Skills[0])
	}
	return gamebuild.TurnSkillRule{}, false
}

func (runtime *Runtime) finishTurnBattleLocked(
	outcome campaign.TurnBattleOutcome,
) error {
	if runtime.turnBattle == nil {
		return errors.New("no active turn battle")
	}
	session := runtime.turnBattle
	result, err := runtime.ruleExecutor.CompleteTurnBattle(
		runtime.campaign,
		session.BattleID,
		outcome,
	)
	if err != nil {
		return err
	}
	if err := runtime.applyRuleIntentsLocked(
		result.Intents,
		session.PlayerID,
	); err != nil {
		return err
	}
	eventData, err := json.Marshal(map[string]any{
		"battle_id": session.BattleID,
		"turn":      session.Turn,
	})
	if err != nil {
		return err
	}
	if err := runtime.applyAuthoredEventIntentLocked(
		rulesruntime.Intent{
			Type:      rulesruntime.IntentEmit,
			EventName: "turn_battle." + string(outcome),
			EventData: eventData,
		},
		session.PlayerID,
		"",
	); err != nil {
		return err
	}
	runtime.turnBattle = nil
	runtime.queueAudioEventLocked("turn_battle." + string(outcome))
	if outcome == campaign.TurnBattleLost {
		if err := runtime.enterGameOverLocked(); err != nil {
			return err
		}
	}
	runtime.revision++
	return nil
}

func (runtime *Runtime) changeTurnPlayerHealthLocked(
	entityID string,
	delta int,
) error {
	state := runtime.simulation.SaveSession()
	for index := range state.Entities {
		entity := &state.Entities[index]
		if entity.ID != entityID {
			continue
		}
		definition, exists := runtime.entityConfig(entityID)
		if !exists {
			return fmt.Errorf("turn battler entity %q is undefined", entityID)
		}
		entity.Health = min(
			definition.MaxHealth,
			max(0, entity.Health+delta),
		)
		entity.Dead = entity.Health == 0
		if entity.Dead {
			entity.Attack = nil
			entity.Statuses = nil
			entity.StaggerTicks = 0
			entity.InvulnerableTicks = 0
			entity.FlashTicks = 0
			entity.Knockback = sim.BurstSessionState{}
			entity.Dodge = sim.BurstSessionState{}
			entity.ParryTicks = 0
		}
		if err := runtime.simulation.LoadSession(state); err != nil {
			return fmt.Errorf("change turn battler health: %w", err)
		}
		return nil
	}
	return fmt.Errorf("turn battler entity %q is missing", entityID)
}

func (runtime *Runtime) entitySnapshotLocked(
	entityID string,
) (sim.EntitySnapshot, bool) {
	for _, entity := range runtime.simulation.Snapshot().Entities {
		if entity.ID == entityID {
			return entity, true
		}
	}
	return sim.EntitySnapshot{}, false
}

func (runtime *Runtime) turnBattleViewLocked() ebitapp.TurnBattleView {
	state := runtime.turnBattleStateLocked()
	result := ebitapp.TurnBattleView{
		Active:        state.Active,
		BattleID:      state.BattleID,
		Name:          state.Name,
		Turn:          state.Turn,
		SelectedIndex: state.SelectedIndex,
		Message:       state.Message,
		PlayerID:      state.PlayerID,
		PlayerHealth:  state.PlayerHealth,
		PlayerMax:     state.PlayerMax,
		Enemies:       make([]ebitapp.TurnBattleEnemyView, len(state.Enemies)),
		Options:       make([]ebitapp.TurnBattleOptionView, len(state.Options)),
	}
	for index, enemy := range state.Enemies {
		result.Enemies[index] = ebitapp.TurnBattleEnemyView{
			ID:        enemy.ID,
			Name:      enemy.Name,
			Health:    enemy.Health,
			MaxHealth: enemy.MaxHealth,
		}
	}
	for index, option := range state.Options {
		result.Options[index] = ebitapp.TurnBattleOptionView{
			ID:    option.ID,
			Type:  option.Type,
			Label: option.Label,
		}
	}
	return result
}
