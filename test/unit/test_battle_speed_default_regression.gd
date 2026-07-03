extends GutTest

## Default battle speed history, now settled by two user reports:
## 2026-06-04 "default must be 1.0x" + 2026-07-02 "default is like 4x
## faster than it should be". The recalibration made displayed "1x" =
## engine 0.5 (BATTLE_SPEED_LABELS index 1); the 06-04 fix bumped the
## default to index 2 against the PRE-recalibration labels, which
## displays as "2x". Default is index 1: label "1x", engine 0.5.

const BATTLE_SCENE_PATH := "res://src/battle/BattleScene.gd"
const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_default_speed_index_is_1_labeled_1x() -> void:
	# Source pin, NOT the live static — suite tests cycle speeds and
	# mutate the static, so runtime reads are order-dependent.
	var text = _read(BATTLE_SCENE_PATH)
	assert_true(text.find("static var _battle_speed_index: int = 1") > -1,
		"default must be index 1 — label \"1x\", engine 0.5 (user reports 2026-06-04 + 2026-07-02)")
	assert_eq(text.find("static var _battle_speed_index: int = 2"), -1,
		"index 2 displays as \"2x\" — the 4x-too-fast report's root cause")


func test_speed_and_label_arrays_stay_paired() -> void:
	var text = _read(BATTLE_SCENE_PATH)
	assert_true(text.find("const BATTLE_SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]") > -1,
		"BATTLE_SPEEDS must keep 0.5 at index 1; the default index relies on this position")
	assert_true(text.find("[\"0.5x\", \"1x\", \"2x\", \"4x\", \"8x\", \"16x\", \"32x\"]") > -1,
		"labels must stay index-paired with speeds or the display lies")


func test_save_system_reads_via_preload_const() -> void:
	var text = _read(SAVE_SYSTEM_PATH)
	assert_true(text.find("BATTLE_SCENE_SCRIPT._battle_speed_index") > -1,
		"SaveSystem must read _battle_speed_index via the BATTLE_SCENE_SCRIPT preload const")
