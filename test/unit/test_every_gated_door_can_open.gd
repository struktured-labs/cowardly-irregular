extends GutTest

## A map gated on a story flag nothing writes is a door that can never open.
##
## Last night's routing ledger (test_every_map_door_leads_somewhere) proved every map id has a door
## and said so in its own header: it pins REFERENCE reachability, not PLAY reachability, because a
## door behind a flag nobody sets still counts as routed. This is the next question down. If a
## village, overworld or dungeon gates content on `is_story_flag_set("x")` and nothing ever writes
## "x", the content is authored, shipped, and unreachable — and the failure renders as the gate
## simply staying shut, which is what a gate is supposed to look like.
##
## ⚠️ THE FILENAME CLAIMS MORE THAN THE INSTRUMENT COMPUTES, and that is recorded here rather than
## fixed by a rename because the gap is the useful part. "can open" is a claim about PLAY; what runs
## below is "every gate flag has a WRITER SOMEWHERE IN THE SOURCE". A writer existing does not make
## it reachable -- the cutscene that sets a flag could itself be gated on a flag nothing sets, and
## this would still pass. cowir-main named the mechanism the same evening after publishing a sweep
## predicate ("unreachable by ANY path") phrased more broadly than the scanner under it: the broader
## a claim sounds, the less anyone interrogates the code beneath it, so an over-broad name does not
## merely fail to describe the instrument, it CONCEALS the gap. Read this as: every gate flag has a
## writer. Nothing more.
##
## The fleet rule for this class is five weeks old and was invisible: feedback_label_broader_than_
## predicate (2026-08-05), 21 inbound links, not in the index until tonight. Its first line explains
## why MY OWN CONTROLS DID NOT CATCH IT -- "no control fires, because the control tests the
## expression, which works". Both controls below are sound and neither can see the gap between the
## name and the computation, because the computation is correct.

## WHAT THIS FOUND WHEN IT WAS WRITTEN: nothing. Twelve gate flags in src/exploration and src/maps,
## twelve writers, every name matching exactly. That is the result being pinned.
##
## ⚠️ THE THREE TIMES IT WAS WRONG FIRST, all on the WRITER side, all in the same direction — a
## missing writer definer turns a working gate into a "permanently closed door" finding, and six of
## them at once looks like a discovery:
##   1. `visited_brasston` and its three siblings are never written as literals. BaseVillage:111 does
##      `set_story_flag("visited_" + aid.replace("_village", ""), true)`, so the flag name does not
##      exist anywhere in the source. Derived here from each village's own _get_area_id().
##   2. `quest_world1_thirty_seven_complete` and `quest_world2_relocated_complete` are written by
##      QuestSystem from the quest JSON's `flag_on_complete` field, which my first scan did not read.
##   3. A reader scan that takes any literal string catches PREFIXES — `"chest_"`, `"secret_"`,
##      `"chicken_caught_"` are concatenated with an id at the call site and are not flags at all.
##
## So the control is the WRITER DEFINER COUNT, not the orphan count, exactly as in the routing
## ledger: each source of writes carries a floor, and if one stops matching the test names it rather
## than reporting every flag it used to cover as an unopenable gate.

const READER_DIRS := ["res://src/exploration", "res://src/maps/villages", "res://src/maps/dungeons", "res://src/maps/interiors"]
const VILLAGE_DIR := "res://src/maps/villages"
const QUEST_DIR := "res://data/quests"
const WRITER_DIRS := ["res://src", "res://src/exploration", "res://src/meta", "res://src/quests", "res://src/maps/villages", "res://src/maps/dungeons"]


func _read_all(dirs: Array) -> String:
	var text := ""
	var seen := {}
	for d in dirs:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		for f in dir.get_files():
			var p: String = d + "/" + f
			if f.ends_with(".gd") and not seen.has(p):
				seen[p] = true
				text += FileAccess.get_file_as_string(p) + "\n"
	return text


## Flags a map actually gates on. Prefix fragments ending in "_" are concatenated with an id at the
## call site (`"chest_" + chest_id`) and are not flag names.
func _gate_flags() -> Array:
	var text := _read_all(READER_DIRS)
	var rx := RegEx.new()
	rx.compile("(?:is_story_flag_set|get_story_flag)\\(\"([a-z0-9_]+)\"")
	var out: Array = []
	for m in rx.search_all(text):
		var f: String = m.get_string(1)
		if f.ends_with("_"):
			continue
		if not (f in out):
			out.append(f)
	out.sort()
	return out


