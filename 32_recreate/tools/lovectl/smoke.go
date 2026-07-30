package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

type smokeMovement struct {
	Action       string  `json:"action"`
	Frames       int     `json:"frames"`
	MinimumDelta float64 `json:"minimum_delta"`
}

type smokeCombat struct {
	TargetTag     string  `json:"target_tag"`
	Action        string  `json:"action"`
	Frames        int     `json:"frames"`
	MinimumDamage float64 `json:"minimum_damage"`
}

type smokeInteraction struct {
	TargetTag        string `json:"target_tag"`
	Action           string `json:"action"`
	Frames           int    `json:"frames"`
	ExpectedFlag     string `json:"expected_flag,omitempty"`
	ExpectedDialogue string `json:"expected_dialogue,omitempty"`
}

type smokePersistence struct {
	Item string `json:"item"`
}

type smokeJourneyStep struct {
	TargetTag string `json:"target_tag,omitempty"`
	Action    string `json:"action,omitempty"`
	Frames    int    `json:"frames"`
	Repeat    int    `json:"repeat,omitempty"`
}

type smokeJourney struct {
	Steps             []smokeJourneyStep `json:"steps"`
	ExpectedFlow      string             `json:"expected_flow"`
	ExpectedQuest     string             `json:"expected_quest,omitempty"`
	ExpectedEncounter string             `json:"expected_encounter,omitempty"`
	ExpectedBattle    string             `json:"expected_battle,omitempty"`
}

type smokeScenario struct {
	SchemaVersion int               `json:"schema_version"`
	Profile       string            `json:"profile"`
	Stage         string            `json:"stage"`
	PlayerTag     string            `json:"player_tag"`
	Movement      smokeMovement     `json:"movement"`
	Combat        *smokeCombat      `json:"combat,omitempty"`
	Interaction   *smokeInteraction `json:"interaction,omitempty"`
	Persistence   *smokePersistence `json:"persistence,omitempty"`
	Journey       *smokeJourney     `json:"journey,omitempty"`
}

type smokeReport struct {
	Project    string  `json:"project"`
	Profile    string  `json:"profile"`
	Stage      string  `json:"stage"`
	PlayerID   string  `json:"player_id"`
	FixedDelta float64 `json:"fixed_dt"`
	Flow       struct {
		InitialMode string   `json:"initial_mode"`
		Options     []string `json:"options"`
		Screenshot  string   `json:"screenshot"`
	} `json:"flow"`
	Movement struct {
		StartX float64 `json:"start_x"`
		EndX   float64 `json:"end_x"`
		Delta  float64 `json:"delta"`
	} `json:"movement"`
	Combat *struct {
		TargetID     string  `json:"target_id"`
		HealthBefore float64 `json:"health_before"`
		HealthAfter  float64 `json:"health_after"`
		Damage       float64 `json:"damage"`
	} `json:"combat,omitempty"`
	Interaction *struct {
		TargetID string `json:"target_id"`
		Flag     string `json:"flag,omitempty"`
		Dialogue string `json:"dialogue,omitempty"`
		Applied  bool   `json:"applied"`
	} `json:"interaction,omitempty"`
	Persistence *struct {
		Item          string `json:"item"`
		SavedCount    int    `json:"saved_count"`
		MutatedCount  int    `json:"mutated_count"`
		RestoredCount int    `json:"restored_count"`
	} `json:"persistence,omitempty"`
	Journey *struct {
		StepCount      int    `json:"step_count"`
		Flow           string `json:"flow"`
		Quest          string `json:"quest,omitempty"`
		QuestState     string `json:"quest_state,omitempty"`
		Encounter      string `json:"encounter,omitempty"`
		EncounterState string `json:"encounter_state,omitempty"`
		Battle         string `json:"battle,omitempty"`
		BattleState    string `json:"battle_state,omitempty"`
		Screenshot     string `json:"screenshot"`
	} `json:"journey,omitempty"`
	SteppedFrames int    `json:"stepped_frames"`
	Screenshot    string `json:"screenshot"`
	Log           string `json:"log"`
}

func decodeStrictJSON(data []byte, target any) error {
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			return errors.New("contains more than one JSON value")
		}
		return fmt.Errorf("trailing JSON: %w", err)
	}
	return nil
}

