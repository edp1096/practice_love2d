package protocol

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"regexp"
	"strings"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
)

const (
	maxMethodBytes     = 128
	maxIdentifierBytes = 256
	maxSlotBytes       = 64
	maxActionFrames    = 3600
	maxJSONDepth       = 128
	maxTokenBytes      = 512
)

var saveSlotPattern = regexp.MustCompile(
	`^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$`,
)

type rawRequest struct {
	ID     *uint64         `json:"id"`
	Method *string         `json:"method"`
	Params json.RawMessage `json:"params"`
	Token  string          `json:"token,omitempty"`
}

func decodeRequest(line []byte, maxParamsBytes int) (Request, *Error) {
	var probe struct {
		ID *uint64 `json:"id"`
	}
	if !json.Valid(line) {
		return Request{}, rpcError(
			CodeParseError,
			"invalid JSON request",
		)
	}
	_ = json.Unmarshal(line, &probe)
	var responseID uint64
	if probe.ID != nil {
		responseID = *probe.ID
	}
	if err := rejectDuplicateKeys(line); err != nil {
		return Request{ID: responseID}, rpcError(
			CodeInvalidRequest,
			err.Error(),
		)
	}

	var wire rawRequest
	if err := decodeStrictJSON(line, &wire); err != nil {
		return Request{ID: responseID}, rpcError(
			CodeInvalidRequest,
			"invalid JSON request: "+err.Error(),
		)
	}
	if wire.ID == nil || *wire.ID == 0 {
		return Request{}, rpcError(
			CodeInvalidRequest,
			"id must be a positive integer",
		)
	}
	if wire.Method == nil || *wire.Method == "" {
		return Request{ID: *wire.ID}, rpcError(
			CodeInvalidRequest,
			"method must be a non-empty string",
		)
	}
	if len(*wire.Method) > maxMethodBytes {
		return Request{ID: *wire.ID}, rpcError(
			CodeInvalidRequest,
			"method is too long",
		)
	}
	if len(wire.Params) == 0 {
		wire.Params = json.RawMessage(`{}`)
	}
	if len(wire.Params) > maxParamsBytes {
		return Request{ID: *wire.ID}, rpcError(
			CodeRequestTooLarge,
			"params exceed the configured byte limit",
		)
	}
	if !isJSONObject(wire.Params) {
		return Request{ID: *wire.ID}, rpcError(
			CodeInvalidParams,
			"params must be a JSON object",
		)
	}
	if len(wire.Token) > maxTokenBytes {
		return Request{ID: *wire.ID}, rpcError(
			CodeInvalidRequest,
			"authentication token is too long",
		)
	}

	return Request{
		ID:     *wire.ID,
		Method: *wire.Method,
		Params: append(json.RawMessage(nil), wire.Params...),
		Token:  wire.Token,
	}, nil
}

