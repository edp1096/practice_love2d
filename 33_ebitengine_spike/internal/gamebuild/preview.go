package gamebuild

import (
	"encoding/json"
	"errors"
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

// EntityPreviewOptions describes one actor instance in authored pixel units.
// It is intentionally independent from a stage so Maker/debug previews can
// translate an actor without rebuilding the running world.
//
// Components use the same recursive override semantics as a stage spawn in
// 32_recreate: object fields are merged, arrays are merged by index, and scalar
// values replace the actor default.
type EntityPreviewOptions struct {
	ActorID    string
	EntityID   string
	Name       string
	X          float64
	Y          float64
	Tags       []string
	Components map[string]json.RawMessage
	LocaleID   string
	Impact     ImpactOptions
}

// EntityPreview is the complete immutable content bundle required to add one
// translated actor to a running simulation. Dialogue and Quest are populated
// only when the actor's supported interaction chain references them.
type EntityPreview struct {
	Entity           sim.EntityConfig
	Metadata         InstanceMetadata
	Dialogue         *sim.DialogueDefinition
	Quest            *sim.QuestDefinition
	InteractionRange sim.Coord
}

// DialoguePreviewOptions identifies an authored dialogue and its locale. The
// speaker entity is runtime context and deliberately does not belong here.
type DialoguePreviewOptions struct {
	DialogueID string
	LocaleID   string
}

// DialoguePreview is the runtime definition for a dialogue plus an optional
// quest definition referenced by the supported start node or one of its
// choices. StartQuestOnOpen distinguishes a start-node action from a choice
// dependency; merely registering Quest does not start it.
type DialoguePreview struct {
	Dialogue         sim.DialogueDefinition
	StartNodeID      string
	Quest            *sim.QuestDefinition
	StartQuestOnOpen bool
}

// BuildEntityPreview translates one actor plus instance overrides without
// constructing or validating an unrelated stage. The returned values are
// detached from the catalog and may be handed to a transactional runtime
// mutation.
func BuildEntityPreview(
	catalog *content.Catalog,
	options EntityPreviewOptions,
) (*EntityPreview, error) {
	if catalog == nil {
		return nil, errors.New("gamebuild: catalog is required")
	}
	if options.ActorID == "" {
		return nil, errors.New("gamebuild: actor ID is required")
	}
	if options.EntityID == "" {
		return nil, errors.New("gamebuild: entity ID is required")
	}
	if !finite(options.X) || !finite(options.Y) {
		return nil, errors.New("gamebuild: entity position must be finite")
	}
	buildOptions := Options{
		LocaleID: options.LocaleID,
		Impact:   options.Impact,
	}
	applyDefaults(&buildOptions)
	strings, err := loadLocaleStrings(catalog, buildOptions.LocaleID)
	if err != nil {
		return nil, err
	}
	entity, metadata, dialogue, quest, interactionRange, err := buildEntity(
		catalog,
		strings,
		stageSpawn{
			ID:         options.EntityID,
			Actor:      options.ActorID,
			Name:       options.Name,
			Tags:       append([]string(nil), options.Tags...),
			Components: cloneRawMessages(options.Components),
			Position: stagePosition{
				X: options.X,
				Y: options.Y,
			},
		},
		buildOptions.Impact,
	)
	if err != nil {
		return nil, fmt.Errorf(
			"build entity preview %q: %w",
			options.EntityID,
			err,
		)
	}
	return &EntityPreview{
		Entity:           entity,
		Metadata:         metadata,
		Dialogue:         dialogue,
		Quest:            quest,
		InteractionRange: interactionRange,
	}, nil
}

// BuildDialoguePreview resolves any catalog dialogue independently from the
// active stage. This is the content boundary used by Dialogue.start previews;
// choosing the optional speaker entity remains a runtime concern.
func BuildDialoguePreview(
	catalog *content.Catalog,
	options DialoguePreviewOptions,
) (*DialoguePreview, error) {
	if catalog == nil {
		return nil, errors.New("gamebuild: catalog is required")
	}
	if options.DialogueID == "" {
		return nil, errors.New("gamebuild: dialogue ID is required")
	}
	localeID := options.LocaleID
	if localeID == "" {
		localeID = defaultLocaleID
	}
	strings, err := loadLocaleStrings(catalog, localeID)
	if err != nil {
		return nil, err
	}
	result, err := buildDialoguePreview(
		catalog,
		strings,
		options.DialogueID,
	)
	if err != nil {
		return nil, fmt.Errorf(
			"build dialogue preview %q: %w",
			options.DialogueID,
			err,
		)
	}
	return result, nil
}
