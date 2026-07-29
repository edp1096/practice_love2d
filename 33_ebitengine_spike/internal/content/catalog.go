package content

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"math"
	"os"
	"path"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strings"
)

const (
	CatalogSchemaVersion = 2
	// MaxContentIDBytes matches the durable campaign identifier contract.
	// Content IDs are ASCII, so bytes and characters have the same length.
	MaxContentIDBytes = 128
)

var contentIDPattern = regexp.MustCompile(
	`^[a-z][a-z0-9_]*\.[a-z][a-z0-9_.-]*$`,
)

func validContentID(id string) bool {
	return len(id) <= MaxContentIDBytes &&
		contentIDPattern.MatchString(id)
}

// Catalog is the deterministic, runtime-neutral representation emitted by the
// content compiler. Definitions and graph nodes are ordered by content ID.
type Catalog struct {
	SchemaVersion   int             `json:"schema_version"`
	Manifest        ProjectManifest `json:"project"`
	Definitions     []Definition    `json:"definitions"`
	DependencyGraph Graph           `json:"graph"`
}

// Definition retains the project-relative source path for diagnostics while
// keeping the source data runtime-neutral.
type Definition struct {
	Source string         `json:"source"`
	Data   map[string]any `json:"data"`
}

type Graph struct {
	Total     int    `json:"total"`
	EdgeCount int    `json:"edge_count"`
	Nodes     []Node `json:"nodes"`
}

type Node struct {
	ID           string `json:"id"`
	Kind         string `json:"kind"`
	Source       string `json:"source"`
	Dependencies []Edge `json:"dependencies"`
	Dependents   []Edge `json:"dependents"`
}

type Edge struct {
	ID   string `json:"id"`
	Path string `json:"path"`
}

func (definition Definition) ID() string {
	id, _ := definition.Data["id"].(string)
	return id
}

func (definition Definition) Kind() string {
	kind, _ := definition.Data["kind"].(string)
	return kind
}

// Load decodes and validates a compiled catalog from a stream.
func Load(reader io.Reader) (*Catalog, error) {
	if reader == nil {
		return nil, fmt.Errorf("decode content catalog: reader is nil")
	}
	decoder := json.NewDecoder(reader)
	decoder.UseNumber()
	decoder.DisallowUnknownFields()

	var catalog Catalog
	if err := decoder.Decode(&catalog); err != nil {
		return nil, fmt.Errorf("decode content catalog: %w", err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			return nil, fmt.Errorf("decode content catalog: trailing JSON value")
		}
		return nil, fmt.Errorf("decode content catalog: trailing data: %w", err)
	}
	if err := validateCatalog(&catalog); err != nil {
		return nil, err
	}
	return &catalog, nil
}

func LoadBytes(data []byte) (*Catalog, error) {
	return Load(bytes.NewReader(data))
}

func LoadFS(filesystem fs.FS, path string) (*Catalog, error) {
	if filesystem == nil {
		return nil, fmt.Errorf("load content catalog: filesystem is nil")
	}
	file, err := filesystem.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open content catalog %q: %w", path, err)
	}
	defer file.Close()
	catalog, err := Load(file)
	if err != nil {
		return nil, fmt.Errorf("load content catalog %q: %w", path, err)
	}
	return catalog, nil
}

func LoadFile(path string) (*Catalog, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open content catalog %q: %w", path, err)
	}
	defer file.Close()
	catalog, err := Load(file)
	if err != nil {
		return nil, fmt.Errorf("load content catalog %q: %w", path, err)
	}
	return catalog, nil
}

// IDs returns the stable ID order used by the compiled artifact.
func (catalog *Catalog) IDs() []string {
	if catalog == nil {
		return nil
	}
	ids := make([]string, len(catalog.Definitions))
	for index, definition := range catalog.Definitions {
		ids[index] = definition.ID()
	}
	return ids
}

// Graph returns a copy of the dependency graph's slice structure. Edge values
// are immutable scalars, so this is enough to keep the catalog's indexes safe.
func (catalog *Catalog) Graph() Graph {
	if catalog == nil {
		return Graph{}
	}
	graph := catalog.DependencyGraph
	graph.Nodes = make([]Node, len(catalog.DependencyGraph.Nodes))
	for index, node := range catalog.DependencyGraph.Nodes {
		graph.Nodes[index] = node
		graph.Nodes[index].Dependencies = append(
			[]Edge(nil),
			node.Dependencies...,
		)
		graph.Nodes[index].Dependents = append(
			[]Edge(nil),
			node.Dependents...,
		)
	}
	return graph
}