func _writers() -> Dictionary:
	var written := {}
	var thin: Array = []
	var src := _read_all(WRITER_DIRS)

	var definers := [
		{"name": "set_story_flag literal", "rx": "set_story_flag\\(\"([a-z0-9_]+)\"", "min": 10},
		{"name": "game_constants[]", "rx": "game_constants\\[\\s*\"([a-z0-9_]+)\"\\s*\\]\\s*=", "min": 5},
		{"name": "cutscene_flag literals", "rx": "\"([a-z0-9_]*cutscene_flag_[a-z0-9_]+)\"", "min": 20},
	]
	for d in definers:
		var rx := RegEx.new()
		rx.compile(d["rx"])
		var hits := 0
		for m in rx.search_all(src):
			written[m.get_string(1)] = true
			hits += 1
		if hits < int(d["min"]):
			thin.append("%s matched %d (floor %d)" % [d["name"], hits, int(d["min"])])

	# DERIVED: DragonCave writes game_constants["dungeon_flags"][boss_flag_key] and is_story_flag_set
	# reads that dict, so `boss_flag_key = "x"` in a dungeon subclass is a writer no literal scan sees.
	var rx_boss := RegEx.new()
	rx_boss.compile("boss_flag_key\\s*=\\s*\"([a-z0-9_]+)\"")
	var bosses := 0
	for m in rx_boss.search_all(src):
		written[m.get_string(1)] = true
		bosses += 1
	if bosses < 4:
		thin.append("boss_flag_key definers derived %d (floor 4)" % bosses)

	# DERIVED: BaseVillage writes "visited_" + area id, so these names exist in no source file.
	var villages := 0
	var vdir := DirAccess.open(VILLAGE_DIR)
	if vdir != null:
		for f in vdir.get_files():
			if not f.ends_with(".gd") or f == "BaseVillage.gd":
				continue
			var text := FileAccess.get_file_as_string(VILLAGE_DIR + "/" + f)
			var rx2 := RegEx.new()
			rx2.compile("func _get_area_id[\\s\\S]{0,120}?return \"([a-z0-9_]+)\"")
			var m2 := rx2.search(text)
			if m2 != null:
				written["visited_" + m2.get_string(1).replace("_village", "")] = true
				villages += 1
	if villages < 8:
		thin.append("village area ids derived %d (floor 8)" % villages)

	# DERIVED: HiddenPassage writes "secret_" + passage_id and TreasureChest "chest_" + chest_id,
	# so a readable that names one literally (the Survey Stone) gates on a flag no source spells.
	var rx_secret := RegEx.new()
	rx_secret.compile("\\{\"id\":\\s*\"([a-z0-9_]+)\"[^}]*\"disguise\"")
	var secrets := 0
	for m in rx_secret.search_all(src):
		written["secret_" + m.get_string(1)] = true
		secrets += 1
	var rx_secret2 := RegEx.new()
	rx_secret2.compile("passage_id\\s*=\\s*\"([a-z0-9_]+)\"")
	for m in rx_secret2.search_all(src):
		written["secret_" + m.get_string(1)] = true
		secrets += 1
	if secrets < 5:
		thin.append("hidden passage ids derived %d (floor 5)" % secrets)
	var rx_chest := RegEx.new()
	rx_chest.compile("\\{\"id\":\\s*\"([a-z0-9_]+)\"[^}]*\"pos\"[^}]*\"type\"")
	var chests := 0
	for m in rx_chest.search_all(src):
		written["chest_" + m.get_string(1)] = true
		chests += 1
	if chests < 10:
		thin.append("treasure chest ids derived %d (floor 10)" % chests)

	# DERIVED: QuestSystem mirrors each quest's own flag_on_complete, quest-level and per-objective.
	var quests := 0
	var qdir := DirAccess.open(QUEST_DIR)
	if qdir != null:
		for f in qdir.get_files():
			if not f.ends_with(".json"):
				continue
			var raw := FileAccess.get_file_as_string(QUEST_DIR + "/" + f)
			var rx3 := RegEx.new()
			rx3.compile("\"flag_on_complete\"\\s*:\\s*\"([a-z0-9_]+)\"")
			for m3 in rx3.search_all(raw):
				written[m3.get_string(1)] = true
				quests += 1
	if quests < 20:
		thin.append("quest flag_on_complete matched %d (floor 20)" % quests)

	# Cutscene JSON flag steps.
	var cdir := DirAccess.open("res://data/cutscenes")
	var cflags := 0
	if cdir != null:
		for f in cdir.get_files():
			if not f.ends_with(".json"):
				continue
			var raw := FileAccess.get_file_as_string("res://data/cutscenes/" + f)
			var rx4 := RegEx.new()
			rx4.compile("\"(?:flag|set_flag|story_flag)\"\\s*:\\s*\"([a-z0-9_]+)\"")
			for m4 in rx4.search_all(raw):
				written[m4.get_string(1)] = true
				cflags += 1
	if cflags < 20:
		thin.append("cutscene flag steps matched %d (floor 20)" % cflags)

	assert_eq(thin, [],
		"a writer definer stopped matching -- every flag it used to cover now reads as a door that can never open: %s" % str(thin))
	return written


func test_no_map_gates_on_a_flag_nothing_writes() -> void:
	var gates := _gate_flags()
	assert_gt(gates.size(), 8,
		"CONTROL: only %d gate flags found across every map script -- the reader scan is broken and the zero below is free" % gates.size())
	var written := _writers()
	assert_gt(written.size(), 60, "CONTROL: only %d writable flags collected" % written.size())

	var sealed: Array = []
	for g in gates:
		if not written.has(g):
			sealed.append(g)
	assert_eq(sealed, [],
		"a map gates content on a flag nothing ever writes -- the door renders as shut, which is what a gate is supposed to look like: %s" % str(sealed))


func test_the_ledger_can_see_a_flag_nobody_writes() -> void:
	var written := _writers()
	assert_false(written.has("zzz_no_such_flag"),
		"CONTROL: a fabricated flag must read as unwritten, or the comparison above is vacuous")
	var gates := _gate_flags()
	assert_false("zzz_no_such_flag" in gates,
		"CONTROL: a fabricated flag must not appear among the gates")
