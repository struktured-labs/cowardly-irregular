extends GutTest

## Regression (cowir-main's .613 Fire Dragon Cave floor 5 frame): the floor-label sign and a lore sign stand side by
## side, and both texts showed at once, drawn over each other ("The Caldera. Pyrroth has been rehearsing his
## entrance..." across "Infernal Grotto · Floor 5 / 5"). Signs in range of one player now yield to the nearest.

var _player: CharacterBody2D = null


func _sign(text: String, pos: Vector2) -> Signpost:
	var s := Signpost.new()
	s.sign_text = text
	s.position = pos
	add_child_autofree(s)
	return s


func _put_player(pos: Vector2) -> void:
	_player = CharacterBody2D.new()
	_player.add_to_group("player")
	_player.position = pos
	add_child_autofree(_player)


func _enter(s: Signpost) -> void:
	s._on_body_entered(_player)


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func test_a_lone_sign_shows_its_text() -> void:
	var a := _sign("Alone", Vector2(100, 100))
	_put_player(Vector2(100, 120))
	_enter(a)
	await _settle()
	assert_true(a._label.visible, "CONTROL: a sign with no neighbour still speaks")


func test_the_nearer_of_two_signs_speaks_alone() -> void:
	var a := _sign("Near", Vector2(100, 100))
	var b := _sign("Far", Vector2(132, 100))
	_put_player(Vector2(104, 120))
	_enter(a)
	_enter(b)
	await _settle()
	assert_true(a._label.visible, "the nearer sign shows its text")
	assert_false(b._label.visible, "the farther sign stays quiet instead of drawing over it")


func test_a_tie_still_shows_exactly_one() -> void:
	var a := _sign("Left", Vector2(100, 100))
	var b := _sign("Right", Vector2(132, 100))
	_put_player(Vector2(116, 120))
	_enter(a)
	_enter(b)
	await _settle()
	assert_eq(int(a._label.visible) + int(b._label.visible), 1, "standing square between two posts shows one text, never both")
