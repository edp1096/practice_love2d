package protocol

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"reflect"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

type callRecorder struct {
	mutex sync.Mutex
	calls []Call
	fn    func(context.Context, Call) (any, error)
}

type observingRecorder struct {
	callRecorder
	written chan string
}

func (backend *observingRecorder) ProtocolResponseWritten(method string) {
	backend.written <- method
}

type blockingJSONResult struct {
	started chan<- struct{}
	release <-chan struct{}
}

type panickingJSONResult struct{}

func (panickingJSONResult) MarshalJSON() ([]byte, error) {
	panic("unsafe backend marshaler")
}

func (result blockingJSONResult) MarshalJSON() ([]byte, error) {
	close(result.started)
	<-result.release
	return []byte(`{"ok":true}`), nil
}

func (backend *callRecorder) Call(
	ctx context.Context,
	call Call,
) (any, error) {
	backend.mutex.Lock()
	backend.calls = append(backend.calls, call)
	backend.mutex.Unlock()
	if backend.fn != nil {
		return backend.fn(ctx, call)
	}
	return map[string]any{"method": call.Method}, nil
}

func (backend *callRecorder) snapshot() []Call {
	backend.mutex.Lock()
	defer backend.mutex.Unlock()
	return append([]Call(nil), backend.calls...)
}

func startTestServer(
	t *testing.T,
	backend Backend,
	config Config,
) (string, *Server) {
	t.Helper()
	server, err := NewServer(backend, config)
	if err != nil {
		t.Fatal(err)
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- server.Serve(ctx, listener)
	}()
	t.Cleanup(func() {
		cancel()
		select {
		case err := <-done:
			if err != nil {
				t.Errorf("Serve returned an error: %v", err)
			}
		case <-time.After(2 * time.Second):
			t.Error("Serve did not stop after cancellation")
		}
	})
	return listener.Addr().String(), server
}

