extends GutTest

## main 24676: a boss's charge-turn words live in boss_dialogue.json beside every other word it says; the cadence row in monsters.json is mechanics only.
## BossCadence (cowir-battle) asks BossDialogue.get_charge_lines(boss_id) for them, so the accessor must hand back a fixed shape whatever was authored.

const BD_SCRIPT := "res://src/llm/BossDialogue.gd"
const DATA := "res://data/boss_dialogue.json"
const MONSTERS := "res://data/monsters.json"
const TEXT_KEYS: Array[String] = ["charge_line", "charge_barks", "interrupted_line"]


func _dialogue_with(data: Dictionary) -> Node:
	var bd: Node = (load(BD_SCRIPT) as Script).new()
	autofree(bd)
	bd._data = data
	bd._loaded = true
	return bd


func test_an_authored_row_hands_back_every_field() -> void:
	var bd := _dialogue_with({"glacius": {
		"charge_line": " Glacius draws the cold inward. ",
		"charge_barks": ["Be still.", "", 7, "  Hold your breath.  "],
		"interrupted_line": {"bark": "You dare!", "log": "Glacius's breath shatters."},
	}})
	var lines: Dictionary = bd.get_charge_lines("glacius")
	assert_eq(lines["charge_line"], "Glacius draws the cold inward.", "the log line, trimmed")
	assert_eq(lines["charge_barks"], ["Be still.", "Hold your breath."] as Array[String], "barks keep their order; blanks and non-strings are dropped")
	assert_true(lines["charge_barks"] is Array and (lines["charge_barks"] as Array).is_typed(), "the barks come back as a typed Array[String]")
	assert_eq(lines["interrupted_bark"], "You dare!", "the interrupted bark")
	assert_eq(lines["interrupted_log"], "Glacius's breath shatters.", "the interrupted log line")


func test_an_unauthored_boss_gets_the_same_shape_empty() -> void:
	var bd := _dialogue_with({"pyrroth": {"persona": "A dragon."}, "odd": "not a dictionary"})
	for boss in ["pyrroth", "odd", "nobody"]:
		var lines: Dictionary = bd.get_charge_lines(boss)
		assert_eq(lines.keys().size(), 4, "%s: the four keys are always there" % boss)
		assert_eq(lines["charge_line"], "", "%s: no charge line" % boss)
		assert_eq(lines["charge_barks"], [] as Array[String], "%s: no barks" % boss)
		assert_eq(lines["interrupted_bark"] + lines["interrupted_log"], "", "%s: no interrupted words" % boss)


func test_a_malformed_row_degrades_instead_of_aborting() -> void:
	var bd := _dialogue_with({"umbraxis": {"charge_line": 3, "charge_barks": "one string", "interrupted_line": "not an object"}})
	var lines: Dictionary = bd.get_charge_lines("umbraxis")
	assert_eq(lines["charge_line"], "", "a non-string charge line reads as unauthored")
	assert_eq(lines["charge_barks"], [] as Array[String], "a non-array bark pool reads as empty")
	assert_eq(lines["interrupted_bark"] + lines["interrupted_log"], "", "interrupted_line must be {bark, log}; a bare string reads as unauthored")


func test_every_authored_charge_row_has_the_reader_shape() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	assert_true(parsed is Dictionary, "CONTROL: boss_dialogue.json parses")
	if not (parsed is Dictionary):
		return
	var bad: Array = []
	for boss in parsed:
		var e: Variant = (parsed as Dictionary)[boss]
		if not (e is Dictionary):
			continue
		if e.has("charge_line") and not (e["charge_line"] is String and str(e["charge_line"]).strip_edges() != ""):
			bad.append("%s.charge_line" % boss)
		if e.has("charge_barks") and not (e["charge_barks"] is Array and (e["charge_barks"] as Array).all(func(b): return b is String and b.strip_edges() != "")):
			bad.append("%s.charge_barks" % boss)
		if e.has("interrupted_line") and not (e["interrupted_line"] is Dictionary and e["interrupted_line"].get("bark") is String and e["interrupted_line"].get("log") is String):
			bad.append("%s.interrupted_line" % boss)
	assert_eq(bad, [], "an authored charge field the reader would silently drop")


## The one-source ruling, from this side: a cadence row in monsters.json never carries the words.
func test_no_monster_cadence_row_carries_the_words() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MONSTERS))
	assert_true(parsed is Dictionary, "CONTROL: monsters.json parses")
	if not (parsed is Dictionary):
		return
	var leaks: Array = []
	for id in parsed:
		var m: Variant = (parsed as Dictionary)[id]
		if m is Dictionary and m.get("cadence") is Dictionary:
			for k in TEXT_KEYS:
				if (m["cadence"] as Dictionary).has(k):
					leaks.append("%s.cadence.%s" % [id, k])
	assert_eq(leaks, [], "charge words belong in boss_dialogue.json (main 24676), not in a cadence row")
