extends GutTest

## Ability icons, round 2 (struktured, via cowir-main 2026-09-28: the item icons "for abilities and spells
## as well"). Round 1 covered the battle menu, the Abilities screen and the Job screen; these are the
## surfaces that still listed abilities as bare text: the autobattle grid's action cells and ring picker,
## the autogrind editor's and console's "casts" cells, and the Party Status abilities column.
##
## Derived, not hand-listed: a saved or shared rule can name ANY ability, so the cell arms walk every id in
## abilities.json; the picker and Party Status arms walk what each starter job actually offers.
##
## The same cells also printed the raw id: `ability_id.capitalize()` showed "Fire" for the spell every
## menu calls "Ignis" — 28 renamed abilities. The name arms derive that set and pin the display name.

const AutobattleEditorScript := preload("res://src/ui/autobattle/AutobattleGridEditor.gd")
const AutogrindEditorScript := preload("res://src/ui/autogrind/AutogrindGridEditor.gd")
const AutogrindUIScript := preload("res://src/ui/autogrind/AutogrindUI.gd")
const PartyStatusScript := preload("res://src/ui/PartyStatusScreen.gd")
const RadialPickerScript := preload("res://src/ui/RadialPicker.gd")
const STARTERS := ["fighter", "cleric", "mage", "rogue", "bard"]
const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")

var _ag_state: Dictionary = {}


## The grind editor and console save on some paths; these arms only build cells, but the flag is the rule.
func before_each() -> void:
	_ag_state = AutogrindState.snapshot_and_isolate()
	AutogrindSystem._test_disable_persistence = true


func after_each() -> void:
	AutogrindState.restore(_ag_state)


func _ability_ids() -> Array:
	var f := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	var root: Dictionary = parsed.get("abilities", parsed) if parsed is Dictionary else {}
	var out: Array = []
	for id in root:
		if root[id] is Dictionary:
			out.append(str(id))
	out.sort()
	return out


## Abilities whose display name is not what `id.capitalize()` prints — where a raw id reads wrong.
func _renamed() -> Array:
	var out: Array = []
	for id in _ability_ids():
		var name := str(JobSystem.get_ability(id).get("name", ""))
		if name != "" and name != id.capitalize():
			out.append(id)
	return out


func _pc(job_id: String) -> Combatant:
	var pc := Combatant.new()
	pc.combatant_name = job_id.capitalize()
	pc.is_alive = true
	pc.max_hp = 40
	pc.current_hp = 40
	pc.max_mp = 99
	pc.current_mp = 99
	pc.job = JobSystem.get_job(job_id)
	add_child_autofree(pc)
	return pc


func _icon_in(cell: Node) -> TextureRect:
	for c in cell.find_children("AbilityIcon*", "TextureRect", true, false):
		return c
	return null


func _label_text(cell: Node) -> String:
	var parts: Array = []
	for c in cell.get_children():
		if c is Label:
			parts.append((c as Label).text)
	return " ".join(parts)


func _cell_problems(make_cell: Callable, ids: Array) -> Array:
	var bad: Array = []
	for id in ids:
		var cell: Control = make_cell.call(id)
		add_child_autofree(cell)
		var icon := _icon_in(cell)
		if icon == null:
			bad.append("%s: no icon" % id)
		elif icon.texture != AbilityIcons.tinted(id):
			bad.append("%s: wrong icon" % id)
		elif int(icon.size.y) > int(cell.custom_minimum_size.y):
			bad.append("%s: the icon is taller than its cell" % id)
	return bad


