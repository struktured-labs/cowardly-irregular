extends GutTest

## MasteriteEncounter runtime integration (msg 2569 cadence, PR #139 followup).
##
## The static PR #139 test (test_w1_masterites_placed) source-pins the
## MasteriteEncounter contract: pending_boss_defeat + defeat_flag() + gate
## on w1_<archetype>_defeated. But no test actually EXERCISES the
## body_entered → pending_boss_defeat → _apply_pending_boss_defeat →
## story-flag-written round-trip. A future edit that stops staking
## story_flags, swaps to game_constants, or changes the defeat_flag
## naming convention would slip past static assertions.
##
## This test drives the trigger like a real player entering the encounter
## zone: instantiate the trigger in-tree, fake a body_entered with a
## player-group node, confirm the pending_boss_defeat spec, apply it via
## the actual GameLoop mechanism, verify the flag lands, then verify the
## trigger self-hides on scene re-entry (once-per-save contract).

const MasteriteEncounterScript := preload("res://src/exploration/MasteriteEncounter.gd")


func _fake_player() -> Node2D:
	var p := Node2D.new()
	p.add_to_group("player")
	return p


func _clear_flags(archetype: String) -> void:
	if GameState == null:
		return
	var flag := "w1_%s_defeated" % archetype
	GameState.set_story_flag(flag, false)
	GameState.pending_boss_defeat = {}


func before_each() -> void:
	_clear_flags("warden")
	_clear_flags("tempo")
	_clear_flags("arbiter")
	_clear_flags("curator")
	for s in _kill_gated_steps():
		_reset_quest(s["quest"])


func after_each() -> void:
	before_each()


## When the player enters the trigger zone, MasteriteEncounter must stake
## pending_boss_defeat.story_flags with the archetype's defeat flag.
func test_body_entered_stakes_pending_boss_defeat() -> void:
	var trig := MasteriteEncounterScript.new()
	trig.archetype = "warden"
	trig.monster_id = "masterite_warden_medieval"
	add_child_autofree(trig)
	await get_tree().process_frame

	var player := _fake_player()
	add_child_autofree(player)
	await get_tree().process_frame

	# Drive the entry handler directly — the physics probe would need a
	# real CharacterBody2D on layer 2. Direct call exercises the same
	# code path minus the collision-mask filter.
	trig._on_body_entered(player)

	var spec: Dictionary = GameState.pending_boss_defeat
	assert_false(spec.is_empty(), "pending_boss_defeat is staked on entry")
	var story_flags: Array = spec.get("story_flags", [])
	assert_true(story_flags.has("w1_warden_defeated"),
		"pending story_flags carries w1_warden_defeated (got %s)" % str(story_flags))


## Source-level contract: GameLoop._apply_pending_boss_defeat must
## read spec.story_flags and clear pending_boss_defeat after applying.
## Verified at source rather than invoked at runtime — the real handler
## calls SaveSystem.auto_save() at the end, which writes to user://saves
## and would corrupt struktured's live saves on every full-suite run
## (feedback_test_isolation_from_user_save, msg 2586 PSA class).
func test_apply_pending_boss_defeat_consumes_story_flags() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var fn_idx := src.find("func _apply_pending_boss_defeat")
	assert_gt(fn_idx, 0, "GameLoop._apply_pending_boss_defeat exists")
	var next_fn := src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("spec: Dictionary = GameState.pending_boss_defeat"),
		"reads pending_boss_defeat")
	assert_true(body.contains("spec.get(\"story_flags\", [])"),
		"consumes spec.story_flags — the field MasteriteEncounter stakes")
	assert_true(body.contains("GameState.set_story_flag(flag)"),
		"writes each story_flag entry via set_story_flag — same store MasteriteEncounter reads on _ready")
	assert_true(body.contains("GameState.pending_boss_defeat = {}"),
		"clears pending_boss_defeat after applying (one-shot contract)")


## Once the defeat flag is set, a fresh MasteriteEncounter must hide
## itself and stop monitoring on _ready — the once-per-save contract.
func test_defeated_trigger_hides_on_ready() -> void:
	GameState.set_story_flag("w1_arbiter_defeated", true)

	var trig := MasteriteEncounterScript.new()
	trig.archetype = "arbiter"
	trig.monster_id = "masterite_arbiter_medieval"
	add_child_autofree(trig)
	await get_tree().process_frame

	assert_false(trig.visible,
		"defeated MasteriteEncounter is hidden on scene re-entry")
	assert_false(trig.monitoring,
		"defeated MasteriteEncounter stops monitoring — no ghost collisions")


