// Package storage separates durable save slots from the simulation.
//
// Console builds can provide a user-storage implementation without changing
// the game or save schema. Desktop builds use FileStore.
package storage

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sync"
)

var slotPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$`)

// Store is the complete persistence surface needed by the runtime.
type Store interface {
	Load(slot string) ([]byte, error)
	Save(slot string, data []byte) error
}

// FileStore writes one JSON document per slot below a fixed root.
type FileStore struct {
	root string
	mu   sync.Mutex
}

// NewFileStore creates a desktop save store. The root is resolved once so a
// later working-directory change cannot redirect saves.
func NewFileStore(root string) (*FileStore, error) {
	if root == "" {
		return nil, errors.New("save root is required")
	}
	absolute, err := filepath.Abs(root)
	if err != nil {
		return nil, fmt.Errorf("resolve save root: %w", err)
	}
	return &FileStore{root: filepath.Clean(absolute)}, nil
}

func slotFilename(slot string) (string, error) {
	if !slotPattern.MatchString(slot) {
		return "", fmt.Errorf("invalid save slot %q", slot)
	}
	return slot + ".json", nil
}

// Load reads a complete slot. Callers own the returned byte slice.
func (store *FileStore) Load(slot string) ([]byte, error) {
	filename, err := slotFilename(slot)
	if err != nil {
		return nil, err
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	data, err := os.ReadFile(filepath.Join(store.root, filename))
	if err != nil {
		return nil, fmt.Errorf("load slot %q: %w", slot, err)
	}
	return data, nil
}

// Save atomically replaces a slot and durability-synchronizes both file data
// and the containing directory.
func (store *FileStore) Save(slot string, data []byte) error {
	filename, err := slotFilename(slot)
	if err != nil {
		return err
	}
	store.mu.Lock()
	defer store.mu.Unlock()

	if err := os.MkdirAll(store.root, 0o755); err != nil {
		return fmt.Errorf("create save root: %w", err)
	}
	temporary, err := os.CreateTemp(store.root, ".recreate-save-*")
	if err != nil {
		return fmt.Errorf("create temporary save: %w", err)
	}
	temporaryPath := temporary.Name()
	cleanup := true
	defer func() {
		if cleanup {
			_ = temporary.Close()
			_ = os.Remove(temporaryPath)
		}
	}()
	if err := temporary.Chmod(0o600); err != nil {
		return fmt.Errorf("set temporary save mode: %w", err)
	}
	if _, err := temporary.Write(data); err != nil {
		return fmt.Errorf("write temporary save: %w", err)
	}
	if err := temporary.Sync(); err != nil {
		return fmt.Errorf("sync temporary save: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close temporary save: %w", err)
	}
	destination := filepath.Join(store.root, filename)
	if err := os.Rename(temporaryPath, destination); err != nil {
		return fmt.Errorf("replace save slot: %w", err)
	}
	cleanup = false

	directory, err := os.Open(store.root)
	if err != nil {
		return fmt.Errorf("open save root after replacement: %w", err)
	}
	syncErr := directory.Sync()
	closeErr := directory.Close()
	if syncErr != nil {
		return fmt.Errorf("sync save root: %w", syncErr)
	}
	if closeErr != nil {
		return fmt.Errorf("close save root: %w", closeErr)
	}
	return nil
}

// IsMissing reports whether Load failed because the slot does not exist.
func IsMissing(err error) bool {
	return errors.Is(err, fs.ErrNotExist)
}
