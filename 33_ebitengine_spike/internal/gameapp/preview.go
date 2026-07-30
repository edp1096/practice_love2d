package gameapp

import (
	"errors"
	"fmt"
	"sort"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/protocol"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func (runtime *Runtime) spawnEntity(
	params protocol.SpawnEntityParams,
) (any, error) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	if err := runtime.rejectMakerMutationWhileEquipmentPendingLocked(
		"spawn entity",
	); err != nil {
		return nil, err
	}

	entityID, nextSequence := runtime.previewEntityIDLocked(
		params.ActorID,
		params.EntityID,
	)
	x, y := runtime.previewPositionLocked(params)
	preview, err := gamebuild.BuildEntityPreview(
		runtime.catalog,
		gamebuild.EntityPreviewOptions{
			ActorID:  params.ActorID,
			EntityID: entityID,
			X:        x,
			Y:        y,
			LocaleID: runtime.buildOptions.LocaleID,
			Impact:   runtime.buildOptions.Impact,
		},
	)
	if err != nil {
		return nil, err
	}

	// The spike has one semantic-input owner. Previewing an authored player
	// actor must not steal control from the running stage; explicit automation
	// can still drive its ability through Entity.requestAbility.
	preview.Entity.Controlled = false
	preview.Metadata.Controlled = false
	bundle := sim.EntityPreviewConfig{
		Entity:           preview.Entity,
		Dialogue:         preview.Dialogue,
		Quest:            preview.Quest,
		InteractionRange: preview.InteractionRange,
	}
	if err := runtime.simulation.SpawnEntityPreview(bundle); err != nil {
		return nil, fmt.Errorf("spawn entity: %w", err)
	}

	runtime.previewEntities[entityID] = previewEntity{
		config:   preview.Entity,
		metadata: preview.Metadata,
	}
	runtime.previewSequence = nextSequence
	runtime.revision++
	entity, found := runtime.entityDTOLocked(entityID)
	if !found {
		return nil, errors.New("spawned entity is missing from the snapshot")
	}
	return entity, nil
}

func (runtime *Runtime) previewEntityIDLocked(
	actorID string,
	requested string,
) (string, uint64) {
	next := runtime.previewSequence + 1
	if requested != "" {
		return requested, next
	}
	return fmt.Sprintf("%s.%d", actorID, next), next
}

func (runtime *Runtime) previewPositionLocked(
	params protocol.SpawnEntityParams,
) (float64, float64) {
	if params.X != nil {
		return *params.X, *params.Y
	}
	camera := runtime.simulation.RenderFrame().Camera
	return coordPixels(camera.Center.X), coordPixels(camera.Center.Y)
}

func (runtime *Runtime) queueEntityRemoval(
	params protocol.RemoveEntityParams,
) (any, error) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	if err := runtime.rejectMakerMutationWhileEquipmentPendingLocked(
		"remove entity",
	); err != nil {
		return nil, err
	}

	if runtime.pendingRemovals[params.EntityID] {
		return removeEntityResult{
			EntityID: params.EntityID,
			Queued:   true,
		}, nil
	}
	candidate := runtime.simulation.Clone()
	if err := candidate.RemoveEntity(params.EntityID); err != nil {
		return nil, fmt.Errorf("remove entity: %w", err)
	}
	runtime.pendingRemovals[params.EntityID] = true
	runtime.revision++
	return removeEntityResult{
		EntityID: params.EntityID,
		Queued:   true,
	}, nil
}

type removeEntityResult struct {
	EntityID string `json:"entity_id"`
	Queued   bool   `json:"queued"`
}

func (runtime *Runtime) flushPendingRemovalsLocked() error {
	if len(runtime.pendingRemovals) == 0 {
		return nil
	}
	ids := make([]string, 0, len(runtime.pendingRemovals))
	for id := range runtime.pendingRemovals {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		if err := runtime.simulation.RemoveEntity(id); err != nil {
			return fmt.Errorf("flush removal %q: %w", id, err)
		}
		delete(runtime.previewEntities, id)
		delete(runtime.pendingAbilities, id)
		delete(runtime.moving, id)
		delete(runtime.pendingRemovals, id)
	}
	return nil
}

func (runtime *Runtime) startDialogue(
	params protocol.StartDialogueParams,
) (any, error) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	if err := runtime.rejectMakerMutationWhileEquipmentPendingLocked(
		"start dialogue",
	); err != nil {
		return nil, err
	}

	if runtime.campaign.Snapshot().Mode != campaign.ModePlaying {
		return nil, errors.New(
			"start dialogue: game flow is modal",
		)
	}
	if runtime.dialogue != nil ||
		runtime.activeShopID != "" ||
		runtime.inventoryOpen {
		return nil, errors.New(
			"start dialogue: another modal is active",
		)
	}
	if params.SpeakerID != "" &&
		runtime.pendingRemovals[params.SpeakerID] {
		return nil, fmt.Errorf(
			"dialogue speaker %q is queued for removal",
			params.SpeakerID,
		)
	}
	preview, err := gamebuild.BuildDialoguePreview(
		runtime.catalog,
		gamebuild.DialoguePreviewOptions{
			DialogueID: params.DialogueID,
			LocaleID:   runtime.buildOptions.LocaleID,
		},
	)
	if err != nil {
		return nil, err
	}
	if err := runtime.simulation.StartDialoguePreview(
		sim.DialoguePreviewConfig{
			Dialogue:   preview.Dialogue,
			Quest:      preview.Quest,
			StartQuest: preview.StartQuestOnOpen,
		},
		params.SpeakerID,
	); err != nil {
		return nil, fmt.Errorf("start dialogue: %w", err)
	}
	runtime.revision++
	return startDialogueResult{
		Applied:    true,
		DialogueID: preview.Dialogue.ID,
		NodeID:     preview.StartNodeID,
	}, nil
}

type startDialogueResult struct {
	Applied    bool   `json:"applied"`
	DialogueID string `json:"dialogue_id"`
	NodeID     string `json:"node_id"`
}

func (runtime *Runtime) entityDTOLocked(id string) (entityDTO, bool) {
	for _, entity := range runtime.worldSnapshotLocked().Entities {
		if entity.ID == id {
			return entity, true
		}
	}
	return entityDTO{}, false
}

func clonePreviewEntities(
	source map[string]previewEntity,
) map[string]previewEntity {
	result := make(map[string]previewEntity, len(source))
	for id, preview := range source {
		preview.metadata.Tags = append(
			[]string(nil),
			preview.metadata.Tags...,
		)
		if preview.metadata.BehaviorAI != nil {
			behavior := *preview.metadata.BehaviorAI
			behavior.Patterns = append(
				[]gamebuild.AIPatternMetadata(nil),
				preview.metadata.BehaviorAI.Patterns...,
			)
			for index := range behavior.Patterns {
				behavior.Patterns[index].Attacks = append(
					[]gamebuild.AIAttackMetadata(nil),
					behavior.Patterns[index].Attacks...,
				)
			}
			preview.metadata.BehaviorAI = &behavior
		}
		result[id] = preview
	}
	return result
}
