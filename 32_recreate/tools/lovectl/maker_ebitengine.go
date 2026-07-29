package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

const (
	makerBackendLove       = "love"
	makerBackendEbitengine = "ebitengine"
)

// ebitMakerRuntime turns Maker's source-oriented reload request into a fresh,
// atomic Ebitengine preview. The source file has already been replaced by the
// Maker server. We compile the entire project to a canonical catalog, then ask
// the running preview to build the same stage/spawn/locale from that catalog.
// A failed compile or start leaves the old runtime untouched; handleSave then
// restores the source and calls this adapter again to reconcile the preview.
type ebitMakerRuntime struct {
	delegate       makerRuntime
	compileCatalog func() error
}

func (runtime *ebitMakerRuntime) call(
	method string,
	params map[string]any,
	target any,
) error {
	if method != "App.reloadContent" {
		return runtime.delegate.call(method, params, target)
	}
	var location struct {
		StageID  string `json:"current_stage_id"`
		SpawnID  string `json:"entry_spawn_id"`
		LocaleID string `json:"locale"`
	}
	if err := runtime.delegate.call(
		"Campaign.getState",
		nil,
		&location,
	); err != nil {
		return fmt.Errorf("read Ebitengine preview location: %w", err)
	}
	if runtime.compileCatalog == nil {
		return errors.New("Ebitengine Maker catalog compiler is unavailable")
	}
	if err := runtime.compileCatalog(); err != nil {
		return fmt.Errorf("compile Ebitengine Maker catalog: %w", err)
	}
	start := map[string]any{}
	if location.StageID != "" {
		start["stageId"] = location.StageID
	}
	if location.SpawnID != "" {
		start["spawnId"] = location.SpawnID
	}
	if location.LocaleID != "" {
		start["localeId"] = location.LocaleID
	}
	if err := runtime.delegate.call(
		"App.startNewGame",
		start,
		target,
	); err != nil {
		return fmt.Errorf("apply Ebitengine Maker catalog: %w", err)
	}
	return nil
}

func resolveEbitengineRoot(
	explicit string,
	projectPath string,
) (string, error) {
	candidates := make([]string, 0, 2)
	if explicit != "" {
		candidates = append(candidates, explicit)
	} else {
		candidates = append(
			candidates,
			filepath.Join(filepath.Dir(projectPath), "33_ebitengine_spike"),
		)
	}
	for _, candidate := range candidates {
		absolute, err := filepath.Abs(candidate)
		if err != nil {
			continue
		}
		if err := validateEbitengineRoot(absolute); err == nil {
			return absolute, nil
		}
	}
	if explicit != "" {
		return "", fmt.Errorf(
			"%q is not a Recreate Ebitengine runtime",
			explicit,
		)
	}
	return "", errors.New(
		"could not find sibling 33_ebitengine_spike; pass --ebitengine PATH",
	)
}

func validateEbitengineRoot(root string) error {
	module, err := os.ReadFile(filepath.Join(root, "go.mod"))
	if err != nil {
		return err
	}
	if !strings.Contains(
		string(module),
		"module practice_love2d/33_ebitengine_spike",
	) {
		return errors.New("unexpected Ebitengine module")
	}
	for _, relative := range []string{
		"cmd/contentc/main.go",
		"cmd/recreate/main.go",
	} {
		info, err := os.Stat(filepath.Join(root, relative))
		if err != nil || !info.Mode().IsRegular() {
			return fmt.Errorf("missing %s", relative)
		}
	}
	return nil
}

type ebitMakerTools struct {
	runtimeBinary string
	contentBinary string
	catalogPath   string
}

func buildEbitMakerTools(
	root string,
	runtimeDirectory string,
	logFile *os.File,
) (ebitMakerTools, error) {
	tools := ebitMakerTools{
		runtimeBinary: filepath.Join(runtimeDirectory, "recreate-ebitengine"),
		contentBinary: filepath.Join(runtimeDirectory, "recreate-contentc"),
		catalogPath:   filepath.Join(runtimeDirectory, "catalog.json"),
	}
	builds := []struct {
		output      string
		packagePath string
	}{
		{tools.runtimeBinary, "./cmd/recreate"},
		{tools.contentBinary, "./cmd/contentc"},
	}
	for _, build := range builds {
		command := exec.Command(
			"go",
			"build",
			"-trimpath",
			"-o",
			build.output,
			build.packagePath,
		)
		command.Dir = root
		command.Stdout = logFile
		command.Stderr = logFile
		if err := command.Run(); err != nil {
			return ebitMakerTools{}, fmt.Errorf(
				"build %s: %w",
				build.packagePath,
				err,
			)
		}
	}
	return tools, nil
}

func compileEbitMakerCatalog(
	tools ebitMakerTools,
	projectPath string,
	root string,
	logFile *os.File,
) error {
	command := exec.Command(
		tools.contentBinary,
		"-source",
		projectPath,
		"-output",
		tools.catalogPath,
	)
	command.Dir = root
	command.Stdout = logFile
	command.Stderr = logFile
	if err := command.Run(); err != nil {
		return err
	}
	return nil
}

func startEbitMakerPreview(
	tools ebitMakerTools,
	root string,
	port int,
	logFile *os.File,
	runtimeDirectory string,
) (*loveProcess, error) {
	command := exec.Command(
		tools.runtimeBinary,
		"-catalog",
		tools.catalogPath,
		"-debug-address",
		fmt.Sprintf("127.0.0.1:%d", port),
		"-save-dir",
		filepath.Join(runtimeDirectory, "saves"),
	)
	command.Dir = root
	command.Env = overrideEnvironment(
		os.Environ(),
		map[string]string{
			"LIBGL_ALWAYS_SOFTWARE": "1",
			"XDG_CACHE_HOME": filepath.Join(
				runtimeDirectory,
				"cache",
			),
			"XDG_CONFIG_HOME": filepath.Join(
				runtimeDirectory,
				"config",
			),
			"XDG_DATA_HOME": filepath.Join(
				runtimeDirectory,
				"data",
			),
		},
	)
	command.Stdout = logFile
	command.Stderr = logFile
	if err := command.Start(); err != nil {
		return nil, err
	}
	process := &loveProcess{
		command: command,
		done:    make(chan error, 1),
	}
	go func() {
		process.done <- command.Wait()
	}()
	return process, nil
}

func waitForMakerBridge(
	client *protocolClient,
	process *loveProcess,
	runtimeName string,
	timeout time.Duration,
) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		select {
		case err := <-process.done:
			process.command = nil
			return fmt.Errorf(
				"%s exited before debug bridge: %w",
				runtimeName,
				err,
			)
		default:
		}
		var result struct {
			Pong bool `json:"pong"`
		}
		if err := client.call("Runtime.ping", nil, &result); err == nil &&
			result.Pong {
			return nil
		}
		time.Sleep(25 * time.Millisecond)
	}
	return fmt.Errorf("timed out waiting for %s debug bridge", runtimeName)
}
