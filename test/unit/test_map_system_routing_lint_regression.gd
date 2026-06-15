extends GutTest

## Source-lint regression: MapSystem._get_map_path() must NOT route any
## map_id to a .gd script path. load_map calls scene.instantiate(),
## which is a PackedScene method — pointing at a GDScript produces a
## silently broken instance (instantiate() raises an error on a
## non-PackedScene Resource, current_map ends up null, all subsequent
## find_child / global_position calls crash). Plus every routed .tscn
## entry must actually exist on disk; a missing-file route is a latent
## silent-failure.
##
## The dead-routing class was real:
##   • Before this fix, 10 entries pointed at .gd scripts (dragon caves,
##     5 .gd-only villages, the Steampunk overworld) — those scenes ARE
##     loaded successfully, but via GameLoop's preloaded Script +
##     Script.new() pattern, not via MapSystem. MapSystem's table was a
##     stale duplicate that would crash if anyone routed through it.
##   • 2 more entries pointed at .tscn files that no longer exist
##     (StarterVillage, Cave).
##
## Tests:
##   • For every map_id explicitly enumerated in the match block,
##     _get_map_path returns a .tscn path that exists on disk.
##   • The match block contains zero references to .gd paths.

const MAP_SYSTEM_PATH := "res://src/maps/MapSystem.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


func _ms() -> Node:
	return get_node_or_null("/root/MapSystem")


# ── Source pin ────────────────────────────────────────────────────────────────

func test_no_gd_paths_in_routing_table() -> void:
	# A .gd return inside _get_map_path is the bug shape: instantiate()
	# fails on a GDScript Resource, breaking the whole map load path.
	var text := _read(MAP_SYSTEM_PATH)
	var idx := text.find("func _get_map_path")
	assert_gt(idx, -1, "_get_map_path must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# Strip comment lines so the teaching doc-comment that calls out the
	# bug shape can mention .gd without tripping its own lint.
	var lines := body.split("\n")
	var bad: PackedStringArray = PackedStringArray()
	for line in lines:
		var ln: String = str(line)
		if ln.strip_edges().begins_with("#"):
			continue
		# Only flag a `return "res://....gd"` style entry.
		if ln.contains("return ") and ln.contains(".gd\""):
			bad.append(ln.strip_edges())
	assert_eq(bad.size(), 0,
		"_get_map_path must NOT route any map_id to a .gd path. Offending:\n%s" % "\n".join(bad))


# ── Behavioural: every routed map_id resolves to an existing .tscn ────────────

func test_routed_map_ids_point_at_existing_files() -> void:
	# Enumerate the explicit map_id cases from the match block and verify
	# each returns a path that ResourceLoader can see. Catches both the
	# .gd routing bug (returns a Script Resource that instantiate() can't
	# use) and the missing-file class (returns a .tscn whose file isn't
	# in the project).
	var ms := _ms()
	if ms == null:
		pending("MapSystem autoload unavailable")
		return
	# These are the IDs the live match block currently enumerates. Adding a
	# new id below MUST come with a new file; the test keeps both honest.
	var routed_ids: Array[String] = [
		"overworld",
		"harmonia_village",
		"whispering_cave",
	]
	for map_id in routed_ids:
		var path: String = ms._get_map_path(map_id)
		assert_true(path.ends_with(".tscn"),
			"routed map_id '%s' must return a .tscn path, got '%s'" % [map_id, path])
		assert_true(ResourceLoader.exists(path),
			"routed map_id '%s' returns a path that doesn't exist: '%s'" % [map_id, path])


func test_wildcard_fallback_returns_tscn_path() -> void:
	# The wildcard branch must still hand back a .tscn path so callers
	# routing an unknown id at least try a sensible default (even if the
	# real layout is villages/* and dungeons/*).
	var ms := _ms()
	if ms == null:
		pending("MapSystem autoload unavailable")
		return
	var path: String = ms._get_map_path("future_map_that_does_not_exist")
	assert_true(path.ends_with(".tscn"),
		"wildcard fallback must return a .tscn path (load_map uses PackedScene.instantiate)")
