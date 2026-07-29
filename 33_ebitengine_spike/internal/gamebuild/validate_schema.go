package gamebuild

import (
	"encoding/json"
	"fmt"
	"math"
	"strings"

	"practice_love2d/33_ebitengine_spike/internal/content"
)

func validateColor(value any, path string, required bool) error {
	items, exists, err := optionalArray(value, path)
	if err != nil {
		return err
	}
	if !exists {
		if required {
			return fmt.Errorf("%s is required", path)
		}
		return nil
	}
	if len(items) != 3 && len(items) != 4 {
		return fmt.Errorf("%s must contain RGB or RGBA values", path)
	}
	for index, raw := range items {
		component, err := requiredNumber(
			raw,
			fmt.Sprintf("%s[%d]", path, index),
		)
		if err != nil {
			return err
		}
		if component < 0 || component > 1 {
			return fmt.Errorf("%s[%d] must be between 0 and 1", path, index)
		}
	}
	return nil
}

func referencedDefinition(
	catalog *content.Catalog,
	id string,
	kind string,
	path string,
) (map[string]any, error) {
	raw, exists := catalog.Definition(id)
	if !exists {
		return nil, fmt.Errorf("%s references missing definition %q", path, id)
	}
	var data map[string]any
	if err := json.Unmarshal(raw, &data); err != nil {
		return nil, fmt.Errorf("%s cannot decode %q: %w", path, id, err)
	}
	if data["id"] != id || data["kind"] != kind {
		return nil, fmt.Errorf(
			"%s must reference %s content, got %q",
			path,
			kind,
			id,
		)
	}
	return data, nil
}

func referenceField(
	catalog *content.Catalog,
	object map[string]any,
	field string,
	kind string,
	path string,
	required bool,
) (map[string]any, error) {
	value := object[field]
	if value == nil && !required {
		return nil, nil
	}
	id, err := requiredString(value, path+"."+field)
	if err != nil {
		return nil, err
	}
	return referencedDefinition(catalog, id, kind, path+"."+field)
}

func rejectUnknownKeys(
	object map[string]any,
	path string,
	allowed ...string,
) error {
	known := make(map[string]struct{}, len(allowed))
	for _, key := range allowed {
		known[key] = struct{}{}
	}
	for key := range object {
		if _, exists := known[key]; !exists {
			return fmt.Errorf("%s.%s is not a supported field", path, key)
		}
	}
	return nil
}

func requiredEnum(value any, path string, allowed ...string) error {
	text, err := requiredString(value, path)
	if err != nil {
		return err
	}
	if !containsString(allowed, text) {
		return fmt.Errorf("%s has unsupported value %q", path, text)
	}
	return nil
}

func requiredObject(value any, path string) (map[string]any, error) {
	object, ok := value.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("%s must be an object", path)
	}
	return object, nil
}

func optionalObject(
	value any,
	path string,
) (map[string]any, bool, error) {
	if value == nil {
		return nil, false, nil
	}
	object, err := requiredObject(value, path)
	return object, err == nil, err
}

func requiredArray(value any, path string) ([]any, error) {
	items, ok := value.([]any)
	if !ok {
		return nil, fmt.Errorf("%s must be an array", path)
	}
	return items, nil
}

func optionalArray(value any, path string) ([]any, bool, error) {
	if value == nil {
		return nil, false, nil
	}
	items, err := requiredArray(value, path)
	return items, err == nil, err
}

func requiredString(value any, path string) (string, error) {
	text, ok := value.(string)
	if !ok || strings.TrimSpace(text) == "" {
		return "", fmt.Errorf("%s must be a non-empty string", path)
	}
	return text, nil
}

func optionalString(value any, path string) error {
	if value == nil {
		return nil
	}
	_, err := requiredString(value, path)
	return err
}

func hasNonEmptyString(value any) bool {
	text, ok := value.(string)
	return ok && strings.TrimSpace(text) != ""
}

func requiredNumber(value any, path string) (float64, error) {
	number, ok := number(value)
	if !ok || math.IsNaN(number) || math.IsInf(number, 0) {
		return 0, fmt.Errorf("%s must be a finite number", path)
	}
	return number, nil
}

func requiredPositiveNumber(value any, path string) error {
	_, err := requiredPositiveNumberValue(value, path)
	return err
}

func requiredPositiveNumberValue(value any, path string) (float64, error) {
	number, err := requiredNumber(value, path)
	if err != nil {
		return 0, err
	}
	if number <= 0 {
		return 0, fmt.Errorf("%s must be positive", path)
	}
	return number, nil
}

