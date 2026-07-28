package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
)

const graphMarker = "RECREATE_GRAPH_JSON:"

type contentGraphEdge struct {
	ID   string `json:"id"`
	Path string `json:"path"`
}

type contentGraphNode struct {
	ID           string             `json:"id"`
	Kind         string             `json:"kind"`
	Source       string             `json:"source"`
	AssetPath    string             `json:"asset_path"`
	Dependencies []contentGraphEdge `json:"dependencies"`
	Dependents   []contentGraphEdge `json:"dependents"`
}

type contentGraph struct {
	Total     int                `json:"total"`
	EdgeCount int                `json:"edge_count"`
	Nodes     []contentGraphNode `json:"nodes"`
}

func decodeContentGraph(output string) (contentGraph, error) {
	for _, line := range strings.Split(output, "\n") {
		if !strings.HasPrefix(line, graphMarker) {
			continue
		}
		var graph contentGraph
		if err := json.Unmarshal(
			[]byte(strings.TrimPrefix(line, graphMarker)),
			&graph,
		); err != nil {
			return graph, fmt.Errorf("decode content graph: %w", err)
		}
		return graph, nil
	}
	return contentGraph{}, errors.New("LÖVE did not return a content graph")
}

func findContentGraphNode(
	graph contentGraph,
	contentID string,
) (contentGraphNode, bool) {
	for _, node := range graph.Nodes {
		if node.ID == contentID {
			return node, true
		}
	}
	return contentGraphNode{}, false
}

func uniqueEdgeIDs(edges []contentGraphEdge) []string {
	seen := map[string]bool{}
	var result []string
	for _, edge := range edges {
		if !seen[edge.ID] {
			seen[edge.ID] = true
			result = append(result, edge.ID)
		}
	}
	return result
}

func writeContentGraph(
	writer io.Writer,
	graph contentGraph,
	contentID string,
) error {
	if contentID == "" {
		fmt.Fprintf(
			writer,
			"Content graph: %d definitions, %d reference paths\n",
			graph.Total,
			graph.EdgeCount,
		)
		for _, node := range graph.Nodes {
			fmt.Fprintf(writer, "%s [%s]", node.ID, node.Kind)
			dependencies := uniqueEdgeIDs(node.Dependencies)
			if len(dependencies) > 0 {
				fmt.Fprintf(
					writer,
					" -> %s",
					strings.Join(dependencies, ", "),
				)
			}
			fmt.Fprintln(writer)
		}
		return nil
	}

	node, ok := findContentGraphNode(graph, contentID)
	if !ok {
		return fmt.Errorf("unknown content ID %q", contentID)
	}
	fmt.Fprintf(writer, "%s [%s]\n", node.ID, node.Kind)
	fmt.Fprintf(writer, "source: %s\n", node.Source)
	fmt.Fprintln(writer, "depends on:")
	if len(node.Dependencies) == 0 {
		fmt.Fprintln(writer, "  (none)")
	} else {
		for _, edge := range node.Dependencies {
			fmt.Fprintf(writer, "  %s via %s\n", edge.ID, edge.Path)
		}
	}
	fmt.Fprintln(writer, "used by:")
	if len(node.Dependents) == 0 {
		fmt.Fprintln(writer, "  (none)")
	} else {
		for _, edge := range node.Dependents {
			fmt.Fprintf(writer, "  %s via %s\n", edge.ID, edge.Path)
		}
	}
	return nil
}

func loadContentGraph(
	options globalOptions,
	projectPath string,
) (contentGraph, error) {
	command := exec.Command(options.lovePath, projectPath)
	command.Dir = projectPath
	command.Env = append(
		os.Environ(),
		"RECREATE_GRAPH=1",
		"RECREATE_HEADLESS=1",
	)
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	command.Stdout = &stdout
	command.Stderr = &stderr
	if err := command.Run(); err != nil {
		return contentGraph{}, fmt.Errorf(
			"content graph validation failed: %w\n%s%s",
			err,
			stdout.String(),
			stderr.String(),
		)
	}
	graph, err := decodeContentGraph(stdout.String())
	if err != nil {
		return graph, fmt.Errorf(
			"%w\nLÖVE output:\n%s%s",
			err,
			stdout.String(),
			stderr.String(),
		)
	}
	return graph, nil
}

func runContentGraph(
	options globalOptions,
	projectPath string,
	arguments []string,
) error {
	flags := flag.NewFlagSet("graph", flag.ContinueOnError)
	asJSON := flags.Bool("json", false, "print machine-readable JSON")
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if len(flags.Args()) > 1 {
		return errors.New("usage: lovectl graph [--json] [CONTENT_ID]")
	}
	contentID := ""
	if len(flags.Args()) == 1 {
		contentID = flags.Args()[0]
	}

	graph, err := loadContentGraph(options, projectPath)
	if err != nil {
		return err
	}
	if *asJSON {
		if contentID == "" {
			return printJSON(graph)
		}
		node, ok := findContentGraphNode(graph, contentID)
		if !ok {
			return fmt.Errorf("unknown content ID %q", contentID)
		}
		return printJSON(node)
	}
	return writeContentGraph(os.Stdout, graph, contentID)
}
