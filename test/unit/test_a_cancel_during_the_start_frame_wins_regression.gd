extends GutTest

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const UI_SRC := "res://src/ui/autogrind/AutogrindUI.gd"

## `_toggle_grinding` is the lane's ONLY coroutine: it commits `_is_grinding = true`, hides the
## console and writes the rules into AutogrindSystem, then suspends for one frame before emitting
## grind_requested. Any second toggle inside that window reads the flag it already set and takes
## the STOP branch, so the player's cancel lands FIRST and the suspended start emits over the top.
## Result: the system grinds, the console says it does not, and the config UI sits on a live grind.
## Same controller/system desync family as .422-.430, on the UI side of the same conduit.

var _ag_state: Dictionary
const _SM_ROUTING_FIELDS := [
	"_current_area", "_current_world_suffix", "_current_music",
	"_current_ambient_key", "_music_playing",
]
var _saved_sm: Dictionary = {}
var _ui: Control = null
var _events: Array = []


func before_each() -> void:
	_ag_state = AutogrindState.snapshot()
	_saved_sm.clear()
	for f in _SM_ROUTING_FIELDS:
		_saved_sm[f] = SoundManager.get(f)
	AutogrindSystem._test_disable_persistence = true
	if AutogrindSystem.is_grinding:
		AutogrindSystem.stop_autogrind("test reset")
	var layer := CanvasLayer.new()
	_ui = load(UI_SRC).new()
	layer.add_child(_ui)
	add_child_autofree(layer)
	_events = []
	_ui.grind_requested.connect(func(_c: Dictionary) -> void: _events.append("start"))
	_ui.grind_stop_requested.connect(func() -> void: _events.append("stop"))


func after_each() -> void:
	if AutogrindSystem.is_grinding:
		AutogrindSystem.stop_autogrind("test teardown")
	AutogrindState.restore(_ag_state)
	SoundManager.stop_music()
	for f in _SM_ROUTING_FIELDS:
		SoundManager.set(f, _saved_sm[f])


## CONTROL: without a second toggle the start MUST still reach the controller. A guard that
## suppresses the cancelled start is worthless if it also suppresses the ordinary one.
func test_an_uninterrupted_start_still_emits() -> void:
	_ui._toggle_grinding()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_events, ["start"], "a plain start must emit grind_requested exactly once")
	assert_true(_ui._is_grinding, "and the console must know it is grinding")


func test_a_cancel_inside_the_start_frame_is_not_overridden() -> void:
	_ui._toggle_grinding()
	## The player toggles again before the suspended start resumes — one frame, two events.
	_ui._toggle_grinding()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(_events.has("start"),
		"a start cancelled before it was ever emitted must not reach the controller afterwards")


func test_the_console_and_the_emitted_state_agree_after_a_cancel() -> void:
	_ui._toggle_grinding()
	_ui._toggle_grinding()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(_ui._is_grinding, "the console reports not grinding")
	assert_true(_ui.visible, "so the config UI must be back on screen, not over a live grind")


## The LATCH, not the flag, is what makes this correct: a third toggle re-raises _is_grinding
## inside the same frame, so a guard reading only the flag would let both suspended starts emit.
func test_a_restart_inside_the_window_still_emits_one_start() -> void:
	_ui._toggle_grinding()
	_ui._toggle_grinding()
	_ui._toggle_grinding()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(_events.count("start"), 1, "three toggles in one frame must leave exactly one start")
	assert_true(_ui._is_grinding, "and the console must agree it is grinding")
