extends GutTest

## struktured 2026-11-01: "a newly picked up item should draw attention to itself somehow in the menu after".
## An item or piece of gear the party picks up is NEW until the cursor rests on its row; the row shows a NEW tag
## and the overworld menu's Items / Equipment entry shows one while anything inside is NEW.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const HOST_SRC := "extends Node\nvar party: Array = []\nvar equipment_pool: Dictionary = {\"weapons\": [], \"armors\": [], \"accessories\": []}\n"

## The two pool writers that move gear the party ALREADY owns: never news.
const NOT_AN_ACQUISITION := {
	"equip_from_pool": "takes one copy OUT of the pool onto a member",
	"unequip_to_pool": "returns the member's own gear to the pool",
}

var _host: Node = null
var _saved_unseen: Array[String] = []


func before_each() -> void:
	_saved_unseen = GameState.unseen_items.duplicate()
	GameState.unseen_items.clear()


func after_each() -> void:
	GameState.unseen_items = _saved_unseen
	if _host != null and is_instance_valid(_host):
		_host.get_parent().remove_child(_host)
		_host.free()
	_host = null


## A stand-in /root/GameLoop with a party and a pool, the two things the marking reads.
func _make_host() -> bool:
	if get_tree().root.get_node_or_null("GameLoop") != null:
		return false
	var script := GDScript.new()
	script.source_code = HOST_SRC
	script.reload()
	_host = Node.new()
	_host.set_script(script)
	_host.name = "GameLoop"
	get_tree().root.add_child(_host)
	return true


func _member() -> Combatant:
	var m := Combatant.new()
	autofree(m)
	return m


func test_picking_up_an_item_makes_it_news() -> void:
	if not _make_host():
		pending("a real GameLoop already lives at /root")
		return
	var m := _member()
	_host.party.append(m)
	m.add_item("potion", 2)
	assert_true(GameState.is_unseen("potion"), "a potion picked up by a party member must be NEW")


func test_a_starting_kit_is_not_news() -> void:
	## Both new-game builders add the kit BEFORE party.append, which is exactly what keeps New Game empty.
	if not _make_host():
		pending("a real GameLoop already lives at /root")
		return
	var m := _member()
	m.add_item("potion", 5)
	assert_false(GameState.is_unseen("potion"), "an item added before the member joins the party is a kit, not news")
	_host.party.append(m)
	m.add_item("ether", 1)
	assert_true(GameState.is_unseen("ether"), "CONTROL: the same member, once in the party, does make news")


func test_a_combatant_in_no_party_is_never_news() -> void:
	var m := _member()
	m.add_item("potion", 1)
	assert_false(GameState.is_unseen("potion"), "a detached combatant (a test, a standalone battle) must not mark anything")


func test_seen_then_picked_up_again_is_news_again() -> void:
	GameState.note_acquired("potion")
	GameState.note_acquired("potion")
	assert_eq(GameState.unseen_items.count("potion"), 1, "more of an unseen item keeps ONE entry")
	GameState.mark_seen("potion")
	assert_false(GameState.is_unseen("potion"), "the cursor resting on it clears it")
	GameState.note_acquired("potion")
	assert_true(GameState.is_unseen("potion"), "picking up more of one already seen is news again")


func test_the_unseen_set_survives_save_and_load() -> void:
	var a = load("res://src/meta/GameState.gd").new()
	var b = load("res://src/meta/GameState.gd").new()
	a.note_acquired("potion")
	a.note_acquired("iron_sword")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(a.to_dict()))
	b.from_dict(saved)
	assert_true(b.is_unseen("potion") and b.is_unseen("iron_sword"), "both ids must come back from a JSON round trip: %s" % [b.unseen_items])
	assert_eq(typeof(b.unseen_items), TYPE_ARRAY, "CONTROL: the field is still an Array after the load")
	saved.erase("unseen_items")
	b.from_dict(saved)
	assert_eq(b.unseen_items.size(), 0, "a save from before the key loads with nothing NEW")
	a.free()
	b.free()