func validateSmokeScenario(scenario smokeScenario) error {
	if scenario.SchemaVersion != 1 {
		return fmt.Errorf(
			"smoke scenario schema_version must be 1, got %d",
			scenario.SchemaVersion,
		)
	}
	switch scenario.Profile {
	case "rpg", "action-rpg", "action":
	default:
		return errors.New(
			"smoke scenario profile must be rpg, action-rpg, or action",
		)
	}
	required := []struct {
		Path  string
		Value string
	}{
		{"stage", scenario.Stage},
		{"player_tag", scenario.PlayerTag},
		{"movement.action", scenario.Movement.Action},
	}
	for _, field := range required {
		if field.Value == "" {
			return fmt.Errorf(
				"smoke scenario field %s is required",
				field.Path,
			)
		}
	}
	if scenario.Movement.Frames < 1 ||
		scenario.Movement.Frames > 3600 {
		return errors.New(
			"smoke scenario movement.frames must be between 1 and 3600",
		)
	}
	if scenario.Movement.MinimumDelta <= 0 {
		return errors.New(
			"smoke scenario movement.minimum_delta must be positive",
		)
	}

	needsAction := scenario.Profile == "action" ||
		scenario.Profile == "action-rpg"
	if needsAction && scenario.Combat == nil {
		return fmt.Errorf(
			"smoke scenario profile %s requires combat",
			scenario.Profile,
		)
	}
	if scenario.Combat != nil {
		if scenario.Combat.TargetTag == "" ||
			scenario.Combat.Action == "" {
			return errors.New(
				"smoke scenario combat target_tag and action are required",
			)
		}
		if scenario.Combat.Frames < 1 ||
			scenario.Combat.Frames > 3600 {
			return errors.New(
				"smoke scenario combat.frames must be between 1 and 3600",
			)
		}
		if scenario.Combat.MinimumDamage <= 0 {
			return errors.New(
				"smoke scenario combat.minimum_damage must be positive",
			)
		}
	}

	needsRPG := scenario.Profile == "rpg" ||
		scenario.Profile == "action-rpg"
	if needsRPG && scenario.Interaction == nil {
		return fmt.Errorf(
			"smoke scenario profile %s requires interaction",
			scenario.Profile,
		)
	}
	if needsRPG && scenario.Persistence == nil {
		return fmt.Errorf(
			"smoke scenario profile %s requires persistence",
			scenario.Profile,
		)
	}
	if scenario.Interaction != nil {
		if scenario.Interaction.TargetTag == "" ||
			scenario.Interaction.Action == "" {
			return errors.New(
				"smoke scenario interaction target_tag and action " +
					"are required",
			)
		}
		if scenario.Interaction.ExpectedFlag == "" &&
			scenario.Interaction.ExpectedDialogue == "" {
			return errors.New(
				"smoke scenario interaction requires expected_flag " +
					"or expected_dialogue",
			)
		}
		if scenario.Interaction.Frames < 1 ||
			scenario.Interaction.Frames > 3600 {
			return errors.New(
				"smoke scenario interaction.frames must be between 1 and 3600",
			)
		}
	}
	if scenario.Persistence != nil && scenario.Persistence.Item == "" {
		return errors.New(
			"smoke scenario persistence.item is required",
		)
	}
	if scenario.Journey != nil {
		if len(scenario.Journey.Steps) == 0 {
			return errors.New(
				"smoke scenario journey.steps must not be empty",
			)
		}
		switch scenario.Journey.ExpectedFlow {
		case "playing", "gameover", "ending":
		default:
			return errors.New(
				"smoke scenario journey.expected_flow must be " +
					"playing, gameover, or ending",
			)
		}
		for index, step := range scenario.Journey.Steps {
			if step.Action == "" && step.TargetTag != "" {
				return fmt.Errorf(
					"smoke scenario journey.steps[%d] target_tag "+
						"requires action",
					index,
				)
			}
			if step.Frames < 1 || step.Frames > 3600 {
				return fmt.Errorf(
					"smoke scenario journey.steps[%d].frames must "+
						"be between 1 and 3600",
					index,
				)
			}
			if step.Repeat < 0 || step.Repeat > 20 {
				return fmt.Errorf(
					"smoke scenario journey.steps[%d].repeat must "+
						"be between 1 and 20 when present",
					index,
				)
			}
		}
	}
	return nil
}

