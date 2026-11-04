extends GutTest

## The five W1 bosses after the Rat King are recorded (cowir-main 20795 under struktured's "all the bosses but start with him").
## Each line is found by (speaker, on-screen text); these arms derive every line the way each panel shows it.

## canonical speaker -> [monsters.json id, boss_dialogue.json key]
const BOSSES := {
	"Pyrroth": ["fire_dragon", "pyrroth"],
	"Glacius": ["ice_dragon", "glacius"],
	"Voltharion": ["lightning_dragon", "voltharion"],
	"Umbraxis": ["shadow_dragon", "umbraxis"],
	"Mordaine": ["chancellor_mordaine", "chancellor_mordaine"],
}


func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _cutscene_lines(node: Variant, canon: String, out: Array) -> void:
	if node is Dictionary:
		if SoundManager.speaks_as(canon, str(node.get("speaker", ""))) and str(node.get("text", "")) != "":
			out.append(str(node["text"]))
		for v in node.values():
			_cutscene_lines(v, canon, out)
	elif node is Array:
		for v in node:
			_cutscene_lines(v, canon, out)


## Every line a panel can show for this boss, as the panel shows it.
func _authored(canon: String) -> Array:
	var out: Array = []
	var ids: Array = BOSSES[canon]
	var mon: Dictionary = (_json("res://data/monsters.json") as Dictionary).get(ids[0], {}).get("dialogue", {})
	for part in mon:
		for l in mon[part]:
			var s := str(l)
			if not s.begins_with("*") and ":" in s and SoundManager.speaks_as(canon, s.split(":", true, 1)[0]):
				out.append(s.split(":", true, 1)[1].strip_edges())
	for trig in BossBarks.TRIGGERS:
		for l in BossBarks.lines_for(ids[0], trig):
			out.append(str(l))
	# A signature move's title-card bark (cowir-battle 21077) is spoken by the boss too.
	var bark := str(((_json("res://data/monsters.json") as Dictionary).get(ids[0], {}) as Dictionary).get("fx_signature_card", {}).get("bark", ""))
	if bark != "":
		out.append(bark)
	for f in DirAccess.get_files_at("res://data/cutscenes"):
		if f.ends_with(".json"):
			_cutscene_lines(_json("res://data/cutscenes/" + f), canon, out)
	var bd: Dictionary = (_json("res://data/boss_dialogue.json") as Dictionary).get(ids[1], {})
	for pool in ["opening_lines", "victory_lines", "defeat_lines"]:
		for l in bd.get(pool, []):
			if not str(l).strip_edges().begins_with("*"):
				out.append(DialoguePrompts.spoken_line(str(l)))
	for it in bd.get("scripted_intents", []):
		for l in it.get("taunt_lines", []):
			out.append(DialoguePrompts.spoken_line(str(l)))
	return out


func test_every_authored_boss_line_has_a_recording_on_disk() -> void:
	for canon in BOSSES:
		var lines := _authored(canon)
		assert_gt(lines.size(), 30, "PREMISE: the derivation must find %s's lines, found %d" % [canon, lines.size()])
		var missing: Array = []
		for l in lines:
			var key := SoundManager.voiced_line_clip(canon, l)
			if key == "" or not FileAccess.file_exists(str(SoundManager._sfx_manifest[key]["file"])):
				missing.append(l)
		assert_eq(missing, [], "a %s line was edited or added without a recording; re-render it (cowir-sfx): %s" % [canon, missing])


func test_every_boss_recording_belongs_to_a_line_that_still_exists() -> void:
	for canon in BOSSES:
		var wanted: Dictionary = {}
		for l in _authored(canon):
			wanted[SoundManager.voiced_line_key("", l)] = true
		var seen := 0
		var orphans: Array = []
		for key in SoundManager._sfx_manifest:
			var e = SoundManager._sfx_manifest[key]
			if e is Dictionary and str(e.get("speaker", "")) == canon and e.has("line"):
				seen += 1
				if not wanted.has(SoundManager.voiced_line_key("", str(e["line"]))):
					orphans.append(key)
		assert_gt(seen, 30, "PREMISE: the manifest must carry %s's recordings, found %d" % [canon, seen])
		assert_eq(orphans, [], "these %s recordings speak a line no panel shows any more: %s" % [canon, orphans])


