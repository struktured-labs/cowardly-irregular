extends GutTest

## The render smoke's wipe leg was bounded by ABSOLUTE PROCESS AGE and reported two different
## outcomes with one message.
##
## Measured 2026-10-12 at load 23.84 on 24 cpus: the leg reached its wait at process age 87.3s,
## spent the remaining 192.7s of the 280s deadline with rounds advancing the whole time, produced no
## game over, and printed `game_over screen never appeared by 280s process age`. That reads as a
## game-over REGRESSION and it was a slow box — the same substitution CLAUDE.md records for exit
## 124, where a WEDGE and a RED are both non-zero and the wrong one sends you to fix the tree.
##
## 🔑 THE ORDER OF THE CHECKS IS THE SEMANTICS, which is why this guard exists rather than a
## comment. A frozen battle and a slow box both end the leg without a screen; only `stalled` before
## `budget` keeps a frozen battle from being excused as slowness. Reverse the two and the smoke
## reports a real stall as "a slow box, not a missing game over" — green-looking prose over a bug.
##
## 📌 NO FLOOR ARM HERE, DELIBERATELY. Every call below goes through a preloaded const
## (`GameLoopScript.smoke_wipe_verdict`), which GDScript resolves at PARSE time — renaming the
## static does not make an arm vacuous, it drops the whole script and `run_tests.sh` exits 3,
## NOT ALL TEST FILES RAN. That is louder than a floor, so a floor would be dead code; CLAUDE.md's
## call-shape table says exactly this, and I confirmed it by hitting the parse error twice while
## trying to write the floor against a class you cannot call instance methods on.
##
## `smoke_wipe_verdict` is STATIC and pure for one reason: no test can instantiate GameLoop (three
## existing files assert `get_tree().root.get_node_or_null("GameLoop")` is null), so a decision left
## inside the await loop would be unreachable from here and provable only by running the whole smoke.

const GameLoopScript := preload("res://src/GameLoop.gd")

const BUDGET := 90000
const STALL := 25000
const GRACE := 15000

## -1 for since_inactive_ms means the battle is still live.
func _verdict(elapsed_ms: int, since_progress_ms: int, since_inactive_ms: int) -> String:
	return GameLoopScript.smoke_wipe_verdict(elapsed_ms, since_progress_ms, since_inactive_ms,
		BUDGET, STALL, GRACE)


func test_a_running_battle_making_progress_keeps_waiting() -> void:
	assert_eq(_verdict(1000, 0, -1), "",
		"CONTROL: a fresh, advancing battle must not trip any bound, or every arm below is free")
	assert_eq(_verdict(BUDGET - 1, STALL - 1, -1), "",
		"one millisecond inside both bounds is still waiting — the leg may not end early")


func test_a_battle_that_ended_without_a_screen_is_a_real_bug() -> void:
	assert_eq(_verdict(1000, 0, GRACE), "ended_without_game_over",
		"the battle finished, the grace window passed, and no GameOverScreen came up; that is the defect")
	assert_eq(_verdict(BUDGET + 9999, STALL + 9999, GRACE + 1), "ended_without_game_over",
		"an ended battle outranks both clocks — reporting it as a slow box would hide a real bug")


func test_a_frozen_battle_reports_stalled() -> void:
	assert_eq(_verdict(1000, STALL, -1), "stalled",
		"no round advanced for the stall window while the battle is live — progress stopped")


## The arm that pins the ORDER. Both bounds are tripped at once; `stalled` must win.
func test_a_frozen_battle_is_never_excused_as_a_slow_box() -> void:
	var both: String = _verdict(BUDGET + 1, STALL + 1, -1)
	assert_eq(both, "stalled",
		"with BOTH bounds tripped the verdict must be 'stalled': a frozen battle reported as " +
		"'budget' tells the reader their box is slow when the game is wedged")


func test_a_slow_box_is_not_reported_as_a_missing_game_over() -> void:
	assert_eq(_verdict(BUDGET, STALL - 1, -1), "budget",
		"rounds still advancing and the leg outran its budget — that is a slow box, and saying so " +
		"is the whole point of the change")


