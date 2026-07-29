package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type fakeMakerRuntime struct {
	mu            sync.Mutex
	graph         contentGraph
	definitions   map[string]map[string]any
	validateErr   error
	graphErr      error
	definitionErr error
	reloadErrors  []error
	calls         []string
}

func assignMakerTarget(target any, value any) error {
	encoded, err := json.Marshal(value)
	if err != nil {
		return err
	}
	return json.Unmarshal(encoded, target)
}

func (runtime *fakeMakerRuntime) call(
	method string,
	params map[string]any,
	target any,
) error {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	runtime.calls = append(runtime.calls, method)
	switch method {
	case "Content.getGraph":
		if runtime.graphErr != nil {
			return runtime.graphErr
		}
		return assignMakerTarget(target, runtime.graph)
	case "Content.getDefinition":
		if runtime.definitionErr != nil {
			return runtime.definitionErr
		}
		contentID, _ := params["contentId"].(string)
		definition, found := runtime.definitions[contentID]
		if !found {
			return errors.New("unknown content")
		}
		node, _ := findContentGraphNode(runtime.graph, contentID)
		return assignMakerTarget(target, map[string]any{
			"id":         contentID,
			"kind":       definition["kind"],
			"source":     node.Source,
			"definition": definition,
		})
	case "Content.validateDefinition":
		if runtime.validateErr != nil {
			return runtime.validateErr
		}
		return assignMakerTarget(target, map[string]any{
			"valid": true,
		})
	case "App.reloadContent":
		if len(runtime.reloadErrors) > 0 {
			err := runtime.reloadErrors[0]
			runtime.reloadErrors = runtime.reloadErrors[1:]
			if err != nil {
				return err
			}
		}
		return assignMakerTarget(target, map[string]any{
			"reloaded": true,
		})
	case "Runtime.getState":
		return assignMakerTarget(target, map[string]any{
			"profile": "action-rpg",
		})
	case "World.getSnapshot":
		return assignMakerTarget(target, map[string]any{
			"available": true,
		})
	case "Page.captureScreenshot":
		return assignMakerTarget(target, map[string]any{
			"data":   base64.StdEncoding.EncodeToString([]byte("png")),
			"format": "png",
		})
	default:
		return assignMakerTarget(target, map[string]any{
			"accepted": true,
		})
	}
}

type blockingMakerRuntime struct {
	mu             sync.Mutex
	calls          []string
	stateStarted   chan struct{}
	stateRelease   <-chan struct{}
	inputCallStart chan struct{}
}

func (runtime *blockingMakerRuntime) call(
	method string,
	_ map[string]any,
	target any,
) error {
	runtime.mu.Lock()
	runtime.calls = append(runtime.calls, method)
	runtime.mu.Unlock()

	switch method {
	case "Runtime.getState":
		runtime.stateStarted <- struct{}{}
		<-runtime.stateRelease
		return assignMakerTarget(target, map[string]any{
			"profile": "action-rpg",
		})
	case "World.getSnapshot":
		return assignMakerTarget(target, map[string]any{
			"available": true,
		})
	case "Input.action":
		runtime.inputCallStart <- struct{}{}
		return assignMakerTarget(target, map[string]any{
			"accepted": true,
		})
	default:
		return errors.New("unexpected runtime method: " + method)
	}
}

func (runtime *blockingMakerRuntime) callSequence() []string {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	return append([]string(nil), runtime.calls...)
}

type eofNotifyingReader struct {
	reader *strings.Reader
	done   chan struct{}
	once   sync.Once
}

func (reader *eofNotifyingReader) Read(buffer []byte) (int, error) {
	count, err := reader.reader.Read(buffer)
	if errors.Is(err, io.EOF) {
		reader.once.Do(func() {
			close(reader.done)
		})
	}
	return count, err
}

