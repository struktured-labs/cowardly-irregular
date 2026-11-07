extends GutTest

## struktured's show-floor ask (main 23186), battle half of design 23190: the ability submenu's description zooms on
## AbilityZoom's button (west + A), grows AbilityZoom.FACTOR on top of Text Size, keeps Up/Down, makes Confirm and Advance
## inert, and un-zooms on Back without closing. West is Repeat elsewhere in battle; on the ability list it must zoom.

const Win98MenuClass = preload("res://src/ui/Win98Menu.gd")
const LONG := "Calls down a pillar of lightning that strikes every foe at once, then lingers as static that may stun anything still standing when it clears."

var _saved_scale = null


class ProbeScene extends "res://src/battle/BattleScene.gd":
	var repeats: int = 0
	func _repeat_previous_actions() -> void:
		repeats += 1


func before_each() -> void:
	_saved_scale = GameState.text_size_scale


func after_each() -> void:
	GameState.text_size_scale = _saved_scale


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS resolves")
	return p


func _ability_rows() -> Array:
	return [
		{"id": "ability_menu_thundaga", "label": "Thundaga", "tooltip": LONG, "submenu": [{"id": "ability_thundaga_enemy_0", "label": "Goblin"}]},
		{"id": "ability_menu_cure", "label": "Cure", "tooltip": "Restores HP to one ally.", "submenu": [{"id": "ability_cure_ally_0", "label": "Bram"}]},
	]


## A root command menu with the Ability row opened, as the battle builds it. Returns [root, ability_list].
func _opened() -> Array:
	var holder := Control.new()
	add_child_autofree(holder)
	holder.size = Vector2(1280, 720)
	var root = Win98MenuClass.new()
	holder.add_child(root)
	# The ROOT carries quick-slot ability rows with the same ids (BattleCommandMenu's MRU/pins), as a real command menu does.
	var items := [{"id": "ability_menu", "label": "Ability", "submenu": _ability_rows()}, {"id": "attack_menu", "label": "Attack"},
		{"id": "ability_menu_thundaga", "label": "Thundaga", "tooltip": LONG, "submenu": [{"id": "ability_thundaga_enemy_0", "label": "Goblin"}]}]
	root.setup("Fighter", items, Vector2(400, 420), "fighter")
	for i in 3:
		await get_tree().process_frame
	root._can_accept_input = true
	root._do_open_submenu(0, items[0])
	for i in 3:
		await get_tree().process_frame
	var sub = root.submenu
	assert_not_null(sub, "CONTROL: the Ability submenu opened")
	if sub:
		sub._can_accept_input = true
	return [root, sub]


