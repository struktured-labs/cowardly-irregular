extends GutTest

## `SaveSystem.load_failed` was declared with a `reason: String` payload and emitted two fixed
## strings to NOBODY — zero listeners anywhere in src/, which is the state `save_failed` was in
## before tick 76 wired it to a toast. One site fixed, the sibling left.
##
## And the reasons it was not carrying had already been computed. `_read_save_file` diagnoses
## three distinct failures — the file would not open, the JSON would not parse, the root is not
## an object — pushes each to `push_warning`, and returns `{}`. `load_game` collapsed all three
## into "Failed to read save file" and told no one. Tick 181's own comment in that function says
## what it costs: "load silently returned {} which the title-screen CONTINUE button treated as
## 'no save'; player saw their save disappear with no hint why."
##
## ⛔ THE LIVE DEFECT IS ONE BRANCH IN `GameLoop._show_game_over_screen`. Its Continue arm did:
##
##     if not (loaded and _restore_party_from_save_data()):
##         _create_party()
##
## with no message of any kind. `_title_load_slot` — the TITLE screen's Continue, the same
## fallback one function over — already calls that a UX trap in words: "the player clicks
## Continue expecting to resume, gets a brand-new party with no explanation, and assumes their
## progress is gone." That repair reached the title screen and not the game-over screen.
##
## The game-over one is worse. `show_game_over(has_save)` only OFFERS Continue when a save
## exists, so the player picked it knowing one is there, having just been wiped, and landed in a
## fresh game with nothing anywhere saying the save is still on disk.
##
## ⚠️ WHAT THIS FILE WILL NOT DO. `SAVE_DIR` is a `const`, not a redirectable static var, so a
## behavioural test of the unreadable-file exits would have to write a deliberately corrupt file
## into `user://saves/` — the player's own save directory, in whichever worktree runs the suite.
## It does not. The missing-slot exit needs no writes and is exercised for real; the three
## `_read_save_file` exits are covered by shape, behind a floor and a control.

const SAVE_SRC := "res://src/save/SaveSystem.gd"
const GAMELOOP_SRC := "res://src/GameLoop.gd"

## Far outside MAX_SAVE_SLOTS, so "does this slot exist" cannot accidentally be yes.
const ABSENT_SLOT := 87


func _require_reason_api(sys) -> bool:
	## ⛔ WITHOUT THIS, THE TWO BEHAVIOURAL ARMS GO GREEN BY ABORTING. Measured while mutating
	## this fix: with `last_load_reason()` removed, GDScript raises "Invalid call. Nonexistent
	## function" and the arm STOPS THERE — and GUT scored it **Passing**, because an arm that
	## already recorded one successful assert is not Risky and a runtime error does not mark it
	## failed. Two arms reported green while never reaching their assertions. So the absence of
	## the API has to be an ASSERTION, not a call that explodes.
	if sys.has_method("last_load_reason"):
		return true
	assert_true(false, "SaveSystem must expose last_load_reason() — this arm cannot run without it")
	return false


func _sys():
	var s = get_tree().root.get_node_or_null("SaveSystem")
	assert_not_null(s, "CONTROL: SaveSystem autoload must exist, or nothing below is a test")
	return s


func test_control_the_probe_slot_really_has_no_save() -> void:
	## The arm below is only a test of the REASON if the load genuinely fails, and it must fail
	## for the reason this file thinks. Pinned separately, and it writes nothing.
	var sys = _sys()
	if sys == null:
		return
	assert_false(sys.save_exists(ABSENT_SLOT),
		"CONTROL: slot %d must have no save file — otherwise the arm below tests a different exit"
		% [ABSENT_SLOT])


func test_a_missing_slot_names_the_slot_instead_of_failing_mutely() -> void:
	var sys = _sys()
	if sys == null:
		return
	if not _require_reason_api(sys):
		return
	assert_false(sys.load_game(ABSENT_SLOT), "precondition: a slot with no file must not load")
	var why: String = str(sys.last_load_reason())
	assert_ne(why, "",
		"a refused load must record a reason — '' is what let the game-over Continue fall back in silence")
	assert_true(why.find(str(ABSENT_SLOT)) != -1,
		"and it must name WHICH slot, since the caller picked it by number: '%s'" % [why])


