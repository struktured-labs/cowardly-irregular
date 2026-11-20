extends GutTest

## struktured's 200% frame (cowir-main 26648/26666, measured on .812): the battle command menu was 512x386 at y 324, so it
## ended at 710 with the hint bar at 670, and enemy name tags read through its face. The menu chain now ends above the hint
## bar at every Text Size, and a name tag under an open menu is not drawn.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const BCM := preload("res://src/battle/BattleCommandMenu.gd")
const MENU_WAIT_FRAMES := 240
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
	## Names as long as the real party's: with four-letter names the panel never grew to where a 200% menu reaches it.
	for nm in ["Fighter", "Cleric", "Rogue", "Mage", "Bard"].slice(0, n):
		var c := Combatant.new()
		c.initialize({"name": nm, "max_hp": 1948, "max_mp": 132, "attack": 25, "defense": 15, "magic": 12, "speed": 12})
		autofree(c)
		out.append(c)
	return out


## A live battle at `scale`, waited until a command menu is up (bounded); [scene, menu or null].
func _battle_with_menu(scale: float) -> Array:
	GameState.text_size_scale = scale
	var party := _party(5)
	BattleManager.player_party.assign(party)
	var scene = SCENE.instantiate()
	scene.set_party(party)
	add_child_autofree(scene)
	var menu = null
	for f in MENU_WAIT_FRAMES:
		await get_tree().process_frame
		menu = scene.get("active_win98_menu")
		if is_instance_valid(menu) and (menu as Control).size.y > 0.0:
			break
	for f in 4:
		await get_tree().process_frame
	return [scene, menu if is_instance_valid(menu) else null]


func test_the_floor_names_what_this_file_drives() -> void:
	var scene = SCENE.instantiate()
	add_child_autofree(scene)
	assert_true(scene.has_method("menu_floor_y"), "FLOOR: BattleScene.menu_floor_y")
	assert_true(scene.has_method("menu_right_wall_x"), "FLOOR: BattleScene.menu_right_wall_x")
	assert_true(scene.has_method("_hide_name_plates_under_menus"), "FLOOR: BattleScene._hide_name_plates_under_menus")
	var m := Win98Menu.new()
	autofree(m)
	assert_true("screen_floor_y" in m, "FLOOR: Win98Menu.screen_floor_y")


func test_a_menu_y_ends_above_the_floor_and_never_passes_the_top() -> void:
	assert_eq(BCM.menu_y_above_floor(324.0, 386.0, 666.0), 280.0, "his frame: a 386 px menu at 324 rises to end at 666")
	assert_eq(BCM.menu_y_above_floor(161.0, 218.0, 682.0), 161.0, "CONTROL: a menu that already fits is not moved")
	assert_eq(BCM.menu_y_above_floor(400.0, 700.0, 666.0), 30.0, "a menu taller than the band keeps its top row on screen")


## THE DEFECT, on the menu itself: with a floor it ends above it; without one the same menu ends below (the shipped clamp).
func test_a_menu_with_a_floor_ends_above_it() -> void:
	var rows: Array = []
	for i in 7:
		rows.append({"label": "Row %d" % i, "id": "r%d" % i})
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var floor_y: float = vp.y - 60.0
	var loose := Win98Menu.new()
	add_child_autofree(loose)
	loose.setup("Hero", rows, Vector2(300, vp.y - 40.0), "fighter")
	await get_tree().process_frame
	assert_gt(loose.position.y + loose.size.y, floor_y, "CONTROL: with no floor the menu ends at %d, below %d" % [int(loose.position.y + loose.size.y), int(floor_y)])
	var held := Win98Menu.new()
	held.screen_floor_y = floor_y
	add_child_autofree(held)
	held.setup("Hero", rows, Vector2(300, vp.y - 40.0), "fighter")
	await get_tree().process_frame
	assert_lte(held.position.y + held.size.y, floor_y + 0.5, "with a floor the menu ends at %d, above %d" % [int(held.position.y + held.size.y), int(floor_y)])
	assert_eq(held.size, loose.size, "the menu is moved, not shrunk")


