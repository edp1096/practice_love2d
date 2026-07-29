package content

import (
	"fmt"
	"math"
	"path"
	"sort"
	"strings"
)

const (
	projectManifestSource       = "game/game.lua"
	unsupportedProjectFieldCode = "unsupported_project_field"
	unsupportedProjectFieldText = "project setting is not compiled into the runtime manifest"
	supportedProjectFixedDT     = 1.0 / 60.0
)

// ProjectManifest is the runtime-neutral subset of game/game.lua needed to
// bootstrap a project. Settings outside this contract are represented by
// Warnings instead of being silently copied into the runtime artifact.
type ProjectManifest struct {
	Source       string                   `json:"source"`
	ID           string                   `json:"id"`
	Profile      string                   `json:"profile"`
	Title        string                   `json:"title"`
	InitialStage string                   `json:"initial_stage"`
	FixedDT      float64                  `json:"fixed_dt"`
	Locale       ProjectLocale            `json:"locale"`
	Flow         ProjectFlow              `json:"flow"`
	Input        ProjectInput             `json:"input"`
	Font         ProjectFont              `json:"font"`
	Audio        ProjectAudio             `json:"audio"`
	Warnings     []ProjectManifestWarning `json:"warnings"`
}

type ProjectLocale struct {
	Default  string `json:"default"`
	Fallback string `json:"fallback"`
}

type ProjectFlow struct {
	SaveSlot   string          `json:"save_slot"`
	StartStage string          `json:"start_stage"`
	StartSpawn string          `json:"start_spawn"`
	Title      ProjectFlowCopy `json:"title"`
	GameOver   ProjectFlowCopy `json:"game_over"`
	Ending     ProjectFlowCopy `json:"ending"`
}

type ProjectFlowCopy struct {
	HeadingKey string `json:"heading_key"`
	MessageKey string `json:"message_key"`
}

// ProjectInput is an ordered, runtime-neutral form of the action bindings
// authored as the input.actions object in game/game.lua.
type ProjectInput struct {
	Actions []ProjectInputAction `json:"actions"`
}

type ProjectInputAction struct {
	ID      string   `json:"id"`
	Keys    []string `json:"keys"`
	Buttons []string `json:"buttons"`
}

type ProjectFont struct {
	Asset string  `json:"asset"`
	Size  float64 `json:"size"`
}

type ProjectAudio struct {
	MasterVolume float64             `json:"master_volume"`
	MusicVolume  float64             `json:"music_volume"`
	SFXVolume    float64             `json:"sfx_volume"`
	Cues         []ProjectAudioCue   `json:"cues"`
	StageMusic   []ProjectStageMusic `json:"stage_music"`
}

type ProjectAudioCue struct {
	Event  string  `json:"event"`
	Asset  string  `json:"asset"`
	Volume float64 `json:"volume"`
}

type ProjectStageMusic struct {
	Stage  string  `json:"stage"`
	Asset  string  `json:"asset"`
	Volume float64 `json:"volume"`
}

type ProjectManifestWarning struct {
	Code    string `json:"code"`
	Path    string `json:"path"`
	Message string `json:"message"`
}

// Project returns a detached manifest value suitable for runtime ownership.
func (catalog *Catalog) Project() ProjectManifest {
	if catalog == nil {
		return ProjectManifest{}
	}
	return cloneProjectManifest(catalog.Manifest)
}

// ValidateProjectReferences checks manifest references that need the complete
// definition index. Catalog decoding validates the artifact's own shape; a
// runtime calls this before constructing a playable project.
func (catalog *Catalog) ValidateProjectReferences() error {
	if catalog == nil {
		return fmt.Errorf("project catalog is nil")
	}
	definitions := make(map[string]Definition, len(catalog.Definitions))
	for _, definition := range catalog.Definitions {
		definitions[definition.ID()] = definition
	}
	return validateManifestReferences(catalog.Manifest, definitions)
}

