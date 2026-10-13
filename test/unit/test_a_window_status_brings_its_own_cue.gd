extends GutTest

## A PRODUCER-BOUNDED guard, and the only shape that can work here — the argument is @cowir-ai's and
## the derivation is @cowir-overworld's, both from 2026-10-12.
##
## `_apply_vulnerability_window` applies a set of statuses and cues them. My own fix asserted the two
## cues that exist today, and measured: adding a THIRD `add_status` with no cue passes it 6/6. So the
## defect it cannot see is "a status added without its cue".
##
## ⛔ NO RUNTIME ARM CAN COVER THAT. The consumer's input domain is bounded by the producer — the
## window only ever applies what this function writes — so a third status is not an input I failed to
## supply, it DOES NOT EXIST until someone edits the function. Driving one means stubbing the
## producer, i.e. testing a fiction. The only instrument left is a static assertion that the set
## PRODUCED is a subset of the set CUED, which is what this file does.
##
## ⚠️ This reads source, which is the thing I spent today arguing against — so the distinction
## matters: it does not pin a SPELLING, it derives BOTH sides from the same text and asserts a
## relation between them. A hand-list of the two statuses would be useless, because whoever adds a
## third would add it to the list in the same edit (@cowir-overworld's point about the fifth reason).
##
## ⚠️ And the window is bounded at the FUNCTION'S END, never by a character count: a fixed-width
## `substr` reds on an unrelated insertion and names the wrong file (@cowir-music measured 24 of
## those today, one of which her own change tripped).

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const BM_PATH := "res://src/battle/BattleManager.gd"
const FN := "func _apply_vulnerability_window"
## Returned for an argument that is not a string literal. Must not collide with any real literal.
const UNREADABLE := "\u0000<unreadable>"


## Body from the function header to the NEXT top-level `func`, so an insertion cannot push the
## subject out of range.
func _window_body() -> String:
	var src: String = GdSource.code_of(BM_PATH)
	var at: int = src.find(FN)
	if at < 0:
		return ""
	var nxt: int = src.find("\nfunc ", at + FN.length())
	return src.substr(at, (nxt - at) if nxt > at else -1)


## The FIRST argument of each call, or "" when it is not a string literal.
## ⛔ This used to take "the next quote anywhere after the call", which is not a parse. @cowir-music
## predicted a variable call would evade it; measured, the failure was worse than evasion — on
## `p.add_status(extra, 2)` it reached forward to `p.has_signal("ap_changed")` and reported
## "the window applies 'ap_changed'". A correct VERDICT with a wrong SUBJECT, and the mirror case
## (a reached-forward string that happens to BE cued) is a silent false clean.
func _first_args(body: String, call: String) -> Array:
	var out: Array = []
	var i: int = body.find(call)
	while i >= 0:
		var j: int = i + call.length()
		while j < body.length() and body[j] == " ":
			j += 1
		if j < body.length() and body[j] == "\"":
			var b: int = body.find("\"", j + 1)
			out.append(body.substr(j + 1, b - j - 1) if b > j else "")
		else:
			## ⛔ A DISTINCT SENTINEL, not "". @cowir-overworld's refusal fired on `return ""` because an
			## empty LITERAL and an unreadable argument shared a value — "I found nothing" and "I cannot
			## read this" must never be the same answer. add_status("") is readable and simply empty.
			out.append(UNREADABLE)
		i = body.find(call, i + call.length())
	return out


