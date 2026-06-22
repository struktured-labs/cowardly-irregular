extends GutTest

## tick 18 added floor persistence to WhisperingCave. The DragonCave
## base class — which 10 dungeons inherit from (4 dragon caves, Castle
## Harmonia, Assembly Core, Null Chamber, Root Process, Steampunk
## Mechanism, Suburban Underground) — had the same gap. A player who
## saved on floor 3 of Pyrroth's cave reloaded on floor 1.
##
## Fix: same pattern as WhisperingCave but scoped by `cave_id` so each
## dungeon persists independently. The base class fixes all subclasses
## at once.

const DRAGON_CAVE := "res://src/maps/dungeons/DragonCave.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _body_of(func_name: String) -> String:
	var src := _read(DRAGON_CAVE)
	var idx := src.find("func " + func_name)
	assert_gt(idx, -1, func_name + " must exist")
	var next_fn := src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_transition_writes_per_cave_floor_key() -> void:
	var body := _body_of("_transition_to_floor")
	# Key is cave_id-scoped so each dungeon persists independently. A
	# hardcoded "dragon_cave_floor" would have all 10 dungeons trampling
	# each other.
	assert_true(body.contains("cave_id + \"_floor\""),
		"_transition_to_floor must write a per-cave_id floor key, not a global one")
	assert_true(body.contains("= current_floor"),
		"_transition_to_floor must persist current_floor (the assignment, not just the key)")


func test_ready_restores_per_cave_floor_with_total_floors_clamp() -> void:
	var body := _body_of("_ready")
	assert_true(body.contains("cave_id + \"_floor\""),
		"_ready must look up the per-cave_id floor key (matching what _transition writes)")
	assert_true(body.contains("current_floor = saved_floor"),
		"_ready must assign the saved floor")
	# Range guard: clamp must use `total_floors`, NOT a hardcoded
	# constant — different dungeons have different floor counts
	# (Whispering Cave is 6, dragon caves are 3, Castle Harmonia is N).
	assert_true(body.contains("saved_floor <= total_floors"),
		"floor clamp must use total_floors so caves with different lengths share the same base-class restore safely")


func test_transition_to_overworld_clears_per_cave_floor() -> void:
	var body := _body_of("_on_transition_triggered")
	assert_true(body.contains("game_constants.erase(cave_id + \"_floor\")"),
		"exiting the cave must erase the per-cave floor key — re-entry starts at floor 1")
	# The clear must be conditional on cave_id != "" so a never-set
	# subclass (forgot to assign cave_id) doesn't erase the empty key
	# and pollute game_constants with `_floor` entries.
	assert_true(body.contains("cave_id != \"\""),
		"erase must check cave_id != '' to skip subclasses that left cave_id unset")
