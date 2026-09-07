extends GutTest

## struktured, 2026-09-06: "collision detection is better than ever but still not spot on,
## its prob better in mode 7 than in villagds though irioncally".
##
## He was right, and the irony has a cause. Mode 7's collision is DERIVED -- a displaced
## clone of the tilemap -- so when it was wrong it was wrong everywhere at once and got
## found and fixed. Village props build their art and their collision from two SEPARATE
## expressions of the same footprint, and those only disagreed for props wider than one
## tile. Measured on the shipped build: stall, well and cart drew at x[-32..32] while
## colliding at x[-16..48] -- solid half a tile right of their own picture. You bumped
## empty air on one side and walked through the art on the other. Every 1-wide prop was
## exact, which is precisely why it read as "close but not spot on" instead of as broken.
##
## WHY A TEST AND NOT JUST THE FIX. The two expressions are still separate -- the sprite is
## placed from SIZES, the boxes from FOOTPRINTS -- because the art legitimately extends
## above and beyond the footprint (a tree's canopy is not solid). Nothing makes them agree
## on the GROUND ROW except this. A future prop, or a future re-centring of the art, silently
## reintroduces the same half-tile lie, and a half-tile lie is invisible in a screenshot.
##
## WHAT IS ASSERTED is the RELATIONSHIP, not any coordinate: the collision's horizontal
## span must equal the art's horizontal span. Pinning "-16" instead would go red on a
## correct re-authoring and green on a wrong one.

const VP := preload("res://src/exploration/VillageProp.gd")


func _bounds(p: Node) -> Dictionary:
	var spr: Sprite2D = p.get_node_or_null("Sprite")
	var body: StaticBody2D = null
	for c in p.get_children():
		if c is StaticBody2D:
			body = c
	if spr == null or spr.texture == null or body == null:
		return {}
	var boxes: Array = []
	for c in body.get_children():
		if c is CollisionShape2D and c.shape is RectangleShape2D:
			boxes.append(c)
	if boxes.is_empty():
		return {}
	var col_l: float = INF
	var col_r: float = -INF
	for c in boxes:
		var ext: float = (c.shape as RectangleShape2D).size.x / 2.0
		col_l = minf(col_l, c.position.x - ext)
		col_r = maxf(col_r, c.position.x + ext)
	return {
		"art_l": spr.position.x,
		"art_r": spr.position.x + float(spr.texture.get_width()),
		"col_l": col_l, "col_r": col_r,
	}


func test_every_solid_prop_collides_where_it_is_drawn() -> void:
	var checked := 0
	var offenders: Array = []
	for kind in VP.SIZES.keys():
		var p = VP.create(kind, Vector2i(0, 0))
		add_child_autofree(p)
		var b := _bounds(p)
		if b.is_empty():
			continue          # BANNER and friends are decoration with no footprint
		checked += 1
		if not (is_equal_approx(b["art_l"], b["col_l"]) and is_equal_approx(b["art_r"], b["col_r"])):
			offenders.append("kind %d: art x[%.0f..%.0f] but collides x[%.0f..%.0f]"
				% [kind, b["art_l"], b["art_r"], b["col_l"], b["col_r"]])

	# CONTROL: an empty sweep satisfies the offender assert for free. The village prop set
	# has several solid kinds; if this drops to zero the probe stopped seeing them.
	assert_gt(checked, 5, "only %d solid props measured -- the probe is not building props" % checked)
	assert_eq(offenders, [],
		"a prop that is solid somewhere other than where it is drawn reads to the player as bad collision, not as a bad sprite:\n  %s"
			% "\n  ".join(offenders))


func test_a_multi_row_footprint_would_get_collision_on_every_row() -> void:
	# The latent half of the same defect: the box's Y came from a constant, so every box
	# landed on the base row whatever its offset said. Inert while all footprints are y=0,
	# and it would have silently deleted the collision of the first prop given depth.
	var src := FileAccess.get_file_as_string("res://src/exploration/VillageProp.gd")
	assert_gt(src.length(), 2000, "CONTROL: read a real file")
	assert_true(src.contains("off.y * TILE"),
		"the collider's Y must come from the footprint offset, not from a constant -- "
		+ "otherwise a prop with vertical extent collides only on its bottom row")