func cloneProjectManifest(manifest ProjectManifest) ProjectManifest {
	manifest.Input.Actions = append(
		[]ProjectInputAction(nil),
		manifest.Input.Actions...,
	)
	for index := range manifest.Input.Actions {
		keys := manifest.Input.Actions[index].Keys
		manifest.Input.Actions[index].Keys = make([]string, len(keys))
		copy(manifest.Input.Actions[index].Keys, keys)
		buttons := manifest.Input.Actions[index].Buttons
		manifest.Input.Actions[index].Buttons = make(
			[]string,
			len(buttons),
		)
		copy(manifest.Input.Actions[index].Buttons, buttons)
	}
	if manifest.Input.Actions == nil {
		manifest.Input.Actions = []ProjectInputAction{}
	}
	manifest.Audio.Cues = append(
		[]ProjectAudioCue(nil),
		manifest.Audio.Cues...,
	)
	manifest.Audio.StageMusic = append(
		[]ProjectStageMusic(nil),
		manifest.Audio.StageMusic...,
	)
	if manifest.Audio.Cues == nil {
		manifest.Audio.Cues = []ProjectAudioCue{}
	}
	if manifest.Audio.StageMusic == nil {
		manifest.Audio.StageMusic = []ProjectStageMusic{}
	}
	manifest.Warnings = append(
		[]ProjectManifestWarning(nil),
		manifest.Warnings...,
	)
	if manifest.Warnings == nil {
		manifest.Warnings = []ProjectManifestWarning{}
	}
	return manifest
}

func normalizeLegacyProjectAudio(manifest *ProjectManifest) {
	if manifest == nil ||
		manifest.Audio.Cues != nil ||
		manifest.Audio.StageMusic != nil ||
		manifest.Audio.MasterVolume != 0 ||
		manifest.Audio.MusicVolume != 0 ||
		manifest.Audio.SFXVolume != 0 {
		return
	}
	manifest.Audio = ProjectAudio{
		MasterVolume: 1,
		MusicVolume:  0.5,
		SFXVolume:    0.8,
		Cues:         []ProjectAudioCue{},
		StageMusic:   []ProjectStageMusic{},
	}
}

func normalizeLegacyProjectInput(manifest *ProjectManifest) {
	if manifest != nil && manifest.Input.Actions == nil {
		manifest.Input.Actions = []ProjectInputAction{}
	}
}