func makerTestServer(
	t *testing.T,
	source string,
) (*makerServer, *fakeMakerRuntime, string, []byte) {
	t.Helper()
	root := t.TempDir()
	path := filepath.Join(root, filepath.FromSlash(source))
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	original := []byte(`return {
    schema_version = 1,
    kind = "actor",
    id = "actor.hero",
    name = "Hero",
}
`)
	if err := os.WriteFile(path, original, 0o640); err != nil {
		t.Fatal(err)
	}
	graph := contentGraph{
		Total: 1,
		Nodes: []contentGraphNode{{
			ID:     "actor.hero",
			Kind:   "actor",
			Source: source,
		}},
	}
	runtime := &fakeMakerRuntime{
		graph: graph,
		definitions: map[string]map[string]any{
			"actor.hero": {
				"schema_version": float64(1),
				"kind":           "actor",
				"id":             "actor.hero",
				"name":           "Hero",
			},
		},
	}
	server := &makerServer{
		projectPath: root,
		runtime:     runtime,
		token:       "test-token",
		graph:       graph,
	}
	return server, runtime, path, original
}

func makerRequest(
	t *testing.T,
	server *makerServer,
	method string,
	target string,
	body string,
	revision string,
) *httptest.ResponseRecorder {
	t.Helper()
	request := httptest.NewRequest(method, target, strings.NewReader(body))
	if method != http.MethodGet {
		request.Header.Set("X-Recreate-Token", server.token)
		request.Header.Set("Content-Type", "application/json")
	}
	if revision != "" {
		request.Header.Set("If-Match", `"`+revision+`"`)
	}
	response := httptest.NewRecorder()
	server.handler().ServeHTTP(response, request)
	return response
}

