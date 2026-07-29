package main

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"embed"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

//go:embed maker_ui/*
var makerUI embed.FS

const makerBodyLimit = 2 * 1024 * 1024

type makerRuntime interface {
	call(method string, params map[string]any, target any) error
}

type synchronizedMakerRuntime struct {
	delegate makerRuntime
	mu       sync.Mutex
}

func (runtime *synchronizedMakerRuntime) call(
	method string,
	params map[string]any,
	target any,
) error {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	return runtime.delegate.call(method, params, target)
}

type makerServer struct {
	projectPath string
	runtime     makerRuntime
	token       string
	allowedHost string
	graph       contentGraph
	graphMu     sync.RWMutex
	opMu        sync.Mutex
	storeMu     sync.Mutex
	previewID   atomic.Int64
}

type makerAPIResponse struct {
	OK    bool   `json:"ok"`
	Data  any    `json:"data,omitempty"`
	Error string `json:"error,omitempty"`
}

type makerDefinitionRequest struct {
	Definition map[string]any `json:"definition"`
}

type makerContentResult struct {
	ID           string             `json:"id"`
	Kind         string             `json:"kind"`
	Source       string             `json:"source"`
	Definition   map[string]any     `json:"definition"`
	Dependencies []contentGraphEdge `json:"dependencies"`
	Dependents   []contentGraphEdge `json:"dependents"`
	ReadOnly     bool               `json:"read_only"`
	Revision     string             `json:"revision,omitempty"`
}

type makerCreateRequest struct {
	Kind      string `json:"kind"`
	Name      string `json:"name"`
	Reference string `json:"reference,omitempty"`
}

type makerPreviewRequest struct {
	Type      string  `json:"type"`
	ID        string  `json:"id"`
	Spawn     string  `json:"spawn,omitempty"`
	EntityID  string  `json:"entity_id,omitempty"`
	SpeakerID string  `json:"speaker_id,omitempty"`
	X         float64 `json:"x,omitempty"`
	Y         float64 `json:"y,omitempty"`
	Position  bool    `json:"position,omitempty"`
}

type makerInputRequest struct {
	Action string `json:"action"`
	Frames int    `json:"frames"`
}

func newMakerToken() (string, error) {
	value := make([]byte, 24)
	if _, err := rand.Read(value); err != nil {
		return "", err
	}
	return hex.EncodeToString(value), nil
}

func (server *makerServer) refreshGraph() error {
	var graph contentGraph
	if err := server.runtime.call(
		"Content.getGraph",
		nil,
		&graph,
	); err != nil {
		return err
	}
	server.graphMu.Lock()
	server.graph = graph
	server.graphMu.Unlock()
	return nil
}

func (server *makerServer) graphSnapshot() contentGraph {
	server.graphMu.RLock()
	defer server.graphMu.RUnlock()
	graph := server.graph
	graph.Nodes = append([]contentGraphNode(nil), server.graph.Nodes...)
	return graph
}

func (server *makerServer) contentNode(
	contentID string,
) (contentGraphNode, bool) {
	server.graphMu.RLock()
	defer server.graphMu.RUnlock()
	return findContentGraphNode(server.graph, contentID)
}

func writeMakerJSON(
	writer http.ResponseWriter,
	status int,
	data any,
	requestError error,
) {
	writer.Header().Set("Content-Type", "application/json; charset=utf-8")
	writer.Header().Set("Cache-Control", "no-store")
	writer.WriteHeader(status)
	response := makerAPIResponse{OK: requestError == nil, Data: data}
	if requestError != nil {
		response.Error = requestError.Error()
	}
	_ = json.NewEncoder(writer).Encode(response)
}

func makerMethod(
	writer http.ResponseWriter,
	request *http.Request,
	method string,
) bool {
	if request.Method == method {
		return true
	}
	writer.Header().Set("Allow", method)
	writeMakerJSON(
		writer,
		http.StatusMethodNotAllowed,
		nil,
		fmt.Errorf("method must be %s", method),
	)
	return false
}

