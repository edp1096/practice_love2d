//go:build js && wasm

package main

import (
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/gameapp"
	"practice_love2d/33_ebitengine_spike/internal/sim"
	"practice_love2d/33_ebitengine_spike/internal/storage"

	"github.com/hajimehoshi/ebiten/v2"
)

func main() {
	if err := runWeb(); err != nil {
		panic(err)
	}
}

func runWeb() error {
	store, err := storage.NewBrowserStore("recreate.maker_runtime")
	if err != nil {
		return fmt.Errorf("create browser save store: %w", err)
	}
	runtime, err := gameapp.New(gameapp.Options{
		Store:        store,
		StartAtTitle: true,
	})
	if err != nil {
		return err
	}
	game, err := ebitapp.New(runtime)
	if err != nil {
		return err
	}
	runtime.SetCapture(game.CapturePNG)

	ebiten.SetTPS(sim.TicksPerSecond)
	ebiten.SetWindowSize(ebitapp.ScreenWidth, ebitapp.ScreenHeight)
	ebiten.SetWindowTitle("고요한 숲의 수호자 · Recreate")
	ebiten.SetWindowResizingMode(ebiten.WindowResizingModeEnabled)
	return ebiten.RunGame(game)
}