func loadSmokeScenario(
	projectPath string,
	argument string,
) (smokeScenario, error) {
	var scenario smokeScenario
	path := argument
	if path == "" {
		path = filepath.Join(
			projectPath,
			"game",
			"tests",
			"smoke.json",
		)
	} else if !filepath.IsAbs(path) {
		path = filepath.Join(projectPath, path)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return scenario, fmt.Errorf(
			"read smoke scenario %s: %w",
			path,
			err,
		)
	}
	if err := decodeStrictJSON(data, &scenario); err != nil {
		return scenario, fmt.Errorf(
			"decode smoke scenario %s: %w",
			path,
			err,
		)
	}
	if err := validateSmokeScenario(scenario); err != nil {
		return scenario, fmt.Errorf("%s: %w", path, err)
	}
	return scenario, nil
}

func pauseSimulation(
	client *protocolClient,
) (runtimeState, error) {
	var pauseResult map[string]any
	if err := client.call(
		"Test.setPaused",
		map[string]any{"enabled": true},
		&pauseResult,
	); err != nil {
		return runtimeState{}, err
	}
	var state runtimeState
	if err := client.call("Runtime.getState", nil, &state); err != nil {
		return state, err
	}
	return state, nil
}

func runSmokeMovement(
	client *protocolClient,
	scenario smokeScenario,
	steps *int,
	report *smokeReport,
) (entityState, error) {
	var snapshot worldSnapshot
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return entityState{}, err
	}
	if !snapshot.Available {
		return entityState{}, errors.New("semantic world is unavailable")
	}
	player, err := entityWithTag(snapshot.Entities, scenario.PlayerTag)
	if err != nil {
		return entityState{}, err
	}
	report.PlayerID = player.ID
	report.Movement.StartX = player.X

	var actionResult map[string]any
	if err := client.call(
		"Input.action",
		map[string]any{
			"action": scenario.Movement.Action,
			"value":  1,
			"frames": scenario.Movement.Frames,
		},
		&actionResult,
	); err != nil {
		return entityState{}, err
	}
	if err := requestAndWaitSteps(
		client,
		*steps,
		scenario.Movement.Frames,
	); err != nil {
		return entityState{}, err
	}
	*steps += scenario.Movement.Frames

	var moved entityState
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": player.ID},
		&moved,
	); err != nil {
		return moved, err
	}
	report.Movement.EndX = moved.X
	report.Movement.Delta = moved.X - player.X
	if report.Movement.Delta < scenario.Movement.MinimumDelta {
		return moved, fmt.Errorf(
			"movement delta %.2f is below required %.2f",
			report.Movement.Delta,
			scenario.Movement.MinimumDelta,
		)
	}
	return moved, nil
}

func runSmokeCombat(
	client *protocolClient,
	config smokeCombat,
	player entityState,
	steps *int,
	report *smokeReport,
) error {
	var snapshot worldSnapshot
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return err
	}
	target, err := entityWithTag(snapshot.Entities, config.TargetTag)
	if err != nil {
		return err
	}
	var positioned entityState
	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": target.ID,
			"x":        player.X + 40,
			"y":        player.Y,
		},
		&positioned,
	); err != nil {
		return err
	}
	before := positioned.Health

	var actionResult map[string]any
	if err := client.call(
		"Input.action",
		map[string]any{
			"action": config.Action,
			"value":  1,
			"frames": 1,
		},
		&actionResult,
	); err != nil {
		return err
	}
	if err := requestAndWaitSteps(client, *steps, config.Frames); err != nil {
		return err
	}
	*steps += config.Frames

	var after entityState
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": target.ID},
		&after,
	); err != nil {
		return err
	}
	damage := before - after.Health
	report.Combat = &struct {
		TargetID     string  `json:"target_id"`
		HealthBefore float64 `json:"health_before"`
		HealthAfter  float64 `json:"health_after"`
		Damage       float64 `json:"damage"`
	}{
		TargetID:     target.ID,
		HealthBefore: before,
		HealthAfter:  after.Health,
		Damage:       damage,
	}
	if damage < config.MinimumDamage {
		return fmt.Errorf(
			"combat damage %.2f is below required %.2f",
			damage,
			config.MinimumDamage,
		)
	}
	return nil
}

