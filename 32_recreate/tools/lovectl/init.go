package main

import (
	"embed"
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

//go:embed templates/common templates/capabilities templates/profiles
var projectTemplates embed.FS

var projectSlugPattern = regexp.MustCompile(`[^a-z0-9]+`)

type initOptions struct {
	Profile string
	Title   string
	Target  string
}

func parseInitOptions(arguments []string) (initOptions, error) {
	var options initOptions
	flags := flag.NewFlagSet("init", flag.ContinueOnError)
	flags.StringVar(
		&options.Profile,
		"profile",
		"",
		"rpg, action-rpg, or action",
	)
	flags.StringVar(
		&options.Title,
		"title",
		"",
		"project title (defaults to target directory name)",
	)
	if err := flags.Parse(arguments); err != nil {
		return options, err
	}
	if len(flags.Args()) != 1 {
		return options, errors.New(
			"usage: lovectl init --profile rpg|action-rpg|action " +
				"[--title TITLE] TARGET",
		)
	}
	switch options.Profile {
	case "rpg", "action-rpg", "action":
	default:
		return options, errors.New(
			"--profile must be rpg, action-rpg, or action",
		)
	}
	options.Target = flags.Args()[0]
	if strings.ContainsAny(options.Title, "\r\n") || len(options.Title) > 100 {
		return options, errors.New(
			"--title must be one line with at most 100 bytes",
		)
	}
	return options, nil
}

func projectSlug(target string) string {
	value := strings.ToLower(filepath.Base(filepath.Clean(target)))
	value = projectSlugPattern.ReplaceAllString(value, "_")
	value = strings.Trim(value, "_")
	if value == "" {
		value = "game"
	}
	if value[0] >= '0' && value[0] <= '9' {
		value = "game_" + value
	}
	return value
}

func renderProjectTemplate(
	data []byte,
	replacements map[string]string,
) []byte {
	value := string(data)
	keys := make([]string, 0, len(replacements))
	for key := range replacements {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	for _, key := range keys {
		value = strings.ReplaceAll(value, "{{"+key+"}}", replacements[key])
	}
	return []byte(value)
}

func installTemplateTree(
	templateRoot string,
	target string,
	replacements map[string]string,
) error {
	return fs.WalkDir(
		projectTemplates,
		templateRoot,
		func(path string, entry fs.DirEntry, walkError error) error {
			if walkError != nil {
				return walkError
			}
			relative, err := filepath.Rel(templateRoot, path)
			if err != nil {
				return err
			}
			if relative == "." {
				return nil
			}
			if relative == "gitignore" {
				relative = ".gitignore"
			} else if relative == "go_mod" {
				relative = "go.mod"
			}
			destination := filepath.Join(target, relative)
			if entry.IsDir() {
				return os.MkdirAll(destination, 0o755)
			}
			data, err := projectTemplates.ReadFile(path)
			if err != nil {
				return err
			}
			return os.WriteFile(
				destination,
				renderProjectTemplate(data, replacements),
				0o644,
			)
		},
	)
}

func populateInitializedProject(
	sourceProject string,
	target string,
	options initOptions,
) error {
	for _, directory := range []string{"engine", "tools/lovectl", "tests"} {
		source := filepath.Join(sourceProject, directory)
		destination := filepath.Join(target, directory)
		if err := os.MkdirAll(destination, 0o755); err != nil {
			return err
		}
		if err := copyDirectory(source, destination); err != nil {
			return fmt.Errorf("copy %s: %w", directory, err)
		}
	}

	slug := projectSlug(options.Target)
	title := options.Title
	if title == "" {
		title = filepath.Base(filepath.Clean(options.Target))
	}
	replacements := map[string]string{
		"PROFILE":       options.Profile,
		"PROJECT_ID":    "recreate." + slug,
		"PROJECT_TITLE": title,
		"PROJECT_TITLE_LUA": strings.NewReplacer(
			"\\", "\\\\",
			"\"", "\\\"",
		).Replace(title),
		"IDENTITY":  "recreate_" + slug,
		"GO_MODULE": "recreate.local/" + slug,
	}
	if err := installTemplateTree(
		"templates/common",
		target,
		replacements,
	); err != nil {
		return err
	}
	if options.Profile == "action" || options.Profile == "action-rpg" {
		if err := installTemplateTree(
			"templates/capabilities/action",
			target,
			replacements,
		); err != nil {
			return err
		}
	}
	if options.Profile == "rpg" || options.Profile == "action-rpg" {
		if err := installTemplateTree(
			"templates/capabilities/rpg",
			target,
			replacements,
		); err != nil {
			return err
		}
	}
	if err := installTemplateTree(
		"templates/profiles/"+options.Profile,
		target,
		replacements,
	); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Join(target, "game", "maps"), 0o755); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Join(target, "assets", "runtime"), 0o755); err != nil {
		return err
	}
	return nil
}

func runInit(
	sourceProject string,
	arguments []string,
) error {
	options, err := parseInitOptions(arguments)
	if err != nil {
		return err
	}
	target, err := filepath.Abs(options.Target)
	if err != nil {
		return err
	}
	if filepath.Clean(target) == filepath.Clean(sourceProject) {
		return errors.New("TARGET must differ from the source project")
	}
	if _, err := os.Lstat(target); err == nil {
		return fmt.Errorf("TARGET already exists: %s", target)
	} else if !os.IsNotExist(err) {
		return err
	}

	parent := filepath.Dir(target)
	if err := os.MkdirAll(parent, 0o755); err != nil {
		return err
	}
	temporary, err := os.MkdirTemp(
		parent,
		"."+filepath.Base(target)+".init-",
	)
	if err != nil {
		return err
	}
	keep := false
	defer func() {
		if !keep {
			_ = os.RemoveAll(temporary)
		}
	}()

	if err := populateInitializedProject(
		sourceProject,
		temporary,
		options,
	); err != nil {
		return err
	}
	if _, err := validateProject(temporary); err != nil {
		return fmt.Errorf("generated project is invalid: %w", err)
	}
	if err := os.Rename(temporary, target); err != nil {
		return err
	}
	keep = true

	fmt.Printf(
		"Created %s project: %s\n"+
			"Next:\n"+
			"  cd %s\n"+
			"  go run ./tools/lovectl check\n"+
			"  go run ./tools/lovectl smoke\n"+
			"  go run ./tools/lovectl run\n",
		options.Profile,
		target,
		target,
	)
	return nil
}
