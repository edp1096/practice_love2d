package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

type pingState struct {
	Pong          bool `json:"pong"`
	Protocol      int  `json:"protocol"`
	SemanticWorld bool `json:"semantic_world"`
}

type runtimeState struct {
	Scene       string `json:"scene"`
	LoveVersion string `json:"love_version"`
	LuaVersion  string `json:"lua_version"`
	JITVersion  string `json:"jit_version"`
	Simulation  struct {
		Paused        bool    `json:"paused"`
		PendingFrames int     `json:"pending_frames"`
		SteppedFrames int     `json:"stepped_frames"`
		StepDelta     float64 `json:"step_dt"`
	} `json:"simulation"`
}

type worldSnapshot struct {
	Available bool           `json:"available"`
	Map       map[string]any `json:"map"`
	Counts    struct {
		Entities int `json:"entities"`
		Walls    int `json:"walls"`
	} `json:"counts"`
	Entities []entityState `json:"entities"`
}

type entityState struct {
	ID        string  `json:"id"`
	Kind      string  `json:"kind"`
	X         float64 `json:"x"`
	Y         float64 `json:"y"`
	Health    float64 `json:"health"`
	MaxHealth float64 `json:"max_health"`
}

type visualReport struct {
	Ping               pingState          `json:"ping"`
	MenuState          runtimeState       `json:"menu_state"`
	MenuScreenshot     screenshotMetadata `json:"menu_screenshot"`
	GameplayScreenshot screenshotMetadata `json:"gameplay_screenshot"`
	Gameplay           gameplayReport     `json:"gameplay"`
}

type gameplayReport struct {
	Map                  map[string]any `json:"map"`
	Counts               map[string]any `json:"counts"`
	PlayerID             string         `json:"player_id"`
	EnemyID              string         `json:"enemy_id"`
	PositionAfterControl position       `json:"position_after_control"`
	HealthAfterControl   float64        `json:"health_after_control"`
	SteppedFrames        int            `json:"stepped_frames"`
}

type position struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

type loveProcess struct {
	command *exec.Cmd
	done    chan error
}

func runVisualTest(
	options globalOptions,
	projectPath string,
	arguments []string,
) error {
	flags := flag.NewFlagSet("test", flag.ContinueOnError)
	artifactArgument := flags.String(
		"artifacts",
		"",
		"directory for screenshots, report, and log",
	)
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if len(flags.Args()) != 0 {
		return errors.New("usage: lovectl test [--artifacts PATH]")
	}

	artifacts, err := prepareArtifacts(*artifactArgument)
	if err != nil {
		return err
	}
	port, err := availablePort()
	if err != nil {
		return err
	}

	logPath := filepath.Join(artifacts, "love.log")
	logFile, err := os.Create(logPath)
	if err != nil {
		return err
	}

	process, err := startLove(
		options.lovePath,
		projectPath,
		port,
		logFile,
	)
	if err != nil {
		logFile.Close()
		return err
	}

	client := newProtocolClient("127.0.0.1", port, 30*time.Second)
	defer func() {
		stopLove(client, process)
		if logFile != nil {
			logFile.Close()
		}
	}()

	if err := waitForBridge(port, process, 30*time.Second); err != nil {
		return visualFailure(err, logPath)
	}
	report, err := runVisualScenario(client, artifacts)
	if err != nil {
		return visualFailure(err, logPath)
	}

	if err := client.call("App.quit", nil, &map[string]any{}); err != nil {
		return visualFailure(err, logPath)
	}
	select {
	case waitError := <-process.done:
		if waitError != nil {
			return visualFailure(
				fmt.Errorf("LÖVE exited unsuccessfully: %w", waitError),
				logPath,
			)
		}
		process.command = nil
	case <-time.After(10 * time.Second):
		return visualFailure(errors.New("LÖVE did not quit within 10s"), logPath)
	}
	if err := logFile.Close(); err != nil {
		return err
	}
	logFile = nil

	reportPath := filepath.Join(artifacts, "report.json")
	encoded, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return err
	}
	encoded = append(encoded, '\n')
	if err := os.WriteFile(reportPath, encoded, 0o644); err != nil {
		return err
	}

	fmt.Printf("Visual protocol test passed: %s\n", artifacts)
	fmt.Printf(
		"  %d entities, %d walls, %d stepped frames\n",
		report.Gameplay.Counts["entities"],
		report.Gameplay.Counts["walls"],
		report.Gameplay.SteppedFrames,
	)
	return nil
}