## ⛔ THE ONE LAYER THIS WHOLE FILE RESTS ON, pinned THROUGH THE ACCESSOR IT PROTECTS. Every verdict
## here compares statuses PRODUCED against cues FIRED, both read out of BattleManager AS TEXT, and
## prose is not input only because `_window_body` goes through GdSource. Swap it for a raw
## FileAccess.get_file_as_string and a commented-out play_status_if_authored("status_x") WIDENS the
## cued set, so a genuinely uncued status reads as covered.
##
## ⚠️ MEASURED SCOPE, because the first version of this arm asserted about `code_of` DIRECTLY and so
## stayed green through exactly the swap it claimed to catch — a guard scoped to the helper instead
## of to its caller. It now slices the SAME range from the raw file and compares, so the stripped
## side is whatever `_window_body` actually returns.
##
## 📌 And the hazard is NARROWER than it first looks, which is worth stating rather than overclaiming:
## a prose-named cue that is NOT authored already reds test_every_cue_the_window_fires_is_authored
## (measured — that is the arm that fires under the swap). The genuinely SILENT case is a prose
## mention of an AUTHORED key, and this arm is what stands in front of it.
func test_the_body_this_guard_reads_has_had_its_prose_stripped() -> void:
	var raw: String = FileAccess.get_file_as_string(BM_PATH)
	assert_false(raw.is_empty(), "CONTROL: the raw file must be readable, else neither side means anything")
	var at: int = raw.find(FN)
	assert_gt(at, -1, "CONTROL: the function must be findable in the RAW text too")
	if at < 0:
		return
	var nxt: int = raw.find("\nfunc ", at + FN.length())
	var raw_body: String = raw.substr(at, (nxt - at) if nxt > at else -1)
	var raw_comments: int = 0
	for ln in raw_body.split("\n"):
		if ln.strip_edges().begins_with("#"):
			raw_comments += 1
	assert_gt(raw_comments, 0,
		"CONTROL: the raw window body must actually carry comment lines, else a clean strip proves nothing")
	assert_true(raw_body.contains("\"\"\""),
		"CONTROL: and a docstring region, else the parity half of the strip is untested here")
	var body: String = _window_body()
	var left: int = 0
	for ln in body.split("\n"):
		if ln.strip_edges().begins_with("#"):
			left += 1
	assert_eq(left, 0,
		"the body THIS GUARD reasons about must carry no comment lines — %d survived, so prose is input and a comment can widen the cued set" % left)
	assert_false(body.contains("\"\"\""),
		"nor any docstring fence — a surviving region means the parity split did not run on what this guard reads")


## WHY that strip is load-bearing, demonstrated on one input rather than asserted — and the two
## shapes need DIFFERENT machinery, which is the trap. `strip_comments` is a line pass and cannot
## touch a `"""` region; only the parity split in `split()` can, and `code_of` is
## `split(...)["code"]` for exactly that reason. I reached for `strip_comments` first because the
## NAME sounds like the whole job: it passes the `#` case and leaves the docstring cue standing.
## So this arm pins that `code_of` must never be "simplified" to the `#`-only pass — the helper's
## own header records that same reduction as this lane's `.325` defect.
func test_a_cue_named_only_in_prose_is_not_a_fired_cue() -> void:
	var hash_form: String = "func _a():\n\t## play_status_if_authored(\"status_slowed\")\n\tp.add_status(\"slowed\", 2)\n"
	var doc_form: String = "func _b():\n\t\"\"\"\n\tplay_status_if_authored(\"status_frozen\")\n\t\"\"\"\n\tp.add_status(\"frozen\", 2)\n"
	for pair in [[hash_form, "slowed", "status_slowed", "# comment"], [doc_form, "frozen", "status_frozen", "docstring"]]:
		var text: String = str(pair[0])
		var status: String = str(pair[1])
		var cue: String = str(pair[2])
		var shape: String = str(pair[3])
		assert_true(str(status) in _first_args(text, "add_status("),
			"CONTROL (%s): the REAL add_status must be visible to the extractor, else this input tests nothing" % shape)
		assert_true(str(cue) in _first_args(text, "play_status_if_authored("),
			"CONTROL (%s): on RAW text the prose cue IS counted — the hazard must be reproducible here, or the arm below proves nothing" % shape)
		var code_half: String = str(GdSource.split(text)["code"])
		assert_false(str(cue) in _first_args(code_half, "play_status_if_authored("),
			"through the accessor this guard actually uses, a cue named only in a %s must NOT count as fired" % shape)
	## The reduction that would silently reopen it, named as its own assertion rather than left to
	## the comment above: the `#`-only pass is NOT sufficient for a docstring.
	assert_true("status_frozen" in _first_args(GdSource.strip_comments(doc_form), "play_status_if_authored("),
		"strip_comments is a LINE pass — if this ever stops counting the docstring cue it has gained region handling, and the note above is stale")


## CONTROL, must pass on both trees: the body is found and is not the whole file. Without it every
## assertion below is about an empty string.
func test_control_the_window_body_is_isolated() -> void:
	var body: String = _window_body()
	assert_ne(body, "", "the function must be found by name")
	assert_true(body.begins_with(FN), "the body starts at the header")
	## DERIVED, and the literal it replaces was INERT: it named `_execute_group_action`, which sits 387
	## lines EARLIER in the file, so a range starting at this function could never contain it. The one
	## assertion whose job was the range's END could not fail. Measured: break the close anchor and
	## three SUBJECT arms red while that control stayed green — coverage without the explanation.
	## A second `func ` header inside the range is the defect itself, whoever happens to follow.
	assert_false(body.contains("\nfunc "),
		"the range must hold ONE function — a second header means the close anchor over-ran")
	assert_gt(body.length(), 200, "and is not truncated to nothing")


