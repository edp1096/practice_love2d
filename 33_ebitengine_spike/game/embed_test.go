package gamecatalog

import (
	"bytes"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/content"
)

func TestEmbeddedCatalogIsCompleteAndDetached(t *testing.T) {
	t.Parallel()
	first := Bytes()
	catalog, err := content.LoadBytes(first)
	if err != nil {
		t.Fatal(err)
	}
	if catalog.Graph().Total != 44 || catalog.Graph().EdgeCount != 86 {
		t.Fatalf("embedded graph = %#v", catalog.Graph())
	}
	first[0] = 0
	if bytes.Equal(first, Bytes()) {
		t.Fatal("Bytes leaked mutable embedded storage")
	}
}
