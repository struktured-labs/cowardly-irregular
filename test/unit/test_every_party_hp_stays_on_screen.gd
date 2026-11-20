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
	var party := _party(n)
	## As a battle does: the box builder reads BattleManager's party first, and a stale one built 4 members with 5's bars.
	BattleManager.player_party.assign(party)
	scene.set_party(party)
	add_child_autofree(scene)
	for f in 16:
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


## cowir-main 26507: a panel that already fits looks as shipped. 4 members at 100% and 125% drop nothing; 5 at 100% drop only StatMods.
func test_a_panel_that_fits_looks_as_shipped() -> void:
	for row in [[1.0, 4, 0], [1.25, 4, 0], [1.0, 5, 1]]:
		var b: Array = await _battle(row[0], row[1])
		assert_eq(b[0].get("_ui_manager").party_compact_tier, row[2], "@%s x%d stops at tier %d" % row)
		var box: Node = b[0].get("_ui_manager").get("_party_status_boxes")[0]
		assert_not_null(box.get_node_or_null("AP"), "@%s x%d: AP sits on its own row, at its shipped path" % [row[0], row[1]])
		b[0].queue_free()
		await get_tree().process_frame


## The other half of 26507: no row of any member sits under the hint bar, at any Text Size.
func test_the_panel_ends_above_its_floor_at_every_text_size() -> void:
	var bad: Array = []
	for s in _presets():
		for n in [4, 5]:
			var b: Array = await _battle(float(s), n)
			var end_y: float = (b[0].get_node("UI/PartyStatusPanel") as Control).get_global_rect().end.y
			if end_y > b[2] + 0.5:
				bad.append("@%s x%d panel ends %d vs floor %d at tier %d" % [s, n, int(end_y), int(b[2]), b[0].get("_ui_manager").party_compact_tier])
			b[0].queue_free()
			await get_tree().process_frame
	assert_eq(bad, [], "the panel ends above its floor:\n%s" % "\n".join(PackedStringArray(bad)))


## Where AP rides the name row: it is still found, shown and inside the panel, and neither it nor the name shrank its face.
func test_an_inlined_ap_is_whole_and_the_face_did_not_shrink() -> void:
	var inlined := 0
	for s in _presets():
		for n in [4, 5]:
			var b: Array = await _battle(float(s), n)
			var uim = b[0].get("_ui_manager")
			if uim.party_compact_tier >= 2:
				var panel := (b[0].get_node("UI/PartyStatusPanel") as Control).get_global_rect()
				for box in uim.get("_party_status_boxes"):
					inlined += 1
					var ap := UIM.party_ap_label(box) as RichTextLabel
					assert_not_null(ap, "@%s x%d: the AP label is found on the name row" % [s, n])
					if ap == null:
						continue
					assert_eq(str(ap.get_parent().name), "Header", "@%s x%d: AP rides the name row" % [s, n])
					assert_true(ap.is_visible_in_tree(), "@%s x%d: AP shows" % [s, n])
					var r: Rect2 = ap.get_global_rect()
					assert_true(r.position.x >= panel.position.x - 0.5 and r.end.x <= panel.end.x + 0.5, "@%s x%d: AP %d..%d inside the panel %d..%d" % [s, n, int(r.position.x), int(r.end.x), int(panel.position.x), int(panel.end.x)])
					assert_gte(float(ap.get_content_width()), 1.0, "@%s x%d: AP has text to show" % [s, n])
					assert_lte(float(ap.get_content_width()), r.size.x + 0.5, "@%s x%d: AP's text %d px fits its %d px label" % [s, n, ap.get_content_width(), int(r.size.x)])
					assert_eq(ap.get_theme_font_size("normal_font_size"), TextScale.scaled(15), "@%s x%d: AP's face did not shrink" % [s, n])
					var nm := box.get_node("Header/Name") as Label
					assert_eq(nm.get_theme_font_size("font_size"), TextScale.scaled(15), "@%s x%d: the name's face did not shrink" % [s, n])
					assert_false(nm.text.contains("("), "@%s x%d: the job is dropped from '%s' before any letter is cut" % [s, n, nm.text])
					var keep: String = nm.text.left(UIM.PARTY_NAME_MIN_CHARS)
					var need: float = nm.get_theme_font("font").get_string_size(keep, HORIZONTAL_ALIGNMENT_LEFT, -1, nm.get_theme_font_size("font_size")).x
					assert_gte(nm.size.x, need - 0.5, "@%s x%d: '%s' has room for its first %d letters (%d px of %d)" % [s, n, nm.text, UIM.PARTY_NAME_MIN_CHARS, int(nm.size.x), int(need)])
			b[0].queue_free()
			await get_tree().process_frame
	assert_gt(inlined, 0, "CONTROL: some Text Size inlined AP, so the arm judged something")
