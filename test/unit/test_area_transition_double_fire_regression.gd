extends GutTest

## Defensive regression: AreaTransition._trigger_transition must not
## emit transition_triggered more than once per zone instance, and
## _input must not fire on a ui_accept key-repeat echo.
##
## Bug shape:
##   • _input handled `event.is_action_pressed("ui_accept")` without
##     the `not event.is_echo()` guard. Holding the action key fired
##     the handler repeatedly at the OS key-repeat rate. Each fire
##     called _trigger_transition → emitted transition_triggered.
##   • _trigger_transition had no double-fire guard. The auto-enter
##     path (_on_body_entered when require_interaction is false) AND
##     a manual interact()/_input call could race during the brief
##     window before the scene-change pipeline freed this node.
##   • GameLoop's transition handler is not idempotent under back-to-
##     back emits — a double-emit could chain two scene loads, leaving
##     the player in an unexpected state.
##
## Fix:
##   • _triggered bool, set on first _trigger_transition call. All
##     subsequent calls short-circuit before the emit.
##   • _input filters `ui_accept` echoes.
##
## Tests:
##   • Source pin: _triggered var declared
##   • Source pin: _trigger_transition checks _triggered before emit
##   • Source pin: _input gates ui_accept on `not event.is_echo()`
##   • Behavioural: two back-to-back calls to _trigger_transition
##     emit transition_triggered exactly once

const AREA_TRANSITION_PATH := "res://src/exploration/AreaTransition.gd"
const AreaTransitionScript := preload("res://src/exploration/AreaTransition.gd")


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ───────────────────────────────────────────────────────────────

func test_triggered_flag_declared() -> void:
	var text := _read(AREA_TRANSITION_PATH)
	assert_true(text.contains("var _triggered"),
		"AreaTransition must declare a _triggered bool to guard double-emit")


func test_trigger_transition_checks_triggered_before_emit() -> void:
	var text := _read(AREA_TRANSITION_PATH)
	var idx := text.find("func _trigger_transition")
	assert_gt(idx, -1, "_trigger_transition must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# The guard must short-circuit BEFORE the emit. Find the emit; assert
	# the `if _triggered:` and the assignment `_triggered = true` both
	# appear before that emit.
	var emit_idx := body.find("transition_triggered.emit(")
	assert_gt(emit_idx, -1, "_trigger_transition must emit transition_triggered")
	var pre_emit := body.substr(0, emit_idx)
	assert_true(pre_emit.contains("if _triggered:"),
		"_trigger_transition must check `if _triggered:` BEFORE the emit")
	assert_true(pre_emit.contains("_triggered = true"),
		"_trigger_transition must set `_triggered = true` BEFORE the emit")


func test_input_filters_ui_accept_echo() -> void:
	var text := _read(AREA_TRANSITION_PATH)
	var idx := text.find("func _input")
	assert_gt(idx, -1, "_input must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# The ui_accept branch must check `not event.is_echo()` alongside
	# `event.is_action_pressed("ui_accept")`.
	assert_true(body.contains("event.is_action_pressed(\"ui_accept\") and not event.is_echo()"),
		"_input's ui_accept branch must filter echoes via `and not event.is_echo()`")


# ── Behavioural ──────────────────────────────────────────────────────────────

func test_double_trigger_emits_signal_only_once() -> void:
	# Instantiate a transition, force it into a "ready to fire" state, and
	# call _trigger_transition twice in a row. transition_triggered must
	# fire exactly once.
	var at: AreaTransition = AreaTransitionScript.new()
	add_child_autofree(at)
	# Set a target so the print/emit have something coherent.
	at.target_map = "test_target"
	at.target_spawn = "spawn_a"
	# Array-as-counter for lambda capture (int captures by value, see tick 19).
	var emit_count: Array[int] = [0]
	at.transition_triggered.connect(func(_m, _s): emit_count[0] += 1)
	# Two back-to-back calls — the second must short-circuit on _triggered.
	at._trigger_transition(null)
	at._trigger_transition(null)
	assert_eq(emit_count[0], 1,
		"transition_triggered must fire EXACTLY once across two _trigger_transition calls (double-fire guard)")