func newTestClient(t *testing.T, address string) *Client {
	t.Helper()
	client, err := NewClient(ClientConfig{
		Address: address,
		Timeout: 2 * time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	return client
}

func TestProtocolV8DispatchesTypedCalls(t *testing.T) {
	backend := &callRecorder{}
	address, _ := startTestServer(t, backend, Config{})
	client := newTestClient(t, address)

	definition := json.RawMessage(
		`{"id":"actor.hero","kind":"actor","health":10}`,
	)
	spawnX := 80.5
	spawnY := -4.25
	cases := []struct {
		method     string
		params     any
		paramsType any
		mutating   bool
	}{
		{MethodRuntimeGetState, nil, EmptyParams{}, false},
		{MethodContentGetGraph, nil, EmptyParams{}, false},
		{
			MethodContentGetDefinition,
			ContentIDParams{ContentID: "actor.hero"},
			ContentIDParams{},
			false,
		},
		{
			MethodContentValidateDefinition,
			ValidateDefinitionParams{
				ContentID:  "actor.hero",
				Definition: definition,
			},
			ValidateDefinitionParams{},
			false,
		},
		{MethodWorldGetSnapshot, nil, EmptyParams{}, false},
		{
			MethodWorldSetWall,
			SetWallParams{
				WallID: "north",
				X:      0,
				Y:      0,
				Width:  960,
				Height: 32,
			},
			SetWallParams{},
			true,
		},
		{
			MethodEntitySpawn,
			SpawnEntityParams{
				ActorID:  "actor.slime",
				EntityID: "preview.slime",
				X:        &spawnX,
				Y:        &spawnY,
			},
			SpawnEntityParams{},
			true,
		},
		{
			MethodEntityRemove,
			RemoveEntityParams{EntityID: "preview.slime"},
			RemoveEntityParams{},
			true,
		},
		{
			MethodEntitySetPosition,
			SetPositionParams{EntityID: "player", X: 12.5, Y: -3},
			SetPositionParams{},
			true,
		},
		{
			MethodEntitySetHealth,
			SetHealthParams{EntityID: "player", Value: 4},
			SetHealthParams{},
			true,
		},
		{
			MethodEntityRequestAbility,
			RequestAbilityParams{
				EntityID:  "player",
				AbilityID: "ability.parry",
			},
			RequestAbilityParams{},
			true,
		},
		{
			MethodEncounterStart,
			StartEncounterParams{EncounterID: "arena"},
			StartEncounterParams{},
			true,
		},
		{
			MethodFlowGetState,
			nil,
			EmptyParams{},
			false,
		},
		{
			MethodFlowMove,
			FlowMoveParams{Delta: -1},
			FlowMoveParams{},
			true,
		},
		{
			MethodFlowActivate,
			FlowActivateParams{OptionID: "new_game"},
			FlowActivateParams{},
			true,
		},
		{
			MethodDialogueStart,
			StartDialogueParams{
				DialogueID: "dialogue.guide",
				SpeakerID:  "guide",
			},
			StartDialogueParams{},
			true,
		},
		{
			MethodDialogueGetState,
			nil,
			EmptyParams{},
			false,
		},
		{
			MethodDialogueChoose,
			ChooseDialogueParams{ChoiceID: "accept"},
			ChooseDialogueParams{},
			true,
		},
		{
			MethodDialogueAdvance,
			nil,
			EmptyParams{},
			true,
		},
		{
			MethodCampaignGetState,
			nil,
			EmptyParams{},
			false,
		},
		{
			MethodShopGetState,
			nil,
			EmptyParams{},
			false,
		},
		{
			MethodShopBuy,
			map[string]any{"item_id": "item.potion"},
			ShopTradeParams{},
			true,
		},
		{
			MethodShopSell,
			ShopTradeParams{
				ItemID:   "item.potion",
				Quantity: 2,
			},
			ShopTradeParams{},
			true,
		},
		{
			MethodShopClose,
			nil,
			EmptyParams{},
			true,
		},
		{
			MethodInventoryUse,
			InventoryUseParams{ItemID: "item.potion"},
			InventoryUseParams{},
			true,
		},
		{
			MethodEquipmentEquip,
			EquipmentEquipParams{ItemID: "item.sword"},
			EquipmentEquipParams{},
			true,
		},
		{
			MethodEquipmentUnequip,
			EquipmentUnequipParams{SlotID: "weapon"},
			EquipmentUnequipParams{},
			true,
		},
		{
			MethodInputAction,
			map[string]any{"action": "attack"},
			InputActionParams{},
			true,
		},
		{
			MethodEmulationSetPaused,
			SetPausedParams{Enabled: true},
			SetPausedParams{},
			true,
		},
		{
			MethodEmulationStep,
			map[string]any{"frames": 4, "dt": 1.0 / 60},
			StepParams{},
			true,
		},
		{MethodPageCaptureScreenshot, nil, EmptyParams{}, false},
		{MethodAppReloadContent, nil, EmptyParams{}, true},
		{MethodAppStartNewGame, nil, EmptyParams{}, true},
		{
			MethodAppSave,
			SaveSlotParams{Slot: "slot-1"},
			SaveSlotParams{},
			true,
		},
		{
			MethodAppLoad,
			SaveSlotParams{Slot: "slot-1"},
			SaveSlotParams{},
			true,
		},
		{MethodAppQuit, nil, EmptyParams{}, true},
	}
	if len(cases)+2+len(CompatibilityAliases()) != len(Methods()) {
		t.Fatalf(
			"dispatch test covers %d methods, protocol advertises %d",
			len(cases)+2+len(CompatibilityAliases()),
			len(Methods()),
		)
	}

	for _, test := range cases {
		t.Run(test.method, func(t *testing.T) {
			var result struct {
				Method string `json:"method"`
			}
			if err := client.Call(
				context.Background(),
				test.method,
				test.params,
				&result,
			); err != nil {
				t.Fatal(err)
			}
			if result.Method != test.method {
				t.Fatalf("unexpected result method %q", result.Method)
			}
		})
	}

	calls := backend.snapshot()
	if len(calls) != len(cases) {
		t.Fatalf("got %d backend calls, want %d", len(calls), len(cases))
	}
	for index, test := range cases {
		call := calls[index]
		if call.Method != test.method {
			t.Errorf(
				"call %d method = %q, want %q",
				index,
				call.Method,
				test.method,
			)
		}
		if reflect.TypeOf(call.Params) != reflect.TypeOf(test.paramsType) {
			t.Errorf(
				"%s params type = %T, want %T",
				test.method,
				call.Params,
				test.paramsType,
			)
		}
		if call.Mutating() != test.mutating {
			t.Errorf(
				"%s Mutating() = %t, want %t",
				test.method,
				call.Mutating(),
				test.mutating,
			)
		}
	}

	callFor := func(method string) Call {
		t.Helper()
		for _, call := range calls {
			if call.Method == method {
				return call
			}
		}
		t.Fatalf("backend call %q was not recorded", method)
		return Call{}
	}
	spawn := callFor(MethodEntitySpawn).Params.(SpawnEntityParams)
	if spawn.X == nil || spawn.Y == nil ||
		*spawn.X != spawnX || *spawn.Y != spawnY {
		t.Fatalf("spawn coordinates were not preserved: %+v", spawn)
	}
	buy := callFor(MethodShopBuy).Params.(ShopTradeParams)
	if buy.ItemID != "item.potion" || buy.Quantity != 1 {
		t.Fatalf("shop buy defaults were not normalized: %+v", buy)
	}
	sell := callFor(MethodShopSell).Params.(ShopTradeParams)
	if sell.ItemID != "item.potion" || sell.Quantity != 2 {
		t.Fatalf("shop sell params were not preserved: %+v", sell)
	}
	input := callFor(MethodInputAction).Params.(InputActionParams)
	if input.Value != 1 || input.Frames != 1 {
		t.Fatalf("input defaults were not normalized: %+v", input)
	}
	validated := callFor(MethodContentValidateDefinition).
		Params.(ValidateDefinitionParams)
	if string(validated.Definition) != string(definition) {
		t.Fatalf("definition changed: %s", validated.Definition)
	}
}

func TestMakerPreviewParamsPreserveProtocolV8Contract(t *testing.T) {
	backend := &callRecorder{}
	address, _ := startTestServer(t, backend, Config{})
	client := newTestClient(t, address)

	if _, err := client.CallRaw(
		context.Background(),
		MethodEntitySpawn,
		map[string]any{"actorId": "actor.slime"},
	); err != nil {
		t.Fatal(err)
	}
	if _, err := client.CallRaw(
		context.Background(),
		MethodDialogueStart,
		map[string]any{"dialogueId": "dialogue.guide"},
	); err != nil {
		t.Fatal(err)
	}

	calls := backend.snapshot()
	if len(calls) != 2 {
		t.Fatalf("got %d calls, want 2", len(calls))
	}
	spawn := calls[0].Params.(SpawnEntityParams)
	if spawn.ActorID != "actor.slime" ||
		spawn.EntityID != "" ||
		spawn.X != nil ||
		spawn.Y != nil {
		t.Fatalf("unexpected default spawn params: %+v", spawn)
	}
	dialogue := calls[1].Params.(StartDialogueParams)
	if dialogue.DialogueID != "dialogue.guide" ||
		dialogue.SpeakerID != "" {
		t.Fatalf("unexpected default dialogue params: %+v", dialogue)
	}
}

func TestResponseObserverRunsAfterSuccessfulAcknowledgement(t *testing.T) {
	backend := &observingRecorder{written: make(chan string, 1)}
	address, _ := startTestServer(t, backend, Config{})
	client := newTestClient(t, address)
	if _, err := client.CallRaw(
		context.Background(),
		MethodAppQuit,
		nil,
	); err != nil {
		t.Fatal(err)
	}
	select {
	case method := <-backend.written:
		if method != MethodAppQuit {
			t.Fatalf("observer method = %q", method)
		}
	case <-time.After(time.Second):
		t.Fatal("response observer was not notified")
	}
}

func TestProtocolV8CompatibilityAliasesNormalize(t *testing.T) {
	backend := &callRecorder{}
	address, _ := startTestServer(t, backend, Config{})
	client := newTestClient(t, address)
	cases := []struct {
		alias     string
		canonical string
		params    any
	}{
		{
			MethodLegacyTestSetPaused,
			MethodEmulationSetPaused,
			SetPausedParams{Enabled: true},
		},
		{
			MethodLegacyTestStep,
			MethodEmulationStep,
			map[string]any{"frames": 2},
		},
		{
			MethodLegacySaveWrite,
			MethodAppSave,
			SaveSlotParams{Slot: "slot-1"},
		},
		{
			MethodLegacySaveLoad,
			MethodAppLoad,
			SaveSlotParams{Slot: "slot-1"},
		},
	}
	for _, test := range cases {
		if _, err := client.CallRaw(
			context.Background(),
			test.alias,
			test.params,
		); err != nil {
			t.Fatalf("%s: %v", test.alias, err)
		}
	}
	calls := backend.snapshot()
	if len(calls) != len(cases) {
		t.Fatalf("got %d calls, want %d", len(calls), len(cases))
	}
	for index, test := range cases {
		if calls[index].Method != test.canonical {
			t.Errorf(
				"%s reached backend as %q, want %q",
				test.alias,
				calls[index].Method,
				test.canonical,
			)
		}
	}
}

func TestProtocolDiscoveryIsInternalAndStable(t *testing.T) {
	backend := &callRecorder{}
	address, server := startTestServer(t, backend, Config{})
	client := newTestClient(t, address)

	var ping struct {
		Pong      bool `json:"pong"`
		Protocol  int  `json:"protocol"`
		Transport struct {
			Loopback bool   `json:"loopback_only"`
			Framing  string `json:"framing"`
		} `json:"transport"`
	}
	if err := client.Call(
		context.Background(),
		MethodRuntimePing,
		nil,
		&ping,
	); err != nil {
		t.Fatal(err)
	}
	if !ping.Pong || ping.Protocol != Version ||
		!ping.Transport.Loopback ||
		ping.Transport.Framing != "ndjson" {
		t.Fatalf("unexpected ping result: %+v", ping)
	}

	var info struct {
		Version int      `json:"version"`
		Methods []string `json:"methods"`
		Limits  struct {
			Request  int `json:"request_bytes"`
			Params   int `json:"params_bytes"`
			Response int `json:"response_bytes"`
		} `json:"limits"`
	}
	if err := client.Call(
		context.Background(),
		MethodRuntimeGetProtocol,
		nil,
		&info,
	); err != nil {
		t.Fatal(err)
	}
	if info.Version != Version ||
		!reflect.DeepEqual(info.Methods, Methods()) {
		t.Fatalf("unexpected protocol info: %+v", info)
	}
	config := server.Config()
	if info.Limits.Request != config.MaxRequestBytes ||
		info.Limits.Params != config.MaxParamsBytes ||
		info.Limits.Response != config.MaxResponseBytes {
		t.Fatalf("advertised limits do not match config: %+v", info.Limits)
	}
	if len(backend.snapshot()) != 0 {
		t.Fatal("discovery methods reached the backend")
	}
}

func TestProtocolSupportsMultipleNDJSONRequestsPerConnection(t *testing.T) {
	address, _ := startTestServer(t, &callRecorder{}, Config{})
	connection, err := net.DialTimeout("tcp", address, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close()
	if err := connection.SetDeadline(time.Now().Add(2 * time.Second)); err != nil {
		t.Fatal(err)
	}
	for _, id := range []uint64{41, 42} {
		request := Request{
			ID:     id,
			Method: MethodRuntimeGetState,
			Params: json.RawMessage(`{}`),
		}
		if err := json.NewEncoder(connection).Encode(request); err != nil {
			t.Fatal(err)
		}
	}
	decoder := json.NewDecoder(connection)
	for _, id := range []uint64{41, 42} {
		var response Response
		if err := decoder.Decode(&response); err != nil {
			t.Fatal(err)
		}
		if response.ID != id || response.Error != nil ||
			len(response.Result) == 0 {
			t.Fatalf("unexpected response for ID %d: %+v", id, response)
		}
	}
}

func TestProtocolRejectsInvalidRequestsAndStrictParams(t *testing.T) {
	backend := &callRecorder{}
	address, _ := startTestServer(t, backend, Config{})

	cases := []struct {
		name   string
		line   string
		wantID uint64
		code   string
	}{
		{
			"malformed JSON",
			`{"id":9`,
			0,
			CodeParseError,
		},
		{
			"missing ID",
			`{"method":"Runtime.getState","params":{}}`,
			0,
			CodeInvalidRequest,
		},
		{
			"zero ID",
			`{"id":0,"method":"Runtime.getState","params":{}}`,
			0,
			CodeInvalidRequest,
		},
		{
			"unknown envelope field",
			`{"id":7,"method":"Runtime.getState","params":{},"extra":1}`,
			7,
			CodeInvalidRequest,
		},
		{
			"duplicate key",
			`{"id":8,"method":"Runtime.getState","params":{"x":1,"x":2}}`,
			8,
			CodeInvalidRequest,
		},
		{
			"array params",
			`{"id":10,"method":"Runtime.getState","params":[]}`,
			10,
			CodeInvalidParams,
		},
		{
			"null params",
			`{"id":11,"method":"Runtime.getState","params":null}`,
			11,
			CodeInvalidParams,
		},
		{
			"unknown empty param",
			`{"id":12,"method":"World.getSnapshot","params":{"extra":1}}`,
			12,
			CodeInvalidParams,
		},
		{
			"position missing coordinates",
			`{"id":13,"method":"Entity.setPosition","params":{"entityId":"p"}}`,
			13,
			CodeInvalidParams,
		},
		{
			"spawn missing actor",
			`{"id":131,"method":"Entity.spawn","params":{"entityId":"preview","x":1,"y":2}}`,
			131,
			CodeInvalidParams,
		},
		{
			"spawn has only x",
			`{"id":132,"method":"Entity.spawn","params":{"actorId":"actor.slime","x":1}}`,
			132,
			CodeInvalidParams,
		},
		{
			"spawn blank entity id",
			`{"id":133,"method":"Entity.spawn","params":{"actorId":"actor.slime","entityId":""}}`,
			133,
			CodeInvalidParams,
		},
		{
			"spawn rejects unauthored tags",
			`{"id":134,"method":"Entity.spawn","params":{"actorId":"actor.slime","tags":["enemy"]}}`,
			134,
			CodeInvalidParams,
		},
		{
			"spawn rejects control override",
			`{"id":135,"method":"Entity.spawn","params":{"actorId":"actor.slime","controlled":true}}`,
			135,
			CodeInvalidParams,
		},
		{
			"remove missing entity",
			`{"id":136,"method":"Entity.remove","params":{}}`,
			136,
			CodeInvalidParams,
		},
		{
			"dialogue missing definition",
			`{"id":137,"method":"Dialogue.start","params":{"speakerId":"guide"}}`,
			137,
			CodeInvalidParams,
		},
		{
			"dialogue blank speaker",
			`{"id":138,"method":"Dialogue.start","params":{"dialogueId":"dialogue.guide","speakerId":""}}`,
			138,
			CodeInvalidParams,
		},
		{
			"dialogue rejects unknown npc context",
			`{"id":139,"method":"Dialogue.start","params":{"dialogueId":"dialogue.guide","npcId":"guide"}}`,
			139,
			CodeInvalidParams,
		},
		{
			"dialogue state rejects params",
			`{"id":1391,"method":"Dialogue.getState","params":{"extra":true}}`,
			1391,
			CodeInvalidParams,
		},
		{
			"dialogue choose missing choice",
			`{"id":1392,"method":"Dialogue.choose","params":{}}`,
			1392,
			CodeInvalidParams,
		},
		{
			"dialogue choose blank choice",
			`{"id":1393,"method":"Dialogue.choose","params":{"choice_id":"  "}}`,
			1393,
			CodeInvalidParams,
		},
		{
			"dialogue choose rejects camel case",
			`{"id":1394,"method":"Dialogue.choose","params":{"choiceId":"accept"}}`,
			1394,
			CodeInvalidParams,
		},
		{
			"dialogue choose rejects unknown context",
			`{"id":1395,"method":"Dialogue.choose","params":{"choice_id":"accept","node_id":"greeting"}}`,
			1395,
			CodeInvalidParams,
		},
		{
			"dialogue advance rejects params",
			`{"id":1396,"method":"Dialogue.advance","params":{"choice_id":"accept"}}`,
			1396,
			CodeInvalidParams,
		},
		{
			"campaign state rejects params",
			`{"id":1401,"method":"Campaign.getState","params":{"extra":true}}`,
			1401,
			CodeInvalidParams,
		},
		{
			"flow state rejects params",
			`{"id":14011,"method":"Flow.getState","params":{"extra":true}}`,
			14011,
			CodeInvalidParams,
		},
		{
			"flow move requires delta",
			`{"id":14012,"method":"Flow.move","params":{}}`,
			14012,
			CodeInvalidParams,
		},
		{
			"flow move rejects zero",
			`{"id":14013,"method":"Flow.move","params":{"delta":0}}`,
			14013,
			CodeInvalidParams,
		},
		{
			"flow move rejects fractional delta",
			`{"id":14014,"method":"Flow.move","params":{"delta":1.5}}`,
			14014,
			CodeInvalidParams,
		},
		{
			"flow activate requires option",
			`{"id":14015,"method":"Flow.activate","params":{}}`,
			14015,
			CodeInvalidParams,
		},
		{
			"flow activate rejects blank option",
			`{"id":14016,"method":"Flow.activate","params":{"option_id":"  "}}`,
			14016,
			CodeInvalidParams,
		},
		{
			"flow activate rejects camel case",
			`{"id":14017,"method":"Flow.activate","params":{"optionId":"new_game"}}`,
			14017,
			CodeInvalidParams,
		},
		{
			"shop state rejects params",
			`{"id":1402,"method":"Shop.getState","params":{"shop_id":"shop.village"}}`,
			1402,
			CodeInvalidParams,
		},
		{
			"shop buy requires item",
			`{"id":1403,"method":"Shop.buy","params":{}}`,
			1403,
			CodeInvalidParams,
		},
		{
			"shop buy rejects null quantity",
			`{"id":1404,"method":"Shop.buy","params":{"item_id":"item.potion","quantity":null}}`,
			1404,
			CodeInvalidParams,
		},
		{
			"shop buy rejects fractional quantity",
			`{"id":1405,"method":"Shop.buy","params":{"item_id":"item.potion","quantity":1.5}}`,
			1405,
			CodeInvalidParams,
		},
		{
			"shop buy rejects zero quantity",
			`{"id":1406,"method":"Shop.buy","params":{"item_id":"item.potion","quantity":0}}`,
			1406,
			CodeInvalidParams,
		},
		{
			"shop buy rejects negative quantity",
			`{"id":1407,"method":"Shop.buy","params":{"item_id":"item.potion","quantity":-1}}`,
			1407,
			CodeInvalidParams,
		},
		{
			"shop buy rejects quantity above max JSON integer",
			`{"id":1408,"method":"Shop.buy","params":{"item_id":"item.potion","quantity":9007199254740992}}`,
			1408,
			CodeInvalidParams,
		},
		{
			"shop buy rejects unknown field",
			`{"id":1409,"method":"Shop.buy","params":{"item_id":"item.potion","discount":1}}`,
			1409,
			CodeInvalidParams,
		},
		{
			"shop sell rejects blank item",
			`{"id":1410,"method":"Shop.sell","params":{"item_id":"  "}}`,
			1410,
			CodeInvalidParams,
		},
		{
			"shop close rejects params",
			`{"id":1411,"method":"Shop.close","params":{"force":true}}`,
			1411,
			CodeInvalidParams,
		},
		{
			"inventory use requires item",
			`{"id":1412,"method":"Inventory.use","params":{}}`,
			1412,
			CodeInvalidParams,
		},
		{
			"inventory use rejects unknown field",
			`{"id":1413,"method":"Inventory.use","params":{"item_id":"item.potion","quantity":1}}`,
			1413,
			CodeInvalidParams,
		},
		{
			"equipment equip requires item",
			`{"id":1414,"method":"Equipment.equip","params":{}}`,
			1414,
			CodeInvalidParams,
		},
		{
			"equipment equip rejects unknown field",
			`{"id":1415,"method":"Equipment.equip","params":{"item_id":"item.sword","slot_id":"weapon"}}`,
			1415,
			CodeInvalidParams,
		},
		{
			"equipment unequip requires slot",
			`{"id":1416,"method":"Equipment.unequip","params":{}}`,
			1416,
			CodeInvalidParams,
		},
		{
			"equipment unequip rejects unknown field",
			`{"id":1417,"method":"Equipment.unequip","params":{"slot_id":"weapon","item_id":"item.sword"}}`,
			1417,
			CodeInvalidParams,
		},
		{
			"health missing value",
			`{"id":14,"method":"Entity.setHealth","params":{"entityId":"p"}}`,
			14,
			CodeInvalidParams,
		},
		{
			"fractional frames",
			`{"id":15,"method":"Input.action","params":{"action":"attack","frames":1.5}}`,
			15,
			CodeInvalidParams,
		},
		{
			"input value out of range",
			`{"id":151,"method":"Input.action","params":{"action":"move_x","value":2}}`,
			151,
			CodeInvalidParams,
		},
		{
			"too many frames",
			`{"id":16,"method":"Emulation.step","params":{"frames":3601}}`,
			16,
			CodeInvalidParams,
		},
		{
			"nonpositive dt",
			`{"id":17,"method":"Emulation.step","params":{"dt":0}}`,
			17,
			CodeInvalidParams,
		},
		{
			"non-fixed dt",
			`{"id":171,"method":"Emulation.step","params":{"dt":0.02}}`,
			171,
			CodeInvalidParams,
		},
		{
			"definition is array",
			`{"id":18,"method":"Content.validateDefinition","params":{"contentId":"a","definition":[]}}`,
			18,
			CodeInvalidParams,
		},
		{
			"blank save slot",
			`{"id":19,"method":"App.save","params":{"slot":"  "}}`,
			19,
			CodeInvalidParams,
		},
		{
			"path traversal save slot",
			`{"id":191,"method":"App.save","params":{"slot":"../outside"}}`,
			191,
			CodeInvalidParams,
		},
		{
			"unknown method",
			`{"id":20,"method":"Runtime.destroy","params":{}}`,
			20,
			CodeMethodNotFound,
		},
	}

	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			response := rawRoundTrip(t, address, test.line)
			if response.ID != test.wantID {
				t.Errorf("response ID = %d, want %d", response.ID, test.wantID)
			}
			if response.Error == nil || response.Error.Code != test.code {
				t.Fatalf(
					"response error = %+v, want code %q",
					response.Error,
					test.code,
				)
			}
			if len(response.Result) != 0 {
				t.Fatalf("error response contained a result: %s", response.Result)
			}
		})
	}
	if calls := backend.snapshot(); len(calls) != 0 {
		t.Fatalf("invalid requests reached backend: %+v", calls)
	}
}