func runSmokeInteraction(
	client *protocolClient,
	config smokeInteraction,
	player entityState,
	steps *int,
	report *smokeReport,
) error {
	var snapshot worldSnapshot
	if err := client.call("World.getSnapshot", nil, &snapshot); err != nil {
		return err
	}
	target, err := entityWithTag(snapshot.Entities, config.TargetTag)
	if err != nil {
		return err
	}
	var positioned entityState
	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId": player.ID,
			"x":        target.X - 30,
			"y":        target.Y,
		},
		&positioned,
	); err != nil {
		return err
	}
	var actionResult map[string]any
	if err := client.call(
		"Input.action",
		map[string]any{
			"action": config.Action,
			"value":  1,
			"frames": 1,
		},
		&actionResult,
	); err != nil {
		return err
	}
	if err := requestAndWaitSteps(client, *steps, config.Frames); err != nil {
		return err
	}
	*steps += config.Frames

	var after worldSnapshot
	if err := client.call("World.getSnapshot", nil, &after); err != nil {
		return err
	}
	flagApplied := config.ExpectedFlag == "" ||
		after.Flags[config.ExpectedFlag]
	dialogueApplied := config.ExpectedDialogue == "" ||
		(after.Dialogue.Active &&
			after.Dialogue.DialogueID == config.ExpectedDialogue)
	applied := flagApplied && dialogueApplied
	report.Interaction = &struct {
		TargetID string `json:"target_id"`
		Flag     string `json:"flag,omitempty"`
		Dialogue string `json:"dialogue,omitempty"`
		Applied  bool   `json:"applied"`
	}{
		TargetID: target.ID,
		Flag:     config.ExpectedFlag,
		Dialogue: config.ExpectedDialogue,
		Applied:  applied,
	}
	if !applied {
		return fmt.Errorf("interaction expectation was not met")
	}
	return nil
}

func runSmokePersistence(
	client *protocolClient,
	config smokePersistence,
	report *smokeReport,
) error {
	var result map[string]any
	if err := client.call(
		"Inventory.give",
		map[string]any{"itemId": config.Item, "amount": 1},
		&result,
	); err != nil {
		return err
	}
	var saved worldSnapshot
	if err := client.call("World.getSnapshot", nil, &saved); err != nil {
		return err
	}
	savedCount := inventoryCount(saved.Inventory, config.Item)
	if savedCount < 1 {
		return fmt.Errorf("inventory did not receive %q", config.Item)
	}
	if err := client.call(
		"Save.write",
		map[string]any{"slot": "maker_smoke"},
		&result,
	); err != nil {
		return err
	}
	if err := client.call(
		"Inventory.give",
		map[string]any{"itemId": config.Item, "amount": 1},
		&result,
	); err != nil {
		return err
	}
	var mutated worldSnapshot
	if err := client.call("World.getSnapshot", nil, &mutated); err != nil {
		return err
	}
	mutatedCount := inventoryCount(mutated.Inventory, config.Item)
	if mutatedCount != savedCount+1 {
		return fmt.Errorf(
			"inventory mutation expected %d, got %d",
			savedCount+1,
			mutatedCount,
		)
	}
	if err := client.call(
		"Save.load",
		map[string]any{"slot": "maker_smoke"},
		&result,
	); err != nil {
		return err
	}
	var restored worldSnapshot
	if err := client.call("World.getSnapshot", nil, &restored); err != nil {
		return err
	}
	restoredCount := inventoryCount(restored.Inventory, config.Item)
	report.Persistence = &struct {
		Item          string `json:"item"`
		SavedCount    int    `json:"saved_count"`
		MutatedCount  int    `json:"mutated_count"`
		RestoredCount int    `json:"restored_count"`
	}{
		Item:          config.Item,
		SavedCount:    savedCount,
		MutatedCount:  mutatedCount,
		RestoredCount: restoredCount,
	}
	if restoredCount != savedCount {
		return fmt.Errorf(
			"save/load restored %d %s, expected %d",
			restoredCount,
			config.Item,
			savedCount,
		)
	}
	return nil
}

