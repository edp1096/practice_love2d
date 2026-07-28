package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"os"
	"os/signal"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

type watchedFile struct {
	Size    int64
	ModTime int64
}

func scanWatchedFiles(projectPath string) (map[string]watchedFile, error) {
	result := map[string]watchedFile{}
	for _, relativeRoot := range []string{
		"game/content",
		"game/maps",
		"assets",
	} {
		root := filepath.Join(projectPath, relativeRoot)
		err := filepath.WalkDir(
			root,
			func(path string, entry fs.DirEntry, walkError error) error {
				if walkError != nil {
					return walkError
				}
				if entry.IsDir() {
					return nil
				}
				info, err := entry.Info()
				if err != nil {
					return err
				}
				relative, err := filepath.Rel(projectPath, path)
				if err != nil {
					return err
				}
				result[filepath.ToSlash(relative)] = watchedFile{
					Size:    info.Size(),
					ModTime: info.ModTime().UnixNano(),
				}
				return nil
			},
		)
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return nil, err
		}
	}
	return result, nil
}

func changedWatchedFiles(
	previous map[string]watchedFile,
	current map[string]watchedFile,
) []string {
	changed := map[string]bool{}
	for path, before := range previous {
		after, exists := current[path]
		if !exists || after != before {
			changed[path] = true
		}
	}
	for path := range current {
		if _, exists := previous[path]; !exists {
			changed[path] = true
		}
	}
	result := make([]string, 0, len(changed))
	for path := range changed {
		result = append(result, path)
	}
	sort.Strings(result)
	return result
}

func watchNeedsMapCompile(paths []string) bool {
	for _, path := range paths {
		if strings.HasPrefix(path, "game/maps/") &&
			strings.EqualFold(filepath.Ext(path), ".tmx") {
			return true
		}
	}
	return false
}

func processWatchedChanges(
	client *protocolClient,
	projectPath string,
	paths []string,
) error {
	fmt.Printf("[watch] detected %d changed file(s):\n", len(paths))
	for _, path := range paths {
		fmt.Printf("  %s\n", path)
	}
	if watchNeedsMapCompile(paths) {
		if err := compileMaps(projectPath, nil, "", true); err != nil {
			return fmt.Errorf("map compile rejected: %w", err)
		}
	}
	var state runtimeState
	if err := client.call("App.reloadContent", nil, &state); err != nil {
		return fmt.Errorf("content reload rejected: %w", err)
	}
	fmt.Printf(
		"[watch] reload accepted: stage=%s, transitions=%d\n",
		state.StageID,
		state.Transitions,
	)
	return nil
}

func runWatch(
	client *protocolClient,
	projectPath string,
	arguments []string,
) error {
	flags := flag.NewFlagSet("watch", flag.ContinueOnError)
	interval := flags.Duration(
		"interval",
		250*time.Millisecond,
		"filesystem polling interval",
	)
	debounce := flags.Duration(
		"debounce",
		200*time.Millisecond,
		"quiet time before reload",
	)
	once := flags.Bool(
		"once",
		false,
		"process one change batch and exit",
	)
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if len(flags.Args()) != 0 {
		return errors.New(
			"usage: lovectl watch [--interval 250ms] [--debounce 200ms] [--once]",
		)
	}
	if *interval <= 0 || *debounce < 0 {
		return errors.New("watch interval must be positive and debounce non-negative")
	}

	var pong struct {
		Pong bool `json:"pong"`
	}
	if err := client.call("Runtime.ping", nil, &pong); err != nil {
		return fmt.Errorf(
			"debug game is not reachable; run 'lovectl run' first: %w",
			err,
		)
	}
	if !pong.Pong {
		return errors.New(
			"debug game did not answer ping; run 'lovectl run' first",
		)
	}
	previous, err := scanWatchedFiles(projectPath)
	if err != nil {
		return err
	}
	fmt.Printf(
		"[watch] watching %d files; engine and game/game.lua changes require restart\n",
		len(previous),
	)

	contextValue, stop := signal.NotifyContext(
		context.Background(),
		os.Interrupt,
	)
	defer stop()
	ticker := time.NewTicker(*interval)
	defer ticker.Stop()
	pending := map[string]bool{}
	var lastChange time.Time

	for {
		select {
		case <-contextValue.Done():
			fmt.Println("[watch] stopped")
			return nil
		case now := <-ticker.C:
			current, scanError := scanWatchedFiles(projectPath)
			if scanError != nil {
				fmt.Fprintf(os.Stderr, "[watch] scan failed: %v\n", scanError)
				continue
			}
			for _, path := range changedWatchedFiles(previous, current) {
				pending[path] = true
				lastChange = now
			}
			previous = current
			if len(pending) == 0 ||
				now.Sub(lastChange) < *debounce {
				continue
			}

			paths := make([]string, 0, len(pending))
			for path := range pending {
				paths = append(paths, path)
			}
			sort.Strings(paths)
			pending = map[string]bool{}
			processError := processWatchedChanges(
				client,
				projectPath,
				paths,
			)
			if processError != nil {
				fmt.Fprintf(os.Stderr, "[watch] %v\n", processError)
			}
			refreshed, refreshError := scanWatchedFiles(projectPath)
			if refreshError == nil {
				previous = refreshed
			}
			if *once {
				return processError
			}
		}
	}
}
