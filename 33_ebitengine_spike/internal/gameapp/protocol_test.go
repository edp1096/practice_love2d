package gameapp

import (
	"context"
	"net"
	"path/filepath"
	"testing"
	"time"

	"practice_love2d/33_ebitengine_spike/internal/protocol"
	"practice_love2d/33_ebitengine_spike/internal/storage"
)

func TestProtocolDrivesRuntimeWithoutPresentationWindow(t *testing.T) {
	store, err := storage.NewFileStore(filepath.Join(t.TempDir(), "saves"))
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{Store: store})
	if err != nil {
		t.Fatal(err)
	}
	server, err := protocol.NewServer(runtime, protocol.Config{})
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
		if err := <-done; err != nil {
			t.Errorf("server shutdown: %v", err)
		}
	})
	client, err := protocol.NewClient(protocol.ClientConfig{
		Address: listener.Addr().String(),
		Timeout: 2 * time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}

	call := func(method string, params any, target any) {
		t.Helper()
		if err := client.Call(
			context.Background(),
			method,
			params,
			target,
		); err != nil {
			t.Fatalf("%s: %v", method, err)
		}
	}
	call(
		protocol.MethodEmulationSetPaused,
		protocol.SetPausedParams{Enabled: true},
		nil,
	)
	call(
		protocol.MethodInputAction,
		protocol.InputActionParams{
			Action: "move_right",
			Value:  1,
			Frames: 12,
		},
		nil,
	)
	call(
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 12},
		nil,
	)
	var world worldSnapshotDTO
	call(protocol.MethodWorldGetSnapshot, nil, &world)
	if world.Tick != 12 || worldEntity(t, world, "player").X <= 150 {
		t.Fatalf("protocol did not drive simulation: %#v", world)
	}
	call(
		protocol.MethodWorldSetWall,
		protocol.SetWallParams{
			WallID: "north",
			X:      0,
			Y:      0,
			Width:  960,
			Height: 24,
		},
		nil,
	)
	var dialogue startDialogueResult
	call(
		protocol.MethodDialogueStart,
		protocol.StartDialogueParams{DialogueID: "dialogue.guide"},
		&dialogue,
	)
	if !dialogue.Applied || dialogue.NodeID != "greeting" {
		t.Fatalf("wire dialogue preview = %#v", dialogue)
	}
	call(
		protocol.MethodInputAction,
		protocol.InputActionParams{
			Action: "interact",
			Value:  1,
			Frames: 1,
		},
		nil,
	)
	call(
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 1},
		nil,
	)
	spawnX, spawnY := 520.0, 270.0
	var spawned entityDTO
	call(
		protocol.MethodEntitySpawn,
		protocol.SpawnEntityParams{
			ActorID:  "actor.slime",
			EntityID: "wire.preview",
			X:        &spawnX,
			Y:        &spawnY,
		},
		&spawned,
	)
	if spawned.ID != "wire.preview" ||
		spawned.ActorID != "actor.slime" {
		t.Fatalf("wire entity preview = %#v", spawned)
	}
	var removal removeEntityResult
	call(
		protocol.MethodEntityRemove,
		protocol.RemoveEntityParams{EntityID: spawned.ID},
		&removal,
	)
	if !removal.Queued {
		t.Fatalf("wire entity removal = %#v", removal)
	}
	call(protocol.MethodWorldGetSnapshot, nil, &world)
	if world.Count != 6 {
		t.Fatalf("queued wire removal flushed early: count=%d", world.Count)
	}
	call(
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 1},
		nil,
	)
	call(protocol.MethodWorldGetSnapshot, nil, &world)
	if world.Count != 5 {
		t.Fatalf("wire removal did not flush: count=%d", world.Count)
	}
	savedTick := world.Tick
	call(
		protocol.MethodAppSave,
		protocol.SaveSlotParams{Slot: "wire"},
		nil,
	)
	call(protocol.MethodAppStartNewGame, nil, nil)
	call(
		protocol.MethodAppLoad,
		protocol.SaveSlotParams{Slot: "wire"},
		nil,
	)
	call(protocol.MethodWorldGetSnapshot, nil, &world)
	if world.Tick != savedTick {
		t.Fatalf(
			"wire save/load tick = %d, want %d",
			world.Tick,
			savedTick,
		)
	}

	call(protocol.MethodAppQuit, nil, nil)
	deadline := time.Now().Add(time.Second)
	for !runtime.View().Quit && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if !runtime.View().Quit {
		t.Fatal("quit acknowledgement did not reach runtime")
	}
}
