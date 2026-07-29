package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"

	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/gameapp"
	"practice_love2d/33_ebitengine_spike/internal/protocol"
	"practice_love2d/33_ebitengine_spike/internal/sim"
	"practice_love2d/33_ebitengine_spike/internal/storage"

	"github.com/hajimehoshi/ebiten/v2"
)

type options struct {
	catalog       string
	saveDirectory string
	debugAddress  string
	tokenFile     string
	noDebug       bool
	fullscreen    bool
	frames        uint64
	screenshot    string
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "recreate:", err)
		os.Exit(1)
	}
}

func run(arguments []string) error {
	defaultSaveDirectory, err := userSaveDirectory()
	if err != nil {
		return err
	}
	var options options
	flags := flag.NewFlagSet("recreate", flag.ContinueOnError)
	flags.StringVar(
		&options.catalog,
		"catalog",
		"",
		"development override for the embedded content catalog",
	)
	flags.StringVar(
		&options.saveDirectory,
		"save-dir",
		defaultSaveDirectory,
		"save-slot directory",
	)
	flags.StringVar(
		&options.debugAddress,
		"debug-address",
		protocol.DefaultAddress,
		"loopback debug protocol address",
	)
	flags.StringVar(
		&options.tokenFile,
		"token-file",
		"",
		"optional 0600 debug-token file",
	)
	flags.BoolVar(
		&options.noDebug,
		"no-debug",
		false,
		"disable the loopback debug protocol",
	)
	flags.BoolVar(
		&options.fullscreen,
		"fullscreen",
		false,
		"start in fullscreen mode",
	)
	flags.Uint64Var(
		&options.frames,
		"frames",
		0,
		"stop after a deterministic number of ticks",
	)
	flags.StringVar(
		&options.screenshot,
		"screenshot",
		"",
		"write the last automated frame to a PNG",
	)
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if len(flags.Args()) != 0 {
		return fmt.Errorf("unexpected arguments: %v", flags.Args())
	}

	store, err := storage.NewFileStore(options.saveDirectory)
	if err != nil {
		return err
	}
	runtime, err := gameapp.New(gameapp.Options{
		CatalogPath: options.catalog,
		Store:       store,
	})
	if err != nil {
		return err
	}
	game, err := ebitapp.NewWithOptions(runtime, ebitapp.Options{
		StopAfterTicks: options.frames,
		ScreenshotPath: options.screenshot,
	})
	if err != nil {
		return err
	}
	runtime.SetCapture(game.CapturePNG)

	ctx, cancel := context.WithCancel(context.Background())
	serverErrors := make(chan error, 1)
	if !options.noDebug {
		token, err := debugToken(options.tokenFile)
		if err != nil {
			cancel()
			return err
		}
		config := protocol.DefaultConfig()
		config.Address = options.debugAddress
		config.AuthToken = token
		server, err := protocol.NewServer(runtime, config)
		if err != nil {
			cancel()
			return err
		}
		listener, err := (&net.ListenConfig{}).Listen(
			ctx,
			"tcp",
			config.Address,
		)
		if err != nil {
			cancel()
			return fmt.Errorf("listen for debug protocol: %w", err)
		}
		go func() {
			serverErrors <- server.Serve(ctx, listener)
		}()
		fmt.Fprintf(
			os.Stderr,
			"debug protocol v%d: %s\n",
			protocol.Version,
			listener.Addr(),
		)
	}

	ebiten.SetTPS(sim.TicksPerSecond)
	ebiten.SetWindowSize(ebitapp.ScreenWidth, ebitapp.ScreenHeight)
	ebiten.SetWindowTitle("Recreate · Ebitengine spike")
	ebiten.SetWindowResizingMode(ebiten.WindowResizingModeEnabled)
	ebiten.SetFullscreen(options.fullscreen)
	runErr := ebiten.RunGame(game)
	cancel()
	if !options.noDebug {
		serverErr := <-serverErrors
		if runErr == nil && serverErr != nil {
			runErr = serverErr
		}
	}
	if errors.Is(runErr, ebiten.Termination) {
		return nil
	}
	return runErr
}

func userSaveDirectory() (string, error) {
	root, err := os.UserConfigDir()
	if err != nil {
		return "", fmt.Errorf("locate user config directory: %w", err)
	}
	return filepath.Join(root, "recreate-ebitengine", "saves"), nil
}

func debugToken(path string) (string, error) {
	if path == "" {
		return os.Getenv("RECREATE_DEBUG_TOKEN"), nil
	}
	info, err := os.Stat(path)
	if err != nil {
		return "", fmt.Errorf("inspect debug token file: %w", err)
	}
	if !info.Mode().IsRegular() {
		return "", errors.New("debug token file must be a regular file")
	}
	if info.Mode().Perm()&0o077 != 0 {
		return "", errors.New(
			"debug token file must not be readable by group or others",
		)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("read debug token file: %w", err)
	}
	token := strings.TrimSpace(string(data))
	if token == "" {
		return "", errors.New("debug token file is empty")
	}
	return token, nil
}
