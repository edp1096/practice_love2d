package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"image/png"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"practice_love2d/33_ebitengine_spike/internal/protocol"
)

type globalOptions struct {
	address string
	timeout time.Duration
	token   string
}

func main() {
	if err := run(
		context.Background(),
		os.Args[1:],
		os.Stdin,
		os.Stdout,
		os.Stderr,
	); err != nil {
		fmt.Fprintln(os.Stderr, "recreatectl:", err)
		os.Exit(1)
	}
}

func run(
	ctx context.Context,
	arguments []string,
	stdin io.Reader,
	stdout io.Writer,
	stderr io.Writer,
) error {
	options, command, commandArguments, err := parseOptions(arguments, stderr)
	if err != nil {
		return err
	}
	if command == "" {
		printUsage(stderr)
		return errors.New("missing command")
	}
	if command == "help" || command == "-h" || command == "--help" {
		printUsage(stdout)
		return nil
	}

	client, err := protocol.NewClient(protocol.ClientConfig{
		Address:   options.address,
		Timeout:   options.timeout,
		AuthToken: options.token,
	})
	if err != nil {
		return err
	}
	call := func(method string, params any) error {
		result, err := client.CallRaw(ctx, method, params)
		if err != nil {
			return err
		}
		return printRawJSON(stdout, result)
	}

	switch command {
	case "ping":
		return requireNoArgs(commandArguments, func() error {
			return call(protocol.MethodRuntimePing, nil)
		})
	case "protocol":
		return requireNoArgs(commandArguments, func() error {
			return call(protocol.MethodRuntimeGetProtocol, nil)
		})
	case "state":
		return requireNoArgs(commandArguments, func() error {
			return call(protocol.MethodRuntimeGetState, nil)
		})
	case "graph":
		return requireNoArgs(commandArguments, func() error {
			return call(protocol.MethodContentGetGraph, nil)
		})
	case "definition":
		if len(commandArguments) != 1 {
			return errors.New("usage: recreatectl definition CONTENT_ID")
		}
		return call(
			protocol.MethodContentGetDefinition,
			protocol.ContentIDParams{ContentID: commandArguments[0]},
		)
	case "validate":
		if len(commandArguments) != 2 {
			return errors.New(
				"usage: recreatectl validate CONTENT_ID FILE.json|-",
			)
		}
		definition, err := readJSONObject(
			commandArguments[1],
			stdin,
			protocol.DefaultMaxParamsBytes,
		)
		if err != nil {
			return err
		}
		return call(
			protocol.MethodContentValidateDefinition,
			protocol.ValidateDefinitionParams{
				ContentID:  commandArguments[0],
				Definition: definition,
			},
		)
	case "world":
		return requireNoArgs(commandArguments, func() error {
			return call(protocol.MethodWorldGetSnapshot, nil)
		})
	case "wall":
		if len(commandArguments) != 5 {
			return errors.New(
				"usage: recreatectl wall WALL_ID X Y WIDTH HEIGHT",
			)
		}
		values := make([]float64, 4)
		for index, label := range []string{"X", "Y", "WIDTH", "HEIGHT"} {
			value, err := parseFiniteFloat(commandArguments[index+1], label)
			if err != nil {
				return err
			}
			values[index] = value
		}
		return call(
			protocol.MethodWorldSetWall,
			protocol.SetWallParams{
				WallID: commandArguments[0],
				X:      values[0],
				Y:      values[1],
				Width:  values[2],
				Height: values[3],
			},
		)
	case "position":
		if len(commandArguments) != 3 {
			return errors.New(
				"usage: recreatectl position ENTITY_ID X Y",
			)
		}
		x, err := parseFiniteFloat(commandArguments[1], "X")
		if err != nil {
			return err
		}
		y, err := parseFiniteFloat(commandArguments[2], "Y")
		if err != nil {
			return err
		}
		return call(
			protocol.MethodEntitySetPosition,
			protocol.SetPositionParams{
				EntityID: commandArguments[0],
				X:        x,
				Y:        y,
			},
		)
	case "health":
		if len(commandArguments) != 2 {
			return errors.New(
				"usage: recreatectl health ENTITY_ID VALUE",
			)
		}
		value, err := parseFiniteFloat(commandArguments[1], "VALUE")
		if err != nil {
			return err
		}
		return call(
			protocol.MethodEntitySetHealth,
			protocol.SetHealthParams{
				EntityID: commandArguments[0],
				Value:    value,
			},
		)
	case "ability":
		if len(commandArguments) != 2 {
			return errors.New(
				"usage: recreatectl ability ENTITY_ID ABILITY_ID",
			)
		}
		return call(
			protocol.MethodEntityRequestAbility,
			protocol.RequestAbilityParams{
				EntityID:  commandArguments[0],
				AbilityID: commandArguments[1],
			},
		)
	case "action":
		return runAction(call, commandArguments, stderr)
	case "pause":
		if len(commandArguments) != 1 {
			return errors.New("usage: recreatectl pause true|false")
		}
		enabled, err := strconv.ParseBool(commandArguments[0])
		if err != nil {
			return errors.New("pause expects true or false")
		}
		return call(
			protocol.MethodEmulationSetPaused,
			protocol.SetPausedParams{Enabled: enabled},
		)
	case "step":
		return runStep(call, commandArguments, stderr)
	case "screenshot":
		if len(commandArguments) != 1 {
			return errors.New(
				"usage: recreatectl screenshot OUTPUT.png",
			)
		}
		return captureScreenshot(
			ctx,
			client,
			commandArguments[0],
			stdout,
		)
	case "reload":
		return requireNoArgs(commandArguments, func() error {
			return call(protocol.MethodAppReloadContent, nil)
		})
	case "new-game":
		return requireNoArgs(commandArguments, func() error {
			return call(protocol.MethodAppStartNewGame, nil)
		})
	case "save":
		if len(commandArguments) != 1 {
			return errors.New("usage: recreatectl save SLOT")
		}
		return call(
			protocol.MethodAppSave,
			protocol.SaveSlotParams{Slot: commandArguments[0]},
		)
	case "load":
		if len(commandArguments) != 1 {
			return errors.New("usage: recreatectl load SLOT")
		}
		return call(
			protocol.MethodAppLoad,
			protocol.SaveSlotParams{Slot: commandArguments[0]},
		)
	case "quit":
		return requireNoArgs(commandArguments, func() error {
			return call(protocol.MethodAppQuit, nil)
		})
	case "call":
		return runRawCall(call, commandArguments)
	default:
		return fmt.Errorf("unknown command: %s", command)
	}
}

