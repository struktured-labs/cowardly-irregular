extends GutTest

## struktured's 200% frame (cowir-main 26747): the ability list sat in the 318 px between the enemy panel and the command menu,
## and its names read "Power ...", "Provok...". Ruling 26791: WIDTH BEFORE WRAP. A battle list is as wide as its longest real
## label needs on one line, resting over the dimmed root where the gap is smaller; rows wrap only when even that cannot hold a
## name; and the description box stays above the floor. Judged on the rows BattleCommandMenu really builds.

const MenuScript = preload("res://src/battle/BattleCommandMenu.gd")
const SceneScript = preload("res://src/battle/BattleScene.gd")
const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")
const STARTERS := ["fighter", "cleric", "mage", "rogue", "bard"]
const OLD_GAP := 318

var _battle_state: RefCounted = null
var _saved_scale = null


func before_each() -> void:
	_battle_state = BattleStateHelper.new()
	_battle_state.snapshot()
	_saved_scale = GameState.text_size_scale


func after_each() -> void:
	GameState.text_size_scale = _saved_scale
	if _battle_state != null:
		_battle_state.restore()


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step (%s)" % [p])
	return p


## Every ability id a starter job ever learns.
func _kit_ids(job: String) -> Array:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	var jobs: Dictionary = (d as Dictionary).get("jobs", d) if d is Dictionary else {}
	var row: Dictionary = jobs.get(job, {})
	var ids: Array = []
	ids.append_array(row.get("abilities", []))
	for lv in (row.get("abilities_at_level", {}) as Dictionary).values():
		ids.append_array(lv)
	return ids


func _pc(job_id: String, abilities: Array) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = job_id.capitalize() if job_id != "" else "Goblin"
	c.job = {"id": job_id, "abilities": abilities}
	c.max_hp = 500
	c.current_hp = 500
	c.max_mp = 999
	c.current_mp = 999
	c.is_alive = true
	c.current_ap = 2
	return c


## The Ability submenu's rows exactly as BattleCommandMenu builds them for `job` with its whole kit: labels, costs, icons, pickers.
func _real_rows(job: String) -> Array:
	var actor := _pc(job, _kit_ids(job))
	var party: Array[Combatant] = [actor]
	BattleManager.player_party.assign(party)
	BattleManager.selection_order.assign(party)
	BattleManager.selection_index = 0
	BattleManager.current_combatant = actor
	var foe := _pc("", [])
	BattleManager.enemy_party.assign([foe])
	var scene = autofree(SceneScript.new())
	scene.party_members.assign(party)
	scene.test_enemies.assign(BattleManager.enemy_party)
	for n in 2:
		var sprite := AnimatedSprite2D.new()
		add_child_autofree(sprite)
		if n == 0:
			scene.party_sprite_nodes.append(sprite)
		else:
			scene.enemy_sprite_nodes.append(sprite)
	add_child_autofree(scene)
	for item in MenuScript.new(scene).build_command_menu_items_with_targets(actor):
		if str((item as Dictionary).get("label", "")).begins_with("Ability") and (item as Dictionary).has("submenu"):
			return (item as Dictionary).get("submenu", [])
	return []


func _list(rows: Array, cap: int, floor_y: float = 0.0) -> Win98Menu:
	var m := Win98Menu.new()
	m._width_cap = cap
	m._names_whole = true
	m.screen_floor_y = floor_y
	add_child_autofree(m)
	m.setup("Ability", rows, Vector2(300, 100), "fighter")
	await get_tree().process_frame
	await get_tree().process_frame
	return m


func _name_labels(m: Win98Menu) -> Array:
	var out: Array = []
	for n in m.find_children("Label", "Label", true, false):
		if (n as Node).get_parent() != null and (n as Node).get_parent().name == "LabelClip":
			out.append(n)
	return out


func _one_line_px(l: Label) -> float:
	return l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x


