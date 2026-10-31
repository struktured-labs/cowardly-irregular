extends GutTest

## struktured, 2026-10-26: three sub-final bosses, "one for automated gamers, one for classic games,
## one for one shotters", ROUTED by how the player actually played. TrialRouting decides which.
##
## ⛔ THE CONSTRAINT THIS FILE EXISTS FOR: CutsceneDirector._detect_playstyle() returns five labels
## and world6_chapter3 branches on the four canon ones to pick one of the game's FOUR ENDINGS. Adding
## a fifth label for the one-shot build would leave an unhandled branch and could cost a player their
## ending, so the trial decision CONSUMES that answer and never extends it. Arm 1 pins the label set
## so a later lane cannot quietly add one; arm 2 pins that every label still reaches a trial.

const DIRECTOR_PATH := "res://src/cutscene/CutsceneDirector.gd"

## The five labels _detect_playstyle can return, measured 2026-10-26. Named here so a SIXTH reds with
## the list in front of the reader rather than as a bare count.
const KNOWN_PLAYSTYLES: Array[String] = ["automator", "manual", "grinder", "exploiter", "balanced"]


## Every `return "..."` inside _detect_playstyle's own body, bounded at both ends.
func _playstyle_returns() -> Array:
	var src: String = FileAccess.get_file_as_string(DIRECTOR_PATH)
	var start: int = src.find("func _detect_playstyle(")
	if start < 0:
		return []
	var end: int = src.find("\nfunc ", start + 1)
	var body: String = src.substr(start, (end - start) if end > start else -1)
	var out: Array = []
	var rx := RegEx.new()
	rx.compile('return "(\\w+)"')
	for m in rx.search_all(body):
		var v: String = m.get_string(1)
		if not out.has(v):
			out.append(v)
	return out


func test_the_playstyle_label_set_is_unchanged() -> void:
	## THE CONTRACT. If this reds, someone added or renamed a playstyle — check world6_chapter3's
	## branches BEFORE updating this list, because an unhandled label is a player with no ending.
	var found := _playstyle_returns()
	assert_gt(found.size(), 3, "the derivation must find _detect_playstyle's returns (got %s)" % str(found))
	found.sort()
	var want: Array = KNOWN_PLAYSTYLES.duplicate()
	want.sort()
	assert_eq(found, want,
		"_detect_playstyle's label set changed; the endings branch on it and the trial routing consumes it: " + str(found))


func test_every_playstyle_reaches_exactly_one_trial() -> void:
	## TOTALITY, derived from the director rather than from my list, so a new label is routed the day
	## it lands instead of falling through to nothing.
	var trials: Array[String] = [TrialRouting.TRIAL_AUTOMATION, TrialRouting.TRIAL_CLASSIC, TrialRouting.TRIAL_BURST]
	var seen := {}
	for ps in _playstyle_returns():
		var t: String = TrialRouting.trial_for(str(ps), 0, 0, 500)
		assert_true(trials.has(t), "playstyle '%s' routed to '%s', which is not one of the three trials" % [str(ps), t])
		seen[t] = true
	assert_true(seen.has(TrialRouting.TRIAL_AUTOMATION), "no playstyle reaches the automation trial, so it is unreachable content")
	assert_true(seen.has(TrialRouting.TRIAL_CLASSIC), "no playstyle reaches the classic trial")


func test_a_one_shot_build_outranks_its_delivery_method() -> void:
	## DELIBERATE ASYMMETRY: automation is HOW a player issues commands, a one-shot build is WHAT they
	## built, and a script that one-shots is still a one-shot build. The burst trial is also the one
	## such a player has never been tested by — they have skipped the second half of every fight.
	var t: String = TrialRouting.trial_for("automator", 40, 30, 100)
	assert_eq(t, TrialRouting.TRIAL_BURST,
		"an automator who one-shots deliberately must get the burst trial, not the automation one")
	## CONTROL: the same automator WITHOUT the build still gets automation.
	assert_eq(TrialRouting.trial_for("automator", 0, 0, 100), TrialRouting.TRIAL_AUTOMATION,
		"an automator with no one-shots must still reach the automation trial")


func test_the_burst_gate_is_a_build_and_not_a_knack() -> void:
	## BISECTED on each of the three conditions separately, so a single relaxed clause cannot pass
	## unnoticed. Post-.727 the formation still one-shots 13 of 50 monsters by design, which is exactly
	## why a count alone cannot be the test.
	var floor_n: int = int(TrialRouting.BURST_MIN_ONE_SHOTS)
	## (a) volume, one short and exactly at it
	assert_ne(TrialRouting.trial_for("manual", floor_n - 1, floor_n - 1, 10), TrialRouting.TRIAL_BURST,
		"one one-shot short of the floor must not count as a build")
	assert_eq(TrialRouting.trial_for("manual", floor_n, floor_n, 10), TrialRouting.TRIAL_BURST,
		"at the floor, with every one deliberate and a high share, it is a build")
	## (b) quality: plenty of one-shots, none of them S or A
	assert_ne(TrialRouting.trial_for("manual", 50, 0, 100), TrialRouting.TRIAL_BURST,
		"one-shots that never reached rank S or A are a party finishing fights, not a build")
	## (c) proportion: deliberate one-shots that are a rounding error against the wins
	assert_ne(TrialRouting.trial_for("manual", 10, 10, 100000), TrialRouting.TRIAL_BURST,
		"ten one-shots in a hundred thousand wins is a knack, not a habit")


func test_a_save_with_no_battles_still_decides_on_the_deliberate_count() -> void:
	## The zero-denominator path, which would otherwise divide by zero or silently answer CLASSIC.
	assert_eq(TrialRouting.trial_for("manual", 30, 30, 0), TrialRouting.TRIAL_BURST,
		"with no battle count to divide by, a deliberate one-shot record must still read as a build")
	assert_ne(TrialRouting.trial_for("manual", 30, 0, 0), TrialRouting.TRIAL_BURST,
		"...but not when none of them were deliberate")


func test_the_counts_come_from_the_records_the_engine_already_writes() -> void:
	## counts_from_save is the only part that touches a save, so it is tested against a fake rather
	## than a real one: ONLY rank S and A count as deliberate, and counts sum across monsters.
	var fake_save := _FakeSave.new()
	fake_save.one_shot_records = {
		"goblin": {"count": 5, "best_rank": "S", "best_setup": 1},
		"slime": {"count": 3, "best_rank": "A", "best_setup": 3},
		"bat": {"count": 7, "best_rank": "C", "best_setup": 9},
		"junk": "not a dictionary",
	}
	var fake_state := _FakeState.new()
	fake_state.battles = 40
	var c: Dictionary = TrialRouting.counts_from_save(fake_save, fake_state)
	assert_eq(int(c["one_shots"]), 15, "every record's count must be summed (5+3+7)")
	assert_eq(int(c["deliberate"]), 8, "only S and A are deliberate (5+3), never the rank-C seven")
	assert_eq(int(c["battles_won"]), 40, "the battle count must come from organic_battles_won()")
	## And it must not crash on a null save, which is what a fresh game hands it.
	var empty: Dictionary = TrialRouting.counts_from_save(null, null)
	assert_eq(int(empty["one_shots"]), 0, "a null save must read as zero, not as an error")


class _FakeSave extends RefCounted:
	var one_shot_records: Dictionary = {}


class _FakeState extends RefCounted:
	var battles: int = 0
	func organic_battles_won() -> int:
		return battles
