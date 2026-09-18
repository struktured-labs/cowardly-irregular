extends GutTest

## `BattleTransition._await_tween_safe` exists for the 2026-09-06 spider wedge — a tween whose
## targets are freed mid-flight never emits `finished`. Its own comment says so. Its condition was
## `is_running()`, which is blind to exactly that death.
##
## Engine facts, measured rather than reasoned (2026-09-18):
##     freed target : is_running TRUE   is_valid FALSE   <- the wedge case
##     killed       : is_running FALSE  is_valid FALSE
##     live         : is_running TRUE   is_valid TRUE    <- control: the fix cannot shorten this
##     finished     : is_running FALSE  is_valid TRUE    <- control: already exited on is_running
##
## Not a wedge — the 6 s ceiling always terminated it — but six seconds of frozen transition on the
## one path the helper was written to protect.

const BT_SRC := "res://src/transitions/BattleTransition.gd"

## Shared, not a 13th private stripper. It is quote-AND-escape-aware and also splits `"""`
## docstrings, neither of which my own line-pass handled (cowir-controller, 2026-09-18).
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


func test_the_wait_condition_checks_validity_not_just_running() -> void:
	var src: String = GdSource.code_of(BT_SRC)
	assert_ne(src, "", "CONTROL: BattleTransition.gd must be readable")
	var at: int = src.find("func _await_tween_safe")
	assert_gt(at, -1, "CONTROL: _await_tween_safe must exist to be pinned")
	var after: int = src.find("\nfunc ", at + 1)
	## THE CODE HALF. Unstripped, this arm false-greened on the likeliest form of the defect — comment
	## the condition out, restore the pre-fix one beside it, and `is_valid()` is still "present"
	## (EC=0, Passing 5, six-second freeze back). ⛔ And `strip_comments` alone was NOT enough: it
	## removes `#` only, so a `"""` docstring naming is_valid() false-greened it too. Picking the
	## wrong half of the right helper is its own false green. Both measured 2026-09-18.
	var body: String = src.substr(at, (after - at) if after != -1 else -1)
	assert_true(body.contains("is_valid()"),
		"_await_tween_safe waits on is_running(), which stays TRUE forever for a tween whose target "
		+ "was freed — the exact death its own comment cites. Without is_valid() the loop runs to the "
		+ "6s deadline and freezes the transition for six seconds. 14 call sites.")


func test_a_freed_target_tween_really_does_keep_reporting_running() -> void:
	# The premise. If the engine ever changes this, the guard above is defending nothing.
	var n := Node2D.new()
	add_child_autofree(n)
	var t: Tween = n.create_tween()
	t.tween_property(n, "position", Vector2(500, 0), 10.0)
	await get_tree().process_frame
	n.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(is_instance_valid(t), "the Tween object itself survives its target")
	assert_true(t.is_running(), "PREMISE: a freed-target tween still reports is_running() — if this "
		+ "fails the engine changed and _await_tween_safe's extra term is now dead weight")
	assert_false(t.is_valid(), "PREMISE: is_valid() is the only tell for a freed target")


func test_a_live_tween_is_still_waited_on() -> void:
	# Control for the fix: is_valid() must be TRUE mid-flight, or adding it would make every one of
	# the 14 call sites return instantly and break the transitions it is meant to protect.
	var n := Node2D.new()
	add_child_autofree(n)
	var t: Tween = n.create_tween()
	t.tween_property(n, "position", Vector2(500, 0), 5.0)
	await get_tree().process_frame
	assert_true(t.is_valid(), "a live tween must read valid, else the new term short-circuits the wait")
	assert_true(t.is_running(), "and running")
	t.kill()


## ⛔ ARRIVAL, not departure. Everything above notices `is_valid()` LEAVING; nothing noticed a raw
## `await <tween>.finished` ARRIVING at a new call site, which is the same wedge with no ceiling —
## `finished` never emits at all, so the transition hangs forever rather than for six seconds.
##
## Scoped to THIS FILE on purpose. Measured 2026-09-18: 21 raw-await sites live in six other files
## and every one is safe by construction — the target is a child of the awaiter (target death
## implies awaiter death) or a local the awaiting function frees itself AFTER the await. A
## codebase-wide rule would red 21 correct sites.
##
## BattleTransition is the exception because `_cleanup_effects()` frees `_screen_rect` and LEAVES
## SELF ALIVE, and it has 4 callers — including a second transition arriving on top of a running
## one, which is precisely the case its own comment at :120 describes.
func _raw_tween_awaits(src: String) -> PackedStringArray:
	var re := RegEx.create_from_string("await\\s+[A-Za-z_][A-Za-z0-9_]*\\.finished")
	var found: PackedStringArray = PackedStringArray()
	for m in re.search_all(str(GdSource.split(src)["code"])):
		found.append(m.get_string())
	return found


func test_no_tween_is_awaited_raw_in_battle_transition() -> void:
	var src: String = FileAccess.get_file_as_string(BT_SRC)
	assert_ne(src, "", "CONTROL: BattleTransition.gd must be readable")
	var raw: PackedStringArray = _raw_tween_awaits(src)
	assert_eq(raw.size(), 0,
		"a tween here is awaited raw: %s. In THIS file _cleanup_effects() frees _screen_rect and " % str(raw)
		+ "leaves self alive, so `finished` can never emit and the await hangs with no deadline — "
		+ "strictly worse than the 6s freeze _await_tween_safe was written for. Route it through "
		+ "_await_tween_safe(tween) instead.")


func test_the_raw_await_detector_can_actually_fire() -> void:
	# A zero from an unexercised detector is worth nothing — the instrument watched saying YES.
	assert_eq(_raw_tween_awaits("\tawait tween.finished\n").size(), 1,
		"CONTROL: the detector must find a raw tween await, or the arm above is vacuous")
	assert_eq(_raw_tween_awaits("\tawait _await_tween_safe(tween)\n").size(), 0,
		"CONTROL: the sanctioned helper call must NOT be reported as a raw await")
	assert_eq(_raw_tween_awaits("\t## await tween.finished in a comment\n").size(), 0,
		"CONTROL: a comment mentioning the shape is not a call — this file's own :120 comment does")


func test_the_stripper_leaves_the_real_code_standing() -> void:
	## GdSource's header requires this of every caller: over-stripping and a correct strip are the
	## same green, so a presence arm that reads stripped source proves nothing until a known code
	## site is shown to survive. Both halves floored — an empty doc side passes by construction.
	var halves: Dictionary = GdSource.split(FileAccess.get_file_as_string(BT_SRC))
	var code: String = str(halves["code"])
	assert_gt(code.find("func _await_tween_safe"), -1,
		"CONTROL: the subject function must survive the strip, or every arm reading `code` is vacuous")
	assert_gt(code.find("await get_tree().process_frame"), -1,
		"CONTROL: a live statement inside that function must survive the strip too")
	assert_gt(str(halves["doc"]).length(), 0,
		"CONTROL: the doc half must be non-empty, else the split is not separating anything")
