extends GutTest

## Every ability and spell shows an icon — struktured 2026-09-26, after the item icons shipped:
## "I really like the icons added for the items, I think it would be cool to add it for abilities
## and spells as well."
##
## The icon KEY is derived from each ability's own data (element, then type, then a support
## ability's effect), so the 289 ids are never hand-listed and a new ability is covered the day it
## lands. The tint follows the element, from ItemIcons.ELEMENT_TINTS so the two sets agree.
##
## ⛔ The battle menu already drew icons for ITEMS, and ItemIcons maps any ability id to a generic
## "scroll". So "an ability row has an icon" is satisfied by the WRONG resolver. The battle arm pins
## that the drawn texture is AbilityIcons' and not ItemIcons' — the discriminating assert.

const MenuScript := preload("res://src/battle/BattleCommandMenu.gd")
const Win98MenuScript := preload("res://src/ui/Win98Menu.gd")
const AbilitiesMenuScript := preload("res://src/ui/AbilitiesMenu.gd")
const JobMenuScript := preload("res://src/ui/JobMenu.gd")


func _abilities() -> Dictionary:
	var f := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	var root: Dictionary = parsed.get("abilities", parsed) if parsed is Dictionary else {}
	var out := {}
	for id in root:
		if root[id] is Dictionary:
			out[str(id)] = root[id]
	return out


func _first(pred: Callable) -> String:
	var abil := _abilities()
	var ids := abil.keys()
	ids.sort()
	for id in ids:
		if pred.call(abil[id]):
			return str(id)
	return ""


func _has_ink(img: Image) -> bool:
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.1:
				return true
	return false


func _pc(job_id: String) -> Combatant:
	var pc := Combatant.new()
	pc.combatant_name = "Tester"
	pc.is_alive = true
	pc.max_hp = 40
	pc.current_hp = 40
	pc.max_mp = 99
	pc.current_mp = 99
	pc.job = JobSystem.get_job(job_id)
	add_child_autofree(pc)
	return pc


func test_every_ability_resolves_to_a_real_icon() -> void:
	var abil := _abilities()
	assert_gt(abil.size(), 250, "CONTROL: abilities.json was actually read")
	var bad: Array[String] = []
	for id in abil:
		var key := AbilityIcons.icon_key(id)
		if not FileAccess.file_exists(AbilityIcons.png_path(key)):
			bad.append("%s -> %s (no png)" % [id, key])
			continue
		var tex := AbilityIcons.tinted(id)
		if tex == null or tex.get_width() != 16 or not _has_ink(tex.get_image()):
			bad.append("%s blank or wrong size" % id)
	assert_eq(bad, [], "an ability resolved to a missing or blank icon: %s" % str(bad))


func test_no_ability_falls_through_to_the_default() -> void:
	# The default exists so the game never shows a blank; the guard makes a NEW type get a deliberate icon.
	var fell: Array[String] = []
	var abil := _abilities()
	for id in abil:
		if AbilityIcons.icon_key(id) == AbilityIcons.DEFAULT_KEY:
			fell.append("%s (type %s)" % [id, abil[id].get("type", "?")])
	assert_eq(fell, [], "these matched no icon rule — give their type/effect an icon: %s" % str(fell))


func test_the_derivation_reads_each_abilitys_own_data() -> void:
	# CONTROL against a constant resolver: each case is found BY ITS DATA, and the keys must differ.
	var cases := {
		"fire": _first(func(a): return a.get("element") == "fire"),
		"ice": _first(func(a): return a.get("element") == "ice"),
		"lightning": _first(func(a): return a.get("element") == "lightning"),
		"dark": _first(func(a): return a.get("element") == "dark"),
		"cure": _first(func(a): return a.get("type") == "healing" and not a.has("element")),
		"strike": _first(func(a): return a.get("type") == "physical" and not a.has("element")),
		"summon": _first(func(a): return a.get("type") == "summon"),
		"song": _first(func(a): return a.get("type") == "song"),
		"meta": _first(func(a): return a.get("type") == "meta"),
		"buff": _first(func(a): return a.get("type") == "support" and str(a.get("effect", "")).ends_with("_up")),
		"debuff": _first(func(a): return a.get("type") == "support" and str(a.get("effect", "")).ends_with("_down")),
	}
	for want in cases:
		var id: String = cases[want]
		assert_ne(id, "", "CONTROL: abilities.json has an ability of kind '%s'" % want)
		if id != "":
			assert_eq(AbilityIcons.icon_key(id), want, "%s must derive the '%s' icon" % [id, want])


func test_element_spells_take_the_element_tint() -> void:
	var abil := _abilities()
	var checked := 0
	for id in abil:
		var el := str(abil[id].get("element", ""))
		if el == "" or not ItemIcons.ELEMENT_TINTS.has(el):
			continue
		assert_eq(AbilityIcons.tint_color(id), ItemIcons.ELEMENT_TINTS[el], "%s must wear the %s tint" % [id, el])
		checked += 1
	assert_gt(checked, 40, "CONTROL: the elemental abilities were actually judged")


