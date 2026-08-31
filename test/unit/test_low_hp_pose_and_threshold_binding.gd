extends GutTest

## The artist's `weak` sheets loaded but nothing played them — BattleScene only
## ever reached play("idle"), all four sites at spawn. These pin the pose hook and
## the threshold binding: five consumers of one dramatic beat, previously one
## constant and two bare literals on a DIFFERENT SCALE (0-1 vs 0-100).

const SRC := "res://src/battle/BattleScene.gd"

func _src() -> String:
	var s := FileAccess.get_file_as_string(SRC)
	assert_gt(s.length(), 1000, "CONTROL: read BattleScene source")
	return s

func test_no_bare_low_hp_literal_survives() -> void:
	var src := _src()
	assert_true(src.contains("DANGER_HP_THRESHOLD"), "CONTROL: the constant is present to bind to")
	assert_eq(src.count("get_hp_percentage() < 25.0"), 0,
		"a bare 25.0 is a SECOND expression of DANGER_HP_THRESHOLD on a 0-100 scale — tuning the constant would move the music and silently leave this behind")

func test_both_dialogue_triggers_bind_to_the_constant() -> void:
	var src := _src()
	assert_eq(src.count("get_hp_percentage() < DANGER_HP_THRESHOLD * 100.0"), 2,
		"both the player low-HP quip and the boss wounded line must scale the constant, not copy it")

func test_the_pose_predicate_uses_the_same_strict_comparison() -> void:
	var src := _src()
	assert_true(src.contains("float(c.current_hp) / float(c.max_hp) < DANGER_HP_THRESHOLD"),
		"_is_low_hp must use strict < like the danger-music check — <= diverges at exactly 25%, the one value anyone tests with")

func test_the_pose_hook_is_actually_called() -> void:
	var src := _src()
	assert_true(src.contains("func _refresh_low_hp_poses()"), "CONTROL: the function exists")
	## Defined-but-uncalled is exactly the state the weak sheets were already in.
	assert_gt(src.count("_refresh_low_hp_poses()"), 1,
		"_refresh_low_hp_poses must be CALLED, not merely defined — an uncalled hook reproduces the inert-art bug it fixes")

func test_the_pose_never_interrupts_a_playing_animation() -> void:
	var src := _src()
	assert_true(src.contains("if current != \"idle\" and current != \"weak\":"),
		"the refresh must skip sprites mid attack/cast/hit — it runs every frame and would otherwise cut those animations short")

func test_the_pose_is_gated_on_the_sheet_existing() -> void:
	var src := _src()
	assert_true(src.contains("has_animation(&\"weak\")"),
		"only bard and mage ship a weak sheet; the other three must fall through to idle without a branch")