## What is wrong with one built name label, or "" when the whole label shows.
func _cut(m: Win98Menu, l: Label) -> String:
	if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
		return "" if _one_line_px(l) <= l.size.x + 0.5 else "'%s' needs %d px on one line, has %d" % [l.text, int(_one_line_px(l)), int(l.size.x)]
	if l.get_line_count() > m._row_lines:
		return "'%s' wraps to %d lines, the row holds %d" % [l.text, l.get_line_count(), m._row_lines]
	var f: Font = l.get_theme_font("font")
	var px: int = l.get_theme_font_size("font_size")
	for w in l.text.split(" ", false):
		var ww: float = f.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		if ww > l.size.x + 0.5:
			return "'%s': the word '%s' is %d px, the name column is %d" % [l.text, w, int(ww), int(l.size.x)]
	return ""


func _half_screen() -> int:
	return int(get_viewport().get_visible_rect().size.x / 2.0)


func test_the_floor_names_every_member_this_file_drives() -> void:
	var m := Win98Menu.new()
	autofree(m)
	for p in ["_width_cap", "_row_lines", "_description_room", "screen_floor_y", "expand_left", "submenu", "_tooltip_label", "_names_whole", "_fill_alpha", "_panel_fill", "_row_line_counts", "_window_px", "_scroll_offset", "_max_visible_rows", "_row_tops", "selected_index"]:
		assert_true(p in m, "FLOOR: Win98Menu.%s" % p)
	for f in ["setup", "_row_height", "_line_row_height", "_submenu_width_cap", "_submenu_right_wall", "_submenu_left_bound", "_open_submenu", "_update_tooltip", "_tooltip_backing", "_row_top", "_row_height_at", "_nav_step"]:
		assert_true(m.has_method(f), "FLOOR: Win98Menu.%s()" % f)
	for job in STARTERS:
		assert_gt(_real_rows(job).size(), 2, "FLOOR: BattleCommandMenu builds %s an Ability list to judge" % job)


## Ruling 4, his size: at 100% the Fighter's real list keeps one-line rows, and its longest real label now reads whole.
func test_at_his_size_the_fighters_list_keeps_its_rows_and_reads_whole() -> void:
	GameState.text_size_scale = 1.0
	var rows: Array = _real_rows("fighter")
	var squeezed: Win98Menu = await _list(rows, OLD_GAP)
	var cut_before := 0
	for l in _name_labels(squeezed):
		if _one_line_px(l as Label) > (l as Label).size.x + 0.5:
			cut_before += 1
	var m: Win98Menu = await _list(rows, _half_screen())
	assert_eq(m._row_lines, 1, "no row takes a second line at 100%")
	assert_eq(m._row_height(), m._line_row_height(), "the row is its shipped one-line height (%d)" % m._row_height())
	var cut: Array = []
	for l in _name_labels(m):
		var why: String = _cut(m, l as Label)
		if why != "":
			cut.append(why)
	assert_eq(cut, [], "every real label reads whole on one line:\n%s" % "\n".join(PackedStringArray(cut)))
	gut.p("at 100%% the Fighter's list is %d px wide (the old gap gave %d); labels that did not fit the old gap: %d" % [int(m.size.x), OLD_GAP, cut_before])


## Rulings 1 and 5: every starter's real list at every Text Size, given the width a battle allows. No label is cut anywhere.
func test_no_real_ability_label_is_cut_at_any_text_size() -> void:
	var cut: Array = []
	var judged := 0
	var would_cut := 0
	for s in _presets():
		GameState.text_size_scale = float(s)
		for job in STARTERS:
			var rows: Array = _real_rows(job)
			var old: Win98Menu = await _list(rows, OLD_GAP)
			for l in _name_labels(old):
				if _one_line_px(l as Label) > (l as Label).size.x + 0.5:
					would_cut += 1
			old.queue_free()
			var m: Win98Menu = await _list(rows, _half_screen())
			for l in _name_labels(m):
				judged += 1
				var why: String = _cut(m, l as Label)
				if why != "":
					cut.append("%s%% %s (list %d px, %d line rows): %s" % [int(roundf(float(s) * 100.0)), job, int(m.size.x), m._row_lines, why])
			m.queue_free()
			await get_tree().process_frame
	assert_gt(judged, 20 * _presets().size(), "CONTROL: every kit was judged at every preset (%d labels)" % judged)
	assert_gt(would_cut, 0, "CONTROL: held to the old 318 px gap some real label did not fit one line (%d), so a clean result is the rule working" % would_cut)
	assert_eq(cut, [], "a real ability label is cut:\n%s" % "\n".join(PackedStringArray(cut)))