func test_every_autobattle_action_cell_draws_its_ability_icon() -> void:
	var ge = AutobattleEditorScript.new()
	add_child_autofree(ge)
	var ids := _ability_ids()
	assert_gt(ids.size(), 250, "CONTROL: abilities.json was read")
	var bad := _cell_problems(func(id): return ge._create_action_cell(0, 0, {"type": "ability", "id": id, "target": "lowest_hp_enemy"}, 1), ids)
	assert_eq(bad, [], "autobattle action cells: %s" % str(bad.slice(0, 8)))
	var collapsed: Control = ge._create_collapsed_action_cell(0, {"type": "ability", "id": "fire", "target": "lowest_hp_enemy"}, 3)
	add_child_autofree(collapsed)
	assert_not_null(_icon_in(collapsed), "the collapsed 'Ignis ×3' cell draws the icon too")


func test_every_autogrind_casts_cell_draws_its_ability_icon() -> void:
	var ed = AutogrindEditorScript.new()
	add_child_autofree(ed)
	var ui = AutogrindUIScript.new()
	add_child_autofree(ui)
	var ids := _ability_ids()
	var bad := _cell_problems(func(id): return ed._create_action_cell(0, 0, {"type": "member_ability", "member": "cleric", "ability": id}), ids)
	assert_eq(bad, [], "autogrind editor cells: %s" % str(bad.slice(0, 8)))
	bad = _cell_problems(func(id): return ui._create_action_cell(0, 0, {"type": "member_ability", "member": "cleric", "ability": id}), ids)
	assert_eq(bad, [], "autogrind console cells: %s" % str(bad.slice(0, 8)))


func test_a_cell_names_the_ability_the_way_the_menus_do() -> void:
	var renamed := _renamed()
	assert_gt(renamed.size(), 10, "CONTROL: the Latin renames exist (fire -> Ignis ...)")
	var ge = AutobattleEditorScript.new()
	add_child_autofree(ge)
	var ed = AutogrindEditorScript.new()
	add_child_autofree(ed)
	var ui = AutogrindUIScript.new()
	add_child_autofree(ui)
	var wrong: Array = []
	for id in renamed:
		var name := str(JobSystem.get_ability(id).get("name", ""))
		var texts := {
			"autobattle": ge._format_action({"type": "ability", "id": id, "target": "lowest_hp_enemy"}),
			"autogrind editor": ed._format_action({"type": "member_ability", "member": "cleric", "ability": id}),
			"autogrind console": ui._format_action({"type": "member_ability", "member": "cleric", "ability": id}),
		}
		# The console's options ring says "Cycle Ability: <this>" for the cell under the cursor.
		ui.rules = [{"conditions": [{"type": "always"}], "actions": [{"type": "member_ability", "member": "cleric", "ability": id}], "enabled": true}]
		ui.cursor_row = 0
		ui.cursor_col = 1
		texts["console cycle label"] = ui._cursor_ability_label()
		for where in texts:
			if not str(texts[where]).contains(name):
				wrong.append("%s shows '%s' for %s" % [where, str(texts[where]).replace("\n", " "), name])
	assert_eq(wrong, [], "a cell printed the raw id instead of the name: %s" % str(wrong.slice(0, 6)))


func test_the_ring_picker_draws_each_offered_ability_and_item_icon() -> void:
	var ge = AutobattleEditorScript.new()
	add_child_autofree(ge)
	var checked := 0
	var bad: Array = []
	for job in STARTERS:
		ge.combatant = _pc(job)
		var ring = RadialPickerScript.new()
		var opts: Array = []
		for ab in ge._get_character_abilities():
			opts.append({"id": ab["id"], "label": ab.get("name", ab["id"])})
		ring.setup({"title": "Ability", "kind": "ability_id", "options": opts, "selected": 0})
		for o in opts:
			checked += 1
			if ring.icon_for(o) != AbilityIcons.tinted(str(o["id"])):
				bad.append("%s/%s" % [job, o["id"]])
		ring.free()
	assert_gt(checked, 15, "CONTROL: every starter offered abilities to the ring")
	assert_eq(bad, [], "ring options without their ability icon: %s" % str(bad))
	var items = RadialPickerScript.new()
	items.setup({"title": "Item", "kind": "item_id", "options": [{"id": "potion", "label": "Potion"}], "selected": 0})
	assert_eq(items.icon_for({"id": "potion"}), ItemIcons.tinted("potion"), "item rings use the item icon")
	var other = RadialPickerScript.new()
	other.setup({"title": "Target", "kind": "target_type", "options": [{"id": "lowest_hp_enemy", "label": "Low HP"}], "selected": 0})
	assert_null(other.icon_for({"id": "lowest_hp_enemy"}), "a target ring has no icon to draw")
	items.free()
	other.free()


