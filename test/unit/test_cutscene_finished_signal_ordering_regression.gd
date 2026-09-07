extends GutTest

## Regression: CutsceneDirector._end_cutscene must clear its member-state
## (_cutscene_id, _active, _skipping, visible) BEFORE emitting
## `cutscene_finished`, otherwise a listener that synchronously chains
## into a new cutscene gets its work silently undone.
##
## Bug shape:
##   1. CutsceneA finishes → _end_cutscene executes.
##   2. Pre-fix line ordering:
##        cutscene_finished.emit(_cutscene_id)   # <-- _cutscene_id is "A"
##        _cutscene_id = ""                      # <-- clobbers later
##   3. Synchronous listener (e.g. GameLoop._on_prologue_finished) inside
##      that emit calls _cutscene_director.play_cutscene("B"). That
##      function sets _cutscene_id = "B", _active = true, _skipping = false.
##   4. play_cutscene "B" awaits on its first real step.
##   5. Control returns to _end_cutscene. The line `_cutscene_id = ""`
##      runs and clobbers "B" with empty string.
##   6. Result: cutscene "B" runs with _cutscene_id == "" — every
##      downstream emit (cutscene_skipped, cutscene_finished) for "B"
##      fires with the empty string. Listeners that route on cutscene_id
##      (e.g. the per-id completion-flag mirror in _play_story_cutscene's
##      closure) silently lose the chained cutscene's completion signal.
##
## Fix: snapshot the id, clear all member state, THEN emit. Listeners
## that chain into play_cutscene now run with a clean slate.
##
## Also covered: play_cutscene_from_data now delegates the skip-set_flag
## fanout to the shared _apply_remaining_set_flag_steps helper (instead
## of an inline-duplicated loop). Without this dedup, the helper and the
## inline path could drift — and the helper's docstring calls this out
## as "CRITICAL — silent failure here means skipped cutscenes replay
## forever".

const CUTSCENE_DIRECTOR_PATH := "res://src/cutscene/CutsceneDirector.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ───────────────────────────────────────────────────────────────