func TestProtocolBoundsRequestParamsAndResponse(t *testing.T) {
	backend := &callRecorder{
		fn: func(context.Context, Call) (any, error) {
			return map[string]string{"data": strings.Repeat("x", 500)}, nil
		},
	}
	address, _ := startTestServer(t, backend, Config{
		MaxRequestBytes:  512,
		MaxParamsBytes:   96,
		MaxResponseBytes: 256,
	})

	response := rawRoundTrip(
		t,
		address,
		`{"id":21,"method":"Content.getDefinition","params":{"contentId":"`+
			strings.Repeat("a", 150)+`"}}`,
	)
	if response.Error == nil ||
		response.Error.Code != CodeRequestTooLarge {
		t.Fatalf("unexpected params limit response: %+v", response)
	}

	response = rawRoundTrip(
		t,
		address,
		`{"id":22,"method":"Runtime.getState","params":{}}`,
	)
	if response.Error == nil ||
		response.Error.Code != CodeResponseTooLarge {
		t.Fatalf("unexpected response limit result: %+v", response)
	}

	connection, err := net.Dial("tcp", address)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close()
	_ = connection.SetDeadline(time.Now().Add(time.Second))
	if _, err := fmt.Fprintln(connection, strings.Repeat("x", 513)); err != nil {
		t.Fatal(err)
	}
	var oversized Response
	if err := json.NewDecoder(connection).Decode(&oversized); err != nil {
		t.Fatal(err)
	}
	if oversized.ID != 0 || oversized.Error == nil ||
		oversized.Error.Code != CodeRequestTooLarge {
		t.Fatalf("unexpected line limit response: %+v", oversized)
	}
}