func parseOptions(
	arguments []string,
	stderr io.Writer,
) (globalOptions, string, []string, error) {
	options := globalOptions{}
	flags := flag.NewFlagSet("recreatectl", flag.ContinueOnError)
	flags.SetOutput(stderr)
	flags.StringVar(
		&options.address,
		"address",
		protocol.DefaultAddress,
		"loopback debug address",
	)
	flags.DurationVar(
		&options.timeout,
		"timeout",
		15*time.Second,
		"request timeout",
	)
	tokenFile := flags.String(
		"token-file",
		"",
		"path to a private debug token file",
	)
	if err := flags.Parse(arguments); err != nil {
		return options, "", nil, err
	}
	options.token = os.Getenv("RECREATE_DEBUG_TOKEN")
	if *tokenFile != "" {
		token, err := readAuthTokenFile(*tokenFile)
		if err != nil {
			return options, "", nil, err
		}
		options.token = token
	}
	remaining := flags.Args()
	if len(remaining) == 0 {
		return options, "", nil, nil
	}
	return options, remaining[0], remaining[1:], nil
}

func readAuthTokenFile(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("open token file: %w", err)
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return "", fmt.Errorf("inspect token file: %w", err)
	}
	if !info.Mode().IsRegular() {
		return "", errors.New("token file must be a regular file")
	}
	if info.Mode().Perm()&0o077 != 0 {
		return "", errors.New(
			"token file must not be accessible by group or other users",
		)
	}
	data, err := io.ReadAll(io.LimitReader(file, 513))
	if err != nil {
		return "", fmt.Errorf("read token file: %w", err)
	}
	if len(data) > 512 {
		return "", errors.New("token file exceeds 512 bytes")
	}
	token := strings.TrimSpace(string(data))
	if token == "" {
		return "", errors.New("token file is empty")
	}
	return token, nil
}

