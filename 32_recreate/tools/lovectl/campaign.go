package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

type campaignScenario struct {
	SchemaVersion int    `json:"schema_version"`
	Project       string `json:"project"`
	Profile       string `json:"profile"`
	SaveSlot      string `json:"save_slot"`
	Stages        struct {
		Village string `json:"village"`
		Field   string `json:"field"`
		Grove   string `json:"grove"`
	} `json:"stages"`
	Entities struct {
		Guide        string   `json:"guide"`
		Merchant     string   `json:"merchant"`
		FieldEnemies []string `json:"field_enemies"`
		Guardian     string   `json:"guardian"`
	} `json:"entities"`
	Content struct {
		Quest     string `json:"quest"`
		Equipment string `json:"equipment"`
		Potion    string `json:"potion"`
	} `json:"content"`
	EquipmentSlot string `json:"equipment_slot"`
}

type campaignReport struct {
	Project string `json:"project"`
	Profile string `json:"profile"`
	Flow    struct {
		Title     bool `json:"title"`
		Started   bool `json:"started"`
		Paused    bool `json:"paused"`
		Continued bool `json:"continued_after_process_restart"`
		GameOver  bool `json:"game_over"`
		Ending    bool `json:"ending"`
	} `json:"flow"`
	Stages struct {
		Village  bool `json:"village"`
		Field    bool `json:"field"`
		Grove    bool `json:"grove"`
		Returned bool `json:"returned_to_village"`
	} `json:"stages"`
	RPG struct {
		QuestStarted   bool   `json:"quest_started"`
		QuestCompleted bool   `json:"quest_completed"`
		QuestStatus    string `json:"quest_status"`
		Equipment      string `json:"equipment"`
		ShopOpened     bool   `json:"shop_opened"`
		PotionBought   bool   `json:"potion_bought"`
		PotionCount    int    `json:"potion_count"`
		Currency       int    `json:"currency"`
	} `json:"rpg"`
	Combat struct {
		FieldKills   int  `json:"field_kills"`
		GuardianKill bool `json:"guardian_kill"`
	} `json:"combat"`
	Save struct {
		Slot             string `json:"slot"`
		Written          bool   `json:"written"`
		FoundAfterBoot   bool   `json:"found_after_boot"`
		ProgressRestored bool   `json:"progress_restored"`
	} `json:"save"`
	FixedFrames int               `json:"fixed_frames"`
	Screenshots map[string]string `json:"screenshots"`
	Log         string            `json:"log"`
}

func validateCampaignScenario(scenario campaignScenario) error {
	if scenario.SchemaVersion != 1 {
		return fmt.Errorf(
			"campaign scenario schema_version must be 1, got %d",
			scenario.SchemaVersion,
		)
	}
	if scenario.Profile != "action-rpg" {
		return errors.New(
			"campaign scenario profile must be action-rpg",
		)
	}
	required := []struct {
		Path  string
		Value string
	}{
		{"project", scenario.Project},
		{"save_slot", scenario.SaveSlot},
		{"stages.village", scenario.Stages.Village},
		{"stages.field", scenario.Stages.Field},
		{"stages.grove", scenario.Stages.Grove},
		{"entities.guide", scenario.Entities.Guide},
		{"entities.merchant", scenario.Entities.Merchant},
		{"entities.guardian", scenario.Entities.Guardian},
		{"content.quest", scenario.Content.Quest},
		{"content.equipment", scenario.Content.Equipment},
		{"content.potion", scenario.Content.Potion},
		{"equipment_slot", scenario.EquipmentSlot},
	}
	for _, field := range required {
		if field.Value == "" {
			return fmt.Errorf(
				"campaign scenario field %s is required",
				field.Path,
			)
		}
	}
	if len(scenario.Entities.FieldEnemies) != 2 {
		return errors.New(
			"campaign scenario entities.field_enemies requires two IDs",
		)
	}
	for index, id := range scenario.Entities.FieldEnemies {
		if id == "" {
			return fmt.Errorf(
				"campaign scenario entities.field_enemies[%d] is required",
				index,
			)
		}
	}
	return nil
}

