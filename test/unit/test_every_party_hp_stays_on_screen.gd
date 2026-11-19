extends GutTest

## cowir-main 26303: in battle every member's HP must be visible at once. A live 5-PC panel ran under the hint bar at 100%
## and pushed the 5th HP off-screen from 125% (battle probe 26318). The panel drops rows before anything else gives.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const UIM := preload("res://src/battle/BattleUIManager.gd")
var _guard
var _saved_scale = null


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_saved_scale = GameState.text_size_scale


func after_each() -> void:
	GameState.text_size_scale = _saved_scale
	_guard.restore()


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS resolves")
	return p


func _party(n: int) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for nm in ["Hero", "Mira", "Zack", "Vex", "Lyra"].slice(0, n):
		var c := Combatant.new()
		c.initialize({"name": nm, "max_hp": 1948, "max_mp": 132, "attack": 25, "defense": 15, "magic": 12, "speed": 12})
		autofree(c)
		out.append(c)
	return out


func _visible_named(root: Node, name: String, acc: Array) -> void:
	if root.name == name and root is Control and (root as Control).is_visible_in_tree():
		acc.append(root)
	for ch in root.get_children():
		_visible_named(ch, name, acc)


## A live battle at `scale` with `n` members, settled; [scene, HP labels, the panel's floor].
func _battle(scale: float, n: int) -> Array:
	GameState.text_size_scale = scale
	var scene = SCENE.instantiate()
	scene.set_party(_party(n))
	add_child_autofree(scene)
	for f in 12:
		await get_tree().process_frame
	var hp: Array = []
	_visible_named(scene.get_node("UI/PartyStatusPanel"), "HPLabel", hp)
	return [scene, hp, scene.party_panel_floor_y()]


func test_the_floor_names_what_this_file_drives() -> void:
	var scene = SCENE.instantiate()
	add_child_autofree(scene)
	assert_true(scene.has_method("party_panel_floor_y"), "FLOOR: BattleScene.party_panel_floor_y")
	assert_true(UIM.new(null).has_method("compact_party_panel_step"), "FLOOR: BattleUIManager.compact_party_panel_step")


func test_every_hp_label_sits_above_the_panel_floor_at_every_text_size() -> void:
	var bad: Array = []
	var judged := 0
	for s in _presets():
		for n in [4, 5]:
			var b: Array = await _battle(float(s), n)
			assert_eq(b[1].size(), n, "CONTROL @%s x%d: one visible HP label per member" % [s, n])
			for l in b[1]:
				judged += 1
				var r: Rect2 = (l as Control).get_global_rect()
				if r.end.y > b[2] or r.position.y < 0.0:
					bad.append("@%s x%d %s HP %d..%d vs floor %d" % [s, n, l.get_parent().get_parent().name, int(r.position.y), int(r.end.y), int(b[2])])
			b[0].queue_free()
			await get_tree().process_frame
	assert_gt(judged, 0, "CONTROL: HP labels were judged")
	assert_eq(bad, [], "every member's HP stays on screen:\n%s" % "\n".join(PackedStringArray(bad)))


## The shipped look: 4 members at 100% drop nothing.
func test_four_at_100_percent_drops_no_row() -> void:
	var b: Array = await _battle(1.0, 4)
	assert_eq(b[0].get("_ui_manager").party_compact_tier, 0, "4 members at 100% fit, so no row is dropped")
	var mods: Array = []
	_visible_named(b[0].get_node("UI/PartyStatusPanel"), "StatMods", mods)
	assert_eq(mods.size(), 4, "every box keeps its StatMods row")


## CONTROL that compaction really ran: 5 members at 100% overran the hint bar before it (709 vs 686, probe 26318).
func test_five_at_100_percent_drops_statmods_to_fit() -> void:
	var b: Array = await _battle(1.0, 5)
	assert_gt(b[0].get("_ui_manager").party_compact_tier, 0, "5 members at 100% overrun, so a row is dropped")
	var panel := b[0].get_node("UI/PartyStatusPanel") as Control
	assert_lte(panel.get_global_rect().end.y, b[2], "and the panel then ends above its floor")
