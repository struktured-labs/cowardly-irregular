extends GutTest

## Reduce Flashes says it suppresses full-screen flash effects in battle.
## Three battle overlays still painted one anyway:
## the one-shot banner's pale-yellow rect (full screen, alpha 0.6, gone in 0.4s),
## the autobattle banner's cyan rect (full screen, alpha 0.5, gone in 0.4s),
## and the lightning storm's dark sky (full screen, alpha 0 to 0.55 in 0.1s,
## a short hold, then out). That sky is a luminance pulse, not the slow cast dim
## that stays up for the whole ability. Banner text and the storm's bolts are
## not flashes, so they stay. With the setting off, each overlay still appears.

const BS := preload("res://src/battle/BattleScene.gd")

## _ready would boot a battle and need the scene's nodes. These handlers only
## build overlays, so a quiet subclass is enough to watch them.
class QuietBattle extends BS:
	func _ready() -> void:
		pass


var _saved_flashes: bool = false
var _saved_one_shot: bool = false


func before_each() -> void:
	_saved_flashes = GameState.reduce_flashes
	_saved_one_shot = BattleManager._one_shot_achieved
	BattleManager._one_shot_achieved = false


func after_each() -> void:
	GameState.reduce_flashes = _saved_flashes
	BattleManager._one_shot_achieved = _saved_one_shot


func test_banner_and_sky_flashes_are_suppressed_when_reduce_flashes_is_on() -> void:
	GameState.reduce_flashes = true
	var scene := _scene()
	await scene._on_one_shot_achieved("S", 1)
	assert_eq(_banner_flashes(scene, "OneShotFlash").size(), 0,
		"the one-shot banner still covers the screen in pale yellow while Reduce Flashes is on")
	assert_true(_banner_texts(scene, "OneShotFlash").has("ONE-SHOT!"),
		"the ONE-SHOT banner text must stay when only the flash is skipped")
	assert_true(_banner_texts(scene, "OneShotFlash").has("Rank: S"),
		"the rank line must stay when only the flash is skipped")
	await scene._on_autobattle_victory(2.0, 4)
	assert_eq(_banner_flashes(scene, "AutobattleFlash").size(), 0,
		"the autobattle banner still covers the screen in cyan while Reduce Flashes is on")
	assert_true(_banner_texts(scene, "AutobattleFlash").has("AUTO-BATTLE!"),
		"the AUTO-BATTLE banner text must stay when only the flash is skipped")
	assert_true(_banner_texts(scene, "AutobattleFlash").has("4 turns automated"),
		"the turns line must stay when only the flash is skipped")
	var storm := _scene()
	storm._full_render_storm(Color(0.7, 0.85, 1.0), Vector2(200, 200), 1.0)
	assert_eq(_direct_rects(storm).size(), 0,
		"the lightning storm still drops a full-screen dark sky while Reduce Flashes is on")
	await get_tree().create_timer(0.10).timeout
	assert_gt(_line_count(storm), 0,
		"the storm's bolts must still strike when only the sky overlay is skipped")
	assert_eq(_direct_rects(storm).size(), 0,
		"the storm's white bolt flashes must stay suppressed with the sky")


func test_banner_and_sky_flashes_still_play_when_reduce_flashes_is_off() -> void:
	GameState.reduce_flashes = false
	var scene := _scene()
	await scene._on_one_shot_achieved("S", 1)
	var one := _banner_flashes(scene, "OneShotFlash")
	assert_eq(one.size(), 1, "the one-shot banner must still flash when Reduce Flashes is off")
	assert_almost_eq(one[0].color.r, 1.0, 0.001, "one-shot flash stays pale yellow")
	assert_almost_eq(one[0].color.g, 1.0, 0.001, "one-shot flash stays pale yellow")
	assert_almost_eq(one[0].color.b, 0.8, 0.001, "one-shot flash stays pale yellow")
	assert_gt(one[0].color.a, 0.4, "one-shot flash is still on screen, not already gone")
	assert_true(_banner_texts(scene, "OneShotFlash").has("ONE-SHOT!"),
		"the ONE-SHOT banner text still plays with the flash")
	await scene._on_autobattle_victory(2.0, 4)
	var auto := _banner_flashes(scene, "AutobattleFlash")
	assert_eq(auto.size(), 1, "the autobattle banner must still flash when Reduce Flashes is off")
	assert_almost_eq(auto[0].color.r, 0.4, 0.001, "autobattle flash stays cyan")
	assert_almost_eq(auto[0].color.g, 0.8, 0.001, "autobattle flash stays cyan")
	assert_almost_eq(auto[0].color.b, 1.0, 0.001, "autobattle flash stays cyan")
	assert_gt(auto[0].color.a, 0.3, "autobattle flash is still on screen, not already gone")
	assert_true(_banner_texts(scene, "AutobattleFlash").has("AUTO-BATTLE!"),
		"the AUTO-BATTLE banner text still plays with the flash")
	var storm := _scene()
	storm._full_render_storm(Color(0.7, 0.85, 1.0), Vector2(200, 200), 1.0)
	var skies := _direct_rects(storm)
	assert_eq(skies.size(), 1, "the storm must still drop its dark sky when Reduce Flashes is off")
	assert_true(skies[0].color.is_equal_approx(Color(0.05, 0.06, 0.14, 0.0)),
		"the sky is the dark full-screen drop, not a bolt or a bright flash")
	await get_tree().create_timer(0.10).timeout
	assert_gt(_line_count(storm), 0, "the storm's bolts still strike when the setting is off")
	assert_gt(_bright_rects(storm), 0, "the white bolt flash still plays when the setting is off")


