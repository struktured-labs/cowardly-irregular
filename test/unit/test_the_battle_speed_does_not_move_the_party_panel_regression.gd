extends GutTest

## struktured 2026-11-07: "64x speed shifts the panel down". The speed readout rides the PARTY panel's wrapping header row;
## its 64x arm (six arrows a side, 107 px) no longer fit beside the header's other items, the row wrapped, and the whole
## PARTY panel grew 32 px (measured: 665 -> 697 at rung 7 only). Now every rung reserves the widest rung's width and the
## 64x arm draws five arrows like 32x, so the speed never moves a panel.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BS := preload("res://src/battle/BattleScene.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")

var _guard
var _saved_index := 0
var _saved_scale = null


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_saved_index = BS._battle_speed_index
	_saved_scale = GameState.text_size_scale


func after_each() -> void:
	BS._battle_speed_index = _saved_index
	GameState.text_size_scale = _saved_scale
	Engine.time_scale = 1.0
	_guard.restore()


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS resolves")
	return p


## {rung: [party panel, header row, speed panel]} rects for one scene at the current Text Size.
func _rects_per_rung(scene) -> Dictionary:
	var out := {}
	var party := scene.get_node("UI/PartyStatusPanel") as Control
	var row := scene.get_node_or_null("UI/PartyStatusPanel/VBoxContainer/HeaderRow") as Control
	var speed := (scene.get("_speed_indicator") as Control).get_parent() as Control
	for i in BS.BATTLE_SPEEDS.size():
		BS._battle_speed_index = i
		scene._update_speed_indicator()
		for f in 3:
			await get_tree().process_frame
		out[i] = [party.get_global_rect(), row.get_global_rect() if row else Rect2(), speed.get_global_rect()]
	return out


func test_no_panel_moves_with_the_speed_at_any_text_size() -> void:
	var moved: Array = []
	for scale in _presets():
		GameState.text_size_scale = scale
		var scene = SCENE.instantiate()
		add_child_autofree(scene)
		for f in 4:
			await get_tree().process_frame
		assert_not_null(scene.get("_speed_indicator"), "CONTROL: the battle built its speed readout at %s" % str(scale))
		var rects: Dictionary = await _rects_per_rung(scene)
		for i in rects:
			for k in 3:
				if not rects[i][k].is_equal_approx(rects[0][k]):
					moved.append("@%s rung %d: %s %s vs rung 0 %s" % [str(scale), i, ["PARTY panel", "header row", "speed readout"][k], str(rects[i][k]), str(rects[0][k])])
		scene.queue_free()
		await get_tree().process_frame
	assert_eq(moved, [], "changing the battle speed must not move or resize a panel")

