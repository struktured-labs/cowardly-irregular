extends GutTest

## Live-build tests for the battle command menu. Every existing menu test greps SOURCE, which
## is why the Bard/Cleric "no Attack row" bug shipped — a source pin cannot see that a job LOST
## a row. These build the real menu for a real job and assert on the rows that come back.
## Playtest 2026-08-22 (struktured): "the menu is too busy", "bard menu is cutoff on bottom".

const SCENE_PATH := "res://src/battle/BattleScene.gd"
const MenuClass = preload("res://src/battle/BattleCommandMenu.gd")
const Win98MenuClass = preload("res://src/ui/Win98Menu.gd")


var _saved_enemy: Array = []
var _saved_player: Array = []


## BattleManager is an AUTOLOAD and other test files leave FREED combatants in its parties
## (test_calibrant_final_battle does; measured 3 freed entries). A freed entry aborts the
## menu builder somewhere in its body, and an abort in a function returning Array discards
## everything and yields [] — so this file passed alone and returned ZERO ROWS in the suite.
## Purging on entry makes the file hermetic instead of order-dependent.
func before_each() -> void:
	_saved_enemy = BattleManager.enemy_party.duplicate()
	_saved_player = BattleManager.player_party.duplicate()
	var live_e: Array = []
	for e in BattleManager.enemy_party:
		if is_instance_valid(e):
			live_e.append(e)
	var live_p: Array = []
	for p in BattleManager.player_party:
		if is_instance_valid(p):
			live_p.append(p)
	BattleManager.enemy_party.assign(live_e)
	BattleManager.player_party.assign(live_p)


func after_each() -> void:
	BattleManager.enemy_party.assign(_saved_enemy)
	BattleManager.player_party.assign(_saved_player)


## MUST await: build_command_menu_items_with_targets reads _scene.get_viewport() on its THIRD
## line, and a scene not yet in the tree makes that null — which ABORTS the builder and returns
## an empty array. Passed in isolation and failed in the full suite until this await existed;
## the CONTROL assert ("the builder produced a real menu") is what caught it.
func _scene_with_enemies(n: int = 2) -> Node:
	var scene: Node = load(SCENE_PATH).new()
	add_child_autofree(scene)
	await get_tree().process_frame
	var enemies: Array = []
	for i in n:
		var e := Combatant.new()
		add_child_autofree(e)
		e.combatant_name = "Dummy%d" % i
		e.max_hp = 10
		e.current_hp = 10
		enemies.append(e)
	scene.test_enemies.assign(enemies)
	return scene


func _pc(job_id: String) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = job_id.capitalize()
	c.max_hp = 30
	c.current_hp = 30
	c.max_mp = 20
	c.current_mp = 20
	c.job = JobSystem.get_job(job_id)
	return c


func _rows(job_id: String) -> Array:
	var scene = await _scene_with_enemies()
	var menu = MenuClass.new(scene)
	return menu.build_command_menu_items_with_targets(_pc(job_id))


