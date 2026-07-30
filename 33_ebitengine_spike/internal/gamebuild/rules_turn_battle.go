package gamebuild

import "fmt"

func (compiler *contentRuleCompiler) compileTurnSkill(
	id string,
) (TurnSkillRule, error) {
	if err := compiler.validate(id); err != nil {
		return TurnSkillRule{}, err
	}
	data := compiler.definitions[id].data
	power, err := ruleInteger(data["power"], id+".power", 1)
	if err != nil {
		return TurnSkillRule{}, fmt.Errorf("build content rules: %w", err)
	}
	return TurnSkillRule{
		ID:      id,
		Name:    ruleOptionalString(data, "name"),
		NameKey: ruleOptionalString(data, "name_key"),
		Effect:  ruleOptionalString(data, "effect"),
		Target:  ruleOptionalString(data, "target"),
		Power:   power,
	}, nil
}

func (compiler *contentRuleCompiler) compileTurnBattler(
	actorID string,
) (ActorTurnBattlerRule, bool, error) {
	data := compiler.definitions[actorID].data
	components, _ := data["components"].(map[string]any)
	raw, exists := components["rpg.turn_battler"]
	if !exists {
		return ActorTurnBattlerRule{}, false, nil
	}
	if err := compiler.validate(actorID); err != nil {
		return ActorTurnBattlerRule{}, false, err
	}
	path := actorID + ".components.rpg.turn_battler"
	battler, err := requiredObject(raw, path)
	if err != nil {
		return ActorTurnBattlerRule{}, false, fmt.Errorf(
			"build content rules: %w",
			err,
		)
	}
	rawSkills, err := requiredArray(battler["skills"], path+".skills")
	if err != nil {
		return ActorTurnBattlerRule{}, false, fmt.Errorf(
			"build content rules: %w",
			err,
		)
	}
	skills := make([]string, 0, len(rawSkills))
	for index, raw := range rawSkills {
		skillID, err := requiredString(
			raw,
			fmt.Sprintf("%s.skills[%d]", path, index),
		)
		if err != nil {
			return ActorTurnBattlerRule{}, false, fmt.Errorf(
				"build content rules: %w",
				err,
			)
		}
		skills = append(skills, skillID)
	}
	return ActorTurnBattlerRule{
		ActorID: actorID,
		Skills:  skills,
	}, true, nil
}

func (compiler *contentRuleCompiler) compileTurnBattle(
	id string,
) (TurnBattleRule, error) {
	if err := compiler.validate(id); err != nil {
		return TurnBattleRule{}, err
	}
	data := compiler.definitions[id].data
	rawEnemies, err := requiredArray(data["enemies"], id+".enemies")
	if err != nil {
		return TurnBattleRule{}, fmt.Errorf("build content rules: %w", err)
	}
	enemies := make([]TurnBattleEnemyRule, 0, len(rawEnemies))
	for index, raw := range rawEnemies {
		path := fmt.Sprintf("%s.enemies[%d]", id, index)
		entry, err := requiredObject(raw, path)
		if err != nil {
			return TurnBattleRule{}, fmt.Errorf("build content rules: %w", err)
		}
		enemyID, err := requiredString(entry["id"], path+".id")
		if err != nil {
			return TurnBattleRule{}, fmt.Errorf("build content rules: %w", err)
		}
		actorID, err := requiredString(entry["actor"], path+".actor")
		if err != nil {
			return TurnBattleRule{}, fmt.Errorf("build content rules: %w", err)
		}
		actor := compiler.definitions[actorID].data
		components, _ := actor["components"].(map[string]any)
		health, _ := components["action.health"].(map[string]any)
		stats, _ := components["rpg.stats"].(map[string]any)
		battler, _ := components["rpg.turn_battler"].(map[string]any)
		maxHealth, err := ruleInteger(
			health["max"],
			path+".actor.action.health.max",
			1,
		)
		if err != nil {
			return TurnBattleRule{}, fmt.Errorf("build content rules: %w", err)
		}
		attack, err := optionalTurnBattleStat(
			stats["attack"],
			path+".actor.rpg.stats.attack",
		)
		if err != nil {
			return TurnBattleRule{}, err
		}
		defense, err := optionalTurnBattleStat(
			stats["defense"],
			path+".actor.rpg.stats.defense",
		)
		if err != nil {
			return TurnBattleRule{}, err
		}
		rawSkills, _ := battler["skills"].([]any)
		skills := make([]string, 0, len(rawSkills))
		for _, rawSkill := range rawSkills {
			skillID, _ := rawSkill.(string)
			skills = append(skills, skillID)
		}
		enemies = append(enemies, TurnBattleEnemyRule{
			ID:        enemyID,
			ActorID:   actorID,
			Name:      ruleOptionalString(actor, "name"),
			MaxHealth: maxHealth,
			Attack:    attack,
			Defense:   defense,
			Skills:    skills,
		})
	}
	onStart, err := compiler.compileOptionalActions(
		data["on_start"],
		id+".on_start",
	)
	if err != nil {
		return TurnBattleRule{}, err
	}
	onVictory, err := compiler.compileOptionalActions(
		data["on_victory"],
		id+".on_victory",
	)
	if err != nil {
		return TurnBattleRule{}, err
	}
	onEscape, err := compiler.compileOptionalActions(
		data["on_escape"],
		id+".on_escape",
	)
	if err != nil {
		return TurnBattleRule{}, err
	}
	onDefeat, err := compiler.compileOptionalActions(
		data["on_defeat"],
		id+".on_defeat",
	)
	if err != nil {
		return TurnBattleRule{}, err
	}
	allowEscape, err := ruleOptionalBool(
		data,
		"allow_escape",
		id+".allow_escape",
	)
	if err != nil {
		return TurnBattleRule{}, fmt.Errorf("build content rules: %w", err)
	}
	repeatable, err := ruleOptionalBool(
		data,
		"repeatable",
		id+".repeatable",
	)
	if err != nil {
		return TurnBattleRule{}, fmt.Errorf("build content rules: %w", err)
	}
	return TurnBattleRule{
		ID:          id,
		Name:        ruleOptionalString(data, "name"),
		NameKey:     ruleOptionalString(data, "name_key"),
		AllowEscape: allowEscape,
		Repeatable:  repeatable,
		Enemies:     enemies,
		OnStart:     onStart,
		OnVictory:   onVictory,
		OnEscape:    onEscape,
		OnDefeat:    onDefeat,
	}, nil
}

func optionalTurnBattleStat(value any, path string) (int, error) {
	if value == nil {
		return 0, nil
	}
	result, err := ruleInteger(value, path, 0)
	if err != nil {
		return 0, fmt.Errorf("build content rules: %w", err)
	}
	return result, nil
}

func cloneTurnBattleRule(rule TurnBattleRule) TurnBattleRule {
	result := rule
	result.Enemies = make([]TurnBattleEnemyRule, len(rule.Enemies))
	for index, enemy := range rule.Enemies {
		result.Enemies[index] = enemy
		result.Enemies[index].Skills = append([]string(nil), enemy.Skills...)
	}
	result.OnStart = cloneRuleActions(rule.OnStart)
	result.OnVictory = cloneRuleActions(rule.OnVictory)
	result.OnEscape = cloneRuleActions(rule.OnEscape)
	result.OnDefeat = cloneRuleActions(rule.OnDefeat)
	return result
}
