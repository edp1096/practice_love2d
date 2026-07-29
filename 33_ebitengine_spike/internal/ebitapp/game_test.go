package ebitapp

import (
	"image"
	"reflect"
	"strings"
	"testing"
	"unicode/utf8"
)

func TestTileDrawCommandsPreserveLayersGIDsFlipsAndCamera(t *testing.T) {
	t.Parallel()

	view := View{
		Camera: CameraView{
			X:      4,
			Y:      2,
			ShakeX: 1,
			ShakeY: -1,
			Zoom:   2,
		},
		Tilemap: &TilemapView{
			TileWidth:  16,
			TileHeight: 16,
			Tilesets: []TilesetView{{
				ID:         "terrain",
				AssetID:    "image.terrain",
				FirstGID:   1,
				TileCount:  4,
				Columns:    2,
				TileWidth:  8,
				TileHeight: 8,
			}},
			Layers: []TileLayerView{{
				ID:      "ground",
				Width:   2,
				Height:  2,
				Visible: true,
				Opacity: 0.5,
				OffsetX: 4,
				OffsetY: 2,
				Data: []uint32{
					1,
					tileFlipHorizontal | 2,
					tileFlipVertical | 3,
					tileFlipDiagonal | 4,
				},
			}},
		},
	}
	commands := tileDrawCommands(view)
	if len(commands) != 4 {
		t.Fatalf("tile commands = %#v", commands)
	}
	if commands[0].AssetID != "image.terrain" ||
		commands[0].Source != image.Rect(0, 0, 8, 8) ||
		commands[0].X != 2 ||
		commands[0].Y != -2 ||
		commands[0].Width != 32 ||
		commands[0].Height != 32 ||
		commands[0].Opacity != 0.5 {
		t.Fatalf("first tile command = %#v", commands[0])
	}
	if commands[1].Source != image.Rect(8, 0, 16, 8) ||
		!commands[1].FlipHorizontal ||
		commands[1].FlipVertical ||
		commands[1].FlipDiagonal {
		t.Fatalf("horizontal tile command = %#v", commands[1])
	}
	if commands[2].Source != image.Rect(0, 8, 8, 16) ||
		!commands[2].FlipVertical {
		t.Fatalf("vertical tile command = %#v", commands[2])
	}
	if commands[3].Source != image.Rect(8, 8, 16, 16) ||
		!commands[3].FlipDiagonal {
		t.Fatalf("diagonal tile command = %#v", commands[3])
	}

	horizontal := tileVertices(commands[1])
	if horizontal[0].SrcX != 16 || horizontal[1].SrcX != 8 {
		t.Fatalf("horizontal tile UVs = %#v", horizontal)
	}
	vertical := tileVertices(commands[2])
	if vertical[0].SrcY != 16 || vertical[3].SrcY != 8 {
		t.Fatalf("vertical tile UVs = %#v", vertical)
	}
	diagonal := tileVertices(commands[3])
	if diagonal[1].SrcX != 8 || diagonal[1].SrcY != 16 {
		t.Fatalf("diagonal tile UVs = %#v", diagonal)
	}
}

func TestTileDrawCommandsCullAndIgnoreHiddenMalformedLayers(t *testing.T) {
	t.Parallel()

	view := View{
		Camera: CameraView{X: 10_000, Y: 10_000, Zoom: 1},
		Tilemap: &TilemapView{
			TileWidth:  32,
			TileHeight: 32,
			Tilesets: []TilesetView{{
				AssetID:    "image.terrain",
				FirstGID:   1,
				TileCount:  1,
				Columns:    1,
				TileWidth:  32,
				TileHeight: 32,
			}},
			Layers: []TileLayerView{
				{
					ID:      "offscreen",
					Width:   1,
					Height:  1,
					Visible: true,
					Opacity: 1,
					Data:    []uint32{1},
				},
				{
					ID:      "hidden",
					Width:   1,
					Height:  1,
					Visible: false,
					Opacity: 1,
					Data:    []uint32{1},
				},
				{
					ID:      "malformed",
					Width:   2,
					Height:  2,
					Visible: true,
					Opacity: 1,
					Data:    []uint32{1},
				},
			},
		},
	}
	if got := tileDrawCommands(view); len(got) != 0 {
		t.Fatalf("culled tile commands = %#v", got)
	}
}

