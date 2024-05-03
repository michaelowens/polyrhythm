package main

import "core:math"
import "core:time"
import rl "vendor:raylib"

ui_state := struct {
	width:         i32,
	height:        i32,
	circlePadding: i32,
	circleRadius:  i32,
} {
	width         = 900,
	height        = 600,
	circlePadding = 10,
	circleRadius  = 10,
}

ui_init :: proc() {
	rl.InitWindow(ui_state.width, ui_state.height, "Polyrhythm")
	rl.SetTargetFPS(60)
}

ui_deinit :: proc() {
	rl.CloseWindow()
}

ui_should_show :: proc() -> bool {
	return !rl.WindowShouldClose()
}

ui_render :: proc(midi_ctx: ^MidiContext) {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	ms := time.duration_milliseconds(midi_ctx.total_time_passed)
	screenWidth := cast(f64)ui_state.width - 60
	for bpm, i in state.noteBPMs {
		beatTime := cast(f64)(60000.0 / bpm)
		angle := 2 * 3.14 * ms / beatTime
		x := 30 + (screenWidth / 2) + ((screenWidth / 2) * math.cos(angle / 2))
		y := 30 + cast(i32)(30 * i) + (ui_state.circlePadding * cast(i32)i)

		color := rl.RED

		rl.DrawCircle(cast(i32)x, y, auto_cast ui_state.circleRadius, color)
	}

	rl.EndDrawing()
}
