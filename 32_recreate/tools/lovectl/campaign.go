package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"math"
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
		Home    string `json:"home"`
		Shop    string `json:"shop"`
		Field   string `json:"field"`
		Grove   string `json:"grove"`
	} `json:"stages"`
	Entities struct {
		Guide        string   `json:"guide"`
		Merchant     string   `json:"merchant"`
		FieldEnemies []string `json:"field_enemies"`
		WorldItem    string   `json:"world_item"`
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
		Home     bool `json:"home"`
		Shop     bool `json:"shop"`
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
		Rested         bool   `json:"rested"`
		PotionCount    int    `json:"potion_count"`
		Currency       int    `json:"currency"`
	} `json:"rpg"`
	Combat struct {
		PerfectParry bool `json:"perfect_parry"`
		ParryShake   bool `json:"parry_camera_shake"`
		FieldKills   int  `json:"field_kills"`
		GuardianKill bool `json:"guardian_kill"`
	} `json:"combat"`
	Environment struct {
		WorldItemCollected bool `json:"world_item_collected"`
		WorldItemOneShot   bool `json:"world_item_one_shot"`
		HazardDamage       int  `json:"hazard_damage"`
	} `json:"environment"`
	Input struct {
		Mode    string `json:"mode"`
		Gamepad bool   `json:"gamepad"`
	} `json:"input"`
	Accessibility struct {
		Configured     bool   `json:"configured"`
		Persisted      bool   `json:"persisted_after_process_restart"`
		Motion         string `json:"motion"`
		HitFlash       bool   `json:"hit_flash"`
		NoticeDuration string `json:"notice_duration"`
	} `json:"accessibility"`
	Presentation struct {
		IntroCutscene   bool `json:"intro_cutscene"`
		IntroNotice     bool `json:"intro_notice"`
		QuestNotice     bool `json:"quest_notice"`
		PurchaseMessage bool `json:"purchase_message"`
		RestNotice      bool `json:"rest_notice"`
		FieldNotice     bool `json:"field_notice"`
		GroveNotice     bool `json:"grove_notice"`
		RewardNotice    bool `json:"reward_notice"`
	} `json:"presentation"`
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
		{"stages.home", scenario.Stages.Home},
		{"stages.shop", scenario.Stages.Shop},
		{"stages.field", scenario.Stages.Field},
		{"stages.grove", scenario.Stages.Grove},
		{"entities.guide", scenario.Entities.Guide},
		{"entities.merchant", scenario.Entities.Merchant},
		{"entities.world_item", scenario.Entities.WorldItem},
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
	method := "Input.action"
	params := map[string]any{
		"action": action,
		"value":  1,
		"frames": inputFrames,
	}
	if client.inputMode == "gamepad" {
		buttons := map[string]string{
			"move_up":      "dpup",
			"move_down":    "dpdown",
			"move_left":    "dpleft",
			"move_right":   "dpright",
			"attack":       "x",
			"special":      "y",
			"technique":    "rightshoulder",
			"jump":         "a",
			"parry":        "leftshoulder",
			"dodge":        "b",
			"interact":     "x",
			"menu_up":      "dpup",
			"menu_down":    "dpdown",
			"menu_left":    "dpleft",
			"menu_right":   "dpright",
			"menu_confirm": "a",
			"menu_cancel":  "b",
			"pause":        "start",
			"restart":      "back",
		}
		button := buttons[action]
		if button == "" {
			return fmt.Errorf(
				"campaign action %q has no gamepad binding",
				action,
			)
		}
		method = "Input.gamepad"
		params = map[string]any{
			"button": button,
			"frames": inputFrames,
		}
	}
	if err := client.call(
		method,
		params,
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

func campaignPortalCenter(
	snapshot worldSnapshot,
	portalID string,
) (float64, float64, error) {
	for _, portal := range snapshot.Navigation.Portals {
		if portal.ID != portalID {
			continue
		}
		return campaignShapeCenter(
			"portal "+portalID,
			portal.Shape,
		)
	}
	return 0, 0, fmt.Errorf(
		"campaign stage %q has no portal %q",
		snapshot.Stage.ID,
		portalID,
	)
}

func campaignTriggerCenter(
	snapshot worldSnapshot,
	triggerID string,
) (float64, float64, error) {
	for _, trigger := range snapshot.Navigation.Triggers {
		if trigger.ID == triggerID {
			return campaignShapeCenter(
				"trigger "+triggerID,
				trigger.Shape,
			)
		}
	}
	return 0, 0, fmt.Errorf(
		"campaign stage %q has no trigger %q",
		snapshot.Stage.ID,
		triggerID,
	)
}

func campaignShapeCenter(
	label string,
	shape navigationShapeState,
) (float64, float64, error) {
	switch shape.Type {
	case "rectangle":
		if !finiteNumber(shape.X) ||
			!finiteNumber(shape.Y) ||
			!finiteNumber(shape.Width) ||
			!finiteNumber(shape.Height) ||
			shape.Width <= 0 ||
			shape.Height <= 0 {
			return 0, 0, fmt.Errorf(
				"campaign %s has invalid rectangle %#v",
				label,
				shape,
			)
		}
		return shape.X, shape.Y, nil
	case "polygon":
		if len(shape.Points) < 3 {
			return 0, 0, fmt.Errorf(
				"campaign %s has invalid polygon %#v",
				label,
				shape.Points,
			)
		}
		var x, y float64
		for _, point := range shape.Points {
			if !finiteNumber(point.X) || !finiteNumber(point.Y) {
				return 0, 0, fmt.Errorf(
					"campaign %s has a non-finite point",
					label,
				)
			}
			x += point.X
			y += point.Y
		}
		return x / float64(len(shape.Points)),
			y / float64(len(shape.Points)),
			nil
	default:
		return 0, 0, fmt.Errorf(
			"campaign %s has unsupported shape %q",
			label,
			shape.Type,
		)
	}
}

func campaignEnterPortal(
	client *protocolClient,
	playerID string,
	portalID string,
	steps *int,
) error {
	snapshot, err := campaignSnapshot(client)
	if err != nil {
		return err
	}
	x, y, err := campaignPortalCenter(snapshot, portalID)
	if err != nil {
		return err
	}
	if _, err := campaignPosition(client, playerID, x, y); err != nil {
		return err
	}
	if err := requestAndWaitSteps(client, *steps, 1); err != nil {
		return err
	}
	*steps += 1
	return nil
}

func finiteNumber(value float64) bool {
	return !math.IsNaN(value) && !math.IsInf(value, 0)
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
	var removed entityState
	for attempts := 0; attempts < 3; attempts++ {
		if err := campaignInput(
			client,
			"attack",
			1,
			40,
			steps,
		); err != nil {
			return err
		}
		if err := client.call(
			"Entity.get",
			map[string]any{"entityId": targetID},
			&removed,
		); err != nil {
			return nil
		}
	}
	return fmt.Errorf(
		"campaign target %q survived repeated attacks with %.2f health",
		targetID,
		removed.Health,
	)
}

func campaignPerfectParry(
	client *protocolClient,
	playerID string,
	enemyID string,
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
	healthBefore := player.Health
	if _, err := campaignPosition(
		client,
		enemyID,
		player.X+35,
		player.Y,
	); err != nil {
		return err
	}
	var enemy entityState
	for attempts := 0; attempts < 120; attempts++ {
		if err := requestAndWaitSteps(client, *steps, 1); err != nil {
			return err
		}
		*steps++
		if err := client.call(
			"Entity.get",
			map[string]any{"entityId": enemyID},
			&enemy,
		); err != nil {
			return err
		}
		if enemy.AttackPhase == "windup" {
			break
		}
	}
	if enemy.AttackPhase != "windup" {
		return fmt.Errorf(
			"campaign enemy %q did not enter attack windup: "+
				"phase=%q pattern=%q next=%q",
			enemyID,
			enemy.AttackPhase,
			enemy.AIPattern,
			enemy.AINextAbility,
		)
	}
	if err := stepUntilWindupRemaining(
		client,
		enemyID,
		steps,
		0.07,
	); err != nil {
		return err
	}
	if err := campaignInput(
		client,
		"parry",
		1,
		1,
		steps,
	); err != nil {
		return err
	}

	for attempt := 0; attempt < 10; attempt++ {
		if err := client.call(
			"Entity.get",
			map[string]any{"entityId": playerID},
			&player,
		); err != nil {
			return err
		}
		if err := client.call(
			"Entity.get",
			map[string]any{"entityId": enemyID},
			&enemy,
		); err != nil {
			return err
		}
		if player.ParrySuccessRemaining > 0 {
			if player.Health != healthBefore {
				return fmt.Errorf(
					"campaign parry lost health: %.0f -> %.0f",
					healthBefore,
					player.Health,
				)
			}
			if !player.ParryPerfect ||
				enemy.StaggerRemaining <= 0 {
				return fmt.Errorf(
					"campaign parry feedback is incomplete: "+
						"perfect=%t stagger=%.3f",
					player.ParryPerfect,
					enemy.StaggerRemaining,
				)
			}
			snapshot, err := campaignSnapshot(client)
			if err != nil {
				return err
			}
			minimumMagnitude := 9.0
			if snapshot.Accessibility.Motion == "reduced" {
				minimumMagnitude = 3
			}
			if snapshot.Camera.ShakeRemaining <= 0 ||
				snapshot.Camera.ShakeMagnitude < minimumMagnitude {
				return fmt.Errorf(
					"campaign perfect parry has no camera shake: "+
						"remaining=%.3f magnitude=%.1f",
					snapshot.Camera.ShakeRemaining,
					snapshot.Camera.ShakeMagnitude,
				)
			}
			return nil
		}
		if err := requestAndWaitSteps(client, *steps, 1); err != nil {
			return err
		}
		*steps++
	}
	return errors.New("campaign enemy attack was not parried")
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
	if snapshot.GameFlow.Panel != "accessibility" {
		return 0, fmt.Errorf(
			"campaign accessibility menu did not open: %#v",
			snapshot.GameFlow,
		)
	}
	for _, action := range []string{
		"menu_confirm",
		"menu_down",
		"menu_confirm",
		"menu_down",
		"menu_confirm",
	} {
		if err := campaignInput(
			client,
			action,
			1,
			1,
			&steps,
		); err != nil {
			return 0, err
		}
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	report.Accessibility.Motion = snapshot.Accessibility.Motion
	report.Accessibility.HitFlash = snapshot.Accessibility.HitFlash
	report.Accessibility.NoticeDuration =
		snapshot.Accessibility.NoticeDuration
	report.Accessibility.Configured =
		report.Accessibility.Motion == "reduced" &&
			!report.Accessibility.HitFlash &&
			report.Accessibility.NoticeDuration == "long"
	if !report.Accessibility.Configured {
		return 0, fmt.Errorf(
			"campaign accessibility settings were not applied: %#v",
			snapshot.Accessibility,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_accessibility",
		report,
	); err != nil {
		return 0, err
	}
	if err := campaignInput(
		client,
		"menu_cancel",
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
	var playingRuntime runtimeState
	if err := client.call(
		"Runtime.getState",
		nil,
		&playingRuntime,
	); err != nil {
		return 0, err
	}
	steps = playingRuntime.Simulation.SteppedFrames
	if !snapshot.Notice.Active && !snapshot.Cutscene.Active {
		if err := requestAndWaitSteps(client, steps, 1); err != nil {
			return 0, err
		}
		steps++
		snapshot, err = campaignSnapshot(client)
		if err != nil {
			return 0, err
		}
	}
	report.Presentation.IntroCutscene =
		snapshot.Cutscene.Active &&
			snapshot.Cutscene.StepIndex == 1 &&
			snapshot.Cutscene.StepCount >= 2
	if !report.Presentation.IntroCutscene {
		return 0, fmt.Errorf(
			"new game intro cutscene is missing: %#v",
			snapshot.Cutscene,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_intro_cutscene",
		report,
	); err != nil {
		return 0, err
	}
	for snapshot.Cutscene.Active {
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
	}
	report.Presentation.IntroNotice =
		snapshot.Notice.Active &&
			snapshot.Notice.TextKey == "notice.intro" &&
			snapshot.Notice.Tone == "info"
	if !report.Presentation.IntroNotice {
		return 0, fmt.Errorf(
			"new game intro notice is missing: %#v",
			snapshot.Notice,
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
	report.Presentation.QuestNotice =
		snapshot.Notice.Active &&
			snapshot.Notice.TextKey == "notice.quest.accepted" &&
			snapshot.Notice.Tone == "success"
	if !report.Presentation.QuestNotice {
		return 0, fmt.Errorf(
			"quest acceptance notice is missing: %#v",
			snapshot.Notice,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_quest_notice",
		report,
	); err != nil {
		return 0, err
	}
	player, err = entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return 0, err
	}
	if err := campaignEnterPortal(
		client,
		player.ID,
		"to_shop",
		&steps,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	report.Stages.Shop = snapshot.Stage.ID == scenario.Stages.Shop
	if !report.Stages.Shop {
		return 0, fmt.Errorf(
			"campaign shop portal did not enter the interior: %s",
			snapshot.Stage.ID,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_shop_interior",
		report,
	); err != nil {
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
	report.Presentation.PurchaseMessage = snapshot.Shop.Message != ""
	if !report.Presentation.PurchaseMessage {
		return 0, errors.New(
			"campaign purchase has no visible shop confirmation",
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_shop_purchased",
		report,
	); err != nil {
		return 0, err
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
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	player, err = entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return 0, err
	}
	if err := campaignEnterPortal(
		client,
		player.ID,
		"to_village",
		&steps,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	if snapshot.Stage.ID != scenario.Stages.Village {
		return 0, fmt.Errorf(
			"campaign shop exit did not return to village: %s",
			snapshot.Stage.ID,
		)
	}
	player, err = entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return 0, err
	}
	if err := campaignEnterPortal(
		client,
		player.ID,
		"to_home",
		&steps,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	report.Stages.Home = snapshot.Stage.ID == scenario.Stages.Home
	if !report.Stages.Home {
		return 0, fmt.Errorf(
			"campaign home portal did not enter the interior: %s",
			snapshot.Stage.ID,
		)
	}
	player, err = entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return 0, err
	}
	var injured entityState
	if err := client.call(
		"Entity.setHealth",
		map[string]any{
			"entityId": player.ID,
			"value":    50,
		},
		&injured,
	); err != nil {
		return 0, err
	}
	restX, restY, err := campaignTriggerCenter(snapshot, "rest_area")
	if err != nil {
		return 0, err
	}
	if _, err := campaignPosition(
		client,
		player.ID,
		restX,
		restY,
	); err != nil {
		return 0, err
	}
	if err := requestAndWaitSteps(client, steps, 1); err != nil {
		return 0, err
	}
	steps++
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	player, err = entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return 0, err
	}
	report.RPG.Rested = player.Health == 80
	if !report.RPG.Rested {
		return 0, fmt.Errorf(
			"campaign home rest trigger health = %.2f, want 80",
			player.Health,
		)
	}
	report.Presentation.RestNotice =
		snapshot.Notice.Active &&
			snapshot.Notice.TextKey == "notice.home.rest" &&
			snapshot.Notice.Tone == "success"
	if !report.Presentation.RestNotice {
		return 0, fmt.Errorf(
			"campaign rest notice is missing: %#v",
			snapshot.Notice,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_home",
		report,
	); err != nil {
		return 0, err
	}
	if err := campaignEnterPortal(
		client,
		player.ID,
		"to_village",
		&steps,
	); err != nil {
		return 0, err
	}
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	if snapshot.Stage.ID != scenario.Stages.Village {
		return 0, fmt.Errorf(
			"campaign home exit did not return to village: %s",
			snapshot.Stage.ID,
		)
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
	report.Accessibility.Persisted =
		snapshot.Accessibility.Motion ==
			report.Accessibility.Motion &&
			snapshot.Accessibility.HitFlash ==
				report.Accessibility.HitFlash &&
			snapshot.Accessibility.NoticeDuration ==
				report.Accessibility.NoticeDuration
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
	if !report.Accessibility.Persisted {
		return 0, fmt.Errorf(
			"campaign accessibility settings were not restored: %#v",
			snapshot.Accessibility,
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

	if err := campaignEnterPortal(
		client,
		player.ID,
		"to_field",
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
	if !snapshot.Notice.Active {
		if err := requestAndWaitSteps(client, steps, 1); err != nil {
			return 0, err
		}
		steps++
		snapshot, err = campaignSnapshot(client)
		if err != nil {
			return 0, err
		}
	}
	report.Presentation.FieldNotice =
		snapshot.Notice.Active &&
			snapshot.Notice.TextKey == "notice.field.tutorial" &&
			snapshot.Notice.Tone == "info"
	if !report.Presentation.FieldNotice {
		return 0, fmt.Errorf(
			"campaign field tutorial notice is missing: %#v",
			snapshot.Notice,
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
	worldItem, err := entityByID(
		snapshot.Entities,
		scenario.Entities.WorldItem,
	)
	if err != nil {
		return 0, err
	}
	potionsBefore := inventoryCount(
		snapshot.Inventory,
		scenario.Content.Potion,
	)
	if _, err := campaignPosition(
		client,
		player.ID,
		worldItem.X,
		worldItem.Y,
	); err != nil {
		return 0, err
	}
	if err := campaignInput(
		client,
		"interact",
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
	report.Environment.WorldItemCollected =
		inventoryCount(snapshot.Inventory, scenario.Content.Potion) ==
			potionsBefore+1 &&
			snapshot.Flags["world.field_potion_collected"]
	if !report.Environment.WorldItemCollected {
		return 0, fmt.Errorf(
			"campaign world item was not collected: inventory=%#v flags=%#v",
			snapshot.Inventory,
			snapshot.Flags,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_world_item",
		report,
	); err != nil {
		return 0, err
	}
	if err := campaignInput(
		client,
		"interact",
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
	report.Environment.WorldItemOneShot =
		inventoryCount(snapshot.Inventory, scenario.Content.Potion) ==
			potionsBefore+1 &&
			snapshot.Notice.TextKey == "notice.field_potion.empty"
	if !report.Environment.WorldItemOneShot {
		return 0, fmt.Errorf(
			"campaign world item repeated its reward: inventory=%#v notice=%#v",
			snapshot.Inventory,
			snapshot.Notice,
		)
	}
	hazardX, hazardY, err := campaignTriggerCenter(
		snapshot,
		"toxic_mire",
	)
	if err != nil {
		return 0, err
	}
	player, err = entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return 0, err
	}
	healthBeforeHazard := player.Health
	if _, err := campaignPosition(
		client,
		player.ID,
		hazardX,
		hazardY,
	); err != nil {
		return 0, err
	}
	if err := requestAndWaitSteps(client, steps, 1); err != nil {
		return 0, err
	}
	steps++
	snapshot, err = campaignSnapshot(client)
	if err != nil {
		return 0, err
	}
	player, err = entityWithTag(snapshot.Entities, "player")
	if err != nil {
		return 0, err
	}
	report.Environment.HazardDamage =
		int(healthBeforeHazard - player.Health)
	if report.Environment.HazardDamage != 12 ||
		snapshot.Notice.TextKey != "notice.field.hazard" {
		return 0, fmt.Errorf(
			"campaign hazard mismatch: damage=%d notice=%#v",
			report.Environment.HazardDamage,
			snapshot.Notice,
		)
	}
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_hazard",
		report,
	); err != nil {
		return 0, err
	}
	if err := campaignPerfectParry(
		client,
		player.ID,
		scenario.Entities.FieldEnemies[0],
		&steps,
	); err != nil {
		return 0, err
	}
	report.Combat.PerfectParry = true
	report.Combat.ParryShake = true
	if err := campaignCapture(
		client,
		artifacts,
		"campaign_parry",
		report,
	); err != nil {
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
	if err := campaignEnterPortal(
		client,
		player.ID,
		"to_grove",
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
	if !snapshot.Notice.Active {
		player, err = entityWithTag(snapshot.Entities, "player")
		if err != nil {
			return 0, err
		}
		triggerX, triggerY, triggerErr := campaignTriggerCenter(
			snapshot,
			"grove_discovery",
		)
		if triggerErr != nil {
			return 0, triggerErr
		}
		if _, err := campaignPosition(
			client,
			player.ID,
			triggerX,
			triggerY,
		); err != nil {
			return 0, err
		}
		if err := requestAndWaitSteps(client, steps, 1); err != nil {
			return 0, err
		}
		steps++
		snapshot, err = campaignSnapshot(client)
		if err != nil {
			return 0, err
		}
	}
	report.Presentation.GroveNotice =
		snapshot.Notice.Active &&
			snapshot.Notice.TextKey == "notice.grove.warning" &&
			snapshot.Notice.Tone == "warning"
	if !report.Presentation.GroveNotice {
		return 0, fmt.Errorf(
			"campaign grove warning notice is missing: %#v",
			snapshot.Notice,
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
		report.RPG.PotionCount != 3 {
		return 0, fmt.Errorf(
			"guardian defeat did not complete rewards: quest=%#v "+
				"currency=%d inventory=%#v",
			quest,
			snapshot.Currency.Balance,
			snapshot.Inventory,
		)
	}
	report.Presentation.RewardNotice =
		snapshot.Notice.Active &&
			snapshot.Notice.TextKey == "notice.quest.completed" &&
			snapshot.Notice.Tone == "success"
	if !report.Presentation.RewardNotice {
		return 0, fmt.Errorf(
			"campaign quest reward notice is missing: %#v",
			snapshot.Notice,
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
	if err := campaignEnterPortal(
		client,
		player.ID,
		"to_hub",
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
	if err := campaignEnterPortal(
		client,
		player.ID,
		"to_village",
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
	inputMode := flags.String(
		"input",
		"gamepad",
		"campaign input boundary: gamepad or semantic",
	)
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if len(flags.Args()) != 0 {
		return errors.New(
			"usage: lovectl campaign [--artifacts PATH] " +
				"[--scenario FILE] [--input gamepad|semantic]",
		)
	}
	if *inputMode != "gamepad" && *inputMode != "semantic" {
		return errors.New("--input must be gamepad or semantic")
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
	report.Input.Mode = *inputMode
	report.Input.Gamepad = *inputMode == "gamepad"
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
		client.inputMode = *inputMode
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
			"  title → quest → shop → home/rest → save/restart/continue → "+
			"field → guardian → return → ending\n"+
			"  %d fixed ticks, report %s\n",
		scenario.Project,
		report.FixedFrames,
		reportPath,
	)
	return nil
}