## Ruling 2: wrap is the last resort. A list held narrower than its longest label still shows it, on two lines.
func test_a_list_with_no_room_wraps_as_the_last_resort() -> void:
	GameState.text_size_scale = 2.0
	var rows: Array = [{"label": "Power Strike", "id": "a", "cost": 8}, {"label": "Slash", "id": "b", "cost": 0}]
	var m: Win98Menu = await _list(rows, 330)
	var first: Label = _name_labels(m)[0]
	assert_gt(_one_line_px(first), first.size.x, "CONTROL: 'Power Strike' is wider than the column a 330 px list leaves (%d vs %d)" % [int(_one_line_px(first)), int(first.size.x)])
	assert_eq(m._row_lines, 2, "the rows take a second line")
	assert_gt(m._row_height(), m._line_row_height(), "and are taller for it")
	assert_eq(_cut(m, first), "", "and the name reads whole")
	var wide: Win98Menu = await _list(rows, _half_screen())
	assert_eq(wide._row_lines, 1, "given the width, the same list stays on one line: width comes before wrap")


## Ruling 1: a list wider than the gap before the root rests over the root, never over the enemy panel or the party panel.
func test_a_wide_list_rests_between_the_two_panels() -> void:
	GameState.text_size_scale = 2.0
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var enemies := Control.new()
	enemies.name = "EnemyStatusPanel"
	enemies.position = Vector2(8, 60)
	enemies.size = Vector2(200, 220)
	add_child_autofree(enemies)
	var party := Control.new()
	party.name = "PartyStatusPanel"
	party.position = Vector2(vp.x - 300.0, 40)
	party.size = Vector2(292, 600)
	add_child_autofree(party)
	await get_tree().process_frame
	var item := {"label": "Ability", "id": "ability_menu", "submenu": _real_rows("fighter")}
	var root := Win98Menu.new()
	add_child_autofree(root)
	root.setup("Fighter", [item, {"label": "Defer", "id": "defer"}], Vector2(enemies.get_global_rect().end.x + 260.0, 300), "fighter")
	await get_tree().process_frame
	await get_tree().process_frame
	root._open_submenu(0, item)
	await get_tree().process_frame
	var sub: Win98Menu = root.submenu
	assert_not_null(sub, "CONTROL: the Ability list opened")
	if sub == null:
		return
	## Wait for the slide-in to settle on its rest position (bounded), not for a clock.
	var last := Vector2.INF
	var still := 0
	for i in 240:
		await get_tree().process_frame
		still = still + 1 if sub.position == last else 0
		last = sub.position
		if still >= 6:
			break
	assert_gte(still, 6, "CONTROL: the list came to rest")
	var r: Rect2 = sub.get_global_rect()
	var gap: float = root.get_global_rect().position.x - 6.0 - (enemies.get_global_rect().end.x + 8.0)
	assert_gt(r.size.x, gap, "CONTROL: the list (%d px) is wider than the gap before the root (%d px)" % [int(r.size.x), int(gap)])
	assert_gte(r.position.x, enemies.get_global_rect().end.x + 8.0 - 0.5, "it does not cover the enemy panel (starts %d)" % int(r.position.x))
	assert_lte(r.end.x, party.get_global_rect().position.x - 8.0 + 0.5, "nor the party panel (ends %d, panel at %d)" % [int(r.end.x), int(party.get_global_rect().position.x)])
	assert_true(r.intersects(root.get_global_rect()), "so it rests over the root's left edge")
	var cut: Array = []
	for l in _name_labels(sub):
		var why: String = _cut(sub, l as Label)
		if why != "":
			cut.append(why)
	assert_eq(cut, [], "and no label in it is cut:\n%s" % "\n".join(PackedStringArray(cut)))
	## cowir-main 26913: no root text through the list. The fill and the description box are opaque where the list rests on the root.
	assert_eq(sub._panel_fill.color.a, sub.style.bg.a, "the list's fill is opaque over the root (%.2f of %.2f)" % [sub._panel_fill.color.a, sub.style.bg.a])
	assert_eq(sub._tooltip_backing().bg_color.a, 1.0, "and so is its description box")
	assert_lt(root._tooltip_backing().bg_color.a, 1.0, "CONTROL: a list over the open battlefield keeps its see-through backing")
	root.force_close()


