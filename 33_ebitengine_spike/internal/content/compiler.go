package content

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	lua "github.com/yuin/gopher-lua"
)

const (
	defaultEvaluationTimeout = 2 * time.Second
	maxDefinitionBytes       = 8 << 20
)

type Compiler struct {
	EvaluationTimeout time.Duration
}

func Compile(ctx context.Context, sourceProject string) (*Catalog, error) {
	return (Compiler{}).Compile(ctx, sourceProject)
}

func (compiler Compiler) Compile(
	ctx context.Context,
	sourceProject string,
) (*Catalog, error) {
	if ctx == nil {
		return nil, fmt.Errorf("compile content: context is nil")
	}
	if sourceProject == "" {
		return nil, fmt.Errorf("compile content: source project is empty")
	}
	absoluteSource, err := filepath.Abs(sourceProject)
	if err != nil {
		return nil, fmt.Errorf("resolve source project %q: %w", sourceProject, err)
	}
	contentRoot := filepath.Join(absoluteSource, "game", "content")
	paths, err := discoverDefinitionPaths(contentRoot)
	if err != nil {
		return nil, err
	}
	if len(paths) == 0 {
		return nil, fmt.Errorf("%s: no content definitions found", contentRoot)
	}

	timeout := compiler.EvaluationTimeout
	if timeout <= 0 {
		timeout = defaultEvaluationTimeout
	}

	definitions := make([]Definition, 0, len(paths))
	sourcesByID := make(map[string]string, len(paths))
	for _, path := range paths {
		if err := ctx.Err(); err != nil {
			return nil, fmt.Errorf("compile content: %w", err)
		}
		relative, err := filepath.Rel(absoluteSource, path)
		if err != nil {
			return nil, fmt.Errorf("make %q project-relative: %w", path, err)
		}
		source := filepath.ToSlash(relative)
		data, err := evaluateDefinition(ctx, path, source, timeout)
		if err != nil {
			return nil, err
		}
		if err := validateDefinition(data, source); err != nil {
			return nil, err
		}
		id := data["id"].(string)
		if previous, exists := sourcesByID[id]; exists {
			return nil, fmt.Errorf(
				"%s: duplicate id %q (already declared in %s)",
				source,
				id,
				previous,
			)
		}
		sourcesByID[id] = source
		definitions = append(definitions, Definition{
			Source: source,
			Data:   data,
		})
	}

	sort.Slice(definitions, func(i, j int) bool {
		return definitions[i].ID() < definitions[j].ID()
	})
	catalog := &Catalog{
		SchemaVersion: CatalogSchemaVersion,
		Definitions:   definitions,
	}
	catalog.DependencyGraph = buildGraph(definitions)
	if err := validateCatalog(catalog); err != nil {
		return nil, err
	}
	return catalog, nil
}

func discoverDefinitionPaths(contentRoot string) ([]string, error) {
	info, err := os.Stat(contentRoot)
	if err != nil {
		return nil, fmt.Errorf("inspect content root %q: %w", contentRoot, err)
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("content root %q is not a directory", contentRoot)
	}

	var paths []string
	err = filepath.WalkDir(
		contentRoot,
		func(path string, entry fs.DirEntry, walkErr error) error {
			if walkErr != nil {
				return walkErr
			}
			if entry.Type()&os.ModeSymlink != 0 {
				return fmt.Errorf("%s: symbolic links are not allowed", path)
			}
			if entry.IsDir() {
				return nil
			}
			name := entry.Name()
			if filepath.Ext(name) != ".lua" ||
				strings.HasPrefix(name, "_") ||
				name == "init.lua" {
				return nil
			}
			info, err := entry.Info()
			if err != nil {
				return fmt.Errorf("inspect %s: %w", path, err)
			}
			if !info.Mode().IsRegular() {
				return fmt.Errorf("%s: content definition is not a regular file", path)
			}
			if info.Size() > maxDefinitionBytes {
				return fmt.Errorf(
					"%s: content definition exceeds %d bytes",
					path,
					maxDefinitionBytes,
				)
			}
			paths = append(paths, path)
			return nil
		},
	)
	if err != nil {
		return nil, fmt.Errorf("discover content definitions: %w", err)
	}
	sort.Strings(paths)
	return paths, nil
}