func (server *makerServer) authorizeMutation(
	writer http.ResponseWriter,
	request *http.Request,
) bool {
	if request.Header.Get("X-Recreate-Token") == server.token {
		return true
	}
	writeMakerJSON(
		writer,
		http.StatusForbidden,
		nil,
		errors.New("missing or invalid maker token"),
	)
	return false
}

func decodeMakerRequest(
	writer http.ResponseWriter,
	request *http.Request,
	target any,
) error {
	request.Body = http.MaxBytesReader(
		writer,
		request.Body,
		makerBodyLimit,
	)
	decoder := json.NewDecoder(request.Body)
	decoder.UseNumber()
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		return fmt.Errorf("invalid JSON request: %w", err)
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		if err == nil {
			return errors.New("request contains more than one JSON value")
		}
		return fmt.Errorf("invalid trailing JSON: %w", err)
	}
	return nil
}

func (server *makerServer) handleProject(
	writer http.ResponseWriter,
	request *http.Request,
) {
	if !makerMethod(writer, request, http.MethodGet) {
		return
	}
	server.opMu.Lock()
	defer server.opMu.Unlock()
	var runtime map[string]any
	if err := server.runtime.call(
		"Runtime.getState",
		nil,
		&runtime,
	); err != nil {
		writeMakerJSON(writer, http.StatusBadGateway, nil, err)
		return
	}
	var world map[string]any
	if err := server.runtime.call(
		"World.getSnapshot",
		nil,
		&world,
	); err != nil {
		writeMakerJSON(writer, http.StatusBadGateway, nil, err)
		return
	}
	writeMakerJSON(writer, http.StatusOK, map[string]any{
		"name":    filepath.Base(server.projectPath),
		"runtime": runtime,
		"world":   world,
		"graph":   server.graphSnapshot(),
	}, nil)
}

func (server *makerServer) handleGraph(
	writer http.ResponseWriter,
	request *http.Request,
) {
	if !makerMethod(writer, request, http.MethodGet) {
		return
	}
	if request.URL.Query().Get("refresh") == "1" {
		server.opMu.Lock()
		defer server.opMu.Unlock()
		if err := server.refreshGraph(); err != nil {
			writeMakerJSON(writer, http.StatusBadGateway, nil, err)
			return
		}
	}
	writeMakerJSON(writer, http.StatusOK, server.graphSnapshot(), nil)
}

func (server *makerServer) handleDefinition(
	writer http.ResponseWriter,
	request *http.Request,
) {
	if !makerMethod(writer, request, http.MethodGet) {
		return
	}
	contentID := request.URL.Query().Get("id")
	if contentID == "" {
		writeMakerJSON(
			writer,
			http.StatusBadRequest,
			nil,
			errors.New("id query parameter is required"),
		)
		return
	}
	server.opMu.Lock()
	defer server.opMu.Unlock()
	var result makerContentResult
	if err := server.runtime.call(
		"Content.getDefinition",
		map[string]any{"contentId": contentID},
		&result,
	); err != nil {
		writeMakerJSON(writer, http.StatusNotFound, nil, err)
		return
	}
	node, found := server.contentNode(contentID)
	if !found || (result.Source != "" && node.Source != result.Source) {
		node = contentGraphNode{
			ID:     result.ID,
			Kind:   result.Kind,
			Source: result.Source,
		}
	}
	if node.Source == "" {
		node.Source = result.Source
	}
	result.Dependencies = node.Dependencies
	result.Dependents = node.Dependents
	result.ReadOnly = makerSourceReadOnly(node.Source)
	if !result.ReadOnly {
		path, err := server.editableSourcePath(node)
		if err != nil {
			writeMakerJSON(writer, http.StatusForbidden, nil, err)
			return
		}
		data, err := os.ReadFile(path)
		if err != nil {
			writeMakerJSON(
				writer,
				http.StatusInternalServerError,
				nil,
				err,
			)
			return
		}
		result.Revision = makerRevision(data)
		writer.Header().Set("ETag", `"`+result.Revision+`"`)
	}
	writeMakerJSON(writer, http.StatusOK, result, nil)
}

func (server *makerServer) validateDefinition(
	contentID string,
	definition map[string]any,
) (map[string]any, error) {
	var result map[string]any
	err := server.runtime.call(
		"Content.validateDefinition",
		map[string]any{
			"contentId":  contentID,
			"definition": definition,
		},
		&result,
	)
	return result, err
}