func TestMakerDefinitionReturnsRevisionAndReferences(t *testing.T) {
	server, _, _, original := makerTestServer(
		t,
		"game/content/actors/hero.lua",
	)
	response := makerRequest(
		t,
		server,
		http.MethodGet,
		"/api/content?id=actor.hero",
		"",
		"",
	)
	if response.Code != http.StatusOK {
		t.Fatalf("status %d: %s", response.Code, response.Body.String())
	}
	if got := response.Header().Get("ETag"); got != `"`+makerRevision(original)+`"` {
		t.Fatalf("unexpected ETag %q", got)
	}
	var payload struct {
		OK   bool               `json:"ok"`
		Data makerContentResult `json:"data"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if !payload.OK || payload.Data.ReadOnly ||
		payload.Data.Revision != makerRevision(original) {
		t.Fatalf("unexpected content response: %+v", payload)
	}
}

func TestMakerSaveValidatesWritesAndRejectsStaleRevision(t *testing.T) {
	server, runtime, path, original := makerTestServer(
		t,
		"game/content/actors/hero.lua",
	)
	body := `{"definition":{"schema_version":1,"kind":"actor",` +
		`"id":"actor.hero","name":"Edited"}}`
	response := makerRequest(
		t,
		server,
		http.MethodPost,
		"/api/content/save?id=actor.hero",
		body,
		makerRevision(original),
	)
	if response.Code != http.StatusOK {
		t.Fatalf("status %d: %s", response.Code, response.Body.String())
	}
	current, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(current, []byte(`name = "Edited"`)) {
		t.Fatalf("definition was not written:\n%s", current)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o640 {
		t.Fatalf("file mode changed to %o", info.Mode().Perm())
	}
	if len(runtime.calls) < 3 ||
		runtime.calls[0] != "Content.validateDefinition" {
		t.Fatalf("unexpected runtime calls: %v", runtime.calls)
	}

	stale := makerRequest(
		t,
		server,
		http.MethodPost,
		"/api/content/save?id=actor.hero",
		body,
		makerRevision(original),
	)
	if stale.Code != http.StatusConflict {
		t.Fatalf("stale status %d: %s", stale.Code, stale.Body.String())
	}
}

func TestMakerSaveRollbackAndValidationFailureLeaveSourceUntouched(
	t *testing.T,
) {
	t.Run("validation", func(t *testing.T) {
		server, runtime, path, original := makerTestServer(
			t,
			"game/content/actors/hero.lua",
		)
		runtime.validateErr = errors.New("name must be a string")
		response := makerRequest(
			t,
			server,
			http.MethodPost,
			"/api/content/save?id=actor.hero",
			`{"definition":{"kind":"actor","id":"actor.hero"}}`,
			makerRevision(original),
		)
		if response.Code != http.StatusUnprocessableEntity {
			t.Fatalf("status %d: %s", response.Code, response.Body.String())
		}
		current, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(current, original) {
			t.Fatal("invalid draft changed the source file")
		}
	})

	t.Run("reload", func(t *testing.T) {
		server, runtime, path, original := makerTestServer(
			t,
			"game/content/actors/hero.lua",
		)
		runtime.reloadErrors = []error{errors.New("reload failed"), nil}
		response := makerRequest(
			t,
			server,
			http.MethodPost,
			"/api/content/save?id=actor.hero",
			`{"definition":{"schema_version":1,"kind":"actor",`+
				`"id":"actor.hero","name":"Edited"}}`,
			makerRevision(original),
		)
		if response.Code != http.StatusInternalServerError {
			t.Fatalf("status %d: %s", response.Code, response.Body.String())
		}
		current, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		if !bytes.Equal(current, original) {
			t.Fatal("reload failure was not rolled back")
		}
	})
}

func TestMakerSavePostCommitFailuresReturnWarningsAndKeepNewSource(
	t *testing.T,
) {
	tests := []struct {
		name            string
		inject          func(*fakeMakerRuntime)
		warningPart     string
		wantGraphSynced bool
	}{
		{
			name: "graph refresh",
			inject: func(runtime *fakeMakerRuntime) {
				runtime.graphErr = errors.New("graph unavailable")
			},
			warningPart:     "graph refresh failed",
			wantGraphSynced: false,
		},
		{
			name: "canonical definition",
			inject: func(runtime *fakeMakerRuntime) {
				runtime.definitionErr = errors.New("definition unavailable")
			},
			warningPart:     "canonical definition",
			wantGraphSynced: true,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			server, runtime, path, original := makerTestServer(
				t,
				"game/content/actors/hero.lua",
			)
			test.inject(runtime)
			response := makerRequest(
				t,
				server,
				http.MethodPost,
				"/api/content/save?id=actor.hero",
				`{"definition":{"schema_version":1,"kind":"actor",`+
					`"id":"actor.hero","name":"Post Commit"}}`,
				makerRevision(original),
			)
			if response.Code != http.StatusOK {
				t.Fatalf(
					"post-commit failure status %d: %s",
					response.Code,
					response.Body.String(),
				)
			}

			var payload struct {
				OK   bool `json:"ok"`
				Data struct {
					Warnings    []string `json:"warnings"`
					GraphSynced bool     `json:"graph_synced"`
				} `json:"data"`
			}
			if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
				t.Fatal(err)
			}
			if !payload.OK {
				t.Fatalf("save response was not successful: %+v", payload)
			}
			if payload.Data.GraphSynced != test.wantGraphSynced {
				t.Fatalf(
					"graph_synced = %v, want %v",
					payload.Data.GraphSynced,
					test.wantGraphSynced,
				)
			}
			if len(payload.Data.Warnings) == 0 ||
				!strings.Contains(
					strings.Join(payload.Data.Warnings, "\n"),
					test.warningPart,
				) {
				t.Fatalf(
					"warnings %q do not contain %q",
					payload.Data.Warnings,
					test.warningPart,
				)
			}

			current, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Contains(current, []byte(`name = "Post Commit"`)) {
				t.Fatalf(
					"committed definition was not retained:\n%s",
					current,
				)
			}
		})
	}
}

func TestMakerSaveUsesDependenciesFromRefreshedGraph(t *testing.T) {
	server, runtime, _, original := makerTestServer(
		t,
		"game/content/actors/hero.lua",
	)
	updatedGraph := runtime.graph
	updatedGraph.Nodes = append(
		[]contentGraphNode(nil),
		runtime.graph.Nodes...,
	)
	updatedGraph.Nodes[0].Dependencies = []contentGraphEdge{{
		ID:   "ability.parry",
		Path: "abilities[1]",
	}}
	runtime.graph = updatedGraph

	response := makerRequest(
		t,
		server,
		http.MethodPost,
		"/api/content/save?id=actor.hero",
		`{"definition":{"schema_version":1,"kind":"actor",`+
			`"id":"actor.hero","name":"Edited"}}`,
		makerRevision(original),
	)
	if response.Code != http.StatusOK {
		t.Fatalf("status %d: %s", response.Code, response.Body.String())
	}
	var payload struct {
		Data struct {
			Content makerContentResult `json:"content"`
		} `json:"data"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	dependencies := payload.Data.Content.Dependencies
	if len(dependencies) != 1 ||
		dependencies[0].ID != "ability.parry" ||
		dependencies[0].Path != "abilities[1]" {
		t.Fatalf(
			"save response did not use refreshed dependencies: %+v",
			dependencies,
		)
	}
}

func TestMakerProtectsGeneratedSourcesAndMutations(t *testing.T) {
	server, _, _, _ := makerTestServer(
		t,
		"game/content/stages/generated/hero.lua",
	)
	getResponse := makerRequest(
		t,
		server,
		http.MethodGet,
		"/api/content?id=actor.hero",
		"",
		"",
	)
	if getResponse.Code != http.StatusOK {
		t.Fatalf("status %d: %s", getResponse.Code, getResponse.Body.String())
	}
	if !strings.Contains(getResponse.Body.String(), `"read_only":true`) {
		t.Fatalf("generated source was not read-only: %s", getResponse.Body)
	}

	request := httptest.NewRequest(
		http.MethodPost,
		"/api/content/save?id=actor.hero",
		strings.NewReader(`{"definition":{}}`),
	)
	response := httptest.NewRecorder()
	server.handler().ServeHTTP(response, request)
	if response.Code != http.StatusForbidden {
		t.Fatalf("unauthorized status %d", response.Code)
	}
}

func TestMakerScreenshotRequiresToken(t *testing.T) {
	server, _, _, _ := makerTestServer(
		t,
		"game/content/actors/hero.lua",
	)
	unauthorized := makerRequest(
		t,
		server,
		http.MethodGet,
		"/api/screenshot",
		"",
		"",
	)
	if unauthorized.Code != http.StatusForbidden {
		t.Fatalf(
			"unauthorized screenshot status %d: %s",
			unauthorized.Code,
			unauthorized.Body.String(),
		)
	}

	request := httptest.NewRequest(http.MethodGet, "/api/screenshot", nil)
	request.Header.Set("X-Recreate-Token", server.token)
	response := httptest.NewRecorder()
	server.handler().ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf(
			"authorized screenshot status %d: %s",
			response.Code,
			response.Body.String(),
		)
	}
	if contentType := response.Header().Get("Content-Type"); contentType != "image/png" {
		t.Fatalf("screenshot content type = %q", contentType)
	}
	if !bytes.Equal(response.Body.Bytes(), []byte("png")) {
		t.Fatalf("unexpected screenshot body %q", response.Body.Bytes())
	}
}

