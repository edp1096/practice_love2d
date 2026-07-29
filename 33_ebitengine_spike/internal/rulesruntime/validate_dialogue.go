package rulesruntime

import (
	"fmt"
	"sort"

	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

func (executor *Executor) validateDialogueRules() error {
	for _, dialogue := range executor.rules.Dialogues {
		if dialogue.StartNode == "" ||
			!dialogueHasNode(dialogue, dialogue.StartNode) {
			return fmt.Errorf(
				"dialogue %q has missing start node %q",
				dialogue.ID,
				dialogue.StartNode,
			)
		}
		if err := validateDialogueNodeOrder(dialogue); err != nil {
			return err
		}
		for _, node := range dialogue.Nodes {
			if node.Next != "" && !dialogueHasNode(dialogue, node.Next) {
				return fmt.Errorf(
					"dialogue %q node %q references missing next node %q",
					dialogue.ID,
					node.ID,
					node.Next,
				)
			}
			if err := executor.validateActionList(
				node.Actions,
				fmt.Sprintf(
					"dialogue %q node %q actions",
					dialogue.ID,
					node.ID,
				),
			); err != nil {
				return err
			}
			if err := executor.validateDialogueChoices(
				dialogue,
				node,
			); err != nil {
				return err
			}
		}
	}
	return nil
}

func (executor *Executor) validateDialogueChoices(
	dialogue gamebuild.DialogueRule,
	node gamebuild.DialogueNodeRule,
) error {
	choiceIDs := make(map[string]struct{}, len(node.Choices))
	for _, choice := range node.Choices {
		if choice.ID == "" {
			return fmt.Errorf(
				"dialogue %q node %q has empty choice id",
				dialogue.ID,
				node.ID,
			)
		}
		if _, duplicate := choiceIDs[choice.ID]; duplicate {
			return fmt.Errorf(
				"dialogue %q node %q has duplicate choice %q",
				dialogue.ID,
				node.ID,
				choice.ID,
			)
		}
		choiceIDs[choice.ID] = struct{}{}
		if choice.Next != "" &&
			!dialogueHasNode(dialogue, choice.Next) {
			return fmt.Errorf(
				"dialogue %q choice %q references missing next node %q",
				dialogue.ID,
				choice.ID,
				choice.Next,
			)
		}
		if choice.Condition != nil {
			if err := executor.validateCondition(
				*choice.Condition,
				fmt.Sprintf(
					"dialogue %q choice %q condition",
					dialogue.ID,
					choice.ID,
				),
			); err != nil {
				return err
			}
		}
		if err := executor.validateActionList(
			choice.Actions,
			fmt.Sprintf(
				"dialogue %q choice %q actions",
				dialogue.ID,
				choice.ID,
			),
		); err != nil {
			return err
		}
	}
	return nil
}

func validateDialogueNodeOrder(dialogue gamebuild.DialogueRule) error {
	for index, node := range dialogue.Nodes {
		if node.ID == "" {
			return fmt.Errorf(
				"dialogue %q node %d has empty id",
				dialogue.ID,
				index,
			)
		}
		if index > 0 && dialogue.Nodes[index-1].ID >= node.ID {
			return fmt.Errorf(
				"dialogue %q nodes are not in strict canonical ID order at %q",
				dialogue.ID,
				node.ID,
			)
		}
	}
	return nil
}

func dialogueHasNode(dialogue gamebuild.DialogueRule, id string) bool {
	index := sort.Search(len(dialogue.Nodes), func(index int) bool {
		return dialogue.Nodes[index].ID >= id
	})
	return index < len(dialogue.Nodes) && dialogue.Nodes[index].ID == id
}