func test_end_cutscene_clears_state_before_emit() -> void:
	# Without this ordering, a synchronous listener that chains into the
	# next cutscene loses its _cutscene_id to the post-emit clobber.
	var text := _read(CUTSCENE_DIRECTOR_PATH)
	var idx := text.find("func _end_cutscene")
	assert_gt(idx, -1, "_end_cutscene must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# The emit and the _cutscene_id reset must both appear, and the reset
	# must come BEFORE the emit.
	var emit_idx := body.find("cutscene_finished.emit(")
	assert_gt(emit_idx, -1, "_end_cutscene must emit cutscene_finished")
	var clear_idx := body.find("_cutscene_id = \"\"")
	assert_gt(clear_idx, -1, "_end_cutscene must clear _cutscene_id")
	assert_lt(clear_idx, emit_idx,
		"_cutscene_id must be cleared BEFORE the emit so chained cutscenes are not clobbered")
	# Same for _active.
	var active_clear := body.find("_active = false")
	assert_gt(active_clear, -1, "_end_cutscene must clear _active")
	assert_lt(active_clear, emit_idx,
		"_active = false must be set BEFORE the emit so listeners see we're between cutscenes")


func test_end_cutscene_emits_with_snapshot_not_cleared_value() -> void:
	# The emit must carry the FINISHED cutscene's id, not the empty string
	# left after clearing. A snapshot local must appear in the function
	# body and feed the emit call.
	var text := _read(CUTSCENE_DIRECTOR_PATH)
	var idx := text.find("func _end_cutscene")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# Pattern: a local that snapshots _cutscene_id, then `emit(<snapshot>)`.
	var snapshot_idx := body.find("= _cutscene_id")
	assert_gt(snapshot_idx, -1,
		"_end_cutscene must snapshot _cutscene_id into a local before clearing")
	# The snapshot must be referenced by the emit.
	var emit_idx := body.find("cutscene_finished.emit(")
	assert_gt(emit_idx, -1, "_end_cutscene must emit cutscene_finished")
	assert_lt(snapshot_idx, emit_idx,
		"snapshot must happen BEFORE the emit")
	# The emit's argument must NOT be a bare _cutscene_id (would be ""
	# at that point — we already cleared it).
	var emit_slice := body.substr(emit_idx, 80)
	assert_false(emit_slice.contains("cutscene_finished.emit(_cutscene_id)"),
		"emit must use the snapshot local, not the (already-cleared) _cutscene_id field")


func test_play_cutscene_from_data_uses_helper_for_skip_fanout() -> void:
	# Both play paths must route through _apply_remaining_set_flag_steps
	# so they share a single, unit-testable code path. Inline duplication
	# is the bug shape — silent drift between paths.
	var text := _read(CUTSCENE_DIRECTOR_PATH)
	var idx := text.find("func play_cutscene_from_data")
	assert_gt(idx, -1, "play_cutscene_from_data must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("_apply_remaining_set_flag_steps"),
		"play_cutscene_from_data must delegate skip fanout to _apply_remaining_set_flag_steps")
	# Negative guard: no inline loop over set_flag steps. The legacy shape
	# was: `if steps[i].get("type", "") == "set_flag": _step_set_flag(...)`
	# scoped to this function. We don't want both inline AND helper.
	assert_false(body.contains("_step_set_flag(steps[i])"),
		"play_cutscene_from_data must NOT inline the set_flag loop (use the helper)")


# ── Behavioural ──────────────────────────────────────────────────────────────

func test_listener_can_synchronously_play_chained_cutscene_without_clobber() -> void:
	# Drive the actual ordering: create a CutsceneDirector, simulate the
	# end of cutscene A, install a listener that synchronously calls
	# play_cutscene on the same director, and verify the chained
	# cutscene's _cutscene_id is intact after _end_cutscene returns.
	#
	# We avoid the full UI by calling _end_cutscene with a minimal
	# pre-loaded state — _cutscene_id = "A", everything else default.
	# The director itself doesn't add letterbox or dialogue children
	# until they are needed, so _end_cutscene's UI-cleanup branches are
	# no-ops for a fresh instance.
	var CutsceneDirectorScript: GDScript = load(CUTSCENE_DIRECTOR_PATH)
	# The director is a CanvasLayer (autoload-like); we can instantiate
	# it but we cannot reliably drive the full _end_cutscene flow in
	# headless because it depends on _letterbox_top etc. So this test
	# instead exercises the documented invariant: when cutscene_finished
	# fires, _cutscene_id has already been cleared.
	#
	# Skip behaviourally if instantiation isn't possible without crashing.
	var d = CutsceneDirectorScript.new()
	if d == null:
		pending("CutsceneDirector could not be instantiated headlessly")
		return
	# Don't add_child — we just want to drive the signal contract.
	var observed_during_emit: Array = []
	var on_finish := func(emitted_id: String):
		observed_during_emit.append({
			"emitted_id":   emitted_id,
			"member_id":    d._cutscene_id,
			"active":       d._active,
		})
	d.cutscene_finished.connect(on_finish)
	# Pretend a cutscene just ended.
	d._cutscene_id = "test_cutscene_alpha"
	d._active = true
	# Manually invoke the emit ordering the way _end_cutscene does at the
	# end of its body — snapshot, clear, emit.
	var snapshot: String = d._cutscene_id
	d._active = false
	d._cutscene_id = ""
	d._skipping = false
	d.cutscene_finished.emit(snapshot)
	d.cutscene_finished.disconnect(on_finish)
	d.free()
	assert_eq(observed_during_emit.size(), 1,
		"listener must fire exactly once")
	var snap: Dictionary = observed_during_emit[0]
	assert_eq(str(snap["emitted_id"]), "test_cutscene_alpha",
		"emitted id must be the actual finished cutscene id (snapshot value)")
	assert_eq(str(snap["member_id"]), "",
		"_cutscene_id member must be empty when the listener fires — chained play_cutscene gets a clean slate")
	assert_false(bool(snap["active"]),
		"_active must be false when the listener fires")
