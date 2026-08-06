extends GutTest

## W3's dungeon played Tempo's intro, recorded Tempo's defeat, had Tempo's theme composed on
## disk — and the fight was "meta_knight", a level-matched placeholder never swapped back. The
## masterite music branch keys on masterite_type, so it silently fell through to generic music:
## nothing errored, three signals said Tempo, one said otherwise, and no guard compared them.
##
## This asserts the four signals AGREE (cowir-cutscenes' design): wherever a dungeon's
## boss_cutscene_id names a masterite role, the boss it stages must BE that role. Derived from
## the dungeon files themselves — a hand-list of dungeons would miss the next one added.

const DUNGEON_DIR := "res://src/maps/dungeons"
const ROLES := ["warden", "curator", "tempo", "arbiter"]


func _dungeon_sources() -> Dictionary:
	var out := {}
	var d := DirAccess.open(DUNGEON_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out[f] = FileAccess.get_file_as_string(DUNGEON_DIR + "/" + f)
	return out


func _field(src: String, field: String) -> String:
	var re := RegEx.create_from_string(field + "\\s*=\\s*\"([^\"]+)\"")
	var m := re.search(src)
	return m.get_string(1) if m else ""


func _intro_role(cutscene_id: String) -> String:
	# world3_tempo_intro -> tempo. Non-masterite intros (mordaine, null_chamber_boss) return "".
	var re := RegEx.create_from_string("^world\\d+_(\\w+)_intro$")
	var m := re.search(cutscene_id)
	if m == null:
		return ""
	var role := m.get_string(1)
	return role if role in ROLES else ""


func test_a_masterite_intro_stages_that_masterite() -> void:
	var monsters: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/monsters.json"))
	var checked: int = 0
	var wrong: Array[String] = []
	for f in _dungeon_sources():
		var src: String = _dungeon_sources()[f]
		var role := _intro_role(_field(src, "boss_cutscene_id"))
		if role == "":
			continue
		checked += 1
		var boss := _field(src, "boss_id")
		if not role in boss:
			wrong.append("%s: intro says %s, boss_id is %s" % [f, role, boss])
			continue
		# The signal that actually drives the music branch: the staged monster must carry the
		# role as its masterite_type, or boss_<role>_<world> silently never plays.
		var mdata: Dictionary = monsters.get(boss, {})
		if str(mdata.get("masterite_type", "")) != role:
			wrong.append("%s: %s has masterite_type '%s', intro promises %s"
				% [f, boss, str(mdata.get("masterite_type", "")), role])
	assert_gt(checked, 0,
		"CONTROL: at least one masterite-intro dungeon exists — a zero here makes this vacuous")
	assert_eq(wrong, [] as Array[String],
		"a dungeon staging a masterite intro must fight that masterite: %s" % str(wrong))


func test_a_masterite_defeat_flag_matches_its_intro() -> void:
	var wrong: Array[String] = []
	var checked: int = 0
	for f in _dungeon_sources():
		var src: String = _dungeon_sources()[f]
		var role := _intro_role(_field(src, "boss_cutscene_id"))
		if role == "":
			continue
		var flag_re := RegEx.create_from_string("defeat_cutscene_flags\\s*=\\s*\\[\\s*\"([^\"]+)\"")
		var fm := flag_re.search(src)
		if fm == null:
			continue
		checked += 1
		if not role in fm.get_string(1):
			wrong.append("%s: intro says %s, defeat flag is %s" % [f, role, fm.get_string(1)])
	assert_gt(checked, 0, "CONTROL: at least one dungeon carries both signals")
	assert_eq(wrong, [] as Array[String],
		"the flag a dungeon records must name the masterite its intro staged: %s" % str(wrong))


func test_control_the_parser_reads_the_w3_dungeon() -> void:
	# The reported instance, pinned so a rename or refactor cannot silently empty the walk.
	var srcs := _dungeon_sources()
	assert_true(srcs.has("SteampunkMechanism.gd"), "CONTROL: the W3 dungeon is in the walk")
	var src: String = srcs.get("SteampunkMechanism.gd", "")
	assert_eq(_intro_role(_field(src, "boss_cutscene_id")), "tempo",
		"CONTROL: W3's intro parses to the tempo role")
	assert_eq(_field(src, "boss_id"), "masterite_tempo_steampunk",
		"W3 fights The Grand Schedule — the fix this file guards")