func runAction(
	call func(string, any) error,
	arguments []string,
	stderr io.Writer,
) error {
	if len(arguments) == 0 {
		return errors.New(
			"usage: recreatectl action NAME [--value N] [--frames N]",
		)
	}
	flags := flag.NewFlagSet("action", flag.ContinueOnError)
	flags.SetOutput(stderr)
	value := flags.Float64("value", 1, "input strength")
	frames := flags.Int("frames", 1, "simulation frames")
	if err := flags.Parse(arguments[1:]); err != nil {
		return err
	}
	if len(flags.Args()) != 0 {
		return errors.New(
			"usage: recreatectl action NAME [--value N] [--frames N]",
		)
	}
	return call(protocol.MethodInputAction, protocol.InputActionParams{
		Action: arguments[0],
		Value:  *value,
		Frames: *frames,
	})
}

func runStep(
	call func(string, any) error,
	arguments []string,
	stderr io.Writer,
) error {
	flags := flag.NewFlagSet("step", flag.ContinueOnError)
	flags.SetOutput(stderr)
	frames := flags.Int("frames", 1, "simulation frames")
	dt := flags.Float64("dt", 0, "simulation delta (optional)")
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if len(flags.Args()) != 0 {
		return errors.New(
			"usage: recreatectl step [--frames N] [--dt SECONDS]",
		)
	}
	params := protocol.StepParams{Frames: *frames}
	if *dt != 0 {
		params.DT = dt
	}
	return call(protocol.MethodEmulationStep, params)
}

func runRawCall(
	call func(string, any) error,
	arguments []string,
) error {
	if len(arguments) < 1 || len(arguments) > 2 {
		return errors.New(
			"usage: recreatectl call METHOD [PARAMS_JSON]",
		)
	}
	params := json.RawMessage(`{}`)
	if len(arguments) == 2 {
		params = json.RawMessage(arguments[1])
		var object map[string]json.RawMessage
		if err := json.Unmarshal(params, &object); err != nil ||
			object == nil {
			return errors.New("PARAMS_JSON must be a JSON object")
		}
	}
	return call(arguments[0], params)
}

func captureScreenshot(
	ctx context.Context,
	client *protocol.Client,
	outputPath string,
	stdout io.Writer,
) error {
	var result struct {
		Data     string `json:"data"`
		Format   string `json:"format"`
		Width    int    `json:"width"`
		Height   int    `json:"height"`
		Tick     uint64 `json:"tick"`
		Revision uint64 `json:"revision"`
	}
	if err := client.Call(
		ctx,
		protocol.MethodPageCaptureScreenshot,
		nil,
		&result,
	); err != nil {
		return err
	}
	if result.Format != "png" && result.Format != "image/png" {
		return fmt.Errorf(
			"unsupported screenshot format %q",
			result.Format,
		)
	}
	decoded, err := base64.StdEncoding.DecodeString(result.Data)
	if err != nil {
		return fmt.Errorf("decode screenshot: %w", err)
	}
	if err := validateScreenshotPNG(
		decoded,
		result.Width,
		result.Height,
	); err != nil {
		return err
	}
	absolute, err := filepath.Abs(outputPath)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(absolute), 0o755); err != nil {
		return fmt.Errorf("create screenshot directory: %w", err)
	}
	if err := writeFileAtomically(absolute, decoded, 0o644); err != nil {
		return fmt.Errorf("write screenshot: %w", err)
	}
	_, err = fmt.Fprintf(
		stdout,
		"Screenshot: %s (%dx%d, tick %d, revision %d)\n",
		absolute,
		result.Width,
		result.Height,
		result.Tick,
		result.Revision,
	)
	return err
}