func requiredNonNegativeNumber(value any, path string) error {
	number, err := requiredNumber(value, path)
	if err != nil {
		return err
	}
	if number < 0 {
		return fmt.Errorf("%s must not be negative", path)
	}
	return nil
}

func optionalPositiveNumber(value any, path string) error {
	if value == nil {
		return nil
	}
	return requiredPositiveNumber(value, path)
}

func optionalNonNegativeNumber(value any, path string) error {
	if value == nil {
		return nil
	}
	return requiredNonNegativeNumber(value, path)
}

func requiredPositiveInteger(value any, path string) error {
	_, err := requiredPositiveIntegerValue(value, path)
	return err
}

func requiredPositiveIntegerValue(value any, path string) (int, error) {
	number, err := requiredNumber(value, path)
	if err != nil {
		return 0, err
	}
	if number < 1 || math.Trunc(number) != number {
		return 0, fmt.Errorf("%s must be a positive integer", path)
	}
	return int(number), nil
}

func optionalPositiveInteger(value any, path string) error {
	if value == nil {
		return nil
	}
	return requiredPositiveInteger(value, path)
}

func optionalNonNegativeInteger(value any, path string) error {
	if value == nil {
		return nil
	}
	number, err := requiredNumber(value, path)
	if err != nil {
		return err
	}
	if number < 0 || math.Trunc(number) != number {
		return fmt.Errorf("%s must be a non-negative integer", path)
	}
	return nil
}

func requiredNonNegativeInteger(value any, path string) error {
	if value == nil {
		return fmt.Errorf("%s is required", path)
	}
	return optionalNonNegativeInteger(value, path)
}

func optionalBoolean(value any, path string) error {
	if value == nil {
		return nil
	}
	if _, ok := value.(bool); !ok {
		return fmt.Errorf("%s must be a boolean", path)
	}
	return nil
}

func stringArray(
	value any,
	path string,
	required bool,
) ([]string, error) {
	items, exists, err := optionalArray(value, path)
	if err != nil {
		return nil, err
	}
	if !exists {
		if required {
			return nil, fmt.Errorf("%s is required", path)
		}
		return nil, nil
	}
	result := make([]string, len(items))
	for index, raw := range items {
		item, err := requiredString(raw, fmt.Sprintf("%s[%d]", path, index))
		if err != nil {
			return nil, err
		}
		result[index] = item
	}
	return result, nil
}

func validateStringArray(value any, path string, required bool) error {
	_, err := stringArray(value, path, required)
	return err
}

func containsString(items []string, wanted string) bool {
	for _, item := range items {
		if item == wanted {
			return true
		}
	}
	return false
}

func validateSemanticNumbers(value any, path string) error {
	switch typed := value.(type) {
	case map[string]any:
		for key, child := range typed {
			if numberValue, ok := number(child); ok {
				if err := validateNumberField(
					key,
					numberValue,
					path+"."+key,
				); err != nil {
					return err
				}
			}
			if err := validateSemanticNumbers(child, path+"."+key); err != nil {
				return err
			}
		}
	case []any:
		for index, child := range typed {
			if err := validateSemanticNumbers(
				child,
				fmt.Sprintf("%s[%d]", path, index),
			); err != nil {
				return err
			}
		}
	}
	return nil
}

func validateNumberField(key string, value float64, path string) error {
	if math.IsNaN(value) || math.IsInf(value, 0) {
		return fmt.Errorf("%s must be finite", path)
	}
	switch key {
	case "width", "height", "radius", "fps", "count",
		"required", "max", "stack_limit", "max_stacks":
		if value <= 0 {
			return fmt.Errorf("%s must be positive", path)
		}
	case "duration", "windup", "recovery", "cooldown",
		"distance", "range", "aggro_range", "attack_distance",
		"speed", "lifetime", "delay", "tick_interval",
		"amount", "value", "buy_price", "sell_price", "pierce":
		if value < 0 {
			return fmt.Errorf("%s must not be negative", path)
		}
	case "health_ratio_at_most":
		if value < 0 || value > 1 {
			return fmt.Errorf("%s must be between 0 and 1", path)
		}
	}
	return nil
}

func number(value any) (float64, bool) {
	number, ok := value.(float64)
	return number, ok
}

func anySlice(value any) []any {
	items, _ := value.([]any)
	return items
}