func evaluateDefinition(
	parent context.Context,
	path string,
	source string,
	timeout time.Duration,
) (map[string]any, error) {
	code, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", source, err)
	}
	if len(code) > maxDefinitionBytes {
		return nil, fmt.Errorf(
			"%s: content definition exceeds %d bytes",
			source,
			maxDefinitionBytes,
		)
	}

	state := lua.NewState(lua.Options{
		SkipOpenLibs:        true,
		IncludeGoStackTrace: false,
	})
	defer state.Close()

	evaluationContext, cancel := context.WithTimeout(parent, timeout)
	defer cancel()
	state.SetContext(evaluationContext)

	function, err := state.Load(strings.NewReader(string(code)), "@"+source)
	if err != nil {
		return nil, fmt.Errorf("%s: compile Lua: %w", source, err)
	}
	// No standard libraries or globals are opened. Each chunk receives its own
	// empty environment, so content cannot access files, processes, modules,
	// clocks, randomness, or definitions evaluated before it.
	state.SetFEnv(function, state.NewTable())
	state.Push(function)
	if err := state.PCall(0, lua.MultRet, nil); err != nil {
		if errors.Is(evaluationContext.Err(), context.DeadlineExceeded) {
			return nil, fmt.Errorf(
				"%s: evaluation exceeded %s",
				source,
				timeout,
			)
		}
		if errors.Is(evaluationContext.Err(), context.Canceled) {
			return nil, fmt.Errorf("%s: evaluation canceled", source)
		}
		return nil, fmt.Errorf("%s: evaluate Lua: %w", source, err)
	}
	if state.GetTop() != 1 {
		return nil, fmt.Errorf(
			"%s: content file must return exactly one value, returned %d",
			source,
			state.GetTop(),
		)
	}

	converted, err := convertLuaValue(
		state,
		state.Get(1),
		"content",
		make(map[*lua.LTable]string),
	)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", source, err)
	}
	object, ok := converted.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("%s: content file must return an object", source)
	}
	return object, nil
}

func convertLuaValue(
	state *lua.LState,
	value lua.LValue,
	path string,
	active map[*lua.LTable]string,
) (any, error) {
	switch typed := value.(type) {
	case *lua.LNilType:
		return nil, nil
	case lua.LBool:
		return bool(typed), nil
	case lua.LString:
		return string(typed), nil
	case lua.LNumber:
		number := float64(typed)
		if math.IsNaN(number) || math.IsInf(number, 0) {
			return nil, fmt.Errorf("%s contains a non-finite number", path)
		}
		return number, nil
	case *lua.LTable:
		return convertLuaTable(state, typed, path, active)
	case *lua.LFunction:
		return nil, fmt.Errorf("%s contains forbidden function value", path)
	case *lua.LUserData:
		return nil, fmt.Errorf("%s contains forbidden userdata value", path)
	case *lua.LState:
		return nil, fmt.Errorf("%s contains forbidden thread value", path)
	case lua.LChannel:
		return nil, fmt.Errorf("%s contains forbidden channel value", path)
	default:
		return nil, fmt.Errorf(
			"%s contains forbidden %s value",
			path,
			value.Type().String(),
		)
	}
}

func convertLuaTable(
	state *lua.LState,
	table *lua.LTable,
	path string,
	active map[*lua.LTable]string,
) (any, error) {
	if state.GetMetatable(table) != lua.LNil {
		return nil, fmt.Errorf("%s must not have a metatable", path)
	}
	if firstPath, exists := active[table]; exists {
		return nil, fmt.Errorf(
			"%s contains a table cycle back to %s",
			path,
			firstPath,
		)
	}
	active[table] = path
	defer delete(active, table)

	type entry struct {
		key   lua.LValue
		value lua.LValue
	}
	var entries []entry
	table.ForEach(func(key, value lua.LValue) {
		entries = append(entries, entry{key: key, value: value})
	})
	if len(entries) == 0 {
		// Lua has one empty-table representation. Content definitions use empty
		// tables as records/components, so the neutral representation is {}.
		return map[string]any{}, nil
	}

	keyKind := entries[0].key.Type()
	if keyKind != lua.LTString && keyKind != lua.LTNumber {
		return nil, fmt.Errorf(
			"%s contains forbidden %s key",
			path,
			keyKind.String(),
		)
	}
	for _, item := range entries[1:] {
		if item.key.Type() != keyKind {
			if item.key.Type() == lua.LTString ||
				item.key.Type() == lua.LTNumber {
				return nil, fmt.Errorf(
					"%s must not mix string and numeric keys",
					path,
				)
			}
			return nil, fmt.Errorf(
				"%s contains forbidden %s key",
				path,
				item.key.Type().String(),
			)
		}
	}

	if keyKind == lua.LTString {
		object := make(map[string]any, len(entries))
		for _, item := range entries {
			key := string(item.key.(lua.LString))
			child, err := convertLuaValue(
				state,
				item.value,
				objectPath(path, key),
				active,
			)
			if err != nil {
				return nil, err
			}
			object[key] = child
		}
		return object, nil
	}

	array := make([]any, len(entries))
	present := make([]bool, len(entries))
	for _, item := range entries {
		number := float64(item.key.(lua.LNumber))
		index := int(number)
		if math.IsNaN(number) || math.IsInf(number, 0) ||
			float64(index) != number ||
			index < 1 ||
			index > len(entries) {
			return nil, fmt.Errorf(
				"%s numeric keys must form a contiguous 1-based array",
				path,
			)
		}
		if present[index-1] {
			return nil, fmt.Errorf("%s contains duplicate array index %d", path, index)
		}
		child, err := convertLuaValue(
			state,
			item.value,
			fmt.Sprintf("%s[%d]", path, index),
			active,
		)
		if err != nil {
			return nil, err
		}
		array[index-1] = child
		present[index-1] = true
	}
	for index, exists := range present {
		if !exists {
			return nil, fmt.Errorf(
				"%s numeric keys must form a contiguous 1-based array (missing %d)",
				path,
				index+1,
			)
		}
	}
	return array, nil
}

