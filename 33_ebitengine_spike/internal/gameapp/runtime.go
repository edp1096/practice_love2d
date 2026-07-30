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
	"reflect"
	"sort"
	"sync"

	gamecatalog "practice_love2d/33_ebitengine_spike/game"
	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/protocol"
	"practice_love2d/33_ebitengine_spike/internal/rulesruntime"
	"practice_love2d/33_ebitengine_spike/internal/sim"
	"practice_love2d/33_ebitengine_spike/internal/storage"
)

type CaptureFunc func(context.Context) (ebitapp.Capture, error)

type Options struct {
	CatalogPath string
	Build       gamebuild.Options
	Store       storage.Store
	// StartAtTitle enables the authored game-flow entry screen. Fixture and
	// low-level simulation tests may leave it false to enter Build directly.
	StartAtTitle bool
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

type queuedAudioCue struct {
	sequence uint64
	event    string
	assetID  string
	volume   float64
}

type behaviorAIState struct {
	PatternID   string
	AttackIndex int
}

type runtimeCheckpoint struct {
	buildOptions gamebuild.Options
	built        *gamebuild.Result
	simulation   *sim.Simulation
	campaign     *campaign.Campaign
	dialogue     *rulesruntime.DialogueSession

	virtual          map[string]virtualAction
	pendingAbilities map[string]string
	behaviorAI       map[string]behaviorAIState
	pendingRemovals  map[string]bool
	moving           map[string]bool
	audioSequence    uint64
	audioCues        []queuedAudioCue

	previewSequence uint64
	previewEntities map[string]previewEntity

	dialogueSpeakerID       string
	dialogueChoiceIndex     int
	activeShopID            string
	shopSelectedIndex       int
	shopStatus              string
	inventoryOpen           bool
	inventorySelected       int
	inventoryStatus         string
	equipmentRebuildPending bool
	flowSelectedIndex       int
	flowStatus              string
	flowPanel               string
	continueAvailable       bool
	notice                  ebitapp.NoticeView
	turnBattle              *turnBattleSession
	cutscene                *cutsceneSession

	portalCooldownTicks int
	portalInside        map[string]bool
	triggerInside       map[string]bool
	triggerCooldowns    map[string]int
	triggerFired        map[string]bool
	worldInitialized    bool
	worldActivePage     string
	worldActiveRegions  map[string]bool
	revision            uint64
}

// Runtime serializes every mutable simulation operation. Ebitengine's update
// goroutine and protocol connection goroutines may call it concurrently.
type Runtime struct {
	mu sync.RWMutex

	catalogPath    string
	buildOverrides gamebuild.Options
	buildOptions   gamebuild.Options
	catalog        *content.Catalog
	campaignConfig campaign.Config
	campaign       *campaign.Campaign
	contentRules   gamebuild.ContentRules
	ruleExecutor   *rulesruntime.Executor
	built          *gamebuild.Result
	simulation     *sim.Simulation
	store          storage.Store

	// automationPaused is controlled only by Emulation.*. Semantic
	// title/pause/gameover UI belongs to the campaign flow controller and
	// must never reuse this clock gate.
	automationPaused bool
	quit             bool
	quitPending      bool
	revision         uint64

	virtual          map[string]virtualAction
	pendingAbilities map[string]string
	behaviorAI       map[string]behaviorAIState
	pendingRemovals  map[string]bool
	moving           map[string]bool
	audioSequence    uint64
	audioCues        []queuedAudioCue

	previewSequence uint64
	previewEntities map[string]previewEntity

	dialogue                *rulesruntime.DialogueSession
	dialogueSpeakerID       string
	dialogueChoiceIndex     int
	activeShopID            string
	shopSelectedIndex       int
	shopStatus              string
	inventoryOpen           bool
	inventorySelected       int
	inventoryStatus         string
	equipmentRebuildPending bool
	flowSelectedIndex       int
	flowStatus              string
	flowPanel               string
	continueAvailable       bool
	notice                  ebitapp.NoticeView
	turnBattle              *turnBattleSession
	cutscene                *cutsceneSession

	portalCooldownTicks int
	portalInside        map[string]bool
	triggerInside       map[string]bool
	triggerCooldowns    map[string]int
	triggerFired        map[string]bool
	worldInitialized    bool
	worldActivePage     string
	worldActiveRegions  map[string]bool

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
	resolved := resolveBuildOptions(catalog, options.Build)
	campaignConfig, err := gamebuild.BuildCampaignConfig(catalog)
	if err != nil {
		return nil, err
	}
	contentRules, ruleExecutor, err := buildRuleRuntime(
		catalog,
		campaignConfig,
	)
	if err != nil {
		return nil, err
	}
	var seedCampaign *campaign.Campaign
	if options.StartAtTitle {
		seedCampaign, err = campaign.NewTitle(campaignConfig)
	} else {
		seedCampaign, err = campaign.NewGame(campaignConfig)
	}
	if err != nil {
		return nil, err
	}
	built, simulation, err := buildCampaignSimulation(
		catalog,
		resolved,
		seedCampaign.Snapshot(),
		contentRules,
	)
	if err != nil {
		return nil, err
	}
	activeCampaign := seedCampaign
	if !options.StartAtTitle {
		activeCampaign, err = newCampaignForWorld(
			campaignConfig,
			built,
			resolved,
		)
		if err != nil {
			return nil, err
		}
	}
	portalInside, err := portalOverlaps(built, simulation)
	if err != nil {
		return nil, fmt.Errorf("seed initial portal latch: %w", err)
	}
	runtime := &Runtime{
		catalogPath:        options.CatalogPath,
		buildOverrides:     options.Build,
		buildOptions:       resolved,
		catalog:            catalog,
		campaignConfig:     campaignConfig,
		campaign:           activeCampaign,
		contentRules:       contentRules,
		ruleExecutor:       ruleExecutor,
		built:              built,
		simulation:         simulation,
		store:              options.Store,
		virtual:            make(map[string]virtualAction),
		pendingAbilities:   make(map[string]string),
		behaviorAI:         make(map[string]behaviorAIState),
		pendingRemovals:    make(map[string]bool),
		moving:             make(map[string]bool),
		audioCues:          make([]queuedAudioCue, 0),
		portalInside:       portalInside,
		triggerInside:      make(map[string]bool),
		triggerCooldowns:   make(map[string]int),
		triggerFired:       make(map[string]bool),
		worldActiveRegions: make(map[string]bool),
		revision:           1,
	}
	runtime.resetPreviewLocked()
	saved, available := runtime.validContinueCampaignLocked()
	runtime.continueAvailable = available
	if options.StartAtTitle && available {
		settings := saved.Snapshot().Accessibility
		if err := runtime.campaign.Transaction(
			func(state *campaign.State) error {
				state.Accessibility = settings
				return nil
			},
		); err != nil {
			return nil, fmt.Errorf(
				"restore title accessibility settings: %w",
				err,
			)
		}
	}
	return runtime, nil
}

func loadCatalog(path string) (*content.Catalog, error) {
	if path == "" {
		return content.LoadBytes(gamecatalog.Bytes())
	}
	return content.LoadFile(path)
}

func resolveBuildOptions(
	catalog *content.Catalog,
	overrides gamebuild.Options,
) gamebuild.Options {
	resolved := overrides
	project := catalog.Project()
	if resolved.StageID == "" {
		resolved.StageID = project.Flow.StartStage
	}
	if resolved.SpawnID == "" &&
		resolved.StageID == project.Flow.StartStage {
		resolved.SpawnID = project.Flow.StartSpawn
	}
	if resolved.LocaleID == "" {
		resolved.LocaleID = project.Locale.Default
	}
	return resolved
}

// buildValidationSimulation constructs a stateless definition-validation
// preview. Player-owned Worlds must use buildCampaignSimulation instead.
func buildValidationSimulation(
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

func newCampaignForWorld(
	config campaign.Config,
	built *gamebuild.Result,
	options gamebuild.Options,
) (*campaign.Campaign, error) {
	active, err := campaign.NewGame(config)
	if err != nil {
		return nil, err
	}
	entrySpawnID, err := campaignEntrySpawn(built, options)
	if err != nil {
		return nil, err
	}
	state := active.Snapshot()
	if state.CurrentStageID == built.Stage.ID &&
		state.EntrySpawnID == entrySpawnID &&
		state.Locale == options.LocaleID {
		return active, nil
	}
	if err := active.Transaction(func(state *campaign.State) error {
		state.CurrentStageID = built.Stage.ID
		state.EntrySpawnID = entrySpawnID
		state.Locale = options.LocaleID
		return nil
	}); err != nil {
		return nil, fmt.Errorf(
			"align campaign with initial world %s/%s: %w",
			built.Stage.ID,
			entrySpawnID,
			err,
		)
	}
	return active, nil
}

func campaignEntrySpawn(
	built *gamebuild.Result,
	options gamebuild.Options,
) (string, error) {
	if options.SpawnID != "" {
		return options.SpawnID, nil
	}
	if len(built.Stage.SpawnPoints) == 0 {
		return "default", nil
	}

	var controlled *sim.EntityConfig
	for index := range built.Config.Entities {
		if built.Config.Entities[index].Controlled {
			controlled = &built.Config.Entities[index]
			break
		}
	}
	if controlled != nil {
		matched := ""
		for _, spawn := range built.Stage.SpawnPoints {
			if spawn.Position != controlled.Position {
				continue
			}
			if matched != "" {
				return "", fmt.Errorf(
					"stage %q has multiple entry spawns at the authored player position; an explicit spawn is required",
					built.Stage.ID,
				)
			}
			matched = spawn.ID
		}
		if matched != "" {
			return matched, nil
		}
	}
	return "", fmt.Errorf(
		"stage %q has no entry spawn at the authored player position; an explicit spawn is required",
		built.Stage.ID,
	)
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
	campaignConfig, err := gamebuild.BuildCampaignConfig(catalog)
	if err != nil {
		return err
	}
	contentRules, ruleExecutor, err := buildRuleRuntime(
		catalog,
		campaignConfig,
	)
	if err != nil {
		return err
	}
	campaignState := runtime.campaign.Snapshot()
	if err := validateCampaignReloadTopology(
		runtime.campaignConfig,
		campaignConfig,
	); err != nil {
		return err
	}
	resolved := runtime.buildOptions
	if campaignState.Flow.Started {
		resolved.StageID = campaignState.CurrentStageID
		resolved.SpawnID = campaignState.EntrySpawnID
		resolved.LocaleID = campaignState.Locale
	} else {
		resolved = resolveBuildOptions(catalog, runtime.buildOverrides)
		resolved.LocaleID = campaignState.Locale
	}
	if campaignState.Locale == runtime.campaignConfig.DefaultLocale {
		// A campaign still following the old project default follows a changed
		// default during explicit developer reload. A user-selected locale is
		// retained.
		resolved.LocaleID = campaignConfig.DefaultLocale
	}
	activeCampaign, err := restoreReloadedCampaign(
		campaignConfig,
		campaignState,
		resolved.LocaleID,
	)
	if err != nil {
		return err
	}
	built, candidate, err := buildCampaignSimulation(
		catalog,
		resolved,
		activeCampaign.Snapshot(),
		contentRules,
	)
	if err != nil {
		return err
	}
	state := runtime.simulation.SaveSession()
	state.Dialogue = sim.DialogueSessionState{}
	if err := candidate.LoadSession(state); err != nil {
		return fmt.Errorf(
			"reload is incompatible with the active session: %w",
			err,
		)
	}
	portalInside, err := portalOverlaps(built, candidate)
	if err != nil {
		return fmt.Errorf("reload portal latch: %w", err)
	}
	runtime.catalog = catalog
	runtime.buildOptions = resolved
	runtime.campaignConfig = campaignConfig
	runtime.campaign = activeCampaign
	runtime.contentRules = contentRules
	runtime.ruleExecutor = ruleExecutor
	runtime.built = built
	runtime.simulation = candidate
	runtime.virtual = make(map[string]virtualAction)
	runtime.pendingAbilities = make(map[string]string)
	runtime.behaviorAI = make(map[string]behaviorAIState)
	runtime.pendingRemovals = make(map[string]bool)
	runtime.moving = make(map[string]bool)
	runtime.resetPreviewLocked()
	runtime.resetRulePresentationLocked()
	runtime.resetFlowPresentationLocked()
	runtime.portalCooldownTicks = 0
	runtime.portalInside = portalInside
	runtime.resetTriggerStateLocked()
	runtime.revision++
	return nil
}

func validateCampaignReloadTopology(
	current campaign.Config,
	next campaign.Config,
) error {
	if current.ProjectID != next.ProjectID {
		return fmt.Errorf(
			"reload project identity changed from %q to %q; start a new game to open another project",
			current.ProjectID,
			next.ProjectID,
		)
	}
	checks := []struct {
		name  string
		left  any
		right any
	}{
		{"config version", current.Version, next.Version},
		{"initial stage", current.InitialStageID, next.InitialStageID},
		{
			"initial entry spawn",
			current.InitialEntrySpawnID,
			next.InitialEntrySpawnID,
		},
		{"locale topology", current.Locales, next.Locales},
		{"stage entry topology", current.Stages, next.Stages},
		{"flag topology", current.Flags, next.Flags},
		{"item topology", current.Items, next.Items},
		{
			"equipment slot topology",
			current.EquipmentSlots,
			next.EquipmentSlots,
		},
		{"quest objective topology", current.Quests, next.Quests},
		{
			"turn battle topology",
			current.TurnBattles,
			next.TurnBattles,
		},
	}
	for _, check := range checks {
		if !reflect.DeepEqual(check.left, check.right) {
			return fmt.Errorf(
				"reload campaign %s changed; start a new game to accept incompatible content",
				check.name,
			)
		}
	}
	return nil
}

func restoreReloadedCampaign(
	config campaign.Config,
	state campaign.State,
	localeID string,
) (*campaign.Campaign, error) {
	state.ContentID = config.ContentID
	state.Locale = localeID
	active, err := campaign.Restore(config, state)
	if err != nil {
		return nil, fmt.Errorf(
			"reload campaign progress is incompatible with edited content: %w",
			err,
		)
	}
	return active, nil
}

func (runtime *Runtime) startNewGame(ctx context.Context) error {
	return runtime.startNewGameWithBuildOptions(
		ctx,
		runtime.buildOverrides,
	)
}

func (runtime *Runtime) startNewGameAt(
	ctx context.Context,
	params protocol.StartNewGameParams,
) error {
	options := runtime.buildOverrides
	if params.StageID != "" {
		options.StageID = params.StageID
		// A spawn override belongs to its original stage. Let the selected
		// stage resolve its own authored entry unless Maker explicitly chose
		// one for this request.
		options.SpawnID = ""
	}
	if params.SpawnID != "" {
		options.SpawnID = params.SpawnID
	}
	if params.LocaleID != "" {
		options.LocaleID = params.LocaleID
	}
	return runtime.startNewGameWithBuildOptions(ctx, options)
}

func (runtime *Runtime) startNewGameWithBuildOptions(
	ctx context.Context,
	overrides gamebuild.Options,
) error {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()

	if err := ctx.Err(); err != nil {
		return err
	}
	accessibility := runtime.campaign.Snapshot().Accessibility
	catalog, err := loadCatalog(runtime.catalogPath)
	if err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	resolved := resolveBuildOptions(catalog, overrides)
	campaignConfig, err := gamebuild.BuildCampaignConfig(catalog)
	if err != nil {
		return err
	}
	contentRules, ruleExecutor, err := buildRuleRuntime(
		catalog,
		campaignConfig,
	)
	if err != nil {
		return err
	}
	seedCampaign, err := campaign.NewGame(campaignConfig)
	if err != nil {
		return err
	}
	built, simulation, err := buildCampaignSimulation(
		catalog,
		resolved,
		seedCampaign.Snapshot(),
		contentRules,
	)
	if err != nil {
		return err
	}
	activeCampaign, err := newCampaignForWorld(
		campaignConfig,
		built,
		resolved,
	)
	if err != nil {
		return err
	}
	if err := activeCampaign.Transaction(
		func(state *campaign.State) error {
			state.Accessibility = accessibility
			return nil
		},
	); err != nil {
		return fmt.Errorf(
			"preserve accessibility settings for new game: %w",
			err,
		)
	}
	portalInside, err := portalOverlaps(built, simulation)
	if err != nil {
		return fmt.Errorf("seed new-game portal latch: %w", err)
	}
	runtime.catalog = catalog
	runtime.buildOptions = resolved
	runtime.campaignConfig = campaignConfig
	runtime.campaign = activeCampaign
	runtime.contentRules = contentRules
	runtime.ruleExecutor = ruleExecutor
	runtime.built = built
	runtime.simulation = simulation
	runtime.virtual = make(map[string]virtualAction)
	runtime.pendingAbilities = make(map[string]string)
	runtime.behaviorAI = make(map[string]behaviorAIState)
	runtime.pendingRemovals = make(map[string]bool)
	runtime.moving = make(map[string]bool)
	runtime.resetPreviewLocked()
	runtime.resetRulePresentationLocked()
	runtime.resetFlowPresentationLocked()
	runtime.portalCooldownTicks = 0
	runtime.portalInside = portalInside
	runtime.resetTriggerStateLocked()
	runtime.revision++
	return nil
}

func (runtime *Runtime) resetLocked() error {
	built, candidate, err := buildCampaignSimulation(
		runtime.catalog,
		runtime.buildOptions,
		runtime.campaign.Snapshot(),
		runtime.contentRules,
	)
	if err != nil {
		return err
	}
	built = mergeResetBuild(built, runtime.built)
	candidate, err = sim.New(built.Config)
	if err != nil {
		return fmt.Errorf("construct reset simulation: %w", err)
	}
	portalInside, err := portalOverlaps(built, candidate)
	if err != nil {
		return fmt.Errorf("reset portal latch: %w", err)
	}
	runtime.built = built
	runtime.simulation = candidate
	runtime.virtual = make(map[string]virtualAction)
	runtime.pendingAbilities = make(map[string]string)
	runtime.behaviorAI = make(map[string]behaviorAIState)
	runtime.pendingRemovals = make(map[string]bool)
	runtime.moving = make(map[string]bool)
	runtime.resetPreviewLocked()
	runtime.resetRulePresentationLocked()
	runtime.resetFlowPresentationLocked()
	runtime.portalCooldownTicks = 0
	runtime.portalInside = portalInside
	runtime.resetTriggerStateLocked()
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
	for _, encounter := range runtime.built.Config.Encounters {
		for _, wave := range encounter.Waves {
			for _, spawn := range wave.Spawns {
				if spawn.Entity.ID == id {
					return spawn.Entity, true
				}
			}
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

func (runtime *Runtime) checkpointLocked() runtimeCheckpoint {
	return runtimeCheckpoint{
		buildOptions:            runtime.buildOptions,
		built:                   runtime.built,
		simulation:              runtime.simulation,
		campaign:                runtime.campaign,
		dialogue:                runtime.dialogue,
		virtual:                 runtime.virtual,
		pendingAbilities:        runtime.pendingAbilities,
		behaviorAI:              runtime.behaviorAI,
		pendingRemovals:         runtime.pendingRemovals,
		moving:                  runtime.moving,
		audioSequence:           runtime.audioSequence,
		audioCues:               runtime.audioCues,
		previewSequence:         runtime.previewSequence,
		previewEntities:         runtime.previewEntities,
		dialogueSpeakerID:       runtime.dialogueSpeakerID,
		dialogueChoiceIndex:     runtime.dialogueChoiceIndex,
		activeShopID:            runtime.activeShopID,
		shopSelectedIndex:       runtime.shopSelectedIndex,
		shopStatus:              runtime.shopStatus,
		inventoryOpen:           runtime.inventoryOpen,
		inventorySelected:       runtime.inventorySelected,
		inventoryStatus:         runtime.inventoryStatus,
		equipmentRebuildPending: runtime.equipmentRebuildPending,
		flowSelectedIndex:       runtime.flowSelectedIndex,
		flowStatus:              runtime.flowStatus,
		flowPanel:               runtime.flowPanel,
		continueAvailable:       runtime.continueAvailable,
		notice:                  runtime.notice,
		turnBattle:              cloneTurnBattleSession(runtime.turnBattle),
		cutscene:                cloneCutsceneSession(runtime.cutscene),
		portalCooldownTicks:     runtime.portalCooldownTicks,
		portalInside:            runtime.portalInside,
		triggerInside:           runtime.triggerInside,
		triggerCooldowns:        runtime.triggerCooldowns,
		triggerFired:            runtime.triggerFired,
		worldInitialized:        runtime.worldInitialized,
		worldActivePage:         runtime.worldActivePage,
		worldActiveRegions:      runtime.worldActiveRegions,
		revision:                runtime.revision,
	}
}

func (runtime *Runtime) detachMutableLocked(
	checkpoint runtimeCheckpoint,
) error {
	activeCampaign, err := campaign.Restore(
		runtime.campaignConfig,
		checkpoint.campaign.Snapshot(),
	)
	if err != nil {
		return fmt.Errorf("detach campaign candidate: %w", err)
	}
	var activeDialogue *rulesruntime.DialogueSession
	if checkpoint.dialogue != nil {
		activeDialogue, err = checkpoint.dialogue.CloneForCampaign(
			activeCampaign,
		)
		if err != nil {
			return fmt.Errorf("detach dialogue candidate: %w", err)
		}
	}
	runtime.simulation = checkpoint.simulation.Clone()
	runtime.campaign = activeCampaign
	runtime.dialogue = activeDialogue
	runtime.virtual = cloneVirtualActions(checkpoint.virtual)
	runtime.pendingAbilities = cloneStringMap(checkpoint.pendingAbilities)
	runtime.behaviorAI = cloneBehaviorAIStates(checkpoint.behaviorAI)
	runtime.pendingRemovals = cloneBoolMap(checkpoint.pendingRemovals)
	runtime.moving = cloneBoolMap(checkpoint.moving)
	runtime.audioSequence = checkpoint.audioSequence
	runtime.audioCues = append(
		[]queuedAudioCue(nil),
		checkpoint.audioCues...,
	)
	runtime.previewEntities = clonePreviewEntities(
		checkpoint.previewEntities,
	)
	runtime.notice = checkpoint.notice
	runtime.turnBattle = cloneTurnBattleSession(checkpoint.turnBattle)
	runtime.cutscene = cloneCutsceneSession(checkpoint.cutscene)
	runtime.portalInside = cloneBoolMap(checkpoint.portalInside)
	runtime.triggerInside = cloneBoolMap(checkpoint.triggerInside)
	runtime.triggerCooldowns = cloneIntMap(checkpoint.triggerCooldowns)
	runtime.triggerFired = cloneBoolMap(checkpoint.triggerFired)
	runtime.worldInitialized = checkpoint.worldInitialized
	runtime.worldActivePage = checkpoint.worldActivePage
	runtime.worldActiveRegions = cloneBoolMap(
		checkpoint.worldActiveRegions,
	)
	return nil
}

func (runtime *Runtime) restoreCheckpointLocked(
	checkpoint runtimeCheckpoint,
) {
	runtime.buildOptions = checkpoint.buildOptions
	runtime.built = checkpoint.built
	runtime.simulation = checkpoint.simulation
	runtime.campaign = checkpoint.campaign
	runtime.dialogue = checkpoint.dialogue
	runtime.virtual = checkpoint.virtual
	runtime.pendingAbilities = checkpoint.pendingAbilities
	runtime.behaviorAI = checkpoint.behaviorAI
	runtime.pendingRemovals = checkpoint.pendingRemovals
	runtime.moving = checkpoint.moving
	runtime.audioSequence = checkpoint.audioSequence
	runtime.audioCues = checkpoint.audioCues
	runtime.previewSequence = checkpoint.previewSequence
	runtime.previewEntities = checkpoint.previewEntities
	runtime.dialogueSpeakerID = checkpoint.dialogueSpeakerID
	runtime.dialogueChoiceIndex = checkpoint.dialogueChoiceIndex
	runtime.activeShopID = checkpoint.activeShopID
	runtime.shopSelectedIndex = checkpoint.shopSelectedIndex
	runtime.shopStatus = checkpoint.shopStatus
	runtime.inventoryOpen = checkpoint.inventoryOpen
	runtime.inventorySelected = checkpoint.inventorySelected
	runtime.inventoryStatus = checkpoint.inventoryStatus
	runtime.equipmentRebuildPending = checkpoint.equipmentRebuildPending
	runtime.flowSelectedIndex = checkpoint.flowSelectedIndex
	runtime.flowStatus = checkpoint.flowStatus
	runtime.flowPanel = checkpoint.flowPanel
	runtime.continueAvailable = checkpoint.continueAvailable
	runtime.notice = checkpoint.notice
	runtime.turnBattle = checkpoint.turnBattle
	runtime.cutscene = checkpoint.cutscene
	runtime.portalCooldownTicks = checkpoint.portalCooldownTicks
	runtime.portalInside = checkpoint.portalInside
	runtime.triggerInside = checkpoint.triggerInside
	runtime.triggerCooldowns = checkpoint.triggerCooldowns
	runtime.triggerFired = checkpoint.triggerFired
	runtime.worldInitialized = checkpoint.worldInitialized
	runtime.worldActivePage = checkpoint.worldActivePage
	runtime.worldActiveRegions = checkpoint.worldActiveRegions
	runtime.revision = checkpoint.revision
}

func (runtime *Runtime) resetTriggerStateLocked() {
	runtime.triggerInside = make(map[string]bool)
	runtime.triggerCooldowns = make(map[string]int)
	runtime.triggerFired = make(map[string]bool)
	runtime.resetWorldStateLocked()
}
