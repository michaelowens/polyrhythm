package main

import "core:bufio"
import "core:bytes"
import "core:c"
import "core:fmt"
import "core:io"
import "core:math"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:sys/windows"
import "core:time"
import pm "vendor:portmidi"

BUFFER_SIZE :: 100
BASE_NOTE: i32 : 36
NOTE_DURATION :: 300
CHORD_DURATION :: 1200

state := struct {
	forceQuit:       bool,
	notesPressed:    [dynamic]i32,
	chords:          [dynamic]i32,
	notes:           [dynamic]i32,
	scaleOffsets:    [dynamic]i32,
	noteBPMs:        [dynamic]f32,
	chordBPM:        f32,
	noteLastPlayed:  [13]time.Duration,
	chordLastPlayed: time.Duration,
	chordIndex:      int,
	notesScale:      i32,
	chordsScale:     i32,
} {
	forceQuit      = false,
	chords         = {1, 6, 5, 4},
	notes          = {1, 3, 5, 7, 8, 10, 12, 14, 15, 17, 19, 21, 22}, // C2// E2// G2// B2// C3// E3
	scaleOffsets   = {0, 2, 4, 5, 7, 9, 11}, // c major scale
	chordBPM       = 15.0,
	noteBPMs       =  {
		15.0,
		15.3,
		15.600000000000002,
		15.900000000000003,
		16.200000000000004,
		16.500000000000005,
		16.800000000000006,
		17.100000000000006,
		17.400000000000007,
		17.700000000000008,
		18.000000000000008,
		18.300000000000009,
		18.60000000000001,
	},
	noteLastPlayed = [13]time.Duration{},
	chordIndex     = 0,
	notesScale     = 1,
	chordsScale    = 0,
}

/// Signal handlers (mostly for ctrl-c)
// TODO: implement for other distros
when ODIN_OS == .Windows {
	registerSignalHandler :: proc() {
		windows.SetConsoleCtrlHandler(sigHandler, true)
	}

	sigHandler :: proc "system" (dwCtrlType: windows.DWORD) -> windows.BOOL {
		if dwCtrlType == windows.CTRL_C_EVENT {
			state.forceQuit = true
		}

		return true
	}
} else {
	registerSignalHandler :: proc() {
		fmt.eprintln("Registering signal handler failed: not implemented for your system")
	}
}

calculateMidiNote :: proc(n: i32, scale: i32) -> i32 {
	note_index := (n - 1) % 7
	octave := ((n - 1) / 7) + scale
	midi_note := BASE_NOTE + octave * 12 + state.scaleOffsets[note_index]
	return midi_note
}

device_selector :: proc() -> pm.DeviceID {
	fmt.println("Select MIDI output device...")

	deviceCount: int = auto_cast pm.CountDevices()
	for i := 0; i < deviceCount; i += 1 {
		device := pm.GetDeviceInfo(auto_cast i)
		if !device.output {continue}
		fmt.printfln("%v: %v", i, device.name)
		// auto select loopMIDI during dev
		if device.name == "loopMIDI Port" {
			return cast(pm.DeviceID)i
		}
	}

	fmt.print("Number: ")
	data: [10]byte
	os.read(os.stdin, data[:])

	// stdin_stream := os.stream_from_handle(io.stdin)

	adv, tok, erro, fin := bufio.scan_lines(data[:], true)
	selected_device_id: pm.DeviceID = auto_cast strconv.atoi(auto_cast tok)

	return selected_device_id
}

stop_held_notes :: proc(midi_ctx: ^MidiContext) {
	for note, started in midi_ctx.active_notes {
		duration := time.duration_milliseconds(time.tick_diff(started, midi_ctx.last_tick))
		if duration >= NOTE_DURATION {
			midi_note_off(midi_ctx, note)
		}
	}
}

main :: proc() {
	fmt.println("MIDI Polyrhythm\n")

	registerSignalHandler()

	midi_ctx := midi_init()
	defer midi_deinit(&midi_ctx)

	selected_device_id := device_selector()
	midi_select_device(&midi_ctx, selected_device_id)

	ui_init()
	defer ui_deinit()

	midi_reset_time(&midi_ctx)

	note_is_on := false
	last_tick := time.tick_now()
	time_passed: f64 = 0
	total_time_passed: f64 = 0
	note_index := 0
	chord_note_on := false
	for !state.forceQuit && ui_should_show() {
		midi_tick(&midi_ctx)
		stop_held_notes(&midi_ctx)

		// chord
		chordBPMMs := cast(f64)(60000 / state.chordBPM)
		ms_since_last_chord :=
			time.duration_milliseconds(midi_ctx.total_time_passed) -
			time.duration_milliseconds(state.chordLastPlayed)
		if chord_note_on && ms_since_last_chord >= CHORD_DURATION {
			midiChord: i32 = calculateMidiNote(state.chords[state.chordIndex], state.chordsScale)
			midi_send_command(&midi_ctx, .NoteOff, midiChord, 100)
			chord_note_on = false
		}

		if ms_since_last_chord >= chordBPMMs {
			state.chordIndex = (state.chordIndex + 1) % len(state.chords)
			midiChord: i32 = calculateMidiNote(state.chords[state.chordIndex], state.chordsScale)
			// midi_note_on(&midi_ctx, midiChord)
			midi_send_command(&midi_ctx, .NoteOn, midiChord, 100)
			chord_note_on = true
			state.chordLastPlayed = midi_ctx.total_time_passed
		}

		// notes
		for note, i in state.notes {
			bpm := state.noteBPMs[i]
			lastPlayed := state.noteLastPlayed[i]
			bpmMs := cast(f64)(60000 / bpm)
			ms_since_last :=
				time.duration_milliseconds(midi_ctx.total_time_passed) -
				time.duration_milliseconds(lastPlayed)
			if ms_since_last >= bpmMs {
				calcNote := note + (state.chords[state.chordIndex] - 1)
				midiNote: i32 = calculateMidiNote(calcNote, state.notesScale)
				midi_note_on(&midi_ctx, midiNote)
				state.noteLastPlayed[i] = midi_ctx.total_time_passed
			}
		}

		time_passed += midi_ctx.ms_since_last_tick
		total_time_passed += midi_ctx.ms_since_last_tick

		ui_render(&midi_ctx)
	}

	// fmt.println("Cleaning up...")

}