func TestProtocolReadDeadlineClosesSlowClient(t *testing.T) {
	address, _ := startTestServer(t, &callRecorder{}, Config{
		ReadTimeout: 50 * time.Millisecond,
	})
	connection, err := net.Dial("tcp", address)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close()
	if err := connection.SetReadDeadline(time.Now().Add(time.Second)); err != nil {
		t.Fatal(err)
	}
	started := time.Now()
	var one [1]byte
	_, err = connection.Read(one[:])
	if err == nil {
		t.Fatal("slow connection unexpectedly remained open")
	}
	if time.Since(started) > 750*time.Millisecond {
		t.Fatalf("server did not apply its read deadline: %v", err)
	}
}

func TestProtocolPassesAndReportsBackendDeadline(t *testing.T) {
	backend := BackendFunc(func(
		ctx context.Context,
		_ Call,
	) (any, error) {
		<-ctx.Done()
		return nil, ctx.Err()
	})
	address, _ := startTestServer(t, backend, Config{
		BackendTimeout: 40 * time.Millisecond,
	})
	client := newTestClient(t, address)
	started := time.Now()
	_, err := client.CallRaw(
		context.Background(),
		MethodRuntimeGetState,
		nil,
	)
	var rpcErr *Error
	if !errors.As(err, &rpcErr) || rpcErr.Code != CodeTimeout {
		t.Fatalf("backend timeout response = %#v", err)
	}
	if time.Since(started) > 500*time.Millisecond {
		t.Fatalf("backend deadline was not enforced promptly: %v", err)
	}
}

