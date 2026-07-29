// Command webbundle builds a deterministic, static-host-ready WebAssembly
// distribution of the Recreate Ebitengine runtime.
package main

import (
	"archive/zip"
	"context"
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"time"
)

//go:embed templates/*
var templates embed.FS

var staticTemplateNames = []string{
	"app.js",
	"icon.svg",
	"index.html",
	"manifest.webmanifest",
	"style.css",
}

type options struct {
	source  string
	output  string
	archive string
}

type fileRecord struct {
	Path   string `json:"path"`
	Bytes  int64  `json:"bytes"`
	SHA256 string `json:"sha256"`
}

type buildManifest struct {
	SchemaVersion    int          `json:"schema_version"`
	Module           string       `json:"module"`
	Target           string       `json:"target"`
	GoVersion        string       `json:"go_version"`
	Ebitengine       string       `json:"ebitengine"`
	CatalogSHA256    string       `json:"catalog_sha256"`
	BundleID         string       `json:"bundle_id"`
	RequiredWASMMIME string       `json:"required_wasm_mime"`
	Files            []fileRecord `json:"files"`
}

func main() {
	if err := run(
		context.Background(),
		os.Args[1:],
		os.Stdout,
		os.Stderr,
	); err != nil {
		fmt.Fprintln(os.Stderr, "webbundle:", err)
		os.Exit(1)
	}
}

func run(
	ctx context.Context,
	arguments []string,
	stdout io.Writer,
	stderr io.Writer,
) error {
	var options options
	flags := flag.NewFlagSet("webbundle", flag.ContinueOnError)
	flags.SetOutput(stderr)
	flags.StringVar(&options.source, "source", ".", "Go module root")
	flags.StringVar(
		&options.output,
		"output",
		"dist/web",
		"static web output directory",
	)
	flags.StringVar(
		&options.archive,
		"archive",
		"dist/recreate-web.zip",
		"deterministic zip output; empty disables it",
	)
	if err := flags.Parse(arguments); err != nil {
		return err
	}
	if len(flags.Args()) != 0 {
		return errors.New(
			"usage: webbundle [-source DIR] [-output DIR] [-archive FILE.zip]",
		)
	}
	root, err := validateModuleRoot(options.source)
	if err != nil {
		return err
	}
	output, err := resolveOutput(root, options.output)
	if err != nil {
		return fmt.Errorf("resolve web output: %w", err)
	}
	archive := ""
	if options.archive != "" {
		archive, err = resolveOutput(root, options.archive)
		if err != nil {
			return fmt.Errorf("resolve web archive: %w", err)
		}
		if filepath.Ext(archive) != ".zip" {
			return errors.New("web archive must use a .zip extension")
		}
	}
	if output == root || pathInside(output, root) {
		return errors.New("web output cannot contain the module root")
	}
	if archive != "" && pathInside(output, archive) {
		return errors.New("web archive cannot be inside the web output")
	}
	if err := os.MkdirAll(filepath.Dir(output), 0o755); err != nil {
		return err
	}
	staging, err := os.MkdirTemp(
		filepath.Dir(output),
		".recreate-web-build-*",
	)
	if err != nil {
		return err
	}
	keepStaging := false
	defer func() {
		if !keepStaging {
			_ = os.RemoveAll(staging)
		}
	}()

	if err := writeTemplates(staging); err != nil {
		return err
	}
	if err := copyWASMExec(ctx, staging); err != nil {
		return err
	}
	if err := buildWASM(ctx, root, staging, stdout, stderr); err != nil {
		return err
	}
	precache, err := bundleFingerprint(staging)
	if err != nil {
		return err
	}
	if err := writeServiceWorker(staging, precache); err != nil {
		return err
	}
	manifest, err := makeBuildManifest(root, staging, precache)
	if err != nil {
		return err
	}
	if err := writeJSON(
		filepath.Join(staging, "recreate-web.json"),
		manifest,
	); err != nil {
		return err
	}

	if err := replaceDirectory(staging, output); err != nil {
		return err
	}
	keepStaging = true
	if archive != "" {
		if err := writeDeterministicArchive(output, archive); err != nil {
			return err
		}
	}
	fmt.Fprintf(
		stdout,
		"web bundle %s (%s, %d files)\n",
		output,
		manifest.BundleID,
		len(manifest.Files)+1,
	)
	if archive != "" {
		fmt.Fprintf(stdout, "web archive %s\n", archive)
	}
	return nil
}

func validateModuleRoot(source string) (string, error) {
	root, err := filepath.Abs(source)
	if err != nil {
		return "", err
	}
	root = filepath.Clean(root)
	module, err := os.ReadFile(filepath.Join(root, "go.mod"))
	if err != nil {
		return "", fmt.Errorf("read module: %w", err)
	}
	if modulePath(module) != "practice_love2d/33_ebitengine_spike" {
		return "", errors.New("source is not the Recreate Ebitengine module")
	}
	for _, relative := range []string{
		"cmd/recreate/main_js.go",
		"game/catalog.json",
	} {
		info, err := os.Stat(filepath.Join(root, relative))
		if err != nil || !info.Mode().IsRegular() {
			return "", fmt.Errorf("source is missing %s", relative)
		}
	}
	return root, nil
}

