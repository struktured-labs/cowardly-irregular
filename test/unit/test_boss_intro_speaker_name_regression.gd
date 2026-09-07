extends GutTest

## Regression: BattleScene._show_boss_intro_dialogue used to pass the literal
## string "Boss" as the speaker label, so all boss intros displayed "Boss:"
## instead of "Mordaine:" / "Cave Rat King:" / "Pyrroth:" etc. Source-level
## pin because BattleScene is a Control with autoload-driven _ready and
## cannot be safely instantiated headless without a full scene tree.

const BATTLE_SCENE_PATH: String = "res://src/battle/BattleScene.gd"


func _load_source() -> String:
	var f: FileAccess = FileAccess.open(BATTLE_SCENE_PATH, FileAccess.READ)
	assert_not_null(f, "could not open BattleScene source")
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s


func test_show_boss_intro_dialogue_uses_helper_not_literal_boss() -> void:
	var src: String = _load_source()
	# The literal string call must be gone — replaced by the helper.
	assert_false(src.contains("show_boss_intro(\"Boss\","),
		"_show_boss_intro_dialogue must NOT pass the literal \"Boss\" label anymore")
	assert_true(src.contains("show_boss_intro(_get_boss_intro_speaker()"),
		"_show_boss_intro_dialogue must call show_boss_intro with the speaker helper")


func test_get_boss_intro_speaker_helper_exists_and_consults_test_enemies() -> void:
	var src: String = _load_source()
	assert_true(src.contains("func _get_boss_intro_speaker"),
		"BattleScene must define the _get_boss_intro_speaker helper")
	# Make sure the helper actually reads the boss name from enemy data — the
	# fallback to "Boss" should ONLY trigger when no enemies are available.
	var idx: int = src.find("func _get_boss_intro_speaker")
	assert_gt(idx, -1)
	var slice: String = src.substr(idx, 600)
	assert_true(slice.contains("test_enemies"),
		"_get_boss_intro_speaker must read from test_enemies, not just return a constant")
	assert_true(slice.contains("combatant_name"),
		"_get_boss_intro_speaker must surface the combatant_name, not a generic placeholder")
	assert_true(slice.contains("is_boss"),
		"_get_boss_intro_speaker must prefer is_boss-tagged enemies for accurate labeling")
