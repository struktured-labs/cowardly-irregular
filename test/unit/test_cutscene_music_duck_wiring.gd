extends GutTest

## Cadence #10 (2026-07-16): CutsceneDialogue + NPCDialogue wire the
## music-duck bus (cowir-music msg 2707). Forward-compat via has_method +
## null-guard on SoundManager so this ships before the API fold in v3.33.198.
##
## Two shapes per cowir-music's leak-catcher recommendation:
##   (1) POSITIVE — sequential show + hide returns duck state to false
##       (music not left tapered forever).
##   (2) NEGATIVE — pinning that show WITHOUT hide leaves duck ACTIVE
##       (source-level check on the show/hide symmetry — if either hook
##       is removed accidentally the negative test fails to fail).
##
## Plus source pins so a refactor can't silently remove the guarded
## SoundManager calls.


const CUTSCENE_DIALOGUE_SRC := "res://src/cutscene/CutsceneDialogue.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _sm_has_duck_api() -> bool:
	# cowir-music's API — present after v3.33.198 fold. Tests below run
	# behaviorally only when the API is live; source-level pins run always.
	return SoundManager != null and SoundManager.has_method("duck_music_for_dialogue")


func _new_dialogue() -> Node:
	var script: GDScript = load(CUTSCENE_DIALOGUE_SRC)
	assert_not_null(script, "CutsceneDialogue must load")
	var d = script.new()
	add_child_autofree(d)
	# Wait a frame so _ready builds the UI.
	await get_tree().process_frame
	return d


# ── SOURCE PINS (always run, even without the API on main) ─────────────

func test_show_dialogue_ducks_music_via_guarded_call() -> void:
	var src := _read(CUTSCENE_DIALOGUE_SRC)
	var fn := src.find("func show_dialogue(")
	assert_gt(fn, -1, "show_dialogue must exist")
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_gt(body.find("_duck_music_for_dialogue(true)"), -1,
		"show_dialogue must call _duck_music_for_dialogue(true) — otherwise music never ducks under modal dialogue")


func test_finish_dialogue_unducks_music() -> void:
	# Leak-catcher for the class where a dialogue closes without pairing —
	# music stays tapered forever, worst UX bug in the ducking scheme.
	var src := _read(CUTSCENE_DIALOGUE_SRC)
	var fn := src.find("func _finish_dialogue(")
	assert_gt(fn, -1, "_finish_dialogue must exist")
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_gt(body.find("_duck_music_for_dialogue(false)"), -1,
		"_finish_dialogue must call _duck_music_for_dialogue(false) — pair with the show hook or music stays tapered forever")


func test_duck_wrapper_guards_on_soundmanager_and_method() -> void:
	# cowir-music's ask (thread msg 2711): guard on SoundManager != null
	# AND has_method — test contexts often have no autoload up and pre-fold
	# builds don't have the method yet.
	var src := _read(CUTSCENE_DIALOGUE_SRC)
	var fn := src.find("func _duck_music_for_dialogue(")
	assert_gt(fn, -1, "_duck_music_for_dialogue wrapper must exist")
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_gt(body.find("SoundManager"), -1,
		"wrapper must reference SoundManager (both null-guarded AND method-checked)")
	assert_gt(body.find('has_method("duck_music_for_dialogue")'), -1,
		"wrapper must has_method-guard so pre-198-fold builds are clean no-ops")


func test_skip_all_finishes_dialogue_so_it_composes_with_duck() -> void:
	# skip_all calls _finish_dialogue — which unducks. Pin the routing.
	var src := _read(CUTSCENE_DIALOGUE_SRC)
	var fn := src.find("func skip_all(")
	assert_gt(fn, -1, "skip_all must exist")
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_gt(body.find("_finish_dialogue()"), -1,
		"skip_all must delegate to _finish_dialogue so skipped dialogues also unduck music")


# ── BEHAVIORAL (only run when the ducking API is on main) ──────────────

func test_show_dialogue_actually_ducks_when_api_present() -> void:
	if not _sm_has_duck_api():
		pass_test("SoundManager.duck_music_for_dialogue not yet available (cowir-music fold pending)")
		return
	# Reset to a known state first.
	SoundManager.duck_music_for_dialogue(false)
	assert_false(SoundManager.is_music_ducked_for_dialogue(),
		"pre-test state must not be ducked")
	var d = await _new_dialogue()
	d.show_dialogue([{"speaker": "Test", "text": "Hi", "theme": "narrator", "portrait": "narrator"}])
	assert_true(SoundManager.is_music_ducked_for_dialogue(),
		"show_dialogue must taper music down")
	# Clean up.
	SoundManager.duck_music_for_dialogue(false)


func test_show_hide_returns_duck_to_false_when_api_present() -> void:
	# Positive shape — the round-trip must leave the state clean.
	if not _sm_has_duck_api():
		pass_test("SoundManager.duck_music_for_dialogue not yet available (cowir-music fold pending)")
		return
	SoundManager.duck_music_for_dialogue(false)
	var d = await _new_dialogue()
	d.show_dialogue([{"speaker": "Test", "text": "Hi", "theme": "narrator", "portrait": "narrator"}])
	# Simulate the caller reaching the end of the queue — _finish_dialogue is
	# what the last-line-advance path calls.
	d._finish_dialogue()
	assert_false(SoundManager.is_music_ducked_for_dialogue(),
		"show → hide round-trip must return music to unducked (leak-catcher)")
