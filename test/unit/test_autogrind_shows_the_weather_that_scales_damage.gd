extends GutTest

## Visual autogrind watches the battlefield (the log panel becomes a console; the field stays up)
## and BattleManager still scales spells by GameState's live weather. The weather layer forced
## itself to "clear" whenever autogrind_console_mode was set, so a grind in the rain showed a
## dry field and no "~ RAIN ~" tag while Fire landed at 0.75×. A storm that rolled in mid-grind
## stayed invisible the same way. The tag exists so that modifier is never invisible.

const BS := preload("res://src/battle/BattleScene.gd")


class QuietBattle extends BS:
	func _ready() -> void:
		pass


var _saved_condition: String = ""
var _saved_timer: float = 0.0
var _saved_pin: int = 0


func before_each() -> void:
	_saved_condition = GameState.weather_condition
	_saved_timer = GameState.weather_timer
	_saved_pin = GameState._weather_world


func after_each() -> void:
	GameState.weather_condition = _saved_condition
	GameState.weather_timer = _saved_timer
	GameState._weather_world = _saved_pin


func _scene() -> BS:
	var scene := QuietBattle.new()
	scene.set_process(false)
	# @onready paths resolve on enter. Stub them so a script-only node does not error.
	_stub_onready_paths(scene)
	scene._build_weather_layer()
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


func test_a_manual_battle_still_shows_rain() -> void:
	## CONTROL. If the harness cannot see rain with the console off, the arm below proves nothing.
	GameState.set_weather("rain", 9999.0)
	var scene := _scene()
	scene.autogrind_console_mode = false
	scene._process_weather_layer(0.016)
	var tag: Label = scene.get_node("UI/WeatherTag")
	assert_eq(tag.text, "~ RAIN ~", "a normal battle must label the rain")
	assert_true(tag.visible, "and the label must be on screen")
	assert_true(scene._weather_rain.emitting, "and the field must actually be raining")


func test_autogrind_shows_the_same_weather_that_scales_the_spell() -> void:
	GameState.set_weather("rain", 9999.0)
	var scene := _scene()
	scene.autogrind_console_mode = true
	scene._process_weather_layer(0.016)
	var tag: Label = scene.get_node("UI/WeatherTag")
	assert_eq(scene._weather_rendered, GameState.get_weather(),
		"the field rendered '%s' while damage reads '%s' — Fire is scaled by the second one"
		% [scene._weather_rendered, GameState.get_weather()])
	assert_eq(tag.text, "~ RAIN ~",
		"the grind is in the rain, so the tag must say so — a blank tag is a dry field over a wet spell")
	assert_true(tag.visible, "the rain tag must be visible during the grind")
	assert_true(scene._weather_rain.emitting, "rain particles must be on, matching the 0.75× fire modifier")
	assert_almost_eq(scene._weather_overlay.color.a, BS.BATTLE_WEATHER_TINTS["rain"].a, 0.001,
		"the overlay tint must be the rain tint, not clear")
	assert_almost_eq(BattleManager.get_weather_damage_modifier("fire"),
		float(BattleManager.WEATHER_DAMAGE_MODIFIERS["rain"]["fire"]), 0.001,
		"CONTROL: rain must still dampen fire, or the screen and the spell are agreeing about nothing")


func test_a_storm_that_starts_mid_grind_shows_up() -> void:
	## The clock keeps rolling during a grind. A layer stuck on the weather from battle start
	## (or on clear) would keep naming the old sky after the modifier had moved.
	GameState.set_weather("rain", 9999.0)
	var scene := _scene()
	scene.autogrind_console_mode = true
	scene._process_weather_layer(0.016)
	GameState.set_weather("storm", 9999.0)
	scene._process_weather_layer(0.016)
	var tag: Label = scene.get_node("UI/WeatherTag")
	assert_eq(scene._weather_rendered, "storm",
		"the storm rolled in and the field is still showing '%s'" % scene._weather_rendered)
	assert_eq(tag.text, "~ STORM ~", "the tag must follow the storm that now boosts lightning")
	assert_eq(scene._weather_rain.amount, 200, "storm rain is the heavy emitter, not the drizzle one")
	assert_almost_eq(BattleManager.get_weather_damage_modifier("lightning"),
		float(BattleManager.WEATHER_DAMAGE_MODIFIERS["storm"]["lightning"]), 0.001,
		"CONTROL: the storm must be what boosts lightning")


func test_clear_weather_stays_unlabelled_during_a_grind() -> void:
	## The tag is absent on a dry field. Forcing a label up would be a different lie.
	GameState.set_weather("clear", 9999.0)
	var scene := _scene()
	scene.autogrind_console_mode = true
	scene._process_weather_layer(0.016)
	var tag: Label = scene.get_node("UI/WeatherTag")
	assert_eq(scene._weather_rendered, "clear")
	assert_false(tag.visible, "clear weather has no modifier and must not wear a tag")
	assert_false(scene._weather_rain.emitting, "clear weather must not rain")
