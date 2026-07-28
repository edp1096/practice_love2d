package main

import (
	"encoding/json"
	"testing"
)

func TestBoolMapAcceptsLuaEmptyTable(t *testing.T) {
	var values boolMap
	if err := json.Unmarshal([]byte("[]"), &values); err != nil {
		t.Fatalf("decode Lua empty table: %v", err)
	}
	if values == nil || len(values) != 0 {
		t.Fatalf("expected initialized empty map, got %#v", values)
	}
}

func TestBoolMapAcceptsJSONObject(t *testing.T) {
	var values boolMap
	if err := json.Unmarshal([]byte(`{"quest.rewarded":true}`), &values); err != nil {
		t.Fatalf("decode JSON object: %v", err)
	}
	if !values["quest.rewarded"] {
		t.Fatalf("expected decoded flag, got %#v", values)
	}
}
