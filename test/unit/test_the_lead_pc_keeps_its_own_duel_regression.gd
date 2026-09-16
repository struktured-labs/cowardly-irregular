extends GutTest

## world1_prologue's lead_job arm wrote cutscene_flag_spotlight_unlocked_<lead_job>. The story
## gates read that key as "the duel was WON" (GameLoop:3351 is its only other writer, on
## battle_won), so the prologue answered a question the player had not been asked yet: with the
## default fighter lead, `unlocked_mage and not unlocked_fighter` could never be true and
## world1_spotlight_fighter_ch2 — 17 authored steps, a real duel against fighter_skeleton_knight,
## its own signature and victory SFX, a win_condition entry and five tests — was unreachable in
## normal play. QuestLog's "Face the antechamber skeleton" objective also ticked itself at the
## prologue.
##
## The step's benign half (the PC you led with is controllable without a duel) now travels on its
## own key, spotlight_lead_<job>, which _reconcile_spotlight_locks honours. The gates are
## untouched, so the duel-win key means only that. Old saves already carry the _unlocked_ flag and
## keep both behaviours — grandfathered, no migration.
##
## 27 files / 176 tests / 3495 asserts covered this seam and none of them moved: the gate was
## pinned by hand-set flags (test_story_cutscene_chain_regression) and the prologue's write was
## pinned nowhere, so the collision between the two was invisible. Every arm below drives the
## AUTHORED data through the real prefix rule into the real gate.
##
## PROVENANCE, read after the fix and recorded because it decides whether this is a fix at all
## (b06065117, "W1 spotlight pattern + lead-branched prologue"): "the default case fires the
## trope-demonstrating beat that unlocks the PC; the LEAD-OF-THIS-PC case shows the lead doing the
## moment without a separate unlock (their flag was already set in prologue)". The same commit
## authored a lead-specific narration arm in ALL FIVE spotlight scenes AND the prologue write that
## closes their gates — so those five arms have never been reachable. The pre-set flag is
## deliberate and so is the lead arm; they cannot both work off one key. Splitting the key is what
## makes the commit's own first sentence true. Pinned by
## test_every_lead_still_reaches_its_own_scene, which is the arm that would red if anyone decides
## the lead should NOT see their own beat.

const GAME_LOOP := "res://src/GameLoop.gd"
const PROLOGUE := "res://data/cutscenes/world1_prologue.json"
const QUEST_LOG := "res://src/ui/QuestLog.gd"

var _saved_constants: Dictionary = {}
var _saved_story_flags = null


func before_each() -> void:
	_saved_constants = GameState.game_constants.duplicate(true)
	_saved_story_flags = GameState.story_flags.duplicate(true) if "story_flags" in GameState and GameState.story_flags is Dictionary else null


func after_each() -> void:
	GameState.game_constants = _saved_constants.duplicate(true)
	if _saved_story_flags != null:
		GameState.story_flags = _saved_story_flags.duplicate(true)


## Detached (never added to tree) — the gate reads only game_constants + _current_map_id.
func _detached_loop():
	var gl = load(GAME_LOOP).new()
	autofree(gl)
	return gl


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(_read(path))
	return parsed if parsed is Dictionary else {}


## Every lead_job branch in the prologue whose cases write flags, as {job: [flag, ...]}.
func _authored_lead_arms() -> Dictionary:
	var out: Dictionary = {}
	for step in _json(PROLOGUE).get("steps", []):
		if not (step is Dictionary) or step.get("type", "") != "branch":
			continue
		if str(step.get("condition", "")) != "lead_job":
			continue
		var cases = step.get("cases", {})
		if not (cases is Dictionary):
			continue
		for job in cases:
			for sub in cases[job]:
				if sub is Dictionary and sub.get("type", "") == "set_flag" and str(sub.get("flag", "")) != "":
					if not out.has(job):
						out[job] = []
					out[job].append(str(sub["flag"]))
	return out


## Apply an authored arm the way _step_set_flag does — prefix, no interpretation.
func _play_lead_arm(job: String) -> Array:
	var flags: Array = _authored_lead_arms().get(job, [])
	for f in flags:
		GameState.game_constants["cutscene_flag_" + str(f)] = true
	return flags


## State on the cave floor where the fighter gate is authored to fire.
func _arm_antechamber(gl) -> void:
	gl._current_map_id = "whispering_cave"
	gl._current_cave_floor = 5
	for f in ["prologue_complete", "chapter1_complete", "chapter2_complete", "chapter3_complete",
			"spotlight_unlocked_cleric", "spotlight_unlocked_rogue", "spotlight_unlocked_mage"]:
		GameState.game_constants["cutscene_flag_" + f] = true
	GameState.game_constants["talked_to_theron"] = true


