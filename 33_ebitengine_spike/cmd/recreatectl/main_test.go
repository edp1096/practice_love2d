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
		{"spawn", "actor.slime", "80.5", "-4.25", "preview.slime"},
		{"remove", "preview.slime"},
		{"position", "player", "10.5", "-2"},
		{"health", "player", "7"},
		{"ability", "player", "ability.parry"},
		{"encounter-start", "arena"},
		{"dialogue", "dialogue.guide", "guide"},
		{"dialogue-state"},
		{"dialogue-choose", "accept"},
		{"dialogue-advance"},
		{"campaign-state"},
		{"flow-state"},
		{"flow-move", "up"},
		{"flow-activate", "new_game"},
		{"shop-state"},
		{"shop-buy", "item.potion"},
		{"shop-sell", "item.potion", "2"},
		{"shop-close"},
		{"item-use", "item.potion"},
		{"equip", "item.sword"},
		{"unequip", "weapon"},
		{"action", "attack", "--value", "0.5", "--frames", "3"},
		{"pause", "true"},
		{"step", "--frames", "4", "--dt", "0.0166666667"},
		{"reload"},
		{"new-game", "stage.world_hub", "village_entry", "locale.ko"},
		{"save", "slot-1"},
		{"load", "slot-1"},
		{"quit"},
	}
	wantMethods := []string{
		protocol.MethodRuntimeGetState,
		protocol.MethodContentGetGraph,
		protocol.MethodContentGetDefinition,
		protocol.MethodWorldSetWall,
		protocol.MethodEntitySpawn,
		protocol.MethodEntityRemove,
		protocol.MethodEntitySetPosition,
		protocol.MethodEntitySetHealth,
		protocol.MethodEntityRequestAbility,
		protocol.MethodEncounterStart,
		protocol.MethodDialogueStart,
		protocol.MethodDialogueGetState,
		protocol.MethodDialogueChoose,
		protocol.MethodDialogueAdvance,
		protocol.MethodCampaignGetState,
		protocol.MethodFlowGetState,
		protocol.MethodFlowMove,
		protocol.MethodFlowActivate,
		protocol.MethodShopGetState,
		protocol.MethodShopBuy,
		protocol.MethodShopSell,
		protocol.MethodShopClose,
		protocol.MethodInventoryUse,
		protocol.MethodEquipmentEquip,
		protocol.MethodEquipmentUnequip,
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
	spawn := calls[4].Params.(protocol.SpawnEntityParams)
	if spawn.ActorID != "actor.slime" ||
		spawn.EntityID != "preview.slime" ||
		spawn.X == nil || *spawn.X != 80.5 ||
		spawn.Y == nil || *spawn.Y != -4.25 {
		t.Fatalf("unexpected spawn params: %+v", spawn)
	}
	dialogue := calls[10].Params.(protocol.StartDialogueParams)
	if dialogue.DialogueID != "dialogue.guide" ||
		dialogue.SpeakerID != "guide" {
		t.Fatalf("unexpected dialogue params: %+v", dialogue)
	}
	choice := calls[12].Params.(protocol.ChooseDialogueParams)
	if choice.ChoiceID != "accept" {
		t.Fatalf("unexpected dialogue choice params: %+v", choice)
	}
	flowMove := calls[16].Params.(protocol.FlowMoveParams)
	if flowMove.Delta != -1 {
		t.Fatalf("unexpected flow move params: %+v", flowMove)
	}
	flowActivate := calls[17].Params.(protocol.FlowActivateParams)
	if flowActivate.OptionID != "new_game" {
		t.Fatalf("unexpected flow activation params: %+v", flowActivate)
	}
	buy := calls[19].Params.(protocol.ShopTradeParams)
	if buy.ItemID != "item.potion" || buy.Quantity != 1 {
		t.Fatalf("unexpected shop buy params: %+v", buy)
	}
	sell := calls[20].Params.(protocol.ShopTradeParams)
	if sell.ItemID != "item.potion" || sell.Quantity != 2 {
		t.Fatalf("unexpected shop sell params: %+v", sell)
	}
	equip := calls[23].Params.(protocol.EquipmentEquipParams)
	if equip.ItemID != "item.sword" {
		t.Fatalf("unexpected equipment params: %+v", equip)
	}
	action := calls[25].Params.(protocol.InputActionParams)
	if action.Value != 0.5 || action.Frames != 3 {
		t.Fatalf("unexpected action params: %+v", action)
	}
	step := calls[27].Params.(protocol.StepParams)
	if step.Frames != 4 || step.DT == nil {
		t.Fatalf("unexpected step params: %+v", step)
	}
	newGame := calls[29].Params.(protocol.StartNewGameParams)
	if newGame.StageID != "stage.world_hub" ||
		newGame.SpawnID != "village_entry" ||
		newGame.LocaleID != "locale.ko" {
		t.Fatalf("unexpected new-game params: %+v", newGame)
	}
}

func TestCLIMakerPreviewOptionalDefaults(t *testing.T) {
	backend := &cliBackend{}
	address := startCLITestServer(t, backend)
	for _, command := range [][]string{
		{"spawn", "actor.slime"},
		{"dialogue", "dialogue.guide"},
	} {
		arguments := append([]string{"--address", address}, command...)
		if err := run(
			context.Background(),
			arguments,
			bytes.NewReader(nil),
			io.Discard,
			io.Discard,
		); err != nil {
			t.Fatalf("%v: %v", command, err)
		}
	}
	calls := backend.snapshot()
	if len(calls) != 2 {
		t.Fatalf("got %d calls, want 2", len(calls))
	}
	spawn := calls[0].Params.(protocol.SpawnEntityParams)
	if spawn.EntityID != "" || spawn.X != nil || spawn.Y != nil {
		t.Fatalf("spawn defaults were not preserved: %+v", spawn)
	}
	dialogue := calls[1].Params.(protocol.StartDialogueParams)
	if dialogue.SpeakerID != "" {
		t.Fatalf("dialogue speaker should be optional: %+v", dialogue)
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
		{"spawn", "actor.slime", "10"},
		{"spawn", "actor.slime", "NaN", "1"},
		{"remove"},
		{"dialogue"},
		{"dialogue", "dialogue.guide", "guide", "extra"},
		{"dialogue-state", "extra"},
		{"dialogue-choose"},
		{"dialogue-choose", "accept", "extra"},
		{"dialogue-advance", "extra"},
		{"campaign-state", "extra"},
		{"flow-state", "extra"},
		{"flow-move"},
		{"flow-move", "left"},
		{"flow-move", "up", "extra"},
		{"flow-activate"},
		{"flow-activate", "new_game", "extra"},
		{"shop-state", "extra"},
		{"shop-buy"},
		{"shop-buy", "item.potion", "1", "extra"},
		{"shop-buy", "item.potion", "null"},
		{"shop-buy", "item.potion", "1.5"},
		{"shop-buy", "item.potion", "0"},
		{"shop-buy", "item.potion", "-1"},
		{"shop-buy", "item.potion", "9007199254740992"},
		{"shop-sell"},
		{"shop-sell", "item.potion", "1.5"},
		{"shop-close", "extra"},
		{"item-use"},
		{"item-use", "item.potion", "extra"},
		{"equip"},
		{"equip", "item.sword", "extra"},
		{"unequip"},
		{"unequip", "weapon", "extra"},
		{"new-game", "stage.village", "default", "locale.ko", "extra"},
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