func test_autobattle_flash_stays_skipped_when_one_shot_already_flashed() -> void:
	## Control: stacking already omitted the cyan rect. The setting must not bring it back.
	GameState.reduce_flashes = false
	BattleManager._one_shot_achieved = true
	var scene := _scene()
	await scene._on_autobattle_victory(2.0, 4)
	assert_eq(_banner_flashes(scene, "AutobattleFlash").size(), 0,
		"a stacked autobattle banner must not add a second full-screen flash")
	assert_true(_banner_texts(scene, "AutobattleFlash").has("AUTO-BATTLE!"),
		"the stacked banner text still shows")


func _scene() -> BS:
	var scene := QuietBattle.new()
	# @onready paths resolve on enter. Stub them so a script-only node does not error.
	_stub_onready_paths(scene)
	add_child_autofree(scene)
	return scene


func _stub_onready_paths(scene: Node) -> void:
	var leaves: Array = [
		["UI/BattleLogPanel/MarginContainer/VBoxContainer/BattleLog", "rich"],
		["UI/TurnInfoPanel/TurnInfo", "label"],
		["UI/ActionMenuPanel", "panel"],
		["UI/ActionMenuPanel/MarginContainer/VBoxContainer/AttackButton", "button"],
		["UI/ActionMenuPanel/MarginContainer/VBoxContainer/AbilityButton", "button"],
		["UI/ActionMenuPanel/MarginContainer/VBoxContainer/ItemButton", "button"],
		["UI/ActionMenuPanel/MarginContainer/VBoxContainer/DefaultButton", "button"],
		["UI/ActionMenuPanel/MarginContainer/VBoxContainer/BideButton", "button"],
		["UI/PartyStatusPanel/VBoxContainer/Character1/Name", "label"],
		["UI/PartyStatusPanel/VBoxContainer/Character1/HP", "bar"],
		["UI/PartyStatusPanel/VBoxContainer/Character1/HP/HPLabel", "label"],
		["UI/PartyStatusPanel/VBoxContainer/Character1/MP", "bar"],
		["UI/PartyStatusPanel/VBoxContainer/Character1/MP/MPLabel", "label"],
		["UI/PartyStatusPanel/VBoxContainer/Character1/AP", "label"],
		["BattleField/EnemySprites", "node2d"],
		["BattleField/PartySprites", "node2d"],
		["BattleField/EnemyArea/Enemy1Pos", "marker"],
		["BattleField/EnemyArea/Enemy2Pos", "marker"],
		["BattleField/EnemyArea/Enemy3Pos", "marker"],
		["BattleField/PartyArea/Player1Pos", "marker"],
		["BattleField/PartyArea/Player2Pos", "marker"],
		["BattleField/PartyArea/Player3Pos", "marker"],
		["BattleField/PartyArea/Player4Pos", "marker"],
		["BattleField/PartyArea/Player5Pos", "marker"],
	]
	for row in leaves:
		_ensure_path(scene, str(row[0]), str(row[1]))


func _ensure_path(root: Node, path: String, kind: String) -> void:
	var parent := root
	var parts := path.split("/")
	for i in range(parts.size()):
		var part := str(parts[i])
		var child := parent.get_node_or_null(part)
		if child == null:
			var leaf: bool = i == parts.size() - 1
			child = _make_node(kind if leaf else "node")
			child.name = part
			parent.add_child(child)
		parent = child


func _make_node(kind: String) -> Node:
	match kind:
		"rich":
			return RichTextLabel.new()
		"label":
			return Label.new()
		"panel":
			return PanelContainer.new()
		"button":
			return Button.new()
		"bar":
			return ProgressBar.new()
		"node2d":
			return Node2D.new()
		"marker":
			return Marker2D.new()
		_:
			return Node.new()


func _banner_flashes(scene: Node, banner_name: String) -> Array[ColorRect]:
	var found: Array[ColorRect] = []
	var banner := scene.get_node_or_null(banner_name)
	if banner == null:
		return found
	for c in banner.get_children():
		if c is ColorRect:
			found.append(c)
	return found


func _banner_texts(scene: Node, banner_name: String) -> PackedStringArray:
	var found := PackedStringArray()
	var banner := scene.get_node_or_null(banner_name)
	if banner == null:
		return found
	for c in banner.get_children():
		if c is Label:
			found.append((c as Label).text)
	return found


func _direct_rects(scene: Node) -> Array[ColorRect]:
	var found: Array[ColorRect] = []
	for c in scene.get_children():
		if c is ColorRect:
			found.append(c)
	return found


func _bright_rects(scene: Node) -> int:
	var n := 0
	for c in _direct_rects(scene):
		if c.color.r > 0.8 and c.color.g > 0.8 and c.color.b > 0.8:
			n += 1
	return n


func _line_count(scene: Node) -> int:
	var n := 0
	for c in scene.get_children():
		if c is Line2D:
			n += 1
	return n