func TestMakerListenAddressAndOriginAreLoopbackOnly(t *testing.T) {
	for _, address := range []string{
		"127.0.0.1:0",
		"[::1]:19833",
		"localhost:19833",
	} {
		if err := validateMakerListenAddress(address); err != nil {
			t.Fatalf("%s: %v", address, err)
		}
	}
	for _, address := range []string{
		"0.0.0.0:19833",
		"192.0.2.10:19833",
		":19833",
	} {
		if err := validateMakerListenAddress(address); err == nil {
			t.Fatalf("expected %s to be rejected", address)
		}
	}

	server, _, _, _ := makerTestServer(
		t,
		"game/content/actors/hero.lua",
	)
	server.allowedHost = "127.0.0.1:1234"
	request := httptest.NewRequest(http.MethodGet, "/api/project", nil)
	request.Host = server.allowedHost
	request.Header.Set("Origin", "http://attacker.invalid")
	response := httptest.NewRecorder()
	server.handler().ServeHTTP(response, request)
	if response.Code != http.StatusForbidden {
		t.Fatalf("cross-origin status %d", response.Code)
	}
}

func TestMakerOperationLockKeepsProjectSnapshotTogether(t *testing.T) {
	server, _, _, _ := makerTestServer(
		t,
		"game/content/actors/hero.lua",
	)
	stateRelease := make(chan struct{})
	runtime := &blockingMakerRuntime{
		stateStarted:   make(chan struct{}, 1),
		stateRelease:   stateRelease,
		inputCallStart: make(chan struct{}, 1),
	}
	server.runtime = runtime
	handler := server.handler()

	var releaseOnce sync.Once
	release := func() {
		releaseOnce.Do(func() {
			close(stateRelease)
		})
	}
	defer release()

	projectDone := make(chan *httptest.ResponseRecorder, 1)
	go func() {
		request := httptest.NewRequest(http.MethodGet, "/api/project", nil)
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		projectDone <- response
	}()
	select {
	case <-runtime.stateStarted:
	case <-time.After(2 * time.Second):
		t.Fatal("Runtime.getState did not start")
	}

	inputBodyRead := make(chan struct{})
	inputDone := make(chan *httptest.ResponseRecorder, 1)
	go func() {
		request := httptest.NewRequest(
			http.MethodPost,
			"/api/input",
			&eofNotifyingReader{
				reader: strings.NewReader(
					`{"action":"move_right","frames":1}`,
				),
				done: inputBodyRead,
			},
		)
		request.Header.Set("X-Recreate-Token", server.token)
		request.Header.Set("Content-Type", "application/json")
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, request)
		inputDone <- response
	}()
	select {
	case <-inputBodyRead:
	case <-time.After(2 * time.Second):
		t.Fatal("input request body was not decoded")
	}

	select {
	case <-runtime.inputCallStart:
		t.Fatal(
			"Input.action interleaved between Runtime.getState and World.getSnapshot",
		)
	case <-time.After(150 * time.Millisecond):
	}

	release()
	var projectResponse *httptest.ResponseRecorder
	select {
	case projectResponse = <-projectDone:
	case <-time.After(2 * time.Second):
		t.Fatal("project request did not complete")
	}
	if projectResponse.Code != http.StatusOK {
		t.Fatalf(
			"project status %d: %s",
			projectResponse.Code,
			projectResponse.Body.String(),
		)
	}
	var inputResponse *httptest.ResponseRecorder
	select {
	case inputResponse = <-inputDone:
	case <-time.After(2 * time.Second):
		t.Fatal("input request did not complete")
	}
	if inputResponse.Code != http.StatusOK {
		t.Fatalf(
			"input status %d: %s",
			inputResponse.Code,
			inputResponse.Body.String(),
		)
	}

	calls := runtime.callSequence()
	want := []string{
		"Runtime.getState",
		"World.getSnapshot",
		"Input.action",
	}
	if strings.Join(calls, "\n") != strings.Join(want, "\n") {
		t.Fatalf("runtime call order = %v, want %v", calls, want)
	}
}