func parseCall(request Request, fixedStepSeconds float64) (Call, *Error) {
	request.Method = CanonicalMethod(request.Method)
	switch request.Method {
	case MethodRuntimePing, MethodRuntimeGetProtocol:
		if err := decodeEmptyParams(request.Params); err != nil {
			return Call{}, err
		}
		return Call{Method: request.Method, Params: EmptyParams{}}, nil

	case MethodRuntimeGetState,
		MethodContentGetGraph,
		MethodWorldGetSnapshot,
		MethodFlowGetState,
		MethodDialogueGetState,
		MethodDialogueAdvance,
		MethodCampaignGetState,
		MethodShopGetState,
		MethodShopClose,
		MethodPageCaptureScreenshot,
		MethodAppReloadContent,
		MethodAppStartNewGame,
		MethodAppQuit:
		if err := decodeEmptyParams(request.Params); err != nil {
			return Call{}, err
		}
		return Call{Method: request.Method, Params: EmptyParams{}}, nil

	case MethodContentGetDefinition:
		var params ContentIDParams
		if err := decodeParams(request.Params, &params); err != nil {
			return Call{}, err
		}
		if err := requireIdentifier("contentId", params.ContentID); err != nil {
			return Call{}, err
		}
		return Call{Method: request.Method, Params: params}, nil

	case MethodContentValidateDefinition:
		var params ValidateDefinitionParams
		if err := decodeParams(request.Params, &params); err != nil {
			return Call{}, err
		}
		if err := requireIdentifier("contentId", params.ContentID); err != nil {
			return Call{}, err
		}
		if len(params.Definition) == 0 || !isJSONObject(params.Definition) {
			return Call{}, rpcError(
				CodeInvalidParams,
				"definition must be a JSON object",
			)
		}
		params.Definition = append(json.RawMessage(nil), params.Definition...)
		return Call{Method: request.Method, Params: params}, nil

	case MethodWorldSetWall:
		type wallWire struct {
			WallID string   `json:"wallId"`
			X      *float64 `json:"x"`
			Y      *float64 `json:"y"`
			Width  *float64 `json:"width"`
			Height *float64 `json:"height"`
		}
		var wire wallWire
		if err := decodeParams(request.Params, &wire); err != nil {
			return Call{}, err
		}
		if err := requireIdentifier("wallId", wire.WallID); err != nil {
			return Call{}, err
		}
		if wire.X == nil || wire.Y == nil ||
			wire.Width == nil || wire.Height == nil {
			return Call{}, rpcError(
				CodeInvalidParams,
				"x, y, width, and height are required",
			)
		}
		if !finite(*wire.X) || !finite(*wire.Y) ||
			!finite(*wire.Width) || !finite(*wire.Height) ||
			*wire.Width <= 0 || *wire.Height <= 0 {
			return Call{}, rpcError(
				CodeInvalidParams,
				"wall geometry must use finite coordinates and positive dimensions",
			)
		}
		return Call{
			Method: request.Method,
			Params: SetWallParams{
				WallID: wire.WallID,
				X:      *wire.X,
				Y:      *wire.Y,
				Width:  *wire.Width,
				Height: *wire.Height,
			},
		}, nil

	case MethodEntitySpawn:
		type spawnWire struct {
			ActorID  string   `json:"actorId"`
			EntityID *string  `json:"entityId,omitempty"`
			X        *float64 `json:"x,omitempty"`
			Y        *float64 `json:"y,omitempty"`
		}
		var wire spawnWire
		if err := decodeParams(request.Params, &wire); err != nil {
			return Call{}, err
		}
		if err := requireIdentifier("actorId", wire.ActorID); err != nil {
			return Call{}, err
		}
		entityID := ""
		if wire.EntityID != nil {
			if err := requireIdentifier("entityId", *wire.EntityID); err != nil {
				return Call{}, err
			}
			entityID = *wire.EntityID
		}
		if (wire.X == nil) != (wire.Y == nil) {
			return Call{}, rpcError(
				CodeInvalidParams,
				"x and y must be provided together",
			)
		}
		if wire.X != nil && (!finite(*wire.X) || !finite(*wire.Y)) {
			return Call{}, rpcError(
				CodeInvalidParams,
				"x and y must be finite numbers",
			)
		}
		return Call{
			Method: request.Method,
			Params: SpawnEntityParams{
				ActorID:  wire.ActorID,
				EntityID: entityID,
				X:        wire.X,
				Y:        wire.Y,
			},
		}, nil

	case MethodEntityRemove:
		var params RemoveEntityParams
		if err := decodeParams(request.Params, &params); err != nil {
			return Call{}, err
		}
		if err := requireIdentifier("entityId", params.EntityID); err != nil {
			return Call{}, err
		}
		return Call{Method: request.Method, Params: params}, nil

	case MethodEntitySetPosition:
		type positionWire struct {
			EntityID string   `json:"entityId"`
			X        *float64 `json:"x"`
			Y        *float64 `json:"y"`
		}
		var wire positionWire
		if err := decodeParams(request.Params, &wire); err != nil {
			return Call{}, err
		}
		if err := requireIdentifier("entityId", wire.EntityID); err != nil {
			return Call{}, err
		}
		if wire.X == nil || wire.Y == nil {
			return Call{}, rpcError(
				CodeInvalidParams,
				"x and y are required",
			)
		}
		if !finite(*wire.X) || !finite(*wire.Y) {
			return Call{}, rpcError(
				CodeInvalidParams,
				"x and y must be finite numbers",
			)
		}
		return Call{
			Method: request.Method,
			Params: SetPositionParams{
				EntityID: wire.EntityID,
				X:        *wire.X,
				Y:        *wire.Y,
			},
		}, nil

	case MethodEntitySetHealth:
		type healthWire struct {
			EntityID string   `json:"entityId"`
			Value    *float64 `json:"value"`
		}
		var wire healthWire
		if err := decodeParams(request.Params, &wire); err != nil {
			return Call{}, err
		}
		if err := requireIdentifier("entityId", wire.EntityID); err != nil {
			return Call{}, err
		}
		if wire.Value == nil {
			return Call{}, rpcError(
				CodeInvalidParams,
				"value is required",
			)
		}
		if !finite(*wire.Value) {
			return Call{}, rpcError(
				CodeInvalidParams,
				"value must be a finite number",
			)
		}
		return Call{
			Method: request.Method,
			Params: SetHealthParams{
				EntityID: wire.EntityID,
				Value:    *wire.Value,
			},
		}, nil

	case MethodEntityRequestAbility:
		var params RequestAbilityParams
		if err := decodeParams(request.Params, &params); err != nil {
			return Call{}, err
		}
		if err := requireIdentifier("entityId", params.EntityID); err != nil {
			return Call{}, err
		}
		if err := requireIdentifier("abilityId", params.AbilityID); err != nil {
			return Call{}, err
		}
		return Call{Method: request.Method, Params: params}, nil

	case MethodFlowMove:
		type flowMoveWire struct {
			Delta *int `json:"delta"`
		}
		var wire flowMoveWire
		if err := decodeParams(request.Params, &wire); err != nil {
			return Call{}, err
		}
		if wire.Delta == nil || (*wire.Delta != -1 && *wire.Delta != 1) {
			return Call{}, rpcError(
				CodeInvalidParams,
				"delta must be -1 or 1",
			)
		}
		return Call{
			Method: request.Method,
			Params: FlowMoveParams{Delta: *wire.Delta},
		}, nil

	case MethodFlowActivate:
		var params FlowActivateParams
		if err := decodeParams(request.Params, &params); err != nil {
			return Call{}, err
		}
		if err := requireIdentifier("option_id", params.OptionID); err != nil {
			return Call{}, err
		}
		return Call{Method: request.Method, Params: params}, nil

	case MethodDialogueStart:
		type dialogueWire struct {
			DialogueID string  `json:"dialogueId"`
			SpeakerID  *string `json:"speakerId,omitempty"`
		}
		var wire dialogueWire
		if err := decodeParams(request.Params, &wire); err != nil {
			return Call{}, err
		}
		if err := requireIdentifier("dialogueId", wire.DialogueID); err != nil {
			return Call{}, err
		}
		speakerID := ""
		if wire.SpeakerID != nil {
			if err := requireIdentifier("speakerId", *wire.SpeakerID); err != nil {
				return Call{}, err
			}
			speakerID = *wire.SpeakerID
		}
		return Call{
			Method: request.Method,
			Params: StartDialogueParams{
				DialogueID: wire.DialogueID,
				SpeakerID:  speakerID,
			},
		}, nil

	case MethodDialogueChoose:
		var params ChooseDialogueParams
		if err := decodeParams(request.Params, &params); err != nil {
			return Call{}, err
		}
		if err := requireIdentifier("choice_id", params.ChoiceID); err != nil {
			return Call{}, err
		}
		return Call{Method: request.Method, Params: params}, nil

	case MethodShopBuy, MethodShopSell:
		params, err := parseShopTradeParams(request.Params)
		if err != nil {
			return Call{}, err
		}
		return Call{Method: request.Method, Params: params}, nil

	case MethodInventoryUse:
		var params InventoryUseParams
		if err := decodeParams(request.Params, &params); err != nil {
			return Call{}, err
		}
		if err := requireIdentifier("item_id", params.ItemID); err != nil {
			return Call{}, err
		}
		return Call{Method: request.Method, Params: params}, nil

	case MethodEquipmentEquip:
		var params EquipmentEquipParams
		if err := decodeParams(request.Params, &params); err != nil {
			return Call{}, err
		}
		if err := requireIdentifier("item_id", params.ItemID); err != nil {
			return Call{}, err
		}
		return Call{Method: request.Method, Params: params}, nil

	case MethodEquipmentUnequip:
		var params EquipmentUnequipParams
		if err := decodeParams(request.Params, &params); err != nil {
			return Call{}, err
		}
		if err := requireIdentifier("slot_id", params.SlotID); err != nil {
			return Call{}, err
		}
		return Call{Method: request.Method, Params: params}, nil

	case MethodInputAction:
		type inputWire struct {
			Action string   `json:"action"`
			Value  *float64 `json:"value,omitempty"`
			Frames *int     `json:"frames,omitempty"`
		}
		var wire inputWire
		if err := decodeParams(request.Params, &wire); err != nil {
			return Call{}, err
		}
		if err := requireIdentifier("action", wire.Action); err != nil {
			return Call{}, err
		}
		value := 1.0
		if wire.Value != nil {
			value = *wire.Value
		}
		frames := 1
		if wire.Frames != nil {
			frames = *wire.Frames
		}
		if !finite(value) || value < -1 || value > 1 {
			return Call{}, rpcError(
				CodeInvalidParams,
				"value must be a finite number between -1 and 1",
			)
		}
		if frames < 1 || frames > maxActionFrames {
			return Call{}, rpcError(
				CodeInvalidParams,
				"frames must be between 1 and 3600",
			)
		}
		return Call{
			Method: request.Method,
			Params: InputActionParams{
				Action: wire.Action,
				Value:  value,
				Frames: frames,
			},
		}, nil

	case MethodEmulationSetPaused:
		type pausedWire struct {
			Enabled *bool `json:"enabled"`
		}
		var wire pausedWire
		if err := decodeParams(request.Params, &wire); err != nil {
			return Call{}, err
		}
		if wire.Enabled == nil {
			return Call{}, rpcError(
				CodeInvalidParams,
				"enabled is required",
			)
		}
		return Call{
			Method: request.Method,
			Params: SetPausedParams{Enabled: *wire.Enabled},
		}, nil

	case MethodEmulationStep:
		type stepWire struct {
			Frames *int     `json:"frames,omitempty"`
			DT     *float64 `json:"dt,omitempty"`
		}
		var wire stepWire
		if err := decodeParams(request.Params, &wire); err != nil {
			return Call{}, err
		}
		frames := 1
		if wire.Frames != nil {
			frames = *wire.Frames
		}
		if frames < 1 || frames > maxActionFrames {
			return Call{}, rpcError(
				CodeInvalidParams,
				"frames must be between 1 and 3600",
			)
		}
		if wire.DT != nil &&
			(!finite(*wire.DT) ||
				math.Abs(*wire.DT-fixedStepSeconds) > 1e-9) {
			return Call{}, rpcError(
				CodeInvalidParams,
				fmt.Sprintf(
					"dt must match the fixed simulation step %.12g",
					fixedStepSeconds,
				),
			)
		}
		normalizedDT := fixedStepSeconds
		return Call{
			Method: request.Method,
			Params: StepParams{Frames: frames, DT: &normalizedDT},
		}, nil

	case MethodAppSave, MethodAppLoad:
		var params SaveSlotParams
		if err := decodeParams(request.Params, &params); err != nil {
			return Call{}, err
		}
		if strings.TrimSpace(params.Slot) == "" {
			return Call{}, rpcError(
				CodeInvalidParams,
				"slot must be a non-empty string",
			)
		}
		if len(params.Slot) > maxSlotBytes ||
			!saveSlotPattern.MatchString(params.Slot) {
			return Call{}, rpcError(
				CodeInvalidParams,
				"slot must use only letters, digits, dot, underscore, or hyphen",
			)
		}
		return Call{Method: request.Method, Params: params}, nil

	default:
		return Call{}, rpcError(
			CodeMethodNotFound,
			"unknown method: "+request.Method,
		)
	}
}

