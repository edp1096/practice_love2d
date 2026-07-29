package main

import (
	"encoding/json"
	"strings"
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

func TestOverrideEnvironmentReplacesKeysWithoutDuplicates(t *testing.T) {
	environment := overrideEnvironment(
		[]string{
			"PATH=/bin",
			"XDG_DATA_HOME=/real",
			"RECREATE_IDENTITY=real_game",
		},
		map[string]string{
			"XDG_DATA_HOME":     "/temporary",
			"RECREATE_IDENTITY": "visual_test",
		},
	)
	joined := strings.Join(environment, "\n")
	if strings.Contains(joined, "/real") ||
		strings.Contains(joined, "real_game") {
		t.Fatalf("old environment leaked into test: %v", environment)
	}
	if strings.Count(joined, "XDG_DATA_HOME=") != 1 ||
		strings.Count(joined, "RECREATE_IDENTITY=") != 1 {
		t.Fatalf("environment contains duplicate keys: %v", environment)
	}
}
