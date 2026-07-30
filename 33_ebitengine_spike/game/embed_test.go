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
	if catalog.Graph().Total != 65 || catalog.Graph().EdgeCount != 113 {
		t.Fatalf("embedded graph = %#v", catalog.Graph())
	}
	if project := catalog.Project(); project.ID != "recreate.maker_runtime" ||
		project.InitialStage != "stage.village" ||
		project.Flow.StartSpawn != "default" {
		t.Fatalf("embedded project = %#v", project)
	}
	first[0] = 0
	if bytes.Equal(first, Bytes()) {
		t.Fatal("Bytes leaked mutable embedded storage")
	}
}