## The live battle: at every Text Size the command menu ends above the hint bar.
func test_the_live_command_menu_ends_above_the_hint_bar_at_every_text_size() -> void:
	var bad: Array = []
	var judged := 0
	for s in _presets():
		var b: Array = await _battle_with_menu(float(s))
		assert_not_null(b[1], "CONTROL @%s: a command menu opened" % s)
		if b[1] != null:
			judged += 1
			var m := b[1] as Control
			## Read off the hint bar itself, so a floor that ignores the bar cannot agree with its own mistake.
			var hint := b[0].get_node_or_null("UI/InputHintBar") as Control
			assert_true(hint != null and hint.is_visible_in_tree(), "CONTROL @%s: the hint bar shows" % s)
			var floor_y: float = hint.get_global_rect().position.y - 4.0 if hint else 0.0
			var end_y: float = m.get_global_rect().end.y
			gut.p("    @%s menu %s ends %d, floor %d" % [s, str(m.get_global_rect().size), int(end_y), int(floor_y)])
			assert_eq(float(m.get("screen_floor_y")), floor_y, "@%s the menu carries the battle's floor" % s)
			if end_y > floor_y + 0.5:
				bad.append("@%s the menu ends %d vs the hint bar's floor %d" % [s, int(end_y), int(floor_y)])
		b[0].queue_free()
		await get_tree().process_frame
	assert_gt(judged, 0, "CONTROL: menus were judged")
	assert_eq(bad, [], "the command menu ends above the hint bar:\n%s" % "\n".join(PackedStringArray(bad)))


## A name tag under an open menu is not drawn; it comes back when the menu moves off it.
func test_a_name_tag_under_an_open_menu_is_not_drawn() -> void:
	var b: Array = await _battle_with_menu(1.0)
	assert_not_null(b[1], "CONTROL: a command menu opened")
	if b[1] == null:
		return
	var tag: Control = null
	for sprite in b[0].enemy_sprite_nodes:
		if is_instance_valid(sprite) and sprite.get_node_or_null("NameLabel") != null:
			tag = sprite.get_node("NameLabel")
			break
	assert_not_null(tag, "CONTROL: an enemy carries a name tag")
	if tag == null:
		return
	var menu := b[1] as Control
	var rect: Rect2 = tag.get_global_transform() * Rect2(Vector2.ZERO, tag.size)
	menu.global_position = Vector2(-4000, -4000)
	b[0]._hide_name_plates_under_menus()
	assert_eq(tag.self_modulate.a, 1.0, "CONTROL: with the menu away the tag is drawn")
	menu.global_position = rect.position - Vector2(10, 10)
	b[0]._hide_name_plates_under_menus()
	assert_eq(tag.self_modulate.a, 0.0, "under the menu %s the tag %s is not drawn" % [str(menu.get_global_rect()), str(rect)])
	menu.global_position = Vector2(-4000, -4000)
	b[0]._hide_name_plates_under_menus()
	assert_eq(tag.self_modulate.a, 1.0, "and it comes back when the menu moves off it")


## cowir-main 26747, read off a real 200% frame: the root menu's right edge and "+1 AP" chip covered the PARTY panel's
## portraits and names. The menu now ends left of the panel at every Text Size.
func test_a_menu_x_ends_left_of_the_wall_and_never_passes_the_left_margin() -> void:
	assert_eq(BCM.menu_x_left_of(537.6, 512.0, 977.0), 465.0, "his frame: a 512 px menu at 537 moves left to end at 977")
	assert_eq(BCM.menu_x_left_of(537.6, 284.0, 1067.0), 537.6, "CONTROL: a menu that already clears the panel is not moved")
	assert_eq(BCM.menu_x_left_of(300.0, 1400.0, 977.0), 10.0, "a menu wider than the room keeps its left edge on screen")


func test_the_live_command_menu_ends_left_of_the_party_panel_at_every_text_size() -> void:
	var bad: Array = []
	var judged := 0
	var reached := 0
	for s in _presets():
		var b: Array = await _battle_with_menu(float(s))
		assert_not_null(b[1], "CONTROL @%s: a command menu opened" % s)
		if b[1] != null:
			judged += 1
			var m := (b[1] as Control).get_global_rect()
			## Read off the panel itself, so a wall that ignores the panel cannot agree with its own mistake.
			var panel := b[0].get_node_or_null("UI/PartyStatusPanel") as Control
			assert_true(panel != null and panel.is_visible_in_tree(), "CONTROL @%s: the PARTY panel shows" % s)
			var panel_left: float = panel.get_global_rect().position.x if panel else 0.0
			gut.p("    @%s menu x %d..%d, panel starts %d" % [s, int(m.position.x), int(m.end.x), int(panel_left)])
			## Where the menu WOULD end if nothing held it: its opening column plus its width. The arm judges only where that reaches the panel.
			var unheld_end: float = 1280.0 * 0.42 + m.size.x
			if unheld_end > panel_left + 0.5:
				reached += 1
			if m.end.x > panel_left + 0.5:
				bad.append("@%s the menu ends at x %d, over the panel that starts at %d" % [s, int(m.end.x), int(panel_left)])
		b[0].queue_free()
		await get_tree().process_frame
	assert_gt(judged, 0, "CONTROL: menus were judged")
	assert_gt(reached, 0, "CONTROL: at some Text Size an unheld menu would reach the panel, so the arm can fail")
	assert_eq(bad, [], "the command menu ends left of the PARTY panel:\n%s" % "\n".join(PackedStringArray(bad)))

