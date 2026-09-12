extends GutTest

## A quest whose giver NPC exists nowhere can never be started by any means.

const QUEST_DIR := "res://data/quests/"
const NPC_SRC := "res://src/exploration/OverworldNPC.gd"

## Value is the BLOCKER, not just the world — membership must carry WHY it is still absent.
## The three W4 rivet_row givers below are DELIBERATELY unplaced: their NPCs exist and one line
## each would start the quests, but every custom step needs a designed mechanic (multi-path
## counter-signature, a compression puzzle, an archive in maintenance tunnels that has no map).
## Placing them would ship startable-but-unfinishable quests — the W1 trap, on purpose.
## 2026-09-11 (cowir-story 239ba029): foreman/union_rep/dorrit/madame_orrery_w4 + firewall_attendant_w5 now have ids and left this list.
const AUTHORED_AHEAD := {
	"rat_patrol_junction": "W4 — sited in rivet_row_tunnels, which exists as no map",
	"memory_leak_district": "W5 — no village placement yet",
	"madame_orrery_w5": "W5 — no village placement yet",
	"race_condition_pair": "W5 — no village placement yet",
	"traveler_w6": "W6 — no village placement yet",
	"madame_orrery_w6": "W6 — no village placement yet",
	"last_shopkeeper_w6": "W6 — no village placement yet",
}

## One NAMED member per resolution path — a count control passes on a sweep that resolved nothing.
const CONTROLS := ["rowan_harmonia", "warden_tally_wall", "scholar_milo", "senga_the_glassblower"]


func _gd_files() -> Array:
	var out: Array = []
	var stack: Array = ["res://src"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			var p: String = dir + "/" + f
			if d.current_is_dir():
				stack.append(p)
			elif f.ends_with(".gd"):
				## Comment lines are stripped: a commented-out placement would mark a giver reachable and hide a dead quest.
				var text := ""
				for line in FileAccess.get_file_as_string(p).split("\n"):
					if not line.strip_edges().begins_with("#"):
						text += line + "\n"
				out.append(text)
			f = d.get_next()
		d.list_dir_end()
	return out


## Mirrors OverworldNPC.get_npc_id()'s fallback; drift here silently un-blinds or blinds this guard.
func _name_to_id(npc_name: String) -> String:
	return npc_name.to_lower().replace(" ", "_").replace("'", "").replace("-", "_")


## Every id an NPC can answer to: explicit assignment, typed default, or name fallback.
func _reachable_ids() -> Dictionary:
	var out := {}
	var assigned := RegEx.create_from_string("(\\w+)\\.npc_id\\s*=\\s*\"([^\"]+)\"")
	var declared := RegEx.create_from_string("var npc_id\\s*:\\s*String\\s*=\\s*\"([^\"]+)\"")
	var made := RegEx.create_from_string("(?:var\\s+(\\w+)\\s*=\\s*)?_create_(?:wandering_)?npc\\(\\s*\"([^\"]+)\"")
	## 48 ids exist only this way: interiors build NPCs directly instead of through the factory.
	var named := RegEx.create_from_string("(\\w+)\\.npc_name\\s*=\\s*\"([^\"]+)\"")
	for src in _gd_files():
		var overridden := {}
		for m in assigned.search_all(src):
			overridden[m.get_string(1)] = true
			out[m.get_string(2)] = "explicit"
		for m in declared.search_all(src):
			out[m.get_string(1)] = "declared"
		for m in made.search_all(src):
			## An explicit npc_id SUPPRESSES the fallback — get_npc_id() returns it and the display name is never derived.
			if m.get_string(1) != "" and overridden.has(m.get_string(1)):
				continue
			var derived := _name_to_id(m.get_string(2))
			if not out.has(derived):
				out[derived] = "name_fallback"
		for m in named.search_all(src):
			if overridden.has(m.get_string(1)):
				continue
			var derived := _name_to_id(m.get_string(2))
			if not out.has(derived):
				out[derived] = "name_fallback"
	return out


func _quests() -> Array:
	var out: Array = []
	var d := DirAccess.open(QUEST_DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".json"):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(QUEST_DIR + f))
			if parsed is Dictionary:
				out.append([f.trim_suffix(".json"), parsed])
		f = d.get_next()
	d.list_dir_end()
	return out