func test_new_game_forgets_the_unseen_set() -> void:
	## Driving reset_game_state in a unit test wipes the live party (GameState's own warning), so this pins the body.
	var code: String = GdSource.code_of("res://src/meta/GameState.gd")
	var at: int = code.find("func reset_game_state")
	assert_gt(at, -1, "CONTROL: reset_game_state must exist")
	var end: int = code.find("\nfunc ", at + 1)
	assert_true(code.substr(at, end - at).contains("unseen_items.clear()"), "New Game must start with nothing NEW")


func _items_menu(inventory: Dictionary) -> ItemsMenu:
	var menu := ItemsMenu.new()
	add_child_autofree(menu)
	menu.setup([], inventory)
	menu._build_ui()
	return menu


func _row_for(menu: ItemsMenu, item_id: String) -> Control:
	for i in menu._item_labels.size():
		if str(menu._item_list[menu._item_scroll + i].get("id", "")) == item_id:
			return menu._item_labels[i]
	return null


func test_the_items_list_tags_a_new_row_and_the_cursor_clears_it() -> void:
	GameState.note_acquired("potion")
	var menu := _items_menu({"potion": 3, "ether": 1, "antidote": 2})
	var potion_at := -1
	for i in menu._item_list.size():
		if str(menu._item_list[i]["id"]) == "potion":
			potion_at = i
	assert_gt(potion_at, -1, "CONTROL: the potion must be listed")
	var potion_row := _row_for(menu, "potion")
	assert_not_null(potion_row, "CONTROL: the potion's row must be on screen")
	assert_not_null(potion_row.get_node_or_null(NewItemTag.NODE_NAME), "the NEW potion's row must carry the NEW tag")
	assert_null(_row_for(menu, "ether").get_node_or_null(NewItemTag.NODE_NAME), "a row that is not new carries no tag")
	if potion_at != menu.selected_item_index:
		assert_true(GameState.is_unseen("potion"), "CONTROL: opening the list does not clear a row the cursor is not on")
	menu.selected_item_index = potion_at
	menu._update_selection()
	assert_false(GameState.is_unseen("potion"), "the cursor resting on the row is the player seeing it")
	assert_not_null(_row_for(menu, "potion").get_node_or_null(NewItemTag.NODE_NAME), "the tag stays drawn for the rest of this visit")


func _offensive_item_id() -> String:
	for id in ItemSystem.items:
		if int(ItemSystem.items[id].get("category", -1)) == ItemSystem.ItemCategory.OFFENSIVE:
			return str(id)
	return ""


func test_the_menu_entry_shows_news_only_for_what_it_can_show() -> void:
	if not _make_host():
		pending("a real GameLoop already lives at /root")
		return
	var menu = load("res://src/ui/OverworldMenu.gd").new()
	add_child_autofree(menu)
	var m := _member()
	menu.party = [m]
	m.inventory = {"potion": 2}
	var items_entry := {"id": "items"}
	GameState.note_acquired("potion")
	assert_true(menu._option_has_news(items_entry), "an unseen potion in the bag lights the Items entry")
	GameState.mark_seen("potion")
	assert_false(menu._option_has_news(items_entry), "once seen, the entry goes dark")
	var bomb := _offensive_item_id()
	assert_ne(bomb, "", "CONTROL: an offensive item must exist to test the field list's exclusion")
	m.inventory = {bomb: 1}
	GameState.note_acquired(bomb)
	assert_false(menu._option_has_news(items_entry), "an item the field Items list never shows cannot light its entry forever")
	var sword := str(EquipmentSystem.weapons.keys()[0])
	_host.equipment_pool["weapons"].append(sword)
	GameState.note_acquired(sword)
	assert_true(menu._option_has_news({"id": "equipment"}), "unseen gear in the pool lights the Equipment entry")