func modulePath(goMod []byte) string {
	for _, line := range strings.Split(string(goMod), "\n") {
		fields := strings.Fields(line)
		if len(fields) == 2 && fields[0] == "module" {
			return strings.Trim(fields[1], `"`)
		}
	}
	return ""
}

func resolveOutput(root string, value string) (string, error) {
	if strings.TrimSpace(value) == "" {
		return "", errors.New("path is empty")
	}
	if !filepath.IsAbs(value) {
		value = filepath.Join(root, value)
	}
	return filepath.Abs(value)
}

func pathInside(root string, candidate string) bool {
	relative, err := filepath.Rel(root, candidate)
	return err == nil &&
		relative != ".." &&
		!strings.HasPrefix(relative, ".."+string(filepath.Separator))
}

func writeTemplates(destination string) error {
	for _, name := range staticTemplateNames {
		data, err := templates.ReadFile("templates/" + name)
		if err != nil {
			return err
		}
		if err := os.WriteFile(
			filepath.Join(destination, name),
			data,
			0o644,
		); err != nil {
			return err
		}
	}
	return nil
}

func copyWASMExec(ctx context.Context, destination string) error {
	goRoot := runtime.GOROOT()
	if goRoot == "" {
		command := exec.CommandContext(ctx, "go", "env", "GOROOT")
		output, err := command.Output()
		if err != nil {
			return fmt.Errorf("resolve Go root: %w", err)
		}
		goRoot = strings.TrimSpace(string(output))
	}
	var data []byte
	var readErrors []error
	for _, relative := range []string{
		filepath.Join("lib", "wasm", "wasm_exec.js"),
		filepath.Join("misc", "wasm", "wasm_exec.js"),
	} {
		source := filepath.Join(goRoot, relative)
		var err error
		data, err = os.ReadFile(source)
		if err == nil {
			break
		}
		readErrors = append(readErrors, err)
	}
	if data == nil {
		return fmt.Errorf(
			"read matching wasm_exec.js: %w",
			errors.Join(readErrors...),
		)
	}
	return os.WriteFile(
		filepath.Join(destination, "wasm_exec.js"),
		data,
		0o644,
	)
}

func buildWASM(
	ctx context.Context,
	root string,
	destination string,
	stdout io.Writer,
	stderr io.Writer,
) error {
	command := exec.CommandContext(
		ctx,
		"go",
		"build",
		"-buildvcs=false",
		"-trimpath",
		"-ldflags=-s -w -buildid=",
		"-o",
		filepath.Join(destination, "game.wasm"),
		"./cmd/recreate",
	)
	command.Dir = root
	command.Env = targetEnvironment(os.Environ(), map[string]string{
		"GOOS":        "js",
		"GOARCH":      "wasm",
		"CGO_ENABLED": "0",
	})
	command.Stdout = stdout
	command.Stderr = stderr
	if err := command.Run(); err != nil {
		return fmt.Errorf("build browser runtime: %w", err)
	}
	return nil
}

func targetEnvironment(
	current []string,
	overrides map[string]string,
) []string {
	result := make([]string, 0, len(current)+len(overrides))
	for _, entry := range current {
		key, _, found := strings.Cut(entry, "=")
		if _, replaced := overrides[key]; found && replaced {
			continue
		}
		result = append(result, entry)
	}
	keys := make([]string, 0, len(overrides))
	for key := range overrides {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		result = append(result, key+"="+overrides[key])
	}
	return result
}

