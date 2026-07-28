package main

import (
	"bytes"
	"strings"
	"testing"
)

func sampleContentGraph() contentGraph {
	return contentGraph{
		Total:     2,
		EdgeCount: 2,
		Nodes: []contentGraphNode{
			{
				ID:     "actor.hero",
				Kind:   "actor",
				Source: "game/content/actors/hero.lua",
				Dependencies: []contentGraphEdge{
					{ID: "ability.slash", Path: "components.action.combat.abilities[1]"},
					{ID: "ability.slash", Path: "components.action.combat.primary"},
				},
			},
			{
				ID:     "ability.slash",
				Kind:   "ability",
				Source: "game/content/abilities/slash.lua",
				Dependents: []contentGraphEdge{
					{ID: "actor.hero", Path: "components.action.combat.abilities[1]"},
					{ID: "actor.hero", Path: "components.action.combat.primary"},
				},
			},
		},
	}
}

func TestDecodeContentGraphIgnoresOtherLoveOutput(t *testing.T) {
	output := "[recreate] content valid\n" + graphMarker +
		`{"total":1,"edge_count":0,"nodes":[]}` + "\n"
	graph, err := decodeContentGraph(output)
	if err != nil {
		t.Fatal(err)
	}
	if graph.Total != 1 || graph.EdgeCount != 0 {
		t.Fatalf("unexpected graph: %#v", graph)
	}
}

func TestWriteContentGraphSummaryCollapsesDuplicateTargets(t *testing.T) {
	var output bytes.Buffer
	if err := writeContentGraph(&output, sampleContentGraph(), ""); err != nil {
		t.Fatal(err)
	}
	text := output.String()
	if !strings.Contains(
		text,
		"actor.hero [actor] -> ability.slash",
	) {
		t.Fatalf("missing dependency summary:\n%s", text)
	}
	if strings.Contains(text, "ability.slash, ability.slash") {
		t.Fatalf("summary did not collapse duplicate targets:\n%s", text)
	}
}

func TestWriteContentGraphDetailShowsPathsAndReverseEdges(t *testing.T) {
	var output bytes.Buffer
	if err := writeContentGraph(
		&output,
		sampleContentGraph(),
		"ability.slash",
	); err != nil {
		t.Fatal(err)
	}
	text := output.String()
	for _, expected := range []string{
		"ability.slash [ability]",
		"source: game/content/abilities/slash.lua",
		"used by:",
		"actor.hero via components.action.combat.primary",
	} {
		if !strings.Contains(text, expected) {
			t.Fatalf("detail lacks %q:\n%s", expected, text)
		}
	}
	if err := writeContentGraph(
		&output,
		sampleContentGraph(),
		"missing.content",
	); err == nil {
		t.Fatal("expected unknown content ID to fail")
	}
}