func TestProtocolSerializesMutationsAndAllowsConcurrentQueries(
	t *testing.T,
) {
	var activeMutations atomic.Int32
	var maxMutations atomic.Int32
	var activeQueries atomic.Int32
	queriesTogether := make(chan struct{})
	var closeQueries sync.Once

	backend := &callRecorder{
		fn: func(ctx context.Context, call Call) (any, error) {
			if call.Mutating() {
				active := activeMutations.Add(1)
				raiseMax(&maxMutations, active)
				time.Sleep(15 * time.Millisecond)
				activeMutations.Add(-1)
				return map[string]any{"ok": true}, nil
			}
			if call.Method == MethodRuntimeGetState {
				if activeQueries.Add(1) == 2 {
					closeQueries.Do(func() { close(queriesTogether) })
				}
				select {
				case <-queriesTogether:
				case <-ctx.Done():
					return nil, ctx.Err()
				}
				activeQueries.Add(-1)
			}
			return map[string]any{"ok": true}, nil
		},
	}
	address, _ := startTestServer(t, backend, Config{})
	client := newTestClient(t, address)

	var queries sync.WaitGroup
	errs := make(chan error, 2)
	for range 2 {
		queries.Add(1)
		go func() {
			defer queries.Done()
			_, err := client.CallRaw(
				context.Background(),
				MethodRuntimeGetState,
				nil,
			)
			errs <- err
		}()
	}
	queries.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}

	var mutations sync.WaitGroup
	mutationErrors := make(chan error, 8)
	for range 8 {
		mutations.Add(1)
		go func() {
			defer mutations.Done()
			_, err := client.CallRaw(
				context.Background(),
				MethodInputAction,
				map[string]any{"action": "attack"},
			)
			mutationErrors <- err
		}()
	}
	mutations.Wait()
	close(mutationErrors)
	for err := range mutationErrors {
		if err != nil {
			t.Fatal(err)
		}
	}
	if maximum := maxMutations.Load(); maximum != 1 {
		t.Fatalf("maximum concurrent mutations = %d, want 1", maximum)
	}
}

