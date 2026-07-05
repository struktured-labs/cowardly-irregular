extends GutTest

## Feature 2026-07-04: the Quest Log and HUD tracker showed a fetch objective's
## description but never the item count — "Gather herbs" with no "2/5". New
## QuestSystem.fetch_progress(obj) returns Vector2i(have, need) with have capped
## at need, or Vector2i(-1, -1) for non-fetch objectives so both readouts append
## " [2/5]" only where it applies. It reads the fetch holder (party[0]) from the
## GameLoop node, which unit tests must stand in for (GameLoop is the main scene,
## not an autoload, so it is absent here).

var _fake_gl: Node = null


func after_each() -> void:
	# free() (immediate), not queue_free() — a deferred free would leave the
	# stale node in the tree so the NEXT test's holder becomes a second
	# /root/GameLoop and get_node_or_null returns the wrong one.
	if _fake_gl and is_instance_valid(_fake_gl):
		_fake_gl.free()
	_fake_gl = null


func _install_holder(item_id: String, qty: int) -> void:
	var gs := GDScript.new()
	gs.source_code = "extends Node\nvar party: Array = []"
	gs.reload()
	_fake_gl = Node.new()
	_fake_gl.set_script(gs)
	_fake_gl.name = "GameLoop"
	var c := Combatant.new()
	c.combatant_name = "Holder"
	if qty > 0:
		c.inventory[item_id] = qty
	_fake_gl.add_child(c)  # freed with the fake in after_each
	_fake_gl.party = [c]
	get_tree().root.add_child(_fake_gl)


func _fetch(item_id: String, count: int) -> Dictionary:
	return {"type": "fetch", "item_id": item_id, "count": count}


func test_nonfetch_objective_returns_sentinel() -> void:
	assert_eq(QuestSystem.fetch_progress({"type": "talk"}), Vector2i(-1, -1),
		"non-fetch objectives have no item-count readout")


func test_fetch_without_item_id_returns_sentinel() -> void:
	assert_eq(QuestSystem.fetch_progress({"type": "fetch", "count": 3}), Vector2i(-1, -1),
		"a fetch with no item_id can't report progress")


func test_partial_progress() -> void:
	_install_holder("herb", 2)
	assert_eq(QuestSystem.fetch_progress(_fetch("herb", 5)), Vector2i(2, 5),
		"holding 2 of 5 reports 2/5")


func test_progress_capped_at_need() -> void:
	_install_holder("herb", 7)
	assert_eq(QuestSystem.fetch_progress(_fetch("herb", 5)), Vector2i(5, 5),
		"overstocked fetch caps the displayed have at the needed count")


func test_zero_held() -> void:
	_install_holder("herb", 0)
	assert_eq(QuestSystem.fetch_progress(_fetch("herb", 5)), Vector2i(0, 5),
		"holding none reports 0/need")
