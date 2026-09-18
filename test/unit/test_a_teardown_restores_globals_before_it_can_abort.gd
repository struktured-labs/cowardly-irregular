extends GutTest

## GameLoop's two autogrind teardowns cleared `_is_autogrinding` — the flag that gates re-entry —
## as their FIRST action, then restored two GLOBAL fields dozens of lines later:
##   _stop_autogrind      flag at +5 · BattleManager.turbo_mode at +30 · Engine.time_scale at +42
##   _on_grind_complete   flag at +2 · turbo_mode at +30               · time_scale at +33
##
## A GDScript error aborts its enclosing function, so an abort in that window stranded both while
## `if not _is_autogrinding: return` refused every retry. The abort is not hypothetical here —
## _start_autogrind carries struktured's own report of this shape: "grind_complete freed the
## controller and restored exploration before this line, so everything below was a null deref
## that aborted here and left the autogrind bed playing."
##
## ⛔ THE SECOND CLEARER DOES NOT RESCUE IT. stop_grind emits grind_complete SYNCHRONOUSLY, so
## _on_grind_complete usually runs re-entrantly before queue_free() — but stop_grind's IDLE branch
## returns WITHOUT resetting time_scale and without emitting, and that branch is the stranded-flag
## recovery path. On it, GameLoop's own two lines are the only clearers there are.
##
## Stranded turbo_mode collapses five inter-action delays to one process_frame and skips the
## presentation hold. Stranded Engine.time_scale runs the ENTIRE game — every later scene, menu
## and cutscene — at the grind speed, for the rest of the session.

const GameLoopScript := preload("res://src/GameLoop.gd")

const GRIND_SPEED := 2.0

var _saved_persist: bool = false


## Answers everything the teardown asks. The CONTROL case.
class FullController extends Node:
	var stopped := false
	func get_grind_stats() -> Dictionary: return {}
	func stop_grind(_reason: String) -> void: stopped = true


## Answers the stats call and NOT stop_grind. GameLoop calls stop_grind unguarded, so the
## unresolvable call aborts GameLoop's OWN frame — which a stub that merely errors internally
## could never do, because an error aborts the callee.
class StatsOnlyController extends Node:
	func get_grind_stats() -> Dictionary: return {}


func before_each() -> void:
	## Autogrind tests must never write the player's real profiles (CLAUDE.md standing rule).
	if AutogrindSystem and "_test_disable_persistence" in AutogrindSystem:
		_saved_persist = bool(AutogrindSystem._test_disable_persistence)
		AutogrindSystem._test_disable_persistence = true


func after_each() -> void:
	## FIRST and unconditional: this file deliberately sets two GLOBALS to their grind values, and
	## leaking either re-times every later test in the run. Nothing above it can abort.
	Engine.time_scale = 1.0
	if BattleManager:
		BattleManager.turbo_mode = false
	if AutogrindSystem and "_test_disable_persistence" in AutogrindSystem:
		AutogrindSystem._test_disable_persistence = _saved_persist


## NOT added to the tree — the teardown touches fields, two autoloads and its null-guarded UI
## handles, none of which need a live GameLoop.
func _loop_mid_grind(ctrl: Node) -> Node:
	var gl: Node = autofree(GameLoopScript.new())
	gl._is_autogrinding = true
	gl._autogrind_controller = ctrl
	gl._autogrind_ui = null
	gl._autogrind_dashboard = null
	Engine.time_scale = GRIND_SPEED
	BattleManager.turbo_mode = true
	return gl


func test_globals_survive_an_abort_at_the_teardowns_first_call() -> void:
	## A bare Node has neither method, so the very first call — get_grind_stats — aborts.
	var gl: Node = _loop_mid_grind(autofree(Node.new()))
	gl._stop_autogrind("probe: abort at get_grind_stats")
	assert_eq(Engine.time_scale, 1.0,
		"Engine.time_scale stranded at %s — the whole game runs at the grind speed and the re-entry guard refuses the retry that would reset it" % Engine.time_scale)
	assert_false(BattleManager.turbo_mode,
		"BattleManager.turbo_mode stranded true — every later manual battle plays at autogrind pacing")


func test_globals_survive_an_abort_at_stop_grind() -> void:
	var gl: Node = _loop_mid_grind(autofree(StatsOnlyController.new()))
	gl._stop_autogrind("probe: abort at stop_grind")
	assert_eq(Engine.time_scale, 1.0, "Engine.time_scale stranded at %s" % Engine.time_scale)
	assert_false(BattleManager.turbo_mode, "BattleManager.turbo_mode stranded true")


func test_the_sibling_entry_restores_them_too() -> void:
	## _on_grind_complete reaches the same state by its own route, with the same flag-first
	## ordering. Fixing only the reported function would leave this entry live.
	##
	## ⛔ A WORKING CONTROLLER HERE WOULD MAKE THIS ARM VACUOUS: _on_grind_complete then runs to
	## completion and its OLD bottom-of-function restores also cleared both fields, so the arm
	## passed pre-fix. Written that way first and it was green on the unfixed tree. A bare Node
	## has no get_grind_stats, which aborts the frame AFTER the hoisted restores and BEFORE the
	## old ones — the only window in which the two versions differ.
	var gl: Node = _loop_mid_grind(autofree(Node.new()))
	gl._on_grind_complete("probe")
	assert_eq(Engine.time_scale, 1.0, "Engine.time_scale stranded at %s by _on_grind_complete" % Engine.time_scale)
	assert_false(BattleManager.turbo_mode, "BattleManager.turbo_mode stranded true by _on_grind_complete")


func test_a_clean_teardown_still_restores_them() -> void:
	## CONTROL: every arm above would pass if _stop_autogrind aborted before doing anything at all.
	## This one runs the teardown through a controller that answers, and proves it got that far.
	var ctrl := FullController.new()
	var gl: Node = _loop_mid_grind(autofree(ctrl))
	gl._stop_autogrind("probe: clean")
	assert_true(ctrl.stopped,
		"CONTROL: the teardown never reached stop_grind, so the arms above measure an abort at line 1 rather than the hoist")
	assert_eq(Engine.time_scale, 1.0, "a clean teardown left Engine.time_scale at %s" % Engine.time_scale)
	assert_false(BattleManager.turbo_mode, "a clean teardown left turbo_mode true")


func test_every_member_this_file_reaches_for_still_exists() -> void:
	var gl: Node = autofree(GameLoopScript.new())
	for m in ["_stop_autogrind", "_on_grind_complete"]:
		assert_true(gl.has_method(m), "GameLoop has no method %s — this file drives it" % m)
	for f in ["_is_autogrinding", "_autogrind_controller", "_autogrind_ui", "_autogrind_dashboard"]:
		assert_true(f in gl, "GameLoop has no %s — this file writes it to stand up a live grind" % f)
	assert_not_null(BattleManager, "CONTROL: BattleManager autoload must be present")
	assert_true("turbo_mode" in BattleManager,
		"BattleManager has no turbo_mode — the field this file asserts is restored")