func TestMakerDefinitionEncodingIsDeterministic(t *testing.T) {
	left, err := encodeMakerDefinition(map[string]any{
		"name": "Hero",
		"id":   "actor.hero",
		"tags": []any{"player", "hero"},
	})
	if err != nil {
		t.Fatal(err)
	}
	right, err := encodeMakerDefinition(map[string]any{
		"tags": []any{"player", "hero"},
		"id":   "actor.hero",
		"name": "Hero",
	})
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(left, right) {
		t.Fatalf("encoding is not deterministic:\n%s\n%s", left, right)
	}
}

func TestMakerUIAssetsAreEmbeddedAndCSPCompatible(t *testing.T) {
	for _, name := range []string{"index.html", "app.js", "style.css"} {
		data, err := makerUI.ReadFile("maker_ui/" + name)
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		if len(data) == 0 {
			t.Fatalf("%s is empty", name)
		}
	}

	server, _, _, _ := makerTestServer(
		t,
		"game/content/actors/hero.lua",
	)
	response := makerRequest(
		t,
		server,
		http.MethodGet,
		"/",
		"",
		"",
	)
	if response.Code != http.StatusOK {
		t.Fatalf("status %d: %s", response.Code, response.Body.String())
	}
	csp := response.Header().Get("Content-Security-Policy")
	for _, directive := range []string{
		"default-src 'self'",
		"object-src 'none'",
		"base-uri 'none'",
		"form-action 'none'",
		"frame-ancestors 'none'",
	} {
		if !strings.Contains(csp, directive) {
			t.Fatalf("Maker UI CSP %q does not contain %q", csp, directive)
		}
	}
	if strings.Contains(response.Body.String(), "__RECREATE_MAKER_TOKEN__") ||
		!strings.Contains(response.Body.String(), server.token) {
		t.Fatal("Maker token was not injected into the initial document")
	}
}
