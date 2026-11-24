extends GutTest
## 2026-11-23 (cowir-story): The Lost Cartographer, Contrarian Depths' boss, had no boss_dialogue entry, so the fight was mute.
## Every dungeon's literal `boss_id` must reach an entry (via monsters.json's boss_llm_persona_id bridge) with victory and defeat lines.

const DUNGEON_DIR := "res://src/maps/dungeons/"
## Shrink-only. The Calibrant speaks through phase_barks and its ending is world6_ending's; its own end lines wait on a canon ruling.
const KNOWN_ENDLESS := {"the_calibrant": "speaks via phase_barks; final-boss end lines are canon, held for struktured"}


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _dungeon_boss_ids() -> Dictionary:
	var out := {}
	var re := RegEx.new()
	re.compile('(?m)^\\s*boss_id\\s*=\\s*"([a-z0-9_]+)"')
	for f in DirAccess.get_files_at(DUNGEON_DIR):
		if not f.ends_with(".gd"):
			continue
		for m in re.search_all(FileAccess.get_file_as_string(DUNGEON_DIR + f)):
			out[m.get_string(1)] = f
	return out


func _persona(monsters: Dictionary, boss_id: String) -> String:
	var row: Variant = monsters.get(boss_id, {})
	var mapped := str((row as Dictionary).get("boss_llm_persona_id", "")) if row is Dictionary else ""
	return mapped if mapped != "" else boss_id


func _has_lines(entry: Dictionary, key: String) -> bool:
	var lines: Variant = entry.get(key, [])
	if not (lines is Array):
		return false
	for l in lines:
		if l is String and not (l as String).strip_edges().is_empty():
			return true
	return false


func test_every_dungeon_boss_has_victory_and_defeat_lines() -> void:
	var ids := _dungeon_boss_ids()
	assert_true(ids.has("cartographer_wraith"), "CONTROL: the derivation must see ContrarianDepths' boss")
	assert_gt(ids.size(), 10, "CONTROL: more than 10 dungeons name a literal boss")
	var monsters := _json("res://data/monsters.json")
	var dialogue := _json("res://data/boss_dialogue.json")
	var mute: Array = []
	for boss_id in ids:
		var entry: Variant = dialogue.get(_persona(monsters, boss_id), null)
		if not (entry is Dictionary) or not _has_lines(entry, "victory_lines") or not _has_lines(entry, "defeat_lines"):
			mute.append("%s (%s)" % [boss_id, ids[boss_id]])
	for known in KNOWN_ENDLESS:
		assert_true(ids.has(known), "a KNOWN_ENDLESS boss is no longer a dungeon boss: drop %s" % known)
		var label := "%s (%s)" % [known, ids.get(known, "")]
		assert_true(mute.has(label), "%s has end lines now: remove it from KNOWN_ENDLESS" % known)
		mute.erase(label)
	assert_eq(mute, [], "dungeon bosses with nothing to say at the end of their fight")


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
