package storage

import (
	"bytes"
	"os"
	"path/filepath"
	"sync"
	"testing"
)

func TestFileStoreRoundTripAndReplacement(t *testing.T) {
	t.Parallel()

	store, err := NewFileStore(filepath.Join(t.TempDir(), "nested", "saves"))
	if err != nil {
		t.Fatal(err)
	}
	if err := store.Save("campaign", []byte(`{"tick":1}`)); err != nil {
		t.Fatal(err)
	}
	if err := store.Save("campaign", []byte(`{"tick":2}`)); err != nil {
		t.Fatal(err)
	}
	got, err := store.Load("campaign")
	if err != nil {
		t.Fatal(err)
	}
	if want := []byte(`{"tick":2}`); !bytes.Equal(got, want) {
		t.Fatalf("Load = %q, want %q", got, want)
	}
	info, err := os.Stat(filepath.Join(store.root, "campaign.json"))
	if err != nil {
		t.Fatal(err)
	}
	if gotMode := info.Mode().Perm(); gotMode != 0o600 {
		t.Fatalf("mode = %o, want 600", gotMode)
	}
}

func TestFileStoreRejectsPathTraversalAndEmptySlots(t *testing.T) {
	t.Parallel()

	store, err := NewFileStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	for _, slot := range []string{"", "../outside", "nested/slot", ".hidden"} {
		if err := store.Save(slot, []byte("x")); err == nil {
			t.Errorf("Save(%q) unexpectedly succeeded", slot)
		}
		if _, err := store.Load(slot); err == nil {
			t.Errorf("Load(%q) unexpectedly succeeded", slot)
		}
	}
}

func TestFileStoreSerializesConcurrentReplacement(t *testing.T) {
	t.Parallel()

	store, err := NewFileStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	values := [][]byte{
		[]byte(`{"writer":0}`),
		[]byte(`{"writer":1}`),
		[]byte(`{"writer":2}`),
		[]byte(`{"writer":3}`),
	}
	var wait sync.WaitGroup
	errors := make(chan error, len(values))
	for _, value := range values {
		value := value
		wait.Add(1)
		go func() {
			defer wait.Done()
			errors <- store.Save("slot", value)
		}()
	}
	wait.Wait()
	close(errors)
	for err := range errors {
		if err != nil {
			t.Fatal(err)
		}
	}
	got, err := store.Load("slot")
	if err != nil {
		t.Fatal(err)
	}
	for _, value := range values {
		if bytes.Equal(got, value) {
			return
		}
	}
	t.Fatalf("slot contains a torn value: %q", got)
}

func TestIsMissing(t *testing.T) {
	t.Parallel()

	store, err := NewFileStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	_, err = store.Load("missing")
	if !IsMissing(err) {
		t.Fatalf("IsMissing(%v) = false", err)
	}
}
