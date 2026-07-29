package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/projectcheck"
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout io.Writer, stderr io.Writer) int {
	flags := flag.NewFlagSet("contentc", flag.ContinueOnError)
	flags.SetOutput(stderr)
	source := flags.String(
		"source",
		".",
		"source project containing game/content",
	)
	output := flags.String(
		"output",
		filepath.FromSlash("game/catalog.json"),
		"destination catalog JSON",
	)
	if err := flags.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return 0
		}
		return 2
	}
	if flags.NArg() != 0 {
		fmt.Fprintln(stderr, "contentc: unexpected positional arguments")
		flags.Usage()
		return 2
	}

	catalog, err := content.Compile(context.Background(), *source)
	if err != nil {
		fmt.Fprintf(stderr, "contentc: %v\n", err)
		return 1
	}
	report, err := projectcheck.Validate(catalog)
	if err != nil {
		fmt.Fprintf(stderr, "contentc: %v\n", err)
		return 1
	}
	if err := content.WriteCanonical(*output, catalog); err != nil {
		fmt.Fprintf(stderr, "contentc: %v\n", err)
		return 1
	}
	project := catalog.Project()
	for _, warning := range project.Warnings {
		fmt.Fprintf(
			stderr,
			"contentc: warning: %s.%s: %s\n",
			project.Source,
			warning.Path,
			warning.Message,
		)
	}
	fmt.Fprintf(
		stdout,
		"compiled project %s, %d definitions, %d dependency paths, "+
			"%d stages, %d entry builds across %d locales, "+
			"%d manifest warnings -> %s\n",
		project.ID,
		report.DefinitionCount,
		catalog.DependencyGraph.EdgeCount,
		report.StageCount,
		report.EntryBuildCount,
		report.LocaleCount,
		len(project.Warnings),
		*output,
	)
	return 0
}