## The bounds must be RELATIVE to the leg, not an absolute process age: the old form shrank by every
## second any upstream leg spent, so adding a world leg silently stole from this one.
func test_the_bounds_are_relative_to_the_leg_not_the_process() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_ne(src, "", "CONTROL: GameLoop.gd must be readable or this arm proves nothing")
	assert_false(src.contains("SMOKE_WIPE_DEADLINE_MS"),
		"the absolute-process-age deadline is back; it cannot bound a leg whose start time varies")
	assert_true(src.contains("var leg_start: int = Time.get_ticks_msec()"),
		"the wait must timestamp its own start, so its budget is its own")
	assert_true(src.contains("SMOKE_VERDICT_FLOOR_MS"),
		"the verdict must still be clamped to print before deploy_web.sh's outer timeout 300")


## ⛔ THE ARM THAT PINS THE RACE MY FIRST VERSION SHIPPED. The GameOverScreen is added SEVERAL
## FRAMES AFTER the battle goes INACTIVE, so concluding at the first inactive poll calls a correctly
## wiped party a missing screen. The real smoke printed "ended at round 5 with no game over screen"
## one line after the engine logged "=== DEFEAT ===". My unit arms PASSED through that, because they
## asserted the same wrong model the code had — a guard written from the author's belief tests the
## belief. Only the end-to-end run disagreed.
func test_an_ended_battle_is_given_the_grace_the_defeat_sequence_needs() -> void:
	assert_eq(_verdict(1000, 0, 0), "",
		"the battle has only just gone inactive — the defeat sequence has not had a frame yet")
	assert_eq(_verdict(1000, 0, GRACE - 1), "",
		"one millisecond inside the grace window must still be waiting for the screen")
	assert_eq(_verdict(1000, 0, GRACE), "ended_without_game_over",
		"and the grace window must END, or a genuinely missing screen waits forever")


## A battle that goes inactive INSIDE the grace must not be judged by the fighting-side bounds:
## the stall clock keeps ticking once rounds stop, so without the inactive branch first, a normal
## defeat would be reported as a stall 25s later.
func test_an_ended_battle_is_not_reported_as_a_stall() -> void:
	assert_eq(_verdict(1000, STALL + 9999, 1), "",
		"rounds stopped because the battle ENDED; that is not a stall and must not be called one")