func loadCampaignScenario(
	projectPath string,
	argument string,
) (campaignScenario, error) {
	var scenario campaignScenario
	path := argument
	if path == "" {
		path = filepath.Join(
			projectPath,
			"game",
			"tests",
			"campaign.json",
		)
	} else if !filepath.IsAbs(path) {
		path = filepath.Join(projectPath, path)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return scenario, fmt.Errorf(
			"read campaign scenario %s: %w",
			path,
			err,
		)
	}
	if err := decodeStrictJSON(data, &scenario); err != nil {
		return scenario, fmt.Errorf(
			"decode campaign scenario %s: %w",
			path,
			err,
		)
	}
	if err := validateCampaignScenario(scenario); err != nil {
		return scenario, fmt.Errorf("%s: %w", path, err)
	}
	return scenario, nil
}

func campaignSnapshot(
	client *protocolClient,
) (worldSnapshot, error) {
	var snapshot worldSnapshot
	if err := client.call(
		"World.getSnapshot",
		nil,
		&snapshot,
	); err != nil {
		return snapshot, err
	}
	if !snapshot.Available {
		return snapshot, errors.New("semantic world is unavailable")
	}
	return snapshot, nil
}

func campaignInput(
	client *protocolClient,
	action string,
	inputFrames int,
	waitFrames int,
	steps *int,
) error {
	var result map[string]any
	if err := client.call(
		"Input.action",
		map[string]any{
			"action": action,
			"value":  1,
			"frames": inputFrames,
		},
		&result,
	); err != nil {
		return err
	}
	if waitFrames < inputFrames {
		waitFrames = inputFrames
	}
	if err := requestAndWaitSteps(
		client,
		*steps,
		waitFrames,
	); err != nil {
		return err
	}
	*steps += waitFrames
	return nil
}

func campaignCapture(
	client *protocolClient,
	artifacts string,
	name string,
	report *campaignReport,
) error {
	path := filepath.Join(artifacts, name+".png")
	if err := captureScreenshot(client, path); err != nil {
		return err
	}
	report.Screenshots[name] = path
	return nil
}

func campaignPosition(
	client *protocolClient,
	entityID string,
	x float64,
	y float64,
) (entityState, error) {
	var entity entityState
	err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": entityID,
			"x":        x,
			"y":        y,
		},
		&entity,
	)
	return entity, err
}

func campaignKillWithAttack(
	client *protocolClient,
	playerID string,
	targetID string,
	steps *int,
) error {
	var player entityState
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": playerID},
		&player,
	); err != nil {
		return err
	}
	var target entityState
	if err := client.call(
		"Entity.setHealth",
		map[string]any{
			"entityId": targetID,
			"value":    1,
		},
		&target,
	); err != nil {
		return err
	}
	if _, err := campaignPosition(
		client,
		targetID,
		player.X+42,
		player.Y,
	); err != nil {
		return err
	}
	if err := campaignInput(
		client,
		"attack",
		1,
		40,
		steps,
	); err != nil {
		return err
	}
	var removed entityState
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": targetID},
		&removed,
	); err == nil {
		return fmt.Errorf(
			"campaign target %q survived the attack with %.2f health",
			targetID,
			removed.Health,
		)
	}
	return nil
}

func campaignQuest(
	snapshot worldSnapshot,
	questID string,
) (questState, error) {
	return questByID(snapshot.Quests, questID)
}

func stopCampaignProcess(
	client *protocolClient,
	process *loveProcess,
) error {
	var result map[string]any
	if err := client.call("App.quit", nil, &result); err != nil {
		return err
	}
	select {
	case waitError := <-process.done:
		process.command = nil
		if waitError != nil {
			return fmt.Errorf("LÖVE exited unsuccessfully: %w", waitError)
		}
		return nil
	case <-time.After(10 * time.Second):
		return errors.New("LÖVE did not quit within 10s")
	}
}

