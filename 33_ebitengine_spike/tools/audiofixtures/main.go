// Command audiofixtures generates the original synthetic WAV files used by
// the sample project. It has no external tool or source-asset dependency.
package main

import (
	"encoding/binary"
	"errors"
	"flag"
	"fmt"
	"math"
	"os"
	"path/filepath"
)

const sampleRate = 48_000

type sampleFunc func(float64) float64

func main() {
	var output string
	flag.StringVar(&output, "output", "", "assets/runtime output directory")
	flag.Parse()
	if output == "" {
		fmt.Fprintln(os.Stderr, "audiofixtures: -output is required")
		os.Exit(2)
	}
	if err := generate(output); err != nil {
		fmt.Fprintln(os.Stderr, "audiofixtures:", err)
		os.Exit(1)
	}
}

func generate(output string) error {
	files := []struct {
		path     string
		duration float64
		sample   sampleFunc
	}{
		{"audio/music/forest-theme.wav", 8, forestTheme},
		{"audio/music/village-theme.wav", 8, villageTheme},
		{"audio/music/road-theme.wav", 8, roadTheme},
		{"audio/sfx/attack.wav", 0.18, attackCue},
		{"audio/sfx/hit.wav", 0.16, hitCue},
		{"audio/sfx/jump.wav", 0.22, jumpCue},
		{"audio/sfx/kill.wav", 0.42, killCue},
		{"audio/sfx/parry.wav", 0.34, parryCue},
		{"audio/sfx/projectile.wav", 0.24, projectileCue},
		{"audio/sfx/quest.wav", 0.72, questCue},
		{"audio/sfx/ui-cancel.wav", 0.12, uiCancelCue},
		{"audio/sfx/ui-confirm.wav", 0.12, uiConfirmCue},
	}
	for _, file := range files {
		target := filepath.Join(output, filepath.FromSlash(file.path))
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		if err := writeWAV(target, file.duration, file.sample); err != nil {
			return fmt.Errorf("%s: %w", file.path, err)
		}
	}
	return nil
}

func writeWAV(path string, duration float64, sample sampleFunc) error {
	if duration <= 0 || sample == nil {
		return errors.New("invalid waveform")
	}
	count := int(math.Round(duration * sampleRate))
	dataSize := count * 2
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()
	write := func(value any) error {
		return binary.Write(file, binary.LittleEndian, value)
	}
	if _, err := file.Write([]byte("RIFF")); err != nil {
		return err
	}
	if err := write(uint32(36 + dataSize)); err != nil {
		return err
	}
	if _, err := file.Write([]byte("WAVEfmt ")); err != nil {
		return err
	}
	for _, value := range []any{
		uint32(16),
		uint16(1),
		uint16(1),
		uint32(sampleRate),
		uint32(sampleRate * 2),
		uint16(2),
		uint16(16),
	} {
		if err := write(value); err != nil {
			return err
		}
	}
	if _, err := file.Write([]byte("data")); err != nil {
		return err
	}
	if err := write(uint32(dataSize)); err != nil {
		return err
	}
	for index := 0; index < count; index++ {
		t := float64(index) / sampleRate
		value := max(-1, min(1, sample(t)))
		if err := write(int16(math.Round(value * 32767))); err != nil {
			return err
		}
	}
	return file.Sync()
}

func loopEdge(t, length float64) float64 {
	return min(1, min(t/0.08, (length-t)/0.08))
}

func forestTheme(t float64) float64 {
	const length = 8.0
	edge := loopEdge(t, length)
	beat := math.Mod(t, 2)
	pulse := 0.45 + 0.55*math.Exp(-4*beat)
	chords := [4][3]float64{
		{130.81, 155.56, 196.00},
		{116.54, 146.83, 174.61},
		{103.83, 130.81, 155.56},
		{116.54, 146.83, 196.00},
	}
	chord := chords[int(t/2)%len(chords)]
	value := 0.0
	for index, frequency := range chord {
		value += math.Sin(2*math.Pi*frequency*t+float64(index)*0.7) *
			(0.11 - float64(index)*0.018)
	}
	value += 0.045 * math.Sin(2*math.Pi*chord[0]*0.5*t)
	return value * pulse * max(0, edge)
}

