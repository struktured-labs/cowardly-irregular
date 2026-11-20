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
	for p in ["_width_cap", "_row_lines", "_description_room", "screen_floor_y", "expand_left", "submenu", "_tooltip_label"]:
		assert_true(p in m, "FLOOR: Win98Menu.%s" % p)
	for f in ["setup", "_row_height", "_line_row_height", "_submenu_width_cap", "_submenu_right_wall", "_submenu_left_bound", "_open_submenu", "_update_tooltip"]:
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
	root.force_close()


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