func TestPackagedAssetPathRejectsTraversalAndHostPaths(t *testing.T) {
	t.Parallel()

	got, err := packagedAssetPath(
		"assets/runtime/images/tilesets/world.png",
	)
	if err != nil || got != "images/tilesets/world.png" {
		t.Fatalf("packaged asset path = %q, %v", got, err)
	}
	for _, invalid := range []string{
		"",
		"/assets/runtime/world.png",
		"assets/runtime/../secret.png",
		"assets/runtime\\world.png",
		"images/world.png",
		"assets/runtime/",
	} {
		if _, err := packagedAssetPath(invalid); err == nil {
			t.Fatalf("unsafe packaged asset path %q was accepted", invalid)
		}
	}
}

func TestCaptureRequestsArrivingDuringDrawWaitForNextFrame(t *testing.T) {
	t.Parallel()
	game := &Game{capture: make(chan captureRequest, 2)}
	first := captureRequest{result: make(chan captureResult, 1)}
	second := captureRequest{result: make(chan captureResult, 1)}

	game.capture <- first
	currentFrame := game.beginCaptures()
	if len(currentFrame) != 1 {
		t.Fatalf("current frame captures = %d, want 1", len(currentFrame))
	}
	game.capture <- second
	if got := len(currentFrame); got != 1 {
		t.Fatalf("mid-draw request changed current batch to %d", got)
	}
	nextFrame := game.beginCaptures()
	if len(nextFrame) != 1 {
		t.Fatalf("next frame captures = %d, want 1", len(nextFrame))
	}
}

func TestWallPolygonScreenPointsUsesExactVerticesAndCameraTransform(
	t *testing.T,
) {
	t.Parallel()
	view := View{
		Camera: CameraView{
			X:      100,
			Y:      50,
			ShakeX: -3,
			ShakeY: 4,
			Zoom:   2,
		},
	}
	wall := RectView{
		// Deliberately unrelated bounds prove the polygon path does not render
		// the broad-phase rectangle.
		X:      -1000,
		Y:      -1000,
		Width:  2000,
		Height: 2000,
		Points: []PointView{
			{X: 110, Y: 60},
			{X: 125, Y: 64},
			{X: 118, Y: 80},
		},
	}
	got := wallPolygonScreenPoints(view, wall)
	want := []PointView{
		{X: 14, Y: 28},
		{X: 44, Y: 36},
		{X: 30, Y: 68},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("screen polygon = %#v, want %#v", got, want)
	}
	got[0].X = -999
	if wall.Points[0].X != 110 {
		t.Fatal("screen polygon aliases the immutable world-coordinate view")
	}
	if points := wallPolygonScreenPoints(view, RectView{}); points != nil {
		t.Fatalf("rectangle produced polygon points: %#v", points)
	}
}

func TestLayoutDialogueClampsSelectionAndKeepsEligibleOrder(
	t *testing.T,
) {
	t.Parallel()

	choices := []DialogueChoiceView{
		{ID: "a", Text: "Alpha"},
		{ID: "b", Text: "Bravo"},
		{ID: "c", Text: "Charlie"},
		{ID: "d", Text: "Delta"},
		{ID: "e"},
	}
	layout := layoutDialogue(DialogueView{
		Active:        true,
		Text:          "Choose one.",
		Choices:       choices,
		SelectedIndex: 99,
	})
	if layout.Selected != 4 || !layout.HasEarlier || layout.HasLater {
		t.Fatalf("selection/window flags = %#v", layout)
	}
	want := []dialogueChoiceLayout{
		{Index: 2, ID: "c", Text: "Charlie"},
		{Index: 3, ID: "d", Text: "Delta"},
		{Index: 4, ID: "e", Text: "e", Selected: true},
	}
	if !reflect.DeepEqual(layout.Choices, want) {
		t.Fatalf("visible choices = %#v, want %#v", layout.Choices, want)
	}

	first := layoutDialogue(DialogueView{
		Choices:       choices,
		SelectedIndex: -4,
	})
	if first.Selected != 0 || first.HasEarlier || !first.HasLater ||
		len(first.Choices) != maxVisibleDialogueChoices ||
		!first.Choices[0].Selected {
		t.Fatalf("negative selection layout = %#v", first)
	}
}

