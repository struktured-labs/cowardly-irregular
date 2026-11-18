extends GutTest

## The limit-break job stinger replaced the battle bed with play_music on EVERY limit break, with no gate, while the
## other signature sounds stop at turbo and in the autogrind console (signature_sound_allowed). So a grind or a 4x
## fight swapped its music for a 4.5-13.5 s stinger each time. Regression for that: the stinger still plays at
## normal speed (CONTROL), and returns "" when signature sounds are off.

const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
const BS_PATH := "res://src/battle/BattleScene.gd"

var _scene: Node = null
var _leader: Combatant = null


func before_each() -> void:
	_scene = load(BS_PATH).new()
	_leader = Combatant.new()
	_leader.job = {"id": "fighter"}


func after_each() -> void:
	if _leader != null:
		_leader.free()
		_leader = null
	if _scene != null:
		_scene.free()
		_scene = null


func test_control_the_stinger_plays_at_normal_speed() -> void:
	assert_true(SoundManager.music_is_available("job_fighter_special"),
		"CONTROL: the fighter's stinger is authored, so an empty answer below means the gate, not a missing track")
	assert_eq(_scene.limit_break_stinger_key([_leader]), "job_fighter_special",
		"at normal speed a limit break still plays the leader's job stinger")


func test_turbo_keeps_the_battle_bed() -> void:
	_scene.turbo_mode = true
	assert_eq(_scene.limit_break_stinger_key([_leader]), "",
		"at turbo the limit break must not swap the battle bed for the stinger")


func test_the_autogrind_console_keeps_the_battle_bed() -> void:
	_scene.autogrind_console_mode = true
	assert_eq(_scene.limit_break_stinger_key([_leader]), "",
		"in the autogrind console the limit break must not swap the battle bed for the stinger")


func test_no_leader_means_no_stinger() -> void:
	assert_eq(_scene.limit_break_stinger_key([]), "", "an empty participant list picks no stinger")


func test_the_limit_break_branch_plays_only_what_the_helper_returns() -> void:
	var code: String = GdSourceHelper.code_of(BS_PATH)
	var at: int = code.find("func _on_group_attack_executing(")
	assert_gt(at, -1, "CONTROL: the group-attack handler survives comment stripping")
	var body: String = code.substr(at, code.find("\nfunc ", at + 1) - at)
	assert_true(body.contains("limit_break_stinger_key(participants)"),
		"the limit-break branch must ask the gated helper for its stinger")
	assert_false(body.contains("music_is_available("),
		"and must not pick a stinger itself, which would bypass the turbo/console gate")
