package main

import (
	"archive/zip"
	"bytes"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

var packageDirectories = map[string]bool{
	"assets": true,
	"engine": true,
	"game":   true,
	"vendor": true,
}

var packageFiles = map[string]bool{
	"conf.lua":    true,
	"icon.png":    true,
	"locker.lua":  true,
	"main.lua":    true,
	"startup.lua": true,
	"system.lua":  true,
}

var packageTimestamp = time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC)

func defaultLovePackage(projectPath string) string {
	return filepath.Join(projectPath, "web", "game.love")
}

func runPackage(projectPath string, arguments []string) error {
	flags := flag.NewFlagSet("package", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	output := flags.String("output", defaultLovePackage(projectPath), "output .love path")
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return errors.New("usage: lovectl package [--output PATH]")
	}

	if !filepath.IsAbs(*output) {
		*output = filepath.Join(projectPath, *output)
	}
	count, err := buildLovePackage(projectPath, *output)
	if err != nil {
		return err
	}
	if err := verifyLovePackage(projectPath, *output); err != nil {
		return fmt.Errorf("package verification failed: %w", err)
	}
	fmt.Printf("Packaged %d files: %s\n", count, *output)
	return nil
}

func collectPackageFiles(projectPath string) ([]string, error) {
	var relativePaths []string
	for name := range packageFiles {
		path := filepath.Join(projectPath, name)
		info, err := os.Stat(path)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			return nil, err
		}
		if info.Mode().IsRegular() {
			relativePaths = append(relativePaths, filepath.ToSlash(name))
		}
	}

	for directory := range packageDirectories {
		root := filepath.Join(projectPath, directory)
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
			if !entry.Type().IsRegular() {
				return nil
			}
			relative, err := filepath.Rel(projectPath, path)
			if err != nil {
				return err
			}
			relativePaths = append(relativePaths, filepath.ToSlash(relative))
			return nil
		})
		if err != nil {
			return nil, err
		}
	}

	sort.Strings(relativePaths)
	return relativePaths, nil
}

func buildLovePackage(projectPath, outputPath string) (int, error) {
	files, err := collectPackageFiles(projectPath)
	if err != nil {
		return 0, err
	}
	if err := os.MkdirAll(filepath.Dir(outputPath), 0o755); err != nil {
		return 0, err
	}

	temporary, err := os.CreateTemp(filepath.Dir(outputPath), ".game.love-*")
	if err != nil {
		return 0, err
	}
	temporaryPath := temporary.Name()
	keepTemporary := false
	defer func() {
		if !keepTemporary {
			_ = os.Remove(temporaryPath)
		}
	}()

	archive := zip.NewWriter(temporary)
	for _, relative := range files {
		sourcePath := filepath.Join(projectPath, filepath.FromSlash(relative))
		data, err := os.ReadFile(sourcePath)
		if err != nil {
			_ = archive.Close()
			_ = temporary.Close()
			return 0, err
		}
		header := &zip.FileHeader{
			Name:   relative,
			Method: zip.Deflate,
		}
		header.SetModTime(packageTimestamp)
		header.SetMode(0o644)
		writer, err := archive.CreateHeader(header)
		if err != nil {
			_ = archive.Close()
			_ = temporary.Close()
			return 0, err
		}
		if _, err := writer.Write(data); err != nil {
			_ = archive.Close()
			_ = temporary.Close()
			return 0, err
		}
	}
	if err := archive.Close(); err != nil {
		_ = temporary.Close()
		return 0, err
	}
	if err := temporary.Sync(); err != nil {
		_ = temporary.Close()
		return 0, err
	}
	if err := temporary.Close(); err != nil {
		return 0, err
	}
	if err := os.Chmod(temporaryPath, 0o644); err != nil {
		return 0, err
	}
	if err := os.Rename(temporaryPath, outputPath); err != nil {
		if removeError := os.Remove(outputPath); removeError != nil &&
			!errors.Is(removeError, os.ErrNotExist) {
			return 0, fmt.Errorf("replace package: %w", err)
		}
		if err := os.Rename(temporaryPath, outputPath); err != nil {
			return 0, err
		}
	}
	keepTemporary = true
	return len(files), nil
}

func verifyLovePackage(projectPath, packagePath string) error {
	files, err := collectPackageFiles(projectPath)
	if err != nil {
		return err
	}
	expected := make(map[string]string, len(files))
	for _, relative := range files {
		expected[relative] = filepath.Join(projectPath, filepath.FromSlash(relative))
	}

	archive, err := zip.OpenReader(packagePath)
	if err != nil {
		return err
	}
	defer archive.Close()

	seen := make(map[string]bool, len(archive.File))
	for _, entry := range archive.File {
		name := strings.TrimPrefix(entry.Name, "./")
		sourcePath, ok := expected[name]
		if !ok {
			return fmt.Errorf("unexpected archive entry %q", entry.Name)
		}
		if seen[name] {
			return fmt.Errorf("duplicate archive entry %q", entry.Name)
		}
		seen[name] = true

		source, err := os.ReadFile(sourcePath)
		if err != nil {
			return err
		}
		reader, err := entry.Open()
		if err != nil {
			return err
		}
		archived, readError := io.ReadAll(reader)
		closeError := reader.Close()
		if readError != nil {
			return readError
		}
		if closeError != nil {
			return closeError
		}
		if !bytes.Equal(source, archived) {
			return fmt.Errorf("archive entry %q does not match source", entry.Name)
		}
	}
	for name := range expected {
		if !seen[name] {
			return fmt.Errorf("missing archive entry %q", name)
		}
	}
	return nil
}