// Definition returns canonical raw JSON for one definition's data object.
// Source metadata remains available in the catalog artifact but does not leak
// into typed runtime definitions.
func (catalog *Catalog) Definition(id string) (json.RawMessage, bool) {
	definition, exists := catalog.lookup(id)
	if !exists {
		return nil, false
	}
	data, err := json.Marshal(definition.Data)
	if err != nil {
		// Compiled/loaded catalogs have already passed JSON validation.
		return nil, false
	}
	return json.RawMessage(data), true
}

// Decode unmarshals one definition into a runtime-owned typed structure.
func (catalog *Catalog) Decode(id string, target any) error {
	if target == nil {
		return fmt.Errorf("decode content %q: target is nil", id)
	}
	raw, exists := catalog.Definition(id)
	if !exists {
		return fmt.Errorf("decode content %q: definition not found", id)
	}
	if err := json.Unmarshal(raw, target); err != nil {
		return fmt.Errorf("decode content %q: %w", id, err)
	}
	return nil
}

// WithDefinition validates an editor draft against the complete catalog and
// returns an immutable candidate catalog with a freshly derived dependency
// graph. The receiver is never mutated.
func (catalog *Catalog) WithDefinition(
	id string,
	raw json.RawMessage,
) (*Catalog, error) {
	if catalog == nil {
		return nil, fmt.Errorf("validate content %q: catalog is nil", id)
	}
	existing, exists := catalog.lookup(id)
	if !exists {
		return nil, fmt.Errorf("validate content %q: definition not found", id)
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	var draft map[string]any
	if err := decoder.Decode(&draft); err != nil {
		return nil, fmt.Errorf("validate content %q: %w", id, err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			return nil, fmt.Errorf(
				"validate content %q: trailing JSON value",
				id,
			)
		}
		return nil, fmt.Errorf("validate content %q: %w", id, err)
	}
	draftID, _ := draft["id"].(string)
	if draftID != id {
		return nil, fmt.Errorf(
			"validate content %q: definition id is %q",
			id,
			draftID,
		)
	}
	draftKind, _ := draft["kind"].(string)
	if draftKind != existing.Kind() {
		return nil, fmt.Errorf(
			"validate content %q: kind changed from %q to %q",
			id,
			existing.Kind(),
			draftKind,
		)
	}

	definitions := make([]Definition, len(catalog.Definitions))
	copy(definitions, catalog.Definitions)
	index := sort.Search(len(definitions), func(index int) bool {
		return definitions[index].ID() >= id
	})
	definitions[index] = Definition{
		Source: existing.Source,
		Data:   draft,
	}
	candidate := &Catalog{
		SchemaVersion:   CatalogSchemaVersion,
		Manifest:        cloneProjectManifest(catalog.Manifest),
		Definitions:     definitions,
		DependencyGraph: buildGraph(definitions),
	}
	if err := validateCatalog(candidate); err != nil {
		return nil, fmt.Errorf("validate content %q: %w", id, err)
	}
	return candidate, nil
}

func (catalog *Catalog) lookup(id string) (Definition, bool) {
	if catalog == nil {
		return Definition{}, false
	}
	index := sort.Search(len(catalog.Definitions), func(index int) bool {
		return catalog.Definitions[index].ID() >= id
	})
	if index == len(catalog.Definitions) ||
		catalog.Definitions[index].ID() != id {
		return Definition{}, false
	}
	return catalog.Definitions[index], true
}

// MarshalCanonical emits stable, human-reviewable JSON. encoding/json sorts
// map keys; all slices in Catalog have already been given a semantic order.
func MarshalCanonical(catalog *Catalog) ([]byte, error) {
	if catalog == nil {
		return nil, fmt.Errorf("marshal content catalog: catalog is nil")
	}
	if err := validateCatalog(catalog); err != nil {
		return nil, err
	}
	data, err := json.MarshalIndent(catalog, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("marshal content catalog: %w", err)
	}
	return append(data, '\n'), nil
}

// ParseCanonical verifies the envelope and all invariants needed by a runtime.
// It intentionally accepts non-canonical whitespace; callers can marshal the
// result again when byte-for-byte canonical output is required.
func ParseCanonical(data []byte) (*Catalog, error) {
	return LoadBytes(data)
}

// WriteCanonical writes through a same-directory temporary file and rename so
// the runtime never observes a partially written catalog.
func WriteCanonical(path string, catalog *Catalog) error {
	data, err := MarshalCanonical(catalog)
	if err != nil {
		return err
	}

	directory := filepath.Dir(path)
	if err := os.MkdirAll(directory, 0o755); err != nil {
		return fmt.Errorf("create catalog directory %q: %w", directory, err)
	}
	file, err := os.CreateTemp(directory, ".catalog-*.json")
	if err != nil {
		return fmt.Errorf("create temporary catalog: %w", err)
	}
	tempPath := file.Name()
	keep := false
	defer func() {
		_ = file.Close()
		if !keep {
			_ = os.Remove(tempPath)
		}
	}()

	if _, err := file.Write(data); err != nil {
		return fmt.Errorf("write temporary catalog: %w", err)
	}
	if err := file.Chmod(0o644); err != nil {
		return fmt.Errorf("set temporary catalog permissions: %w", err)
	}
	if err := file.Sync(); err != nil {
		return fmt.Errorf("sync temporary catalog: %w", err)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("close temporary catalog: %w", err)
	}
	if err := os.Rename(tempPath, path); err != nil {
		return fmt.Errorf("replace catalog %q: %w", path, err)
	}
	keep = true
	return nil
}

func validateCatalog(catalog *Catalog) error {
	if catalog.SchemaVersion != CatalogSchemaVersion {
		return fmt.Errorf(
			"content catalog schema_version must be %d, got %d",
			CatalogSchemaVersion,
			catalog.SchemaVersion,
		)
	}
	if err := validateProjectManifest(catalog.Manifest); err != nil {
		return err
	}
	if catalog.DependencyGraph.Total != len(catalog.Definitions) ||
		catalog.DependencyGraph.Total != len(catalog.DependencyGraph.Nodes) {
		return fmt.Errorf(
			"content catalog totals disagree: definitions=%d nodes=%d total=%d",
			len(catalog.Definitions),
			len(catalog.DependencyGraph.Nodes),
			catalog.DependencyGraph.Total,
		)
	}

	seen := make(map[string]string, len(catalog.Definitions))
	definitionsByID := make(map[string]Definition, len(catalog.Definitions))
	lastID := ""
	for index, definition := range catalog.Definitions {
		if err := validateNeutralValue(
			definition.Data,
			definition.Source+": content",
		); err != nil {
			return err
		}
		if err := validateDefinition(definition.Data, definition.Source); err != nil {
			return err
		}
		id := definition.ID()
		if previous, exists := seen[id]; exists {
			return fmt.Errorf(
				"%s: duplicate id %q (already declared in %s)",
				definition.Source,
				id,
				previous,
			)
		}
		if index > 0 && id <= lastID {
			return fmt.Errorf("content definitions are not strictly sorted by id")
		}
		seen[id] = definition.Source
		definitionsByID[id] = definition
		lastID = id
	}
	edgeCount := 0
	reverseEdgeCount := 0
	forward := make(map[string]struct{})
	reverse := make(map[string]struct{})
	lastID = ""
	for index, node := range catalog.DependencyGraph.Nodes {
		definition, exists := definitionsByID[node.ID]
		if !exists {
			return fmt.Errorf("content graph has unknown node %q", node.ID)
		}
		if node.Kind != definition.Kind() {
			return fmt.Errorf(
				"%s: graph kind %q does not match definition kind %q",
				node.ID,
				node.Kind,
				definition.Kind(),
			)
		}
		if node.Source != definition.Source {
			return fmt.Errorf(
				"%s: graph source %q does not match definition source %q",
				node.ID,
				node.Source,
				definition.Source,
			)
		}
		if index > 0 && node.ID <= lastID {
			return fmt.Errorf("content graph nodes are not strictly sorted by id")
		}
		if !strictlySortedEdges(node.Dependencies) {
			return fmt.Errorf("%s: dependencies are not sorted", node.ID)
		}
		if !strictlySortedEdges(node.Dependents) {
			return fmt.Errorf("%s: dependents are not sorted", node.ID)
		}
		for _, edge := range node.Dependencies {
			if _, exists := seen[edge.ID]; !exists {
				return fmt.Errorf(
					"%s: dependency %q does not exist",
					node.ID,
					edge.ID,
				)
			}
			if edge.Path == "" {
				return fmt.Errorf("%s: dependency path must not be empty", node.ID)
			}
			if edge.ID == node.ID {
				return fmt.Errorf("%s: self dependencies are not allowed", node.ID)
			}
			forward[graphEdgeKey(node.ID, edge.ID, edge.Path)] = struct{}{}
		}
		for _, edge := range node.Dependents {
			if _, exists := seen[edge.ID]; !exists {
				return fmt.Errorf(
					"%s: dependent %q does not exist",
					node.ID,
					edge.ID,
				)
			}
			if edge.Path == "" {
				return fmt.Errorf("%s: dependent path must not be empty", node.ID)
			}
			if edge.ID == node.ID {
				return fmt.Errorf("%s: self dependents are not allowed", node.ID)
			}
			reverse[graphEdgeKey(edge.ID, node.ID, edge.Path)] = struct{}{}
		}
		edgeCount += len(node.Dependencies)
		reverseEdgeCount += len(node.Dependents)
		lastID = node.ID
	}
	if edgeCount != catalog.DependencyGraph.EdgeCount {
		return fmt.Errorf(
			"content graph edge_count is %d, counted %d",
			catalog.DependencyGraph.EdgeCount,
			edgeCount,
		)
	}
	if reverseEdgeCount != catalog.DependencyGraph.EdgeCount {
		return fmt.Errorf(
			"content graph reverse edge count is %d, expected %d",
			reverseEdgeCount,
			catalog.DependencyGraph.EdgeCount,
		)
	}
	if len(forward) != len(reverse) {
		return fmt.Errorf("content graph forward and reverse edges disagree")
	}
	for key := range forward {
		if _, exists := reverse[key]; !exists {
			return fmt.Errorf("content graph is missing a reverse edge")
		}
	}
	expectedGraph := buildGraph(catalog.Definitions)
	if !reflect.DeepEqual(catalog.DependencyGraph, expectedGraph) {
		return fmt.Errorf(
			"content graph does not match references in compiled definitions",
		)
	}
	return nil
}

func validateDefinition(data map[string]any, source string) error {
	if source == "" ||
		strings.Contains(source, `\`) ||
		strings.HasPrefix(source, "/") ||
		strings.HasPrefix(source, "../") ||
		source == ".." ||
		path.Clean(source) != source ||
		!strings.HasPrefix(source, "game/content/") ||
		path.Ext(source) != ".lua" {
		return fmt.Errorf(
			"%q: source must be a slash-normalized project-relative game/content Lua path",
			source,
		)
	}
	if data == nil {
		return fmt.Errorf("%s: content file must return an object", source)
	}
	version, ok := numberAsInt(data["schema_version"])
	if !ok || version != 1 {
		return fmt.Errorf("%s: schema_version must be 1", source)
	}
	kind, ok := data["kind"].(string)
	if !ok || kind == "" {
		return fmt.Errorf("%s: kind must be a non-empty string", source)
	}
	id, ok := data["id"].(string)
	if !ok || !validContentID(id) {
		return fmt.Errorf(
			"%s: id must match namespace.name using lowercase characters and be at most %d bytes",
			source,
			MaxContentIDBytes,
		)
	}
	return nil
}

func numberAsInt(value any) (int, bool) {
	switch number := value.(type) {
	case float64:
		integer := int(number)
		return integer, float64(integer) == number
	case json.Number:
		integer, err := number.Int64()
		return int(integer), err == nil && int64(int(integer)) == integer
	case int:
		return number, true
	default:
		return 0, false
	}
}

func edgeLess(left, right Edge) bool {
	if left.ID != right.ID {
		return left.ID < right.ID
	}
	return left.Path < right.Path
}

func strictlySortedEdges(edges []Edge) bool {
	for index := 1; index < len(edges); index++ {
		if !edgeLess(edges[index-1], edges[index]) {
			return false
		}
	}
	return true
}

func graphEdgeKey(source, target, path string) string {
	return source + "\x00" + target + "\x00" + path
}

func validateNeutralValue(value any, currentPath string) error {
	switch typed := value.(type) {
	case bool, string:
		return nil
	case float64:
		if math.IsNaN(typed) || math.IsInf(typed, 0) {
			return fmt.Errorf("%s contains a non-finite number", currentPath)
		}
		return nil
	case json.Number:
		number, err := typed.Float64()
		if err != nil || math.IsNaN(number) || math.IsInf(number, 0) {
			return fmt.Errorf("%s contains an invalid JSON number", currentPath)
		}
		return nil
	case []any:
		for index, child := range typed {
			if err := validateNeutralValue(
				child,
				fmt.Sprintf("%s[%d]", currentPath, index+1),
			); err != nil {
				return err
			}
		}
		return nil
	case map[string]any:
		keys := make([]string, 0, len(typed))
		for key := range typed {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		for _, key := range keys {
			if err := validateNeutralValue(
				typed[key],
				currentPath+"."+key,
			); err != nil {
				return err
			}
		}
		return nil
	case nil:
		return fmt.Errorf("%s contains forbidden null value", currentPath)
	default:
		return fmt.Errorf(
			"%s contains unsupported %T value",
			currentPath,
			value,
		)
	}
}