func compileProjectManifest(data map[string]any) (ProjectManifest, error) {
	const source = projectManifestSource
	if data == nil {
		return ProjectManifest{}, fmt.Errorf(
			"%s: project manifest must return an object",
			source,
		)
	}

	supported := map[string]struct{}{
		"fixed_dt":      {},
		"flow":          {},
		"font":          {},
		"audio":         {},
		"id":            {},
		"initial_stage": {},
		"input":         {},
		"locale":        {},
		"profile":       {},
		"title":         {},
	}
	warnings := make([]ProjectManifestWarning, 0)
	for key := range data {
		if _, exists := supported[key]; exists {
			continue
		}
		warnings = append(warnings, ProjectManifestWarning{
			Code:    unsupportedProjectFieldCode,
			Path:    key,
			Message: unsupportedProjectFieldText,
		})
	}
	sort.Slice(warnings, func(i, j int) bool {
		return warnings[i].Path < warnings[j].Path
	})

	id, err := manifestString(data, "id", source)
	if err != nil {
		return ProjectManifest{}, err
	}
	profile, err := manifestString(data, "profile", source)
	if err != nil {
		return ProjectManifest{}, err
	}
	title, err := manifestString(data, "title", source)
	if err != nil {
		return ProjectManifest{}, err
	}
	initialStage, err := manifestString(data, "initial_stage", source)
	if err != nil {
		return ProjectManifest{}, err
	}
	fixedDT, err := manifestNumber(data, "fixed_dt", source)
	if err != nil {
		return ProjectManifest{}, err
	}

	var defaultLocale, fallbackLocale string
	if rawLocale, exists := data["locale"]; exists {
		localeData, ok := rawLocale.(map[string]any)
		if !ok {
			return ProjectManifest{}, fmt.Errorf(
				"%s.locale must be an object",
				source,
			)
		}
		if err := rejectUnknownManifestFields(
			localeData,
			source+".locale",
			"default",
			"fallback",
		); err != nil {
			return ProjectManifest{}, err
		}
		defaultLocale, err = manifestString(
			localeData,
			"default",
			source+".locale",
		)
		if err != nil {
			return ProjectManifest{}, err
		}
		fallbackLocale, err = optionalManifestString(
			localeData,
			"fallback",
			source+".locale",
		)
		if err != nil {
			return ProjectManifest{}, err
		}
		if fallbackLocale == "" {
			fallbackLocale = defaultLocale
		}
	}

	var fontAsset string
	var fontSize float64
	if rawFont, exists := data["font"]; exists {
		fontData, ok := rawFont.(map[string]any)
		if !ok {
			return ProjectManifest{}, fmt.Errorf(
				"%s.font must be an object",
				source,
			)
		}
		if err := rejectUnknownManifestFields(
			fontData,
			source+".font",
			"asset",
			"size",
		); err != nil {
			return ProjectManifest{}, err
		}
		fontAsset, err = manifestString(fontData, "asset", source+".font")
		if err != nil {
			return ProjectManifest{}, err
		}
		fontSize, err = manifestNumber(fontData, "size", source+".font")
		if err != nil {
			return ProjectManifest{}, err
		}
	}
	audio, err := compileProjectAudio(data)
	if err != nil {
		return ProjectManifest{}, err
	}
	input, err := compileProjectInput(data)
	if err != nil {
		return ProjectManifest{}, err
	}

	flowData, err := manifestObject(data, "flow", source)
	if err != nil {
		return ProjectManifest{}, err
	}
	if err := rejectUnknownManifestFields(
		flowData,
		source+".flow",
		"ending",
		"game_over",
		"save_slot",
		"start_spawn",
		"start_stage",
		"title",
	); err != nil {
		return ProjectManifest{}, err
	}
	saveSlot, err := manifestString(flowData, "save_slot", source+".flow")
	if err != nil {
		return ProjectManifest{}, err
	}
	startStage, err := manifestString(flowData, "start_stage", source+".flow")
	if err != nil {
		return ProjectManifest{}, err
	}
	startSpawn, err := optionalManifestString(
		flowData,
		"start_spawn",
		source+".flow",
	)
	if err != nil {
		return ProjectManifest{}, err
	}
	titleCopy, err := compileProjectFlowCopy(flowData, "title")
	if err != nil {
		return ProjectManifest{}, err
	}
	gameOverCopy, err := compileProjectFlowCopy(flowData, "game_over")
	if err != nil {
		return ProjectManifest{}, err
	}
	endingCopy, err := compileProjectFlowCopy(flowData, "ending")
	if err != nil {
		return ProjectManifest{}, err
	}

	manifest := ProjectManifest{
		Source:       source,
		ID:           id,
		Profile:      profile,
		Title:        title,
		InitialStage: initialStage,
		FixedDT:      fixedDT,
		Locale: ProjectLocale{
			Default:  defaultLocale,
			Fallback: fallbackLocale,
		},
		Flow: ProjectFlow{
			SaveSlot:   saveSlot,
			StartStage: startStage,
			StartSpawn: startSpawn,
			Title:      titleCopy,
			GameOver:   gameOverCopy,
			Ending:     endingCopy,
		},
		Input: input,
		Font: ProjectFont{
			Asset: fontAsset,
			Size:  fontSize,
		},
		Audio:    audio,
		Warnings: warnings,
	}
	if err := validateProjectManifest(manifest); err != nil {
		return ProjectManifest{}, err
	}
	return manifest, nil
}

func compileProjectInput(data map[string]any) (ProjectInput, error) {
	result := ProjectInput{Actions: []ProjectInputAction{}}
	raw, exists := data["input"]
	if !exists {
		return result, nil
	}
	input, ok := raw.(map[string]any)
	if !ok {
		return ProjectInput{}, fmt.Errorf(
			"%s.input must be an object",
			projectManifestSource,
		)
	}
	currentPath := projectManifestSource + ".input"
	if err := rejectUnknownManifestFields(
		input,
		currentPath,
		"actions",
	); err != nil {
		return ProjectInput{}, err
	}
	actions, err := manifestObject(input, "actions", currentPath)
	if err != nil {
		return ProjectInput{}, err
	}
	ids := make([]string, 0, len(actions))
	for id := range actions {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		actionPath := currentPath + ".actions." + id
		rawAction := actions[id]
		action, ok := rawAction.(map[string]any)
		if !ok {
			return ProjectInput{}, fmt.Errorf(
				"%s must be an object",
				actionPath,
			)
		}
		if err := rejectUnknownManifestFields(
			action,
			actionPath,
			"buttons",
			"keys",
		); err != nil {
			return ProjectInput{}, err
		}
		keys, err := manifestStringList(action, "keys", actionPath)
		if err != nil {
			return ProjectInput{}, err
		}
		buttons, err := manifestStringList(
			action,
			"buttons",
			actionPath,
		)
		if err != nil {
			return ProjectInput{}, err
		}
		result.Actions = append(result.Actions, ProjectInputAction{
			ID:      id,
			Keys:    keys,
			Buttons: buttons,
		})
	}
	return result, nil
}