func TestProtocolHoldsMutationGateUntilResultIsDetached(t *testing.T) {
	marshalStarted := make(chan struct{})
	releaseMarshal := make(chan struct{})
	var backendCalls atomic.Int32
	backend := BackendFunc(func(
		_ context.Context,
		_ Call,
	) (any, error) {
		if backendCalls.Add(1) == 1 {
			return blockingJSONResult{
				started: marshalStarted,
				release: releaseMarshal,
			}, nil
		}
		return map[string]any{"ok": true}, nil
	})
	address, _ := startTestServer(t, backend, Config{})
	client := newTestClient(t, address)

	firstDone := make(chan error, 1)
	go func() {
		_, err := client.CallRaw(
			context.Background(),
			MethodInputAction,
			map[string]any{"action": "attack"},
		)
		firstDone <- err
	}()
	select {
	case <-marshalStarted:
	case <-time.After(time.Second):
		t.Fatal("first result did not begin marshaling")
	}

	secondDone := make(chan error, 1)
	go func() {
		_, err := client.CallRaw(
			context.Background(),
			MethodEntitySetHealth,
			SetHealthParams{EntityID: "player", Value: 1},
		)
		secondDone <- err
	}()
	time.Sleep(30 * time.Millisecond)
	if calls := backendCalls.Load(); calls != 1 {
		t.Fatalf(
			"second mutation entered backend while result was mutable: %d calls",
			calls,
		)
	}
	close(releaseMarshal)
	for index, done := range []<-chan error{firstDone, secondDone} {
		select {
		case err := <-done:
			if err != nil {
				t.Fatalf("call %d: %v", index, err)
			}
		case <-time.After(time.Second):
			t.Fatalf("call %d did not finish", index)
		}
	}
}