func TestLayoutDialogueWithoutChoicesHasNoSelection(t *testing.T) {
	t.Parallel()

	layout := layoutDialogue(DialogueView{Text: "Continue."})
	if layout.Selected != -1 || len(layout.Choices) != 0 {
		t.Fatalf("choice-free layout = %#v", layout)
	}
}

func TestWrapTextHonorsRunesExplicitLinesAndEllipsis(
	t *testing.T,
) {
	t.Parallel()

	got := wrapText(
		"alpha beta gamma\n가나다라마바사아자차카타파하",
		10,
		3,
	)
	want := []string{"alpha beta", "gamma", "가나다라마바사아자…"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("wrapped dialogue = %#v, want %#v", got, want)
	}
	for _, line := range got {
		if utf8.RuneCountInString(line) > 10 {
			t.Fatalf("wrapped line exceeds rune budget: %q", line)
		}
	}
	if lines := wrapText("  \r\n ", 10, 2); lines != nil {
		t.Fatalf("blank dialogue produced lines: %#v", lines)
	}
}

func TestEllipsizeTextBoundsLongLabels(t *testing.T) {
	t.Parallel()

	got := ellipsizeText("가나다라마바사", 5)
	if got != "가나다라…" || utf8.RuneCountInString(got) != 5 {
		t.Fatalf("ellipsized label = %q", got)
	}
	if got := ellipsizeText(" short ", 10); got != "short" {
		t.Fatalf("short label = %q", got)
	}
	if got := ellipsizeText("long", 1); got != "…" {
		t.Fatalf("single-rune label = %q", got)
	}
}

func TestDialogueBoxDoesNotCoverAutomationOverlay(t *testing.T) {
	t.Parallel()

	const automationOverlayBottom = ScreenHeight/2 + 54
	if dialogueBoxY < automationOverlayBottom {
		t.Fatalf(
			"dialogue box y=%d overlaps automation overlay bottom=%d",
			dialogueBoxY,
			automationOverlayBottom,
		)
	}
	if dialogueBoxY+dialogueBoxHeight > ScreenHeight {
		t.Fatalf(
			"dialogue box bottom=%d exceeds screen height=%d",
			dialogueBoxY+dialogueBoxHeight,
			ScreenHeight,
		)
	}
	if dialogueChoiceHelp !=
		"↑ / ↓  선택    Enter / E  확인    Esc  취소" {
		t.Fatalf("dialogue choice help = %q", dialogueChoiceHelp)
	}
}