func manifestStringList(
	data map[string]any,
	field string,
	currentPath string,
) ([]string, error) {
	value, exists := data[field]
	if !exists {
		return nil, fmt.Errorf("%s.%s is required", currentPath, field)
	}
	var raw []any
	switch typed := value.(type) {
	case []any:
		raw = typed
	case map[string]any:
		// An empty Lua table has no shape information. The project decoder
		// represents it as an empty object, but bindings intentionally permit
		// keys={} and buttons={}.
		if len(typed) != 0 {
			return nil, fmt.Errorf(
				"%s.%s must be an array",
				currentPath,
				field,
			)
		}
		raw = []any{}
	default:
		return nil, fmt.Errorf(
			"%s.%s must be an array",
			currentPath,
			field,
		)
	}
	result := make([]string, 0, len(raw))
	seen := make(map[string]struct{}, len(raw))
	for index, value := range raw {
		text, ok := value.(string)
		if !ok || strings.TrimSpace(text) == "" {
			return nil, fmt.Errorf(
				"%s.%s[%d] must be a non-empty string",
				currentPath,
				field,
				index+1,
			)
		}
		if _, exists := seen[text]; exists {
			return nil, fmt.Errorf(
				"%s.%s contains duplicate value %q",
				currentPath,
				field,
				text,
			)
		}
		seen[text] = struct{}{}
		result = append(result, text)
	}
	sort.Strings(result)
	return result, nil
}

func compileProjectAudio(data map[string]any) (ProjectAudio, error) {
	result := ProjectAudio{
		MasterVolume: 1,
		MusicVolume:  0.5,
		SFXVolume:    0.8,
		Cues:         []ProjectAudioCue{},
		StageMusic:   []ProjectStageMusic{},
	}
	raw, exists := data["audio"]
	if !exists {
		return result, nil
	}
	audio, ok := raw.(map[string]any)
	if !ok {
		return ProjectAudio{}, fmt.Errorf(
			"%s.audio must be an object",
			projectManifestSource,
		)
	}
	currentPath := projectManifestSource + ".audio"
	if err := rejectUnknownManifestFields(
		audio,
		currentPath,
		"cues",
		"master_volume",
		"music_volume",
		"sfx_volume",
		"stage_music",
	); err != nil {
		return ProjectAudio{}, err
	}
	var err error
	result.MasterVolume, err = manifestNumber(
		audio,
		"master_volume",
		currentPath,
	)
	if err != nil {
		return ProjectAudio{}, err
	}
	result.MusicVolume, err = manifestNumber(
		audio,
		"music_volume",
		currentPath,
	)
	if err != nil {
		return ProjectAudio{}, err
	}
	result.SFXVolume, err = manifestNumber(
		audio,
		"sfx_volume",
		currentPath,
	)
	if err != nil {
		return ProjectAudio{}, err
	}
	rawCues, err := manifestArray(audio, "cues", currentPath)
	if err != nil {
		return ProjectAudio{}, err
	}
	for index, rawCue := range rawCues {
		path := fmt.Sprintf("%s.cues[%d]", currentPath, index+1)
		cue, ok := rawCue.(map[string]any)
		if !ok {
			return ProjectAudio{}, fmt.Errorf("%s must be an object", path)
		}
		if err := rejectUnknownManifestFields(
			cue,
			path,
			"asset",
			"event",
			"volume",
		); err != nil {
			return ProjectAudio{}, err
		}
		event, err := manifestString(cue, "event", path)
		if err != nil {
			return ProjectAudio{}, err
		}
		asset, err := manifestString(cue, "asset", path)
		if err != nil {
			return ProjectAudio{}, err
		}
		volume, err := manifestNumber(cue, "volume", path)
		if err != nil {
			return ProjectAudio{}, err
		}
		result.Cues = append(result.Cues, ProjectAudioCue{
			Event:  event,
			Asset:  asset,
			Volume: volume,
		})
	}
	sort.Slice(result.Cues, func(i, j int) bool {
		return result.Cues[i].Event < result.Cues[j].Event
	})
	rawMusic, err := manifestArray(audio, "stage_music", currentPath)
	if err != nil {
		return ProjectAudio{}, err
	}
	for index, rawTrack := range rawMusic {
		path := fmt.Sprintf("%s.stage_music[%d]", currentPath, index+1)
		track, ok := rawTrack.(map[string]any)
		if !ok {
			return ProjectAudio{}, fmt.Errorf("%s must be an object", path)
		}
		if err := rejectUnknownManifestFields(
			track,
			path,
			"asset",
			"stage",
			"volume",
		); err != nil {
			return ProjectAudio{}, err
		}
		stage, err := manifestString(track, "stage", path)
		if err != nil {
			return ProjectAudio{}, err
		}
		asset, err := manifestString(track, "asset", path)
		if err != nil {
			return ProjectAudio{}, err
		}
		volume, err := manifestNumber(track, "volume", path)
		if err != nil {
			return ProjectAudio{}, err
		}
		result.StageMusic = append(result.StageMusic, ProjectStageMusic{
			Stage:  stage,
			Asset:  asset,
			Volume: volume,
		})
	}
	sort.Slice(result.StageMusic, func(i, j int) bool {
		return result.StageMusic[i].Stage < result.StageMusic[j].Stage
	})
	return result, nil
}