func executeCampaignOpening(
	client *protocolClient,
	artifacts string,
	scenario campaignScenario,
	report *campaignReport,
) (int, error) {
	state, err := pauseSimulation(client)
	if err != nil {
		return 0, err
	}
	if state.Project != scenario.Project ||
		state.Profile != scenario.Profile {
		return 0, fmt.Errorf(
			"campaign runtime mismatch: %#v",
			state,
		)
	}
	steps := state.Simulation.SteppedFrames
	snapshot, err := campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	report.Flow.Title =
		snapshot.GameFlow.Mode == "title" &&
			!snapshot.GameFlow.Started
	if !report.Flow.Title {
		return 0, fmt.Errorf(
			"campaign did not open on title: %#v",
			snapshot.GameFlow,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_title",
		report,
	); err != nil {
		return 0, err
	}

	if err := campaignInput(
		client,
		"menu_confirm",
		1,
		1,
		&steps,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	report.Flow.Started =
		snapshot.GameFlow.Mode == "playing" &&
			snapshot.GameFlow.Started
	report.Stages.Village = snapshot.Stage.ID == scenario.Stages.Village
	if !report.Flow.Started || !report.Stages.Village {
		return 0, fmt.Errorf(
			"new game did not enter the village: flow=%#v stage=%s",
			snapshot.GameFlow,
			snapshot.Stage.ID,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_village",
		report,
	); err != nil {
		return 0, err
	}

	player, err := entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return 0, err
	}
	var guide entityState
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": scenario.Entities.Guide},
		&guide,
	); err != nil {
		return 0, err
	}
	if _, err := campaignPosition(
		client,
		player.ID,
		guide.X-30,
		guide.Y,
	); err != nil {
		return 0, err
	}
	if err := campaignInput(
		client,
		"interact",
		1,
		2,
		&steps,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	if !snapshot.Dialogue.Active ||
		snapshot.Dialogue.DialogueID != "dialogue.village_guide" {
		return 0, fmt.Errorf(
			"village guide dialogue did not open: %#v",
			snapshot.Dialogue,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_quest_offer",
		report,
	); err != nil {
		return 0, err
	}
	if err := campaignInput(
		client,
		"menu_confirm",
		1,
		2,
		&steps,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	quest, questErr := campaignQuest(snapshot, scenario.Content.Quest)
	player, playerErr := entityWithTag(snapshot.Entities, "player")
	if questErr != nil || playerErr != nil {
		return 0, fmt.Errorf(
			"campaign quest start snapshot is incomplete: quest=%v player=%v",
			questErr,
			playerErr,
		)
	}
	report.RPG.QuestStarted = quest.Status == "active"
	report.RPG.Equipment = equippedItem(
		player,
		scenario.EquipmentSlot,
	)
	if !report.RPG.QuestStarted ||
		report.RPG.Equipment != scenario.Content.Equipment ||
		snapshot.Currency.Balance != 25 {
		return 0, fmt.Errorf(
			"campaign quest start failed: quest=%#v player=%#v currency=%d",
			quest,
			player,
			snapshot.Currency.Balance,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_quest_started",
		report,
	); err != nil {
		return 0, err
	}
	if err := campaignInput(
		client,
		"menu_confirm",
		1,
		2,
		&steps,
	); err != nil {
		return 0, err
	}

	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	player, err = entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return 0, err
	}
	var merchant entityState
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": scenario.Entities.Merchant},
		&merchant,
	); err != nil {
		return 0, err
	}
	if _, err := campaignPosition(
		client,
		player.ID,
		merchant.X-30,
		merchant.Y,
	); err != nil {
		return 0, err
	}
	if err := campaignInput(
		client,
		"interact",
		1,
		2,
		&steps,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	report.RPG.ShopOpened =
		snapshot.Shop.Active &&
			snapshot.Shop.ShopID == "shop.village"
	if !report.RPG.ShopOpened {
		return 0, fmt.Errorf(
			"campaign shop did not open: %#v",
			snapshot.Shop,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_shop",
		report,
	); err != nil {
		return 0, err
	}
	if err := campaignInput(
		client,
		"menu_confirm",
		1,
		2,
		&steps,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	report.RPG.PotionBought =
		snapshot.Currency.Balance == 0 &&
			inventoryCount(
				snapshot.Inventory,
				scenario.Content.Potion,
			) == 1
	if !report.RPG.PotionBought {
		return 0, fmt.Errorf(
			"campaign purchase failed: currency=%d inventory=%#v",
			snapshot.Currency.Balance,
			snapshot.Inventory,
		)
	}
	if err := campaignInput(
		client,
		"menu_cancel",
		1,
		2,
		&steps,
	); err != nil {
		return 0, err
	}

	if err := campaignInput(
		client,
		"pause",
		1,
		1,
		&steps,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	report.Flow.Paused = snapshot.GameFlow.Mode == "paused"
	if !report.Flow.Paused {
		return 0, fmt.Errorf(
			"campaign pause menu did not open: %#v",
			snapshot.GameFlow,
		)
	}
	if err := campaignInput(
		client,
		"menu_down",
		1,
		1,
		&steps,
	); err != nil {
		return 0, err
	}
	if err := campaignInput(
		client,
		"menu_confirm",
		1,
		1,
		&steps,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	report.Save.Slot = scenario.SaveSlot
	report.Save.Written =
		snapshot.GameFlow.HasSave &&
			snapshot.GameFlow.Notice == "saved"
	if !report.Save.Written {
		return 0, fmt.Errorf(
			"campaign save was not written: %#v",
			snapshot.GameFlow,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_saved",
		report,
	); err != nil {
		return 0, err
	}
	return steps - state.Simulation.SteppedFrames, nil
}

func executeCampaignCompletion(
	client *protocolClient,
	artifacts string,
	scenario campaignScenario,
	report *campaignReport,
) (int, error) {
	state, err := pauseSimulation(client)
	if err != nil {
		return 0, err
	}
	steps := state.Simulation.SteppedFrames
	snapshot, err := campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	report.Save.FoundAfterBoot =
		snapshot.GameFlow.Mode == "title" &&
			snapshot.GameFlow.HasSave
	if !report.Save.FoundAfterBoot {
		return 0, fmt.Errorf(
			"campaign save was not found after restart: %#v",
			snapshot.GameFlow,
		)
	}
	if err := campaignInput(
		client,
		"menu_down",
		1,
		1,
		&steps,
	); err != nil {
		return 0, err
	}
	if err := campaignInput(
		client,
		"menu_confirm",
		1,
		1,
		&steps,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	quest, questErr := campaignQuest(snapshot, scenario.Content.Quest)
	player, playerErr := entityWithTag(snapshot.Entities, "player")
	report.Flow.Continued =
		snapshot.GameFlow.Mode == "playing" &&
			snapshot.Stage.ID == scenario.Stages.Village
	report.Save.ProgressRestored =
		questErr == nil &&
			quest.Status == "active" &&
			playerErr == nil &&
			equippedItem(
				player,
				scenario.EquipmentSlot,
			) == scenario.Content.Equipment &&
			inventoryCount(
				snapshot.Inventory,
				scenario.Content.Potion,
			) == 1 &&
			snapshot.Currency.Balance == 0
	if !report.Flow.Continued || !report.Save.ProgressRestored {
		return 0, fmt.Errorf(
			"campaign continue did not restore progress: flow=%#v "+
				"quest=%#v player=%#v inventory=%#v currency=%d",
			snapshot.GameFlow,
			quest,
			player,
			snapshot.Inventory,
			snapshot.Currency.Balance,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_continued",
		report,
	); err != nil {
		return 0, err
	}

	if _, err := campaignPosition(
		client,
		player.ID,
		910,
		270,
	); err != nil {
		return 0, err
	}
	if err := campaignInput(
		client,
		"move_right",
		1,
		14,
		&steps,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	report.Stages.Field = snapshot.Stage.ID == scenario.Stages.Field
	if !report.Stages.Field {
		return 0, fmt.Errorf(
			"campaign portal did not enter field: %s",
			snapshot.Stage.ID,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_field",
		report,
	); err != nil {
		return 0, err
	}
	player, err = entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return 0, err
	}
	for _, enemyID := range scenario.Entities.FieldEnemies {
		if err := campaignKillWithAttack(
			client,
			player.ID,
			enemyID,
			&steps,
		); err != nil {
			return 0, err
		}
		report.Combat.FieldKills++
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	quest, questErr = campaignQuest(snapshot, scenario.Content.Quest)
	if questErr != nil ||
		len(quest.Objectives) != 2 ||
		quest.Objectives[0].Count != 2 ||
		quest.Status != "active" {
		return 0, fmt.Errorf(
			"field kills did not advance campaign quest: %#v (%v)",
			quest,
			questErr,
		)
	}

	player, err = entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return 0, err
	}
	if _, err := campaignPosition(
		client,
		player.ID,
		1072,
		288,
	); err != nil {
		return 0, err
	}
	if err := campaignInput(
		client,
		"move_right",
		1,
		14,
		&steps,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	report.Stages.Grove = snapshot.Stage.ID == scenario.Stages.Grove
	if !report.Stages.Grove {
		return 0, fmt.Errorf(
			"campaign portal did not enter grove: %s",
			snapshot.Stage.ID,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_guardian",
		report,
	); err != nil {
		return 0, err
	}
	player, err = entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return 0, err
	}
	if err := campaignKillWithAttack(
		client,
		player.ID,
		scenario.Entities.Guardian,
		&steps,
	); err != nil {
		return 0, err
	}
	report.Combat.GuardianKill = true
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	quest, questErr = campaignQuest(snapshot, scenario.Content.Quest)
	report.RPG.QuestCompleted =
		questErr == nil && quest.Status == "completed"
	report.RPG.QuestStatus = quest.Status
	report.RPG.Currency = snapshot.Currency.Balance
	report.RPG.PotionCount = inventoryCount(
		snapshot.Inventory,
		scenario.Content.Potion,
	)
	if !report.RPG.QuestCompleted ||
		report.RPG.Currency != 75 ||
		report.RPG.PotionCount != 2 {
		return 0, fmt.Errorf(
			"guardian defeat did not complete rewards: quest=%#v "+
				"currency=%d inventory=%#v",
			quest,
			snapshot.Currency.Balance,
			snapshot.Inventory,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_guardian_defeated",
		report,
	); err != nil {
		return 0, err
	}

	player, err = entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return 0, err
	}
	var healed entityState
	if err := client.call(
		"Entity.setHealth",
		map[string]any{
			"entityId": player.ID,
			"value":    100,
		},
		&healed,
	); err != nil {
		return 0, err
	}
	if _, err := campaignPosition(
		client,
		player.ID,
		16,
		288,
	); err != nil {
		return 0, err
	}
	if err := campaignInput(
		client,
		"move_left",
		1,
		14,
		&steps,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	if snapshot.Stage.ID != scenario.Stages.Field {
		return 0, fmt.Errorf(
			"campaign did not return to field: %s",
			snapshot.Stage.ID,
		)
	}
	player, err = entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return 0, err
	}
	if _, err := campaignPosition(
		client,
		player.ID,
		16,
		288,
	); err != nil {
		return 0, err
	}
	if err := campaignInput(
		client,
		"move_left",
		1,
		14,
		&steps,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	report.Stages.Returned =
		snapshot.Stage.ID == scenario.Stages.Village
	if !report.Stages.Returned {
		return 0, fmt.Errorf(
			"campaign did not return to village: %s",
			snapshot.Stage.ID,
		)
	}
	player, err = entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return 0, err
	}
	var guide entityState
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": scenario.Entities.Guide},
		&guide,
	); err != nil {
		return 0, err
	}
	if _, err := campaignPosition(
		client,
		player.ID,
		guide.X-30,
		guide.Y,
	); err != nil {
		return 0, err
	}
	if err := campaignInput(
		client,
		"interact",
		1,
		2,
		&steps,
	); err != nil {
		return 0, err
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_return",
		report,
	); err != nil {
		return 0, err
	}
	if err := campaignInput(
		client,
		"menu_confirm",
		1,
		2,
		&steps,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	report.Flow.Ending =
		snapshot.GameFlow.Mode == "ending" &&
			snapshot.GameFlow.Completed
	if !report.Flow.Ending {
		return 0, fmt.Errorf(
			"campaign final report did not reach ending: flow=%#v "+
				"dialogue=%#v",
			snapshot.GameFlow,
			snapshot.Dialogue,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_ending",
		report,
	); err != nil {
		return 0, err
	}

	var runtime runtimeState
	if err := client.call(
		"App.startNewGame",
		map[string]any{"stageId": scenario.Stages.Village},
		&runtime,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	player, err = entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return 0, err
	}
	var defeated entityState
	if err := client.call(
		"Entity.setHealth",
		map[string]any{
			"entityId": player.ID,
			"value":    0,
		},
		&defeated,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	report.Flow.GameOver = snapshot.GameFlow.Mode == "gameover"
	if !report.Flow.GameOver {
		return 0, fmt.Errorf(
			"player death did not open gameover: %#v",
			snapshot.GameFlow,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_gameover",
		report,
	); err != nil {
		return 0, err
	}
	return steps - state.Simulation.SteppedFrames, nil
}

func runCampaignTest(
	options globalOptions,
	projectPath string,
	arguments []string,
) error {
	flags := flag.NewFlagSet("campaign", flag.ContinueOnError)
	artifactArgument := flags.String(
		"artifacts",
		"",
		"directory for campaign screenshots, report, and log",
	)
	scenarioArgument := flags.String(
		"scenario",
		"",
		"project-relative campaign scenario JSON",
	)
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if len(flags.Args()) != 0 {
		return errors.New(
			"usage: lovectl campaign [--artifacts PATH] " +
				"[--scenario FILE]",
		)
	}
	scenario, err := loadCampaignScenario(
		projectPath,
		*scenarioArgument,
	)
	if err != nil {
		return err
	}
	artifacts, err := prepareArtifacts(*artifactArgument)
	if err != nil {
		return err
	}
	runtimeDirectory, err :=
		os.MkdirTemp("", "recreate_campaign_runtime_")
	if err != nil {
		return err
	}
	defer os.RemoveAll(runtimeDirectory)
	logPath := filepath.Join(artifacts, "campaign-love.log")
	logFile, err := os.Create(logPath)
	if err != nil {
		return err
	}
	defer logFile.Close()

	report := campaignReport{
		Project:     scenario.Project,
		Profile:     scenario.Profile,
		Screenshots: map[string]string{},
		Log:         logPath,
	}
	launch := func() (
		*loveProcess,
		*protocolClient,
		error,
	) {
		port, portErr := availablePort()
		if portErr != nil {
			return nil, nil, portErr
		}
		process, startErr := startLove(
			options.lovePath,
			projectPath,
			port,
			logFile,
			runtimeDirectory,
		)
		if startErr != nil {
			return nil, nil, startErr
		}
		client := newProtocolClient(
			"127.0.0.1",
			port,
			20*time.Second,
		)
		if waitErr := waitForBridge(
			client,
			process,
			20*time.Second,
		); waitErr != nil {
			forceStop(process)
			return nil, nil, waitErr
		}
		return process, client, nil
	}

	firstProcess, firstClient, err := launch()
	if err != nil {
		return visualFailure(err, logPath)
	}
	firstStopped := false
	defer func() {
		if !firstStopped {
			forceStop(firstProcess)
		}
	}()
	openingFrames, err := executeCampaignOpening(
		firstClient,
		artifacts,
		scenario,
		&report,
	)
	if err != nil {
		return visualFailure(err, logPath)
	}
	if err := stopCampaignProcess(
		firstClient,
		firstProcess,
	); err != nil {
		return visualFailure(err, logPath)
	}
	firstStopped = true

	secondProcess, secondClient, err := launch()
	if err != nil {
		return visualFailure(err, logPath)
	}
	secondStopped := false
	defer func() {
		if !secondStopped {
			forceStop(secondProcess)
		}
	}()
	completionFrames, err := executeCampaignCompletion(
		secondClient,
		artifacts,
		scenario,
		&report,
	)
	if err != nil {
		return visualFailure(err, logPath)
	}
	if err := stopCampaignProcess(
		secondClient,
		secondProcess,
	); err != nil {
		return visualFailure(err, logPath)
	}
	secondStopped = true

	report.FixedFrames = openingFrames + completionFrames
	reportPath := filepath.Join(artifacts, "campaign-report.json")
	encoded, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return err
	}
	encoded = append(encoded, '\n')
	if err := os.WriteFile(reportPath, encoded, 0o644); err != nil {
		return err
	}
	fmt.Printf(
		"Campaign passed: %s\n"+
			"  title → quest → shop → save/restart/continue → "+
			"field → guardian → return → ending\n"+
			"  %d fixed ticks, report %s\n",
		scenario.Project,
		report.FixedFrames,
		reportPath,
	)
	return nil
}