## The property: every status this window APPLIES must also be CUED by it.
func test_every_status_the_window_applies_is_cued() -> void:
	var body: String = _window_body()
	if body == "":
		fail_test("no body; the control arm says why")
		return
	var applied: Array = _first_args(body, "add_status(")
	var cued: Array = _first_args(body, "play_status_if_authored(")
	assert_gt(applied.size(), 0, "PRECONDITION: the window must apply at least one status")
	for s in applied:
		assert_true(cued.has("status_" + str(s)),
			"the window applies '%s' but never cues status_%s — a status added without its cue is silent, which is the defect this file exists for" % [s, s])


## And every cue it fires must be authored, or the call is a no-op that reads as covered.
func test_every_cue_the_window_fires_is_authored() -> void:
	var body: String = _window_body()
	if body == "":
		fail_test("no body")
		return
	var f := FileAccess.open("res://data/sfx_manifest.json", FileAccess.READ)
	assert_not_null(f, "manifest readable")
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}
	var cued: Array = _first_args(body, "play_status_if_authored(")
	assert_gt(cued.size(), 0, "PRECONDITION: the window must cue something")
	for key in cued:
		assert_true(sfx.has(str(key)),
			"%s is cued by the window but not authored — play_status_if_authored would return false and the cue is silent" % str(key))


## @cowir-music's gap, and the reason it is not merely a sibling's problem: `produced ⊆ cued` is
## VACUOUSLY TRUE over an empty set, so a function applying statuses only through variables reports
## clean. BattleManager:5228 already does exactly that — `target.add_status(entry["status"], ...)`.
## This window is all literals today, so the arm pins that rather than assuming it.
func test_every_status_in_the_window_is_nameable() -> void:
	var body: String = _window_body()
	if body == "":
		fail_test("no body; the control arm says why")
		return
	var applied: Array = _first_args(body, "add_status(")
	assert_gt(applied.size(), 0, "PRECONDITION: the window must apply at least one status")
	for s in applied:
		assert_ne(str(s), UNREADABLE,
			"this window applies a status through a variable or expression — the literal derivation cannot name it, so the subset check above would pass VACUOUSLY. Either keep the call literal or give this guard a different instrument.")


## THE EXTRACTOR'S OWN ARM. @cowir-ai's generalisation, from the defect three lanes found in the
## first version of this file: a derived-relation guard has TWO failure modes and only one usually
## gets an arm — the RELATION it asserts, and the DERIVATION that feeds it. Every arm above trusts
## `_first_args`. This one tests it, against the exact shape that broke it: an unbounded quote search
## imported `"unrelated"` from a later line and reported it as an applied status.
func test_the_extractor_reads_first_arguments_not_the_next_quote() -> void:
	var fixture: String = "\tp.add_status(\"exposed\", 2)\n" \
		+ "\tp.add_status(wrong, 2)\n" \
		+ "\tif x:\n\t\tprint(\"unrelated\")\n" \
		+ "\tp.add_status( \"spaced\" , 1)\n"
	var got: Array = _first_args(fixture, "add_status(")
	assert_eq(got.size(), 3, "one entry per CALL, including the one it cannot read")
	if got.size() != 3:
		return
	assert_eq(str(got[0]), "exposed", "a literal first argument is read")
	assert_eq(str(got[1]), UNREADABLE,
		"a VARIABLE argument is an explicit unknown — not skipped, and NOT the next quote in the text ('unrelated'), which is the bug this pins")
	assert_eq(str(got[2]), "spaced", "whitespace between the paren and the literal does not defeat it")
	## And the distinction @cowir-overworld's refusal missed one level down: an EMPTY literal is
	## readable, and must not be reported as unreadable.
	var empty_case: Array = _first_args("\tp.add_status(\"\", 1)\n", "add_status(")
	assert_eq(empty_case.size(), 1, "one call")
	if empty_case.size() == 1:
		assert_eq(str(empty_case[0]), "", "an empty literal reads as empty — NOT as unreadable")