func manifestArray(
	data map[string]any,
	field string,
	currentPath string,
) ([]any, error) {
	value, exists := data[field]
	if !exists {
		return nil, fmt.Errorf("%s.%s is required", currentPath, field)
	}
	array, ok := value.([]any)
	if !ok {
		return nil, fmt.Errorf("%s.%s must be an array", currentPath, field)
	}
	return array, nil
}

func compileProjectFlowCopy(
	flow map[string]any,
	field string,
) (ProjectFlowCopy, error) {
	currentPath := projectManifestSource + ".flow"
	raw, exists := flow[field]
	if !exists {
		return ProjectFlowCopy{}, nil
	}
	data, ok := raw.(map[string]any)
	if !ok {
		return ProjectFlowCopy{}, fmt.Errorf(
			"%s.%s must be an object",
			currentPath,
			field,
		)
	}
	copyPath := currentPath + "." + field
	if err := rejectUnknownManifestFields(
		data,
		copyPath,
		"heading_key",
		"message_key",
	); err != nil {
		return ProjectFlowCopy{}, err
	}
	heading, err := optionalManifestString(data, "heading_key", copyPath)
	if err != nil {
		return ProjectFlowCopy{}, err
	}
	message, err := optionalManifestString(data, "message_key", copyPath)
	if err != nil {
		return ProjectFlowCopy{}, err
	}
	return ProjectFlowCopy{
		HeadingKey: heading,
		MessageKey: message,
	}, nil
}

func manifestString(
	data map[string]any,
	field string,
	currentPath string,
) (string, error) {
	value, exists := data[field]
	if !exists {
		return "", fmt.Errorf("%s.%s is required", currentPath, field)
	}
	text, ok := value.(string)
	if !ok || strings.TrimSpace(text) == "" {
		return "", fmt.Errorf(
			"%s.%s must be a non-empty string",
			currentPath,
			field,
		)
	}
	return text, nil
}

func optionalManifestString(
	data map[string]any,
	field string,
	currentPath string,
) (string, error) {
	if _, exists := data[field]; !exists {
		return "", nil
	}
	return manifestString(data, field, currentPath)
}

func manifestNumber(
	data map[string]any,
	field string,
	currentPath string,
) (float64, error) {
	value, exists := data[field]
	if !exists {
		return 0, fmt.Errorf("%s.%s is required", currentPath, field)
	}
	number, ok := value.(float64)
	if !ok || math.IsNaN(number) || math.IsInf(number, 0) {
		return 0, fmt.Errorf(
			"%s.%s must be a finite number",
			currentPath,
			field,
		)
	}
	return number, nil
}

func manifestObject(
	data map[string]any,
	field string,
	currentPath string,
) (map[string]any, error) {
	value, exists := data[field]
	if !exists {
		return nil, fmt.Errorf("%s.%s is required", currentPath, field)
	}
	object, ok := value.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("%s.%s must be an object", currentPath, field)
	}
	return object, nil
}

func rejectUnknownManifestFields(
	data map[string]any,
	currentPath string,
	fields ...string,
) error {
	allowed := make(map[string]struct{}, len(fields))
	for _, field := range fields {
		allowed[field] = struct{}{}
	}
	var unknown []string
	for field := range data {
		if _, exists := allowed[field]; !exists {
			unknown = append(unknown, field)
		}
	}
	sort.Strings(unknown)
	if len(unknown) > 0 {
		return fmt.Errorf(
			"%s.%s is not supported",
			currentPath,
			unknown[0],
		)
	}
	return nil
}