func bundleFingerprint(root string) (string, error) {
	names := append([]string(nil), staticTemplateNames...)
	names = append(names, "game.wasm", "wasm_exec.js")
	sort.Strings(names)
	hash := sha256.New()
	for _, name := range names {
		data, err := os.ReadFile(filepath.Join(root, name))
		if err != nil {
			return "", err
		}
		_, _ = hash.Write([]byte(name))
		_, _ = hash.Write([]byte{0})
		_, _ = hash.Write(data)
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

func writeServiceWorker(root string, fingerprint string) error {
	if len(fingerprint) < 16 {
		return errors.New("web bundle fingerprint is invalid")
	}
	data, err := templates.ReadFile("templates/sw.js")
	if err != nil {
		return err
	}
	cacheName := "recreate-web-" + fingerprint[:16]
	data = []byte(strings.ReplaceAll(
		string(data),
		"__RECREATE_CACHE_NAME__",
		cacheName,
	))
	return os.WriteFile(filepath.Join(root, "sw.js"), data, 0o644)
}

func makeBuildManifest(
	moduleRoot string,
	bundleRoot string,
	fingerprint string,
) (buildManifest, error) {
	catalog, err := os.ReadFile(filepath.Join(moduleRoot, "game", "catalog.json"))
	if err != nil {
		return buildManifest{}, err
	}
	records, err := fileRecords(bundleRoot)
	if err != nil {
		return buildManifest{}, err
	}
	catalogHash := sha256.Sum256(catalog)
	return buildManifest{
		SchemaVersion:    1,
		Module:           "practice_love2d/33_ebitengine_spike",
		Target:           "js/wasm",
		GoVersion:        runtime.Version(),
		Ebitengine:       ebitengineVersion(moduleRoot),
		CatalogSHA256:    hex.EncodeToString(catalogHash[:]),
		BundleID:         "sha256:" + fingerprint,
		RequiredWASMMIME: "application/wasm",
		Files:            records,
	}, nil
}

func ebitengineVersion(moduleRoot string) string {
	data, err := os.ReadFile(filepath.Join(moduleRoot, "go.mod"))
	if err != nil {
		return "unknown"
	}
	for _, line := range strings.Split(string(data), "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 2 &&
			fields[0] == "github.com/hajimehoshi/ebiten/v2" {
			return fields[1]
		}
	}
	return "unknown"
}

func fileRecords(root string) ([]fileRecord, error) {
	var names []string
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
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		names = append(names, filepath.ToSlash(relative))
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Strings(names)
	records := make([]fileRecord, 0, len(names))
	for _, name := range names {
		path := filepath.Join(root, filepath.FromSlash(name))
		data, err := os.ReadFile(path)
		if err != nil {
			return nil, err
		}
		info, err := os.Stat(path)
		if err != nil {
			return nil, err
		}
		sum := sha256.Sum256(data)
		records = append(records, fileRecord{
			Path:   name,
			Bytes:  info.Size(),
			SHA256: hex.EncodeToString(sum[:]),
		})
	}
	return records, nil
}

func writeJSON(path string, value any) error {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return os.WriteFile(path, data, 0o644)
}

func replaceDirectory(staging string, destination string) error {
	info, err := os.Lstat(destination)
	if errors.Is(err, fs.ErrNotExist) {
		return os.Rename(staging, destination)
	}
	if err != nil {
		return err
	}
	if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("web output %q is not a regular directory", destination)
	}
	parent := filepath.Dir(destination)
	backup, err := os.MkdirTemp(parent, ".recreate-web-old-*")
	if err != nil {
		return err
	}
	if err := os.Remove(backup); err != nil {
		return err
	}
	if err := os.Rename(destination, backup); err != nil {
		return err
	}
	if err := os.Rename(staging, destination); err != nil {
		_ = os.Rename(backup, destination)
		return err
	}
	if err := os.RemoveAll(backup); err != nil {
		return fmt.Errorf(
			"web output replaced but old output cleanup failed: %w",
			err,
		)
	}
	return nil
}

func writeDeterministicArchive(root string, destination string) error {
	if err := os.MkdirAll(filepath.Dir(destination), 0o755); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(
		filepath.Dir(destination),
		".recreate-web-archive-*.zip",
	)
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	keep := false
	defer func() {
		_ = temporary.Close()
		if !keep {
			_ = os.Remove(temporaryPath)
		}
	}()
	writer := zip.NewWriter(temporary)
	records, err := fileRecords(root)
	if err != nil {
		return err
	}
	fixedTime := time.Date(1980, 1, 1, 0, 0, 0, 0, time.UTC)
	for _, record := range records {
		data, err := os.ReadFile(filepath.Join(
			root,
			filepath.FromSlash(record.Path),
		))
		if err != nil {
			return err
		}
		header := &zip.FileHeader{
			Name:     record.Path,
			Method:   zip.Deflate,
			Modified: fixedTime,
		}
		header.SetMode(0o644)
		entry, err := writer.CreateHeader(header)
		if err != nil {
			return err
		}
		if _, err := entry.Write(data); err != nil {
			return err
		}
	}
	if err := writer.Close(); err != nil {
		return err
	}
	if err := temporary.Sync(); err != nil {
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := replaceRegularFile(temporaryPath, destination); err != nil {
		return err
	}
	keep = true
	return nil
}

func replaceRegularFile(source string, destination string) error {
	info, err := os.Lstat(destination)
	if errors.Is(err, fs.ErrNotExist) {
		return os.Rename(source, destination)
	}
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("archive %q is not a regular file", destination)
	}
	backup := destination + ".previous"
	if _, err := os.Lstat(backup); err == nil {
		return fmt.Errorf("archive backup already exists: %s", backup)
	} else if !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	if err := os.Rename(destination, backup); err != nil {
		return err
	}
	if err := os.Rename(source, destination); err != nil {
		_ = os.Rename(backup, destination)
		return err
	}
	if err := os.Remove(backup); err != nil {
		return fmt.Errorf(
			"archive replaced but old archive cleanup failed: %w",
			err,
		)
	}
	return nil
}
