extends GutTest

## struktured 2026-11-01 (Harmonia item shop, the pilot's redrawn art): "you can be right on the door and not be allowed to
## enter, but LEFT of the door is fine". A building's one entrance stands under its DRAWN door (the door record's rect, or the
## art's centre without one), and a door with an opening strip opens before the fade and closes behind the player.

const HARMONIA := "res://src/maps/villages/HarmoniaVillage.tscn"
const VILLAGES := "res://src/maps/villages"
## A committed PNG stands in for a door strip; frames divide its width.
const STRIP := "res://assets/sprites/buildings/medieval/harmonia_arms.png"


func after_each() -> void:
	BaseVillage.building_art_override = null


func _village(path: String) -> Node:
	var v = load(path).instantiate() if path.ends_with(".tscn") else load(path).new()
	add_child_autofree(v)
	return v


func _house(v: Node, key: String) -> Node2D:
	return v.props.get_node_or_null("BuildingArt_" + key) as Node2D


## The building's own door record, as the runtime reads it: a list takes its first entry, absence is {}.
func _door_of(house: Node2D) -> Dictionary:
	var key := str(house.name).trim_prefix("BuildingArt_")
	var d: Variant = (BaseVillage._building_art_entries().get(key, {}) as Dictionary).get("door", {})
	if d is Array:
		d = (d as Array)[0] if not (d as Array).is_empty() else {}
	return d if d is Dictionary else {}


func _shop_named(v: Node, shop_name: String) -> Node2D:
	for b in v.buildings.get_children():
		if str(b.get("shop_name")) == shop_name:
			return b
	return null


func test_the_harmonia_item_shop_enters_from_under_its_drawn_door() -> void:
	var v := _village(HARMONIA)
	var house := _house(v, "harmonia_remedies")
	var shop := _shop_named(v, "Mystic Remedies")
	assert_not_null(house, "CONTROL: Harmonia draws the remedies building")
	assert_not_null(shop, "CONTROL: Harmonia has its item shop")
	if house == null or shop == null:
		return
	var door_x := VillageDoor.entrance_x(house, _door_of(house))
	assert_almost_eq(shop.global_position.x, door_x, 1.0, "the item shop's entrance is %.0f px off its drawn door" % (shop.global_position.x - door_x))
	## Walking straight up from the cell under the door: that point must sit inside the entrance's trigger.
	var cs := shop.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null:
		for c in shop.get_children():
			if c is CollisionShape2D:
				cs = c
	var r := Rect2(cs.global_position - (cs.shape as RectangleShape2D).size / 2.0, (cs.shape as RectangleShape2D).size)
	var below := Vector2(door_x, house.global_position.y + 16.0)
	assert_true(r.has_point(below), "standing right under the drawn door (%s) is outside the shop's trigger %s" % [below, r])


func test_every_drawn_building_with_one_entrance_has_it_under_its_door() -> void:
	var judged: int = 0
	for f in DirAccess.get_files_at(VILLAGES):
		if not f.ends_with("Village.gd") or f == "BaseVillage.gd":
			continue
		var v := _village(VILLAGES + "/" + f)
		for house in v.props.get_children():
			if not str(house.name).begins_with("BuildingArt_"):
				continue
			var cells := Rect2i(Vector2i(floori(house.position.x / 32.0), floori(house.position.y / 32.0) - house.size_tiles.y + 1), house.size_tiles)
			var found: Array = []
			for b in v.buildings.get_children():
				if b is AreaTransition and cells.grow_individual(0, 0, 0, 1).has_point(Vector2i(floori(b.position.x / 32.0), floori(b.position.y / 32.0))):
					found.append(b)
				elif b is Area2D and b.has_method("interact") and v._building_cells(b).intersects(cells):
					found.append(b)
			if found.size() != 1:
				continue
			judged += 1
			var x := VillageDoor.entrance_x(house, _door_of(house))
			assert_almost_eq((found[0] as Node2D).global_position.x, x, 1.0, "%s: %s stands off its drawn door" % [f, house.name])
	assert_gt(judged, 10, "only %d drawn buildings with one entrance were judged" % judged)