## Ruling 4 (cowir-main 26913, the red neighbour): only the Ability list grows over the root. A target list with a boss name keeps the shipped gap, its one-line rows and its ellipsis.
func test_a_list_that_is_not_the_ability_list_stays_where_it_shipped() -> void:
	GameState.text_size_scale = 1.0
	var enemies := Control.new()
	enemies.name = "EnemyStatusPanel"
	enemies.position = Vector2(5, 60)
	enemies.size = Vector2(175, 220)
	add_child_autofree(enemies)
	await get_tree().process_frame
	var targets: Array = [{"id": "t0", "label": "Slime (48 HP) ~12 dmg [KILL]"}, {"id": "t1", "label": "Glacius, the Frozen Sovereign (248 HP) ~86 dmg [KILL]"}]
	var opened: Dictionary = {}
	for id in ["attack_menu", "ability_menu"]:
		var item := {"label": "Attack" if id == "attack_menu" else "Ability", "id": id, "submenu": targets}
		var root := Win98Menu.new()
		add_child_autofree(root)
		root.setup("Fighter", [item], Vector2(537.6, 180), "fighter")
		await get_tree().process_frame
		await get_tree().process_frame
		root._open_submenu(0, item)
		for i in 30:
			await get_tree().process_frame
		var sub: Win98Menu = root.submenu
		assert_not_null(sub, "CONTROL: the %s list opened" % id)
		if sub == null:
			return
		opened[id] = {"end": sub.get_global_rect().end.x, "root": root.get_global_rect().position.x, "lines": sub._row_lines, "whole": sub._names_whole}
		root.force_close()
	assert_false(opened["attack_menu"]["whole"], "a target list is not asked to keep names whole")
	assert_lte(opened["attack_menu"]["end"], opened["attack_menu"]["root"] - 4.0, "it ends left of the command menu, as shipped (%d vs %d)" % [int(opened["attack_menu"]["end"]), int(opened["attack_menu"]["root"])])
	assert_eq(opened["attack_menu"]["lines"], 1, "and keeps one-line rows")
	assert_true(opened["ability_menu"]["whole"], "CONTROL: the same rows opened as the Ability list are")
	assert_gt(opened["ability_menu"]["end"], opened["ability_menu"]["root"], "CONTROL: and that list rests over the root, so the gap is what held the target list")