func test_an_unopenable_file_names_the_open_failure_and_needs_no_writes() -> void:
	## The SECOND exit reachable without touching user://saves/: `_read_save_file` is called
	## directly, past load_game's `save_exists` pre-check, so FileAccess.open fails on a path
	## that is simply not there. Same diagnosis a player with an unreadable save gets, and this
	## arm creates nothing and deletes nothing.
	var sys = _sys()
	if sys == null:
		return
	if not _require_reason_api(sys):
		return
	assert_false(sys.save_exists(ABSENT_SLOT), "CONTROL: the probe slot must still have no file")
	var out: Dictionary = sys._read_save_file(ABSENT_SLOT)
	assert_true(out.is_empty(), "precondition: an absent file must read as empty")
	var why: String = str(sys.last_load_reason())
	assert_ne(why, "", "the open-failure exit must record a reason, not only push_warning it")
	assert_true(why.to_lower().find("open") != -1,
		"and it must say the file could not be OPENED, which is a different repair from a corrupt "
		+ "one: '%s'" % [why])


func test_the_reason_is_readable_through_the_public_accessor() -> void:
	## The accessor is the whole interface the UI uses; a private field nobody can read is the
	## defect in a different costume.
	var sys = _sys()
	if sys == null:
		return
	assert_true(sys.has_method("last_load_reason"),
		"SaveSystem must expose last_load_reason() — GameLoop._load_failure_reason calls it")


func test_a_later_load_does_not_inherit_an_earlier_refusals_reason() -> void:
	## load_game clears on entry. Without that, a successful Continue could be captioned by an
	## older failure — specific, plausible, and about a different slot.
	var sys = _sys()
	if sys == null:
		return
	if not _require_reason_api(sys):
		return
	sys.load_game(ABSENT_SLOT)
	assert_ne(str(sys.last_load_reason()), "", "precondition: the first load failed and set a reason")
	## A SECOND absent slot: the reason must be re-derived, not carried.
	sys.load_game(ABSENT_SLOT + 1)
	var why: String = str(sys.last_load_reason())
	assert_true(why.find(str(ABSENT_SLOT + 1)) != -1,
		"the second refusal must name the second slot, not repeat the first: '%s'" % [why])
	assert_false(why.find("slot %d " % ABSENT_SLOT) != -1,
		"the second refusal carried the first slot's reason: '%s'" % [why])


func _code_without_comments(path: String) -> String:
	## A source scan must look at CODE. This fix's comments QUOTE the sentences it replaced and
	## the `_create_party()` fallback it fixed, so a scan over raw text reads the retired shape as
	## still live. Measured twice on the share surface: two arms failed on their first run for
	## exactly this.
	var out: PackedStringArray = PackedStringArray()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if str(line).strip_edges().begins_with("#"):
			continue
		out.append(str(line))
	return "\n".join(out)


func test_control_the_comment_stripper_keeps_code_and_drops_comments() -> void:
	var code: String = _code_without_comments(SAVE_SRC)
	assert_gt(code.length(), 2000, "CONTROL: stripping comments must leave the code behind")
	assert_true(code.find("func load_game(") != -1, "CONTROL: code lines must survive")
	var raw_comments: int = 0
	for line in FileAccess.get_file_as_string(SAVE_SRC).split("\n"):
		if str(line).strip_edges().begins_with("#"):
			raw_comments += 1
	var left: int = 0
	for line in code.split("\n"):
		if str(line).strip_edges().begins_with("#"):
			left += 1
	assert_gt(raw_comments, 20, "CONTROL: the file must have comments to strip, found %d" % [raw_comments])
	assert_eq(left, 0, "CONTROL: %d comment line(s) survived, so the arms below measure the documentation" % [left])


func _body_of(code: String, signature: String) -> String:
	var start: int = code.find(signature)
	if start < 0:
		return ""
	var stop: int = code.find("\nfunc ", start + 1)
	var stop2: int = code.find("\nstatic func ", start + 1)
	if stop < 0 or (stop2 >= 0 and stop2 < stop):
		stop = stop2
	return code.substr(start, stop - start) if stop > start else code.substr(start)


