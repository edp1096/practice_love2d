package gameapp

import (
	"encoding/json"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/protocol"
	"practice_love2d/33_ebitengine_spike/internal/sim"
	"practice_love2d/33_ebitengine_spike/internal/storage"
)

func TestHomeRestTriggerUsesEntryEdgeAndAuthoredCooldown(t *testing.T) {
	runtime := newTriggerRuntime(t, "stage.village_home", "entry")

	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetHealth,
		protocol.SetHealthParams{EntityID: "player", Value: 50},
	)
	setEntityPosition(t, runtime, "player", 144, 144)
	stepProtocol(t, runtime, 1)
	if got := entitySnapshot(t, runtime, "player").Health; got != 80 {
		t.Fatalf("first rest trigger health = %d, want 80", got)
	}
	notice := runtime.View().Notice
	if !notice.Active ||
		notice.Text != "집에서 쉬어 체력을 30 회복했습니다." ||
		notice.TextKey != "notice.home.rest" ||
		notice.Tone != "success" ||
		notice.RemainingTicks != 180 {
		t.Fatalf("rest notice = %#v", notice)
	}
	if got := runtime.worldSnapshotLocked().Notice; got != notice {
		t.Fatalf("debug notice = %#v, want %#v", got, notice)
	}

	// Remaining inside is not a new edge, even if health changes.
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetHealth,
		protocol.SetHealthParams{EntityID: "player", Value: 60},
	)
	stepProtocol(t, runtime, 1)
	if got := entitySnapshot(t, runtime, "player").Health; got != 60 {
		t.Fatalf("inside rest trigger repeated: health = %d", got)
	}
	if got := runtime.View().Notice.RemainingTicks; got != 179 {
		t.Fatalf("rest notice remaining = %d, want 179", got)
	}

	setEntityPosition(t, runtime, "player", 300, 240)
	stepProtocol(t, runtime, 60)
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetHealth,
		protocol.SetHealthParams{EntityID: "player", Value: 40},
	)
	setEntityPosition(t, runtime, "player", 144, 144)
	stepProtocol(t, runtime, 1)
	if got := entitySnapshot(t, runtime, "player").Health; got != 70 {
		t.Fatalf("re-entered rest trigger health = %d, want 70", got)
	}
}

func TestGroveDiscoveryTriggerEmitsOnceWithAuthoredContext(t *testing.T) {
	runtime := newTriggerRuntime(t, "stage.world_grove", "west_entry")

	setEntityPosition(t, runtime, "player", 630, 410)
	stepProtocol(t, runtime, 1)
	event, found := authoredEvent(
		runtime.simulation.Snapshot().Events,
		"world.grove_discovered",
	)
	if !found {
		t.Fatal("grove discovery trigger did not emit its authored event")
	}
	if event.EntityID != "player" ||
		event.TriggerID != "grove_discovery" {
		t.Fatalf("grove discovery event identity = %#v", event)
	}
	var payload map[string]string
	if err := json.Unmarshal(event.Data, &payload); err != nil {
		t.Fatal(err)
	}
	if payload["region"] != "grove" ||
		payload["entity_id"] != "player" ||
		payload["trigger_id"] != "grove_discovery" {
		t.Fatalf("grove discovery event payload = %#v", payload)
	}
	if !runtime.triggerFired["grove_discovery"] {
		t.Fatal("once trigger did not retain its fired latch")
	}
	notice := runtime.View().Notice
	if !notice.Active ||
		notice.Text !=
			"강한 기운이 느껴집니다. 수호자의 공격을 패링하세요." ||
		notice.TextKey != "notice.grove.warning" ||
		notice.Tone != "warning" ||
		notice.RemainingTicks != 240 {
		t.Fatalf("grove warning notice = %#v", notice)
	}

	setEntityPosition(t, runtime, "player", 400, 288)
	stepProtocol(t, runtime, 1)
	setEntityPosition(t, runtime, "player", 630, 410)
	stepProtocol(t, runtime, 1)
	if _, found := authoredEvent(
		runtime.simulation.Snapshot().Events,
		"world.grove_discovered",
	); found {
		t.Fatal("once trigger emitted again after re-entry")
	}
}

func TestFieldWorldItemUsesPersistentEventPageAndCannotDuplicateReward(
	t *testing.T,
) {
	runtime := newTriggerRuntime(t, "stage.world_hub", "default")
	before := runtime.CampaignState()
	beforePotions := campaignItem(t, before, "item.potion").Quantity

	setEntityPosition(t, runtime, "player", 360, 420)
	callRuntime(
		t,
		runtime,
		protocol.MethodInputAction,
		protocol.InputActionParams{
			Action: "interact",
			Value:  1,
			Frames: 1,
		},
	)
	stepProtocol(t, runtime, 1)
	collected := runtime.CampaignState()
	if got := campaignItem(t, collected, "item.potion").Quantity; got != beforePotions+1 {
		t.Fatalf("world item potion quantity = %d, want %d", got, beforePotions+1)
	}
	if !campaignFlag(t, collected, "world.field_potion_collected") {
		t.Fatal("world item did not persist its collected flag")
	}
	if notice := runtime.View().Notice; !notice.Active ||
		notice.TextKey != "notice.field_potion.collected" ||
		notice.Tone != "success" {
		t.Fatalf("world item collection notice = %#v", notice)
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodInputAction,
		protocol.InputActionParams{
			Action: "interact",
			Value:  1,
			Frames: 1,
		},
	)
	stepProtocol(t, runtime, 1)
	again := runtime.CampaignState()
	if got := campaignItem(t, again, "item.potion").Quantity; got != beforePotions+1 {
		t.Fatalf("collected world item duplicated reward: %d", got)
	}
	if notice := runtime.View().Notice; notice.TextKey != "notice.field_potion.empty" {
		t.Fatalf("collected world item page = %#v", notice)
	}
}

