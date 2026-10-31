extends GutTest

## Default battle speed history, now settled by two user reports:
## 2026-06-04 "default must be 1.0x" + 2026-07-02 "default is like 4x
## faster than it should be". The recalibration made displayed "1x" =
## engine 0.5 (BATTLE_SPEED_LABELS index 1); the 06-04 fix bumped the
## default to index 2 against the PRE-recalibration labels, which
## displays as "2x". 2026-07-11 settled index 0 (engine 0.25, "1x"); 2026-10-30 he
## asked for a rung between 1x and 2x and made it the default (engine 0.375, "1.5x").

const BATTLE_SCENE_PATH := "res://src/battle/BattleScene.gd"
const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_default_speed_index_is_the_1_5x_rung() -> void:
	## struktured 2026-10-30 overrode the 2026-07-11 "1x is the default": "2x I find a bit hard to
	## see animations but 1x feels too slow". Source pin, NOT the live static — suite tests cycle
	## speeds and mutate the static, so runtime reads are order-dependent.
	var text = _read(BATTLE_SCENE_PATH)
	assert_true(text.find("static var _battle_speed_index: int = DEFAULT_BATTLE_SPEED_INDEX") > -1,
		"the static must start at the named default, not a literal index")
	var bs = load(BATTLE_SCENE_PATH)
	assert_eq(bs.BATTLE_SPEEDS[bs.DEFAULT_BATTLE_SPEED_INDEX], 0.375, "the default rung is engine 0.375")
	assert_eq(bs.BATTLE_SPEED_LABELS[bs.DEFAULT_BATTLE_SPEED_INDEX], "1.5x", "and it reads 1.5x")
	assert_eq(bs.DEFAULT_BATTLE_SPEED, bs.BATTLE_SPEEDS[bs.DEFAULT_BATTLE_SPEED_INDEX],
		"the two default constants must name the same rung")


func test_speed_and_label_arrays_stay_paired() -> void:
	var bs = load(BATTLE_SCENE_PATH)
	assert_eq(Array(bs.BATTLE_SPEEDS), [0.25, 0.375, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0],
		"the ladder: 1x, the 1.5x default, then the doubling rungs")
	assert_eq(Array(bs.BATTLE_SPEED_LABELS), ["1x", "1.5x", "2x", "4x", "8x", "16x", "32x", "64x"],
		"labels must stay index-paired with speeds or the display lies")


func test_save_system_reads_via_preload_const() -> void:
	var text = _read(SAVE_SYSTEM_PATH)
	assert_true(text.find("BATTLE_SCENE_SCRIPT._battle_speed_index") > -1,
		"SaveSystem must read _battle_speed_index via the BATTLE_SCENE_SCRIPT preload const")