func TestLayoutShopClampsSelectionAndKeepsAuthoredOrder(
	t *testing.T,
) {
	t.Parallel()

	longName := strings.Repeat("긴", maxShopOfferNameRunes+5)
	offers := []ShopOfferView{
		{ID: "a", Name: "Alpha"},
		{ID: "b"},
		{
			ID:              "c",
			Name:            longName,
			ModifierSummary: strings.Repeat("M", 30),
			Owned:           7,
			CanBuy:          true,
			BuyPrice:        25,
			CanSell:         true,
			SellPrice:       10,
		},
		{ID: "d", Name: "Delta"},
		{},
	}
	layout := layoutShop(ShopView{
		Name:          strings.Repeat("상", maxShopNameRunes+4),
		Offers:        offers,
		SelectedIndex: 99,
		Status:        strings.Repeat("완", maxShopStatusRunes+8),
	})
	if layout.Selected != 4 || !layout.HasEarlier || layout.HasLater {
		t.Fatalf("shop selection/window flags = %#v", layout)
	}
	if len(layout.Offers) != maxVisibleShopOffers {
		t.Fatalf("visible shop offers = %d", len(layout.Offers))
	}
	for offset, wantIndex := range []int{2, 3, 4} {
		if layout.Offers[offset].Index != wantIndex {
			t.Fatalf(
				"visible shop offer %d index = %d, want %d",
				offset,
				layout.Offers[offset].Index,
				wantIndex,
			)
		}
	}
	first := layout.Offers[0]
	if first.ID != "c" || first.Owned != 7 ||
		!first.CanBuy || first.BuyPrice != 25 ||
		!first.CanSell || first.SellPrice != 10 ||
		utf8.RuneCountInString(first.ModifierSummary) > 22 ||
		!strings.HasSuffix(first.ModifierSummary, "…") {
		t.Fatalf("shop offer facts were lost: %#v", first)
	}
	if utf8.RuneCountInString(first.Name) > maxShopOfferNameRunes ||
		!strings.HasSuffix(first.Name, "…") {
		t.Fatalf("long offer name was not bounded: %q", first.Name)
	}
	if layout.Offers[2].Name != shopFallbackOfferName ||
		!layout.Offers[2].Selected {
		t.Fatalf("blank selected offer layout = %#v", layout.Offers[2])
	}
	if utf8.RuneCountInString(layout.Name) > maxShopNameRunes ||
		utf8.RuneCountInString(layout.Status) > maxShopStatusRunes {
		t.Fatalf("shop header/status exceeds bounds: %#v", layout)
	}

	firstWindow := layoutShop(ShopView{
		Offers:        offers,
		SelectedIndex: -8,
	})
	if firstWindow.Selected != 0 ||
		firstWindow.HasEarlier ||
		!firstWindow.HasLater ||
		!firstWindow.Offers[0].Selected ||
		firstWindow.Offers[1].Name != "b" {
		t.Fatalf("negative shop selection layout = %#v", firstWindow)
	}
}

func TestLayoutShopDefendsEmptyOffersAndNames(t *testing.T) {
	t.Parallel()

	layout := layoutShop(ShopView{
		Name:          " ",
		Offers:        nil,
		SelectedIndex: 123,
		Status:        " ",
	})
	if layout.Name != shopFallbackName ||
		layout.Status != "" ||
		layout.Selected != -1 ||
		len(layout.Offers) != 0 ||
		layout.HasEarlier ||
		layout.HasLater {
		t.Fatalf("empty shop layout = %#v", layout)
	}
}

func TestShopPriceTextHonorsAvailability(t *testing.T) {
	t.Parallel()

	if got := shopPriceText(true, 25); got != "25 G" {
		t.Fatalf("available shop price = %q", got)
	}
	if got := shopPriceText(false, 999); got != "—" {
		t.Fatalf("unavailable shop price = %q", got)
	}
}

func TestShopPanelFitsBelowAutomationOverlay(t *testing.T) {
	t.Parallel()

	const automationOverlayBottom = ScreenHeight/2 + 54
	if shopPanelY < automationOverlayBottom {
		t.Fatalf(
			"shop panel y=%d overlaps automation overlay bottom=%d",
			shopPanelY,
			automationOverlayBottom,
		)
	}
	if shopPanelY+shopPanelHeight > ScreenHeight {
		t.Fatalf(
			"shop panel bottom=%d exceeds screen height=%d",
			shopPanelY+shopPanelHeight,
			ScreenHeight,
		)
	}
	if shopActionHelp !=
		"↑ / ↓  선택    Enter / E  구매    Q  판매    Esc  닫기" {
		t.Fatalf("shop action help = %q", shopActionHelp)
	}
}