func test_a_battle_panels_titled_name_reaches_the_same_recording() -> void:
	var mon: Dictionary = _json("res://data/monsters.json")
	for canon in BOSSES:
		var title := str((mon.get(BOSSES[canon][0], {}) as Dictionary).get("name", ""))
		assert_ne(title, "", "PREMISE: %s's monster entry must carry the name a battle panel shows" % canon)
		var line: String = str(_authored(canon)[0])
		assert_ne(SoundManager.voiced_line_clip(title, line), "", "a battle panel names the boss '%s'; that must reach the recording authored for '%s'" % [title, canon])


func test_a_name_that_only_contains_the_boss_is_not_the_boss() -> void:
	var line: String = str(_authored("Pyrroth")[0])
	assert_ne(SoundManager.voiced_line_clip("Pyrroth", line), "", "CONTROL: the plain name must reach it")
	assert_eq(SoundManager.voiced_line_clip("Pyrrothian Scout", line), "", "a different speaker whose name starts with the boss's must not borrow his voice")
	assert_eq(SoundManager.voiced_line_clip("Theron", line), "", "nor anyone else saying the same words")


func _shown_speakers(node: Variant, out: Dictionary) -> void:
	if node is Dictionary:
		if str(node.get("speaker", "")) != "":
			out[str(node["speaker"])] = true
		for v in node.values():
			_shown_speakers(v, out)
	elif node is Array:
		for v in node:
			_shown_speakers(v, out)


## Only a boss's own battle title may reach his recordings by a non-exact name; "Lady Mordaine" would borrow his voice (cowir-music 20801).
func test_only_a_bosss_own_title_reaches_his_voice_by_a_longer_name() -> void:
	var mon: Dictionary = _json("res://data/monsters.json")
	var shown: Dictionary = {}
	for f in DirAccess.get_files_at("res://data/cutscenes"):
		if f.ends_with(".json"):
			_shown_speakers(_json("res://data/cutscenes/" + f), shown)
	for id in mon:
		var e = mon[id]
		if e is Dictionary:
			shown[str(e.get("name", ""))] = true
			for part in (e.get("dialogue", {}) as Dictionary).values():
				for l in part:
					if ":" in str(l) and not str(l).begins_with("*"):
						shown[str(l).split(":", true, 1)[0].strip_edges()] = true
	var titles: Dictionary = {}
	for canon in BOSSES:
		titles[str((mon.get(BOSSES[canon][0], {}) as Dictionary).get("name", ""))] = canon
	var borrowed: Array = []
	var titled := 0
	for name in shown:
		for canon in BOSSES:
			if name != canon and SoundManager.speaks_as(canon, name):
				if titles.get(name, "") == canon:
					titled += 1
				else:
					borrowed.append("%s -> %s" % [name, canon])
	assert_gt(shown.size(), 50, "PREMISE: the walk must collect the game's speaker names, found %d" % shown.size())
	assert_eq(titled, BOSSES.size(), "CONTROL: each boss's own battle title must be found reaching his voice")
	assert_eq(borrowed, [], "these speakers would borrow a boss's recordings through speaks_as; give them their own name or narrow it: %s" % [borrowed])


func test_no_boss_line_outlasts_the_boss_line_watchdog_grace() -> void:
	var grace_sec: float = float(load("res://src/battle/BattleScene.gd").get_script_constant_map().get("BOSS_LINE_GRACE_MS", 0)) / 1000.0
	assert_gt(grace_sec, 0.0, "PREMISE: BattleScene.BOSS_LINE_GRACE_MS must still exist")
	var longest := 0.0
	var who := ""
	for key in SoundManager._sfx_manifest:
		if str(key).begins_with("boss_line_"):
			var s = load(str(SoundManager._sfx_manifest[key]["file"]))
			if s and s.get_length() > longest:
				longest = s.get_length()
				who = str(key)
	assert_gt(longest, 0.0, "PREMISE: at least one boss recording must load")
	assert_lt(longest, grace_sec * 0.8, "%s runs longer than the menu watchdog's grace allows" % who)
