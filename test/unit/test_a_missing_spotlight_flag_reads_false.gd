extends GutTest

## `bool(gl.get("_spotlight_duel_active"))` errors when the GameLoop node lacks that property — Object.get returns
## null and Godot has no bool(Nil) constructor — and the error aborts the whole function. `_drop_bag_holder` then
## returns null, so a monster's drop had no bag to land in. Measured in the .618 gate log against a stub GameLoop.
## The editor half: three structural edits indexed `rules[cursor_row]` with no rules ("Out of bounds get index '0'").

var _stub: Node = null


func after_each() -> void:
	if is_instance_valid(_stub):
		_stub.free()
	_stub = null


func _bm() -> Node:
	return get_tree().root.get_node_or_null("BattleManager")


func _plant_gameloop_without_the_flag() -> bool:
	if get_tree().root.get_node_or_null("GameLoop") != null:
		return false
	_stub = Node.new()
	_stub.name = "GameLoop"
	get_tree().root.add_child(_stub)
	return true


func test_the_drop_bag_is_the_lead_when_gameloop_has_no_spotlight_flag() -> void:
	var bm := _bm()
	assert_not_null(bm, "CONTROL: the BattleManager autoload is present")
	if bm == null:
		return
	if not _plant_gameloop_without_the_flag():
		pending("a real GameLoop is mounted; this arm needs one without the spotlight property")
		return
	var lead := Combatant.new()
	autofree(lead)
	# An aborted _drop_bag_holder yields Variant's default, null; the guarded one reaches the party fallback.
	assert_eq(bm.call("_drop_bag_holder", [lead]), lead, "the drop lands with the party lead, not nowhere")


func test_the_consumable_bag_is_the_party_when_gameloop_has_no_spotlight_flag() -> void:
	var bm := _bm()
	if bm == null or not _plant_gameloop_without_the_flag():
		pending("needs the BattleManager autoload and no real GameLoop")
		return
	var lead := Combatant.new()
	autofree(lead)
	var saved_party: Array = (bm.get("player_party") as Array).duplicate()
	var typed: Array[Combatant] = [lead]
	bm.set("player_party", typed)
	assert_true(lead in (bm.get("player_party") as Array), "CONTROL: the lead is in the party, so the flag line is reached")
	var bag: Array = (bm.call("consumable_bag", lead) as Array).duplicate()  # it returns player_party itself
	(bm.get("player_party") as Array).assign(saved_party)
	# Aborted, this returns Array's default []; the guarded path returns the party.
	assert_eq(bag.size(), 1, "the consumable bag is the party (%d)" % bag.size())


## Source pin, labelled as one: an aborted edit and a guarded return leave the same empty grid, so no behaviour differs.
func test_every_structural_edit_checks_the_row_before_indexing_it() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindGridEditor.gd")
	assert_gt(src.length(), 1000, "CONTROL: the editor source reads")
	for fn in ["_add_and_condition", "_add_action", "_delete_current_cell"]:
		var start := src.find("func %s(" % fn)
		assert_gt(start, -1, "CONTROL: %s exists" % fn)
		var index_at := src.find("var rule = rules[cursor_row]", start)
		var guard_at := src.find("cursor_row >= rules.size()", start)
		assert_true(guard_at > -1 and guard_at < index_at, "%s bounds the row before rules[cursor_row]" % fn)