func parseShopTradeParams(raw []byte) (ShopTradeParams, *Error) {
	type shopTradeWire struct {
		ItemID   string          `json:"item_id"`
		Quantity json.RawMessage `json:"quantity"`
	}
	var wire shopTradeWire
	if err := decodeParams(raw, &wire); err != nil {
		return ShopTradeParams{}, err
	}
	if err := requireIdentifier("item_id", wire.ItemID); err != nil {
		return ShopTradeParams{}, err
	}

	quantity := int64(1)
	if len(wire.Quantity) != 0 {
		if bytes.Equal(bytes.TrimSpace(wire.Quantity), []byte("null")) {
			return ShopTradeParams{}, invalidQuantityError()
		}
		if err := decodeStrictJSON(wire.Quantity, &quantity); err != nil {
			return ShopTradeParams{}, invalidQuantityError()
		}
	}
	if quantity < 1 || quantity > campaign.MaxJSONInteger {
		return ShopTradeParams{}, invalidQuantityError()
	}
	return ShopTradeParams{
		ItemID:   wire.ItemID,
		Quantity: quantity,
	}, nil
}

func invalidQuantityError() *Error {
	return rpcError(
		CodeInvalidParams,
		fmt.Sprintf(
			"quantity must be an integer between 1 and %d",
			campaign.MaxJSONInteger,
		),
	)
}

