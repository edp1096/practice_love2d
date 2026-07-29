package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"io"
	"net"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"practice_love2d/33_ebitengine_spike/internal/protocol"
)

type cliBackend struct {
	mutex              sync.Mutex
	calls              []protocol.Call
	screenshot         []byte
	screenshotWidth    int
	screenshotHeight   int
	screenshotTick     uint64
	screenshotRevision uint64
}

func (backend *cliBackend) Call(
	_ context.Context,
	call protocol.Call,
) (any, error) {
	backend.mutex.Lock()
	backend.calls = append(backend.calls, call)
	backend.mutex.Unlock()
	if call.Method == protocol.MethodPageCaptureScreenshot {
		data := backend.screenshot
		width := backend.screenshotWidth
		height := backend.screenshotHeight
		if data == nil {
			data = validTestPNG()
			width = 2
			height = 1
		}
		return map[string]any{
			"data":     base64.StdEncoding.EncodeToString(data),
			"format":   "png",
			"width":    width,
			"height":   height,
			"tick":     backend.screenshotTick,
			"revision": backend.screenshotRevision,
		}, nil
	}
	return map[string]any{"method": call.Method}, nil
}

func (backend *cliBackend) snapshot() []protocol.Call {
	backend.mutex.Lock()
	defer backend.mutex.Unlock()
	return append([]protocol.Call(nil), backend.calls...)
}

func TestCLIMapsUsefulCommandsToProtocol(t *testing.T) {
	backend := &cliBackend{
		screenshotTick:     42,
		screenshotRevision: 9,
	}
	address := startCLITestServer(t, backend)
	commands := [][]string{
		{"state"},
		{"graph"},
		{"definition", "actor.hero"},
		{"wall", "north", "0", "0", "960", "32"},
		{"position", "player", "10.5", "-2"},
		{"health", "player", "7"},
		{"ability", "player", "ability.parry"},
		{"action", "attack", "--value", "0.5", "--frames", "3"},
		{"pause", "true"},
		{"step", "--frames", "4", "--dt", "0.0166666667"},
		{"reload"},
		{"new-game"},
		{"save", "slot-1"},
		{"load", "slot-1"},
		{"quit"},
	}
	wantMethods := []string{
		protocol.MethodRuntimeGetState,
		protocol.MethodContentGetGraph,
		protocol.MethodContentGetDefinition,
		protocol.MethodWorldSetWall,
		protocol.MethodEntitySetPosition,
		protocol.MethodEntitySetHealth,
		protocol.MethodEntityRequestAbility,
		protocol.MethodInputAction,
		protocol.MethodEmulationSetPaused,
		protocol.MethodEmulationStep,
		protocol.MethodAppReloadContent,
		protocol.MethodAppStartNewGame,
		protocol.MethodAppSave,
		protocol.MethodAppLoad,
		protocol.MethodAppQuit,
	}

	for _, command := range commands {
		var output bytes.Buffer
		arguments := append([]string{"--address", address}, command...)
		if err := run(
			context.Background(),
			arguments,
			bytes.NewReader(nil),
			&output,
			&output,
		); err != nil {
			t.Fatalf("%v: %v", command, err)
		}
		if output.Len() == 0 {
			t.Fatalf("%v produced no output", command)
		}
	}
	calls := backend.snapshot()
	if len(calls) != len(wantMethods) {
		t.Fatalf("got %d calls, want %d", len(calls), len(wantMethods))
	}
	for index, want := range wantMethods {
		if calls[index].Method != want {
			t.Errorf(
				"call %d method = %q, want %q",
				index,
				calls[index].Method,
				want,
			)
		}
	}
	action := calls[7].Params.(protocol.InputActionParams)
	if action.Value != 0.5 || action.Frames != 3 {
		t.Fatalf("unexpected action params: %+v", action)
	}
	step := calls[9].Params.(protocol.StepParams)
	if step.Frames != 4 || step.DT == nil {
		t.Fatalf("unexpected step params: %+v", step)
	}
}

func TestCLIValidateAndScreenshot(t *testing.T) {
	backend := &cliBackend{
		screenshotTick:     42,
		screenshotRevision: 9,
	}
	address := startCLITestServer(t, backend)

	var output bytes.Buffer
	if err := run(
		context.Background(),
		[]string{
			"--address", address,
			"validate", "actor.hero", "-",
		},
		bytes.NewBufferString(`{"id":"actor.hero","kind":"actor"}`),
		&output,
		&output,
	); err != nil {
		t.Fatal(err)
	}
	calls := backend.snapshot()
	if len(calls) != 1 ||
		calls[0].Method != protocol.MethodContentValidateDefinition {
		t.Fatalf("unexpected validate call: %+v", calls)
	}
	params := calls[0].Params.(protocol.ValidateDefinitionParams)
	if string(params.Definition) !=
		`{"id":"actor.hero","kind":"actor"}` {
		t.Fatalf("definition changed: %s", params.Definition)
	}

	output.Reset()
	path := filepath.Join(t.TempDir(), "captures", "frame.png")
	if err := run(
		context.Background(),
		[]string{"--address", address, "screenshot", path},
		bytes.NewReader(nil),
		&output,
		&output,
	); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(data, validTestPNG()) {
		t.Fatalf("unexpected screenshot bytes: %q", data)
	}
	if !strings.Contains(output.String(), "tick 42, revision 9") {
		t.Fatalf("screenshot output omits capture identity: %q", output.String())
	}
}