func runSmokeJourney(
	client *protocolClient,
	config smokeJourney,
	playerTag string,
	steps *int,
	artifacts string,
	report *smokeReport,
) error {
	for _, step := range config.Steps {
		repeat := step.Repeat
		if repeat == 0 {
			repeat = 1
		}
		for range repeat {
			var before worldSnapshot
			if err := client.call(
				"World.getSnapshot",
				nil,
				&before,
			); err != nil {
				return err
			}
			if before.GameFlow.Mode == config.ExpectedFlow {
				break
			}
			if step.TargetTag != "" {
				player, err := entityWithTag(
					before.Entities,
					playerTag,
				)
				if err != nil {
					return err
				}
				target, err := entityWithTag(
					before.Entities,
					step.TargetTag,
				)
				if err != nil {
					return err
				}
				var positioned entityState
				if err := client.call(
					"Entity.setPosition",
					map[string]any{
						"entityId": player.ID,
						"x":        target.X - 50,
						"y":        target.Y,
					},
					&positioned,
				); err != nil {
					return err
				}
			}
			if step.Action != "" {
				var actionResult map[string]any
				if err := client.call(
					"Input.action",
					map[string]any{
						"action": step.Action,
						"value":  1,
						"frames": 1,
					},
					&actionResult,
				); err != nil {
					return err
				}
			}
			if err := requestAndWaitSteps(
				client,
				*steps,
				step.Frames,
			); err != nil {
				return err
			}
			*steps += step.Frames
		}
	}

	var final worldSnapshot
	if err := client.call("World.getSnapshot", nil, &final); err != nil {
		return err
	}
	journeyReport := &struct {
		StepCount      int    `json:"step_count"`
		Flow           string `json:"flow"`
		Quest          string `json:"quest,omitempty"`
		QuestState     string `json:"quest_state,omitempty"`
		Encounter      string `json:"encounter,omitempty"`
		EncounterState string `json:"encounter_state,omitempty"`
		Battle         string `json:"battle,omitempty"`
		BattleState    string `json:"battle_state,omitempty"`
		Screenshot     string `json:"screenshot"`
	}{
		StepCount: len(config.Steps),
		Flow:      final.GameFlow.Mode,
		Quest:     config.ExpectedQuest,
		Encounter: config.ExpectedEncounter,
		Battle:    config.ExpectedBattle,
		Screenshot: filepath.Join(
			artifacts,
			"smoke-complete.png",
		),
	}
	if final.GameFlow.Mode != config.ExpectedFlow {
		return fmt.Errorf(
			"journey flow is %q, expected %q",
			final.GameFlow.Mode,
			config.ExpectedFlow,
		)
	}
	if config.ExpectedQuest != "" {
		for _, quest := range final.Quests {
			if quest.ID == config.ExpectedQuest {
				journeyReport.QuestState = quest.Status
				break
			}
		}
		if journeyReport.QuestState != "completed" {
			return fmt.Errorf(
				"journey quest %q is %q, expected completed",
				config.ExpectedQuest,
				journeyReport.QuestState,
			)
		}
	}
	if config.ExpectedEncounter != "" {
		for _, encounter := range final.Encounters {
			if encounter.ID == config.ExpectedEncounter {
				journeyReport.EncounterState = encounter.Status
				break
			}
		}
		if journeyReport.EncounterState != "completed" {
			return fmt.Errorf(
				"journey encounter %q is %q, expected completed",
				config.ExpectedEncounter,
				journeyReport.EncounterState,
			)
		}
	}
	if config.ExpectedBattle != "" {
		journeyReport.BattleState =
			final.TurnBattle.Results[config.ExpectedBattle]
		if journeyReport.BattleState != "won" {
			return fmt.Errorf(
				"journey turn battle %q is %q, expected won",
				config.ExpectedBattle,
				journeyReport.BattleState,
			)
		}
	}
	if err := captureScreenshot(
		client,
		journeyReport.Screenshot,
	); err != nil {
		return err
	}
	report.Journey = journeyReport
	return nil
}

