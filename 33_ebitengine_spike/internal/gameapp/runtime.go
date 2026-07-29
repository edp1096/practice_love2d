// Package gameapp joins authored content, the deterministic simulation,
// Ebitengine presentation, durable storage, and the loopback debug protocol.
//
// The package deliberately owns no platform APIs. Desktop and console entry
// points can provide different storage and presentation adapters while sharing
// the same game state and automation contract.
package gameapp

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"sync"

	gamecatalog "practice_love2d/33_ebitengine_spike/game"
	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/sim"
	"practice_love2d/33_ebitengine_spike/internal/storage"
)

type CaptureFunc func(context.Context) (ebitapp.Capture, error)

type Options struct {
	CatalogPath string
	Build       gamebuild.Options
	Store       storage.Store
}

type virtualAction struct {
	value     float64
	remaining int
	fresh     bool
}

type previewEntity struct {
	config   sim.EntityConfig
	metadata gamebuild.InstanceMetadata
}

// Runtime serializes every mutable simulation operation. Ebitengine's update
// goroutine and protocol connection goroutines may call it concurrently.
type Runtime struct {
	mu sync.RWMutex

	catalogPath  string
	buildOptions gamebuild.Options
	catalog      *content.Catalog
	built        *gamebuild.Result
	simulation   *sim.Simulation
	store        storage.Store

	paused      bool
	quit        bool
	quitPending bool
	revision    uint64

	virtual          map[string]virtualAction
	pendingAbilities map[string]bool
	pendingRemovals  map[string]bool
	moving           map[string]bool

	previewSequence uint64
	previewEntities map[string]previewEntity

	captureMu sync.RWMutex
	capture   CaptureFunc
}

func New(options Options) (*Runtime, error) {
	if options.Store == nil {
		return nil, errors.New("gameapp: storage is required")
	}
	catalog, err := loadCatalog(options.CatalogPath)
	if err != nil {
		return nil, err
	}
	built, simulation, err := buildSimulation(catalog, options.Build)
	if err != nil {
		return nil, err
	}
	runtime := &Runtime{
		catalogPath:      options.CatalogPath,
		buildOptions:     options.Build,
		catalog:          catalog,
		built:            built,
		simulation:       simulation,
		store:            options.Store,
		virtual:          make(map[string]virtualAction),
		pendingAbilities: make(map[string]bool),
		pendingRemovals:  make(map[string]bool),
		moving:           make(map[string]bool),
		revision:         1,
	}
	runtime.resetPreviewLocked()
	return runtime, nil
}

func loadCatalog(path string) (*content.Catalog, error) {
	if path == "" {
		return content.LoadBytes(gamecatalog.Bytes())
	}
	return content.LoadFile(path)
}

func buildSimulation(
	catalog *content.Catalog,
	options gamebuild.Options,
) (*gamebuild.Result, *sim.Simulation, error) {
	built, err := gamebuild.Build(catalog, options)
	if err != nil {
		return nil, nil, fmt.Errorf("build game content: %w", err)
	}
	simulation, err := sim.New(built.Config)
	if err != nil {
		return nil, nil, fmt.Errorf("construct simulation: %w", err)
	}
	return built, simulation, nil
}

// SetCapture connects Page.captureScreenshot after the Ebitengine game owns
// its canvas. It uses a separate lock because capture waits for Draw, which in
// turn calls View and takes Runtime.mu.
func (runtime *Runtime) SetCapture(capture CaptureFunc) {
	runtime.captureMu.Lock()
	runtime.capture = capture
	runtime.captureMu.Unlock()
}

func (runtime *Runtime) capturePNG(
	ctx context.Context,
) (ebitapp.Capture, error) {
	runtime.captureMu.RLock()
	capture := runtime.capture
	runtime.captureMu.RUnlock()
	if capture == nil {
		return ebitapp.Capture{}, errors.New("screen capture is not connected")
	}
	return capture(ctx)
}