## Warden gates on cave_rat_king_defeated per the design doc. Prereq
## unmet → trigger hides; prereq met → trigger visible.
func test_prereq_flag_gates_visibility() -> void:
	GameState.set_story_flag("cave_rat_king_defeated", false)

	var trig := MasteriteEncounterScript.new()
	trig.archetype = "warden"
	trig.monster_id = "masterite_warden_medieval"
	trig.prereq_flag = "cave_rat_king_defeated"
	add_child_autofree(trig)
	await get_tree().process_frame

	assert_false(trig.visible,
		"Warden hidden until Rat King defeated (design doc 'legitimate business')")
	assert_false(trig.monitoring,
		"Warden not monitoring until prereq is met — no accidental fires")

	# Cleanup — the prereq flag is a shared W1 story flag; other tests
	# shouldn't inherit our stale set here.
	GameState.set_story_flag("cave_rat_king_defeated", false)


## Re-entry with the flag already set: even if body_entered fires
## (paranoid case), the trigger must not double-stake pending_boss_defeat.
func test_defeated_trigger_ignores_body_entered() -> void:
	GameState.set_story_flag("w1_curator_defeated", true)

	var trig := MasteriteEncounterScript.new()
	trig.archetype = "curator"
	trig.monster_id = "masterite_curator_medieval"
	add_child_autofree(trig)
	await get_tree().process_frame

	var player := _fake_player()
	add_child_autofree(player)
	trig._on_body_entered(player)

	assert_true(GameState.pending_boss_defeat.is_empty(),
		"defeated trigger must not stake pending_boss_defeat again")


## ── Masterite defeat must ADVANCE the quest step it resolves ──
##
## struktured's ruling (2026-07-29): the masterites ARE the quest steps, and the
## examine points standing in for them are scaffolding. Wiring the encounter is
## only half of it — a `custom` objective advances ONLY through notify_flag, so
## setting `w1_<arch>_defeated` (which the encounter already did) is invisible to
## QuestSystem and the step strands at its own gate.
##
## Everything below DERIVES its subject from data/quests: a step is masterite-
## gated when its flag_on_complete is `w1_<archetype>_defeated`. The ruling named
## three (Arbiter/Curator/Warden); the data carries FOUR — Eldertree's Tempo
## gates `w1_eldertree_rangers_empty_house` step 3 the same way. A hand-written
## list of the three would have shipped Tempo unwired.

const QUEST_DIR := "res://data/quests"
const VILLAGE_DIR := "res://src/maps/villages"


func _quest_system():
	return get_tree().root.get_node_or_null("QuestSystem")


func _kill_gated_steps() -> Array:
	var out: Array = []
	var re := RegEx.create_from_string("^w1_([a-z]+)_defeated$")
	var d := DirAccess.open(QUEST_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(QUEST_DIR + "/" + f))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var objs: Array = parsed.get("objectives", [])
		for i in objs.size():
			var o: Dictionary = objs[i]
			if str(o.get("type", "")) != "custom":
				continue
			var m := re.search(str(o.get("flag_on_complete", "")))
			if m == null:
				continue
			out.append({
				"quest": str(parsed.get("id", f.get_basename())),
				"index": i,
				"archetype": m.get_string(1),
				"required_flag": str(o.get("required_flag", "")),
			})
	return out


## Every MasteriteEncounter a village constructs, anchored on the construction
## site rather than a maintained list of villages.
func _declared_placements() -> Array:
	var out: Array = []
	var d := DirAccess.open(VILLAGE_DIR)
	if d == null:
		return out
	var arch_re := RegEx.create_from_string("\\.archetype\\s*=\\s*\"([a-z_]+)\"")
	var qf_re := RegEx.create_from_string("\\.quest_flag\\s*=\\s*\"([a-z0-9_]+)\"")
	for f in d.get_files():
		if not f.ends_with(".gd"):
			continue
		var src: String = FileAccess.get_file_as_string(VILLAGE_DIR + "/" + f)
		var idx := src.find("MasteriteScript.new()")
		while idx >= 0:
			var end := src.find("npcs.add_child(", idx)
			var block: String = src.substr(idx, end - idx) if end > idx else src.substr(idx)
			var am := arch_re.search(block)
			if am != null:
				var qm := qf_re.search(block)
				out.append({
					"archetype": am.get_string(1),
					"flag": qm.get_string(1) if qm != null else "",
					"file": f,
				})
			idx = src.find("MasteriteScript.new()", idx + 1)
	return out