func decodeEmptyParams(raw []byte) *Error {
	var params EmptyParams
	return decodeParams(raw, &params)
}

func decodeParams(raw []byte, target any) *Error {
	if !isJSONObject(raw) {
		return rpcError(CodeInvalidParams, "params must be a JSON object")
	}
	if err := decodeStrictJSON(raw, target); err != nil {
		return rpcError(CodeInvalidParams, "invalid params: "+err.Error())
	}
	return nil
}

func decodeStrictJSON(raw []byte, target any) error {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	decoder.UseNumber()
	if err := decoder.Decode(target); err != nil {
		return err
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		if err == nil {
			return errors.New("multiple JSON values")
		}
		return err
	}
	return nil
}

func isJSONObject(raw []byte) bool {
	trimmed := bytes.TrimSpace(raw)
	return len(trimmed) >= 2 &&
		trimmed[0] == '{' &&
		trimmed[len(trimmed)-1] == '}'
}

func requireIdentifier(name, value string) *Error {
	if strings.TrimSpace(value) == "" {
		return rpcError(
			CodeInvalidParams,
			name+" must be a non-empty string",
		)
	}
	if len(value) > maxIdentifierBytes {
		return rpcError(CodeInvalidParams, name+" is too long")
	}
	return nil
}

func finite(value float64) bool {
	return !math.IsInf(value, 0) && !math.IsNaN(value)
}