func buildGraph(definitions []Definition) Graph {
	knownIDs := make(map[string]struct{}, len(definitions))
	for _, definition := range definitions {
		knownIDs[definition.ID()] = struct{}{}
	}

	dependencies := make(map[string][]Edge, len(definitions))
	dependents := make(map[string][]Edge, len(definitions))
	edgeCount := 0
	for _, definition := range definitions {
		sourceID := definition.ID()
		var edges []Edge
		walkReferences(
			definition.Data,
			"",
			"",
			func(targetID, path string) {
				if targetID == sourceID {
					return
				}
				if _, exists := knownIDs[targetID]; !exists {
					return
				}
				edges = append(edges, Edge{ID: targetID, Path: path})
			},
		)
		sort.Slice(edges, func(i, j int) bool {
			return edgeLess(edges[i], edges[j])
		})
		edges = uniqueEdges(edges)
		dependencies[sourceID] = edges
		edgeCount += len(edges)
		for _, edge := range edges {
			dependents[edge.ID] = append(
				dependents[edge.ID],
				Edge{ID: sourceID, Path: edge.Path},
			)
		}
	}

	nodes := make([]Node, 0, len(definitions))
	for _, definition := range definitions {
		id := definition.ID()
		reverse := dependents[id]
		sort.Slice(reverse, func(i, j int) bool {
			return edgeLess(reverse[i], reverse[j])
		})
		reverse = uniqueEdges(reverse)
		nodes = append(nodes, Node{
			ID:           id,
			Kind:         definition.Kind(),
			Source:       definition.Source,
			Dependencies: nonNilEdges(dependencies[id]),
			Dependents:   nonNilEdges(reverse),
		})
	}
	return Graph{
		Total:     len(nodes),
		EdgeCount: edgeCount,
		Nodes:     nodes,
	}
}

func walkReferences(
	value any,
	path string,
	field string,
	visit func(string, string),
) {
	switch typed := value.(type) {
	case string:
		// Fields named id or *_id identify a particular runtime instance/event
		// subject. They are selectors, not ownership/reference edges between
		// reusable content definitions. This also prevents coincidental ID
		// values in query predicates from polluting the build dependency graph.
		if field != "id" && !strings.HasSuffix(field, "_id") {
			visit(typed, path)
		}
	case []any:
		for index, child := range typed {
			walkReferences(
				child,
				fmt.Sprintf("%s[%d]", path, index+1),
				field,
				visit,
			)
		}
	case map[string]any:
		keys := make([]string, 0, len(typed))
		for key := range typed {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		for _, key := range keys {
			walkReferences(
				typed[key],
				graphPath(path, key),
				key,
				visit,
			)
		}
	}
}

func graphPath(parent, key string) string {
	if parent == "" {
		return key
	}
	return parent + "." + key
}

func objectPath(parent, key string) string {
	if parent == "" {
		return key
	}
	return parent + "." + key
}

func uniqueEdges(edges []Edge) []Edge {
	if len(edges) < 2 {
		return edges
	}
	output := edges[:1]
	for _, edge := range edges[1:] {
		last := output[len(output)-1]
		if edge.ID != last.ID || edge.Path != last.Path {
			output = append(output, edge)
		}
	}
	return output
}

func nonNilEdges(edges []Edge) []Edge {
	if edges == nil {
		return []Edge{}
	}
	return edges
}
