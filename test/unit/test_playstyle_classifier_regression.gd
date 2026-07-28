extends GutTest

## _detect_playstyle drives `branch` steps with condition "playstyle" — and
## world6_chapter3.json authors FOUR of the game's endings against its return
## values. So an unreachable return is not a quirk, it is an ENDING THAT NEVER
## PLAYS.
##
## Two were dead (2026-07-28, found by @cowir-ai, sharpened by @cowir-battle):
##   * arms tested VOLUME before RATIO, so above 100 battles only "automator"
##     and "grinder" were reachable. A player who hand-played the entire game
##     got the grinder ending — a word about volume standing in for one about
##     style. @cowir-battle measured 2 of 5 reachable at 150 battles.
##   * "exploiter" was `total_battles < 40` with no other term, while its own
##     docstring claimed "low battles, high level — efficient". Level was
##     never consulted. So it fired for every ordinary early-game player: a
##     level-3 party twenty minutes in got the exploiter ending.
##
## Canon (@cowir-story) settles the shape rather than preference: three of the
## four branches are about PROPORTION, only "ground relentlessly" is a total.
## Hence ratio before volume, and exploitation as a categorical fact.
##
## THE INVARIANT THIS FILE DEFENDS: every value the classifier can name stays
## reachable. Thresholds are struktured's to tune — retuning must keep this
## green, and a retune that kills an arm kills an ending.

const DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"

var _saved_records = null
var _saved_battles: int = 0
var _saved_corruption: Array = []
var _saved_permakill: Array = []


func before_each() -> void:
	if SaveSystem:
		_saved_records = SaveSystem.autobattle_records
	if GameState:
		_saved_battles = GameState.battles_won
		_saved_corruption = GameState.corruption_effects.duplicate()
		_saved_permakill = GameState.permakilled_monster_types.duplicate()
		GameState.corruption_effects.clear()
		GameState.permakilled_monster_types.clear()


func after_each() -> void:
	if SaveSystem:
		SaveSystem.autobattle_records = _saved_records
	if GameState:
		GameState.battles_won = _saved_battles
		GameState.corruption_effects.assign(_saved_corruption)
		GameState.permakilled_monster_types.assign(_saved_permakill)


func _director():
	var d = load(DIRECTOR).new()
	add_child_autofree(d)
	return d


## Drive the classifier at a given battle count and automation ratio.
func _classify(total_battles: int, ratio: float) -> String:
	GameState.battles_won = total_battles
	SaveSystem.autobattle_records = {"x": {"count": int(round(float(total_battles) * ratio))}}
	return _director()._detect_playstyle()


func _returns_in_source() -> Array:
	var src := FileAccess.get_file_as_string(DIRECTOR)
	var fn := src.find("func _detect_playstyle")
	assert_gt(fn, -1, "_detect_playstyle must exist")
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	var out: Array = []
	for line in body.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("return \""):
			var v := t.substr(8, t.length() - 9)
			if not out.has(v):
				out.append(v)
	return out


# ── The headline invariant ────────────────────────────────────────────

func test_every_named_playstyle_is_reachable() -> void:
	# Derived from the classifier's own return statements, not a maintained
	# list — add an arm and it must earn its reachability here too.
	var named := _returns_in_source()
	assert_gt(named.size(), 3, "positive control: the classifier should name several playstyles")
	var seen := {}
	# Sweep the plausible space: battle counts across a whole campaign, the
	# full ratio range, and both exploitation states.
	for battles in [0, 5, 19, 20, 39, 40, 75, 100, 101, 150, 400]:
		for ratio in [0.0, 0.1, 0.29, 0.3, 0.5, 0.7, 0.71, 0.95, 1.0]:
			seen[_classify(battles, ratio)] = true
	GameState.permakilled_monster_types.append("slime")
	seen[_classify(150, 0.5)] = true
	var unreachable: Array = []
	for v in named:
		if not seen.has(v):
			unreachable.append(v)
	assert_eq(unreachable.size(), 0,
		"these playstyles can never be returned, so any cutscene branching on them is DEAD CONTENT — world6_chapter3 authors four endings this way:\n  %s\n  reachable: %s" % [
			str(unreachable), str(seen.keys())])


