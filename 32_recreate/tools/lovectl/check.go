package main

import (
	"bytes"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
)

func collectFiles(root, extension string) ([]string, error) {
	var paths []string
	err := filepath.WalkDir(
		root,
		func(path string, entry fs.DirEntry, walkError error) error {
			if walkError != nil {
				return walkError
			}
			if entry.IsDir() {
				return nil
			}
			if filepath.Ext(path) == extension {
				paths = append(paths, path)
			}
			return nil
		},
	)
	sort.Strings(paths)
	return paths, err
}

func runChecks(options globalOptions, projectPath string) error {
	if err := compileMaps(projectPath, nil, "", false); err != nil {
		return fmt.Errorf("map validation failed: %w", err)
	}

	luaFiles, err := collectFiles(projectPath, ".lua")
	if err != nil {
		return err
	}

	var failures []string
	for _, path := range luaFiles {
		command := exec.Command("luajit", "-bl", path)
		command.Stdout = io.Discard
		var stderr bytes.Buffer
		command.Stderr = &stderr
		if err := command.Run(); err != nil {
			relative, _ := filepath.Rel(projectPath, path)
			failures = append(
				failures,
				fmt.Sprintf("%s\n%s", relative, stderr.String()),
			)
		}
	}
	if len(failures) != 0 {
		for _, failure := range failures {
			fmt.Fprintln(os.Stderr, failure)
		}
		return fmt.Errorf("Lua syntax failed in %d files", len(failures))
	}
	fmt.Printf("Lua syntax: %d files passed\n", len(luaFiles))

	unit := exec.Command(
		"luajit",
		filepath.Join(projectPath, "tests", "run.lua"),
		projectPath,
	)
	unit.Dir = projectPath
	unit.Stdout = os.Stdout
	unit.Stderr = os.Stderr
	if err := unit.Run(); err != nil {
		return fmt.Errorf("Lua unit tests failed: %w", err)
	}

	content := exec.Command(options.lovePath, projectPath)
	content.Dir = projectPath
	content.Env = overrideEnvironment(os.Environ(), map[string]string{
		"RECREATE_CHECK":    "1",
		"RECREATE_HEADLESS": "1",
	})
	content.Stdout = os.Stdout
	content.Stderr = os.Stderr
	if err := content.Run(); err != nil {
		return fmt.Errorf("content validation failed: %w", err)
	}

	goTest := exec.Command("go", "test", "./...")
	goTest.Dir = filepath.Join(projectPath, "tools", "lovectl")
	goTest.Stdout = os.Stdout
	goTest.Stderr = os.Stderr
	if err := goTest.Run(); err != nil {
		return fmt.Errorf("Go tests failed: %w", err)
	}

	fmt.Println("All recreate checks passed")
	return nil
}