## FLOOR. An empty walk makes every giver look unreachable and every check below vacuous.
func test_control_both_corpora_resolve() -> void:
	var ids := _reachable_ids()
	var quests := _quests()
	assert_gt(ids.size(), 100, "NPC walk must find a real corpus of ids — a short read makes every "
		+ "giver look unreachable and inverts this entire guard")
	assert_gt(quests.size(), 25, "quest walk must load the real corpus, else the ratchet is vacuous")

	for c in CONTROLS:
		assert_true(ids.has(c), ("%s must resolve — if the controls do not appear, " % c)
			+ "this scan is not finding NPCs and its verdict means nothing")
	assert_false(ids.has("zzz_no_such_npc"), "a nonexistent id must NOT resolve, else the scan "
		+ "matches everything and cannot report a real absence")
	assert_false(ids.has("rowan"), "Rowan carries an explicit npc_id (rowan_harmonia), so get_npc_id() "
		+ "never derives 'rowan' from his display name. 12 NPCs shadow their derived name this way; "
		+ "counting both would invent ids no NPC answers to and let a dead giver read as reachable")

	var kinds := {}
	for k in ids:
		kinds[ids[k]] = true
	## Each mechanism gets a NAMED member above, not a row count — a sweep resolving nothing also reports zero missing.
	for mechanism in ["explicit", "declared", "name_fallback"]:
		assert_true(kinds.has(mechanism), ("no giver resolved via %s — " % mechanism)
			+ "get_npc_id() reaches an id three ways and a scan blind to one of them reports a live "
			+ "quest as dead. Scanning only explicit .npc_id= writes called farmer_aldwick unreachable "
			+ "when the display name resolves it, and that false alarm is why this guard exists")

	## Was a source pin on ONE of the fallback's three replacements, with a message claiming it
	## caught the shape CHANGING — dropping .replace("'","") passed it while the mirror diverged.
	var probe = load(NPC_SRC).new()
	autofree(probe)
	probe.npc_name = "O'Rourke-Vance the Elder"
	assert_eq(probe.get_npc_id(), _name_to_id("O'Rourke-Vance the Elder"),
		"_name_to_id() must agree with the REAL OverworldNPC.get_npc_id() fallback on a name "
		+ "exercising all three transforms (space, apostrophe, hyphen). This guard derives every "
		+ "name-fallback id by hand; if the two drift it measures an id set no NPC answers to and "
		+ "a live quest reads as dead. A source pin could not see a replacement being removed")
	probe.npc_id = "explicit_wins"
	assert_eq(probe.get_npc_id(), "explicit_wins",
		"an explicit npc_id must SUPPRESS the fallback — the scan above relies on that precedence")


## THE RATCHET. Both directions.
func test_unreachable_giver_set_is_exactly_the_authored_ahead_set() -> void:
	var ids := _reachable_ids()
	var checked := 0
	var broken: Array = []
	var landed: Array = []
	for pair in _quests():
		var giver: String = str(pair[1].get("giver", {}).get("npc_id", ""))
		if giver == "":
			continue
		checked += 1
		if ids.has(giver):
			if AUTHORED_AHEAD.has(giver):
				landed.append("%s (%s)" % [giver, pair[0]])
		elif not AUTHORED_AHEAD.has(giver):
			broken.append("%s needs %s" % [pair[0], giver])

	assert_gt(checked, 25, "must test real givers, else both assertions below are vacuous")
	assert_eq(broken, [], "this quest can never be started: QuestSystem offers a quest only when the "
		+ "player talks to an NPC whose id matches giver.npc_id, and no NPC in src/ answers to this "
		+ "one. Five W1 quests shipped this way with authored rewards nobody could obtain. Place the "
		+ "NPC, or add it to AUTHORED_AHEAD with its world: %s" % [broken])
	assert_eq(landed, [], "these are listed as authored-ahead but their NPCs now exist. Good — remove "
		+ "them from AUTHORED_AHEAD so the list keeps describing reality: %s" % [landed])


## THE DUAL. A reachable giver makes every LATER step of that quest a promise too.
## AUTHORED_AHEAD deliberately does NOT exempt here: it records givers we chose not to place,
## and a member of that list appearing as a TALK TARGET of a quest we DID place is the trap
## the list exists to prevent, not a case it covers.
func test_a_placed_giver_implies_every_talk_target_is_placed() -> void:
	var ids := _reachable_ids()
	var checked := 0
	var stranded: Array = []
	for pair in _quests():
		var giver: String = str(pair[1].get("giver", {}).get("npc_id", ""))
		if giver == "" or not ids.has(giver):
			continue
		checked += 1
		var objectives: Array = pair[1].get("objectives", [])
		for i in objectives.size():
			var o: Dictionary = objectives[i]
			if str(o.get("type", "")) != "talk":
				continue
			var target: String = str(o.get("target_npc", ""))
			if target != "" and not ids.has(target):
				stranded.append("%s obj[%d] -> %s" % [pair[0], i, target])

	assert_gt(checked, 15, "must inspect real placed-giver quests, else this ratchet is vacuous")
	assert_eq(stranded, [], "this quest CAN be accepted and can NEVER be finished. The giver is placed, "
		+ "so the player is offered it, walks to the step, and the target NPC answers to a different id "
		+ "or does not exist. world4_deviation_report shipped this way: Union Rep Voss stands in Rivet "
		+ "Row but derives 'union_rep_voss', while the step asks for 'union_rep_w4'. Either place the "
		+ "target, or un-place the giver — do NOT add the target to AUTHORED_AHEAD, which tracks "
		+ "unplaced GIVERS and would hide exactly this: %s" % [stranded])