## Ruling 3: under a floor the list leaves room for its description box, giving up rows before the box leaves the screen.
func test_the_description_box_stays_above_the_floor() -> void:
	GameState.text_size_scale = 2.0
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var floor_y: float = vp.y - 50.0
	var rows: Array = []
	var bare: Array = []
	for i in 30:
		rows.append({"label": "Ability %d" % i, "id": "r%d" % i, "tooltip": "A powerful physical attack dealing 1.5x damage to one enemy, with a chance to stagger it for a turn."})
		bare.append({"label": "Ability %d" % i, "id": "r%d" % i})
	var plain: Win98Menu = await _list(bare, 400, floor_y)
	var m: Win98Menu = await _list(rows, 400, floor_y)
	assert_gt(m._description_room, 0, "a list with descriptions keeps room for one (%d px)" % m._description_room)
	assert_eq(plain._description_room, 0, "CONTROL: a list with none keeps no room")
	assert_gt(plain._max_visible_rows, 0, "CONTROL: 30 rows at 200% scroll either way")
	assert_lt(m._max_visible_rows, plain._max_visible_rows, "and it gives up rows for the box (%d vs %d)" % [m._max_visible_rows, plain._max_visible_rows])
	assert_lte(m.position.y + m.size.y + float(m._description_room), floor_y + 0.5, "list + description end above the floor (%d + %d vs %d)" % [int(m.position.y + m.size.y), m._description_room, int(floor_y)])
	m._update_tooltip()
	for i in 4:
		await get_tree().process_frame
	var tip: Label = m._tooltip_label
	assert_not_null(tip, "CONTROL: the description box was built")
	if tip == null:
		return
	assert_true(tip.visible, "CONTROL: and shows")
	var tr: Rect2 = tip.get_global_rect()
	assert_lte(tr.end.y, floor_y + 0.5, "the description box ends at %d, above the floor %d" % [int(tr.end.y), int(floor_y)])
	assert_gte(tr.position.y, m.position.y + m.size.y, "and still sits under its list")


func _row_nodes(m: Win98Menu) -> Array:
	var out: Array = []
	for n in m.find_children("Item*", "Control", true, false):
		if (n as Node).get_parent() != null and (n as Node).get_parent().name == "Items":
			out.append(n)
	return out


## cowir-main 27037, the Mage's 200% frame: four long labels wrapped EVERY row (96 px, 4 of 11 shown). Only a row whose own name needs it takes a second line.
func test_only_a_long_name_takes_a_second_line() -> void:
	GameState.text_size_scale = 2.0
	var m: Win98Menu = await _list(_real_rows("mage"), _half_screen(), 670.0)
	var one := m._line_row_height()
	var rows: Array = _row_nodes(m)
	assert_eq(rows.size(), m.menu_items.size(), "FLOOR: every row was built (%d)" % rows.size())
	var tall := 0
	var short := 0
	for i in rows.size():
		var l: Label = _name_labels(m)[i]
		var h := int((rows[i] as Control).custom_minimum_size.y)
		if _one_line_px(l) <= l.size.x + 0.5:
			short += 1
			assert_eq(h, one, "'%s' fits one line, so its row stays %d px (got %d)" % [l.text, one, h])
		else:
			tall += 1
			assert_gt(h, one, "'%s' wraps, so its row is taller" % l.text)
		assert_eq(_cut(m, l), "", "and '%s' reads whole" % l.text)
	assert_gt(tall, 0, "CONTROL: some Mage label needs two lines at 200%")
	assert_gt(short, tall, "CONTROL: most Mage labels fit one line")
	var shown: int = m._max_visible_rows if m._max_visible_rows > 0 else rows.size()
	assert_gt(shown, m._window_px / m._row_height(), "the window shows more rows than it would if every row were tall (%d in %d px)" % [shown, m._window_px])


## Scrolling a mixed list keeps whole rows: the row under the cursor is inside the window, top and bottom.
func test_a_mixed_list_scrolls_by_whole_rows() -> void:
	GameState.text_size_scale = 2.0
	var m: Win98Menu = await _list(_real_rows("mage"), _half_screen(), 670.0)
	assert_gt(m._max_visible_rows, 0, "CONTROL: the Mage's list scrolls at 200%")
	var container: VBoxContainer = m._get_items_container()
	var bad: Array = []
	for i in m.menu_items.size():
		m.selected_index = i
		m._scroll_selection_into_view(container)
		var top: int = m._row_top(i) - m._row_top(m._scroll_offset)
		var bottom: int = top + m._row_height_at(i)
		if top < 0 or bottom > m._window_px:
			bad.append("row %d spans %d..%d of a %d px window" % [i, top, bottom, m._window_px])
		if int(container.position.y) != -m._row_top(m._scroll_offset):
			bad.append("row %d: items sit at %d, the offset's top is %d" % [i, int(container.position.y), -m._row_top(m._scroll_offset)])
	assert_eq(bad, [], "\n".join(PackedStringArray(bad)))
	assert_gt(m._scroll_offset, 0, "CONTROL: reaching the last row scrolled")