## Village sources that reference the encounter script at all — a floor the
## parse above must clear, so a renamed local var fails loudly instead of
## reporting zero placements and passing.
func _village_files_referencing_the_encounter() -> int:
	var n := 0
	var d := DirAccess.open(VILLAGE_DIR)
	if d == null:
		return 0
	for f in d.get_files():
		if f.ends_with(".gd") and FileAccess.get_file_as_string(VILLAGE_DIR + "/" + f).contains("MasteriteEncounter.gd"):
			n += 1
	return n


func _reset_quest(qid: String) -> void:
	var qs = _quest_system()
	if qs == null or GameState == null:
		return
	GameState.quests.erase(qid)
	var q: Dictionary = qs.get_quest(qid)
	for o in q.get("objectives", []):
		for k in ["required_flag", "flag_on_complete"]:
			var f := str((o as Dictionary).get(k, ""))
			if f != "":
				GameState.set_story_flag(f, false)
	var pre := str(q.get("prereq_flag", ""))
	if pre != "":
		GameState.set_story_flag(pre, false)


## Replay the authored chain up to `target` using the same entry points the game
## uses, so the step under test is reached the way a player reaches it.
func _advance_to(qid: String, target: int) -> void:
	var qs = _quest_system()
	var q: Dictionary = qs.get_quest(qid)
	var pre := str(q.get("prereq_flag", ""))
	if pre != "":
		GameState.set_story_flag(pre, true)
	qs.accept(qid)
	var objs: Array = q.get("objectives", [])
	var guard := 0
	while qs.get_objective_index(qid) < target and guard < 16:
		guard += 1
		var idx: int = qs.get_objective_index(qid)
		if idx < 0 or idx >= objs.size():
			break
		var o: Dictionary = objs[idx]
		match str(o.get("type", "")):
			"talk":
				qs.notify_talk(str(o.get("target_npc", "")))
			"custom":
				var rf := str(o.get("required_flag", ""))
				GameState.set_story_flag(rf, true)
				qs.notify_flag(rf)
			_:
				break


func test_every_masterite_gated_step_has_an_encounter_wired_to_it() -> void:
	var steps := _kill_gated_steps()
	assert_gt(steps.size(), 0,
		"quest data declares at least one masterite-gated step — zero steps would pass every assertion in this file for free")
	var by_arch := {}
	for p in _declared_placements():
		by_arch[p["archetype"]] = p
	for s in steps:
		var arch: String = s["archetype"]
		assert_true(by_arch.has(arch),
			"%s step %d completes on w1_%s_defeated but no village constructs that encounter — the step is unreachable" % [s["quest"], s["index"], arch])
		if not by_arch.has(arch):
			continue
		assert_eq(str(by_arch[arch]["flag"]), str(s["required_flag"]),
			"%s places the %s encounter but declares quest_flag '%s'; %s step %d gates on '%s' — a mismatch notifies nothing and the step strands" % [
				by_arch[arch]["file"], arch, by_arch[arch]["flag"], s["quest"], s["index"], s["required_flag"]])


func test_no_encounter_declares_a_quest_flag_that_gates_nothing() -> void:
	var placements := _declared_placements()
	assert_gte(placements.size(), _village_files_referencing_the_encounter(),
		"parsed %d placements from %d village files referencing the encounter — the construction shape changed and the audit is reading nothing" % [
			placements.size(), _village_files_referencing_the_encounter()])
	var gates := {}
	for s in _kill_gated_steps():
		gates[str(s["required_flag"])] = s["quest"]
	for p in placements:
		if str(p["flag"]) == "":
			continue
		assert_true(gates.has(str(p["flag"])),
			"%s declares quest_flag '%s' but no masterite-gated custom objective requires it — the notify fires into nothing" % [p["file"], p["flag"]])


