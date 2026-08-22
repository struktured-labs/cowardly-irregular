extends GutTest

## struktured 2026-08-22: "the 'ZZZ 1' status indicator is ghetto. we need an animation to
## indicte they are sleeping, same with all animations."
##
## The blocker for ANY animated icon was structural, not artistic: _refresh_status_icons
## cleared and rebuilt the whole row on every status change AND every round tick. A looping
## idle animation would restart constantly — visibly worse than the static badge. Icons are
## now keyed by status and REUSED, so a persisting status keeps its node and its phase.

var _scene = null


func before_each() -> void:
	_scene = load("res://src/battle/BattleScene.gd").new()


func after_each() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.free()
	_scene = null


func _combatant(statuses: Array, durations: Dictionary = {}) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Tester"
	for s in statuses:
		c.status_effects.append(str(s))
	for k in durations:
		c.status_durations[k] = durations[k]
	return c


func _row_for(c: Combatant) -> HBoxContainer:
	var row := HBoxContainer.new()
	add_child_autofree(row)
	_scene._status_icon_containers[c] = row
	return row


func _names(row: HBoxContainer) -> Array:
	var out: Array = []
	for ch in row.get_children():
		if not ch.is_queued_for_deletion():
			out.append(String(ch.name))
	return out


# THE FIX: a status that persists across a refresh must keep the SAME NODE.
func test_a_persisting_status_keeps_its_icon_node() -> void:
	var c := _combatant(["sleep"], {"sleep": 3})
	var row := _row_for(c)
	_scene._refresh_status_icons(c, false)
	assert_eq(row.get_child_count(), 1, "one status, one icon")
	var first_id: int = row.get_child(0).get_instance_id()

	c.status_durations["sleep"] = 2
	_scene._refresh_status_icons(c, false)
	assert_eq(row.get_child_count(), 1, "still one icon after the round tick")
	assert_eq(row.get_child(0).get_instance_id(), first_id,
		"the sleep icon must be the SAME node — a rebuild restarts its idle animation every round")


# CONTROL: reuse must not mean "never creates". A genuinely new status gets a new node.
func test_a_new_status_still_creates_a_new_icon() -> void:
	var c := _combatant(["sleep"])
	var row := _row_for(c)
	_scene._refresh_status_icons(c, false)
	var sleep_id: int = row.get_child(0).get_instance_id()

	c.status_effects.append("poison")
	_scene._refresh_status_icons(c, false)
	assert_eq(row.get_child_count(), 2, "poison must add a second icon")
	var ids: Array = []
	for ch in row.get_children():
		ids.append(ch.get_instance_id())
	assert_true(ids.has(sleep_id), "sleep must still be the same node while poison joins")


func test_a_removed_status_drops_its_icon() -> void:
	var c := _combatant(["sleep", "poison"])
	var row := _row_for(c)
	_scene._refresh_status_icons(c, false)
	assert_eq(row.get_child_count(), 2, "two statuses, two icons")

	c.status_effects.erase("sleep")
	_scene._refresh_status_icons(c, false)
	assert_false(_names(row).has("st_sleep"), "the sleep icon must be gone once the status ends")
	assert_true(_names(row).has("st_poison"), "poison must survive its neighbour's removal")


func test_the_turn_counter_updates_without_replacing_the_node() -> void:
	var c := _combatant(["stun"], {"stun": 3})
	var row := _row_for(c)
	_scene._refresh_status_icons(c, false)
	var node_id: int = row.get_child(0).get_instance_id()
	var before: String = _label_text(row.get_child(0))

	c.status_durations["stun"] = 1
	_scene._refresh_status_icons(c, false)
	var after: String = _label_text(row.get_child(0))
	assert_eq(row.get_child(0).get_instance_id(), node_id, "same node")
	assert_ne(before, after, "the counter must actually change (3 -> 1)")
	assert_true(after.ends_with("1"), "expected the badge to read '... 1', got '%s'" % after)


func _label_text(icon: Node) -> String:
	for ch in icon.get_children():
		if ch is Label:
			return ch.text
	return ""


# Families are ABSOLUTE expected strings — never derived from the thing under test.
func test_status_families_map_to_distinct_idle_motions() -> void:
	assert_eq(_scene._status_icon_family("sleep"), "sleep", "sleep is the one he named")
	assert_eq(_scene._status_icon_family("stun"), "jitter")
	assert_eq(_scene._status_icon_family("confuse"), "jitter")
	assert_eq(_scene._status_icon_family("poison"), "throb")
	assert_eq(_scene._status_icon_family("burning"), "throb")
	assert_eq(_scene._status_icon_family("attack_up"), "rise")
	assert_eq(_scene._status_icon_family("defense_down"), "sag")
	assert_eq(_scene._status_icon_family("totally_made_up_status"), "breathe",
		"an unknown status must still get motion, not stand still")


func test_icon_keys_are_valid_and_distinct_node_names() -> void:
	assert_eq(_scene._status_icon_key("attack_up"), "st_attack_up")
	assert_ne(_scene._status_icon_key("attack_up"), _scene._status_icon_key("attack_down"),
		"buff and debuff must not collide onto one node")
	var weird: String = _scene._status_icon_key("odd name/with:chars")
	assert_false(weird.contains("/") or weird.contains(":") or weird.contains(" "),
		"node names must not carry path or space characters; got '%s'" % weird)