## ── THE OTHER KIND OF DEAD END, added 2026-09-12 ───────────────────────────
##
## THE ARM ABOVE QUANTIFIES OVER `talk` OBJECTIVES. A `custom` ONE DEAD-ENDS JUST AS HARD.
##
## Measured on b466669e: FOUR quests whose giver IS placed and whose middle steps are `custom`
## objectives with no emitter anywhere in src/. The player talks to the NPC, accepts, and the
## quest can never advance past step 1.
##
##     world4_form_exception_alpha      dorrit_w4               countersigned · submitted
##     world4_the_watercolors           foreman_w4              archive_located · archive_reached
##     world4_words_per_conversation    union_rep_w4            petition_restructured · submitted
##     world5_termination_condition     firewall_attendant_w5   stack_read · signal_sent
##
## All four share one shape: obj[0] talk-to-giver (accepting IS that talk), obj[1] and obj[2]
## custom with no emitter, obj[3] a turn-in gated on obj[2]'s flag. 1,550 exp, two items
## (`exception_record`, `mechanism_status_report`) and a Scriptweaver variant are unreachable.
## Only `world4_form_exception_alpha` has a prereq_flag, and it resolves.
##
## 🔑 HOW IT SHIPPED, in two commits four hours apart, and it is the reason this arm belongs
## beside AUTHORED_AHEAD rather than anywhere else.
##
##     239ba029  05:32  wired the givers' ids — a DIFFERENT file, no claim about objectives
##     d4f0900cc  09:50  removed the AUTHORED_AHEAD entries as "caught up with the fold"
##
## THE DELETED ENTRIES WERE A SPECIFICATION, NOT A GENERIC WARNING. Verbatim from d4f0900cc:
##
##     "foreman_w4":   "…watercolors step3 needs the maintenance-tunnels map"
##     "union_rep_w4": "…words_per_conversation step2 is the compression puzzle"
##     "dorrit_w4":    "…form_exception step2 is the multi-path counter-signature"
##     "madame_orrery_w4": "…Placing it shipped an acceptable-unfinishable quest"
##
## Each named its own objective-level debt. They were drained on the criterion that the GIVERS
## now resolved, while the text of each entry described the OBJECTIVES. The information was not
## missing when the quests became startable — it was deleted as stale four hours later, because
## the thing the key was about had been fixed.
##
## ⛔ THE RULE, and every stale-list arm in this lane (including the dual below) gets it wrong
## by default: DRAIN AN EXEMPTION WHEN ITS VALUE IS FALSE, NEVER WHEN ITS KEY IS SATISFIED.
## A "GOOD NEWS, STALE LIST" arm keyed on the wrong half fires exactly this deletion.
##
## ⚠️ NOT A PROPOSAL TO DELETE THE QUESTS OR UNPLACE THE GIVERS. Each needs a designed mechanic
## — a countersignature flow, an archive with a route, a petition rewrite, a stack-read
## interact. That is content work and it is not this file's call. The arm exists so a FIFTH
## one cannot appear quietly, and so these four stay visible while they wait.

## quest id -> what is missing. Every entry is a claim about src/, so it must be false before
## its line can go.
##   grows   -> a giver was placed ahead of its emitters again
##   shrinks -> someone built the mechanic; delete the line
const DEAD_END_CUSTOM_STEPS := {
	"world4_form_exception_alpha": "obj[1] countersigned — madame_orrery_w4 counter-signs and IS placed, so this half is buildable; obj[2] submitted — the legacy message tube, HARD-BLOCKED on rivet_row_tunnels, which exists as no map",
	"world4_the_watercolors": "obj[1] archive_located — dorrit_w4 rumor dialogue, buildable; obj[2] archive_reached — entering the LEGACY ARCHIVE, HARD-BLOCKED on rivet_row_tunnels",
	"world4_words_per_conversation": "obj[1] petition_restructured — the compression puzzle, 3 sequential exchanges per the notes' own v1; obj[2] petition_submitted — Form 99-Theta filing. Both in-village, no new map",
	"world5_termination_condition": "obj[1] stack_read, obj[2] signal_sent — the stack overflow behind the checkpoint and the compose interact, same location. Both in-village, no new map",
}


## Carried from another guard in this lane and it did NOT transfer: the first draft used a
## `_cache` dictionary this file does not declare, and the whole suite failed to parse. A helper
## shape is as corpus-specific as a remedy — check what the file already has before importing it.
var _emitter_cache: Dictionary = {}


