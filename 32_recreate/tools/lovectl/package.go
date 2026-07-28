package main

import (
	"archive/zip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
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

type packagedFile struct {
	Path   string `json:"path"`
	Size   int64  `json:"size"`
	SHA256 string `json:"sha256"`
}

type buildManifest struct {
	FormatVersion      int            `json:"format_version"`
	Project            string         `json:"project"`
	ContentDefinitions int            `json:"content_definitions"`
	ReferencePaths     int            `json:"reference_paths"`
	Files              []packagedFile `json:"files"`
}

type packageResult struct {
	Path   string
	Size   int64
	SHA256 string
	Files  int
}

func collectRuntimeFiles(
	projectPath string,
	graph contentGraph,
) ([]string, error) {
	paths := map[string]bool{
		"main.lua":      true,
		"conf.lua":      true,
		"game/game.lua": true,
	}
	for _, root := range []string{"engine", "game/content"} {
		absoluteRoot := filepath.Join(projectPath, root)
		err := filepath.WalkDir(
			absoluteRoot,
			func(path string, entry fs.DirEntry, walkError error) error {
				if walkError != nil {
					return walkError
				}
				if entry.IsDir() {
					return nil
				}
				if entry.Type()&os.ModeSymlink != 0 {
					return fmt.Errorf(
						"runtime package does not follow symlink %s",
						path,
					)
				}
				if filepath.Ext(path) != ".lua" {
					return nil
				}
				relative, err := filepath.Rel(projectPath, path)
				if err != nil {
					return err
				}
				paths[filepath.ToSlash(relative)] = true
				return nil
			},
		)
		if err != nil {
			return nil, err
		}
	}
	for _, node := range graph.Nodes {
		if node.Kind != "asset" {
			continue
		}
		if node.AssetPath == "" {
			return nil, fmt.Errorf("asset %s has no runtime path", node.ID)
		}
		clean := filepath.ToSlash(filepath.Clean(node.AssetPath))
		if filepath.IsAbs(node.AssetPath) ||
			clean == "." ||
			clean == ".." ||
			strings.HasPrefix(clean, "../") {
			return nil, fmt.Errorf(
				"asset %s has unsafe runtime path %q",
				node.ID,
				node.AssetPath,
			)
		}
		if !strings.HasPrefix(clean, "assets/runtime/") {
			return nil, fmt.Errorf(
				"asset %s must live below assets/runtime: %s",
				node.ID,
				clean,
			)
		}
		paths[clean] = true
	}

	result := make([]string, 0, len(paths))
	for path := range paths {
		absolute := filepath.Join(
			projectPath,
			filepath.FromSlash(path),
		)
		info, err := os.Lstat(absolute)
		if err != nil {
			return nil, fmt.Errorf("runtime file %s: %w", path, err)
		}
		if !info.Mode().IsRegular() {
			return nil, fmt.Errorf("runtime path is not a regular file: %s", path)
		}
		result = append(result, path)
	}
	sort.Strings(result)
	return result, nil
}

func packageFileData(
	projectPath string,
	paths []string,
) (map[string][]byte, []packagedFile, error) {
	data := make(map[string][]byte, len(paths))
	files := make([]packagedFile, 0, len(paths))
	for _, path := range paths {
		value, err := os.ReadFile(filepath.Join(
			projectPath,
			filepath.FromSlash(path),
		))
		if err != nil {
			return nil, nil, err
		}
		sum := sha256.Sum256(value)
		data[path] = value
		files = append(files, packagedFile{
			Path:   path,
			Size:   int64(len(value)),
			SHA256: hex.EncodeToString(sum[:]),
		})
	}
	return data, files, nil
}

func writeZipEntry(
	writer *zip.Writer,
	path string,
	data []byte,
) error {
	header := &zip.FileHeader{
		Name:   filepath.ToSlash(path),
		Method: zip.Store,
	}
	header.SetMode(0o644)
	header.SetModTime(time.Date(
		1980,
		time.January,
		1,
		0,
		0,
		0,
		0,
		time.UTC,
	))
	entry, err := writer.CreateHeader(header)
	if err != nil {
		return err
	}
	_, err = entry.Write(data)
	return err
}

func writeLovePackage(
	projectPath string,
	outputPath string,
	paths []string,
	graph contentGraph,
) (packageResult, error) {
	var result packageResult
	data, files, err := packageFileData(projectPath, paths)
	if err != nil {
		return result, err
	}
	manifest := buildManifest{
		FormatVersion:      1,
		Project:            filepath.Base(projectPath),
		ContentDefinitions: graph.Total,
		ReferencePaths:     graph.EdgeCount,
		Files:              files,
	}
	manifestData, err := json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return result, err
	}
	manifestData = append(manifestData, '\n')
	data["recreate-build.json"] = manifestData
	archivePaths := append([]string(nil), paths...)
	archivePaths = append(archivePaths, "recreate-build.json")
	sort.Strings(archivePaths)

	if err := os.MkdirAll(filepath.Dir(outputPath), 0o755); err != nil {
		return result, err
	}
	temporary, err := os.CreateTemp(
		filepath.Dir(outputPath),
		".recreate-package-*.love",
	)
	if err != nil {
		return result, err
	}
	temporaryPath := temporary.Name()
	cleanup := true
	defer func() {
		if cleanup {
			_ = temporary.Close()
			_ = os.Remove(temporaryPath)
		}
	}()

	archive := zip.NewWriter(temporary)
	for _, path := range archivePaths {
		if err := writeZipEntry(archive, path, data[path]); err != nil {
			_ = archive.Close()
			return result, err
		}
	}
	if err := archive.Close(); err != nil {
		return result, err
	}
	if err := temporary.Sync(); err != nil {
		return result, err
	}
	if err := temporary.Close(); err != nil {
		return result, err
	}
	if err := os.Rename(temporaryPath, outputPath); err != nil {
		return result, err
	}
	cleanup = false

	file, err := os.Open(outputPath)
	if err != nil {
		return result, err
	}
	defer file.Close()
	hash := sha256.New()
	size, err := io.Copy(hash, file)
	if err != nil {
		return result, err
	}
	return packageResult{
		Path:   outputPath,
		Size:   size,
		SHA256: hex.EncodeToString(hash.Sum(nil)),
		Files:  len(archivePaths),
	}, nil
}