func test_the_lead_pcs_own_duel_is_still_reachable() -> void:
	var gl = _detached_loop()
	var written := _play_lead_arm("fighter")
	assert_false(written.is_empty(), "control: the prologue really does have a fighter lead arm to play")
	_arm_antechamber(gl)
	assert_eq(gl._get_pending_story_cutscene(), "world1_spotlight_fighter_ch2",
		"the lead PC's own spotlight duel must survive the prologue: wrote %s" % [written])


func test_a_won_duel_still_closes_that_gate() -> void:
	# ARM+: the arm above would also pass if the gate had simply been removed.
	var gl = _detached_loop()
	_arm_antechamber(gl)
	GameState.game_constants["cutscene_flag_spotlight_unlocked_fighter"] = true
	assert_eq(gl._get_pending_story_cutscene(), "",
		"a duel that WAS won still closes its gate — only the duel-win writer sets that key")


func test_no_authored_cutscene_claims_a_duel_win() -> void:
	# FLOOR FIRST: an absence arm passes for free over a VOID subject, and its message then blames
	# the wrong thing (cowir-deploy). If the corpus read comes back empty, say VOID, not "clean".
	var scanned: Array = []
	var offenders: Array = []
	for path in DirAccess.get_files_at("res://data/cutscenes"):
		if not path.ends_with(".json"):
			continue
		scanned.append(path)
		if _read("res://data/cutscenes/" + path).contains("spotlight_unlocked_"):
			offenders.append(path)
	assert_gt(scanned.size(), 100, "VOID, not clean: the cutscene corpus read back %d files" % scanned.size())
	var arms := _authored_lead_arms()
	assert_eq(arms.get("fighter", []), ["spotlight_lead_fighter"],
		"the prologue's fighter arm records who led, not a duel result")
	assert_eq(offenders, [], "spotlight_unlocked_<job> means the duel was won; authored data must not write it: %s" % [offenders])


func test_the_lead_key_still_grants_manual_control() -> void:
	var gl = _detached_loop()
	var locked := Combatant.new()
	locked.initialize({"name": "Cleric", "max_hp": 100, "max_mp": 10})
	JobSystem.assign_job(locked, "cleric")
	locked.autobattle_locked = true
	var untouched := Combatant.new()
	untouched.initialize({"name": "Bard", "max_hp": 100, "max_mp": 10})
	JobSystem.assign_job(untouched, "bard")
	untouched.autobattle_locked = true
	gl.party = [locked, untouched] as Array[Combatant]
	GameState.game_constants["cutscene_flag_spotlight_lead_cleric"] = true
	gl._reconcile_spotlight_locks()
	assert_false(locked.autobattle_locked, "the PC you led the prologue with is controllable without a duel")
	assert_true(untouched.autobattle_locked, "control: a PC with neither key stays locked — the reconcile is not a blanket unlock")


func test_the_prologue_does_not_tick_a_quest_objective() -> void:
	var src := _read(QUEST_LOG)
	var objective_flags: Array = []
	var re := RegEx.create_from_string('"flag"\\s*:\\s*"(spotlight_[a-z_]+)"')
	for m in re.search_all(src):
		objective_flags.append(m.get_string(1))
	assert_false(objective_flags.is_empty(), "control: QuestLog really does key objectives off spotlight flags")
	assert_true(objective_flags.has("spotlight_unlocked_fighter"),
		"control: the fighter trial is one of them — the objective the prologue used to tick")
	for job in _authored_lead_arms():
		for f in _authored_lead_arms()[job]:
			assert_false(objective_flags.has(f),
				"the prologue must not write a flag that ticks a quest objective the player never did: %s" % f)


func test_every_lead_the_player_can_start_with_has_an_arm() -> void:
	# The lead_job branch has no `default` case, so an unlisted lead executes NOTHING — silently.
	var jobs := _json("res://data/jobs.json")  # top level IS the job table, keyed by id
	var starters: Array = []
	for jid in jobs:
		if jobs[jid] is Dictionary and int((jobs[jid] as Dictionary).get("type", -1)) == 0:
			starters.append(jid)
	assert_eq(starters.size(), 5, "control: five starter jobs — a sixth needs an arm or a default")
	var arms := _authored_lead_arms()
	for jid in starters:
		assert_true(arms.has(jid), "starter '%s' can lead the prologue and must have an arm" % jid)