// rejectDuplicateKeys rejects ambiguous JSON objects, including objects nested
// inside a content definition.
func rejectDuplicateKeys(raw []byte) error {
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	if err := walkJSONValue(decoder, 0); err != nil {
		return err
	}
	if _, err := decoder.Token(); !errors.Is(err, io.EOF) {
		if err == nil {
			return errors.New("multiple JSON values")
		}
		return err
	}
	return nil
}

func walkJSONValue(decoder *json.Decoder, depth int) error {
	token, err := decoder.Token()
	if err != nil {
		return err
	}
	delimiter, ok := token.(json.Delim)
	if !ok {
		return nil
	}
	if depth >= maxJSONDepth {
		return fmt.Errorf("JSON nesting exceeds %d levels", maxJSONDepth)
	}

	switch delimiter {
	case '{':
		keys := make(map[string]struct{})
		for decoder.More() {
			keyToken, err := decoder.Token()
			if err != nil {
				return err
			}
			key, ok := keyToken.(string)
			if !ok {
				return errors.New("object key is not a string")
			}
			if _, duplicate := keys[key]; duplicate {
				return fmt.Errorf("duplicate JSON object key %q", key)
			}
			keys[key] = struct{}{}
			if err := walkJSONValue(decoder, depth+1); err != nil {
				return err
			}
		}
		closing, err := decoder.Token()
		if err != nil {
			return err
		}
		if closing != json.Delim('}') {
			return errors.New("unterminated JSON object")
		}
	case '[':
		for decoder.More() {
			if err := walkJSONValue(decoder, depth+1); err != nil {
				return err
			}
		}
		closing, err := decoder.Token()
		if err != nil {
			return err
		}
		if closing != json.Delim(']') {
			return errors.New("unterminated JSON array")
		}
	default:
		return errors.New("unexpected JSON delimiter")
	}
	return nil
}