func TestFieldHazardDamagesOnEntryAndCanCauseGameOver(t *testing.T) {
	runtime := newTriggerRuntime(t, "stage.world_hub", "default")
	hazardX, hazardY := triggerCenter(t, runtime, "toxic_mire")
	for _, enemyID := range []string{"enemy.slime.1", "enemy.slime.2"} {
		callRuntime(
			t,
			runtime,
			protocol.MethodEntitySetHealth,
			protocol.SetHealthParams{EntityID: enemyID, Value: 0},
		)
	}
	setEntityPosition(t, runtime, "player", hazardX, hazardY)
	stepProtocol(t, runtime, 1)
	if got := entitySnapshot(t, runtime, "player").Health; got != 88 {
		t.Fatalf("first hazard entry health = %d, want 88", got)
	}
	if notice := runtime.View().Notice; !notice.Active ||
		notice.TextKey != "notice.field.hazard" ||
		notice.Tone != "warning" {
		t.Fatalf("hazard notice = %#v", notice)
	}
	stepProtocol(t, runtime, 1)
	if got := entitySnapshot(t, runtime, "player").Health; got != 88 {
		t.Fatalf("hazard repeated while actor remained inside: %d", got)
	}

	setEntityPosition(t, runtime, "player", 200, 112)
	stepProtocol(t, runtime, 30)
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetHealth,
		protocol.SetHealthParams{EntityID: "player", Value: 12},
	)
	setEntityPosition(t, runtime, "player", hazardX, hazardY)
	stepProtocol(t, runtime, 1)
	player := entitySnapshot(t, runtime, "player")
	if !player.Dead || player.Health != 0 {
		t.Fatalf("lethal hazard result = %#v", player)
	}
	if mode := runtime.CampaignState().Mode; mode != campaign.ModeGameOver {
		t.Fatalf("lethal hazard mode = %q, want gameover", mode)
	}
}

func TestTriggerEventPagesSwitchAfterDurableFlagChange(t *testing.T) {
	runtime := newTriggerRuntime(t, "stage.village_home", "entry")
	runtime.built.Stage.Triggers = []gamebuild.Trigger{
		{
			ID: "story",
			Rect: sim.Rect{
				MinX: sim.Pixels(100),
				MinY: sim.Pixels(100),
				MaxX: sim.Pixels(190),
				MaxY: sim.Pixels(190),
			},
			Pages: []gamebuild.TriggerPage{
				{
					ID:   "before",
					Once: true,
					Actions: []gamebuild.RuleAction{
						{
							Type:      gamebuild.RuleActionSetFlag,
							FlagName:  "quest.grove_guardian.rewarded",
							FlagValue: true,
						},
					},
				},
				{
					ID:   "after",
					Once: true,
					Condition: &gamebuild.RuleCondition{
						Type:      gamebuild.RuleConditionFlag,
						FlagName:  "quest.grove_guardian.rewarded",
						FlagValue: true,
					},
					Actions: []gamebuild.RuleAction{
						{
							Type:     gamebuild.RuleActionAddCurrency,
							Currency: 1,
						},
					},
				},
			},
		},
	}
	runtime.resetTriggerStateLocked()
	beforeCurrency := runtime.CampaignState().Currency

	setEntityPosition(t, runtime, "player", 144, 144)
	stepProtocol(t, runtime, 1)
	if !runtime.triggerFired["story::before"] {
		t.Fatalf("before page did not fire: %#v", runtime.triggerFired)
	}
	if got := runtime.CampaignState().Currency; got != beforeCurrency {
		t.Fatalf("before page changed currency to %d", got)
	}

	setEntityPosition(t, runtime, "player", 300, 240)
	stepProtocol(t, runtime, 1)
	setEntityPosition(t, runtime, "player", 144, 144)
	stepProtocol(t, runtime, 1)
	if !runtime.triggerFired["story::after"] {
		t.Fatalf("after page did not fire: %#v", runtime.triggerFired)
	}
	if got := runtime.CampaignState().Currency; got != beforeCurrency+1 {
		t.Fatalf("after page currency = %d, want %d", got, beforeCurrency+1)
	}
}

func newTriggerRuntime(
	t *testing.T,
	stageID string,
	spawnID string,
) *Runtime {
	t.Helper()
	store, err := storage.NewFileStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{
		Build: gamebuild.Options{
			StageID: stageID,
			SpawnID: spawnID,
		},
		Store: store,
	})
	if err != nil {
		t.Fatal(err)
	}
	return runtime
}

func setEntityPosition(
	t *testing.T,
	runtime *Runtime,
	entityID string,
	x float64,
	y float64,
) {
	t.Helper()
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: entityID,
			X:        x,
			Y:        y,
		},
	)
}

func triggerCenter(
	t *testing.T,
	runtime *Runtime,
	triggerID string,
) (float64, float64) {
	t.Helper()
	for _, trigger := range runtime.built.Stage.Triggers {
		if trigger.ID != triggerID {
			continue
		}
		return float64(trigger.Rect.MinX+trigger.Rect.MaxX) /
				(2 * float64(sim.UnitsPerPixel)),
			float64(trigger.Rect.MinY+trigger.Rect.MaxY) /
				(2 * float64(sim.UnitsPerPixel))
	}
	t.Fatalf("stage trigger %q not found", triggerID)
	return 0, 0
}

func authoredEvent(
	events []sim.Event,
	eventType sim.EventType,
) (sim.Event, bool) {
	for _, event := range events {
		if event.Type == eventType {
			return event, true
		}
	}
	return sim.Event{}, false
}
