// Command webaccept boots a generated browser bundle in an isolated headless
// Chromium process and verifies that Ebitengine rendered its logical canvas.
package main

import (
	"bytes"
	"context"
	"errors"
	"flag"
	"fmt"
	"image"
	"image/png"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"practice_love2d/33_ebitengine_spike/internal/webdist"
)

type options struct {
	root       string
	browser    string
	screenshot string
	timeout    time.Duration
}

func main() {
	if err := run(
		context.Background(),
		os.Args[1:],
		os.Stdout,
		os.Stderr,
	); err != nil {
		fmt.Fprintln(os.Stderr, "webaccept:", err)
		os.Exit(1)
	}
}

func run(
	parent context.Context,
	arguments []string,
	stdout io.Writer,
	stderr io.Writer,
) error {
	var options options
	flags := flag.NewFlagSet("webaccept", flag.ContinueOnError)
	flags.SetOutput(stderr)
	flags.StringVar(&options.root, "root", "dist/web", "generated web bundle")
	flags.StringVar(
		&options.browser,
		"browser",
		"",
		"Chromium executable; auto-detected when empty",
	)
	flags.StringVar(
		&options.screenshot,
		"screenshot",
		"",
		"optional retained PNG path",
	)
	flags.DurationVar(
		&options.timeout,
		"timeout",
		40*time.Second,
		"whole browser acceptance deadline",
	)
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if len(flags.Args()) != 0 {
		return errors.New(
			"usage: webaccept [-root dist/web] [-browser PATH] " +
				"[-screenshot FILE.png] [-timeout 40s]",
		)
	}
	if options.timeout < time.Second || options.timeout > 5*time.Minute {
		return errors.New("web acceptance timeout must be between 1s and 5m")
	}
	root, err := webdist.Verify(options.root)
	if err != nil {
		return err
	}
	browser, err := browserPath(options.browser)
	if err != nil {
		return err
	}
	temporary, err := os.MkdirTemp("", "recreate-web-accept-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(temporary)

	screenshot := options.screenshot
	if screenshot == "" {
		screenshot = filepath.Join(temporary, "screen.png")
	} else {
		screenshot, err = filepath.Abs(screenshot)
		if err != nil {
			return err
		}
		if filepath.Ext(screenshot) != ".png" {
			return errors.New("web acceptance screenshot must use .png")
		}
		if err := os.MkdirAll(filepath.Dir(screenshot), 0o755); err != nil {
			return err
		}
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return err
	}
	server := &http.Server{
		Handler:           webdist.Handler(root),
		ReadHeaderTimeout: 5 * time.Second,
	}
	serverDone := make(chan error, 1)
	go func() {
		serverDone <- server.Serve(listener)
	}()
	defer func() {
		shutdown, cancel := context.WithTimeout(
			context.Background(),
			2*time.Second,
		)
		defer cancel()
		_ = server.Shutdown(shutdown)
		<-serverDone
	}()

	ctx, cancel := context.WithTimeout(parent, options.timeout)
	defer cancel()
	address := "http://" + listener.Addr().String() + "/"
	var dom bytes.Buffer
	var browserLog bytes.Buffer
	command := exec.CommandContext(
		ctx,
		browser,
		"--headless",
		"--no-sandbox",
		"--disable-dev-shm-usage",
		"--disable-background-networking",
		"--disable-component-update",
		"--use-gl=swiftshader",
		"--enable-webgl",
		"--ignore-gpu-blocklist",
		"--window-size=960,540",
		"--virtual-time-budget=10000",
		"--user-data-dir="+filepath.Join(temporary, "profile"),
		"--screenshot="+screenshot,
		"--dump-dom",
		address,
	)
	command.Stdout = &dom
	command.Stderr = &browserLog
	if err := command.Run(); err != nil {
		if ctx.Err() != nil {
			return fmt.Errorf("headless browser deadline: %w", ctx.Err())
		}
		return fmt.Errorf(
			"headless browser failed: %w\n%s",
			err,
			tail(browserLog.String(), 2000),
		)
	}
	if !strings.Contains(dom.String(), `data-recreate-ready="true"`) {
		return fmt.Errorf(
			"browser runtime did not become ready\n%s",
			tail(dom.String(), 2000),
		)
	}
	if !strings.Contains(dom.String(), `<canvas width="960" height="540"`) {
		return errors.New("browser runtime did not create the 960x540 canvas")
	}
	file, err := os.Open(screenshot)
	if err != nil {
		return fmt.Errorf("open browser screenshot: %w", err)
	}
	screen, err := png.Decode(file)
	closeError := file.Close()
	if err != nil {
		return fmt.Errorf("decode browser screenshot: %w", err)
	}
	if closeError != nil {
		return closeError
	}
	if err := verifyRenderedImage(screen); err != nil {
		return err
	}
	bounds := screen.Bounds()
	if bounds.Dx() != 960 || bounds.Dy() != 540 {
		return fmt.Errorf(
			"browser screenshot is %dx%d, want 960x540",
			bounds.Dx(),
			bounds.Dy(),
		)
	}
	fmt.Fprintf(
		stdout,
		"web acceptance passed (%s, canvas %dx%d)\n",
		filepath.Base(browser),
		bounds.Dx(),
		bounds.Dy(),
	)
	if options.screenshot != "" {
		fmt.Fprintf(stdout, "web screenshot %s\n", screenshot)
	}
	return nil
}

func verifyRenderedImage(screen image.Image) error {
	bounds := screen.Bounds()
	if bounds.Dx() != 960 || bounds.Dy() != 540 {
		return fmt.Errorf(
			"browser screenshot is %dx%d, want 960x540",
			bounds.Dx(),
			bounds.Dy(),
		)
	}
	// Exclude the web controls in the lower-right corner. The remaining
	// central canvas must contain enough light pixels to prove the game
	// rendered more than a cleared framebuffer.
	region := image.Rect(
		bounds.Min.X+80,
		bounds.Min.Y+40,
		bounds.Min.X+840,
		bounds.Min.Y+480,
	)
	bright := 0
	for y := region.Min.Y; y < region.Max.Y; y++ {
		for x := region.Min.X; x < region.Max.X; x++ {
			red, green, blue, _ := screen.At(x, y).RGBA()
			if red+green+blue >= 3*0x6000 {
				bright++
			}
		}
	}
	if bright < 500 {
		return fmt.Errorf(
			"browser canvas appears blank: only %d bright pixels",
			bright,
		)
	}
	return nil
}

func browserPath(requested string) (string, error) {
	if requested != "" {
		path, err := exec.LookPath(requested)
		if err != nil {
			return "", fmt.Errorf("find requested browser: %w", err)
		}
		return path, nil
	}
	for _, name := range []string{
		"chromium-browser",
		"chromium",
		"google-chrome",
		"google-chrome-stable",
	} {
		if path, err := exec.LookPath(name); err == nil {
			return path, nil
		}
	}
	return "", errors.New("Chromium browser was not found")
}

func tail(value string, limit int) string {
	if len(value) <= limit {
		return value
	}
	return value[len(value)-limit:]
}