func TestProtocolBackendErrorsAndPanicAreContained(t *testing.T) {
	var calls atomic.Int32
	backend := &callRecorder{
		fn: func(_ context.Context, call Call) (any, error) {
			switch calls.Add(1) {
			case 1:
				return nil, &Error{
					Code:    "not_found",
					Message: "missing entity",
					Data:    map[string]any{"entityId": "ghost"},
				}
			case 2:
				panic("boom")
			default:
				return map[string]any{"recovered": true}, nil
			}
		},
	}
	address, _ := startTestServer(t, backend, Config{})
	client := newTestClient(t, address)

	_, err := client.CallRaw(
		context.Background(),
		MethodEntitySetHealth,
		SetHealthParams{EntityID: "ghost", Value: 1},
	)
	var rpcErr *Error
	if !errors.As(err, &rpcErr) ||
		rpcErr.Code != "not_found" ||
		rpcErr.Data == nil {
		t.Fatalf("typed backend error was not preserved: %#v", err)
	}

	_, err = client.CallRaw(
		context.Background(),
		MethodEntitySetHealth,
		SetHealthParams{EntityID: "player", Value: 1},
	)
	if !errors.As(err, &rpcErr) || rpcErr.Code != CodeInternal {
		t.Fatalf("panic response = %#v", err)
	}

	var result struct {
		Recovered bool `json:"recovered"`
	}
	if err := client.Call(
		context.Background(),
		MethodEntitySetHealth,
		SetHealthParams{EntityID: "player", Value: 2},
		&result,
	); err != nil {
		t.Fatal(err)
	}
	if !result.Recovered {
		t.Fatal("mutation gate remained locked after backend panic")
	}
}

