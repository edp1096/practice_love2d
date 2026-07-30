package gameapp

import "practice_love2d/33_ebitengine_spike/internal/campaign"

func motionScale(settings campaign.AccessibilitySettings) float64 {
	switch settings.Motion {
	case "off":
		return 0
	case "reduced":
		return 0.35
	default:
		return 1
	}
}

func noticeTicks(
	ticks int,
	settings campaign.AccessibilitySettings,
) int {
	if settings.NoticeDuration == "long" {
		return ticks * 2
	}
	return ticks
}