func validateProjectManifest(manifest ProjectManifest) error {
	if manifest.Source != projectManifestSource ||
		path.Clean(manifest.Source) != manifest.Source {
		return fmt.Errorf(
			"project manifest source must be %q, got %q",
			projectManifestSource,
			manifest.Source,
		)
	}
	if !validContentID(manifest.ID) {
		return fmt.Errorf(
			"%s.id must match namespace.name using lowercase characters and be at most %d bytes",
			manifest.Source,
			MaxContentIDBytes,
		)
	}
	if !simpleManifestValue(manifest.Profile) {
		return fmt.Errorf("%s.profile is invalid", manifest.Source)
	}
	if strings.TrimSpace(manifest.Title) == "" {
		return fmt.Errorf("%s.title must be a non-empty string", manifest.Source)
	}
	if !manifestIDWithNamespace(manifest.InitialStage, "stage.") {
		return fmt.Errorf("%s.initial_stage must be a stage content id", manifest.Source)
	}
	if manifest.FixedDT != supportedProjectFixedDT ||
		math.IsNaN(manifest.FixedDT) ||
		math.IsInf(manifest.FixedDT, 0) {
		return fmt.Errorf(
			"%s.fixed_dt must be 1/60; the runtime currently supports 60 TPS only",
			manifest.Source,
		)
	}
	if manifest.Locale.Default == "" || manifest.Locale.Fallback == "" {
		if manifest.Locale != (ProjectLocale{}) {
			return fmt.Errorf(
				"%s.locale default and fallback must both be configured",
				manifest.Source,
			)
		}
	} else if !manifestIDWithNamespace(
		manifest.Locale.Default,
		"locale.",
	) {
		return fmt.Errorf("%s.locale.default must be a locale content id", manifest.Source)
	} else if !manifestIDWithNamespace(
		manifest.Locale.Fallback,
		"locale.",
	) {
		return fmt.Errorf("%s.locale.fallback must be a locale content id", manifest.Source)
	}
	if !simpleManifestValue(manifest.Flow.SaveSlot) {
		return fmt.Errorf("%s.flow.save_slot is invalid", manifest.Source)
	}
	if !manifestIDWithNamespace(manifest.Flow.StartStage, "stage.") {
		return fmt.Errorf("%s.flow.start_stage must be a stage content id", manifest.Source)
	}
	if manifest.Flow.StartStage != manifest.InitialStage {
		return fmt.Errorf(
			"%s.flow.start_stage must match initial_stage",
			manifest.Source,
		)
	}
	if manifest.Flow.StartSpawn != "" &&
		!simpleManifestValue(manifest.Flow.StartSpawn) {
		return fmt.Errorf("%s.flow.start_spawn is invalid", manifest.Source)
	}
	for index, action := range manifest.Input.Actions {
		if !simpleManifestValue(action.ID) {
			return fmt.Errorf(
				"%s.input.actions[%d].id is invalid",
				manifest.Source,
				index+1,
			)
		}
		if index > 0 &&
			manifest.Input.Actions[index-1].ID >= action.ID {
			return fmt.Errorf(
				"%s.input.actions must have unique sorted ids",
				manifest.Source,
			)
		}
		if action.Keys == nil {
			return fmt.Errorf(
				"%s.input.actions.%s.keys must be an array",
				manifest.Source,
				action.ID,
			)
		}
		if action.Buttons == nil {
			return fmt.Errorf(
				"%s.input.actions.%s.buttons must be an array",
				manifest.Source,
				action.ID,
			)
		}
		for field, values := range map[string][]string{
			"buttons": action.Buttons,
			"keys":    action.Keys,
		} {
			for valueIndex, value := range values {
				if !simpleInputValue(value) {
					return fmt.Errorf(
						"%s.input.actions.%s.%s[%d] is invalid",
						manifest.Source,
						action.ID,
						field,
						valueIndex+1,
					)
				}
				if valueIndex > 0 && values[valueIndex-1] >= value {
					return fmt.Errorf(
						"%s.input.actions.%s.%s must contain unique sorted values",
						manifest.Source,
						action.ID,
						field,
					)
				}
			}
		}
	}
	if manifest.Input.Actions == nil {
		return fmt.Errorf("%s.input.actions must be an array", manifest.Source)
	}
	for name, copy := range map[string]ProjectFlowCopy{
		"ending":    manifest.Flow.Ending,
		"game_over": manifest.Flow.GameOver,
		"title":     manifest.Flow.Title,
	} {
		if copy.HeadingKey != "" &&
			!simpleManifestValue(copy.HeadingKey) {
			return fmt.Errorf(
				"%s.flow.%s.heading_key is invalid",
				manifest.Source,
				name,
			)
		}
		if copy.MessageKey != "" &&
			!simpleManifestValue(copy.MessageKey) {
			return fmt.Errorf(
				"%s.flow.%s.message_key is invalid",
				manifest.Source,
				name,
			)
		}
	}
	if manifest.Font == (ProjectFont{}) {
		// Ebitengine packages its fallback UI font. Pure action templates do
		// not need to load the RPG font feature just to satisfy the adapter.
	} else if !manifestIDWithNamespace(manifest.Font.Asset, "font.") {
		return fmt.Errorf("%s.font.asset must be a font asset id", manifest.Source)
	} else if manifest.Font.Size <= 0 ||
		manifest.Font.Size > 512 ||
		math.IsNaN(manifest.Font.Size) ||
		math.IsInf(manifest.Font.Size, 0) {
		return fmt.Errorf(
			"%s.font.size must be greater than 0 and at most 512",
			manifest.Source,
		)
	}
	for name, volume := range map[string]float64{
		"master_volume": manifest.Audio.MasterVolume,
		"music_volume":  manifest.Audio.MusicVolume,
		"sfx_volume":    manifest.Audio.SFXVolume,
	} {
		if !manifestVolume(volume) {
			return fmt.Errorf(
				"%s.audio.%s must be between 0 and 1",
				manifest.Source,
				name,
			)
		}
	}
	for index, cue := range manifest.Audio.Cues {
		if !simpleManifestValue(cue.Event) {
			return fmt.Errorf(
				"%s.audio.cues[%d].event is invalid",
				manifest.Source,
				index+1,
			)
		}
		if !manifestIDWithNamespace(cue.Asset, "audio.") {
			return fmt.Errorf(
				"%s.audio.cues[%d].asset must be an audio asset id",
				manifest.Source,
				index+1,
			)
		}
		if !manifestVolume(cue.Volume) {
			return fmt.Errorf(
				"%s.audio.cues[%d].volume must be between 0 and 1",
				manifest.Source,
				index+1,
			)
		}
		if index > 0 &&
			manifest.Audio.Cues[index-1].Event >= cue.Event {
			return fmt.Errorf(
				"%s.audio.cues must have unique sorted events",
				manifest.Source,
			)
		}
	}
	if manifest.Audio.Cues == nil {
		return fmt.Errorf("%s.audio.cues must be an array", manifest.Source)
	}
	for index, track := range manifest.Audio.StageMusic {
		if !manifestIDWithNamespace(track.Stage, "stage.") {
			return fmt.Errorf(
				"%s.audio.stage_music[%d].stage must be a stage content id",
				manifest.Source,
				index+1,
			)
		}
		if !manifestIDWithNamespace(track.Asset, "audio.") {
			return fmt.Errorf(
				"%s.audio.stage_music[%d].asset must be an audio asset id",
				manifest.Source,
				index+1,
			)
		}
		if !manifestVolume(track.Volume) {
			return fmt.Errorf(
				"%s.audio.stage_music[%d].volume must be between 0 and 1",
				manifest.Source,
				index+1,
			)
		}
		if index > 0 &&
			manifest.Audio.StageMusic[index-1].Stage >= track.Stage {
			return fmt.Errorf(
				"%s.audio.stage_music must have unique sorted stages",
				manifest.Source,
			)
		}
	}
	if manifest.Audio.StageMusic == nil {
		return fmt.Errorf(
			"%s.audio.stage_music must be an array",
			manifest.Source,
		)
	}
	for index, warning := range manifest.Warnings {
		if warning.Code != unsupportedProjectFieldCode {
			return fmt.Errorf(
				"project manifest warning %d has unsupported code %q",
				index,
				warning.Code,
			)
		}
		if warning.Message != unsupportedProjectFieldText {
			return fmt.Errorf(
				"project manifest warning %d has invalid message",
				index,
			)
		}
		if !simpleManifestPath(warning.Path) {
			return fmt.Errorf(
				"project manifest warning %d has invalid path %q",
				index,
				warning.Path,
			)
		}
		if index > 0 &&
			manifest.Warnings[index-1].Path >= warning.Path {
			return fmt.Errorf(
				"project manifest warnings are not strictly sorted by path",
			)
		}
	}
	if manifest.Warnings == nil {
		return fmt.Errorf("project manifest warnings must be an array")
	}
	return nil
}