func TestProtocolContainsPanickingBackendErrorData(t *testing.T) {
	var calls atomic.Int32
	backend := BackendFunc(func(
		_ context.Context,
		_ Call,
	) (any, error) {
		if calls.Add(1) == 1 {
			return nil, &Error{
				Code:    "bad_data",
				Message: "bad data",
				Data:    panickingJSONResult{},
			}
		}
		return map[string]any{"recovered": true}, nil
	})
	address, _ := startTestServer(t, backend, Config{})
	client := newTestClient(t, address)

	_, err := client.CallRaw(
		context.Background(),
		MethodInputAction,
		map[string]any{"action": "attack"},
	)
	var rpcErr *Error
	if !errors.As(err, &rpcErr) || rpcErr.Code != CodeInternal {
		t.Fatalf("panicking error data response = %#v", err)
	}
	if _, err := client.CallRaw(
		context.Background(),
		MethodInputAction,
		map[string]any{"action": "attack"},
	); err != nil {
		t.Fatalf("server did not recover after error-data panic: %v", err)
	}
}

func TestProtocolRequiresLoopback(t *testing.T) {
	for _, address := range []string{
		"0.0.0.0:19832",
		"[::]:19832",
		"192.0.2.10:19832",
		":19832",
	} {
		t.Run(address, func(t *testing.T) {
			_, err := NewServer(&callRecorder{}, Config{Address: address})
			if err == nil {
				t.Fatalf("accepted non-loopback address %q", address)
			}
			_, err = NewClient(ClientConfig{Address: address})
			if err == nil {
				t.Fatalf("client accepted non-loopback address %q", address)
			}
		})
	}
	for _, address := range []string{
		"127.0.0.1:0",
		"localhost:19832",
		"[::1]:19832",
	} {
		t.Run(address, func(t *testing.T) {
			if _, err := NewServer(
				&callRecorder{},
				Config{Address: address},
			); err != nil {
				t.Fatalf("rejected loopback address %q: %v", address, err)
			}
		})
	}
	server, err := NewServer(&callRecorder{}, Config{})
	if err != nil {
		t.Fatal(err)
	}
	if err := server.ListenAndServe(nil); err == nil {
		t.Fatal("ListenAndServe accepted a nil context")
	}
}

func TestProtocolOptionalAuthentication(t *testing.T) {
	backend := &callRecorder{}
	address, _ := startTestServer(t, backend, Config{
		AuthToken: "private-test-token",
	})
	for _, token := range []string{"", "wrong-token"} {
		client, err := NewClient(ClientConfig{
			Address:   address,
			Timeout:   time.Second,
			AuthToken: token,
		})
		if err != nil {
			t.Fatal(err)
		}
		_, err = client.CallRaw(
			context.Background(),
			MethodRuntimeGetState,
			nil,
		)
		var rpcErr *Error
		if !errors.As(err, &rpcErr) ||
			rpcErr.Code != CodeUnauthorized {
			t.Fatalf("token %q error = %#v", token, err)
		}
	}
	if calls := backend.snapshot(); len(calls) != 0 {
		t.Fatalf("unauthorized request reached backend: %+v", calls)
	}

	client, err := NewClient(ClientConfig{
		Address:   address,
		Timeout:   time.Second,
		AuthToken: "private-test-token",
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := client.CallRaw(
		context.Background(),
		MethodRuntimeGetState,
		nil,
	); err != nil {
		t.Fatal(err)
	}
	if calls := backend.snapshot(); len(calls) != 1 {
		t.Fatalf("authenticated call count = %d, want 1", len(calls))
	}
}

func rawRoundTrip(t *testing.T, address, line string) Response {
	t.Helper()
	connection, err := net.DialTimeout("tcp", address, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close()
	if err := connection.SetDeadline(time.Now().Add(2 * time.Second)); err != nil {
		t.Fatal(err)
	}
	if _, err := fmt.Fprintln(connection, line); err != nil {
		t.Fatal(err)
	}
	responseLine, err := bufio.NewReader(connection).ReadBytes('\n')
	if err != nil {
		t.Fatal(err)
	}
	var response Response
	if err := json.Unmarshal(responseLine, &response); err != nil {
		t.Fatalf("decode response %q: %v", responseLine, err)
	}
	return response
}

func raiseMax(maximum *atomic.Int32, candidate int32) {
	for {
		current := maximum.Load()
		if candidate <= current || maximum.CompareAndSwap(current, candidate) {
			return
		}
	}
}
