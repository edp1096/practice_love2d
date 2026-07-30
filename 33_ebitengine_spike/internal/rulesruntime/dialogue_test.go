package rulesruntime

import (
	"reflect"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

func TestVillageGuideDialogueRunsCompleteCampaignBranches(t *testing.T) {
	t.Parallel()

	executor, live, _ := newCompleteRuntime(t)

	inactive, result, err := executor.StartDialogue(
		live,
		"dialogue.village_guide",
	)
	if err != nil {
		t.Fatal(err)
	}
	assertNoIntents(t, result)
	view := requireDialogueView(t, inactive)
	if view.DialogueID != "dialogue.village_guide" ||
		view.Name != "" ||
		view.NameKey != "dialogue.village_guide.name" ||
		view.NodeID != "greeting" ||
		view.Speaker != "" ||
		view.SpeakerKey != "npc.village_guide.name" ||
		view.Text != "" ||
		view.TextKey != "dialogue.village_guide.greeting" {
		t.Fatalf("inactive greeting view = %#v", view)
	}
	assertDialogueChoices(t, view, "accept", "leave")
	if view.Choices[0].Text != "" ||
		view.Choices[0].TextKey != "dialogue.village_guide.accept" {
		t.Fatalf("accept choice text = %#v", view.Choices[0])
	}

	result, err = inactive.Choose("accept")
	if err != nil {
		t.Fatal(err)
	}
	assertNoticeIntent(t, result, "notice.quest.accepted", "success", 240)
	state := live.Snapshot()
	assertQuestStatus(
		t,
		state,
		"quest.grove_guardian",
		campaign.QuestActive,
	)
	assertInventory(t, state, "item.training_sword", 1)
	assertEquipment(t, state, "weapon", "item.training_sword")
	if state.Currency != 25 {
		t.Fatalf("starting currency = %d, want 25", state.Currency)
	}
	view = requireDialogueView(t, inactive)
	if view.NodeID != "accepted" ||
		view.TextKey != "dialogue.village_guide.accepted" ||
		len(view.Choices) != 0 {
		t.Fatalf("accepted view = %#v", view)
	}
	result, err = inactive.Advance()
	if err != nil {
		t.Fatal(err)
	}
	assertNoIntents(t, result)
	if !inactive.Closed() {
		t.Fatal("accepted terminal node did not close")
	}

	active, _, err := executor.StartDialogue(
		live,
		"dialogue.village_guide",
	)
	if err != nil {
		t.Fatal(err)
	}
	view = requireDialogueView(t, active)
	assertDialogueChoices(t, view, "progress", "leave")
	if _, err := active.Choose("progress"); err != nil {
		t.Fatal(err)
	}
	view = requireDialogueView(t, active)
	if view.NodeID != "reminder" ||
		view.TextKey != "dialogue.village_guide.reminder" {
		t.Fatalf("reminder view = %#v", view)
	}
	if _, err := active.Advance(); err != nil {
		t.Fatal(err)
	}

	progressSlimes(t, executor, live)
	if _, err := executor.ApplyObjectiveEvent(live, ObjectiveEvent{
		Event:   "actor.killed",
		ActorID: "actor.grove_guardian",
		Count:   1,
	}); err != nil {
		t.Fatal(err)
	}
	completed, _, err := executor.StartDialogue(
		live,
		"dialogue.village_guide",
	)
	if err != nil {
		t.Fatal(err)
	}
	view = requireDialogueView(t, completed)
	assertDialogueChoices(t, view, "completed", "leave")

	result, err = completed.Choose("completed")
	if err != nil {
		t.Fatal(err)
	}
	assertNoIntents(t, result)
	state = live.Snapshot()
	if !state.Flow.Completed || state.Mode != campaign.ModeEnding {
		t.Fatalf(
			"thanks entry flow = %#v, mode = %q",
			state.Flow,
			state.Mode,
		)
	}
	view = requireDialogueView(t, completed)
	if view.NodeID != "thanks" ||
		view.TextKey != "dialogue.village_guide.thanks" ||
		len(view.Choices) != 0 {
		t.Fatalf("thanks view = %#v", view)
	}

	// Re-rendering the node cannot execute finish_game a second time.
	beforeClose := live.Snapshot()
	_ = requireDialogueView(t, completed)
	if afterView := live.Snapshot(); !reflect.DeepEqual(afterView, beforeClose) {
		t.Fatal("view re-executed thanks node actions")
	}
	if _, err := completed.Advance(); err != nil {
		t.Fatal(err)
	}
	if !completed.Closed() {
		t.Fatal("thanks terminal node did not close")
	}
	failed, err := completed.Advance()
	if err == nil || !strings.Contains(err.Error(), "closed") {
		t.Fatalf("second terminal advance error = %v", err)
	}
	if !reflect.DeepEqual(failed, ActionResult{}) {
		t.Fatalf("closed advance leaked result: %#v", failed)
	}
	if afterClose := live.Snapshot(); !reflect.DeepEqual(afterClose, beforeClose) {
		t.Fatal("closing or re-advancing thanks changed campaign")
	}
}

func TestDialogueNodeActionsExecuteOnceAndExposeLiteralText(t *testing.T) {
	t.Parallel()

	config, rules := completeDefinitions(t)
	dialogue := mutableDialogue(t, &rules, "dialogue.village_guide")
	greeting := mutableDialogueNode(t, dialogue, "greeting")
	greeting.Speaker = "Village Guide"
	greeting.SpeakerKey = ""
	greeting.Text = "The grove needs help."
	greeting.TextKey = ""
	greeting.Actions = []gamebuild.RuleAction{{
		Type:     gamebuild.RuleActionAddCurrency,
		Currency: 3,
	}}
	accepted := mutableDialogueNode(t, dialogue, "accepted")
	accepted.Actions = []gamebuild.RuleAction{{
		Type:     gamebuild.RuleActionAddCurrency,
		Currency: 2,
	}}
	executor, live := newRuntimeWithRules(t, config, rules)

	session, result, err := executor.StartDialogue(
		live,
		"dialogue.village_guide",
	)
	if err != nil {
		t.Fatal(err)
	}
	assertNoIntents(t, result)
	if got := live.Snapshot().Currency; got != 3 {
		t.Fatalf("start-node currency = %d, want 3", got)
	}
	for range 3 {
		view := requireDialogueView(t, session)
		if view.Speaker != "Village Guide" ||
			view.SpeakerKey != "" ||
			view.Text != "The grove needs help." ||
			view.TextKey != "" {
			t.Fatalf("literal text view = %#v", view)
		}
	}
	if got := live.Snapshot().Currency; got != 3 {
		t.Fatalf("View re-executed start actions: currency = %d", got)
	}

	if _, err := session.Choose("accept"); err != nil {
		t.Fatal(err)
	}
	if got := live.Snapshot().Currency; got != 30 {
		// 3 start + 25 authored accept + 2 accepted-node entry.
		t.Fatalf("currency after accepted entry = %d, want 30", got)
	}
	for range 3 {
		view := requireDialogueView(t, session)
		if view.NodeID != "accepted" {
			t.Fatalf("current node = %q, want accepted", view.NodeID)
		}
	}
	if got := live.Snapshot().Currency; got != 30 {
		t.Fatalf("View re-executed target actions: currency = %d", got)
	}
}

func TestDialogueChoiceAndTargetActionsRollBackTogether(t *testing.T) {
	t.Parallel()

	config, rules := completeDefinitions(t)
	dialogue := mutableDialogue(t, &rules, "dialogue.village_guide")
	accepted := mutableDialogueNode(t, dialogue, "accepted")
	accepted.Actions = []gamebuild.RuleAction{
		{
			Type:   gamebuild.RuleActionOpenShop,
			ShopID: "shop.village",
		},
		{
			Type:     gamebuild.RuleActionGiveItem,
			ItemID:   "item.potion",
			Quantity: 11,
		},
	}
	executor, live := newRuntimeWithRules(t, config, rules)
	session, _, err := executor.StartDialogue(
		live,
		"dialogue.village_guide",
	)
	if err != nil {
		t.Fatal(err)
	}
	before := live.Snapshot()

	result, err := session.Choose("accept")
	if err == nil || !strings.Contains(err.Error(), "stack limit") {
		t.Fatalf("Choose() error = %v, want stack limit", err)
	}
	if !reflect.DeepEqual(result, ActionResult{}) {
		t.Fatalf("failed choice leaked intent: %#v", result)
	}
	if after := live.Snapshot(); !reflect.DeepEqual(after, before) {
		t.Fatalf(
			"failed choice did not roll back campaign\nbefore=%#v\nafter=%#v",
			before,
			after,
		)
	}
	view := requireDialogueView(t, session)
	if view.NodeID != "greeting" {
		t.Fatalf("failed choice moved session to %q", view.NodeID)
	}
	assertDialogueChoices(t, view, "accept", "leave")
}

func TestDialogueStartFailureReturnsNoSessionOrIntent(t *testing.T) {
	t.Parallel()

	config, rules := completeDefinitions(t)
	dialogue := mutableDialogue(t, &rules, "dialogue.village_guide")
	greeting := mutableDialogueNode(t, dialogue, "greeting")
	greeting.Actions = []gamebuild.RuleAction{
		{
			Type:   gamebuild.RuleActionOpenShop,
			ShopID: "shop.village",
		},
		{
			Type:     gamebuild.RuleActionGiveItem,
			ItemID:   "item.potion",
			Quantity: 11,
		},
	}
	executor, live := newRuntimeWithRules(t, config, rules)
	before := live.Snapshot()

	session, result, err := executor.StartDialogue(
		live,
		"dialogue.village_guide",
	)
	if err == nil || !strings.Contains(err.Error(), "stack limit") {
		t.Fatalf("StartDialogue() error = %v, want stack limit", err)
	}
	if session != nil {
		t.Fatalf("failed start returned session: %#v", session)
	}
	if !reflect.DeepEqual(result, ActionResult{}) {
		t.Fatalf("failed start leaked intent: %#v", result)
	}
	if after := live.Snapshot(); !reflect.DeepEqual(after, before) {
		t.Fatal("failed start mutated campaign")
	}
}

func TestDialogueAdvanceEntersNextNodeAfterAtomicActions(t *testing.T) {
	t.Parallel()

	config, rules := completeDefinitions(t)
	dialogue := mutableDialogue(t, &rules, "dialogue.village_guide")
	accepted := mutableDialogueNode(t, dialogue, "accepted")
	accepted.Next = "thanks"
	executor, live := newRuntimeWithRules(t, config, rules)
	session, _, err := executor.StartDialogue(
		live,
		"dialogue.village_guide",
	)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := session.Choose("accept"); err != nil {
		t.Fatal(err)
	}

	result, err := session.Advance()
	if err != nil {
		t.Fatal(err)
	}
	assertNoIntents(t, result)
	state := live.Snapshot()
	if !state.Flow.Completed || state.Mode != campaign.ModeEnding {
		t.Fatalf(
			"advanced node actions flow = %#v, mode = %q",
			state.Flow,
			state.Mode,
		)
	}
	view := requireDialogueView(t, session)
	if view.NodeID != "thanks" {
		t.Fatalf("advanced node = %q, want thanks", view.NodeID)
	}
}

func TestDialogueAdvanceFailureKeepsCampaignAndSession(t *testing.T) {
	t.Parallel()

	config, rules := completeDefinitions(t)
	dialogue := mutableDialogue(t, &rules, "dialogue.village_guide")
	accepted := mutableDialogueNode(t, dialogue, "accepted")
	accepted.Next = "reminder"
	reminder := mutableDialogueNode(t, dialogue, "reminder")
	reminder.Actions = []gamebuild.RuleAction{
		{
			Type:   gamebuild.RuleActionOpenShop,
			ShopID: "shop.village",
		},
		{
			Type:     gamebuild.RuleActionGiveItem,
			ItemID:   "item.potion",
			Quantity: 11,
		},
	}
	executor, live := newRuntimeWithRules(t, config, rules)
	session, _, err := executor.StartDialogue(
		live,
		"dialogue.village_guide",
	)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := session.Choose("accept"); err != nil {
		t.Fatal(err)
	}
	before := live.Snapshot()

	result, err := session.Advance()
	if err == nil || !strings.Contains(err.Error(), "stack limit") {
		t.Fatalf("Advance() error = %v, want stack limit", err)
	}
	if !reflect.DeepEqual(result, ActionResult{}) {
		t.Fatalf("failed advance leaked intent: %#v", result)
	}
	if after := live.Snapshot(); !reflect.DeepEqual(after, before) {
		t.Fatal("failed advance mutated campaign")
	}
	if view := requireDialogueView(t, session); view.NodeID != "accepted" {
		t.Fatalf("failed advance moved session to %q", view.NodeID)
	}
}

func TestDialogueChoiceWithoutNextRunsActionsThenCloses(t *testing.T) {
	t.Parallel()

	config, rules := completeDefinitions(t)
	dialogue := mutableDialogue(t, &rules, "dialogue.village_guide")
	greeting := mutableDialogueNode(t, dialogue, "greeting")
	for index := range greeting.Choices {
		if greeting.Choices[index].ID == "leave" {
			greeting.Choices[index].Actions = []gamebuild.RuleAction{{
				Type:     gamebuild.RuleActionAddCurrency,
				Currency: 4,
			}}
		}
	}
	executor, live := newRuntimeWithRules(t, config, rules)
	session, _, err := executor.StartDialogue(
		live,
		"dialogue.village_guide",
	)
	if err != nil {
		t.Fatal(err)
	}

	result, err := session.Choose("leave")
	if err != nil {
		t.Fatal(err)
	}
	assertNoIntents(t, result)
	if !session.Closed() {
		t.Fatal("choice without next did not close session")
	}
	if got := live.Snapshot().Currency; got != 4 {
		t.Fatalf("leave action currency = %d, want 4", got)
	}
}

func TestDialogueRejectsInvalidIneligibleStaleAndClosedCalls(t *testing.T) {
	t.Parallel()

	executor, live, _ := newCompleteRuntime(t)
	var nilExecutor *Executor
	if session, result, err := nilExecutor.StartDialogue(
		live,
		"dialogue.village_guide",
	); err == nil || session != nil ||
		!reflect.DeepEqual(result, ActionResult{}) {
		t.Fatalf("nil executor start = %#v, %#v, %v", session, result, err)
	}
	if session, result, err := executor.StartDialogue(
		nil,
		"dialogue.village_guide",
	); err == nil || session != nil ||
		!reflect.DeepEqual(result, ActionResult{}) {
		t.Fatalf("nil campaign start = %#v, %#v, %v", session, result, err)
	}
	if session, result, err := executor.StartDialogue(
		live,
		"dialogue.missing",
	); err == nil || session != nil ||
		!reflect.DeepEqual(result, ActionResult{}) {
		t.Fatalf("unknown dialogue start = %#v, %#v, %v", session, result, err)
	}

	var nilSession *DialogueSession
	if view, err := nilSession.View(); err == nil ||
		!reflect.DeepEqual(view, DialogueView{}) {
		t.Fatalf("nil session View = %#v, %v", view, err)
	}
	if result, err := nilSession.Choose("accept"); err == nil ||
		!reflect.DeepEqual(result, ActionResult{}) {
		t.Fatalf("nil session Choose = %#v, %v", result, err)
	}
	if result, err := nilSession.Advance(); err == nil ||
		!reflect.DeepEqual(result, ActionResult{}) {
		t.Fatalf("nil session Advance = %#v, %v", result, err)
	}
	invalid := &DialogueSession{}
	if _, err := invalid.View(); err == nil ||
		!strings.Contains(err.Error(), "invalid") {
		t.Fatalf("invalid session View error = %v", err)
	}

	session, _, err := executor.StartDialogue(
		live,
		"dialogue.village_guide",
	)
	if err != nil {
		t.Fatal(err)
	}
	before := live.Snapshot()
	for _, choiceID := range []string{"", "missing", "progress"} {
		result, err := session.Choose(choiceID)
		if err == nil {
			t.Fatalf("Choose(%q) unexpectedly succeeded", choiceID)
		}
		if !reflect.DeepEqual(result, ActionResult{}) {
			t.Fatalf("Choose(%q) leaked result: %#v", choiceID, result)
		}
		if after := live.Snapshot(); !reflect.DeepEqual(after, before) {
			t.Fatalf("Choose(%q) mutated campaign", choiceID)
		}
		if view := requireDialogueView(t, session); view.NodeID != "greeting" {
			t.Fatalf("Choose(%q) moved to %q", choiceID, view.NodeID)
		}
	}
	if result, err := session.Advance(); err == nil ||
		!reflect.DeepEqual(result, ActionResult{}) {
		t.Fatalf("choice-node Advance = %#v, %v", result, err)
	}

	if _, err := session.Choose("accept"); err != nil {
		t.Fatal(err)
	}
	// "leave" came from a stale greeting view and is invalid on accepted.
	if result, err := session.Choose("leave"); err == nil ||
		!reflect.DeepEqual(result, ActionResult{}) {
		t.Fatalf("stale choice = %#v, %v", result, err)
	}
	if _, err := session.Advance(); err != nil {
		t.Fatal(err)
	}
	if !session.Closed() {
		t.Fatal("session is not closed")
	}
	if view, err := session.View(); err == nil ||
		!reflect.DeepEqual(view, DialogueView{}) ||
		!strings.Contains(err.Error(), "closed") {
		t.Fatalf("closed View = %#v, %v", view, err)
	}
	if result, err := session.Choose("accept"); err == nil ||
		!reflect.DeepEqual(result, ActionResult{}) ||
		!strings.Contains(err.Error(), "closed") {
		t.Fatalf("closed Choose = %#v, %v", result, err)
	}
}

func TestConcurrentDialogueChoiceCommitsExactlyOnce(t *testing.T) {
	executor, live, _ := newCompleteRuntime(t)
	session, _, err := executor.StartDialogue(
		live,
		"dialogue.village_guide",
	)
	if err != nil {
		t.Fatal(err)
	}

	const workers = 32
	type outcome struct {
		result ActionResult
		err    error
	}
	outcomes := make(chan outcome, workers)
	start := make(chan struct{})
	var ready sync.WaitGroup
	var wait sync.WaitGroup
	ready.Add(workers)
	wait.Add(workers)
	for range workers {
		go func() {
			defer wait.Done()
			view, viewErr := session.View()
			if viewErr != nil {
				outcomes <- outcome{err: viewErr}
				ready.Done()
				return
			}
			if !slices.Equal(
				dialogueChoiceIDs(view),
				[]string{"accept", "leave"},
			) {
				outcomes <- outcome{err: &unexpectedDialogueViewError{
					view: view,
				}}
				ready.Done()
				return
			}
			ready.Done()
			<-start
			result, chooseErr := session.Choose("accept")
			outcomes <- outcome{result: result, err: chooseErr}
		}()
	}
	ready.Wait()
	close(start)
	wait.Wait()
	close(outcomes)

	successes := 0
	for outcome := range outcomes {
		if outcome.err == nil {
			successes++
			assertNoticeIntent(
				t,
				outcome.result,
				"notice.quest.accepted",
				"success",
				240,
			)
			continue
		}
		if !reflect.DeepEqual(outcome.result, ActionResult{}) {
			t.Fatalf("failed concurrent choice leaked result: %#v", outcome)
		}
	}
	if successes != 1 {
		t.Fatalf("successful choices = %d, want exactly 1", successes)
	}
	state := live.Snapshot()
	assertQuestStatus(
		t,
		state,
		"quest.grove_guardian",
		campaign.QuestActive,
	)
	assertInventory(t, state, "item.training_sword", 1)
	assertEquipment(t, state, "weapon", "item.training_sword")
	if state.Currency != 25 {
		t.Fatalf("currency = %d, want one authored grant of 25", state.Currency)
	}
	if view := requireDialogueView(t, session); view.NodeID != "accepted" {
		t.Fatalf("concurrent session node = %q, want accepted", view.NodeID)
	}
}

func TestDialogueConditionGuardSharesActionTransaction(t *testing.T) {
	executor, live, _ := newCompleteRuntime(t)
	guardEntered := make(chan struct{})
	releaseGuard := make(chan struct{})
	type executionOutcome struct {
		result ActionResult
		err    error
	}
	executionDone := make(chan executionOutcome, 1)
	go func() {
		result, err := executor.executeGuarded(
			live,
			[]gamebuild.RuleAction{{
				Type:     gamebuild.RuleActionAddCurrency,
				Currency: 9,
			}},
			func(state *campaign.State) error {
				quest, _, err := findQuestState(
					state,
					"quest.grove_guardian",
				)
				if err != nil {
					return err
				}
				if quest.Status != campaign.QuestInactive {
					return &unexpectedQuestStatusError{
						got:  quest.Status,
						want: campaign.QuestInactive,
					}
				}
				close(guardEntered)
				<-releaseGuard
				return nil
			},
		)
		executionDone <- executionOutcome{result: result, err: err}
	}()
	<-guardEntered

	// This transaction would invalidate the dialogue condition. Its callback
	// must not enter while the guarded action transaction is between condition
	// evaluation and action application.
	mutationEntered := make(chan struct{})
	mutationDone := make(chan error, 1)
	go func() {
		mutationDone <- live.Transaction(func(state *campaign.State) error {
			close(mutationEntered)
			quest, _, err := findQuestState(
				state,
				"quest.grove_guardian",
			)
			if err != nil {
				return err
			}
			quest.Status = campaign.QuestActive
			return nil
		})
	}()

	blocked := false
	select {
	case <-mutationEntered:
		// Clean up both goroutines before reporting the failed barrier.
	case <-time.After(100 * time.Millisecond):
		blocked = true
	}
	close(releaseGuard)
	execution := <-executionDone
	mutationErr := <-mutationDone
	if !blocked {
		t.Fatal(
			"campaign mutation entered between dialogue condition and actions",
		)
	}
	if execution.err != nil {
		t.Fatal(execution.err)
	}
	assertNoIntents(t, execution.result)
	if mutationErr != nil {
		t.Fatal(mutationErr)
	}
	state := live.Snapshot()
	assertQuestStatus(
		t,
		state,
		"quest.grove_guardian",
		campaign.QuestActive,
	)
	if state.Currency != 9 {
		t.Fatalf("guarded action currency = %d, want 9", state.Currency)
	}
}

func TestDialogueChoiceRejectsConditionChangedBeforeTransaction(t *testing.T) {
	t.Parallel()

	executor, live, _ := newCompleteRuntime(t)
	session, _, err := executor.StartDialogue(
		live,
		"dialogue.village_guide",
	)
	if err != nil {
		t.Fatal(err)
	}
	if err := live.Transaction(func(state *campaign.State) error {
		quest, _, err := findQuestState(state, "quest.grove_guardian")
		if err != nil {
			return err
		}
		quest.Status = campaign.QuestActive
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	before := live.Snapshot()

	result, err := session.Choose("accept")
	if err == nil || !strings.Contains(err.Error(), "not eligible") {
		t.Fatalf("changed condition error = %v", err)
	}
	if !reflect.DeepEqual(result, ActionResult{}) {
		t.Fatalf("changed condition leaked result: %#v", result)
	}
	if after := live.Snapshot(); !reflect.DeepEqual(after, before) {
		t.Fatal("changed condition choice mutated campaign")
	}
	if view := requireDialogueView(t, session); view.NodeID != "greeting" {
		t.Fatalf("changed condition moved session to %q", view.NodeID)
	}
}

type unexpectedDialogueViewError struct {
	view DialogueView
}

func (err *unexpectedDialogueViewError) Error() string {
	return "unexpected dialogue view"
}

type unexpectedQuestStatusError struct {
	got  campaign.QuestStatus
	want campaign.QuestStatus
}

func (err *unexpectedQuestStatusError) Error() string {
	return "unexpected quest status"
}

func requireDialogueView(
	t *testing.T,
	session *DialogueSession,
) DialogueView {
	t.Helper()
	view, err := session.View()
	if err != nil {
		t.Fatal(err)
	}
	return view
}

func assertDialogueChoices(
	t *testing.T,
	view DialogueView,
	want ...string,
) {
	t.Helper()
	if got := dialogueChoiceIDs(view); !slices.Equal(got, want) {
		t.Fatalf("choice ids = %q, want %q", got, want)
	}
}

func dialogueChoiceIDs(view DialogueView) []string {
	result := make([]string, len(view.Choices))
	for index, choice := range view.Choices {
		result[index] = choice.ID
	}
	return result
}

func assertNoIntents(t *testing.T, result ActionResult) {
	t.Helper()
	if result.Intents == nil || len(result.Intents) != 0 {
		t.Fatalf("intents = %#v, want non-nil empty slice", result.Intents)
	}
}

func assertNoticeIntent(
	t *testing.T,
	result ActionResult,
	key string,
	tone string,
	ticks int,
) {
	t.Helper()
	want := []Intent{{
		Type:        IntentShowNotice,
		NoticeKey:   key,
		NoticeTone:  tone,
		NoticeTicks: ticks,
	}}
	if !reflect.DeepEqual(result.Intents, want) {
		t.Fatalf("intents = %#v, want %#v", result.Intents, want)
	}
}

func mutableDialogue(
	t *testing.T,
	rules *gamebuild.ContentRules,
	dialogueID string,
) *gamebuild.DialogueRule {
	t.Helper()
	for index := range rules.Dialogues {
		if rules.Dialogues[index].ID == dialogueID {
			return &rules.Dialogues[index]
		}
	}
	t.Fatalf("dialogue %q not found", dialogueID)
	return nil
}

func mutableDialogueNode(
	t *testing.T,
	dialogue *gamebuild.DialogueRule,
	nodeID string,
) *gamebuild.DialogueNodeRule {
	t.Helper()
	for index := range dialogue.Nodes {
		if dialogue.Nodes[index].ID == nodeID {
			return &dialogue.Nodes[index]
		}
	}
	t.Fatalf("dialogue node %q not found", nodeID)
	return nil
}

func newRuntimeWithRules(
	t *testing.T,
	config campaign.Config,
	rules gamebuild.ContentRules,
) (*Executor, *campaign.Campaign) {
	t.Helper()
	executor, err := New(config, rules)
	if err != nil {
		t.Fatal(err)
	}
	live, err := campaign.NewGame(config)
	if err != nil {
		t.Fatal(err)
	}
	return executor, live
}
