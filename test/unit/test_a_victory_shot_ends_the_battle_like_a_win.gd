extends GutTest

## adhoc 26238 read a turn header under VICTORY! off a victory_card_shots frame; a real win hides it, the tool skipped that path.
## The hiding is now ONE function the win and both victory shot tools call, so a shot cannot show a HUD a player never sees.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const SRC := "res://src/battle/BattleScene.gd"
const TOOLS := ["res://tools/victory_card_shots.gd", "res://tools/victory_clip.gd"]
const HUD := ["UI/TurnInfoPanel", "UI/InputHintBar"]
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

var _guard


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_guard = BattleStateGuard.new()
	_guard.snapshot()


## A BattleScene starts a battle; without this the next files read BattleManager mid-battle (state=3, the .807 slot).
func after_each() -> void:
	_guard.restore()


func after_all() -> void:
	SoundState.restore()


func test_the_floor_names_every_member_this_file_drives() -> void:
	var m: Array = (load(SRC) as GDScript).get_script_method_list().map(func(x): return str(x["name"]))
	for f in ["retire_battle_hud", "_on_battle_ended"]:
		assert_has(m, f, "BattleScene.%s must exist" % f)


func test_retiring_the_hud_hides_what_only_a_live_turn_uses() -> void:
	var scene = SCENE.instantiate()
	scene.encounter_enemies = ["goblin"]
	add_child_autofree(scene)
	await wait_frames(4)
	var nodes: Array = []
	for path in HUD:
		var n := scene.get_node_or_null(path) as CanvasItem
		assert_not_null(n, "CONTROL: %s exists in a live battle" % path)
		if n != null:
			n.visible = true
			nodes.append(n)
	var speed := scene.find_child("SpeedPanel", true, false) as CanvasItem
	assert_not_null(speed, "CONTROL: SpeedPanel exists in a live battle")
	if speed != null:
		speed.visible = true
		nodes.append(speed)
	scene.retire_battle_hud()
	for n in nodes:
		assert_false((n as CanvasItem).visible, "%s is hidden once the battle is over" % (n as Node).name)


## The body of `fname` in `src`: from its own header to the next top-level func (both boundaries, so a neighbour cannot satisfy it).
func _body(src: String, fname: String) -> String:
	var at := src.find("\nfunc %s(" % fname)
	assert_gt(at, -1, "CONTROL: %s is in the source" % fname)
	if at < 0:
		return ""
	var end := src.find("\nfunc ", at + 1)
	return src.substr(at, (end if end > 0 else src.length()) - at)


func _code_lines(text: String) -> String:
	var out := PackedStringArray()
	for line in text.split("\n"):
		if not line.strip_edges().begins_with("#"):
			out.append(line.split("#")[0])
	return "\n".join(out)


func test_a_win_and_every_victory_shot_tool_retire_the_same_hud() -> void:
	var src := FileAccess.get_file_as_string(SRC)
	assert_string_contains(_code_lines(_body(src, "_on_battle_ended")), "retire_battle_hud()", false)
	assert_false(_code_lines(_body(src, "_on_battle_ended")).contains("TurnInfoPanel"), "the win hides the HUD through retire_battle_hud, not a private copy")
	for t in TOOLS:
		var code := _code_lines(FileAccess.get_file_as_string(t))
		assert_true(code.contains("BattleState.VICTORY"), "CONTROL: %s fakes a win" % t)
		assert_true(code.contains("retire_battle_hud()"), "%s fakes a win, so it must retire the HUD a win retires" % t)
