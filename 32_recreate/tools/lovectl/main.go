package main

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

type globalOptions struct {
	host        string
	port        int
	timeout     time.Duration
	projectPath string
	lovePath    string
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "lovectl:", err)
		os.Exit(1)
	}
}

func run(arguments []string) error {
	options, command, commandArguments, err := parseGlobalOptions(arguments)
	if err != nil {
		return err
	}
	if command == "" {
		printUsage()
		return errors.New("missing command")
	}
	if command == "help" || command == "-h" || command == "--help" {
		printUsage()
		return nil
	}
	if command == "init" {
		sourceProject, err := findProject(options.projectPath)
		if err != nil {
			return fmt.Errorf(
				"find Recreate source project for init: %w",
				err,
			)
		}
		return runInit(sourceProject, commandArguments)
	}

	projectPath, err := findProject(options.projectPath)
	if err != nil {
		return err
	}
	client := newProtocolClient(
		options.host,
		options.port,
		options.timeout,
	)

	switch command {
	case "ping":
		return callAndPrint(client, "Runtime.ping", nil)
	case "state":
		return callAndPrint(client, "Runtime.getState", nil)
	case "protocol":
		return callAndPrint(client, "Runtime.getProtocol", nil)
	case "content":
		return callAndPrint(client, "Content.getSummary", nil)
	case "definition":
		if len(commandArguments) != 1 {
			return errors.New("usage: lovectl definition CONTENT_ID")
		}
		return callAndPrint(client, "Content.getDefinition", map[string]any{
			"contentId": commandArguments[0],
		})
	case "world":
		return callAndPrint(client, "World.getSnapshot", nil)
	case "entity":
		if len(commandArguments) != 1 {
			return errors.New("usage: lovectl entity ENTITY_ID")
		}
		return callAndPrint(client, "Entity.get", map[string]any{
			"entityId": commandArguments[0],
		})
	case "position":
		if len(commandArguments) != 3 {
			return errors.New("usage: lovectl position ENTITY_ID X Y")
		}
		x, err := parseFloat(commandArguments[1], "X")
		if err != nil {
			return err
		}
		y, err := parseFloat(commandArguments[2], "Y")
		if err != nil {
			return err
		}
		return callAndPrint(client, "Entity.setPosition", map[string]any{
			"entityId": commandArguments[0],
			"x":        x,
			"y":        y,
		})
	case "health":
		if len(commandArguments) != 2 {
			return errors.New("usage: lovectl health ENTITY_ID VALUE")
		}
		value, err := parseFloat(commandArguments[1], "VALUE")
		if err != nil {
			return err
		}
		return callAndPrint(client, "Entity.setHealth", map[string]any{
			"entityId": commandArguments[0],
			"value":    value,
		})
	case "give":
		if len(commandArguments) < 1 || len(commandArguments) > 2 {
			return errors.New("usage: lovectl give ITEM_ID [AMOUNT]")
		}
		amount := 1
		if len(commandArguments) == 2 {
			amount, err = strconv.Atoi(commandArguments[1])
			if err != nil || amount < 1 {
				return errors.New("AMOUNT must be a positive integer")
			}
		}
		return callAndPrint(client, "Inventory.give", map[string]any{
			"itemId": commandArguments[0],
			"amount": amount,
		})
	case "money":
		if len(commandArguments) != 1 {
			return errors.New("usage: lovectl money AMOUNT")
		}
		amount, err := strconv.Atoi(commandArguments[0])
		if err != nil || amount < 0 {
			return errors.New("AMOUNT must be a non-negative integer")
		}
		return callAndPrint(client, "Economy.add", map[string]any{
			"amount": amount,
		})
	case "save":
		if len(commandArguments) != 1 {
			return errors.New("usage: lovectl save SLOT")
		}
		return callAndPrint(client, "Save.write", map[string]any{
			"slot": commandArguments[0],
		})
	case "load":
		if len(commandArguments) != 1 {
			return errors.New("usage: lovectl load SLOT")
		}
		return callAndPrint(client, "Save.load", map[string]any{
			"slot": commandArguments[0],
		})
	case "action":
		return runAction(client, commandArguments)
	case "pause":
		if len(commandArguments) != 1 {
			return errors.New("usage: lovectl pause true|false")
		}
		enabled, err := strconv.ParseBool(commandArguments[0])
		if err != nil {
			return errors.New("pause expects true or false")
		}
		return callAndPrint(client, "Test.setPaused", map[string]any{
			"enabled": enabled,
		})
	case "step":
		return runStep(client, commandArguments)
	case "overlay":
		if len(commandArguments) != 1 {
			return errors.New("usage: lovectl overlay true|false")
		}
		enabled, err := strconv.ParseBool(commandArguments[0])
		if err != nil {
			return errors.New("overlay expects true or false")
		}
		return callAndPrint(client, "Overlay.set", map[string]any{
			"enabled": enabled,
		})
	case "screenshot":
		if len(commandArguments) != 1 {
			return errors.New("usage: lovectl screenshot OUTPUT.png")
		}
		return captureScreenshot(client, commandArguments[0])
	case "stage":
		if len(commandArguments) < 1 || len(commandArguments) > 2 {
			return errors.New("usage: lovectl stage STAGE_ID [SPAWN_ID]")
		}
		params := map[string]any{"stageId": commandArguments[0]}
		if len(commandArguments) == 2 {
			params["spawnId"] = commandArguments[1]
		}
		return callAndPrint(client, "App.loadStage", params)
	case "new-game":
		if len(commandArguments) > 2 {
			return errors.New(
				"usage: lovectl new-game [STAGE_ID] [SPAWN_ID]",
			)
		}
		params := map[string]any{}
		if len(commandArguments) >= 1 {
			params["stageId"] = commandArguments[0]
		}
		if len(commandArguments) == 2 {
			params["spawnId"] = commandArguments[1]
		}
		return callAndPrint(client, "App.startNewGame", params)
	case "title":
		if len(commandArguments) != 0 {
			return errors.New("usage: lovectl title")
		}
		return callAndPrint(client, "App.returnToTitle", nil)
	case "reload":
		return callAndPrint(client, "App.reloadContent", nil)
	case "quit":
		return callAndPrint(client, "App.quit", nil)
	case "call":
		return runRawCall(client, commandArguments)
	case "run":
		if len(commandArguments) != 0 {
			return errors.New("usage: lovectl run")
		}
		return launchForeground(options, projectPath)
	case "check":
		if len(commandArguments) != 0 {
			return errors.New("usage: lovectl check")
		}
		return runChecks(options, projectPath)
	case "test":
		return runVisualTest(options, projectPath, commandArguments)
	case "smoke":
		return runSmokeTest(options, projectPath, commandArguments)
	case "campaign":
		return runCampaignTest(options, projectPath, commandArguments)
	case "maker":
		return runMaker(options, projectPath, commandArguments)
	case "map":
		return runMapCommand(projectPath, commandArguments)
	case "new":
		return runScaffold(projectPath, commandArguments)
	case "graph":
		return runContentGraph(options, projectPath, commandArguments)
	case "watch":
		return runWatch(client, projectPath, commandArguments)
	case "preview":
		return runPreview(client, commandArguments)
	case "package":
		return runPackageCommand(options, projectPath, commandArguments)
	default:
		return fmt.Errorf("unknown command: %s", command)
	}
}