func executeSmokeScenario(
	client *protocolClient,
	scenario smokeScenario,
	artifacts string,
) (smokeReport, error) {
	var report smokeReport
	state, err := pauseSimulation(client)
	if err != nil {
		return report, err
	}
	if state.Profile != scenario.Profile {
		return report, fmt.Errorf(
			"runtime profile %q does not match smoke profile %q",
			state.Profile,
			scenario.Profile,
		)
	}
	report.Project = state.Project
	report.Profile = state.Profile
	report.Stage = scenario.Stage
	report.FixedDelta = state.FixedDelta

	var initial worldSnapshot
	if err := client.call("World.getSnapshot", nil, &initial); err != nil {
		return report, err
	}
	report.Flow.InitialMode = initial.GameFlow.Mode
	report.Flow.Options = append(
		[]string(nil),
		initial.GameFlow.Options...,
	)
	if initial.GameFlow.Mode != "title" ||
		initial.GameFlow.Started ||
		!slices.Contains(initial.GameFlow.Options, "new_game") ||
		!slices.Contains(initial.GameFlow.Options, "quit") {
		return report, fmt.Errorf(
			"generated profile must boot a fresh title with new_game and "+
				"quit, got mode=%q started=%t options=%v",
			initial.GameFlow.Mode,
			initial.GameFlow.Started,
			initial.GameFlow.Options,
		)
	}
	report.Flow.Screenshot = filepath.Join(artifacts, "smoke-title.png")
	if err := captureScreenshot(client, report.Flow.Screenshot); err != nil {
		return report, err
	}

	if err := client.call(
		"App.startNewGame",
		map[string]any{"stageId": scenario.Stage},
		&state,
	); err != nil {
		return report, fmt.Errorf(
			"start fresh smoke stage %q: %w",
			scenario.Stage,
			err,
		)
	}
	if state.StageID != scenario.Stage {
		return report, fmt.Errorf(
			"runtime loaded stage %q instead of smoke stage %q",
			state.StageID,
			scenario.Stage,
		)
	}
	steps := state.Simulation.SteppedFrames

	player, err := runSmokeMovement(
		client,
		scenario,
		&steps,
		&report,
	)
	if err != nil {
		return report, err
	}
	if scenario.Combat != nil {
		if err := runSmokeCombat(
			client,
			*scenario.Combat,
			player,
			&steps,
			&report,
		); err != nil {
			return report, err
		}
	}
	if scenario.Interaction != nil {
		if err := runSmokeInteraction(
			client,
			*scenario.Interaction,
			player,
			&steps,
			&report,
		); err != nil {
			return report, err
		}
	}
	if scenario.Persistence != nil {
		if err := runSmokePersistence(
			client,
			*scenario.Persistence,
			&report,
		); err != nil {
			return report, err
		}
	}
	if scenario.Journey != nil {
		if err := runSmokeJourney(
			client,
			*scenario.Journey,
			scenario.PlayerTag,
			&steps,
			artifacts,
			&report,
		); err != nil {
			return report, err
		}
	}

	report.SteppedFrames = steps - state.Simulation.SteppedFrames
	report.Screenshot = filepath.Join(artifacts, "smoke.png")
	if err := captureScreenshot(client, report.Screenshot); err != nil {
		return report, err
	}
	return report, nil
}

func runSmokeTest(
	options globalOptions,
	projectPath string,
	arguments []string,
) error {
	flags := flag.NewFlagSet("smoke", flag.ContinueOnError)
	artifactArgument := flags.String(
		"artifacts",
		"",
		"directory for screenshot, report, and log",
	)
	scenarioArgument := flags.String(
		"scenario",
		"",
		"project-relative smoke scenario JSON",
	)
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if len(flags.Args()) != 0 {
		return errors.New(
			"usage: lovectl smoke [--artifacts PATH] [--scenario FILE]",
		)
	}
	scenario, err := loadSmokeScenario(projectPath, *scenarioArgument)
	if err != nil {
		return err
	}
	artifacts, err := prepareArtifacts(*artifactArgument)
	if err != nil {
		return err
	}
	runtimeDirectory, err := os.MkdirTemp("", "recreate_smoke_runtime_")
	if err != nil {
		return err
	}
	defer os.RemoveAll(runtimeDirectory)

	port, err := availablePort()
	if err != nil {
		return err
	}
	logPath := filepath.Join(artifacts, "love.log")
	logFile, err := os.Create(logPath)
	if err != nil {
		return err
	}
	defer logFile.Close()
	process, err := startLove(
		options.lovePath,
		projectPath,
		port,
		logFile,
		runtimeDirectory,
	)
	if err != nil {
		return err
	}
	defer forceStop(process)
	client := newProtocolClient("127.0.0.1", port, 20*time.Second)
	if err := waitForBridge(client, process, 20*time.Second); err != nil {
		return visualFailure(err, logPath)
	}

	report, err := executeSmokeScenario(client, scenario, artifacts)
	if err != nil {
		return visualFailure(err, logPath)
	}
	report.Log = logPath
	var quitResult map[string]any
	if err := client.call("App.quit", nil, &quitResult); err != nil {
		return visualFailure(err, logPath)
	}
	select {
	case waitError := <-process.done:
		process.command = nil
		if waitError != nil {
			return visualFailure(
				fmt.Errorf("LÖVE exited unsuccessfully: %w", waitError),
				logPath,
			)
		}
	case <-time.After(10 * time.Second):
		return visualFailure(
			errors.New("LÖVE did not quit within 10s"),
			logPath,
		)
	}

	reportPath := filepath.Join(artifacts, "smoke-report.json")
	encoded, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return err
	}
	encoded = append(encoded, '\n')
	if err := os.WriteFile(reportPath, encoded, 0o644); err != nil {
		return err
	}
	fmt.Printf(
		"Smoke passed: %s (%s)\n"+
			"  movement %.2f px, %d fixed ticks\n"+
			"  report %s\n",
		report.Project,
		report.Profile,
		report.Movement.Delta,
		report.SteppedFrames,
		reportPath,
	)
	return nil
}
