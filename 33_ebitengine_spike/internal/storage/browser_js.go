//go:build js && wasm

package storage

import (
	"encoding/base64"
	"errors"
	"fmt"
	"io/fs"
	"strings"
	"sync"
	"syscall/js"
)

// BrowserStore persists complete save documents in origin-scoped
// localStorage. The runtime Store contract is synchronous, which matches
// localStorage and keeps campaign transactions identical across desktop and
// browser builds.
type BrowserStore struct {
	prefix  string
	storage js.Value
	mu      sync.Mutex
}

func NewBrowserStore(namespace string) (
	store *BrowserStore,
	storeError error,
) {
	namespace = strings.TrimSpace(namespace)
	if namespace == "" ||
		len(namespace) > 128 ||
		strings.ContainsAny(namespace, "/\\\x00\r\n") {
		return nil, errors.New("browser storage namespace is invalid")
	}
	defer func() {
		if recovered := recover(); recovered != nil {
			store = nil
			storeError = fmt.Errorf(
				"access browser localStorage: %v",
				recovered,
			)
		}
	}()
	value := js.Global().Get("localStorage")
	if value.Type() != js.TypeObject {
		return nil, errors.New("browser localStorage is unavailable")
	}
	return &BrowserStore{
		prefix:  "recreate:" + namespace + ":",
		storage: value,
	}, nil
}

func (store *BrowserStore) Load(slot string) (
	data []byte,
	loadError error,
) {
	filename, err := slotFilename(slot)
	if err != nil {
		return nil, err
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	defer recoverBrowserStorage("load", slot, &loadError)

	value := store.storage.Call("getItem", store.prefix+filename)
	if value.IsNull() || value.IsUndefined() {
		return nil, fmt.Errorf("load slot %q: %w", slot, fs.ErrNotExist)
	}
	decoded, err := base64.StdEncoding.DecodeString(value.String())
	if err != nil {
		return nil, fmt.Errorf(
			"load slot %q: stored data is corrupt: %w",
			slot,
			err,
		)
	}
	return decoded, nil
}

func (store *BrowserStore) Save(slot string, data []byte) (
	saveError error,
) {
	filename, err := slotFilename(slot)
	if err != nil {
		return err
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	defer recoverBrowserStorage("save", slot, &saveError)

	encoded := base64.StdEncoding.EncodeToString(data)
	store.storage.Call("setItem", store.prefix+filename, encoded)
	return nil
}

func recoverBrowserStorage(
	operation string,
	slot string,
	target *error,
) {
	if recovered := recover(); recovered != nil {
		*target = fmt.Errorf(
			"%s slot %q in browser storage: %v",
			operation,
			slot,
			recovered,
		)
	}
}

var _ Store = (*BrowserStore)(nil)
