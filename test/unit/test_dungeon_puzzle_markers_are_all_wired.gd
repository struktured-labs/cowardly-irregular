extends GutTest

## struktured 2026-09-06: "hit a switch or plate ... changes another piece of the terrain, some
## switches can be traps that cause RE. some treasures too" — and 2026-09-07: "the dragon dungeons
## are too shallow. all dungeons are really".
##
## The puzzle vocabulary is authored in TWO places that nothing forces to agree: the marker in a
## floor layout (S/L for switches, a-f for portals) and the wiring in the scene's own
## switch_effects / portal_links. A marker with no wiring is a DEAD PROP — the player walks onto a
## pressure plate, it depresses, and nothing anywhere happens. It cannot error and cannot log,
## because both halves are individually valid. That is the day's defect class in level data.
##
## RESULT WHEN WRITTEN: every dungeon is fully wired — 11 scenes, every S/L reaching an effect and
## every portal char appearing an even number of times. This ships as a guard on a clean sweep, not
## as a finding. It exists so the next authored floor cannot half-land.

const PUZZLE_DUNGEONS := [
	"res://src/maps/dungeons/FireDragonCave.gd",
	"res://src/maps/dungeons/IceDragonCave.gd",
	"res://src/maps/dungeons/LightningDragonCave.gd",
	"res://src/maps/dungeons/ShadowDragonCave.gd",
	"res://src/maps/dungeons/CastleHarmonia.gd",
	"res://src/maps/dungeons/ContrarianDepths.gd",
	"res://src/maps/dungeons/AssemblyCore.gd",
	"res://src/maps/dungeons/NullChamber.gd",
	"res://src/maps/dungeons/RootProcess.gd",
	"res://src/maps/dungeons/SteampunkMechanism.gd",
	"res://src/maps/dungeons/SuburbanUnderground.gd",
]


## Count layout characters and wired switch ids straight out of the source, because these scenes
## build their layouts in _init and instantiating eleven dungeons to read two dictionaries would
## be a slower test that answers the same question.
func _survey(path: String) -> Dictionary:
	var src := FileAccess.get_file_as_string(path)
	var i: int = src.find("floor_layouts = {")
	if i < 0:
		return {}
	var j: int = src.find("\n\t}", i)
	var block: String = src.substr(i, (j - i) if j > i else 4000)
	var switches: int = 0
	var portals: Dictionary = {}
	for line in block.split("\n"):
		if not line.contains('"'):
			continue
		for ch in line:
			if ch == "S" or ch == "L":
				switches += 1
			elif ch in DungeonPuzzleLayer.PORTAL_CHARS:
				portals[ch] = int(portals.get(ch, 0)) + 1
	var wired: int = 0
	var k: int = 0
	while true:
		k = src.find('"sw%d"' % wired, 0)
		if k < 0:
			break
		wired += 1
	return {"switches": switches, "portals": portals, "wired": wired}


func test_every_switch_marker_reaches_an_effect() -> void:
	var dead: Array[String] = []
	var surveyed: int = 0
	for path in PUZZLE_DUNGEONS:
		var s := _survey(path)
		if s.is_empty():
			continue
		surveyed += 1
		if int(s["switches"]) != int(s["wired"]):
			dead.append("%s: %d S/L markers, %d wired" % [path.get_file(), s["switches"], s["wired"]])
	assert_eq(surveyed, PUZZLE_DUNGEONS.size(),
		"CONTROL: every listed dungeon must have been read — a missing floor_layouts silently skips it")
	assert_eq(dead, [] as Array[String],
		"switch markers with no effect — the player stands on a plate and nothing happens: %s" % str(dead))


func test_every_portal_marker_has_a_twin() -> void:
	## A portal char appearing an ODD number of times has an unpaired mouth. The engine can override
	## a lone one via portal_links, so an odd count is only a defect when nothing declares the twin.
	var orphans: Array[String] = []
	for path in PUZZLE_DUNGEONS:
		var s := _survey(path)
		if s.is_empty():
			continue
		var src := FileAccess.get_file_as_string(path)
		var declares_links: bool = src.contains("portal_links")
		for ch in (s["portals"] as Dictionary):
			var n: int = int((s["portals"] as Dictionary)[ch])
			if n % 2 == 1 and not declares_links:
				orphans.append("%s: portal '%s' appears %d time(s), no portal_links" % [path.get_file(), ch, n])
	assert_eq(orphans, [] as Array[String],
		"portals with no twin and no declared link — stepping in goes nowhere: %s" % str(orphans))


func test_the_survey_can_actually_see_markers() -> void:
	## CONTROL. Without this, a reader that returned zero for everything would pass both assertions
	## above — the exact wrong-shape zero that has to be excluded before a clean sweep means anything.
	var warren := _survey("res://src/maps/dungeons/ContrarianDepths.gd")
	assert_gt(int(warren.get("switches", 0)), 0, "the Warren demonstrably has switches; the reader must find them")
	assert_gt(int(warren.get("wired", 0)), 0, "and it demonstrably wires them")
	assert_gt((warren.get("portals", {}) as Dictionary).size(), 0, "and it demonstrably has portals")


func test_the_survey_reports_nothing_for_a_dungeon_without_layouts() -> void:
	# The base class holds no layouts of its own; an empty survey must be empty, not zero-filled,
	# so test_every_switch_marker_reaches_an_effect's CONTROL can tell "skipped" from "clean".
	assert_true(_survey("res://src/maps/dungeons/DragonCave.gd").is_empty(),
		"DragonCave declares floor_layouts as a var, not a literal — it must survey as absent")