## THE POINT, with its negative control first. If setting the defeat flag alone
## advanced the step, the positive half below would prove nothing about the
## notify seam — so the control is the load-bearing assertion, not padding.
func test_the_step_advances_because_of_the_notify_not_the_flag() -> void:
	var steps := _kill_gated_steps()
	assert_gt(steps.size(), 0, "derived at least one masterite-gated step")
	var qs = _quest_system()
	assert_not_null(qs, "QuestSystem autoload present")
	for s in steps:
		var qid: String = s["quest"]
		_reset_quest(qid)
		_advance_to(qid, s["index"])
		assert_eq(qs.get_objective_index(qid), s["index"],
			"%s: driver reached the masterite-gated step (at %d)" % [qid, qs.get_objective_index(qid)])

		GameState.set_story_flag("w1_%s_defeated" % s["archetype"], true)
		assert_eq(qs.get_objective_index(qid), s["index"],
			"%s: setting w1_%s_defeated must NOT move the objective — a custom step advances only via notify_flag" % [qid, s["archetype"]])

		qs.notify_flag(str(s["required_flag"]))
		var after: int = qs.get_objective_index(qid)
		assert_true(after > s["index"] or qs.get_state(qid) == "completed",
			"%s: notifying '%s' must complete step %d (index stayed %d)" % [qid, s["required_flag"], s["index"], after])
		_reset_quest(qid)


## The encounter must hand the applier the flag to notify. Driven for real:
## instantiate, walk in, read what was staked.
func test_body_entered_stakes_the_quest_flag_the_applier_will_notify() -> void:
	var by_arch := {}
	for p in _declared_placements():
		by_arch[p["archetype"]] = p
	var checked := 0
	for s in _kill_gated_steps():
		var arch: String = s["archetype"]
		if not by_arch.has(arch):
			continue
		GameState.pending_boss_defeat = {}
		GameState.set_story_flag("w1_%s_defeated" % arch, false)
		var trig := MasteriteEncounterScript.new()
		trig.archetype = arch
		trig.monster_id = "masterite_%s_medieval" % arch
		trig.quest_flag = str(by_arch[arch]["flag"])
		add_child_autofree(trig)
		await get_tree().process_frame
		var player := _fake_player()
		add_child_autofree(player)
		trig._on_body_entered(player)
		var staked: Array = GameState.pending_boss_defeat.get("quest_flags", [])
		assert_true(staked.has(str(s["required_flag"])),
			"%s: entry must stake quest_flags carrying '%s' (got %s)" % [arch, s["required_flag"], str(staked)])
		checked += 1
		GameState.pending_boss_defeat = {}
	assert_eq(checked, _kill_gated_steps().size(),
		"drove every masterite-gated archetype — a loop that dies on iteration 1 is indistinguishable from a list of 1")


## Kill first, accept the quest later: the victory notify found no active
## objective, so re-entering the village must catch the step up.
func test_ready_catches_up_a_step_whose_kill_happened_before_the_quest() -> void:
	var qs = _quest_system()
	var by_arch := {}
	for p in _declared_placements():
		by_arch[p["archetype"]] = p
	for s in _kill_gated_steps():
		var arch: String = s["archetype"]
		if not by_arch.has(arch):
			continue
		var qid: String = s["quest"]
		_reset_quest(qid)
		GameState.set_story_flag("w1_%s_defeated" % arch, true)
		_advance_to(qid, s["index"])
		assert_eq(qs.get_objective_index(qid), s["index"], "%s: parked on the gated step" % qid)

		var trig := MasteriteEncounterScript.new()
		trig.archetype = arch
		trig.monster_id = "masterite_%s_medieval" % arch
		trig.quest_flag = str(by_arch[arch]["flag"])
		add_child_autofree(trig)
		await get_tree().process_frame

		assert_false(trig.visible, "%s: already-defeated encounter still hides itself" % arch)
		var after: int = qs.get_objective_index(qid)
		assert_true(after > s["index"] or qs.get_state(qid) == "completed",
			"%s: re-entry must catch the step up (index stayed %d) — otherwise killing it before accepting strands the quest forever" % [qid, after])
		_reset_quest(qid)


