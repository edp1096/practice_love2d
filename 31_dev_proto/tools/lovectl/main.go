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
	"strconv"
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
	case "world":
		return callAndPrint(client, "World.getSnapshot", nil)
	case "start":
		return callAndPrint(client, "Game.startNew", nil)
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
			"entityId":     commandArguments[0],
			"x":            x,
			"y":            y,
			"stopVelocity": true,
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
		_, err := captureScreenshot(client, commandArguments[0], true)
		return err
	case "key":
		if len(commandArguments) != 1 {
			return errors.New("usage: lovectl key KEY")
		}
		return callAndPrint(client, "Input.key", map[string]any{
			"key": commandArguments[0],
		})
	case "move":
		if len(commandArguments) != 2 {
			return errors.New("usage: lovectl move X Y")
		}
		x, err := parseFloat(commandArguments[0], "X")
		if err != nil {
			return err
		}
		y, err := parseFloat(commandArguments[1], "Y")
		if err != nil {
			return err
		}
		return callAndPrint(client, "Input.mouseMove", map[string]any{
			"x": x,
			"y": y,
		})
	case "click":
		return runClick(client, commandArguments)
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
		return runChecks(projectPath)
	case "package":
		return runPackage(projectPath, commandArguments)
	case "test":
		return runVisualTest(options, projectPath, commandArguments)
	case "help", "-h", "--help":
		printUsage()
		return nil
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
	flags.IntVar(&options.port, "port", 19785, "debug bridge port")
	flags.DurationVar(&options.timeout, "timeout", 15*time.Second, "protocol timeout")
	flags.StringVar(&options.projectPath, "project", "", "31_dev_proto path")
	flags.StringVar(&options.lovePath, "love", "/usr/local/bin/love", "LÖVE executable")
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
	fmt.Print(`lovectl - LÖVE semantic debug and test controller

Usage:
  lovectl [global flags] COMMAND [arguments]

Global flags:
  --host HOST          Debug bridge host (default 127.0.0.1)
  --port PORT          Debug bridge port (default 19785)
  --timeout DURATION   Protocol timeout (default 15s)
  --project PATH       Path to 31_dev_proto
  --love PATH          LÖVE executable (default /usr/local/bin/love)

Commands:
  run                         Launch a debug-enabled LÖVE process
  ping | state | protocol     Inspect protocol/runtime
  world                       Get semantic world snapshot
  start                       Enter a new game directly
  entity ID                   Inspect one entity
  position ID X Y             Move an entity and its colliders
  health ID VALUE             Set entity health
  pause true|false            Pause/resume simulation
  step [--frames N] [--dt S]  Advance deterministic frames
  overlay true|false          Toggle semantic screen overlay
  screenshot OUTPUT.png       Capture the actual framebuffer
  key KEY                     Send a key press/release
  move X Y                    Move the mouse
  click [--button N] X Y      Click the mouse
  call METHOD [PARAMS_JSON]   Send a raw whitelisted protocol call
  quit                        Quit LÖVE cleanly
  check                       Check Lua/Go sources and Lua unit tests
  package [--output PATH]     Deterministically rebuild web/game.love
  test [--artifacts PATH]     Run the real-window integration test
`)
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
		nested := filepath.Join(candidate, "31_dev_proto")
		if project, err := validateProject(nested); err == nil {
			return project, nil
		}
		parent := filepath.Dir(candidate)
		if parent == candidate {
			break
		}
	}
	return "", errors.New(
		"could not locate 31_dev_proto; use --project PATH",
	)
}

func validateProject(path string) (string, error) {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	for _, required := range []string{"main.lua", "engine", "tests/run.lua"} {
		if _, err := os.Stat(filepath.Join(absolute, required)); err != nil {
			return "", fmt.Errorf("%s is not 31_dev_proto", absolute)
		}
	}
	return absolute, nil
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
	var value any
	if err := json.Unmarshal(result, &value); err != nil {
		return err
	}
	return printJSON(value)
}

func parseFloat(value, label string) (float64, error) {
	number, err := strconv.ParseFloat(value, 64)
	if err != nil {
		return 0, fmt.Errorf("%s must be a number", label)
	}
	return number, nil
}

func runStep(client *protocolClient, arguments []string) error {
	flags := flag.NewFlagSet("step", flag.ContinueOnError)
	frames := flags.Int("frames", 1, "number of frames")
	delta := flags.Float64("dt", 1.0/60.0, "simulation delta")
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if len(flags.Args()) != 0 {
		return errors.New("usage: lovectl step [--frames N] [--dt S]")
	}
	return callAndPrint(client, "Test.step", map[string]any{
		"frames": *frames,
		"dt":     *delta,
	})
}

func runClick(client *protocolClient, arguments []string) error {
	flags := flag.NewFlagSet("click", flag.ContinueOnError)
	button := flags.Int("button", 1, "mouse button")
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	position := flags.Args()
	if len(position) != 2 {
		return errors.New("usage: lovectl click [--button N] X Y")
	}
	x, err := parseFloat(position[0], "X")
	if err != nil {
		return err
	}
	y, err := parseFloat(position[1], "Y")
	if err != nil {
		return err
	}
	return callAndPrint(client, "Input.mouseClick", map[string]any{
		"x":      x,
		"y":      y,
		"button": *button,
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

type screenshotResult struct {
	Data   string `json:"data"`
	Format string `json:"format"`
	Width  int    `json:"width"`
	Height int    `json:"height"`
}

type screenshotMetadata struct {
	Format string `json:"format"`
	Width  int    `json:"width"`
	Height int    `json:"height"`
	Bytes  int    `json:"bytes"`
}

func captureScreenshot(
	client *protocolClient,
	output string,
	verbose bool,
) (screenshotMetadata, error) {
	var response screenshotResult
	if err := client.call("Page.captureScreenshot", nil, &response); err != nil {
		return screenshotMetadata{}, err
	}
	png, err := base64.StdEncoding.DecodeString(response.Data)
	if err != nil {
		return screenshotMetadata{}, fmt.Errorf("decode screenshot: %w", err)
	}
	signature := []byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'}
	if len(png) < len(signature) ||
		string(png[:len(signature)]) != string(signature) {
		return screenshotMetadata{}, errors.New("screenshot is not a PNG")
	}

	absolute, err := filepath.Abs(output)
	if err != nil {
		return screenshotMetadata{}, err
	}
	if err := os.MkdirAll(filepath.Dir(absolute), 0o755); err != nil {
		return screenshotMetadata{}, err
	}
	if err := os.WriteFile(absolute, png, 0o644); err != nil {
		return screenshotMetadata{}, err
	}

	metadata := screenshotMetadata{
		Format: response.Format,
		Width:  response.Width,
		Height: response.Height,
		Bytes:  len(png),
	}
	if verbose {
		fmt.Printf(
			"%s (%dx%d, %d bytes)\n",
			absolute,
			metadata.Width,
			metadata.Height,
			metadata.Bytes,
		)
	}
	return metadata, nil
}

func debugEnvironment(port int) []string {
	environment := append([]string{}, os.Environ()...)
	environment = append(
		environment,
		"LOVE2D_DEBUG_BRIDGE=1",
		fmt.Sprintf("LOVE2D_DEBUG_PORT=%d", port),
		"LOVE2D_DISABLE_INSTANCE_LOCK=1",
	)
	return environment
}

func launchForeground(options globalOptions, projectPath string) error {
	command := exec.Command(options.lovePath, projectPath)
	command.Dir = projectPath
	command.Env = debugEnvironment(options.port)
	command.Stdin = os.Stdin
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	return command.Run()
}
