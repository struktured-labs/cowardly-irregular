extends GutTest

## tick 255: pin the _flags_reachable contract.
##
## Background: tick 254 introduced _flags_reachable() to fix
## fire_event_flag's silent-fail when GameState was absent — _flags()
## returns a throwaway {} in that case, so any write would land in a
## garbage-collected dict. Same bug existed in mark_viewed and is now
## guarded the same way.
##
## Pin the invariants so a future refactor doesn't reintroduce the
## throwaway-dict write.


const PARTY_CHAT := "res://src/cutscene/PartyChatSystem.gd"


func _make_system_with_override() -> Object:
	var holder_script := GDScript.new()
	holder_script.source_code = "extends Node\nvar game_constants: Dictionary = {}\n"
	holder_script.reload()
	var holder: Node = holder_script.new()
	add_child_autofree(holder)
	var script: GDScript = load(PARTY_CHAT)
	var sys: Object = script.new()
	sys.game_state_override = holder
	return sys


# ── _flags_reachable: true when override IS set ────────────────────

func test_flags_reachable_true_when_override_set() -> void:
	var sys: Object = _make_system_with_override()
	assert_true(sys._flags_reachable(),
		"_flags_reachable() must return true when game_state_override is set, even if game_constants is empty")


# ── mark_viewed writes to override holder ──────────────────────────

func test_mark_viewed_writes_to_override_holder() -> void:
	var sys: Object = _make_system_with_override()
	# Pre-condition: unlock the chat so mark_viewed has something to flip
	sys.fire_event_flag("event_flag_level_10_reached")
	sys.mark_viewed("event_chat_level_10")
	assert_true(sys.game_state_override.game_constants.has("party_chat_viewed_event_chat_level_10"),
		"mark_viewed must persist viewed-state into the override holder, not a throwaway dict")


# ── is_available flips false after mark_viewed (cross-pin) ─────────

func test_mark_viewed_flips_is_available_off() -> void:
	# This was already covered in the e2e test (tick 251) but pin
	# specifically that mark_viewed's write WAS persisted (proves
	# the throwaway-dict write bug is fixed for the override path).
	var sys: Object = _make_system_with_override()
	sys.fire_event_flag("event_flag_level_10_reached")
	assert_true(sys.is_available("event_chat_level_10"), "precondition")
	sys.mark_viewed("event_chat_level_10")
	assert_false(sys.is_available("event_chat_level_10"),
		"is_available must reflect persisted viewed-state (was a no-op pre-fix)")


# ── Fresh system with no override AND no autoload reach ────────────

func test_fire_event_flag_no_op_without_reachable_flags() -> void:
	# Synthesize an unreachable-flags scenario by setting game_state
	# _override to null AND simulating that the autoload isn't there.
	# In headless GUT the GameState autoload IS present, so we can't
	# easily force the false path. We instead verify the helper is
	# wired correctly by reading the source — a behavioral test would
	# require process isolation.
	var script: GDScript = load(PARTY_CHAT)
	var content: String = FileAccess.get_file_as_string(PARTY_CHAT)
	# fire_event_flag must call _flags_reachable() before write
	var fef_idx: int = content.find("func fire_event_flag")
	assert_gt(fef_idx, -1, "fire_event_flag must exist")
	var fef_end: int = content.find("\n\n", fef_idx)
	var fef_body: String = content.substr(fef_idx, fef_end - fef_idx)
	assert_true(fef_body.contains("_flags_reachable"),
		"fire_event_flag body must guard on _flags_reachable() before writing")


# ── mark_viewed body must also guard on _flags_reachable ──────────

func test_mark_viewed_guards_on_flags_reachable() -> void:
	var content: String = FileAccess.get_file_as_string(PARTY_CHAT)
	var mv_idx: int = content.find("func mark_viewed")
	assert_gt(mv_idx, -1, "mark_viewed must exist")
	var mv_end: int = content.find("\n\n", mv_idx)
	var mv_body: String = content.substr(mv_idx, mv_end - mv_idx)
	assert_true(mv_body.contains("_flags_reachable"),
		"mark_viewed body must guard on _flags_reachable() before writing — same silent-fail class as fire_event_flag had")