func villageTheme(t float64) float64 {
	const length = 8.0
	chords := [4][3]float64{
		{130.81, 164.81, 196.00},
		{146.83, 174.61, 220.00},
		{164.81, 196.00, 246.94},
		{146.83, 174.61, 220.00},
	}
	chord := chords[int(t/2)%len(chords)]
	beat := math.Mod(t, 0.5)
	bell := math.Exp(-7 * beat)
	value := 0.06 * math.Sin(2*math.Pi*chord[0]*0.5*t)
	for index, frequency := range chord {
		value += math.Sin(
			2*math.Pi*frequency*t+float64(index)*0.32,
		) * (0.075 - float64(index)*0.012)
	}
	arpeggio := chord[int(t/0.5)%len(chord)] * 2
	value += math.Sin(2*math.Pi*arpeggio*t) * bell * 0.075
	return value * max(0, loopEdge(t, length))
}

func roadTheme(t float64) float64 {
	const length = 8.0
	roots := [4]float64{110.00, 98.00, 87.31, 98.00}
	root := roots[int(t/2)%len(roots)]
	beat := math.Mod(t, 0.5)
	pulse := 0.38 + 0.62*math.Exp(-8*beat)
	melody := [8]float64{
		220.00, 261.63, 293.66, 261.63,
		196.00, 220.00, 261.63, 220.00,
	}
	note := melody[int(t/0.5)%len(melody)]
	value := math.Sin(2*math.Pi*root*t)*0.11 +
		math.Sin(2*math.Pi*root*1.5*t+0.4)*0.06 +
		math.Sin(2*math.Pi*note*t)*0.07
	return value * pulse * max(0, loopEdge(t, length))
}

func attackCue(t float64) float64 {
	duration := 0.18
	frequency := 760 - 560*(t/duration)
	phase := 2 * math.Pi * frequency * t
	return math.Sin(phase) * decay(t, duration, 7) * 0.55
}

func hitCue(t float64) float64 {
	duration := 0.16
	noise := math.Sin(2*math.Pi*1733*t) *
		math.Sin(2*math.Pi*947*t+0.4)
	body := math.Sin(2 * math.Pi * 92 * t)
	return (noise*0.38 + body*0.28) * decay(t, duration, 12)
}

func jumpCue(t float64) float64 {
	duration := 0.22
	frequency := 260 + 620*(t/duration)
	return math.Sin(2*math.Pi*frequency*t) * decay(t, duration, 3) * 0.42
}

func killCue(t float64) float64 {
	duration := 0.42
	frequency := 240 - 150*(t/duration)
	return (math.Sin(2*math.Pi*frequency*t)*0.38 +
		math.Sin(2*math.Pi*frequency*0.5*t)*0.2) *
		decay(t, duration, 4)
}

func parryCue(t float64) float64 {
	duration := 0.34
	return (math.Sin(2*math.Pi*880*t)*0.32 +
		math.Sin(2*math.Pi*1320*t)*0.22 +
		math.Sin(2*math.Pi*1760*t)*0.12) *
		decay(t, duration, 6)
}

func projectileCue(t float64) float64 {
	duration := 0.24
	frequency := 310 + 240*(t/duration)
	wobble := 22 * math.Sin(2*math.Pi*18*t)
	return math.Sin(2*math.Pi*(frequency+wobble)*t) *
		decay(t, duration, 3) * 0.42
}

func questCue(t float64) float64 {
	duration := 0.72
	notes := [...]float64{523.25, 659.25, 783.99, 1046.5}
	index := min(len(notes)-1, int(t/0.18))
	local := math.Mod(t, 0.18)
	return math.Sin(2*math.Pi*notes[index]*t) *
		decay(local, 0.18, 5) *
		decay(t, duration, 0.7) *
		0.38
}

func uiCancelCue(t float64) float64 {
	return math.Sin(2*math.Pi*(420-140*t/0.12)*t) *
		decay(t, 0.12, 6) *
		0.3
}

func uiConfirmCue(t float64) float64 {
	return math.Sin(2*math.Pi*(520+180*t/0.12)*t) *
		decay(t, 0.12, 5) *
		0.3
}

func decay(t, duration, strength float64) float64 {
	if t < 0 || t >= duration {
		return 0
	}
	attack := min(1, t/0.008)
	return attack * math.Exp(-strength*t/duration)
}