func TestLayoutInventoryBoundsLongKoreanAndKeepsItemFacts(
	t *testing.T,
) {
	t.Parallel()

	items := []InventoryItemView{
		{ID: "zero", Name: "Zero", Quantity: 1},
		{ID: "one", Name: "One", Quantity: 1},
		{ID: "two", Name: "Two", Quantity: 2},
		{ID: "three", Name: "Three", Quantity: 3},
		{ID: "four", Name: "Four", Quantity: 4},
		{ID: "empty", Name: "Empty", Quantity: 0},
		{
			ID:            "item.long",
			Name:          strings.Repeat("긴", maxInventoryItemNameRunes+8),
			Description:   strings.Repeat("설", maxInventoryDescriptionRunes*6),
			Quantity:      7,
			Consumable:    true,
			EquipmentSlot: strings.Repeat("장", maxInventorySlotRunes+6),
			Equipped:      true,
			CanUse:        true,
			CanEquip:      true,
		},
		{Quantity: -3},
	}
	layout := layoutInventory(InventoryView{
		Title:         strings.Repeat("소", maxInventoryTitleRunes+7),
		Items:         items,
		SelectedIndex: 6,
		Status:        strings.Repeat("상", maxInventoryStatusRunes*3),
	})
	if layout.Selected != 6 ||
		!layout.HasEarlier ||
		!layout.HasLater ||
		len(layout.Items) != maxVisibleInventoryItems ||
		!layout.HasDetail {
		t.Fatalf("inventory selection/window = %#v", layout)
	}
	for offset, wantIndex := range []int{1, 2, 3, 4, 5, 6} {
		if layout.Items[offset].Index != wantIndex {
			t.Fatalf(
				"visible inventory item %d index = %d, want %d",
				offset,
				layout.Items[offset].Index,
				wantIndex,
			)
		}
	}
	detail := layout.Detail
	if detail.ID != "item.long" ||
		detail.Quantity != 7 ||
		!detail.Consumable ||
		!detail.Equipped ||
		!detail.CanUse ||
		!detail.CanEquip ||
		!detail.Selected {
		t.Fatalf("inventory item facts were lost: %#v", detail)
	}
	if utf8.RuneCountInString(detail.Name) > maxInventoryItemNameRunes ||
		!strings.HasSuffix(detail.Name, "…") ||
		utf8.RuneCountInString(detail.EquipmentSlot) >
			maxInventorySlotRunes ||
		!strings.HasSuffix(detail.EquipmentSlot, "…") {
		t.Fatalf("inventory name/slot was not bounded: %#v", detail)
	}
	if len(detail.Description) != maxInventoryDescriptionLines ||
		!strings.HasSuffix(
			detail.Description[len(detail.Description)-1],
			"…",
		) {
		t.Fatalf("inventory description was not bounded: %#v", detail)
	}
	for _, line := range detail.Description {
		if utf8.RuneCountInString(line) >
			maxInventoryDescriptionRunes {
			t.Fatalf("inventory description exceeds bounds: %q", line)
		}
	}
	if utf8.RuneCountInString(layout.Title) >
		maxInventoryTitleRunes ||
		!strings.HasSuffix(layout.Title, "…") {
		t.Fatalf("inventory title was not bounded: %q", layout.Title)
	}
	if len(layout.Status) != maxInventoryStatusLines ||
		!strings.HasSuffix(layout.Status[len(layout.Status)-1], "…") {
		t.Fatalf("inventory status was not bounded: %#v", layout.Status)
	}
	if layout.Items[4].Quantity != 0 {
		t.Fatalf("zero quantity changed: %#v", layout.Items[4])
	}

	last := layoutInventory(InventoryView{
		Items:         items,
		SelectedIndex: 99,
	})
	if last.Selected != 7 ||
		!last.HasEarlier ||
		last.HasLater ||
		!last.HasDetail ||
		last.Detail.Name != inventoryFallbackItemName ||
		last.Detail.Quantity != 0 ||
		!reflect.DeepEqual(
			last.Detail.Description,
			[]string{inventoryEmptyDescription},
		) {
		t.Fatalf("invalid inventory selection layout = %#v", last)
	}
}

func TestLayoutInventoryDefendsEmptyItemsAndInvalidSelection(
	t *testing.T,
) {
	t.Parallel()

	layout := layoutInventory(InventoryView{
		Title:         " ",
		SelectedIndex: -100,
		Status:        " ",
	})
	if layout.Title != inventoryFallbackTitle ||
		layout.Selected != -1 ||
		len(layout.Items) != 0 ||
		len(layout.Status) != 0 ||
		layout.HasDetail ||
		layout.HasEarlier ||
		layout.HasLater {
		t.Fatalf("empty inventory layout = %#v", layout)
	}
}