func (server *makerServer) handleValidate(
	writer http.ResponseWriter,
	request *http.Request,
) {
	if !makerMethod(writer, request, http.MethodPost) ||
		!server.authorizeMutation(writer, request) {
		return
	}
	contentID := request.URL.Query().Get("id")
	var input makerDefinitionRequest
	if err := decodeMakerRequest(writer, request, &input); err != nil {
		writeMakerJSON(writer, http.StatusBadRequest, nil, err)
		return
	}
	server.opMu.Lock()
	defer server.opMu.Unlock()
	result, err := server.validateDefinition(contentID, input.Definition)
	if err != nil {
		writeMakerJSON(writer, http.StatusUnprocessableEntity, nil, err)
		return
	}
	writeMakerJSON(writer, http.StatusOK, result, nil)
}

func makerSourceReadOnly(source string) bool {
	clean := filepath.ToSlash(filepath.Clean(source))
	return !strings.HasPrefix(clean, "game/content/") ||
		strings.Contains(clean, "/generated/") ||
		filepath.Ext(clean) != ".lua"
}

func makerRevision(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func pathInside(root string, candidate string) bool {
	relative, err := filepath.Rel(root, candidate)
	return err == nil && relative != ".." &&
		!strings.HasPrefix(relative, ".."+string(filepath.Separator))
}

func (server *makerServer) editableSourcePath(
	node contentGraphNode,
) (string, error) {
	if makerSourceReadOnly(node.Source) {
		return "", fmt.Errorf(
			"content source %q is generated or outside game/content",
			node.Source,
		)
	}
	if filepath.IsAbs(node.Source) {
		return "", errors.New("content source must be project-relative")
	}
	contentRoot, err := filepath.EvalSymlinks(filepath.Join(
		server.projectPath,
		"game",
		"content",
	))
	if err != nil {
		return "", err
	}
	path := filepath.Join(
		server.projectPath,
		filepath.FromSlash(node.Source),
	)
	info, err := os.Lstat(path)
	if err != nil {
		return "", err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return "", errors.New("content source must be a regular file")
	}
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil {
		return "", err
	}
	if !pathInside(contentRoot, resolved) {
		return "", errors.New("content source escapes game/content")
	}
	return resolved, nil
}

func encodeMakerDefinition(
	definition map[string]any,
) (data []byte, encodeError error) {
	defer func() {
		if panicValue := recover(); panicValue != nil {
			data = nil
			encodeError = fmt.Errorf(
				"encode content definition: %v",
				panicValue,
			)
		}
	}()
	var builder strings.Builder
	builder.WriteString("return ")
	writeLuaValue(&builder, definition, 0)
	builder.WriteByte('\n')
	return []byte(builder.String()), nil
}

// writeAtomicHostFile reports whether the destination was replaced. Errors
// after a successful rename mean the new bytes are visible but their directory
// entry could not be fully durability-synchronized; callers must not describe
// that state as an untouched file.
func writeAtomicHostFile(path string, data []byte) (bool, error) {
	directory := filepath.Dir(path)
	mode := os.FileMode(0o644)
	if info, err := os.Stat(path); err == nil {
		mode = info.Mode().Perm()
	} else if !os.IsNotExist(err) {
		return false, err
	}
	temporary, err := os.CreateTemp(
		directory,
		".recreate-maker-*.lua",
	)
	if err != nil {
		return false, err
	}
	temporaryPath := temporary.Name()
	cleanup := true
	defer func() {
		if cleanup {
			_ = temporary.Close()
			_ = os.Remove(temporaryPath)
		}
	}()
	if err := temporary.Chmod(mode); err != nil {
		return false, err
	}
	if _, err := temporary.Write(data); err != nil {
		return false, err
	}
	if err := temporary.Sync(); err != nil {
		return false, err
	}
	if err := temporary.Close(); err != nil {
		return false, err
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		return false, err
	}
	cleanup = false
	directoryHandle, err := os.Open(directory)
	if err != nil {
		return true, err
	}
	syncError := directoryHandle.Sync()
	closeError := directoryHandle.Close()
	if syncError != nil {
		return true, syncError
	}
	if closeError != nil {
		return true, closeError
	}
	return true, nil
}

func (server *makerServer) handleSave(
	writer http.ResponseWriter,
	request *http.Request,
) {
	if !makerMethod(writer, request, http.MethodPost) ||
		!server.authorizeMutation(writer, request) {
		return
	}
	contentID := request.URL.Query().Get("id")
	var input makerDefinitionRequest
	if err := decodeMakerRequest(writer, request, &input); err != nil {
		writeMakerJSON(writer, http.StatusBadRequest, nil, err)
		return
	}
	expectedRevision := strings.Trim(
		request.Header.Get("If-Match"),
		`"`,
	)
	if expectedRevision == "" {
		writeMakerJSON(
			writer,
			http.StatusPreconditionRequired,
			nil,
			errors.New("If-Match content revision is required"),
		)
		return
	}

	server.opMu.Lock()
	defer server.opMu.Unlock()
	server.storeMu.Lock()
	defer server.storeMu.Unlock()

	node, found := server.contentNode(contentID)
	if !found {
		if err := server.refreshGraph(); err == nil {
			node, found = server.contentNode(contentID)
		}
	}
	if !found {
		writeMakerJSON(
			writer,
			http.StatusNotFound,
			nil,
			fmt.Errorf("unknown content ID %q", contentID),
		)
		return
	}
	path, err := server.editableSourcePath(node)
	if err != nil {
		writeMakerJSON(writer, http.StatusForbidden, nil, err)
		return
	}
	validated, err := server.validateDefinition(
		contentID,
		input.Definition,
	)
	if err != nil {
		writeMakerJSON(writer, http.StatusUnprocessableEntity, nil, err)
		return
	}
	encoded, err := encodeMakerDefinition(input.Definition)
	if err != nil {
		writeMakerJSON(writer, http.StatusBadRequest, nil, err)
		return
	}

	original, err := os.ReadFile(path)
	if err != nil {
		writeMakerJSON(writer, http.StatusInternalServerError, nil, err)
		return
	}
	originalRevision := makerRevision(original)
	if originalRevision != expectedRevision {
		writer.Header().Set("ETag", `"`+originalRevision+`"`)
		writeMakerJSON(
			writer,
			http.StatusConflict,
			map[string]any{"revision": originalRevision},
			errors.New(
				"content changed outside Maker; reload it before saving",
			),
		)
		return
	}
	warnings := make([]string, 0)
	replaced, writeError := writeAtomicHostFile(path, encoded)
	if writeError != nil {
		if !replaced {
			writeMakerJSON(
				writer,
				http.StatusInternalServerError,
				nil,
				writeError,
			)
			return
		}
		warnings = append(
			warnings,
			"content file was replaced, but directory durability sync failed: "+
				writeError.Error(),
		)
	}
	writtenRevision := makerRevision(encoded)
	var runtime map[string]any
	if err := server.runtime.call(
		"App.reloadContent",
		nil,
		&runtime,
	); err != nil {
		current, readError := os.ReadFile(path)
		restoreError := readError
		sourceRestored := false
		externalEditPreserved := false
		if readError == nil {
			if makerRevision(current) != writtenRevision {
				restoreError = errors.New(
					"file changed again; external edit was preserved",
				)
				externalEditPreserved = true
			} else {
				var restored bool
				restored, restoreError = writeAtomicHostFile(path, original)
				sourceRestored = restored
			}
		}
		var recovered map[string]any
		recoveryError := server.runtime.call(
			"App.reloadContent",
			nil,
			&recovered,
		)
		reloadError := fmt.Errorf("reload failed: %w", err)
		if restoreError != nil {
			reloadError = fmt.Errorf(
				"%v; restore/reconciliation warning: %w",
				reloadError,
				restoreError,
			)
		}
		if recoveryError != nil {
			reloadError = fmt.Errorf(
				"%v; runtime recovery failed: %w",
				reloadError,
				recoveryError,
			)
		}
		writeMakerJSON(
			writer,
			http.StatusInternalServerError,
			map[string]any{
				"source_restored":         sourceRestored,
				"external_edit_preserved": externalEditPreserved,
				"written_revision":        writtenRevision,
			},
			reloadError,
		)
		return
	}

	graphNode := node
	graphSynced := true
	if err := server.refreshGraph(); err != nil {
		graphSynced = false
		warnings = append(
			warnings,
			"content was saved and reloaded, but graph refresh failed: "+
				err.Error(),
		)
	} else if refreshed, ok := server.contentNode(contentID); ok {
		graphNode = refreshed
	}

	current := makerContentResult{
		ID:         contentID,
		Kind:       node.Kind,
		Source:     node.Source,
		Definition: input.Definition,
	}
	if err := server.runtime.call(
		"Content.getDefinition",
		map[string]any{"contentId": contentID},
		&current,
	); err != nil {
		current = makerContentResult{
			ID:         contentID,
			Kind:       node.Kind,
			Source:     node.Source,
			Definition: input.Definition,
		}
		warnings = append(
			warnings,
			"content was saved and reloaded, but the canonical definition "+
				"could not be read back: "+err.Error(),
		)
	}
	if current.ID == "" {
		current.ID = contentID
	}
	if current.Kind == "" {
		current.Kind = graphNode.Kind
	}
	if current.Source == "" {
		current.Source = graphNode.Source
	}
	current.Dependencies = graphNode.Dependencies
	current.Dependents = graphNode.Dependents
	current.ReadOnly = false
	current.Revision = writtenRevision
	writer.Header().Set("ETag", `"`+writtenRevision+`"`)
	writeMakerJSON(writer, http.StatusOK, map[string]any{
		"validated":    validated,
		"content":      current,
		"runtime":      runtime,
		"revision":     writtenRevision,
		"warnings":     warnings,
		"graph_synced": graphSynced,
	}, nil)
}

func (server *makerServer) handleCreate(
	writer http.ResponseWriter,
	request *http.Request,
) {
	if !makerMethod(writer, request, http.MethodPost) ||
		!server.authorizeMutation(writer, request) {
		return
	}
	var input makerCreateRequest
	if err := decodeMakerRequest(writer, request, &input); err != nil {
		writeMakerJSON(writer, http.StatusBadRequest, nil, err)
		return
	}
	server.opMu.Lock()
	defer server.opMu.Unlock()
	server.storeMu.Lock()
	defer server.storeMu.Unlock()

	arguments := []string{input.Kind, input.Name}
	if input.Reference != "" {
		arguments = append(arguments, input.Reference)
	}
	paths, err := createScaffold(server.projectPath, arguments)
	if err != nil {
		writeMakerJSON(writer, http.StatusBadRequest, nil, err)
		return
	}
	var runtime map[string]any
	if err := server.runtime.call(
		"App.reloadContent",
		nil,
		&runtime,
	); err != nil {
		removeErrors := make([]string, 0)
		for _, path := range paths {
			if removeError := os.Remove(path); removeError != nil &&
				!os.IsNotExist(removeError) {
				removeErrors = append(
					removeErrors,
					path+": "+removeError.Error(),
				)
			}
		}
		var recovered map[string]any
		recoveryError := server.runtime.call(
			"App.reloadContent",
			nil,
			&recovered,
		)
		createError := fmt.Errorf("created content failed to reload: %w", err)
		if len(removeErrors) > 0 {
			createError = fmt.Errorf(
				"%v; created file cleanup failed: %s",
				createError,
				strings.Join(removeErrors, "; "),
			)
		}
		if recoveryError != nil {
			createError = fmt.Errorf(
				"%v; runtime recovery failed: %w",
				createError,
				recoveryError,
			)
		}
		writeMakerJSON(
			writer,
			http.StatusUnprocessableEntity,
			map[string]any{
				"paths":          paths,
				"cleanup_errors": removeErrors,
			},
			createError,
		)
		return
	}
	warnings := make([]string, 0)
	graphSynced := true
	if err := server.refreshGraph(); err != nil {
		graphSynced = false
		warnings = append(
			warnings,
			"content files were created and reloaded, but graph refresh "+
				"failed: "+err.Error(),
		)
	}
	relativePaths := make([]string, 0, len(paths))
	for _, path := range paths {
		relative, _ := filepath.Rel(server.projectPath, path)
		relativePaths = append(relativePaths, filepath.ToSlash(relative))
	}
	writeMakerJSON(writer, http.StatusCreated, map[string]any{
		"paths":        relativePaths,
		"runtime":      runtime,
		"graph":        server.graphSnapshot(),
		"warnings":     warnings,
		"graph_synced": graphSynced,
	}, nil)
}

func entityWithMakerTag(
	world map[string]any,
	tag string,
) string {
	entities, _ := world["entities"].([]any)
	for _, raw := range entities {
		entity, _ := raw.(map[string]any)
		tags, _ := entity["tags"].([]any)
		for _, candidate := range tags {
			if candidate == tag {
				id, _ := entity["id"].(string)
				return id
			}
		}
	}
	return ""
}

func (server *makerServer) handlePreview(
	writer http.ResponseWriter,
	request *http.Request,
) {
	if !makerMethod(writer, request, http.MethodPost) ||
		!server.authorizeMutation(writer, request) {
		return
	}
	var input makerPreviewRequest
	if err := decodeMakerRequest(writer, request, &input); err != nil {
		writeMakerJSON(writer, http.StatusBadRequest, nil, err)
		return
	}
	server.opMu.Lock()
	defer server.opMu.Unlock()
	var result map[string]any
	var err error
	switch input.Type {
	case "stage":
		params := map[string]any{"stageId": input.ID}
		if input.Spawn != "" {
			params["spawnId"] = input.Spawn
		}
		err = server.runtime.call("App.startNewGame", params, &result)
	case "actor":
		params := map[string]any{
			"actorId": input.ID,
			"entityId": "maker.preview." +
				strconv.FormatInt(server.previewID.Add(1), 10),
		}
		if input.Position {
			params["x"] = input.X
			params["y"] = input.Y
		}
		err = server.runtime.call("Entity.spawn", params, &result)
	case "dialogue":
		params := map[string]any{"dialogueId": input.ID}
		if input.SpeakerID != "" {
			params["speakerId"] = input.SpeakerID
		}
		err = server.runtime.call("Dialogue.start", params, &result)
	case "ability":
		entityID := input.EntityID
		if entityID == "" {
			var world map[string]any
			if worldError := server.runtime.call(
				"World.getSnapshot",
				nil,
				&world,
			); worldError != nil {
				err = worldError
			} else {
				entityID = entityWithMakerTag(world, "player")
			}
		}
		if err == nil && entityID == "" {
			err = errors.New("ability preview needs a player entity")
		} else if err == nil {
			err = server.runtime.call(
				"Entity.requestAbility",
				map[string]any{
					"entityId":  entityID,
					"abilityId": input.ID,
				},
				&result,
			)
		}
	default:
		err = fmt.Errorf("unsupported preview type %q", input.Type)
	}
	if err != nil {
		writeMakerJSON(writer, http.StatusUnprocessableEntity, nil, err)
		return
	}
	writeMakerJSON(writer, http.StatusOK, result, nil)
}

func (server *makerServer) handleInput(
	writer http.ResponseWriter,
	request *http.Request,
) {
	if !makerMethod(writer, request, http.MethodPost) ||
		!server.authorizeMutation(writer, request) {
		return
	}
	var input makerInputRequest
	if err := decodeMakerRequest(writer, request, &input); err != nil {
		writeMakerJSON(writer, http.StatusBadRequest, nil, err)
		return
	}
	if input.Frames == 0 {
		input.Frames = 1
	}
	if input.Frames < 1 || input.Frames > 600 {
		writeMakerJSON(
			writer,
			http.StatusBadRequest,
			nil,
			errors.New("frames must be between 1 and 600"),
		)
		return
	}
	server.opMu.Lock()
	defer server.opMu.Unlock()
	var result map[string]any
	err := server.runtime.call(
		"Input.action",
		map[string]any{
			"action": input.Action,
			"value":  1,
			"frames": input.Frames,
		},
		&result,
	)
	if err != nil {
		writeMakerJSON(writer, http.StatusUnprocessableEntity, nil, err)
		return
	}
	writeMakerJSON(writer, http.StatusOK, result, nil)
}

func (server *makerServer) handleScreenshot(
	writer http.ResponseWriter,
	request *http.Request,
) {
	if !makerMethod(writer, request, http.MethodGet) ||
		!server.authorizeMutation(writer, request) {
		return
	}
	server.opMu.Lock()
	defer server.opMu.Unlock()
	var result struct {
		Data   string `json:"data"`
		Format string `json:"format"`
	}
	if err := server.runtime.call(
		"Page.captureScreenshot",
		nil,
		&result,
	); err != nil {
		writeMakerJSON(writer, http.StatusBadGateway, nil, err)
		return
	}
	decoded, err := base64.StdEncoding.DecodeString(result.Data)
	if err != nil {
		writeMakerJSON(writer, http.StatusBadGateway, nil, err)
		return
	}
	writer.Header().Set("Content-Type", "image/png")
	writer.Header().Set("Cache-Control", "no-store")
	writer.WriteHeader(http.StatusOK)
	_, _ = writer.Write(decoded)
}

func (server *makerServer) handleUI(
	writer http.ResponseWriter,
	request *http.Request,
) {
	if !makerMethod(writer, request, http.MethodGet) {
		return
	}
	path := strings.TrimPrefix(request.URL.Path, "/")
	if path == "" {
		path = "index.html"
	}
	switch path {
	case "index.html", "app.js", "style.css":
	default:
		http.NotFound(writer, request)
		return
	}
	data, err := makerUI.ReadFile("maker_ui/" + path)
	if err != nil {
		http.NotFound(writer, request)
		return
	}
	if path == "index.html" {
		data = []byte(strings.ReplaceAll(
			string(data),
			"__RECREATE_MAKER_TOKEN__",
			server.token,
		))
		writer.Header().Set("Content-Type", "text/html; charset=utf-8")
	} else if path == "app.js" {
		writer.Header().Set(
			"Content-Type",
			"application/javascript; charset=utf-8",
		)
	} else {
		writer.Header().Set("Content-Type", "text/css; charset=utf-8")
	}
	writer.Header().Set("Cache-Control", "no-store")
	writer.Header().Set(
		"Content-Security-Policy",
		"default-src 'self'; img-src 'self' blob:; "+
			"style-src 'self'; script-src 'self'; connect-src 'self'; "+
			"object-src 'none'; base-uri 'none'; form-action 'none'; "+
			"frame-ancestors 'none'",
	)
	_, _ = writer.Write(data)
}

func (server *makerServer) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/project", server.handleProject)
	mux.HandleFunc("/api/graph", server.handleGraph)
	mux.HandleFunc("/api/content", server.handleDefinition)
	mux.HandleFunc("/api/content/validate", server.handleValidate)
	mux.HandleFunc("/api/content/save", server.handleSave)
	mux.HandleFunc("/api/content/create", server.handleCreate)
	mux.HandleFunc("/api/preview", server.handlePreview)
	mux.HandleFunc("/api/input", server.handleInput)
	mux.HandleFunc("/api/screenshot", server.handleScreenshot)
	mux.HandleFunc("/", server.handleUI)
	return http.HandlerFunc(func(
		writer http.ResponseWriter,
		request *http.Request,
	) {
		writer.Header().Set("X-Content-Type-Options", "nosniff")
		writer.Header().Set("X-Frame-Options", "DENY")
		writer.Header().Set("Referrer-Policy", "no-referrer")
		if server.allowedHost != "" &&
			request.Host != server.allowedHost {
			writeMakerJSON(
				writer,
				http.StatusForbidden,
				nil,
				errors.New("invalid Maker host"),
			)
			return
		}
		origin := request.Header.Get("Origin")
		if origin != "" && origin != "http://"+request.Host {
			writeMakerJSON(
				writer,
				http.StatusForbidden,
				nil,
				errors.New("cross-origin Maker request denied"),
			)
			return
		}
		mux.ServeHTTP(writer, request)
	})
}

