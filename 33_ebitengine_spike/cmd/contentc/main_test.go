package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/content"
)

func TestRunValidatesCompleteProjectBeforeWriting(t *testing.T) {
	t.Parallel()

	output := filepath.Join(t.TempDir(), "catalog.json")
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	status := run([]string{
		"-source", sourceProject(t),
		"-output", output,
	}, &stdout, &stderr)
	if status != 0 {
		t.Fatalf("run() status = %d, stderr = %s", status, stderr.String())
	}
	if !strings.Contains(
		stdout.String(),
		"7 stages, 22 entry builds across 2 locales",
	) {
		t.Fatalf("run() stdout = %q", stdout.String())
	}
	catalog, err := content.LoadFile(output)
	if err != nil {
		t.Fatalf("written catalog: %v", err)
	}
	if catalog.Project().ID != "recreate.maker_runtime" {
		t.Fatalf("written project = %#v", catalog.Project())
	}
}

func TestRunDoesNotReplaceOutputWhenProjectValidationFails(t *testing.T) {
	t.Parallel()

	project := t.TempDir()
	if err := os.CopyFS(project, os.DirFS(sourceProject(t))); err != nil {
		t.Fatal(err)
	}
	questPath := filepath.Join(
		project,
		"game",
		"content",
		"quests",
		"grove_guardian.lua",
	)
	source, err := os.ReadFile(questPath)
	if err != nil {
		t.Fatal(err)
	}
	const original = `name = "quest.grove_guardian.rewarded"`
	replacement := `name = "` + strings.Repeat("x", 129) + `"`
	updated := strings.Replace(string(source), original, replacement, 1)
	if updated == string(source) {
		t.Fatalf("%s did not contain mutation target", questPath)
	}
	if err := os.WriteFile(questPath, []byte(updated), 0o644); err != nil {
		t.Fatal(err)
	}

	output := filepath.Join(t.TempDir(), "catalog.json")
	sentinel := []byte("reviewed catalog must survive")
	if err := os.WriteFile(output, sentinel, 0o644); err != nil {
		t.Fatal(err)
	}
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	status := run([]string{
		"-source", project,
		"-output", output,
	}, &stdout, &stderr)
	if status != 1 {
		t.Fatalf(
			"run() status = %d, stdout = %q, stderr = %q",
			status,
			stdout.String(),
			stderr.String(),
		)
	}
	for _, fragment := range []string{
		`project "recreate.maker_runtime"`,
		"campaign topology",
		"flag",
	} {
		if !strings.Contains(stderr.String(), fragment) {
			t.Fatalf("run() stderr = %q, want %q", stderr.String(), fragment)
		}
	}
	got, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, sentinel) {
		t.Fatalf("failed validation replaced output with %q", got)
	}
}

func sourceProject(t *testing.T) string {
	t.Helper()
	result, err := filepath.Abs(filepath.Join("..", "..", "..", "32_recreate"))
	if err != nil {
		t.Fatal(err)
	}
	return result
}
