// Package gamecatalog embeds the reviewed default game definition.
package gamecatalog

import _ "embed"

//go:embed catalog.json
var catalog []byte

// Bytes returns a detached copy of the canonical default catalog.
func Bytes() []byte {
	return append([]byte(nil), catalog...)
}
