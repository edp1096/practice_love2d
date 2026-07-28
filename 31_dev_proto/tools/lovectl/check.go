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

func runChecks(projectPath string) error {
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

	goTest := exec.Command("go", "test", "./...")
	goTest.Dir = filepath.Join(projectPath, "tools", "lovectl")
	goTest.Stdout = os.Stdout
	goTest.Stderr = os.Stderr
	if err := goTest.Run(); err != nil {
		return fmt.Errorf("Go tests failed: %w", err)
	}

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
	if err := verifyLovePackage(projectPath, defaultLovePackage(projectPath)); err != nil {
		return fmt.Errorf("web package is stale: %w (run lovectl package)", err)
	}
	fmt.Println("Web package: source files match web/game.love")
	return nil
}

func collectFiles(root, extension string) ([]string, error) {
	var paths []string
	err := filepath.WalkDir(root, func(
		path string,
		entry fs.DirEntry,
		walkError error,
	) error {
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
	})
	sort.Strings(paths)
	return paths, err
}