func test_party_status_draws_an_icon_on_every_ability_row() -> void:
	var screen = PartyStatusScript.new()
	add_child_autofree(screen)
	await get_tree().process_frame
	var checked := 0
	for job in STARTERS:
		var panel := Control.new()
		add_child_autofree(panel)
		screen._detail_panel = panel
		var pc := _pc(job)
		screen._build_abilities_column(pc, 0.0, 0.0, 300.0, 800.0)
		var rows: Array = []
		for c in panel.get_children():
			if c is Label and (c as Label).text.begins_with("• "):
				rows.append(c)
		var icons := panel.find_children("AbilityIcon*", "TextureRect", true, false)
		assert_gt(rows.size(), 0, "CONTROL: %s lists abilities on Party Status" % job)
		assert_eq(icons.size(), rows.size(), "%s: one icon per ability row" % job)
		for icon in icons:
			assert_lte(int(icon.size.y), 18, "the icon fits the existing 18px row pitch")
		checked += rows.size()
	assert_gt(checked, 10, "CONTROL: rows were judged")


## The icon sits at the cell's left edge and the label stays centred, so a long enough first line would
## run under it. Measured with the label's own font, at the width the label really takes (an autowrapped
## Label does not shrink to the size its builder asks for), for every ability and the longest member name.
func test_no_cell_text_starts_under_its_icon() -> void:
	var longest := ""
	for jid in JobSystem.jobs if "jobs" in JobSystem else []:
		if str(jid).capitalize().length() > longest.length():
			longest = str(jid).capitalize()
	if longest == "":
		longest = "Scriptweaver"
	var ge = AutobattleEditorScript.new()
	add_child_autofree(ge)
	var ed = AutogrindEditorScript.new()
	add_child_autofree(ed)
	var ui = AutogrindUIScript.new()
	add_child_autofree(ui)
	var makers := {
		"autobattle": func(id): return ge._create_action_cell(0, 0, {"type": "ability", "id": id, "target": "lowest_hp_enemy"}, 1),
		"autogrind editor": func(id): return ed._create_action_cell(0, 0, {"type": "member_ability", "member": longest.to_lower(), "ability": id}),
		"autogrind console": func(id): return ui._create_action_cell(0, 0, {"type": "member_ability", "member": longest.to_lower(), "ability": id}),
	}
	var overlaps: Array = []
	var judged := 0
	for where in makers:
		for id in _ability_ids():
			var cell: Control = makers[where].call(id)
			add_child_autofree(cell)
			var icon := _icon_in(cell)
			var label: Label = null
			for c in cell.get_children():
				if c is Label and (c as Label).text != "":
					label = c
					break
			if icon == null or label == null:
				continue
			var first := label.text.split("\n")[0]
			var font := label.get_theme_font("font")
			var fs := label.get_theme_font_size("font_size")
			var tw := font.get_string_size(first, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var start := label.position.x + (label.size.x - tw) / 2.0
			judged += 1
			if start < icon.position.x + icon.size.x:
				overlaps.append("%s %s '%s' starts at %.0f, icon ends %.0f" % [where, id, first, start, icon.position.x + icon.size.x])
	assert_gt(judged, 700, "CONTROL: every ability was measured on all three surfaces (%d)" % judged)
	assert_eq(overlaps, [], "%d cell(s) start their text under the icon: %s" % [overlaps.size(), str(overlaps.slice(0, 6))])
