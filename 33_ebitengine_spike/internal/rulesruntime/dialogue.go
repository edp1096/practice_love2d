package rulesruntime

import (
	"errors"
	"fmt"
	"sort"
	"sync"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

// DialogueChoiceView is the authored text of one currently eligible choice.
// Text contains literal source text, while TextKey is the locale lookup key.
type DialogueChoiceView struct {
	ID      string `json:"id"`
	Text    string `json:"text,omitempty"`
	TextKey string `json:"text_key,omitempty"`
}

// DialogueView is a transient presentation DTO for the current dialogue node.
// It is deliberately not part of campaign.State or the save envelope: loading
// a game reconstructs stage presentation and starts a new interaction instead
// of restoring an in-flight dialogue.
//
// Speaker and Text contain authored literal source text. SpeakerKey, TextKey,
// and each choice's TextKey retain the authored locale lookup keys so the host
// can localize without losing the original content representation.
type DialogueView struct {
	DialogueID string               `json:"dialogue_id"`
	Name       string               `json:"name,omitempty"`
	NameKey    string               `json:"name_key,omitempty"`
	NodeID     string               `json:"node_id"`
	Speaker    string               `json:"speaker,omitempty"`
	SpeakerKey string               `json:"speaker_key,omitempty"`
	Text       string               `json:"text,omitempty"`
	TextKey    string               `json:"text_key,omitempty"`
	Choices    []DialogueChoiceView `json:"choices"`
}

// DialogueSession owns only ephemeral interaction progress. Durable mutations
// always go through Executor.Execute and Campaign.Transaction; this session is
// intentionally never serialized or included in a player save.
//
// A session serializes View, Choose, and Advance. Node entry actions run before
// nodeID changes, so a failed action leaves both the campaign and this session
// on the previous node.
type DialogueSession struct {
	mu sync.Mutex

	executor *Executor
	live     *campaign.Campaign
	dialogue gamebuild.DialogueRule
	nodeID   string
	closed   bool
}

// CloneForCampaign copies the transient node cursor and binds it to a detached
// Campaign candidate. Hosts use this before a multi-part operation so both the
// durable mutations and the dialogue cursor can be discarded together if a
// later presentation intent fails.
func (session *DialogueSession) CloneForCampaign(
	live *campaign.Campaign,
) (*DialogueSession, error) {
	if session == nil {
		return nil, errors.New("clone dialogue: session is nil")
	}
	if live == nil {
		return nil, errors.New("clone dialogue: campaign is nil")
	}
	session.mu.Lock()
	defer session.mu.Unlock()
	if err := session.requireValid("clone dialogue"); err != nil {
		return nil, err
	}
	sourceState := session.live.Snapshot()
	if err := session.executor.requireIdentity(&sourceState); err != nil {
		return nil, fmt.Errorf("clone dialogue: source campaign: %w", err)
	}
	destinationState := live.Snapshot()
	if err := session.executor.requireIdentity(&destinationState); err != nil {
		return nil, fmt.Errorf("clone dialogue: destination campaign: %w", err)
	}
	return &DialogueSession{
		executor: session.executor,
		live:     live,
		dialogue: session.dialogue,
		nodeID:   session.nodeID,
		closed:   session.closed,
	}, nil
}

// StartDialogue enters a dialogue's authored start node. Its node actions are
// executed exactly once before the session becomes observable. On failure, no
// session or intent is returned and Executor.Execute rolls back the campaign.
func (executor *Executor) StartDialogue(
	live *campaign.Campaign,
	dialogueID string,
) (*DialogueSession, ActionResult, error) {
	if executor == nil {
		return nil, ActionResult{}, errors.New(
			"start dialogue: executor is nil",
		)
	}
	if live == nil {
		return nil, ActionResult{}, errors.New(
			"start dialogue: campaign is nil",
		)
	}
	if dialogueID == "" {
		return nil, ActionResult{}, errors.New(
			"start dialogue: dialogue id is empty",
		)
	}

	dialogue, exists := executor.rules.Dialogue(dialogueID)
	if !exists {
		return nil, ActionResult{}, fmt.Errorf(
			"start dialogue: dialogue %q is not configured",
			dialogueID,
		)
	}
	start, exists := findDialogueNode(dialogue, dialogue.StartNode)
	if !exists {
		// New validates this invariant. Keep the runtime boundary fail-closed in
		// case a future construction path bypasses that validation.
		return nil, ActionResult{}, fmt.Errorf(
			"start dialogue: dialogue %q start node %q is missing",
			dialogue.ID,
			dialogue.StartNode,
		)
	}

	result, err := executor.Execute(live, start.Actions)
	if err != nil {
		return nil, ActionResult{}, fmt.Errorf(
			"start dialogue %q: enter node %q: %w",
			dialogue.ID,
			start.ID,
			err,
		)
	}
	return &DialogueSession{
		executor: executor,
		live:     live,
		dialogue: dialogue,
		nodeID:   start.ID,
	}, result, nil
}

// View returns a detached snapshot of the current node and only the choices
// whose conditions match one atomic campaign snapshot. Authored choice order is
// retained after filtering. View never executes node actions.
func (session *DialogueSession) View() (DialogueView, error) {
	if session == nil {
		return DialogueView{}, errors.New(
			"view dialogue: session is nil",
		)
	}
	session.mu.Lock()
	defer session.mu.Unlock()

	if err := session.requireOpen("view dialogue"); err != nil {
		return DialogueView{}, err
	}
	node, err := session.currentNode("view dialogue")
	if err != nil {
		return DialogueView{}, err
	}
	state := session.live.Snapshot()
	if err := session.executor.requireIdentity(&state); err != nil {
		return DialogueView{}, fmt.Errorf("view dialogue: %w", err)
	}

	choices := make([]DialogueChoiceView, 0, len(node.Choices))
	for _, choice := range node.Choices {
		eligible, err := session.choiceEligible(&state, choice)
		if err != nil {
			return DialogueView{}, fmt.Errorf(
				"view dialogue: choice %q: %w",
				choice.ID,
				err,
			)
		}
		if !eligible {
			continue
		}
		choices = append(choices, DialogueChoiceView{
			ID:      choice.ID,
			Text:    choice.Text,
			TextKey: choice.TextKey,
		})
	}

	return DialogueView{
		DialogueID: session.dialogue.ID,
		Name:       session.dialogue.Name,
		NameKey:    session.dialogue.NameKey,
		NodeID:     node.ID,
		Speaker:    node.Speaker,
		SpeakerKey: node.SpeakerKey,
		Text:       node.Text,
		TextKey:    node.TextKey,
		Choices:    choices,
	}, nil
}

// Choose accepts only an eligible authored choice on the current node.
// Condition evaluation, choice actions, and destination-node entry actions use
// the same guarded transaction path as Executor.Execute. The session moves or
// closes only after that complete action list commits.
func (session *DialogueSession) Choose(
	choiceID string,
) (ActionResult, error) {
	if session == nil {
		return ActionResult{}, errors.New(
			"choose dialogue option: session is nil",
		)
	}
	session.mu.Lock()
	defer session.mu.Unlock()

	if err := session.requireOpen("choose dialogue option"); err != nil {
		return ActionResult{}, err
	}
	if choiceID == "" {
		return ActionResult{}, errors.New(
			"choose dialogue option: choice id is empty",
		)
	}
	node, err := session.currentNode("choose dialogue option")
	if err != nil {
		return ActionResult{}, err
	}

	choice, exists := findDialogueChoice(node, choiceID)
	if !exists {
		return ActionResult{}, fmt.Errorf(
			"choose dialogue option: choice %q is not on current node %q",
			choiceID,
			node.ID,
		)
	}
	actions := append(
		make([]gamebuild.RuleAction, 0, len(choice.Actions)),
		choice.Actions...,
	)
	nextNodeID := ""
	if choice.Next != "" {
		next, exists := findDialogueNode(session.dialogue, choice.Next)
		if !exists {
			return ActionResult{}, fmt.Errorf(
				"choose dialogue option: destination node %q is missing",
				choice.Next,
			)
		}
		nextNodeID = next.ID
		actions = append(actions, next.Actions...)
	}

	result, err := session.executor.executeGuarded(
		session.live,
		actions,
		func(state *campaign.State) error {
			eligible, err := session.choiceEligible(state, choice)
			if err != nil {
				return fmt.Errorf("choice %q: %w", choice.ID, err)
			}
			if !eligible {
				return fmt.Errorf(
					"choice %q is not eligible on node %q",
					choice.ID,
					node.ID,
				)
			}
			return nil
		},
	)
	if err != nil {
		return ActionResult{}, fmt.Errorf(
			"choose dialogue option %q: %w",
			choice.ID,
			err,
		)
	}
	if nextNodeID == "" {
		session.closed = true
		return result, nil
	}
	session.nodeID = nextNodeID
	return result, nil
}

// Advance progresses a node with no authored choices. A terminal node closes
// without another campaign mutation. Entering a next node executes that node's
// actions exactly once before the session moves.
func (session *DialogueSession) Advance() (ActionResult, error) {
	if session == nil {
		return ActionResult{}, errors.New(
			"advance dialogue: session is nil",
		)
	}
	session.mu.Lock()
	defer session.mu.Unlock()

	if err := session.requireOpen("advance dialogue"); err != nil {
		return ActionResult{}, err
	}
	node, err := session.currentNode("advance dialogue")
	if err != nil {
		return ActionResult{}, err
	}
	if len(node.Choices) != 0 {
		return ActionResult{}, fmt.Errorf(
			"advance dialogue: node %q requires a choice",
			node.ID,
		)
	}
	if node.Next == "" {
		session.closed = true
		return emptyActionResult(), nil
	}

	next, exists := findDialogueNode(session.dialogue, node.Next)
	if !exists {
		return ActionResult{}, fmt.Errorf(
			"advance dialogue: destination node %q is missing",
			node.Next,
		)
	}
	result, err := session.executor.Execute(session.live, next.Actions)
	if err != nil {
		return ActionResult{}, fmt.Errorf(
			"advance dialogue: enter node %q: %w",
			next.ID,
			err,
		)
	}
	session.nodeID = next.ID
	return result, nil
}

// Closed reports whether the transient interaction has ended.
func (session *DialogueSession) Closed() bool {
	if session == nil {
		return true
	}
	session.mu.Lock()
	defer session.mu.Unlock()
	return session.closed
}

func (session *DialogueSession) requireOpen(operation string) error {
	if err := session.requireValid(operation); err != nil {
		return err
	}
	if session.closed {
		return fmt.Errorf("%s: session is closed", operation)
	}
	return nil
}

func (session *DialogueSession) requireValid(operation string) error {
	if session.executor == nil ||
		session.live == nil ||
		session.dialogue.ID == "" ||
		session.nodeID == "" {
		return fmt.Errorf("%s: session is invalid", operation)
	}
	return nil
}

func (session *DialogueSession) currentNode(
	operation string,
) (gamebuild.DialogueNodeRule, error) {
	node, exists := findDialogueNode(session.dialogue, session.nodeID)
	if !exists {
		return gamebuild.DialogueNodeRule{}, fmt.Errorf(
			"%s: current node %q is missing",
			operation,
			session.nodeID,
		)
	}
	return node, nil
}

func (session *DialogueSession) choiceEligible(
	state *campaign.State,
	choice gamebuild.DialogueChoiceRule,
) (bool, error) {
	if choice.Condition == nil {
		return true, nil
	}
	quest, _, err := findQuestState(state, choice.Condition.QuestID)
	if err != nil {
		return false, err
	}
	switch choice.Condition.QuestState {
	case gamebuild.RuleQuestInactive:
		return quest.Status == campaign.QuestInactive, nil
	case gamebuild.RuleQuestActive:
		return quest.Status == campaign.QuestActive, nil
	case gamebuild.RuleQuestCompleted:
		return quest.Status == campaign.QuestCompleted, nil
	default:
		return false, fmt.Errorf(
			"unsupported quest state %q",
			choice.Condition.QuestState,
		)
	}
}

func findDialogueNode(
	dialogue gamebuild.DialogueRule,
	nodeID string,
) (gamebuild.DialogueNodeRule, bool) {
	index := sort.Search(len(dialogue.Nodes), func(index int) bool {
		return dialogue.Nodes[index].ID >= nodeID
	})
	if index == len(dialogue.Nodes) ||
		dialogue.Nodes[index].ID != nodeID {
		return gamebuild.DialogueNodeRule{}, false
	}
	return dialogue.Nodes[index], true
}

func findDialogueChoice(
	node gamebuild.DialogueNodeRule,
	choiceID string,
) (gamebuild.DialogueChoiceRule, bool) {
	for _, choice := range node.Choices {
		if choice.ID == choiceID {
			return choice, true
		}
	}
	return gamebuild.DialogueChoiceRule{}, false
}

func emptyActionResult() ActionResult {
	return ActionResult{Intents: []Intent{}}
}