## Source-level, and it has to be: the real _apply_pending_boss_defeat ends in
## SaveSystem.auto_save(), which writes user://saves and would eat struktured's
## live saves on every suite run. The runtime companion is the notify behaviour
## proven above; this pins only the wiring that cannot be executed here.
func test_apply_pending_boss_defeat_notifies_quest_flags() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var fn_idx := src.find("func _apply_pending_boss_defeat")
	assert_gt(fn_idx, 0, "GameLoop._apply_pending_boss_defeat exists")
	var next_fn := src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("spec.get(\"quest_flags\", [])"),
		"consumes spec.quest_flags — the field MasteriteEncounter stakes for kill-gated steps")
	assert_true(body.contains("notify_flag("),
		"notifies QuestSystem — setting the story flag alone leaves a custom objective parked at its gate")


## The quest must not become acceptable before its encounter is VISIBLE.
##
## Now that the examine points are gone, the encounter is the SOLE emitter for
## these steps — so a quest whose prereq opens earlier than its encounter's
## prereq is acceptable with no way to advance it. Sandrift is the live case:
## the quest gates on `cutscene_flag_rat_king_defeated`, the Warden on
## `cave_rat_king_defeated`. Those are aliases ONLY because WhisperingCave's one
## defeat spec writes all three names at the same moment. Split that spec — move
## the dungeon_flag write, rename one side — and the two gates drift apart with
## nothing else in the suite watching. So pin the property that makes it safe:
## one spec opens both.
func test_encounter_prereq_opens_with_its_quest_prereq() -> void:
	var specs := _boss_defeat_specs()
	assert_gt(specs.size(), 0,
		"found at least one pending_boss_defeat spec in src/ — zero means this test read nothing")
	var gated := 0
	for s in _kill_gated_steps():
		var arch: String = s["archetype"]
		var epre := _placement_prereq(arch)
		if epre == "":
			continue
		gated += 1
		var qpre := _quest_prereq(s["quest"])
		assert_ne(qpre, "",
			"%s gates its %s encounter on '%s' but the quest itself has no prereq — it is acceptable while the encounter is invisible" % [s["quest"], arch, epre])
		var together := false
		for spec in specs:
			if spec.contains("\"%s\"" % epre) and spec.contains("\"%s\"" % qpre):
				together = true
				break
		assert_true(together,
			"no single pending_boss_defeat spec writes BOTH '%s' (quest gate) and '%s' (%s visibility) — if they stop opening together, the quest is acceptable while its only emitter is hidden" % [qpre, epre, arch])
	assert_gt(gated, 0,
		"no masterite declares a prereq_flag — this test asserted nothing (Sandrift's Warden should be here)")


## Brace-balanced text of every `pending_boss_defeat = {...}` literal in src/.
func _boss_defeat_specs() -> Array:
	var out: Array = []
	for path in _gd_files_under("res://src"):
		var src: String = FileAccess.get_file_as_string(path)
		var i := src.find("pending_boss_defeat = {")
		while i >= 0:
			var open_at := src.find("{", i)
			var depth := 0
			var j := open_at
			while j < src.length():
				if src[j] == "{":
					depth += 1
				elif src[j] == "}":
					depth -= 1
					if depth == 0:
						out.append(src.substr(open_at, j - open_at + 1))
						break
				j += 1
			i = src.find("pending_boss_defeat = {", i + 1)
	return out


func _gd_files_under(root: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(root + "/" + f)
	for d in dir.get_directories():
		out.append_array(_gd_files_under(root + "/" + d))
	return out


func _placement_prereq(archetype: String) -> String:
	var dir := DirAccess.open(VILLAGE_DIR)
	if dir == null:
		return ""
	var re := RegEx.create_from_string("\\.prereq_flag\\s*=\\s*\"([a-z0-9_]+)\"")
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var src: String = FileAccess.get_file_as_string(VILLAGE_DIR + "/" + f)
		var idx := src.find("MasteriteScript.new()")
		while idx >= 0:
			var end := src.find("npcs.add_child(", idx)
			var block: String = src.substr(idx, end - idx) if end > idx else src.substr(idx)
			if block.contains("\"%s\"" % archetype):
				var m := re.search(block)
				return m.get_string(1) if m != null else ""
			idx = src.find("MasteriteScript.new()", idx + 1)
	return ""


func _quest_prereq(qid: String) -> String:
	for f in DirAccess.open(QUEST_DIR).get_files():
		if not f.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(QUEST_DIR + "/" + f))
		if typeof(parsed) == TYPE_DICTIONARY and str(parsed.get("id", "")) == qid:
			return str(parsed.get("prereq_flag", ""))
	return ""
