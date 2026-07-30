package rulesruntime

import (
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func (executor *Executor) validateCutsceneRules() error {
	for _, cutscene := range executor.rules.Cutscenes {
		if len(cutscene.Steps) == 0 {
			return fmt.Errorf("cutscene %q has no steps", cutscene.ID)
		}
		stepIDs := make(map[string]struct{}, len(cutscene.Steps))
		for index, step := range cutscene.Steps {
			if step.ID == "" {
				return fmt.Errorf(
					"cutscene %q step %d has empty id",
					cutscene.ID,
					index,
				)
			}
			if _, duplicate := stepIDs[step.ID]; duplicate {
				return fmt.Errorf(
					"cutscene %q has duplicate step %q",
					cutscene.ID,
					step.ID,
				)
			}
			stepIDs[step.ID] = struct{}{}
			if step.Text == "" && step.TextKey == "" {
				return fmt.Errorf(
					"cutscene %q step %q has no text or text key",
					cutscene.ID,
					step.ID,
				)
			}
			if step.DurationTicks < 0 ||
				step.DurationTicks > sim.MaxTickCount {
				return fmt.Errorf(
					"cutscene %q step %q has invalid duration %d ticks",
					cutscene.ID,
					step.ID,
					step.DurationTicks,
				)
			}
			if err := executor.validateActionList(
				step.Actions,
				fmt.Sprintf(
					"cutscene %q step %q actions",
					cutscene.ID,
					step.ID,
				),
			); err != nil {
				return err
			}
		}
		if err := executor.validateActionList(
			cutscene.OnComplete,
			fmt.Sprintf("cutscene %q on_complete", cutscene.ID),
		); err != nil {
			return err
		}
	}
	return nil
}
