extends GutTest

## tick 73 regression: every interior map_id must classify as
## "interior" (not "village"), and GameLoop must have an "interior"
## match arm that routes through the quick interior transition
## functions instead of the dramatic village wipe.
##
## Original bug (caught in tick 73 audit): _get_transition_type
## classified all 12 interior map_ids as "village" via substring
## token matching on "harmonia"/"vertex"/"prime"/etc. Stepping into
## Sister Concord's chapel — a single room INSIDE Harmonia — played
## the full "Arriving at Chapel..." amber wipe meant for arriving at
## a new town. The transition was tonally wrong for a small interior.

const GAME_LOOP := "res://src/GameLoop.gd"


const INTERIOR_MAP_IDS: Array[String] = [
	"harmonia_chapel",
	"harmonia_library",
	"tavern_interior",
	"eldertree_hollow",
	"frosthold_warden_hut",
	"sandrift_glassmaker",
	"grimhollow_witch_hut",
	"ironhaven_watchtower",
	"maple_heights_arcade",
	"brasston_clockwork_loft",
	"rivet_row_union_hall",
	"node_prime_daemon_lounge",
	"vertex_threshold",
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_interior_map_ids_const_lists_every_interior() -> void:
	# Pin the const itself — the _get_transition_type interior check
	# depends on it. Adding a 13th interior without updating the const
	# would silently send it through the village wipe.
	var src := _read(GAME_LOOP)
	assert_true(src.contains("const INTERIOR_MAP_IDS"),
		"GameLoop must declare INTERIOR_MAP_IDS const so _get_transition_type can route interiors separately")
	for map_id in INTERIOR_MAP_IDS:
		var quoted: String = "\"" + map_id + "\""
		assert_true(src.contains(quoted),
			"INTERIOR_MAP_IDS must contain '%s' — otherwise it falls through to village wipe" % map_id)


func test_get_transition_type_checks_interior_before_village() -> void:
	# Ordering is critical: every interior map_id ALSO contains a
	# village substring token (harmonia/vertex/prime/etc), so the
	# interior check must run FIRST. If someone reorders it below
	# the village substring check, interiors silently re-classify
	# as village.
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _get_transition_type")
	assert_gt(idx, -1, "_get_transition_type must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	# Anchor on actual code patterns (not docstring mentions).
	var interior_check: int = body.find("map_id in INTERIOR_MAP_IDS")
	var village_check: int = body.find("\"village\" in t")
	assert_gt(interior_check, -1, "_get_transition_type must check 'map_id in INTERIOR_MAP_IDS'")
	assert_gt(village_check, -1, "_get_transition_type must still check '\"village\" in t' substring token")
	assert_lt(interior_check, village_check,
		"INTERIOR_MAP_IDS check must precede the village substring check — interior map_ids contain village tokens (harmonia, vertex, prime, brasston, etc.) and would mis-classify if village ran first")


func test_match_arm_has_interior_case_routing_through_interior_transitions() -> void:
	# Pin the match arm and confirm it calls the lightweight
	# interior transitions, not the dramatic village wipe.
	var src := _read(GAME_LOOP)
	assert_true(src.contains("\"interior\":"),
		"transition match must have an 'interior' arm")
	assert_true(src.contains("_area_interior_transition_in(display_name)"),
		"interior arm must call _area_interior_transition_in — distinct from village wipe")
	assert_true(src.contains("_area_interior_transition_out()"),
		"interior arm must call _area_interior_transition_out — distinct from village wipe-out")


func test_interior_transition_functions_exist() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("func _area_interior_transition_in(location_name: String)"),
		"_area_interior_transition_in must exist and accept the location name")
	assert_true(src.contains("func _area_interior_transition_out()"),
		"_area_interior_transition_out must exist")


func test_interior_transition_no_arriving_prefix() -> void:
	# Interior transitions must NOT use the "Arriving at X..." text —
	# that's a village/town arrival, not a step into a room.
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _area_interior_transition_in")
	assert_gt(idx, -1, "_area_interior_transition_in must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_false(body.contains("Arriving at"),
		"_area_interior_transition_in must NOT use 'Arriving at X...' — that phrasing is for entering a new town")


func test_interior_transition_is_faster_than_village() -> void:
	# Interior transition should be quicker than village (0.5s wipe).
	# Pin specific durations — small enough to feel snappy, distinct
	# enough that someone editing them notices the intent.
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _area_interior_transition_in")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	# 0.20s in-fade, 0.18s out-fade — both well under village's 0.5s.
	assert_true(body.contains("0.20"),
		"_area_interior_transition_in must use ~0.20s fade — quicker than village 0.5s wipe")