func test_a_finished_cutscene_reconciles_the_locks() -> void:
	# Source-level: the completion path needs a live Director in the tree. The old guard tested
	# begins_with("cutscene_flag_spotlight_unlocked_") while every entry in the map writes
	# _watched_, so this call had not fired since that rename.
	# Two paths write a completion flag and print it — _play_story_cutscene and the direct-play
	# helper the prologue uses. BOTH are pinned; picking one by find() picked the wrong one first.
	var src := _read(GAME_LOOP)
	var anchor := 'print("[CUTSCENE] %s complete → set flag %s"'
	var found := 0
	var from := 0
	while true:
		var idx := src.find(anchor, from)
		if idx == -1:
			break
		found += 1
		from = idx + 1
		var block := src.substr(idx, 900)
		assert_true(block.contains("_reconcile_spotlight_locks()"),
			"completion path %d reconciles the locks" % found)
	assert_eq(found, 2, "control: both completion paths were read")
	assert_false(src.contains('begins_with("cutscene_flag_spotlight_unlocked_")'),
		"no reconcile is gated on a prefix that no completion flag carries")


## Each spotlight scene's gate, as authored: the flags and place where that PC's scene is pending.
const GATE_CONTEXT := {
	"cleric": {"map": "harmonia_village", "floor": 0, "flags": ["chapter1_complete"]},
	"rogue": {"map": "whispering_cave", "floor": 1, "flags": ["chapter1_complete", "chapter2_complete", "chapter3_complete"]},
	"mage": {"map": "whispering_cave", "floor": 3, "flags": ["chapter1_complete", "chapter2_complete", "chapter3_complete", "spotlight_unlocked_rogue"]},
	"fighter": {"map": "whispering_cave", "floor": 5, "flags": ["chapter1_complete", "chapter2_complete", "chapter3_complete", "spotlight_unlocked_rogue", "spotlight_unlocked_mage"]},
	"bard": {"map": "harmonia_village", "floor": 0, "flags": ["chapter1_complete", "chapter2_complete", "chapter3_complete", "chapter4_complete", "rat_king_defeated", "world1_harmonia_after_cave_complete"]},
}
const SCENE_OF := {
	"cleric": "world1_spotlight_cleric_ch1",
	"rogue": "world1_spotlight_rogue_ch3",
	"mage": "world1_spotlight_mage_ch3",
	"fighter": "world1_spotlight_fighter_ch2",
	"bard": "world1_spotlight_bard_ch7",
}


## Does this scene carry a narration arm for the case where its own PC is the lead?
func _has_own_lead_arm(scene_id: String, job: String) -> bool:
	for step in _json("res://data/cutscenes/%s.json" % scene_id).get("steps", []):
		if step is Dictionary and step.get("type", "") == "branch" and str(step.get("condition", "")) == "lead_job":
			var cases = step.get("cases", {})
			if cases is Dictionary and cases.has(job):
				return true
	return false


func test_every_lead_still_reaches_its_own_scene() -> void:
	# All five scenes carry a lead-specific beat (b06065117). Under the old prologue write the lead
	# closed their own gate, so all five of those arms were dead prose.
	for job in SCENE_OF:
		var gl = _detached_loop()
		GameState.game_constants = _saved_constants.duplicate(true)
		var ctx: Dictionary = GATE_CONTEXT[job]
		GameState.game_constants["cutscene_flag_prologue_complete"] = true
		GameState.game_constants["talked_to_theron"] = true
		for f in ctx["flags"]:
			GameState.game_constants["cutscene_flag_" + str(f)] = true
		# Close the other four gates so the one under test is the pending beat — the earlier gate
		# in _get_pending_story_cutscene wins otherwise (the bard case read cleric's scene first).
		for other in SCENE_OF:
			if other != job:
				GameState.game_constants["cutscene_flag_spotlight_unlocked_" + str(other)] = true
		gl._current_map_id = str(ctx["map"])
		gl._current_cave_floor = int(ctx["floor"])
		assert_true(_has_own_lead_arm(SCENE_OF[job], job),
			"control: %s authors a beat for the case where %s is the lead" % [SCENE_OF[job], job])
		_play_lead_arm(job)
		assert_eq(gl._get_pending_story_cutscene(), SCENE_OF[job],
			"leading with %s must not close %s" % [job, SCENE_OF[job]])
