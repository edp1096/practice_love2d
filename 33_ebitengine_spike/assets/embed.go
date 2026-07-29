// Package gameassets owns the immutable files shipped with the Go runtime.
//
// Keeping the filesystem behind this package prevents simulation and content
// code from depending on an operating-system working directory.
package gameassets

import (
	"embed"
	"io/fs"
)

// Runtime contains the asset set copied from the verified 32_recreate sample.
//
//go:embed runtime
var Runtime embed.FS

// Open returns a runtime asset using its canonical project-relative path, for
// example "images/player/player-sheet.png".
func Open(path string) (fs.File, error) {
	return Runtime.Open("runtime/" + path)
}

// ReadFile returns one immutable runtime asset.
func ReadFile(path string) ([]byte, error) {
	return Runtime.ReadFile("runtime/" + path)
}

// Files returns a filesystem rooted at assets/runtime.
func Files() fs.FS {
	root, err := fs.Sub(Runtime, "runtime")
	if err != nil {
		panic(err)
	}
	return root
}