func TestInventoryDetailLabelsAndPanelFitScreen(t *testing.T) {
	t.Parallel()

	equipment := inventoryItemLayout{
		Quantity:        1,
		EquipmentSlot:   "weapon",
		ModifierSummary: "ATK +5",
		Equipped:        true,
		CanEquip:        true,
	}
	if kind := inventoryKindText(equipment); !strings.Contains(kind, inventoryEquipmentLabel) ||
		!strings.Contains(kind, "weapon") ||
		!strings.Contains(kind, "ATK +5") ||
		!strings.Contains(kind, "장착 중") {
		t.Fatalf("inventory kind = %q", kind)
	}
	if availability := inventoryAvailabilityText(equipment); !strings.Contains(availability, "장착 가능") ||
		!strings.Contains(availability, "장착 해제") {
		t.Fatalf("inventory availability = %q", availability)
	}
	if got := inventoryAvailabilityText(
		inventoryItemLayout{CanUse: true},
	); got != "보유 수량 없음" {
		t.Fatalf("zero quantity availability = %q", got)
	}
	if inventoryPanelX < 0 ||
		inventoryPanelY < 0 ||
		inventoryPanelX+inventoryPanelWidth > ScreenWidth ||
		inventoryPanelY+inventoryPanelHeight > ScreenHeight {
		t.Fatalf(
			"inventory panel (%d,%d %dx%d) exceeds %dx%d screen",
			inventoryPanelX,
			inventoryPanelY,
			inventoryPanelWidth,
			inventoryPanelHeight,
			ScreenWidth,
			ScreenHeight,
		)
	}
	const hudBottom = 118
	if inventoryPanelY < hudBottom {
		t.Fatalf(
			"inventory panel y=%d overlaps HUD bottom=%d",
			inventoryPanelY,
			hudBottom,
		)
	}
	if inventoryActionHelp !=
		"↑ / ↓  선택    Enter / E  사용·장착    Q  해제    Esc / I  닫기" {
		t.Fatalf("inventory action help = %q", inventoryActionHelp)
	}
}

func TestHUDCurrencyUsesInt64(t *testing.T) {
	t.Parallel()

	if kind := reflect.TypeOf(HUDView{}.Currency).Kind(); kind != reflect.Int64 {
		t.Fatalf("HUD currency kind = %s, want int64", kind)
	}
	const currency int64 = 1<<53 - 1
	if got := (HUDView{Currency: currency}).Currency; got != currency {
		t.Fatalf("HUD currency = %d, want %d", got, currency)
	}
}