func validateMakerListenAddress(address string) error {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return fmt.Errorf("invalid maker listen address: %w", err)
	}
	if host == "localhost" {
		return nil
	}
	ip := net.ParseIP(host)
	if ip == nil || !ip.IsLoopback() {
		return errors.New(
			"maker must listen on a loopback address",
		)
	}
	return nil
}

func runMaker(
	options globalOptions,
	projectPath string,
	arguments []string,
) error {
	flags := flag.NewFlagSet("maker", flag.ContinueOnError)
	listenAddress := flags.String(
		"listen",
		"127.0.0.1:0",
		"loopback HTTP address for the Maker UI",
	)
	noOpen := flags.Bool(
		"no-open",
		false,
		"do not open the system browser",
	)
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if len(flags.Args()) != 0 {
		return errors.New(
			"usage: lovectl maker [--listen 127.0.0.1:PORT] [--no-open]",
		)
	}
	if err := validateMakerListenAddress(*listenAddress); err != nil {
		return err
	}
	listener, err := net.Listen("tcp", *listenAddress)
	if err != nil {
		return err
	}
	defer listener.Close()

	runtimeDirectory, err :=
		os.MkdirTemp("", "recreate_maker_runtime_")
	if err != nil {
		return err
	}
	defer os.RemoveAll(runtimeDirectory)
	logPath := filepath.Join(runtimeDirectory, "love.log")
	logFile, err := os.Create(logPath)
	if err != nil {
		return err
	}
	defer logFile.Close()
	debugPort, err := availablePort()
	if err != nil {
		return err
	}
	process, err := startLove(
		options.lovePath,
		projectPath,
		debugPort,
		logFile,
		runtimeDirectory,
	)
	if err != nil {
		return err
	}
	defer forceStop(process)
	client := newProtocolClient(
		"127.0.0.1",
		debugPort,
		20*time.Second,
	)
	if err := waitForBridge(
		client,
		process,
		20*time.Second,
	); err != nil {
		return visualFailure(err, logPath)
	}
	var started map[string]any
	if err := client.call(
		"App.startNewGame",
		nil,
		&started,
	); err != nil {
		return visualFailure(err, logPath)
	}
	token, err := newMakerToken()
	if err != nil {
		return err
	}
	maker := &makerServer{
		projectPath: projectPath,
		runtime: &synchronizedMakerRuntime{
			delegate: client,
		},
		token:       token,
		allowedHost: listener.Addr().String(),
	}
	if err := maker.refreshGraph(); err != nil {
		return visualFailure(err, logPath)
	}

	httpServer := &http.Server{
		Handler:           maker.handler(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	serverErrors := make(chan error, 1)
	go func() {
		serverErrors <- httpServer.Serve(listener)
	}()
	address := "http://" + listener.Addr().String() + "/"
	fmt.Printf(
		"Recreate Maker: %s\n"+
			"  project: %s\n"+
			"  preview save data is isolated\n"+
			"  press Ctrl+C to stop\n",
		address,
		projectPath,
	)
	if !*noOpen {
		command := exec.Command("xdg-open", address)
		if err := command.Start(); err != nil {
			fmt.Fprintf(
				os.Stderr,
				"lovectl: could not open browser: %v\n",
				err,
			)
		}
	}

	signalContext, stopSignals := signal.NotifyContext(
		context.Background(),
		os.Interrupt,
		syscall.SIGTERM,
	)
	defer stopSignals()
	var runError error
	select {
	case <-signalContext.Done():
	case runError = <-serverErrors:
		if errors.Is(runError, http.ErrServerClosed) {
			runError = nil
		}
	case processError := <-process.done:
		process.command = nil
		runError = fmt.Errorf(
			"LÖVE preview exited: %w (log: %s)",
			processError,
			logPath,
		)
	}
	shutdownContext, cancel := context.WithTimeout(
		context.Background(),
		3*time.Second,
	)
	defer cancel()
	_ = httpServer.Shutdown(shutdownContext)
	if process.command != nil {
		var quit map[string]any
		maker.opMu.Lock()
		_ = maker.runtime.call("App.quit", nil, &quit)
		maker.opMu.Unlock()
		select {
		case <-process.done:
			process.command = nil
		case <-time.After(2 * time.Second):
		}
	}
	return runError
}