func prepareArtifacts(argument string) (string, error) {
	if argument == "" {
		return os.MkdirTemp("", "31_dev_proto_visual_")
	}
	absolute, err := filepath.Abs(argument)
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(absolute, 0o755); err != nil {
		return "", err
	}
	return absolute, nil
}

func availablePort() (int, error) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer listener.Close()
	return listener.Addr().(*net.TCPAddr).Port, nil
}

func startLove(
	lovePath, projectPath string,
	port int,
	logFile *os.File,
) (*loveProcess, error) {
	command := exec.Command(lovePath, projectPath)
	command.Dir = projectPath
	command.Env = debugEnvironment(port)
	command.Stdout = logFile
	command.Stderr = logFile
	if err := command.Start(); err != nil {
		return nil, err
	}
	process := &loveProcess{
		command: command,
		done:    make(chan error, 1),
	}
	go func() {
		process.done <- command.Wait()
	}()
	return process, nil
}

func waitForBridge(
	port int,
	process *loveProcess,
	timeout time.Duration,
) error {
	deadline := time.Now().Add(timeout)
	client := newProtocolClient("127.0.0.1", port, time.Second)
	for time.Now().Before(deadline) {
		select {
		case err := <-process.done:
			process.command = nil
			if err == nil {
				return errors.New("LÖVE exited before the bridge started")
			}
			return fmt.Errorf("LÖVE exited before the bridge started: %w", err)
		default:
		}

		var ping pingState
		if err := client.call("Runtime.ping", nil, &ping); err == nil && ping.Pong {
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}
	return errors.New("timed out waiting for the debug bridge")
}

func runVisualScenario(
	client *protocolClient,
	artifacts string,
) (visualReport, error) {
	report := visualReport{}
	if err := client.call("Runtime.ping", nil, &report.Ping); err != nil {
		return report, err
	}
	if !report.Ping.SemanticWorld {
		return report, errors.New("semantic world capability is missing")
	}

	if err := client.call(
		"Runtime.getState",
		nil,
		&report.MenuState,
	); err != nil {
		return report, err
	}
	if report.MenuState.Scene != "menu" {
		return report, fmt.Errorf(
			"expected menu scene, got %s",
			report.MenuState.Scene,
		)
	}
	if report.MenuState.LuaVersion != "Lua 5.1" ||
		report.MenuState.JITVersion == "" {
		return report, fmt.Errorf(
			"expected LuaJIT with Lua 5.1 compatibility, got %q / %q",
			report.MenuState.LuaVersion,
			report.MenuState.JITVersion,
		)
	}
	menuScreenshot, err := captureScreenshot(
		client,
		filepath.Join(artifacts, "menu.png"),
		false,
	)
	if err != nil {
		return report, err
	}
	report.MenuScreenshot = menuScreenshot

	if err := client.call(
		"Test.setPaused",
		map[string]any{"enabled": true},
		&map[string]any{},
	); err != nil {
		return report, err
	}
	if err := client.call(
		"Game.startNew",
		nil,
		&map[string]any{},
	); err != nil {
		return report, err
	}

	var gameplayState runtimeState
	if err := client.call(
		"Runtime.getState",
		nil,
		&gameplayState,
	); err != nil {
		return report, err
	}
	if gameplayState.Scene != "gameplay" {
		return report, fmt.Errorf(
			"expected gameplay scene, got %s",
			gameplayState.Scene,
		)
	}

	var world worldSnapshot
	if err := client.call("World.getSnapshot", nil, &world); err != nil {
		return report, err
	}
	if !world.Available {
		return report, errors.New("world snapshot is unavailable")
	}
	if world.Counts.Walls < 1 {
		return report, errors.New("expected at least one wall collider")
	}

	var player entityState
	var enemy entityState
	playerFound := false
	enemyFound := false
	for _, entity := range world.Entities {
		switch {
		case entity.Kind == "player" && !playerFound:
			player = entity
			playerFound = true
		case entity.Kind == "enemy" && !enemyFound:
			enemy = entity
			enemyFound = true
		}
	}
	if !playerFound {
		return report, errors.New("player was not exposed")
	}
	if !enemyFound {
		return report, errors.New("expected at least one enemy")
	}

	movedX := player.X + 8
	movedY := player.Y
	var moved entityState
	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId":     player.ID,
			"x":            movedX,
			"y":            movedY,
			"stopVelocity": true,
		},
		&moved,
	); err != nil {
		return report, err
	}
	if !closeEnough(moved.X, movedX) || !closeEnough(moved.Y, movedY) {
		return report, fmt.Errorf(
			"position control failed: got (%f, %f)",
			moved.X,
			moved.Y,
		)
	}

	healthValue := max(0, player.MaxHealth-1)
	var health entityState
	if err := client.call(
		"Entity.setHealth",
		map[string]any{"entityId": player.ID, "value": healthValue},
		&health,
	); err != nil {
		return report, err
	}
	if !closeEnough(health.Health, healthValue) {
		return report, fmt.Errorf(
			"health control failed: got %f",
			health.Health,
		)
	}

	var inspectedEnemy entityState
	if err := client.call(
		"Entity.get",
		map[string]any{"entityId": enemy.ID},
		&inspectedEnemy,
	); err != nil {
		return report, err
	}
	if inspectedEnemy.Kind != "enemy" {
		return report, errors.New("entity lookup returned the wrong object")
	}

	if err := client.call(
		"Entity.setPosition",
		map[string]any{
			"entityId":     player.ID,
			"x":            player.X,
			"y":            player.Y,
			"stopVelocity": true,
		},
		&map[string]any{},
	); err != nil {
		return report, err
	}
	if err := client.call(
		"Entity.setHealth",
		map[string]any{"entityId": player.ID, "value": player.Health},
		&map[string]any{},
	); err != nil {
		return report, err
	}
	if err := client.call(
		"Test.step",
		map[string]any{"frames": 2, "dt": 1.0 / 60.0},
		&map[string]any{},
	); err != nil {
		return report, err
	}

	var stepped runtimeState
	if err := client.call("Runtime.getState", nil, &stepped); err != nil {
		return report, err
	}
	if stepped.Simulation.SteppedFrames < 2 {
		return report, errors.New("deterministic frame stepping did not run")
	}

	if err := client.call(
		"Overlay.set",
		map[string]any{
			"enabled":  true,
			"entities": true,
			"walls":    true,
			"labels":   true,
		},
		&map[string]any{},
	); err != nil {
		return report, err
	}
	gameplayScreenshot, err := captureScreenshot(
		client,
		filepath.Join(artifacts, "gameplay_debug.png"),
		false,
	)
	if err != nil {
		return report, err
	}
	report.GameplayScreenshot = gameplayScreenshot

	counts := map[string]any{
		"entities": world.Counts.Entities,
		"walls":    world.Counts.Walls,
	}
	report.Gameplay = gameplayReport{
		Map:                  world.Map,
		Counts:               counts,
		PlayerID:             player.ID,
		EnemyID:              inspectedEnemy.ID,
		PositionAfterControl: position{X: moved.X, Y: moved.Y},
		HealthAfterControl:   health.Health,
		SteppedFrames:        stepped.Simulation.SteppedFrames,
	}
	return report, nil
}

func closeEnough(actual, expected float64) bool {
	difference := actual - expected
	if difference < 0 {
		difference = -difference
	}
	return difference <= 0.01
}

func stopLove(client *protocolClient, process *loveProcess) {
	if process == nil || process.command == nil ||
		process.command.Process == nil {
		return
	}
	_ = client.call("App.quit", nil, &map[string]any{})
	select {
	case <-process.done:
		process.command = nil
		return
	case <-time.After(3 * time.Second):
	}
	_ = process.command.Process.Kill()
	<-process.done
	process.command = nil
}

func visualFailure(original error, logPath string) error {
	logContents, readError := os.ReadFile(logPath)
	if readError != nil || len(logContents) == 0 {
		return original
	}
	return fmt.Errorf("%w\n\nLÖVE log:\n%s", original, string(logContents))
}
