package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"practice_love2d/33_ebitengine_spike/internal/content"
)

func main() {
	source := flag.String(
		"source",
		".",
		"source project containing game/content",
	)
	output := flag.String(
		"output",
		filepath.FromSlash("game/catalog.json"),
		"destination catalog JSON",
	)
	flag.Parse()
	if flag.NArg() != 0 {
		fmt.Fprintln(os.Stderr, "contentc: unexpected positional arguments")
		flag.Usage()
		os.Exit(2)
	}

	catalog, err := content.Compile(context.Background(), *source)
	if err != nil {
		fmt.Fprintf(os.Stderr, "contentc: %v\n", err)
		os.Exit(1)
	}
	if err := content.WriteCanonical(*output, catalog); err != nil {
		fmt.Fprintf(os.Stderr, "contentc: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf(
		"compiled %d definitions and %d dependency paths -> %s\n",
		catalog.DependencyGraph.Total,
		catalog.DependencyGraph.EdgeCount,
		*output,
	)
}