func validateManifestReferences(
	manifest ProjectManifest,
	definitions map[string]Definition,
) error {
	requireKind := func(field, id, kind string) (Definition, error) {
		definition, exists := definitions[id]
		if !exists {
			return Definition{}, fmt.Errorf(
				"%s.%s references missing content %q",
				manifest.Source,
				field,
				id,
			)
		}
		if definition.Kind() != kind {
			return Definition{}, fmt.Errorf(
				"%s.%s references %q with kind %q, want %q",
				manifest.Source,
				field,
				id,
				definition.Kind(),
				kind,
			)
		}
		return definition, nil
	}

	startStage, err := requireKind(
		"flow.start_stage",
		manifest.Flow.StartStage,
		"stage",
	)
	if err != nil {
		return err
	}
	if manifest.Locale.Default != "" {
		if _, err := requireKind(
			"locale.default",
			manifest.Locale.Default,
			"locale",
		); err != nil {
			return err
		}
		if _, err := requireKind(
			"locale.fallback",
			manifest.Locale.Fallback,
			"locale",
		); err != nil {
			return err
		}
	}
	if manifest.Font.Asset != "" {
		if _, err := requireKind(
			"font.asset",
			manifest.Font.Asset,
			"asset",
		); err != nil {
			return err
		}
	}
	requireAudioAsset := func(field, id string) error {
		definition, err := requireKind(field, id, "asset")
		if err != nil {
			return err
		}
		if definition.Data["asset_type"] != "audio" {
			return fmt.Errorf(
				"%s.%s references %q with asset_type %q, want %q",
				manifest.Source,
				field,
				id,
				definition.Data["asset_type"],
				"audio",
			)
		}
		return nil
	}
	for index, cue := range manifest.Audio.Cues {
		if err := requireAudioAsset(
			fmt.Sprintf("audio.cues[%d].asset", index+1),
			cue.Asset,
		); err != nil {
			return err
		}
	}
	for index, track := range manifest.Audio.StageMusic {
		if _, err := requireKind(
			fmt.Sprintf("audio.stage_music[%d].stage", index+1),
			track.Stage,
			"stage",
		); err != nil {
			return err
		}
		if err := requireAudioAsset(
			fmt.Sprintf("audio.stage_music[%d].asset", index+1),
			track.Asset,
		); err != nil {
			return err
		}
	}

	if manifest.Flow.StartSpawn == "" {
		return nil
	}
	foundSpawn := false
	rawSpawnPoints, _ := startStage.Data["spawn_points"].([]any)
	for _, raw := range rawSpawnPoints {
		spawn, _ := raw.(map[string]any)
		if id, _ := spawn["id"].(string); id == manifest.Flow.StartSpawn {
			foundSpawn = true
			break
		}
	}
	if !foundSpawn {
		return fmt.Errorf(
			"%s.flow.start_spawn references missing spawn point %q in %q",
			manifest.Source,
			manifest.Flow.StartSpawn,
			manifest.Flow.StartStage,
		)
	}
	return nil
}

func manifestIDWithNamespace(value, namespace string) bool {
	return strings.HasPrefix(value, namespace) &&
		validContentID(value)
}

func simpleManifestValue(value string) bool {
	if value == "" || len(value) > MaxContentIDBytes {
		return false
	}
	for index, character := range value {
		if character >= 'a' && character <= 'z' ||
			character >= '0' && character <= '9' && index > 0 ||
			index > 0 && (character == '_' || character == '-' || character == '.') {
			continue
		}
		return false
	}
	return true
}

func simpleInputValue(value string) bool {
	if value == "" || len(value) > MaxContentIDBytes {
		return false
	}
	for _, character := range value {
		if character < '!' || character > '~' {
			return false
		}
	}
	return true
}

func manifestVolume(value float64) bool {
	return value >= 0 &&
		value <= 1 &&
		!math.IsNaN(value) &&
		!math.IsInf(value, 0)
}

func simpleManifestPath(value string) bool {
	if value == "" {
		return false
	}
	for index, character := range value {
		if character >= 'a' && character <= 'z' ||
			character >= '0' && character <= '9' && index > 0 ||
			index > 0 && character == '_' {
			continue
		}
		return false
	}
	return true
}