func (runtime *Runtime) reloadContent(ctx context.Context) error {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()

	if err := ctx.Err(); err != nil {
		return err
	}
	if runtime.simulation.HasTemporaryPreview() ||
		len(runtime.pendingRemovals) != 0 {
		return errors.New(
			"reload is unavailable while temporary Maker preview state is active; start a new game first",
		)
	}
	catalog, err := loadCatalog(runtime.catalogPath)
	if err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	built, candidate, err := buildSimulation(catalog, runtime.buildOptions)
	if err != nil {
		return err
	}
	state := runtime.simulation.SaveSession()
	if err := candidate.LoadSession(state); err != nil {
		return fmt.Errorf(
			"reload is incompatible with the active session: %w",
			err,
		)
	}
	runtime.catalog = catalog
	runtime.built = built
	runtime.simulation = candidate
	runtime.virtual = make(map[string]virtualAction)
	runtime.pendingAbilities = make(map[string]bool)
	runtime.pendingRemovals = make(map[string]bool)
	runtime.moving = make(map[string]bool)
	runtime.resetPreviewLocked()
	runtime.revision++
	return nil
}

func (runtime *Runtime) startNewGame(ctx context.Context) error {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()

	if err := ctx.Err(); err != nil {
		return err
	}
	catalog, err := loadCatalog(runtime.catalogPath)
	if err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	built, simulation, err := buildSimulation(catalog, runtime.buildOptions)
	if err != nil {
		return err
	}
	runtime.catalog = catalog
	runtime.built = built
	runtime.simulation = simulation
	runtime.virtual = make(map[string]virtualAction)
	runtime.pendingAbilities = make(map[string]bool)
	runtime.pendingRemovals = make(map[string]bool)
	runtime.moving = make(map[string]bool)
	runtime.resetPreviewLocked()
	runtime.revision++
	return nil
}

func (runtime *Runtime) resetLocked() error {
	candidate, err := sim.New(runtime.built.Config)
	if err != nil {
		return err
	}
	runtime.simulation = candidate
	runtime.virtual = make(map[string]virtualAction)
	runtime.pendingAbilities = make(map[string]bool)
	runtime.pendingRemovals = make(map[string]bool)
	runtime.moving = make(map[string]bool)
	runtime.resetPreviewLocked()
	runtime.revision++
	return nil
}

func (runtime *Runtime) entityConfig(id string) (sim.EntityConfig, bool) {
	if preview, ok := runtime.previewEntities[id]; ok {
		return preview.config, true
	}
	for _, definition := range runtime.built.Config.Entities {
		if definition.ID == id {
			return definition, true
		}
	}
	return sim.EntityConfig{}, false
}

func (runtime *Runtime) metadata(id string) (gamebuild.InstanceMetadata, bool) {
	if preview, ok := runtime.previewEntities[id]; ok {
		metadata := preview.metadata
		metadata.Tags = append([]string(nil), metadata.Tags...)
		return metadata, true
	}
	return runtime.built.Presentation.Instance(id)
}

func (runtime *Runtime) resetPreviewLocked() {
	runtime.previewSequence = uint64(len(runtime.built.Config.Entities))
	runtime.previewEntities = make(map[string]previewEntity)
}

func (runtime *Runtime) allMetadataLocked() []gamebuild.InstanceMetadata {
	result := make(
		[]gamebuild.InstanceMetadata,
		0,
		len(runtime.built.Presentation.Instances)+len(runtime.previewEntities),
	)
	result = append(result, runtime.built.Presentation.Instances...)
	previewIDs := make([]string, 0, len(runtime.previewEntities))
	for id := range runtime.previewEntities {
		previewIDs = append(previewIDs, id)
	}
	sort.Strings(previewIDs)
	for _, id := range previewIDs {
		result = append(result, runtime.previewEntities[id].metadata)
	}
	return result
}