func _action(name: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


func _drawn_h(label: Label) -> float:
	return float(label.get_line_count()) * label.get_theme_font("font").get_height(label.get_theme_font_size("font_size"))


func test_the_zoom_action_is_the_shared_one() -> void:
	assert_true(InputMap.has_action(AbilityZoom.ACTION), "FLOOR: the shared ability_zoom action exists")
	var west := false
	var key_a := false
	for ev in InputMap.action_get_events(AbilityZoom.ACTION):
		west = west or (ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_X)
		key_a = key_a or (ev is InputEventKey and (ev.keycode == KEY_A or ev.physical_keycode == KEY_A))
	assert_true(west and key_a, "the battle zoom reads the same west + A as the field one")


func test_the_zoomed_description_grows_and_fits_at_every_text_size() -> void:
	var problems: Array = []
	for scale in _presets():
		GameState.text_size_scale = scale
		var pair: Array = await _opened()
		var sub = pair[1]
		if sub == null:
			continue
		sub._update_tooltip()
		var label: Label = sub._tooltip_label
		assert_not_null(label, "CONTROL: the description label exists at %s" % str(scale))
		var unzoomed: int = label.get_theme_font_size("font_size")
		sub._input(_action(AbilityZoom.ACTION))
		await get_tree().process_frame
		await get_tree().process_frame
		assert_true(sub.is_zoomed(), "CONTROL: the zoom took at %s" % str(scale))
		var zoomed: int = label.get_theme_font_size("font_size")
		if zoomed <= unzoomed:
			problems.append("@%s zoomed %d px is not larger than %d" % [str(scale), zoomed, unzoomed])
		var vp: Vector2 = sub.get_viewport_rect().size
		var r := Rect2(label.global_position, Vector2(label.size.x, _drawn_h(label)))
		if r.position.x < 0.0 or r.end.x > vp.x + 0.5 or r.position.y < 0.0 or r.end.y > vp.y * 0.5 + 0.5:
			problems.append("@%s the zoomed text %s leaves its band (screen %s)" % [str(scale), str(r), str(vp)])
		pair[0].force_close()
	assert_eq(problems, [], "the zoomed description must grow at every Text Size and fit its band")


func test_up_down_step_while_zoomed() -> void:
	var pair: Array = await _opened()
	var sub = pair[1]
	sub._input(_action(AbilityZoom.ACTION))
	await get_tree().process_frame
	var before: int = sub.selected_index
	sub._input(_action("ui_down"))
	await get_tree().process_frame
	assert_ne(sub.selected_index, before, "Down steps to the next ability while zoomed")
	assert_true(sub.is_zoomed(), "and the reading view stays zoomed")
	assert_eq(sub._tooltip_label.text, "Restores HP to one ally.", "showing the newly highlighted ability")
	pair[0].force_close()


func test_confirm_and_advance_are_inert_while_zoomed() -> void:
	var pair: Array = await _opened()
	var sub = pair[1]
	var root = pair[0]
	var opened: Array = []
	root.item_selected.connect(func(id, _d): opened.append(id))
	sub._input(_action(AbilityZoom.ACTION))
	await get_tree().process_frame
	sub._input(_action("ui_accept"))
	sub._input(_action("battle_advance"))
	await get_tree().process_frame
	assert_null(sub.submenu, "Confirm while zoomed opens no target list")
	assert_eq(opened, [], "and nothing is chosen")
	assert_eq(root._queued_actions.size(), 0, "Advance while zoomed queues nothing")
	root.force_close()


func test_back_unzooms_without_closing() -> void:
	var pair: Array = await _opened()
	var root = pair[0]
	var sub = pair[1]
	sub._input(_action(AbilityZoom.ACTION))
	await get_tree().process_frame
	sub._input(_action("ui_cancel"))
	await get_tree().process_frame
	assert_false(sub.is_zoomed(), "Back un-zooms")
	assert_eq(root.submenu, sub, "and the ability list stays open")
	sub._input(_action("ui_cancel"))
	await get_tree().process_frame
	assert_null(root.submenu, "CONTROL: an unzoomed Back closes the list as before")
	root.force_close()


func test_west_zooms_on_the_ability_list_and_repeats_everywhere_else() -> void:
	var scene = ProbeScene.new()
	add_child_autofree(scene)
	await get_tree().process_frame
	var pair: Array = await _opened()
	var root = pair[0]
	scene.active_win98_menu = root
	var west := InputEventJoypadButton.new()
	west.button_index = JOY_BUTTON_X
	west.pressed = true
	assert_true(scene.ability_list_open(), "CONTROL: the ability list is open")
	scene._input(west)
	assert_eq(scene.repeats, 0, "west on the ability list must not Repeat last turn")
	root.submenu.queue_free()
	root.submenu = null
	assert_false(root.is_ability_list(), "a command menu holding quick-slot ability rows is not the ability list")
	assert_false(scene.ability_list_open(), "CONTROL: back on the command menu")
	scene._input(west)
	assert_eq(scene.repeats, 1, "CONTROL: west on the command menu still Repeats")
	scene.active_win98_menu = null
	root.force_close()


func test_the_chip_names_the_derived_button() -> void:
	var pair: Array = await _opened()
	var sub = pair[1]
	sub._update_tooltip()
	var chip := sub._tooltip_label.get_node_or_null("ZoomChip") as Label
	assert_not_null(chip, "the ability list's description carries the zoom chip")
	if chip:
		assert_eq(chip.text, "%s: Zoom" % AbilityZoom.hint(), "named through the derived hint, never a typed letter")
	pair[0].force_close()
