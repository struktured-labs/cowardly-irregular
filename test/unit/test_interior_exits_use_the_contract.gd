extends GutTest
## Interior exit doors must get their geometry from InteractGeometry, not from a literal.
##
## FOUND 2026-08-22. InteractGeometry declares the interaction contract and
## test_interact_geometry_contract pins its values -- and it was green while the contract
## was NOT IN FORCE. DOOR_BOX(64,48) was read by zero source files; the 30 interior exits
## that actually ship each hand-rolled a RectangleShape2D at Vector2(TILE_SIZE*2, TILE_SIZE)
## = 64x32, and hardcoded collision_layer 4 / collision_mask 2 beside it. A value pin
## certifies the DECLARATION; it cannot ask whether anything obeys it.
##
## WHY THIS INSTANTIATES RATHER THAN GREPS. A source check would assert that each interior
## spells the call some particular way -- a use-site pin, which reds on a correct refactor
## and passes on a wrong value spelled right. This reads the shape the ENGINE built, which
## is the only thing the player meets.
##
## TavernInterior is a DELIBERATE exception at (TILE_SIZE*3+16, TILE_SIZE*2+16): its comment
## records that the narrower box was a bug -- it missed the outer threshold row of a 2-row
## door band. Pinned here as an exception so nobody "fixes" it back.

const EXPECTED_EXCEPTIONS := {"TavernInterior": Vector2(112, 80)}
const SAMPLE := [
	"res://src/maps/interiors/ScripturaBookshopInterior.gd",
	"res://src/maps/interiors/MapleHeightsArcadeInterior.gd",
	"res://src/maps/interiors/FrostholdWardenHutInterior.gd",
]


func _exit_shape_size(path: String) -> Variant:
	var script = load(path)
	if script == null:
		return null
	var node = script.new()
	if node == null:
		return null
	add_child_autofree(node)
	var found: Variant = null
	for child in node.find_children("*", "Area2D", true, false):
		if str(child.name) != "Exit":
			continue
		for c in child.get_children():
			if c is CollisionShape2D and c.shape is RectangleShape2D:
				found = (c.shape as RectangleShape2D).size
	return found


func test_a_real_interior_exit_measures_the_contract_value() -> void:
	var measured := 0
	for path in SAMPLE:
		var size = _exit_shape_size(path)
		if size == null:
			continue
		measured += 1
		assert_eq(size, InteractGeometry.INTERIOR_EXIT_BOX,
			"%s exit is %s, not the contract's %s" % [path.get_file(), str(size), str(InteractGeometry.INTERIOR_EXIT_BOX)])
	assert_gt(measured, 0, "no interior exit could be instantiated -- this test measured nothing")


func test_no_interior_hand_rolls_an_exit_shape_any_more() -> void:
	var dir := DirAccess.open("res://src/maps/interiors")
	assert_true(dir != null, "the interiors directory is unreadable -- the scan is dead")
	var offenders: Array = []
	var scanned := 0
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		scanned += 1
		var src := FileAccess.get_file_as_string("res://src/maps/interiors/" + f)
		# an exit that builds its own rectangle instead of calling the shared builder
		if src.contains("RectangleShape2D.new()") and src.contains("exit.collision_layer"):
			if not EXPECTED_EXCEPTIONS.has(f.get_basename()):
				offenders.append(f)
	assert_gt(scanned, 20, "only %d interior scripts scanned -- the directory read is not working" % scanned)
	assert_eq(offenders, [], "these interiors still hand-roll their exit geometry: %s" % str(offenders))
	# every exception must still SUPPRESS a real detection -- an entry whose subject was
	# fixed goes inert while the suite stays green, documenting a hazard that is gone
	for name in EXPECTED_EXCEPTIONS:
		var src := FileAccess.get_file_as_string("res://src/maps/interiors/%s.gd" % name)
		assert_true(src.length() > 0, "exception names %s, which no longer exists" % name)
		assert_true(
			src.contains("RectangleShape2D.new()") and src.contains("exit.collision_layer"),
			"EXPECTED_EXCEPTIONS still lists %s but it no longer hand-rolls its exit -- the entry suppresses nothing, delete it" % name
		)