func runPackageCommand(
	options globalOptions,
	projectPath string,
	arguments []string,
) error {
	flags := flag.NewFlagSet("package", flag.ContinueOnError)
	output := flags.String(
		"output",
		"dist/32_recreate.love",
		"output .love path",
	)
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if len(flags.Args()) != 0 {
		return errors.New("usage: lovectl package [--output FILE.love]")
	}
	if filepath.Ext(*output) != ".love" {
		return errors.New("package output must use the .love extension")
	}
	outputPath := *output
	if !filepath.IsAbs(outputPath) {
		outputPath = filepath.Join(projectPath, outputPath)
	}
	outputPath, err := filepath.Abs(outputPath)
	if err != nil {
		return err
	}

	if err := compileMaps(projectPath, nil, "", true); err != nil {
		return fmt.Errorf("map compile before package: %w", err)
	}
	graph, err := loadContentGraph(options, projectPath)
	if err != nil {
		return err
	}
	paths, err := collectRuntimeFiles(projectPath, graph)
	if err != nil {
		return err
	}
	result, err := writeLovePackage(
		projectPath,
		outputPath,
		paths,
		graph,
	)
	if err != nil {
		return err
	}
	fmt.Printf(
		"Package: %s\n  %d files, %d bytes\n  sha256 %s\n",
		result.Path,
		result.Files,
		result.Size,
		result.SHA256,
	)
	return nil
}