func test_every_read_failure_records_which_failure_it_was() -> void:
	## Three exits, three different diagnoses, and load_game used to flatten them to one
	## sentence. Shape rather than behaviour because SAVE_DIR is a const (see the header).
	var code: String = _code_without_comments(SAVE_SRC)
	var body: String = _body_of(code, "func _read_save_file(")
	assert_ne(body, "", "CONTROL: _read_save_file must still be a func of that name")
	if body == "":
		return
	assert_true(body.find("json.parse(") != -1, "CONTROL: the extracted body must be _read_save_file's")
	assert_lt(body.length(), 4000, "CONTROL: the extraction must not have swallowed the rest of the file")

	var chunks: PackedStringArray = body.split("return {}")
	var exits: int = chunks.size() - 1
	assert_gt(exits, 2, "CONTROL: _read_save_file had three `return {}` exits; found %d" % [exits])
	if exits < 1:
		return
	var mute: Array = []
	for i in range(exits):
		if chunks[i].find("_last_load_reason = ") == -1:
			mute.append(i)
	assert_eq(mute, [],
		"these `return {}` exits (0-based) diagnose a failure and drop it, so load_game can only "
		+ "say 'could not be read': %s" % [str(mute)])


func test_both_load_game_refusals_carry_their_reason_on_the_signal() -> void:
	## load_failed's payload is the point of the signal. It emitted two fixed strings; a listener
	## added later would have inherited the same flattening.
	var code: String = _code_without_comments(SAVE_SRC)
	var body: String = _body_of(code, "func load_game(")
	assert_ne(body, "", "CONTROL: load_game must still be a func of that name")
	if body == "":
		return
	var emits: int = body.count("load_failed.emit(")
	assert_gt(emits, 1, "CONTROL: load_game had two load_failed emits; found %d" % [emits])
	assert_eq(body.count("load_failed.emit(_last_load_reason)"), emits,
		"every load_failed emit must carry the recorded reason, not a fixed string")
	assert_true(body.find("_last_load_reason = \"\"") != -1,
		"load_game must clear the reason on entry, or a later refusal inherits an older one")


func test_the_game_over_continue_fallback_is_not_silent() -> void:
	## THE LIVE DEFECT. Per branch, not per file: GameLoop reports on the title-screen Continue
	## and on quick-load, so a file-level scan was green while this branch said nothing.
	var code: String = _code_without_comments(GAMELOOP_SRC)
	var body: String = _body_of(code, "func _show_game_over_screen(")
	assert_ne(body, "", "CONTROL: _show_game_over_screen must still be a func of that name")
	if body == "":
		return
	assert_true(body.find("SaveSystem.load_game(") != -1,
		"CONTROL: the extracted body must contain the Continue load")
	var i: int = body.find("_restore_party_from_save_data()")
	assert_gt(i, -1, "CONTROL: the fallback condition must still be here")
	if i < 0:
		return
	var tail: String = body.substr(i)
	assert_true(tail.find("Toast.show_warning(") != -1,
		"the game-over Continue fallback must TELL the player it fell back — it creates a default "
		+ "party, which reads as 'my save is gone': %s" % [tail])
	assert_true(tail.find("_load_failure_reason(") != -1,
		"and it must name SaveSystem's own diagnosis rather than inventing one")


func test_control_the_title_screen_continue_still_reports() -> void:
	## The sibling that already had the fix, and the positive control for the scan above: without
	## it, a scan that can never find a Toast would report the branch above as green.
	var code: String = _code_without_comments(GAMELOOP_SRC)
	var body: String = _body_of(code, "func _title_load_slot(")
	assert_ne(body, "", "CONTROL: _title_load_slot must still be a func of that name")
	if body == "":
		return
	assert_true(body.find("Toast.show_warning(") != -1,
		"CONTROL: the title-screen Continue has reported since its own fix — if this is gone the "
		+ "scan is not looking at what it thinks")
	assert_true(body.find("_load_failure_reason(") != -1,
		"and it must now name the real diagnosis too, instead of 'save load failed (slot N)'")


func test_every_load_game_caller_in_gameloop_can_say_why() -> void:
	## Derived, so the next caller is judged without editing this arm. Per function, because each
	## of these both calls and reports.
	var code: String = _code_without_comments(GAMELOOP_SRC)
	var checked: int = 0
	var mute: Array = []
	for chunk in code.split("\nfunc "):
		if chunk.find("SaveSystem.load_game(") == -1:
			continue
		checked += 1
		if chunk.find("_load_failure_reason(") == -1 and chunk.find("last_load_reason()") == -1:
			mute.append(str(chunk.split("(")[0]).strip_edges())
	assert_gt(checked, 2, "CONTROL: expected at least three load_game callers, found %d" % [checked])
	assert_eq(mute, [], "these load a save and cannot tell the player why one did not: %s" % [str(mute)])
