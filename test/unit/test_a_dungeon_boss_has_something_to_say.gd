extends GutTest
## 2026-11-23 (cowir-story): The Lost Cartographer, Contrarian Depths' boss, had no end lines, so his fight was mute.
## Every boss a dungeon fields must say something when the party wins AND when it wipes the party, from EITHER source:
## boss_dialogue.json (victory_lines / defeat_lines) or its monsters.json `dialogue` (defeat / player_wiped, the latter
## only behind diegetic_retry, GameLoop._diegetic_retry_boss). Reading one source alone exempted the Calibrant wrongly (2026-11-24).

const DUNGEON_DIR := "res://src/maps/dungeons/"


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Three reaches: a literal `boss_id = "x"`, a const emitted through battle_triggered (CastleHarmonia.WARDEN_ID), and the trials.
func _dungeon_boss_ids() -> Dictionary:
	var out := {}
	var lit := RegEx.new()
	lit.compile('(?m)^\\s*boss_id\\s*=\\s*"([a-z0-9_]+)"')
	var konst := RegEx.new()
	konst.compile('(?m)^const\\s+([A-Z_]+)\\s*(?::\\s*String)?\\s*:?=\\s*"([a-z0-9_]+)"')
	for f in DirAccess.get_files_at(DUNGEON_DIR):
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string(DUNGEON_DIR + f)
		for m in lit.search_all(src):
			out[m.get_string(1)] = f
		for m in konst.search_all(src):
			if src.contains("battle_triggered.emit([%s])" % m.get_string(1)):
				out[m.get_string(2)] = f
	var trials: Dictionary = load("res://src/battle/TrialRouting.gd").get_script_constant_map().get("TRIAL_MONSTERS", {})
	for t in trials:
		out[str(trials[t])] = "TrialRouting.gd"
	return out


func _persona(monsters: Dictionary, boss_id: String) -> String:
	var row: Variant = monsters.get(boss_id, {})
	var mapped := str((row as Dictionary).get("boss_llm_persona_id", "")) if row is Dictionary else ""
	return mapped if mapped != "" else boss_id


func _has_lines(entry: Variant, key: String) -> bool:
	if not (entry is Dictionary):
		return false
	var lines: Variant = (entry as Dictionary).get(key, [])
	if not (lines is Array):
		return false
	for l in lines:
		if l is String and not (l as String).strip_edges().is_empty():
			return true
	return false


## "" when the boss speaks at both ends, else which end is silent.
func _silent_end(monsters: Dictionary, dialogue: Dictionary, boss_id: String) -> String:
	var row: Dictionary = monsters.get(boss_id, {}) if monsters.get(boss_id) is Dictionary else {}
	var md: Variant = row.get("dialogue", {})
	var bd: Variant = dialogue.get(_persona(monsters, boss_id), {})
	var on_win := _has_lines(bd, "victory_lines") or _has_lines(md, "defeat")
	var on_wipe := _has_lines(bd, "defeat_lines") or (bool(row.get("diegetic_retry", false)) and _has_lines(md, "player_wiped"))
	if on_win and on_wipe:
		return ""
	return "silent when the party wins" if not on_win else "silent when it wipes the party"


func test_every_dungeon_boss_has_victory_and_defeat_lines() -> void:
	var ids := _dungeon_boss_ids()
	for reach in ["cartographer_wraith", "castle_warden", "the_examiner", "the_calibrant"]:
		assert_true(ids.has(reach), "CONTROL: the derivation must see %s" % reach)
	assert_gt(ids.size(), 15, "CONTROL: every reach was walked")
	var monsters := _json("res://data/monsters.json")
	var dialogue := _json("res://data/boss_dialogue.json")
	var mute: Array = []
	for boss_id in ids:
		var why := _silent_end(monsters, dialogue, boss_id)
		if why != "":
			mute.append("%s (%s): %s" % [boss_id, ids[boss_id], why])
	assert_eq(mute, [], "dungeon bosses with nothing to say at one end of their fight")


func test_the_calibrant_speaks_from_its_monster_row_alone() -> void:
	## CONTROL for the second source: no boss_dialogue end lines, yet it speaks at both ends.
	var monsters := _json("res://data/monsters.json")
	var dialogue := _json("res://data/boss_dialogue.json")
	assert_false(_has_lines(dialogue.get("the_calibrant", {}), "victory_lines"), "CONTROL: this arm needs the monsters.json route alone")
	assert_eq(_silent_end(monsters, dialogue, "the_calibrant"), "", "its monsters.json defeat and player_wiped carry both ends")


func test_the_cartographer_opens_and_turns_in_his_own_voice() -> void:
	var entry: Dictionary = _json("res://data/boss_dialogue.json").get("cartographer_wraith", {})
	assert_true(_has_lines(entry, "opening_lines"), "the Cartographer opens his fight")
	var phases: Dictionary = entry.get("phase_transition_lines", {})
	assert_true(_has_lines(phases, "phase_2") and _has_lines(phases, "phase_3"), "and speaks at both phase turns")
	var dlg: Node = load("res://src/llm/BossDialogue.gd").new()
	add_child_autofree(dlg)
	assert_true(dlg.has_entry("cartographer_wraith"), "the runtime catalog loads his entry")
	assert_eq(dlg.get_display_name("cartographer_wraith"), "The Lost Cartographer", "signed as his monsters.json name")
	assert_eq(dlg.get_verbs("cartographer_wraith"), [], "no Address verbs, so no half-built Talk menu appears")