func test_the_icons_are_registered_for_the_artist() -> void:
	var f := FileAccess.open("res://data/sprite_manifest.json", FileAccess.READ)
	var m: Dictionary = JSON.parse_string(f.get_as_text())
	var sec = m.get("ability_icons", {})
	assert_true(sec is Dictionary and not sec.is_empty(), "ability_icons must be registered so the artist can replace them")
	if not (sec is Dictionary):
		return
	assert_eq(str(sec.get("tier", "")), "T1", "procedural placeholders are tier T1 until the artist replaces them")
	assert_string_contains(str(sec.get("source", "")), "tools/gen_ability_icons.py")
	var on_disk: Array = []
	for fn in DirAccess.get_files_at(AbilityIcons.DIR):
		if fn.ends_with(".png"):
			on_disk.append(fn.get_basename())
	on_disk.sort()
	var listed: Array = (sec.get("icons", []) as Array).duplicate()
	listed.sort()
	assert_gt(on_disk.size(), 10, "CONTROL: the icon set is on disk")
	assert_eq(listed, on_disk, "the manifest must list exactly the ability icons on disk")


func test_battle_ability_rows_draw_the_ability_icon_not_the_item_scroll() -> void:
	var scene: Node = load("res://src/battle/BattleScene.gd").new()
	add_child_autofree(scene)
	await get_tree().process_frame
	var pc := _pc("mage")
	var enemy := Combatant.new()
	enemy.combatant_name = "Slime"
	enemy.is_alive = true
	enemy.max_hp = 10
	enemy.current_hp = 10
	add_child_autofree(enemy)
	scene.party_members.assign([pc])
	scene.test_enemies.assign([enemy])
	var built: Array = MenuScript.new(scene).build_command_menu_items_with_targets(pc)
	var rows: Array = []
	for row in built:
		if str(row.get("id", "")) == "ability_menu":
			rows = row.get("submenu", [])
	assert_gt(rows.size(), 0, "CONTROL: the mage's battle ability submenu listed abilities")
	for row in rows:
		assert_eq(str(row.get("icon_kind", "")), "ability", "row %s must be marked as an ability icon" % row.get("label", ""))
		assert_ne(str(row.get("icon_id", "")), "", "row %s has no icon_id" % row.get("label", ""))
	var popup := Win98MenuScript.new()
	add_child_autofree(popup)
	popup.battle_mode = true
	popup.setup("Ability", rows, Vector2(80, 80), "mage")
	var container := popup._get_items_container()
	assert_eq(container.get_child_count(), popup.menu_items.size(), "CONTROL: every row was drawn")
	for i in popup.menu_items.size():
		var item: Dictionary = popup.menu_items[i]
		var icon := container.get_child(i).get_node_or_null("AbilityIcon") as TextureRect
		assert_not_null(icon, "battle ability row '%s' drew no ability icon" % item.get("label", ""))
		if icon:
			var id := str(item.get("icon_id", ""))
			assert_eq(icon.texture, AbilityIcons.tinted(id), "row '%s' must draw AbilityIcons' icon" % item.get("label", ""))
			assert_ne(icon.texture, ItemIcons.tinted(id), "row '%s' drew the ITEM resolver's scroll" % item.get("label", ""))
			assert_eq(int(icon.size.y), 32, "battle icons are the 16px art at 2x, like the items")


func test_the_abilities_screen_draws_an_icon_on_every_row() -> void:
	var menu = AbilitiesMenuScript.new()
	add_child_autofree(menu)
	menu.setup(_pc("mage"))
	await get_tree().process_frame
	assert_gt(menu._ability_labels.size(), 0, "CONTROL: the abilities screen rendered rows")
	for row in menu._ability_labels:
		var icon := row.get_node_or_null("AbilityIcon") as TextureRect
		assert_not_null(icon, "an Abilities-screen row has no icon")
		if icon:
			assert_ne(icon.texture, null)
			assert_eq(icon.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
			assert_eq(int(icon.size.y), 16, "the 24px row takes the art at 1x")


func test_the_job_screen_draws_an_icon_beside_each_job_ability() -> void:
	var pc := _pc("mage")
	var menu = JobMenuScript.new()
	add_child_autofree(menu)
	menu.setup(pc)
	await get_tree().process_frame
	var icons := menu.find_children("AbilityIcon*", "TextureRect", true, false)
	assert_eq(icons.size(), (pc.job.get("abilities", []) as Array).size(),
		"one icon per job ability on the Job screen")


func test_no_ability_name_runs_into_its_mp_cost_beside_the_icon() -> void:
	# The icon moved names 18px right; "Create Autobattle Script" then overran "20 MP" (seen in a render).
	var jobs_f := FileAccess.open("res://data/jobs.json", FileAccess.READ)
	var jparsed = JSON.parse_string(jobs_f.get_as_text())
	var jobs: Dictionary = jparsed.get("jobs", jparsed)
	var menu = AbilitiesMenuScript.new()
	add_child_autofree(menu)
	var checked := 0
	var overruns: Array[String] = []
	for jid in jobs:
		if not (jobs[jid] is Dictionary):
			continue
		for aid in jobs[jid].get("abilities", []):
			var data: Dictionary = JobSystem.get_ability(str(aid))
			if int(data.get("mp_cost", 0)) <= 0:
				continue
			var row: Control = menu._create_ability_row({"id": str(aid), "data": data}, -1)
			menu.add_child(row)
			var name_label: Label = null
			var mp_label: Label = null
			for c in row.get_children():
				if c is Label and c.text == data.get("name", ""):
					name_label = c
				elif c is Label and c.text.ends_with(" MP"):
					mp_label = c
			if name_label and mp_label:
				var name_end := name_label.position.x + name_label.get_minimum_size().x
				if name_end > mp_label.position.x - 4:
					overruns.append("%s (ends %d, MP at %d)" % [name_label.text, int(name_end), int(mp_label.position.x)])
				checked += 1
			row.queue_free()
	assert_gt(checked, 40, "CONTROL: rows with an MP cost were actually measured")
	assert_eq(overruns, [], "an ability name runs into its MP cost: %s" % str(overruns))