func _ids(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		if r is Dictionary:
			out.append(str(r.get("id", "")))
	return out


func _find(rows: Array, id: String) -> Dictionary:
	for r in rows:
		if r is Dictionary and str(r.get("id", "")) == id:
			return r
	return {}


func test_the_builder_returns_a_real_menu() -> void:
	## CONTROL: everything below is worthless if the build returns nothing.
	var rows: Array = await _rows("bard")
	assert_gt(rows.size(), 3, "CONTROL: the builder produced a real menu")


func test_auto_block_is_one_top_level_row_with_all_three_actions_inside() -> void:
	var rows: Array = await _rows("bard")
	var ids := _ids(rows)
	assert_true("auto_menu" in ids, "the collapsed Auto row exists at top level")
	for buried in ["autobattle", "autobattle_edit", "trust_toggle"]:
		assert_false(buried in ids, "%s must NOT be a top-level row any more" % buried)
	var sub: Array = _find(rows, "auto_menu").get("submenu", [])
	var sub_ids := _ids(sub)
	for needed in ["autobattle", "autobattle_edit", "trust_toggle"]:
		assert_true(needed in sub_ids, "%s is still REACHABLE inside Auto (buried, not deleted)" % needed)


func test_scan_is_not_an_intrinsic_menu_row_for_any_job() -> void:
	## struktured 2026-08-22: "scan should be an ability not intrinsic to a player".
	## It lives in the Rogue's kit; nobody gets weakness intel just for having a turn.
	for job_id in ["fighter", "mage", "cleric", "rogue", "bard"]:
		var ids: Array = _ids(await _rows(job_id))
		assert_false("scan_menu" in ids, "%s must not get a free intrinsic Scan row" % job_id)


func test_scan_ability_still_reveals_through_the_shared_reader() -> void:
	## The reveal must survive losing the menu path: BattleUIManager ORs its own
	## _revealed_enemies dict with the intel_revealed meta that the ability sets, so the
	## ability alone is sufficient. Guarding the OR, because dropping either side is silent.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleUIManager.gd")
	assert_gt(src.length(), 1000, "CONTROL: read a real file")
	assert_true("intel_revealed" in src, "the UI still reads the meta the scan ABILITY sets")
	assert_true("_revealed_enemies" in src, "and still reads the attack-based reveal")


func test_every_job_can_attack_from_the_menu() -> void:
	## THE BUG (struktured 2026-08-22, on Bard): "the bard can attack in auto mode but
	## otherwise cant". free_move REPLACED Attack, so Mage/Cleric/Bard had no basic attack
	## in the menu while autobattle called basic_attack directly and did. Cleric and Mage
	## carried the identical defect unreported — which is why this asserts over ALL jobs,
	## not the one that got noticed.
	for job_id in ["fighter", "mage", "cleric", "rogue", "bard"]:
		var ids: Array = _ids(await _rows(job_id))
		var has_attack: bool = ("attack_menu" in ids) or ("attack" in ids)
		assert_true(has_attack, "%s must be able to attack from the command menu" % job_id)


func test_ability_free_move_jobs_keep_BOTH_attack_and_their_free_move() -> void:
	## The fix must not go the other way and cost them their job identity move.
	var expected := {"mage": "Channel", "cleric": "Pray", "bard": "Riff"}
	for job_id in expected:
		var rows: Array = await _rows(job_id)
		var ids := _ids(rows)
		assert_true("attack_menu" in ids or "attack" in ids, "%s kept Attack" % job_id)
		var labels := ""
		for r in rows:
			if r is Dictionary:
				labels += str(r.get("label", "")) + "|"
		assert_true(str(expected[job_id]) in labels,
			"%s still has its free move %s" % [job_id, expected[job_id]])


func test_basic_attack_jobs_get_exactly_one_attack_row_with_their_own_label() -> void:
	## Fighter/Rogue must NOT gain a duplicate: their free_move IS the attack.
	var expected := {"fighter": "Attack", "rogue": "Strike"}
	for job_id in expected:
		var rows: Array = await _rows(job_id)
		var n := 0
		for r in rows:
			if r is Dictionary and str(r.get("id", "")) in ["attack_menu", "attack"]:
				n += 1
				assert_eq(str(r.get("label", "")), str(expected[job_id]),
					"%s's attack row keeps its own label" % job_id)
		assert_eq(n, 1, "%s has exactly one attack row, not a duplicate" % job_id)


func _built_menu(rows: Array) -> Node:
	var m = Win98MenuClass.new()
	add_child_autofree(m)
	m.setup("Test", rows, Vector2(200, 200), "bard")
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func test_a_very_tall_menu_still_FITS_the_viewport() -> void:
	## struktured 2026-08-22: "bard menu is cutoff on bottom". menu_height had no cap, so
	## _clamp_to_screen computed a negative y, took its `y < 0` branch and pinned the panel at
	## y=10 with the tail off-screen. Asserts the RELATIONSHIP (it fits) — a row count would
	## go red every time the menu legitimately changes shape.
	var rows: Array = []
	for i in 40:
		rows.append({"id": "row%d" % i, "label": "Row %d" % i})
	var m = await _built_menu(rows)
	var vh: float = get_viewport().get_visible_rect().size.y
	assert_gt(vh, 0.0, "CONTROL: a real viewport with a real height")
	assert_gt(m.size.y, 0.0, "CONTROL: the menu actually built")
	assert_true(m.size.y <= vh, "a 40-row menu is capped to the viewport (%d vs %d)" % [m.size.y, vh])
	assert_true(m.position.y + m.size.y <= vh, "and it sits fully ON screen, not just sized to fit")


func test_the_tallest_REAL_battle_menu_fits() -> void:
	## The live Bard menu — the job that actually overflowed — with its submenus.
	var rows: Array = await _rows("bard")
	var m = await _built_menu(rows)
	var vh: float = get_viewport().get_visible_rect().size.y
	assert_gt(rows.size(), 4, "CONTROL: a real, populated Bard menu")
	assert_true(m.position.y + m.size.y <= vh,
		"Bard's full command menu fits on screen (%d rows, bottom at %d of %d)" % [rows.size(), m.position.y + m.size.y, vh])


func test_scrolling_keeps_the_selected_row_inside_the_window() -> void:
	## A cap without scrolling would hide the rows past it instead of clipping them off-screen.
	var rows: Array = []
	for i in 40:
		rows.append({"id": "row%d" % i, "label": "Row %d" % i})
	var m = await _built_menu(rows)
	assert_gt(m._max_visible_rows, 0, "CONTROL: 40 rows actually triggered the cap")
	m.selected_index = 39
	m._update_selection()
	var last_visible: int = m._scroll_offset + m._max_visible_rows - 1
	assert_true(m.selected_index <= last_visible and m.selected_index >= m._scroll_offset,
		"selecting the last row scrolled it into view (offset %d, window %d)" % [m._scroll_offset, m._max_visible_rows])


func test_cost_renders_as_its_own_span_not_glued_to_the_name() -> void:
	## struktured 2026-08-22: the cost "should be colorized differently or stylized from the
	## other text". Pre-fix the row label was one string, "Fire (6)", so the cost could not
	## carry its own colour. Asserts the SPLIT, which is what makes styling possible at all.
	var m = await _built_menu([
		{"id": "a", "label": "Firebolt", "cost": 6, "cost_affordable": true},
		{"id": "b", "label": "Meteor", "cost": 99, "cost_affordable": false},
	])
	var container = m._get_items_container()
	assert_not_null(container, "CONTROL: the menu built its rows")
	var row_a = container.get_child(0)
	var name_a = row_a.get_node_or_null("Label")
	var cost_a = row_a.get_node_or_null("Cost")
	assert_not_null(cost_a, "the cost is its OWN node, not concatenated into the name")
	assert_eq(name_a.text, "Firebolt", "the name span carries the name ALONE")
	assert_true("6" in cost_a.text, "the cost span carries the cost")


func test_an_unaffordable_cost_is_tinted_differently_from_an_affordable_one() -> void:
	## Makes "why is this row greyed" self-evident without a message.
	var m = await _built_menu([
		{"id": "a", "label": "Firebolt", "cost": 6, "cost_affordable": true},
		{"id": "b", "label": "Meteor", "cost": 99, "cost_affordable": false},
	])
	var container = m._get_items_container()
	var ok = container.get_child(0).get_node_or_null("Cost")
	var bad = container.get_child(1).get_node_or_null("Cost")
	assert_not_null(ok)
	assert_not_null(bad)
	var c_ok: Color = ok.get_theme_color("font_color")
	var c_bad: Color = bad.get_theme_color("font_color")
	assert_false(c_ok.is_equal_approx(c_bad), "affordable and unaffordable costs differ in colour")
	assert_gt(c_bad.r, c_bad.g, "the unaffordable tint reads as a warning (red-dominant)")


func test_selecting_an_unaffordable_row_is_not_silent() -> void:
	## struktured 2026-08-22: "a wasted action because of insufficient resources - mp, ap, etc,
	## should have a noise and/or text to indicate it". The rows were ALREADY marked
	## `disabled: not can_afford`; the gap was that activating one returned with no feedback.
	var m = await _built_menu([
		{"id": "cheap", "label": "Firebolt", "cost": 6, "cost_affordable": true},
		{"id": "dear", "label": "Meteor", "cost": 99, "cost_affordable": false, "disabled": true},
	])
	## Seed the cache: the real label lives under an InputHintBar that only exists in a live
	## battle. _find_hint_label() returns the cache when set, so this exercises the REAL path
	## instead of skipping — a pending test defends nothing.
	var hint := Label.new()
	add_child_autofree(hint)
	hint.text = m.HINT_DEFAULT_TEXT
	m._hint_label_cache = hint
	var before: String = hint.text
	## Through the REAL entry point, not the helper — this pins the WIRING at the silent
	## `if disabled: return`, which is where the feedback was actually missing.
	m._can_accept_input = true
	m.selected_index = 1
	m._on_item_pressed(1)
	assert_ne(hint.text, before, "the hint bar says something after a rejected selection")
	assert_true("MP" in hint.text, "and it names the resource: %s" % hint.text)
	assert_true("99" in hint.text, "and how much was needed")


func test_the_reason_line_restores_itself_on_the_next_move() -> void:
	## No timer: a create_timer() restore would drift with Engine.time_scale at 4x/8x
	## battle speed. Restoring on the next navigation is deterministic at any speed.
	var m = await _built_menu([
		{"id": "a", "label": "Firebolt", "cost": 6, "cost_affordable": true},
		{"id": "b", "label": "Meteor", "cost": 99, "cost_affordable": false, "disabled": true},
	])
	var hint := Label.new()
	add_child_autofree(hint)
	hint.text = m.HINT_DEFAULT_TEXT
	m._hint_label_cache = hint
	m._reject_selection(m.menu_items[1])
	assert_true(m._hint_showing_reason, "CONTROL: a reason is actually being shown")
	m.selected_index = 0
	m._update_selection()
	assert_false(m._hint_showing_reason, "moving clears the reason")
	assert_eq(hint.text, m.HINT_DEFAULT_TEXT, "and the hint bar is back to its default")


func test_panel_is_translucent_but_its_border_is_not() -> void:
	## struktured 2026-08-22 wanted the menu more translucent, and flagged it as needing a
	## playtest — so this pins the STRUCTURE (fill fades, frame does not), not the number.
	## The number is PANEL_ALPHA and is meant to be moved in one line after he looks.
	var m = await _built_menu([{"id": "a", "label": "Row"}])
	assert_lt(m.PANEL_ALPHA, 1.0, "the fill is translucent at all")
	assert_gt(m.PANEL_ALPHA, 0.25, "but not so faint the menu stops reading as a panel")
	var panel = m.get_child(0)
	var fill: ColorRect = null
	var opaque_borders := 0
	for c in panel.get_children():
		if c is ColorRect:
			if fill == null:
				fill = c
			elif c.color.a >= 0.99:
				opaque_borders += 1
	assert_not_null(fill, "CONTROL: found the panel fill")
	assert_lt(fill.color.a, 1.0, "the fill is actually drawn translucent")
	assert_gt(opaque_borders, 0, "the BORDER stays opaque — it is what keeps the menu legible")