## The 200% Mage frame (d3f25820e): the list rested under "Round 1 - SELECT" at y 134 but budgeted rows from the top margin, so its description covered the 8th row.
func test_rows_are_budgeted_from_under_the_turn_banner() -> void:
	GameState.text_size_scale = 2.0
	var floor_y := 670.0
	var free: Win98Menu = await _list(_real_rows("mage"), _half_screen(), floor_y)
	var banner := Control.new()
	banner.name = "TurnInfoPanel"
	banner.position = Vector2(260, 10)
	banner.size = Vector2(760, 120)
	add_child_autofree(banner)
	var m: Win98Menu = await _list(_real_rows("mage"), _half_screen(), floor_y)
	var room := floor_y - float(m._description_room) - (banner.get_global_rect().end.y + 4.0)
	assert_gt(free.size.y, room, "CONTROL: budgeted from the top margin, the list (%d px) is taller than the room under the banner (%d)" % [int(free.size.y), int(room)])
	assert_lte(m.size.y, room + 0.5, "under a banner the list (%d px) fits between it and its description box (%d)" % [int(m.size.y), int(room)])
	assert_gt(m._max_visible_rows, 0, "and it scrolls for it")


## probe2 (27170): row tops re-measured the font per row, so one nav step on a 40-row list cost ~15 ms. Built once now.
func _plain_list(n: int) -> Win98Menu:
	var items: Array = []
	for i in n:
		items.append({"id": "r%d" % i, "label": "Spell %03d" % i})
	var m: Win98Menu = Win98Menu.new()
	add_child_autofree(m)
	m.setup("Spells", items, Vector2(40, 40), "mage")
	await get_tree().create_timer(0.25, true, false, true).timeout
	return m


func test_row_positions_are_read_from_the_build_not_remeasured() -> void:
	var m := await _plain_list(12)
	assert_eq(m._row_tops.size(), 13, "CONTROL: the build recorded a top for every row and the end")
	var built: int = m._row_top(5)
	assert_eq(built, m._row_tops[5], "CONTROL: a row's top is the recorded one")
	m._row_tops[5] += 1000
	assert_eq(m._row_top(5), built + 1000, "a row's top is read from the build, not re-measured row by row")
	assert_eq(m._row_height_at(4), m._row_tops[5] - m._row_tops[4], "a row's height comes from the same record")


func _nav_cost_usec(m: Win98Menu, steps: int) -> int:
	var best := 1 << 40
	for _rep in 3:
		m.selected_index = 0
		m._scroll_offset = 0
		var t0 := Time.get_ticks_usec()
		for _i in steps:
			m._nav_step(1)
		best = mini(best, Time.get_ticks_usec() - t0)
	return maxi(1, best)


## A ratio, never a ms bound (cowir-main 27171): 4x the rows may cost ~4x per step (the selection repaint is linear), not ~16x.
func test_a_step_on_a_long_list_does_not_grow_with_the_square_of_its_rows() -> void:
	var short := await _plain_list(40)
	var big := await _plain_list(160)
	assert_gt(short._max_visible_rows, 0, "CONTROL: the 40-row list scrolls, so the scroll path is what is timed")
	assert_gt(big._max_visible_rows, 0, "CONTROL: so does the 160-row one")
	var a := _nav_cost_usec(short, 10)
	var b := _nav_cost_usec(big, 10)
	assert_lt(float(b) / float(a), 8.0, "10 steps on 160 rows cost %d us vs %d us on 40: a nav step grows faster than its row count" % [b, a])