func test_every_entrance_building_has_a_door_record_once_records_exist() -> void:
	## cowir-adhoc 21331: a building the door probe silently skips must not drop out of the corpus. Pending until any record lands.
	var entries := BaseVillage._building_art_entries()
	var with_door: Array = entries.keys().filter(func(k): return (entries[k] as Dictionary).has("door"))
	if with_door.is_empty():
		pending("no building_art entry carries a door record yet (0 of %d); this arm becomes required when the first lands" % entries.size())
		return
	for k in entries:
		if str(k).begins_with("harmonia_") and k != "harmonia_house":
			assert_true((entries[k] as Dictionary).has("door"), "building_art %s owns an entrance but has no door record (%d of %d have one)" % [k, with_door.size(), entries.size()])


func _planted_door_village() -> Node:
	var e := {}
	for k in BaseVillage._building_art_entries():
		e[k] = (BaseVillage._building_art_entries()[k] as Dictionary).duplicate()
	BaseVillage.building_art_override = null
	e["harmonia_remedies"]["door"] = {"rect": [80, 100, 32, 50], "open": STRIP, "frames": 4, "style": "house"}
	BaseVillage.building_art_override = e
	return _village(HARMONIA)


func test_a_door_opens_before_the_fade_and_its_absence_does_not_wait() -> void:
	var v := _planted_door_village()
	var house := _house(v, "harmonia_remedies")
	var strip := house.get_node_or_null("DoorOpen") as Sprite2D if house else null
	assert_not_null(strip, "the planted door record built no opening strip")
	if strip == null:
		return
	assert_false(strip.visible, "a closed door's strip draws over the building")
	var shop := _shop_named(v, "Mystic Remedies")
	assert_almost_eq(shop.global_position.x, VillageDoor.world_rect(house, [80, 100, 32, 50]).get_center().x, 1.0, "the entrance did not follow the door record")
	var fired := [-1]
	v.area_transition.connect(func(_m, _s): fired[0] = Time.get_ticks_msec(), CONNECT_ONE_SHOT)
	var foot := strip.global_position + Vector2(strip.texture.get_width() / 8.0, strip.texture.get_height())
	v.player.global_position = foot
	var t0 := Time.get_ticks_msec()
	v._on_transition_triggered("harmonia_item_shop", "entrance")
	assert_eq(fired[0], -1, "the fade began before the door opened")
	while fired[0] == -1 and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	assert_gte(fired[0] - t0, int(VillageDoor.SECONDS * 1000.0) - 20, "the door's beat was skipped")
	assert_eq(strip.frame, strip.hframes - 1, "the door is not open when the fade starts")
	assert_true(v.door_cue_played, "GameLoop was not told the village door already sounded")
	## CONTROL: away from any door, the fade starts at once.
	v.player.global_position = foot + Vector2(400, 0)
	var at := [-1]
	v.area_transition.connect(func(_m, _s): at[0] = 1, CONNECT_ONE_SHOT)
	v._on_transition_triggered("overworld", "village_entrance")
	assert_eq(at[0], 1, "a transition with no door at hand waited for one")
	assert_false(v.door_cue_played, "a doorless transition claimed the door cue")


func test_a_door_closes_behind_the_player_on_the_way_out() -> void:
	var v := _planted_door_village()
	var strip := _house(v, "harmonia_remedies").get_node_or_null("DoorOpen") as Sprite2D
	if strip == null:
		fail_test("the planted door record built no opening strip")
		return
	var foot := strip.global_position + Vector2(strip.texture.get_width() / 8.0, strip.texture.get_height())
	v.spawn_points["remedies_test_exit"] = foot
	v.spawn_player_at("remedies_test_exit")
	assert_true(strip.visible, "stepping out did not show the door closing")
	var t0 := Time.get_ticks_msec()
	while strip.visible and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	assert_false(strip.visible, "the door never finished closing")
	assert_eq(strip.frame, 0, "the door did not close")
