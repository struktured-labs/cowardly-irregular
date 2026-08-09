extends GutTest

## Regression: every avatar surface must resolve portraits through the world-aware resolver.
##
## struktured, 2026-08-09: "dont see the sprite updates for avatars in each overworld".
## The world-dressed portraits shipped and the cutscene path used them — but CharacterPortrait
## built "res://assets/sprites/portraits/%s.png" itself, and that widget feeds the overworld
## menu, battle UI, save screen, shop and the autobattle editor. Six surfaces, all medieval,
## while the cutscene path was correct. Fixing one consumer and never asking who else reads
## the same store is the defect this file exists for.

const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const RESOLVER := "portrait_path"
const PORTRAIT_DIR := "res://assets/sprites/portraits"


func _gd_files(root: String, out: Array) -> void:
	var d = DirAccess.open(root)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append("%s/%s" % [root, f])
	for sub in d.get_directories():
		_gd_files("%s/%s" % [root, sub], out)


func test_no_surface_BUILDS_a_portrait_path_itself() -> void:
	# Derived from source, not a hand-list — a seventh surface must not need this file edited
	var files: Array = []
	_gd_files("res://src", files)
	assert_gt(files.size(), 50, "sanity: src/ should have plenty of .gd files to scan")
	var builders: Array = []
	for path in files:
		if path.ends_with("HybridSpriteLoader.gd"):
			continue
		var src := FileAccess.get_file_as_string(path)
		for line in src.split("\n"):
			var t: String = str(line).strip_edges()
			if t.begins_with("#"):
				continue
			# A path assembled at runtime — a literal registry entry is fine, it is a
			# declared mapping the resolver can be pointed at, not a hidden second rule.
			if t.find("sprites/portraits/%s") > -1 or t.find("sprites/portraits/\" +") > -1:
				builders.append("%s: %s" % [str(path).get_file(), t])
	builders.sort()
	assert_eq(builders, [],
		("portrait path(s) built by hand instead of HybridSpriteLoader.%s() — these serve " +
		"MEDIEVAL art in every world and no test of the cutscene path can see it: %s")
		% [RESOLVER, builders])


func test_the_resolver_returns_the_WORLD_variant_when_it_exists() -> void:
	# Pins the VALUE. A resolver that exists and returns base art everywhere would pass
	# every structural check above while showing the player exactly what he reported.
	var gs := get_node_or_null("/root/GameState")
	assert_not_null(gs, "GameState required — run via tools/run_tests.sh")
	if gs == null:
		return
	var restore: int = int(gs.current_world)
	var checked := 0
	var unchanged: Array = []
	for job in ["fighter", "cleric", "mage", "rogue", "bard"]:
		gs.current_world = 1
		var base: String = Loader.portrait_path(job)
		for w in range(2, 7):
			var suffix: String = Loader.WORLD_SUFFIXES[w - 1]
			if not FileAccess.file_exists("%s/%s_%s.png" % [PORTRAIT_DIR, job, suffix]):
				continue
			gs.current_world = w
			checked += 1
			if Loader.portrait_path(job) == base:
				unchanged.append("%s/%s" % [job, suffix])
	gs.current_world = restore
	assert_true(checked > 0,
		"asserted nothing — no world portrait resolved, so this test could not fail")
	unchanged.sort()
	assert_eq(unchanged, [],
		"resolver served the medieval portrait where world art exists: %s" % [unchanged])
	assert_eq(int(gs.current_world), restore, "current_world must be restored")


func test_a_missing_variant_falls_back_to_the_painted_ART() -> void:
	# The safety half: the resolver must never invent a path that does not exist
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	var restore: int = int(gs.current_world)
	var missing: Array = []
	for w in range(1, 7):
		gs.current_world = w
		for job in ["fighter", "cleric", "mage", "rogue", "bard"]:
			if not ResourceLoader.exists(Loader.portrait_path(job)):
				missing.append("%s in world %d" % [job, w])
	gs.current_world = restore
	missing.sort()
	assert_eq(missing, [], "resolver returned a path that does not load: %s" % [missing])
