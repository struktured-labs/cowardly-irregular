extends GutTest

## A quest whose giver NPC exists nowhere can never be started by any means.

const QUEST_DIR := "res://data/quests/"
const NPC_SRC := "res://src/exploration/OverworldNPC.gd"

## Unreachable givers that are authored ahead of their world. Owner, not permission.
const AUTHORED_AHEAD := {
	"rat_patrol_junction": "W4", "madame_orrery_w4": "W4", "dorrit_w4": "W4",
	"foreman_w4": "W4", "union_rep_w4": "W4",
	"memory_leak_district": "W5", "madame_orrery_w5": "W5", "race_condition_pair": "W5",
	"firewall_attendant_w5": "W5",
	"traveler_w6": "W6", "madame_orrery_w6": "W6", "last_shopkeeper_w6": "W6",
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