func TestCLIRejectsTruncatedScreenshotAndMismatchedMetadata(t *testing.T) {
	for _, test := range []struct {
		name   string
		data   []byte
		width  int
		height int
	}{
		{
			name:   "truncated",
			data:   []byte("\x89PNG\r\n\x1a\nfake"),
			width:  2,
			height: 1,
		},
		{
			name:   "metadata mismatch",
			data:   validTestPNG(),
			width:  320,
			height: 180,
		},
	} {
		t.Run(test.name, func(t *testing.T) {
			backend := &cliBackend{
				screenshot:       test.data,
				screenshotWidth:  test.width,
				screenshotHeight: test.height,
			}
			address := startCLITestServer(t, backend)
			path := filepath.Join(t.TempDir(), "frame.png")
			err := run(
				context.Background(),
				[]string{"--address", address, "screenshot", path},
				bytes.NewReader(nil),
				io.Discard,
				io.Discard,
			)
			if err == nil {
				t.Fatal("invalid screenshot unexpectedly succeeded")
			}
			if _, statErr := os.Stat(path); !os.IsNotExist(statErr) {
				t.Fatalf("invalid screenshot was written: %v", statErr)
			}
		})
	}
}

func TestCLIRejectsUnsafeOrMalformedInput(t *testing.T) {
	cases := [][]string{
		{"--address", "0.0.0.0:19832", "state"},
		{"position", "player", "NaN", "1"},
		{"pause", "maybe"},
		{"validate", "actor.hero", "-"},
		{"call", "Runtime.getState", "[]"},
	}
	for _, arguments := range cases {
		t.Run(strings.Join(arguments, "_"), func(t *testing.T) {
			err := run(
				context.Background(),
				arguments,
				bytes.NewBufferString("[]"),
				io.Discard,
				io.Discard,
			)
			if err == nil {
				t.Fatalf("%v unexpectedly succeeded", arguments)
			}
		})
	}
}

func TestCLIUsesPrivateTokenFile(t *testing.T) {
	backend := &cliBackend{}
	address := startCLITestServerWithConfig(t, backend, protocol.Config{
		AuthToken: "private-cli-token",
	})
	tokenPath := filepath.Join(t.TempDir(), "debug.token")
	if err := os.WriteFile(
		tokenPath,
		[]byte("private-cli-token\n"),
		0o600,
	); err != nil {
		t.Fatal(err)
	}

	var output bytes.Buffer
	if err := run(
		context.Background(),
		[]string{
			"--address", address,
			"--token-file", tokenPath,
			"state",
		},
		bytes.NewReader(nil),
		&output,
		&output,
	); err != nil {
		t.Fatal(err)
	}
	if calls := backend.snapshot(); len(calls) != 1 {
		t.Fatalf("authenticated CLI calls = %d, want 1", len(calls))
	}

	t.Setenv("RECREATE_DEBUG_TOKEN", "private-cli-token")
	if err := run(
		context.Background(),
		[]string{"--address", address, "state"},
		bytes.NewReader(nil),
		io.Discard,
		io.Discard,
	); err != nil {
		t.Fatalf("environment token was not used: %v", err)
	}

	if err := os.Chmod(tokenPath, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := run(
		context.Background(),
		[]string{
			"--address", address,
			"--token-file", tokenPath,
			"state",
		},
		bytes.NewReader(nil),
		io.Discard,
		io.Discard,
	); err == nil {
		t.Fatal("CLI accepted a group/world-readable token file")
	}
}

func TestPrintRawJSONPreservesLargeIntegers(t *testing.T) {
	const raw = `{"tick":18446744073709551615}`
	var output bytes.Buffer
	if err := printRawJSON(&output, json.RawMessage(raw)); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(output.String(), "18446744073709551615") {
		t.Fatalf("large integer was changed: %s", output.String())
	}
}

func validTestPNG() []byte {
	source := image.NewRGBA(image.Rect(0, 0, 2, 1))
	source.SetRGBA(0, 0, color.RGBA{R: 255, A: 255})
	source.SetRGBA(1, 0, color.RGBA{G: 255, A: 255})
	var encoded bytes.Buffer
	if err := png.Encode(&encoded, source); err != nil {
		panic(err)
	}
	return encoded.Bytes()
}

func startCLITestServer(t *testing.T, backend protocol.Backend) string {
	return startCLITestServerWithConfig(t, backend, protocol.Config{})
}

func startCLITestServerWithConfig(
	t *testing.T,
	backend protocol.Backend,
	config protocol.Config,
) string {
	t.Helper()
	server, err := protocol.NewServer(backend, config)
	if err != nil {
		t.Fatal(err)
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- server.Serve(ctx, listener)
	}()
	t.Cleanup(func() {
		cancel()
		select {
		case err := <-done:
			if err != nil {
				t.Errorf("Serve returned an error: %v", err)
			}
		case <-time.After(2 * time.Second):
			t.Error("Serve did not stop")
		}
	})
	return listener.Addr().String()
}