## ⛔ EVERY REASON THE VERDICT CAN RETURN MUST HAVE A BRANCH THAT PRINTS IT, and the list is DERIVED
## from the verdict function's own `return` literals rather than written here — the defect being
## guarded is that someone adds a fifth reason and not a fifth message, which a hand-list cannot
## see because they would add to the list in the same edit.
##
## 🔑 AND A STATIC DERIVATION IS NOT MERELY THE STRONGER CHOICE HERE, IT IS THE ONLY ONE THAT CAN
## APPLY (@cowir-ai, 2026-10-12, sharpening this guard's own justification). THE CONSUMER'S INPUT
## DOMAIN IS CLOSED BY THE PRODUCER: `smoke_wipe_verdict` emits exactly these tokens, so the
## dispatch can only ever receive one of them. **A fifth reason is not an input somebody forgot to
## try — it does not exist until the producer is edited**, so no runtime arm, however carefully its
## inputs are chosen, can reach the unbranched case. Driving an unknown token would mean stubbing
## the producer, i.e. asserting against a fiction. `producer returns ⊆ consumer branches`, checked
## in the source, is the whole instrument available for this class.
##
## The leg shipped in .658 with a `match` that had NO default arm: a reason with no branch printed
## nothing, and the two lines after the match still set `_smoke_failed` and returned — so the gate
## would have reported a bare `VERDICT: FAIL` with the explanation missing. That is the exact defect
## this leg exists to remove, reintroduced by the leg's own dispatch. @cowir-sfx measured the same
## shape as a classifier MISFILING a third kind of print; @cowir-deploy's tool LOST it instead;
## generalised: a branch set with no else does not handle the next kind safely, it fails silently.
func test_every_reason_the_verdict_returns_has_a_branch_that_prints_it() -> void:
	var src := FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_ne(src, "", "CONTROL: GameLoop.gd must be readable")

	var vat := src.find("static func smoke_wipe_verdict")
	assert_gt(vat, -1, "CONTROL: the verdict function must exist")
	## `"\nfunc "` alone is BLIND to `static func`, so a static added after the verdict was absorbed
	## into its region: 7 returns scanned, 5 readable, and this arm's refusal fired on a clean tree
	## (.706). Take whichever boundary comes first -- the refusal below is right, the window was not.
	var vend := src.find("\nfunc ", vat + 10)
	var vstatic := src.find("\nstatic func ", vat + 10)
	if vstatic > -1 and (vend < 0 or vstatic < vend):
		vend = vstatic
	assert_gt(vend, vat, "CONTROL: the verdict function ends before the next one")
	var verdict := src.substr(vat, vend - vat)

	## ⛔ THE EXTRACTOR MUST REFUSE WHAT IT CANNOT READ, not silently return fewer members.
	## @cowir-ai's point, measured here: a derived-relation guard has TWO failure modes and only the
	## RELATION is ever tested — nobody points an arm at the DERIVATION. Planted `return
	## _stall_token()` in the producer and this scan reported the same three reasons as before,
	## having silently skipped a fourth. **"I found no member" and "I cannot read this" must not
	## share a value**, because the first is a fact and the second is an absence of one.
	##
	## ⚠️ Two behavioural arms above DID catch that plant, because it changed a (input -> reason)
	## pair they assert — so this file was safer than @cowir-battle's and @cowir-ai's cases, whose
	## consumers are only reachable through production code. It was NOT safe: a fifth reason added
	## on an input branch no arm drives would be invisible to both halves.
	var total_returns: int = 0
	for line in verdict.split("\n"):
		if str(line).strip_edges().begins_with("return "):
			total_returns += 1
	## `[a-z_]*` not `+`: the "keep waiting" return is `return ""`, a LITERAL with an empty token.
	## With `+` the scan read 3 of 4 returns and this very assertion red on a clean tree — my own
	## refusal firing on the shape it was meant to allow. An empty capture is READABLE and is simply
	## not a reason, which is a different fact from "I could not parse this".
	var re := RegEx.create_from_string('return "([a-z_]*)"')
	var reasons: Array = []
	var readable: int = 0
	for m in re.search_all(verdict):
		readable += 1
		if m.get_string(1) != "" and not reasons.has(m.get_string(1)):
			reasons.append(m.get_string(1))
	reasons.sort()
	assert_eq(readable, total_returns,
		"the verdict has %d return statement(s) and this scan could read %d as literals — the " % [total_returns, readable] +
		"unreadable one(s) are reasons with no branch requirement, so the arm below would pass " +
		"while a reason went unbranched. Make the return a literal, or teach this extractor the shape")
	assert_gte(reasons.size(), 3,
		"CONTROL: derived only %d reasons from the verdict function — the scan is broken and the [] below is free: %s" % [
			reasons.size(), str(reasons)])
	gut.p("  reasons the verdict can return: %s" % ", ".join(reasons))

	var lat := src.find("match _smoke_wipe_reason:")
	assert_gt(lat, -1, "the wait must dispatch on the reason")
	var lend := src.find("_smoke_failed = true", lat)
	assert_gt(lend, lat, "CONTROL: the dispatch ends before the failure is recorded")
	var dispatch := src.substr(lat, lend - lat)

	var unbranched: Array = []
	for reason in reasons:
		if not dispatch.contains('"%s":' % reason):
			unbranched.append(str(reason))
	unbranched.sort()
	assert_eq(unbranched, [],
		"these reasons can be returned and have no branch that prints them, so the smoke would fail " +
		"with no explanation: %s" % ", ".join(unbranched))

	assert_true(dispatch.contains("_:"),
		"the dispatch must have a DEFAULT arm; without one the NEXT reason added fails silently, " +
		"which is the defect this leg was written to remove")

