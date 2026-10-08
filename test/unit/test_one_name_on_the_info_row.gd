extends GutTest

## In Mode 7 every NPC name, wanderer remark and sign lifts its label onto ONE screen row above the player, so two in
## range drew on top of each other -- the W4 overworld survey showed "Guard Paulsen" printed over a second name.
## Only the owner nearest the player draws on that row now; the rest are muted until it leaves.

class Owner extends Node2D:
	var label := Label.new()
	func _ready() -> void:
		add_to_group(Mode7Prompt.INFO_GROUP)
		label.text = name
		add_child(label)
	func _info_row_label() -> CanvasItem:
		return label


func _player_at(p: Vector2) -> Node2D:
	var pl := Node2D.new()
	pl.add_to_group("player")
	add_child_autofree(pl)
	pl.global_position = p
	return pl


func _owner_at(p: Vector2, n: String) -> Owner:
	var o := Owner.new()
	o.name = n
	add_child_autofree(o)
	o.global_position = p
	return o


func test_only_the_nearest_owner_draws_on_the_row() -> void:
	_player_at(Vector2.ZERO)
	var near := _owner_at(Vector2(20, 0), "Near")
	var far := _owner_at(Vector2(60, 0), "Far")
	for o in [near, far]:
		Mode7Prompt.share_info_row(o, o.label, true)
	assert_eq(near.label.self_modulate.a, 1.0, "the nearest name draws")
	assert_eq(far.label.self_modulate.a, 0.0, "the farther name yields the shared row")


func test_a_tie_still_draws_exactly_one() -> void:
	_player_at(Vector2.ZERO)
	var a := _owner_at(Vector2(30, 0), "A")
	var b := _owner_at(Vector2(-30, 0), "B")
	for o in [a, b]:
		Mode7Prompt.share_info_row(o, o.label, true)
	assert_eq(a.label.self_modulate.a + b.label.self_modulate.a, 1.0, "a tie draws one name, never both")


func test_flat_maps_draw_every_name() -> void:
	_player_at(Vector2.ZERO)
	var near := _owner_at(Vector2(20, 0), "Near")
	var far := _owner_at(Vector2(60, 0), "Far")
	for o in [near, far]:
		Mode7Prompt.share_info_row(o, o.label, false)
	assert_eq(far.label.self_modulate.a, 1.0, "off Mode 7 each label sits over its own owner, so all draw")


func test_a_hidden_label_does_not_claim_the_row() -> void:
	_player_at(Vector2.ZERO)
	var near := _owner_at(Vector2(20, 0), "Near")
	var far := _owner_at(Vector2(60, 0), "Far")
	near.label.visible = false
	Mode7Prompt.share_info_row(far, far.label, true)
	assert_eq(far.label.self_modulate.a, 1.0, "a nearer owner showing nothing leaves the row to the next one")


## Derived from source: every script that places on ROW_INFO must take part, or a new owner overlaps again.
func test_every_info_row_owner_takes_part() -> void:
	var found := 0
	var dir := DirAccess.open("res://src/exploration")
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string("res://src/exploration/" + f)
		if not src.contains("Mode7Prompt.ROW_INFO"):
			continue
		found += 1
		assert_true(src.contains("add_to_group(Mode7Prompt.INFO_GROUP)"), "%s places on ROW_INFO but never joins the group" % f)
		assert_true(src.contains("func _info_row_label()"), "%s places on ROW_INFO but names no label" % f)
		assert_true(src.contains("Mode7Prompt.share_info_row("), "%s places on ROW_INFO but never yields the row" % f)
	assert_gt(found, 2, "CONTROL: the ROW_INFO owners were found (%d)" % found)