## Every function that appends to an equipment pool either marks the gear NEW or is a named non-acquisition.
func _pool_writers() -> Dictionary:
	var out: Dictionary = {}
	var append := RegEx.new()
	append.compile("(equipment_pool|\\bpool)\\[[^\\]]+\\]\\.append\\(")
	var handler := RegEx.new()
	handler.compile("\\nfunc ([A-Za-z0-9_]+)\\(")
	var stack: Array[String] = ["res://src"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(dir_path):
			stack.append(dir_path.path_join(sub))
		for f in DirAccess.get_files_at(dir_path):
			if not f.ends_with(".gd"):
				continue
			var code: String = GdSource.code_of(dir_path.path_join(f))
			for m in handler.search_all(code):
				var end: int = code.find("\nfunc ", m.get_start() + 1)
				var body: String = code.substr(m.get_start(), (end - m.get_start()) if end > 0 else -1)
				if append.search(body) != null and body.contains("equipment_pool"):
					out["%s:%s" % [f, m.get_string(1)]] = body.contains("note_acquired(")
	return out


func test_every_equipment_acquisition_marks_news() -> void:
	var writers := _pool_writers()
	var acquisitions := 0
	var silent: Array = []
	var named: Dictionary = {}
	for key in writers:
		var fn: String = str(key).get_slice(":", 1)
		if NOT_AN_ACQUISITION.has(fn):
			named[fn] = true
			continue
		acquisitions += 1
		if not writers[key]:
			silent.append(key)
	assert_gt(acquisitions, 3, "CONTROL: the scan must find the drop, chest, quest and shop writers, found %d: %s" % [acquisitions, writers.keys()])
	assert_eq(silent, [], "these put new gear in the pool without marking it NEW: %s" % [silent])
	for fn in NOT_AN_ACQUISITION:
		assert_true(named.has(fn), "the exemption '%s' no longer writes the pool; drop it from NOT_AN_ACQUISITION" % fn)


## The battle Item menu is a Win98Menu: the row carries a NEW badge span and marks itself seen on highlight.
func _battle_item_menu(item_ids: Array) -> Win98Menu:
	var rows: Array = []
	for id in item_ids:
		rows.append(BattleCommandMenu._with_new_badge({"id": "item_" + id, "label": "%s x2" % id, "data": {"item_id": id}}, id))
	var menu := Win98Menu.new()
	add_child_autofree(menu)
	menu.setup("Item", rows, Vector2(40, 40), "fighter")
	await get_tree().create_timer(0.25, true, false, true).timeout
	return menu


func test_the_battle_item_menu_badges_a_new_row_and_the_cursor_clears_it() -> void:
	GameState.note_acquired("potion")
	var menu: Win98Menu = await _battle_item_menu(["ether", "potion"])
	var container := menu._get_items_container()
	assert_eq(menu.selected_index, 0, "the cursor opens on the first row (ether)")
	assert_null(container.get_child(0).get_node_or_null("Badge"), "a seen item's row wears no badge")
	var badge := container.get_child(1).get_node_or_null("Badge") as Label
	assert_not_null(badge, "the new potion's row must wear the NEW badge")
	if badge == null:
		return
	assert_eq(badge.text, NewItemTag.TEXT)
	var clip := container.get_child(1).get_node("LabelClip") as Control
	assert_gte(badge.position.x + 0.5, clip.position.x + clip.size.x, "the badge sits right of the name, not over it")
	var need := badge.get_theme_font("font").get_string_size(badge.text, HORIZONTAL_ALIGNMENT_LEFT, -1, badge.get_theme_font_size("font_size")).x
	assert_gte(badge.size.x + 0.5, need, "the badge's span holds its own text")
	assert_lte(badge.position.x + need, container.get_child(1).size.x + 0.5, "the badge ends inside its row")
	assert_true(GameState.is_unseen("potion"), "the cursor has not rested on the potion yet")
	menu.selected_index = 1
	menu._update_selection()
	assert_false(GameState.is_unseen("potion"), "resting the cursor on the potion's row must clear its NEW")


func test_a_seen_item_gets_no_battle_badge() -> void:
	var row := BattleCommandMenu._with_new_badge({"id": "item_ether", "label": "Ether x1"}, "ether")
	assert_false(row.has("badge"), "an item nobody just picked up wears no badge")
	assert_false(row.has("on_highlight"), "and has nothing to clear")