func validateScreenshotPNG(
	data []byte,
	reportedWidth int,
	reportedHeight int,
) error {
	const (
		maxDimension = 8192
		maxPixels    = 16 * 1024 * 1024
	)
	config, err := png.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		return fmt.Errorf("decode screenshot PNG header: %w", err)
	}
	if config.Width <= 0 ||
		config.Height <= 0 ||
		config.Width > maxDimension ||
		config.Height > maxDimension ||
		int64(config.Width)*int64(config.Height) > maxPixels {
		return fmt.Errorf(
			"screenshot dimensions %dx%d exceed safety limits",
			config.Width,
			config.Height,
		)
	}
	if reportedWidth != config.Width ||
		reportedHeight != config.Height {
		return fmt.Errorf(
			"screenshot metadata says %dx%d but PNG is %dx%d",
			reportedWidth,
			reportedHeight,
			config.Width,
			config.Height,
		)
	}
	if _, err := png.Decode(bytes.NewReader(data)); err != nil {
		return fmt.Errorf("decode complete screenshot PNG: %w", err)
	}
	return nil
}

func readJSONObject(
	path string,
	stdin io.Reader,
	limit int,
) (json.RawMessage, error) {
	var reader io.Reader
	if path == "-" {
		reader = stdin
	} else {
		file, err := os.Open(path)
		if err != nil {
			return nil, fmt.Errorf("open definition: %w", err)
		}
		defer file.Close()
		reader = file
	}
	data, err := io.ReadAll(io.LimitReader(reader, int64(limit)+1))
	if err != nil {
		return nil, fmt.Errorf("read definition: %w", err)
	}
	if len(data) > limit {
		return nil, errors.New("definition exceeds the request byte limit")
	}
	var object map[string]json.RawMessage
	if err := json.Unmarshal(data, &object); err != nil || object == nil {
		return nil, errors.New("definition must be a JSON object")
	}
	return json.RawMessage(data), nil
}

func writeFileAtomically(path string, data []byte, mode os.FileMode) error {
	directory := filepath.Dir(path)
	temporary, err := os.CreateTemp(directory, ".recreatectl-*")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	committed := false
	defer func() {
		_ = temporary.Close()
		if !committed {
			_ = os.Remove(temporaryPath)
		}
	}()
	if err := temporary.Chmod(mode); err != nil {
		return err
	}
	if _, err := temporary.Write(data); err != nil {
		return err
	}
	if err := temporary.Sync(); err != nil {
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		return err
	}
	committed = true
	return nil
}

func parseFiniteFloat(value, name string) (float64, error) {
	parsed, err := strconv.ParseFloat(value, 64)
	if err != nil ||
		strings.EqualFold(value, "nan") ||
		strings.Contains(strings.ToLower(value), "inf") {
		return 0, fmt.Errorf("%s must be a finite number", name)
	}
	return parsed, nil
}

func requireNoArgs(arguments []string, fn func() error) error {
	if len(arguments) != 0 {
		return errors.New("command does not accept arguments")
	}
	return fn()
}

func printRawJSON(writer io.Writer, raw json.RawMessage) error {
	var formatted bytes.Buffer
	if err := json.Indent(&formatted, raw, "", "  "); err != nil {
		return err
	}
	formatted.WriteByte('\n')
	_, err := writer.Write(formatted.Bytes())
	return err
}

func printUsage(writer io.Writer) {
	fmt.Fprint(writer, `recreatectl - Recreate Ebitengine debug controller

Usage:
  recreatectl [--address 127.0.0.1:19832] [--timeout 15s]
              [--token-file PATH] COMMAND

Authentication:
  Use a mode-0600 token file or set RECREATE_DEBUG_TOKEN.

Inspect:
  ping | protocol | state | graph | world
  definition CONTENT_ID
  validate CONTENT_ID FILE.json|-

Control:
  wall WALL_ID X Y WIDTH HEIGHT
  position ENTITY_ID X Y
  health ENTITY_ID VALUE
  ability ENTITY_ID ABILITY_ID
  action NAME [--value N] [--frames N]
  pause true|false
  step [--frames N] [--dt SECONDS]

Application:
  screenshot OUTPUT.png
  reload
  new-game
  save SLOT
  load SLOT
  quit
  call METHOD [PARAMS_JSON]
`)
}