## 2026-11-24 (cowir-story): .817 shipped the Cartographer's pair inverted, conceding when he WIPES the party. victory_lines play when
## the PARTY wins, defeat_lines when the BOSS wins (BossDialogue.gd:12-13). One-sided: a concession marker may never sit in a wipe line.
const CONCEDES := "(?i)\\b(well played|you won|you win|pass[,.!]|worth|at last|never did|held|i yield|i concede|you beat me|defeated)"


func test_no_boss_concedes_when_it_wipes_the_party() -> void:
	var re := RegEx.new()
	re.compile(CONCEDES)
	var dialogue := _json("res://data/boss_dialogue.json")
	var seen_in_victory := 0
	var gloats := 0
	var conceding: Array = []
	for id in dialogue:
		var entry: Variant = dialogue[id]
		if not (entry is Dictionary):
			continue
		for l in (entry as Dictionary).get("victory_lines", []):
			if re.search(str(l)) != null:
				seen_in_victory += 1
		for l in (entry as Dictionary).get("defeat_lines", []):
			gloats += 1
			if re.search(str(l)) != null:
				conceding.append("%s: %s" % [id, l])
	assert_gt(seen_in_victory, 10, "CONTROL: the marker list must recognise the concessions bosses already make when they lose")
	assert_gt(gloats, 40, "CONTROL: the wipe lines were read")
	assert_eq(conceding, [], "a defeat_line plays when the boss WINS; these concede instead")


## 2026-11-24 (cowir-story): nine dungeon bosses (the Cartographer, five Masterites, the three trials) had no `low_hp` line, so the
## once-per-battle "I'm wounded" beat (BattleScene, <25% HP) said nothing. Its only source is monsters.json dialogue.low_hp.
func test_every_dungeon_boss_says_it_is_wounded() -> void:
	var ids := _dungeon_boss_ids()
	assert_gt(ids.size(), 15, "CONTROL: every reach was walked")
	var monsters := _json("res://data/monsters.json")
	assert_true(_has_lines((monsters.get("ice_dragon", {}) as Dictionary).get("dialogue", {}), "low_hp"), "CONTROL: the reader sees a shipped low_hp line")
	var silent: Array = []
	for boss_id in ids:
		var row: Variant = monsters.get(boss_id, {})
		var md: Variant = (row as Dictionary).get("dialogue", {}) if row is Dictionary else {}
		if not _has_lines(md, "low_hp"):
			silent.append("%s (%s)" % [boss_id, ids[boss_id]])
	assert_eq(silent, [], "dungeon bosses with nothing to say when they drop below a quarter HP")


## 2026-11-24 (cowir-story): Masterites are fielded by MasteriteEncounter (villages, roads), not only by dungeons, so the derived
## dungeon set saw 5 of 24. Every Masterite row (masterite_type) must carry its wounded line too.
func test_every_masterite_says_it_is_wounded() -> void:
	var monsters := _json("res://data/monsters.json")
	var judged := 0
	var silent: Array = []
	for id in monsters:
		var row: Variant = monsters[id]
		if not (row is Dictionary) or str((row as Dictionary).get("masterite_type", "")) == "":
			continue
		judged += 1
		if not _has_lines((row as Dictionary).get("dialogue", {}), "low_hp"):
			silent.append(str(id))
	assert_gt(judged, 20, "CONTROL: the Masterite rows were found")
	assert_eq(silent, [], "Masterites with nothing to say when they drop below a quarter HP")


## 2026-11-24 (cowir-story): Optimization Itself (W6 roamer and field elite) had a scripted intro, low_hp and defeat sequence but
## nothing when it WIPES the party. Any boss authored with an end-of-fight line when it loses must also speak when it wins.
func test_a_boss_that_speaks_when_it_loses_speaks_when_it_wins() -> void:
	var monsters := _json("res://data/monsters.json")
	var dialogue := _json("res://data/boss_dialogue.json")
	var judged := 0
	var mute: Array = []
	for id in monsters:
		var row: Variant = monsters[id]
		if not (row is Dictionary) or not (bool(row.get("boss", false)) or bool(row.get("miniboss", false))):
			continue
		if not (_has_lines(row.get("dialogue", {}), "defeat") or _has_lines(dialogue.get(_persona(monsters, str(id)), {}), "victory_lines")):
			continue
		judged += 1
		if _silent_end(monsters, dialogue, str(id)) != "":
			mute.append("%s: %s" % [id, _silent_end(monsters, dialogue, str(id))])
	assert_gt(judged, 15, "CONTROL: the bosses with a losing line were found")
	assert_eq(mute, [], "bosses that speak when they lose but are silent when they win")


## 2026-11-25 (cowir-story): no cutscene introduces a Vertex trial (battle 27612), so with the intro kept for doors that play no cutscene,
## a trial boss opens on its monsters.json intro, and all three had none. Each must open its own fight.
func test_every_trial_boss_opens_its_own_fight() -> void:
	var trials: Dictionary = load("res://src/battle/TrialRouting.gd").get_script_constant_map().get("TRIAL_MONSTERS", {})
	assert_eq(trials.size(), 3, "CONTROL: the three trials were read")
	var monsters := _json("res://data/monsters.json")
	var silent: Array = []
	for t in trials:
		var row: Variant = monsters.get(str(trials[t]), {})
		if not _has_lines((row as Dictionary).get("dialogue", {}) if row is Dictionary else {}, "intro"):
			silent.append("%s (%s)" % [trials[t], t])
	assert_eq(silent, [], "trial bosses that open their fight in silence")