func test_a_manual_player_at_endgame_is_not_called_a_grinder() -> void:
	# THE regression. 150 battles, almost no automation = someone who
	# hand-played the game. Pre-fix this returned "grinder", so the manual
	# ending could never play for the players it was written for.
	assert_eq(_classify(150, 0.02), "manual",
		"a player who hand-fought 150 battles must classify manual — 'grinder' is a word about volume, and it was swallowing the whole ratio range")
	assert_eq(_classify(400, 0.0), "manual",
		"…and it must not degrade back to grinder at higher totals either")


func test_endgame_still_distinguishes_more_than_two_playstyles() -> void:
	# @cowir-battle measured exactly 2 of 5 reachable at 150 battles.
	var seen := {}
	for ratio in [0.0, 0.2, 0.5, 0.65, 0.95]:
		seen[_classify(150, ratio)] = true
	assert_gt(seen.size(), 2,
		"at endgame the classifier must tell more than two stories apart — it collapsed to automator/grinder, which is where the ending reads it: %s" % str(seen.keys()))


# ── exploiter means exploitation, not "early" ─────────────────────────

func test_early_game_is_not_exploitation() -> void:
	# Pre-fix, ANY player under 40 battles was an "exploiter".
	assert_ne(_classify(10, 0.5), "exploiter",
		"a level-3 party twenty minutes in is not exploiting anything — that arm was measuring earliness")
	assert_ne(_classify(39, 0.1), "exploiter",
		"still not exploitation at 39 battles")


func test_actual_system_abuse_is_exploitation() -> void:
	# The meta jobs ARE the sanctioned exploits. Necromancer extermination
	# and accrued corruption (which Scriptweaver's modify_constant adds on
	# every constant edit) are both save-persisted markers.
	GameState.permakilled_monster_types.append("slime")
	assert_eq(_classify(150, 0.5), "exploiter",
		"permakilling a species off the spawn tables is exploitation at any battle count")
	GameState.permakilled_monster_types.clear()
	GameState.corruption_effects.append("visual_glitch")
	assert_eq(_classify(150, 0.5), "exploiter",
		"accrued corruption marks someone who has been manipulating the systems")


func test_exploiter_docstring_no_longer_claims_an_unimplemented_term() -> void:
	# lie-in-the-label: the old comment promised "low battles, high level —
	# efficient" and level was never read. Same class as @cowir-controller's
	# "[+/-] Speed" hint bar. Scan CODE only — a forbidden-substring check
	# that reads comments fires on the note explaining why it's banned
	# (@cowir-controller's trap), so this asserts the term is gone from the
	# arm rather than that a phrase is absent from the file.
	var src := FileAccess.get_file_as_string(DIRECTOR)
	var fn := src.find("func _has_exploited_systems")
	assert_gt(fn, -1, "exploitation must be its own named predicate, not an inline battle-count test")
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_true(body.find("permakilled_monster_types") > -1 or body.find("corruption_effects") > -1,
		"the exploitation test must consult an actual abuse signal")


# ── Sanity on the remaining arms ──────────────────────────────────────

func test_automator_and_grinder_still_work() -> void:
	assert_eq(_classify(150, 0.95), "automator", "heavy automation still reads as automator")
	assert_eq(_classify(150, 0.5), "grinder", "high volume with mixed style is what grinder now means")


func test_too_little_data_is_balanced_not_a_verdict() -> void:
	assert_eq(_classify(5, 0.5), "balanced",
		"below the sample floor no proportion is meaningful — don't hand the player an ending off 5 battles")
	assert_eq(_classify(0, 0.0), "balanced", "a fresh save has no playstyle yet")
