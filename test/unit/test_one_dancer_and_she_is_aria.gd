extends GutTest

## struktured, playing .808: "why are there two identical looking dancers inside the tavern?" The stage carried a nameless
## decoration sprite and Aria stood on the floor below it; once Aria took the artist's frames the two were the same figure.
## His ruling (cowir-main 26387): Aria on the stage, one dancer, and the floor in front can still talk to her.

const FRAME := "res://assets/sprites/npcs/dancer/frame_%d.png"

var _tav: TavernInterior


func before_each() -> void:
	_tav = TavernInterior.new()
	add_child_autofree(_tav)


func _bytes(tex: Texture2D) -> PackedByteArray:
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img.get_data()


## Every Sprite2D under `root` that is showing one of the four dancer frames.
func _dancer_figures(root: Node) -> Array:
	var art: Array = []
	for i in 4:
		art.append(_bytes(load(FRAME % i)))
	var out: Array = []
	for n in root.find_children("*", "Sprite2D", true, false):
		var spr := n as Sprite2D
		if spr.texture != null and art.has(_bytes(spr.texture)):
			out.append(spr)
	return out


func _aria() -> OverworldNPC:
	for n in _tav.npcs.get_children():
		if n is OverworldNPC and n.npc_name == "Aria":
			return n
	return null


func _layout_char(cell: Vector2i) -> String:
	return str(TavernInterior.TAVERN_LAYOUT[cell.y])[cell.x]


func test_the_tavern_shows_one_dancer_and_she_is_aria() -> void:
	var aria := _aria()
	assert_not_null(aria, "CONTROL: the tavern has Aria")
	var shown := _dancer_figures(_tav)
	assert_eq(shown.size(), 1, "the tavern shows %d dancer figures" % shown.size())
	if aria != null and shown.size() == 1:
		assert_true(aria.is_ancestor_of(shown[0]), "the one dancer figure belongs to Aria, it is %s" % str(shown[0].get_path()))
	var twin := Sprite2D.new()
	twin.texture = load(FRAME % 0)
	_tav.add_child(twin)
	assert_eq(_dancer_figures(_tav).size(), 2, "CONTROL: a second figure in the artist's frames is counted")


func test_aria_stands_on_the_stage() -> void:
	var aria := _aria()
	assert_not_null(aria, "CONTROL: the tavern has Aria")
	if aria == null:
		return
	var cell := Vector2i(int(floor(aria.position.x / TavernInterior.TILE_SIZE)), int(floor(aria.position.y / TavernInterior.TILE_SIZE)))
	assert_eq(_layout_char(cell), "S", "Aria stands on %s, which is '%s' and not a stage cell" % [str(cell), _layout_char(cell)])
	assert_almost_eq(aria.position.x, TavernInterior.STAGE_CENTER_X * TavernInterior.TILE_SIZE, 0.5, "she takes the stage's centre column")
	assert_eq(_layout_char(Vector2i(21, 5)), ".", "CONTROL: her old mark (21, 5) is floor, not stage")


func test_aria_dances_without_being_asked() -> void:
	var aria := _aria()
	assert_not_null(aria, "CONTROL: the tavern has Aria")
	if aria == null:
		return
	assert_true(aria.performs, "the tavern's dancer is a stage act")
	assert_true(aria._is_dancing, "she is dancing before anyone has spoken to her")
	var before: int = aria._dance_frame
	aria._process(OverworldNPC.DANCE_SPEED * 1.1)
	assert_ne(aria._dance_frame, before, "and her dance advances on its own")
	var plain := OverworldNPC.new()
	plain.npc_name = "Understudy"
	plain.npc_type = "dancer"
	add_child_autofree(plain)
	assert_false(plain._is_dancing, "CONTROL: a dancer who is not a stage act rests until spoken to")


func test_the_floor_in_front_can_talk_to_her() -> void:
	var aria := _aria()
	assert_not_null(aria, "CONTROL: the tavern has Aria")
	if aria == null:
		return
	var reach: float = 0.0
	for c in aria.get_children():
		if c is CollisionShape2D and c.shape is CircleShape2D:
			reach = (c.shape as CircleShape2D).radius
	assert_gt(reach, 0.0, "CONTROL: Aria has a talk circle")
	var t: float = TavernInterior.TILE_SIZE
	var front_row: int = TavernInterior.STAGE_ROW_LAST + 1
	var judged: int = 0
	for col in [int(TavernInterior.STAGE_CENTER_X) - 1, int(TavernInterior.STAGE_CENTER_X)]:
		var cell := Vector2i(col, front_row)
		assert_eq(_layout_char(cell), ".", "CONTROL: %s in front of the stage is open floor" % str(cell))
		var stand := Vector2((col + 0.5) * t, (front_row + 0.5) * t)
		assert_lt(stand.distance_to(aria.position), reach, "a player on floor cell %s is %.1f px from Aria, her talk reach is %.1f" % [str(cell), stand.distance_to(aria.position), reach])
		var old_centre := Vector2(TavernInterior.STAGE_CENTER_X * t, TavernInterior.STAGE_CENTER_Y * t)
		assert_gt(stand.distance_to(old_centre), reach, "CONTROL: from the stage's centre the same floor cell is out of reach, which is why she takes the front row")
		judged += 1
	assert_eq(judged, 2, "CONTROL: both floor cells in front of her were judged")