func parseGlobalOptions(
	arguments []string,
) (globalOptions, string, []string, error) {
	options := globalOptions{}
	flags := flag.NewFlagSet("lovectl", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	flags.StringVar(&options.host, "host", "127.0.0.1", "debug bridge host")
	flags.IntVar(&options.port, "port", 19832, "debug bridge port")
	flags.DurationVar(
		&options.timeout,
		"timeout",
		15*time.Second,
		"protocol timeout",
	)
	flags.StringVar(
		&options.projectPath,
		"project",
		"",
		"32_recreate path",
	)
	flags.StringVar(
		&options.lovePath,
		"love",
		"/usr/local/bin/love",
		"LÖVE executable",
	)
	if err := flags.Parse(arguments); err != nil {
		return options, "", nil, err
	}
	remaining := flags.Args()
	if len(remaining) == 0 {
		return options, "", nil, nil
	}
	return options, remaining[0], remaining[1:], nil
}

func printUsage() {
	fmt.Print(`lovectl - Recreate content, debug, and visual-test controller

Usage:
  lovectl [global flags] COMMAND [arguments]

Commands:
  init --profile PROFILE TARGET     Create an independent Maker project
  run                              Launch a debug-enabled game
  check                            Syntax, content, Lua, and Go checks
  smoke [--artifacts PATH]         Project-declared capability smoke test
  test [--artifacts PATH]          Full project acceptance scenario
  campaign [--artifacts PATH]      Complete sample-game acceptance scenario
  maker [--listen ADDR] [--no-open]
                                    Open the local visual Maker workspace
  map compile [SOURCE.tmx ...]     Compile canonical TMX into Lua stages
  map check [SOURCE.tmx ...]       Validate TMX and generated output
  new TYPE NAME [REFERENCE_ID]     Create validated content; run without args for types
  graph [--json] [CONTENT_ID]      Show validated content dependencies
  watch [--once]                   Reload safe content/map/asset changes
  preview TYPE ...                 Stage, actor, ability, or dialogue preview
  package [--output FILE.love]     Build deterministic runtime-only package
  ping | state | protocol          Inspect runtime
  content | world                  Inspect semantic content/world
  definition CONTENT_ID            Inspect validated content and source
  entity ID                        Inspect an entity
  position ID X Y                  Move an entity
  health ID VALUE                  Set entity health
  give ITEM_ID [AMOUNT]           Add an item through the RPG service
  money AMOUNT                    Add currency through the RPG service
  save SLOT                       Atomically write a versioned save
  load SLOT                       Validate, migrate, and load a save
  action NAME [--frames N]         Inject semantic input
  pause true|false                 Pause/resume simulation
  step [--frames N]                Advance fixed simulation ticks
  overlay true|false               Toggle semantic overlay
  screenshot OUTPUT.png            Capture the framebuffer
  stage STAGE_ID [SPAWN_ID]        Atomically enter a stage/spawn point
  new-game [STAGE_ID] [SPAWN_ID]   Reset session and start a fresh game
  title                            Reset session and return to title
  reload                           Revalidate content and recreate the stage
  call METHOD [PARAMS_JSON]        Raw whitelisted protocol call
  quit                             Quit LÖVE cleanly
`)
}

func validateProject(path string) (string, error) {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	for _, required := range []string{
		"main.lua",
		"game/game.lua",
		"engine/core/app.lua",
	} {
		info, statErr := os.Stat(filepath.Join(absolute, required))
		if statErr != nil || info.IsDir() {
			return "", fmt.Errorf("%s is not a 32_recreate project", path)
		}
	}
	return absolute, nil
}

func findProject(explicit string) (string, error) {
	if explicit != "" {
		return validateProject(explicit)
	}
	current, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for candidate := current; ; candidate = filepath.Dir(candidate) {
		if project, err := validateProject(candidate); err == nil {
			return project, nil
		}
		nested := filepath.Join(candidate, "32_recreate")
		if project, err := validateProject(nested); err == nil {
			return project, nil
		}
		parent := filepath.Dir(candidate)
		if parent == candidate {
			break
		}
	}
	return "", errors.New("could not find 32_recreate project")
}

func callAndPrint(
	client *protocolClient,
	method string,
	params map[string]any,
) error {
	result, err := client.rawCall(method, params)
	if err != nil {
		return err
	}
	var formatted any
	if err := json.Unmarshal(result, &formatted); err != nil {
		return err
	}
	return printJSON(formatted)
}

func parseFloat(value, name string) (float64, error) {
	parsed, err := strconv.ParseFloat(value, 64)
	if err != nil {
		return 0, fmt.Errorf("%s must be a number", name)
	}
	return parsed, nil
}

func runAction(client *protocolClient, arguments []string) error {
	if len(arguments) < 1 {
		return errors.New("usage: lovectl action NAME [--frames N]")
	}
	name := arguments[0]
	flags := flag.NewFlagSet("action", flag.ContinueOnError)
	frames := flags.Int("frames", 1, "simulation frames")
	value := flags.Float64("value", 1, "input strength")
	if err := flags.Parse(arguments[1:]); err != nil {
		return err
	}
	if len(flags.Args()) != 0 {
		return errors.New("usage: lovectl action NAME [--frames N]")
	}
	return callAndPrint(client, "Input.action", map[string]any{
		"action": name,
		"value":  *value,
		"frames": *frames,
	})
}

func runStep(client *protocolClient, arguments []string) error {
	flags := flag.NewFlagSet("step", flag.ContinueOnError)
	frames := flags.Int("frames", 1, "number of frames")
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if len(flags.Args()) != 0 {
		return errors.New("usage: lovectl step [--frames N]")
	}
	return callAndPrint(client, "Test.step", map[string]any{
		"frames": *frames,
	})
}

func runRawCall(client *protocolClient, arguments []string) error {
	if len(arguments) < 1 || len(arguments) > 2 {
		return errors.New("usage: lovectl call METHOD [PARAMS_JSON]")
	}
	params := map[string]any{}
	if len(arguments) == 2 {
		if err := json.Unmarshal([]byte(arguments[1]), &params); err != nil {
			return fmt.Errorf("invalid params JSON: %w", err)
		}
	}
	return callAndPrint(client, arguments[0], params)
}

func captureScreenshot(client *protocolClient, outputPath string) error {
	var result struct {
		Data   string `json:"data"`
		Format string `json:"format"`
		Width  int    `json:"width"`
		Height int    `json:"height"`
	}
	if err := client.call("Page.captureScreenshot", nil, &result); err != nil {
		return err
	}
	decoded, err := base64.StdEncoding.DecodeString(result.Data)
	if err != nil {
		return fmt.Errorf("decode screenshot: %w", err)
	}
	absolute, err := filepath.Abs(outputPath)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(absolute), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(absolute, decoded, 0o644); err != nil {
		return err
	}
	fmt.Printf("Screenshot: %s (%dx%d)\n", absolute, result.Width, result.Height)
	return nil
}

func overrideEnvironment(
	environment []string,
	overrides map[string]string,
) []string {
	result := make([]string, 0, len(environment)+len(overrides))
	for _, value := range environment {
		key, _, found := strings.Cut(value, "=")
		if found {
			if _, overridden := overrides[key]; overridden {
				continue
			}
		}
		result = append(result, value)
	}
	keys := make([]string, 0, len(overrides))
	for key := range overrides {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		result = append(result, key+"="+overrides[key])
	}
	return result
}

func debugEnvironment(port int) []string {
	return overrideEnvironment(os.Environ(), map[string]string{
		"RECREATE_DEBUG_BRIDGE": "1",
		"RECREATE_DEBUG_PORT":   fmt.Sprintf("%d", port),
	})
}

func launchForeground(options globalOptions, projectPath string) error {
	command := exec.Command(options.lovePath, projectPath)
	command.Dir = projectPath
	command.Env = debugEnvironment(options.port)
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	command.Stdin = os.Stdin
	return command.Run()
}
