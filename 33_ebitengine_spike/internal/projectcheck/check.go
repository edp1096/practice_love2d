// Package projectcheck validates that one compiled content catalog can be
// constructed by every runtime-neutral subsystem used to start a game.
//
// The content compiler proves that Lua sources form a canonical catalog.
// Project validation goes further: it translates durable campaign and rule
// topology, then constructs every authored stage entry in every configured
// locale. No renderer or window is involved.
package projectcheck

import (
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/rulesruntime"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

// Report is a deterministic summary of the complete project surface checked
// by Validate. EntryBuildCount includes each stage x entry spawn x locale
// construction, including the implicit "default" entry used by legacy fixture
// stages with one authored controlled-player spawn.
type Report struct {
	DefinitionCount int `json:"definition_count"`
	StageCount      int `json:"stage_count"`
	EntryBuildCount int `json:"entry_build_count"`
	LocaleCount     int `json:"locale_count"`
}

type dependencies struct {
	buildCampaignConfig func(*content.Catalog) (campaign.Config, error)
	buildContentRules   func(*content.Catalog) (gamebuild.ContentRules, error)
	newRulesRuntime     func(
		campaign.Config,
		gamebuild.ContentRules,
	) (*rulesruntime.Executor, error)
	buildStage func(
		*content.Catalog,
		gamebuild.Options,
	) (*gamebuild.Result, error)
	newSimulation func(sim.Config) (*sim.Simulation, error)
}

var productionDependencies = dependencies{
	buildCampaignConfig: gamebuild.BuildCampaignConfig,
	buildContentRules:   gamebuild.BuildContentRules,
	newRulesRuntime:     rulesruntime.New,
	buildStage:          gamebuild.Build,
	newSimulation:       sim.New,
}

// Validate rejects a catalog unless every definition, durable subsystem, rule
// topology, and playable stage entry can be constructed before the canonical
// artifact is published.
func Validate(catalog *content.Catalog) (Report, error) {
	return validate(catalog, productionDependencies)
}

func validate(
	catalog *content.Catalog,
	deps dependencies,
) (Report, error) {
	if catalog == nil {
		return Report{}, fmt.Errorf("validate project: catalog is nil")
	}
	project := catalog.Project()
	context := projectContext(project)
	fail := func(phase string, err error) (Report, error) {
		return Report{}, fmt.Errorf(
			"validate %s: %s: %w",
			context,
			phase,
			err,
		)
	}

	if _, err := content.MarshalCanonical(catalog); err != nil {
		return fail("catalog", err)
	}
	if err := catalog.ValidateProjectReferences(); err != nil {
		return fail("manifest references", err)
	}

	for _, definition := range catalog.Definitions {
		id := definition.ID()
		if _, err := gamebuild.ValidateDefinition(
			catalog,
			id,
		); err != nil {
			return fail(
				fmt.Sprintf(
					"definition %q from %q",
					id,
					definition.Source,
				),
				err,
			)
		}
	}

	config, err := deps.buildCampaignConfig(catalog)
	if err != nil {
		return fail("campaign topology", err)
	}
	rules, err := deps.buildContentRules(catalog)
	if err != nil {
		return fail("content rules", err)
	}
	if _, err := deps.newRulesRuntime(config, rules); err != nil {
		return fail("campaign/rules topology", err)
	}

	report := Report{
		DefinitionCount: len(catalog.Definitions),
		StageCount:      len(config.Stages),
		LocaleCount:     len(config.Locales),
	}
	stageSources := definitionSources(catalog)
	for _, stage := range config.Stages {
		for _, entrySpawnID := range stage.EntrySpawns {
			for _, localeID := range config.Locales {
				options := gamebuild.Options{
					StageID:  stage.ID,
					SpawnID:  entrySpawnID,
					LocaleID: localeID,
				}
				built, err := deps.buildStage(catalog, options)
				if err != nil {
					return fail(
						stageBuildPhase(
							stage.ID,
							stageSources[stage.ID],
							entrySpawnID,
							localeID,
						),
						err,
					)
				}
				if _, err := deps.newSimulation(built.Config); err != nil {
					return fail(
						stageSimulationPhase(
							stage.ID,
							stageSources[stage.ID],
							entrySpawnID,
							localeID,
						),
						err,
					)
				}
				report.EntryBuildCount++
			}
		}
	}
	return report, nil
}

func projectContext(project content.ProjectManifest) string {
	if project.ID == "" && project.Source == "" {
		return "project with missing manifest identity"
	}
	return fmt.Sprintf("project %q from %q", project.ID, project.Source)
}

func definitionSources(catalog *content.Catalog) map[string]string {
	result := make(map[string]string, len(catalog.Definitions))
	for _, definition := range catalog.Definitions {
		result[definition.ID()] = definition.Source
	}
	return result
}

func stageBuildPhase(
	stageID string,
	source string,
	entrySpawnID string,
	localeID string,
) string {
	return fmt.Sprintf(
		"stage %q from %q entry %q locale %q build",
		stageID,
		source,
		entrySpawnID,
		localeID,
	)
}

func stageSimulationPhase(
	stageID string,
	source string,
	entrySpawnID string,
	localeID string,
) string {
	return fmt.Sprintf(
		"stage %q from %q entry %q locale %q simulation",
		stageID,
		source,
		entrySpawnID,
		localeID,
	)
}