func TestLayoutFlowNormalizesModeSelectionAndLongKorean(
	t *testing.T,
) {
	t.Parallel()

	options := []FlowOptionView{
		{ID: "zero", Label: "잠김", Enabled: false},
		{ID: "one", Label: "계속", Enabled: true},
		{
			ID:      "two",
			Label:   strings.Repeat("비", maxFlowOptionRunes+9),
			Enabled: false,
		},
		{ID: "three", Label: "설정", Enabled: true},
		{ID: "four"},
		{ID: "five", Label: "타이틀로", Enabled: true},
		{Enabled: true},
	}
	layout := layoutFlow(FlowView{
		Mode:          " PAUSED ",
		Heading:       strings.Repeat("제", maxFlowHeadingRunes+6),
		Message:       strings.Repeat("한", maxFlowMessageRunes*5),
		Options:       options,
		SelectedIndex: 99,
	})
	if layout.Mode != "paused" ||
		layout.Selected != 6 ||
		!layout.HasEarlier ||
		layout.HasLater {
		t.Fatalf("flow mode/selection/window = %#v", layout)
	}
	if len(layout.Options) != maxVisibleFlowOptions {
		t.Fatalf("visible flow options = %d", len(layout.Options))
	}
	for offset, wantIndex := range []int{2, 3, 4, 5, 6} {
		if layout.Options[offset].Index != wantIndex {
			t.Fatalf(
				"visible flow option %d index = %d, want %d",
				offset,
				layout.Options[offset].Index,
				wantIndex,
			)
		}
	}
	disabled := layout.Options[0]
	if disabled.Enabled ||
		disabled.Selected ||
		!strings.HasSuffix(disabled.Label, flowDisabledIndicator) ||
		utf8.RuneCountInString(disabled.Label) > maxFlowOptionRunes {
		t.Fatalf("disabled flow option layout = %#v", disabled)
	}
	selected := layout.Options[len(layout.Options)-1]
	if !selected.Enabled ||
		!selected.Selected ||
		selected.Label != flowFallbackOption {
		t.Fatalf("blank selected flow option layout = %#v", selected)
	}
	if utf8.RuneCountInString(layout.Heading) > maxFlowHeadingRunes ||
		!strings.HasSuffix(layout.Heading, "…") {
		t.Fatalf("flow heading was not bounded: %q", layout.Heading)
	}
	if len(layout.Message) != maxFlowMessageLines ||
		!strings.HasSuffix(layout.Message[len(layout.Message)-1], "…") {
		t.Fatalf("flow message was not bounded: %#v", layout.Message)
	}
	for _, line := range layout.Message {
		if utf8.RuneCountInString(line) > maxFlowMessageRunes {
			t.Fatalf("flow message line exceeds bounds: %q", line)
		}
	}
}

func TestLayoutFlowDefendsDisabledAndEmptyOptions(t *testing.T) {
	t.Parallel()

	disabled := layoutFlow(FlowView{
		Mode: "gameover",
		Options: []FlowOptionView{
			{ID: "retry", Label: "다시 하기"},
			{},
		},
		SelectedIndex: -100,
	})
	if disabled.Selected != -1 ||
		len(disabled.Options) != 2 ||
		disabled.Options[0].Selected ||
		disabled.Options[1].Selected {
		t.Fatalf("all-disabled flow layout = %#v", disabled)
	}
	if disabled.Heading != flowGameOverHeading {
		t.Fatalf("game-over fallback heading = %q", disabled.Heading)
	}

	empty := layoutFlow(FlowView{
		Mode:          "ending",
		SelectedIndex: 100,
	})
	if empty.Selected != -1 ||
		len(empty.Options) != 0 ||
		empty.HasEarlier ||
		empty.HasLater ||
		empty.Heading != flowEndingHeading {
		t.Fatalf("empty flow layout = %#v", empty)
	}
}

func TestFlowModePalettesAndPanelFitScreen(t *testing.T) {
	t.Parallel()

	pause := paletteForFlow("paused")
	title := paletteForFlow("title")
	gameOver := paletteForFlow("gameover")
	ending := paletteForFlow("ending")
	if pause.Backdrop.A >= title.Backdrop.A {
		t.Fatalf(
			"pause backdrop alpha=%d is not translucent against title=%d",
			pause.Backdrop.A,
			title.Backdrop.A,
		)
	}
	if gameOver.Heading == title.Heading ||
		ending.Heading == title.Heading {
		t.Fatalf(
			"flow mode palettes are not distinct: title=%#v gameover=%#v ending=%#v",
			title,
			gameOver,
			ending,
		)
	}
	if flowPanelX < 0 ||
		flowPanelY < 0 ||
		flowPanelX+flowPanelWidth > ScreenWidth ||
		flowPanelY+flowPanelHeight > ScreenHeight {
		t.Fatalf(
			"flow panel (%d,%d %dx%d) exceeds %dx%d screen",
			flowPanelX,
			flowPanelY,
			flowPanelWidth,
			flowPanelHeight,
			ScreenWidth,
			ScreenHeight,
		)
	}
	if flowActionHelp !=
		"↑ / ↓  선택    Enter / E  확인    Esc  뒤로" {
		t.Fatalf("flow action help = %q", flowActionHelp)
	}
}
