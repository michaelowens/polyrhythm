package main

import "core:fmt"
import "core:time"
import pm "vendor:portmidi"

MidiCommand :: enum {
	NoteOff = 0x80,
	NoteOn  = 0x90,
}

MidiContext :: struct {
	device_stream:      pm.Stream,
	active_notes:       map[i32]time.Tick,
	first_tick:         time.Tick,
	last_tick:          time.Tick,
	ms_since_last_tick: f64,
	total_time_passed:  time.Duration,
}

midi_init :: proc() -> MidiContext {
	err := pm.Initialize()
	if err != .NoError {
		fmt.eprintln(err)
	}

	return {}
}

midi_select_device :: proc(ctx: ^MidiContext, device_id: pm.DeviceID) -> pm.Error {
	err := pm.OpenOutput(&ctx.device_stream, device_id, nil, BUFFER_SIZE, nil, nil, 5)
	if err != .NoError {
		fmt.eprintln(err)
		return err
	}

	return .NoError
}

midi_reset_time :: proc(ctx: ^MidiContext) {
	current_tick := time.tick_now()
	ctx.first_tick = current_tick
	ctx.last_tick = current_tick
}

midi_tick :: proc(ctx: ^MidiContext) {
	tick := time.tick_now()
	ctx.ms_since_last_tick = time.duration_milliseconds(time.tick_diff(ctx.last_tick, tick))
	ctx.total_time_passed = time.tick_diff(ctx.first_tick, tick)
	ctx.last_tick = tick
}

midi_send_command :: proc(ctx: ^MidiContext, command: MidiCommand, data1, data2: i32) {
	// TODO: check if I can use timestamps to sync notes properly
	pm.WriteShort(ctx.device_stream, 0, pm.MessageMake(cast(i32)command, data1, data2))
}

midi_note_on :: proc(ctx: ^MidiContext, note: i32) {
	// fmt.printfln("NOTE_ON %v", note)
	midi_send_command(ctx, .NoteOn, note, 100)
	ctx.active_notes[note] = ctx.last_tick
}

midi_note_off :: proc(ctx: ^MidiContext, note: i32) {
	// fmt.printfln("NOTE_OFF %v", note)
	midi_send_command(ctx, .NoteOff, note, 100)
	delete_key(&ctx.active_notes, note)
}

midi_stop_all_notes :: proc(ctx: ^MidiContext) {
	for note in ctx.active_notes {
		midi_send_command(ctx, .NoteOff, note, 100)
	}

	clear(&ctx.active_notes)
}

midi_deinit :: proc(ctx: ^MidiContext) {
	midi_stop_all_notes(ctx)

	if ctx.device_stream != nil {
		pm.Close(ctx.device_stream)
	}
	pm.Terminate()
}
