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
	## Derived, not a literal list, so a later rung (his "maybe 3x") does not re-pin this file.
	var bs = load(BATTLE_SCENE_PATH)
	assert_eq(bs.BATTLE_SPEEDS.size(), bs.BATTLE_SPEED_LABELS.size(), "every rung names itself")
	for i in bs.BATTLE_SPEEDS.size():
		var x: float = bs.BATTLE_SPEEDS[i] * 4.0
		var want: String = ("%dx" % int(x)) if is_equal_approx(x, roundf(x)) else ("%sx" % str(x))
		assert_eq(bs.BATTLE_SPEED_LABELS[i], want, "labels are engine*4: rung %d is engine %s" % [i, bs.BATTLE_SPEEDS[i]])
		if i > 0:
			assert_gt(bs.BATTLE_SPEEDS[i], bs.BATTLE_SPEEDS[i - 1], "the ladder strictly climbs at rung %d" % i)
	var r: int = Array(bs.BATTLE_SPEED_LABELS).find("2.5x")
	assert_gt(r, 0, "the 2.5x rung (2026-11-15) is on the ladder")
	if r > 0:
		assert_eq(bs.BATTLE_SPEED_LABELS[r - 1], "2x", "between 2x")
		assert_eq(bs.BATTLE_SPEED_LABELS[r + 1], "4x", "and 4x")
	assert_eq(bs.BATTLE_SPEED_LABELS[0], "1x", "the ladder still starts at 1x")


func test_save_system_reads_via_preload_const() -> void:
	var text = _read(SAVE_SYSTEM_PATH)
	assert_true(text.find("BATTLE_SCENE_SCRIPT._battle_speed_index") > -1,
		"SaveSystem must read _battle_speed_index via the BATTLE_SCENE_SCRIPT preload const")
