extends GutTest

## Playtest 2026-07-15: "quest log looks outdated to our touch ups with
## mordaine and masterites and such. also I beat the rat king but it shows
## up as TODO still."
##
## Two fixes:
## 1. Chapter 1 content refresh — spotlight duels, Castle Harmonia reveal,
##    Mordaine, and the 4 dragons (as an optional section).
## 2. _is_quest_flag_set gains a 4th namespace: game_constants.dungeon_flags
##    (dragon kills / cave clears were invisible to the log).


func _chapter1() -> Dictionary:
	return QuestLog.CHAPTERS[0]


func test_chapter1_covers_the_modern_w1_arc() -> void:
	var flags: Array = []
	for obj in _chapter1()["objectives"]:
		flags.append(str(obj["flag"]))
	for expected in ["spotlight_unlocked_cleric", "spotlight_unlocked_rogue",
			"spotlight_unlocked_mage", "spotlight_unlocked_fighter",
			"spotlight_unlocked_bard", "rat_king_defeated",
			"world1_mordaine_defeated"]:
		assert_true(expected in flags,
			"Chapter 1 must track '%s' — the log was stale vs the shipped W1 arc" % expected)


func test_chapter1_optional_dragons_present() -> void:
	var opts: Array = _chapter1().get("optional", [])
	assert_eq(opts.size(), 4, "all four elemental dragons listed as optional")
	var flags: Array = []
	for o in opts:
		flags.append(str(o["flag"]))
	for f in ["fire_dragon_defeated", "ice_dragon_defeated",
			"lightning_dragon_defeated", "shadow_dragon_defeated"]:
		assert_true(f in flags, "optional dragons must use the dungeon boss_flag_key names (%s)" % f)


func test_flag_check_reads_dungeon_flags_namespace() -> void:
	# Dragon kills live ONLY in game_constants.dungeon_flags — pin the
	# 4th-namespace fallback behaviorally.
	var ql = QuestLog.new()
	autofree(ql)
	GameState.game_constants["dungeon_flags"] = {"fire_dragon_defeated": true}
	assert_true(ql._is_quest_flag_set("fire_dragon_defeated"),
		"dungeon_flags entries must resolve — dragon kills were invisible to the log")
	assert_false(ql._is_quest_flag_set("ice_dragon_defeated"),
		"unset dungeon flag stays false")
	GameState.game_constants.erase("dungeon_flags")


func test_optional_section_rendered_by_build() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/QuestLog.gd")
	assert_true("chapter.get(\"optional\", [])" in src,
		"_build_ui must render the optional section — data without a renderer is the authored-but-never-wired class")
	assert_true("— Optional —" in src,
		"optional block needs its header line")
