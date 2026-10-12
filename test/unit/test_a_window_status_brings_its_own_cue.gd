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


## CONTROL, must pass on both trees: the body is found and is not the whole file. Without it every
## assertion below is about an empty string.
func test_control_the_window_body_is_isolated() -> void:
	var body: String = _window_body()
	assert_ne(body, "", "the function must be found by name")
	assert_true(body.begins_with(FN), "the body starts at the header")
	assert_false(body.contains("\nfunc _execute_group_action"), "and stops before the next function")
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
