extends GutTest

## Milo is the autobattle NPC, and his REACHABLE lines must name the route into the editor.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

const PERSONA_JSON := "res://data/cutscenes/npc_showcase_personas.json"
const OVERWORLD_MENU := "res://src/ui/OverworldMenu.gd"
const MILO := "Scholar Milo"

## The bucket a player reaches before starting his quest — the first lines anyone hears.
const REACHABLE_BUCKET := "pre_task_1"

## A key or pad button spelled into JSON cannot derive per device, so a reachable line must not name one.
const DEVICE_TOKENS := ["F5", "F6", "Start", "Select", "Options", "Plus", "Minus", "Share", "L+R"]


func _personas() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PERSONA_JSON))
	return raw if raw is Dictionary else {}


func _milo() -> Dictionary:
	var p: Dictionary = _personas()
	return p.get(MILO, {}) if p.has(MILO) else {}


func _reachable_lines() -> Array:
	var q: Variant = _milo().get("quest_state_lines", {})
	if not (q is Dictionary):
		return []
	var b: Variant = (q as Dictionary).get(REACHABLE_BUCKET, [])
	return b if b is Array else []


## The label the menu really renders, read from code so a rename cannot leave the dialogue behind.
## The autobattle row's label, found by its stable id so the Auto: ON/OFF row cannot stand in for it.
func _autobattle_row_label() -> String:
	var code := GdSource.code_of(OVERWORLD_MENU)
	var anchor := "\"id\": \"autobattle\""
	var i := code.find(anchor)
	if i < 0:
		return ""
	var needle := "\"label\": \""
	var j := code.find(needle, i)
	if j < 0:
		return ""
	var start := j + needle.length()
	var end := code.find("\"", start)
	return code.substr(start, end - start) if end > start else ""


func _menu_labels() -> Array:
	var code := GdSource.code_of(OVERWORLD_MENU)
	assert_true(code.contains("const SettingsMenuScript"), "CONTROL: OverworldMenu code must survive comment-stripping")
	var out: Array = []
	var needle := "\"label\": \""
	var i := code.find(needle)
	while i > -1:
		var start := i + needle.length()
		var end := code.find("\"", start)
		if end > start:
			out.append(code.substr(start, end - start))
		i = code.find(needle, start)
	return out


func test_the_persona_and_bucket_this_file_assumes_still_exist() -> void:
	assert_true(_personas().has(MILO), "CONTROL: %s must be in the persona file" % MILO)
	assert_false(_personas().has("Scholar Zzz"), "CONTROL: a fabricated persona must not be found")
	assert_gt(_reachable_lines().size(), 0,
		"CONTROL: %s's %s bucket must hold lines; his fallbacks are shadowed, so this bucket IS the idle path" % [MILO, REACHABLE_BUCKET])


func test_his_reachable_lines_name_the_route_into_the_editor() -> void:
	var route := _autobattle_row_label()
	assert_ne(route, "",
		"CONTROL: OverworldMenu must still declare an autobattle row; without one there is no route to name")
	var naming: Array = []
	for line in _reachable_lines():
		if str(line).contains(route):
			naming.append(str(line))
	assert_gt(naming.size(), 0,
		("Milo is the autobattle NPC and none of his REACHABLE lines names the route. His six tutorial "
		+ "fallbacks never render on the idle path — quest_state_lines shadow them totally (see his "
		+ "_fallbacks_note) — so a player who talks to him is told nothing about where the editor is. "
		+ "Put \"%s\" into one %s line, or move the teaching into whichever bucket is reachable.") % [route, REACHABLE_BUCKET])


func test_the_route_he_names_is_the_row_the_menu_renders() -> void:
	var labels := _menu_labels()
	assert_gt(labels.size(), 3, "CONTROL: the menu should declare several rows; found %d" % labels.size())
	for line in _reachable_lines():
		var s := str(line)
		if not s.contains("Auto Rules"):
			continue
		assert_true(labels.has("Auto Rules"),
			("Milo's reachable dialogue says \"Auto Rules\" and the menu no longer renders a row with that "
			+ "label. Rename the line to match the row, or the player is sent to a row that is not there. "
			+ "Rows today: %s") % str(labels))


func test_a_reachable_line_never_spells_a_device_key() -> void:
	var offenders: Array = []
	for line in _reachable_lines():
		var s := str(line)
		for tok in DEVICE_TOKENS:
			if s.contains(tok):
				offenders.append("%s names %s" % [s.substr(0, 40), tok])
	offenders.sort()
	assert_eq(offenders.size(), 0,
		("a reachable line spells a device key. JSON cannot derive per device, so a pad player reads a "
		+ "keyboard key and a Switch player reads a button that is not on their pad — the frozen-caption "
		+ "class. Name the MENU ROW instead, which is device-independent: " + ", ".join(offenders)) % [])