## Every string literal in src/. A flag reaches an objective only by being written somewhere,
## and every emitter in this codebase passes the flag as a LITERAL — DIALOGUE_EMITTERS entries,
## _add_quest_examine_point, _add_quest_route_point, set_story_flag, notify_flag all do.
## Comment-stripped by _gd_files(), so a commented-out emitter does not count.
func _src_text() -> String:
	if _emitter_cache.has("srctext"):
		return _emitter_cache["srctext"]
	var out: String = ""
	for t in _gd_files():
		out += t
	_emitter_cache["srctext"] = out
	return out


## PREMISE. The corpus and the reader must both be real, by NAMED member.
func test_premise_the_emitter_corpus_is_readable() -> void:
	var src: String = _src_text()
	assert_gt(src.length(), 1000000,
		"the src/ walk collected only %d chars — every flag would read as unemitted for that reason, not because the emitter is missing" % src.length())
	assert_true(src.contains("\"quest_world3_before_the_regulator_junction_traced\""),
		"CONTROL: a known-wired emitter flag must be found; if this reads missing the scan is broken and every finding below is noise")
	assert_false(src.contains("\"zzz_not_a_quest_flag\""),
		"CONTROL: a fabricated flag must read as unemitted, or the check cannot return a positive")
	assert_gte(DEAD_END_CUSTOM_STEPS.size(), 4,
		"DEAD_END_CUSTOM_STEPS holds %d, fewer than the 4 measured — a drained list makes the ratchet silent. ADDING is free; losing one hides a quest." % DEAD_END_CUSTOM_STEPS.size())


## THE RATCHET. A placed giver makes every CUSTOM step a promise too.
func test_a_placed_giver_implies_every_custom_step_has_an_emitter() -> void:
	var ids := _reachable_ids()
	var src: String = _src_text()
	var checked := 0
	var stranded: Array = []
	for pair in _quests():
		var giver: String = str(pair[1].get("giver", {}).get("npc_id", ""))
		if giver == "" or not ids.has(giver):
			continue
		checked += 1
		if DEAD_END_CUSTOM_STEPS.has(str(pair[0])):
			continue
		var objectives: Array = pair[1].get("objectives", [])
		for i in objectives.size():
			var o: Dictionary = objectives[i]
			if str(o.get("type", "")) != "custom":
				continue
			var flag: String = str(o.get("required_flag", ""))
			if flag != "" and not src.contains("\"%s\"" % flag):
				stranded.append("%s obj[%d] needs %s" % [pair[0], i, flag])

	assert_gt(checked, 15, "must inspect real placed-giver quests, else this ratchet is vacuous")
	stranded.sort()
	assert_eq(stranded, [], "this quest CAN be accepted and can NEVER be finished: its giver is placed "
		+ "and a custom step's flag is emitted by nothing in src/. Build the emitter, or add the quest "
		+ "to DEAD_END_CUSTOM_STEPS saying which mechanic is missing: %s" % [stranded])


## THE STALE-LIST DUAL. The ratchet skips listed quests entirely, so a line whose mechanic was
## built, or whose giver was unplaced again, would sit here forever asserting nothing.
func test_the_dead_end_list_still_describes_the_corpus() -> void:
	var ids := _reachable_ids()
	var src: String = _src_text()
	var by_id := {}
	for pair in _quests():
		by_id[str(pair[0])] = pair[1]

	var fixed: Array = []
	var unplaced: Array = []
	var gone: Array = []
	for k in DEAD_END_CUSTOM_STEPS.keys():
		var qid: String = str(k)
		if not by_id.has(qid):
			gone.append(qid)
			continue
		var q: Dictionary = by_id[qid]
		if not ids.has(str(q.get("giver", {}).get("npc_id", ""))):
			unplaced.append(qid)
			continue
		var still_dead := false
		for o in (q.get("objectives", []) as Array):
			var od: Dictionary = o
			if str(od.get("type", "")) != "custom":
				continue
			var f: String = str(od.get("required_flag", ""))
			if f != "" and not src.contains("\"%s\"" % f):
				still_dead = true
				break
		if not still_dead:
			fixed.append(qid)
	fixed.sort()
	unplaced.sort()
	gone.sort()

	assert_eq(fixed, [], "GOOD NEWS, STALE LIST: every custom step of %s now has an emitter — the quest is "
		+ "finishable. Delete its line from DEAD_END_CUSTOM_STEPS." % [fixed])
	assert_eq(unplaced, [], "%s is listed as a startable dead end but its giver is no longer placed, so it "
		+ "cannot be started at all. That is a different debt — move it to AUTHORED_AHEAD, or restore the giver." % [unplaced])
	assert_eq(gone, [], "DEAD_END_CUSTOM_STEPS names a quest that no longer exists: %s. Delete the line." % [gone])
