extends GutTest

## tick 358: GameLoop._pluralize_monster_name handles the non-trivial
## English plurals the monsters.json name set actually hits.
##
## Pre-fix _on_bestiary_kill_milestone formatted the milestone toast
## as "%d %ss" — bare "s" append. Real monster names produced
## ungrammatical text:
##   "Glitch Entity"   → "Glitch Entitys"   (should be "Entities")
##   "Null Entity"     → "Null Entitys"
##   "Rogue Process"   → "Rogue Processs"   (should be "Processes")
##   "Cranky Lady"     → "Cranky Ladys"     (should be "Ladies")
##   "Wretch" (hypo)   → "Wretchs"          (should be "Wretches")
##
## Only the rules the actual monster name set needs:
##   - -y after consonant → -ies
##   - -s / -sh / -ch / -x / -z → -es
##   - otherwise → -s

const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: helper exists and toast uses it ─────────────────────

func test_pluralize_helper_and_toast_use() -> void:
	var src := _read(GAME_LOOP_PATH)
	assert_true(src.contains("func _pluralize_monster_name(name: String)"),
		"GameLoop._pluralize_monster_name helper must exist")
	assert_true(src.contains("_pluralize_monster_name(monster_name)"),
		"the milestone toast must route through the pluralizer")
	# Bare "%ss" format must be gone (was the pre-fix call site).
	assert_false(src.contains("\"%d %ss defeated!\""),
		"the bare %ss format must be removed — it produces \"Entitys\" etc.")


# ── Behavioral: -y after consonant → -ies ───────────────────────────

func test_y_after_consonant_to_ies() -> void:
	var gl_script: GDScript = load(GAME_LOOP_PATH)
	var gl: Object = gl_script.new()
	add_child_autofree(gl)
	assert_eq(gl._pluralize_monster_name("Lady"), "Ladies",
		"Lady → Ladies (y after consonant)")
	assert_eq(gl._pluralize_monster_name("Entity"), "Entities",
		"Entity → Entities")
	assert_eq(gl._pluralize_monster_name("Glitch Entity"), "Glitch Entities",
		"multi-word with y-after-consonant suffix")
	# Y after vowel is NOT pluralized to ies.
	assert_eq(gl._pluralize_monster_name("Monkey"), "Monkeys",
		"Monkey → Monkeys (y after vowel)")


# ── Behavioral: -s/-sh/-ch/-x/-z → -es ──────────────────────────────

func test_sibilants_get_es() -> void:
	var gl_script: GDScript = load(GAME_LOOP_PATH)
	var gl: Object = gl_script.new()
	add_child_autofree(gl)
	assert_eq(gl._pluralize_monster_name("Process"), "Processes",
		"Process → Processes (-s)")
	assert_eq(gl._pluralize_monster_name("Rogue Process"), "Rogue Processes",
		"Rogue Process → Rogue Processes")
	assert_eq(gl._pluralize_monster_name("Wretch"), "Wretches",
		"Wretch → Wretches (-ch)")
	assert_eq(gl._pluralize_monster_name("Phoenix"), "Phoenixes",
		"Phoenix → Phoenixes (-x)")


# ── Behavioral: normal names get -s ─────────────────────────────────

func test_normal_names_get_s() -> void:
	var gl_script: GDScript = load(GAME_LOOP_PATH)
	var gl: Object = gl_script.new()
	add_child_autofree(gl)
	assert_eq(gl._pluralize_monster_name("Slime"), "Slimes",
		"Slime → Slimes")
	assert_eq(gl._pluralize_monster_name("Cave Rat"), "Cave Rats",
		"Cave Rat → Cave Rats")
	assert_eq(gl._pluralize_monster_name("Shadow Knight"), "Shadow Knights",
		"Shadow Knight → Shadow Knights")


# ── Behavioral: empty stays empty ───────────────────────────────────

func test_empty_stays_empty() -> void:
	var gl_script: GDScript = load(GAME_LOOP_PATH)
	var gl: Object = gl_script.new()
	add_child_autofree(gl)
	assert_eq(gl._pluralize_monster_name(""), "",
		"empty name stays empty — guard against accidental empty kill events")
