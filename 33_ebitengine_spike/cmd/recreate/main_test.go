//go:build !js

package main

import "testing"

func TestShouldStartAtTitleDistinguishesInteractiveAndBoundedRuns(
	t *testing.T,
) {
	t.Parallel()

	tests := []struct {
		name    string
		options options
		want    bool
	}{
		{
			name: "interactive desktop",
			want: true,
		},
		{
			name:    "bounded fixture",
			options: options{frames: 2},
		},
		{
			name: "bounded title capture",
			options: options{
				frames:       2,
				startAtTitle: true,
			},
			want: true,
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			if got := shouldStartAtTitle(test.options); got != test.want {
				t.Fatalf(
					"shouldStartAtTitle(%#v) = %t, want %t",
					test.options,
					got,
					test.want,
				)
			}
		})
	}
}

func TestAutomationOptionsUseUpdateLimitForModalTitle(t *testing.T) {
	t.Parallel()

	fixture := automationOptions(options{
		frames:     7,
		screenshot: "fixture.png",
	})
	if fixture.StopAfterTicks != 7 ||
		fixture.StopAfterUpdates != 0 ||
		fixture.ScreenshotPath != "fixture.png" {
		t.Fatalf("fixture automation options = %#v", fixture)
	}

	title := automationOptions(options{
		frames:       7,
		screenshot:   "title.png",
		startAtTitle: true,
	})
	if title.StopAfterTicks != 0 ||
		title.StopAfterUpdates != 7 ||
		title.ScreenshotPath != "title.png" {
		t.Fatalf("title automation options = %#v", title)
	}
}
