extends GutTest

## tick 233: AreaTransition._trigger_transition now validates
## target_map (and warns on target_spawn) before emitting.
##
## Pre-fix flow:
##   func _trigger_transition(_player):
##       if _triggered: return
##       _triggered = true
##       transition_triggered.emit(target_map, target_spawn)
##
## If target_map was empty (designer typo, forgotten override on
## a new transition node), the signal still emitted. GameLoop's
## loader hit the empty string as an unknown map_id — player
## walked into a doorway, screen faded, and NOTHING happened (or
## a silent fallback scene loaded). Hard to diagnose because the
## emit DID fire, the downstream loader just couldn't make sense
## of the payload.
##
## Fix:
##   - Empty target_map: push_warning + refuse to emit
##     (prevents the cascade through GameLoop)
##   - Empty target_spawn: push_warning but still emit
##     (most maps accept a "default" spawn point — non-fatal)
##
## The double-fire guard (_triggered) order matters: validation
## comes AFTER the double-fire guard so a triggered-already
## node doesn't re-warn on every subsequent ui_accept tick.
##
## Continues silent-fail audit theme (ticks 231-232) into a
## third exploration subsystem.

const AREA_TRANSITION := "res://src/exploration/AreaTransition.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Validation surfaces ──────────────────────────────────────────────

func test_empty_target_map_warns() -> void:
	var src := _read(AREA_TRANSITION)
	assert_true(src.contains("[AreaTransition] '%s' has empty target_map"),
		"empty target_map must push_warning naming the transition node")
	assert_true(src.contains("refusing to emit transition_triggered"),
		"warning must state the consequence (no emit)")
	assert_true(src.contains("likely an @export var unwired"),
		"warning must hint at the wiring cause for fast diagnosis")


func test_empty_target_spawn_warns_but_does_not_block() -> void:
	var src := _read(AREA_TRANSITION)
	assert_true(src.contains("[AreaTransition] '%s' has empty target_spawn"),
		"empty target_spawn must push_warning")
	assert_true(src.contains("emitting anyway"),
		"warning must state non-fatal behavior (still emits)")


# ── Order: double-fire guard runs BEFORE target_map check ─────────────

func test_double_fire_guard_precedes_target_validation() -> void:
	# Pin: if _triggered, we early-return BEFORE the target_map check.
	# Otherwise an already-emitted node would re-warn on every
	# subsequent ui_accept tick (player holds the button after the
	# transition fires) — annoying log noise.
	var src := _read(AREA_TRANSITION)
	var fn_idx: int = src.find("func _trigger_transition")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	var triggered_check: int = body.find("if _triggered:")
	var empty_map_check: int = body.find("if target_map == \"\":")
	assert_gt(triggered_check, -1)
	assert_gt(empty_map_check, -1)
	assert_lt(triggered_check, empty_map_check,
		"double-fire guard must come BEFORE target_map validation (prevents repeat warnings on held button)")


func test_validation_precedes_triggered_flag_set() -> void:
	# Pin: target_map validation comes BEFORE `_triggered = true`.
	# Otherwise a bad config gets locked into _triggered=true on
	# first attempt, but the same node could be re-tried in a
	# legitimate way after editing (in editor) and we'd skip the
	# warn-and-refuse path.
	var src := _read(AREA_TRANSITION)
	var fn_idx: int = src.find("func _trigger_transition")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	var empty_map_check: int = body.find("if target_map == \"\":")
	var triggered_set: int = body.find("_triggered = true")
	assert_gt(empty_map_check, -1)
	assert_gt(triggered_set, -1)
	assert_lt(empty_map_check, triggered_set,
		"target_map validation must come BEFORE `_triggered = true` (avoids locking out a corrected config)")


# ── Existing behavior preserved ──────────────────────────────────────

func test_double_fire_guard_preserved() -> void:
	var src := _read(AREA_TRANSITION)
	var fn_idx: int = src.find("func _trigger_transition")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("if _triggered:\n\t\treturn"),
		"original double-fire guard preserved")


func test_emit_still_happens_in_happy_path() -> void:
	# Pin: the emit line is still present (the validations only
	# add early-returns/warnings; they don't remove the success path).
	var src := _read(AREA_TRANSITION)
	var fn_idx: int = src.find("func _trigger_transition")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, src.length() - fn_idx) if next_fn < 0 else src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("transition_triggered.emit(target_map, target_spawn)"),
		"happy-path emit preserved")


# ── Default values still sane (sanity check) ─────────────────────────

func test_default_target_map_is_overworld() -> void:
	# Pin: the default value for the @export var hasn't been
	# changed to empty (which would defeat the validation).
	var src := _read(AREA_TRANSITION)
	assert_true(src.contains("@export var target_map: String = \"overworld\""),
		"default target_map must be 'overworld' (non-empty, validation passes for unset nodes)")
	assert_true(src.contains("@export var target_spawn: String = \"default\""),
		"default target_spawn must be 'default'")


# ── Cross-pin: tick 232 OverworldController audit preserved ──────────

func test_tick_232_overworld_loud_fail_preserved() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/exploration/OverworldController.gd")
	assert_true(src.contains("[OverworldController] enemy_pools.json missing at %s"),
		"tick 232 OverworldController loud-fail preserved")
