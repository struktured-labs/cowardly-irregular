extends GutTest

## struktured 2026-08-22, mid-playtest: "I see proc gen characters still in some villages.
## NO PROC GEN CHARS".
##
## WanderingNPC falls to the PROCEDURAL drawer whenever `sprite_archetype` is empty — its own
## docstring says so ("If empty, the NPC uses procedural"). Five of the six overworlds created
## their wanderers with a `sprite_color` and no archetype at all, so W2-W6 shipped hand-drawn
## blobs walking around. OverworldNPC never had this problem: it resolves every npc_type through
## NPC_TYPE_TO_ARCHETYPE (with name-hash pairs for elder/villager), and all of those land on
## registered sheets.
##
## Both arms assert a RELATIONSHIP rather than a list of names: every wanderer must carry an
## archetype, and every archetype anyone uses must resolve to a sheet that exists. Adding a
## sixth wanderer or renaming an archetype stays green; shipping a procedural one reds.

const MANIFEST := "res://data/sprite_manifest.json"
const OVERWORLD_FILES := [
	"res://src/exploration/OverworldScene.gd",
	"res://src/exploration/SuburbanOverworld.gd",
	"res://src/exploration/SteampunkOverworld.gd",
	"res://src/exploration/IndustrialOverworld.gd",
	"res://src/exploration/FuturisticOverworld.gd",
	"res://src/exploration/AbstractOverworld.gd",
]


func _sheets() -> Dictionary:
	var raw = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return raw.get("overworld_npc_sheets", {}) if raw is Dictionary else {}


func test_the_sheet_registry_is_readable() -> void:
	# CONTROL first: every assertion below is vacuous if the manifest doesn't parse.
	var s := _sheets()
	assert_gt(s.size(), 10, "overworld_npc_sheets must load — got %d" % s.size())
	assert_true(s.has("traveler"), "a known-present sheet resolves, so absence below means something")
	assert_false(s.has("definitely_not_a_sheet"), "a fabricated name is absent, so membership discriminates")


func test_every_overworld_that_spawns_wanderers_assigns_an_archetype() -> void:
	# The defect was structural: `WanderingNPC.new()` followed by npc_name/dialogue/sprite_color
	# and no archetype. Any file that constructs one must also set sprite_archetype.
	var offenders: Array = []
	var constructing := 0
	for path in OVERWORLD_FILES:
		var src := FileAccess.get_file_as_string(path)
		assert_gt(src.length(), 500, "CONTROL: %s is readable" % path)
		if not src.contains("WanderingNPC.new()"):
			continue
		constructing += 1
		if not src.contains("sprite_archetype"):
			offenders.append("%s constructs WanderingNPC but never sets sprite_archetype" % path.get_file())
	assert_gt(constructing, 4, "CONTROL: found %d overworlds spawning wanderers — a low count means the scan broke" % constructing)
	assert_eq(offenders.size(), 0, "procedural wanderers:\n  %s" % "\n  ".join(offenders))


func test_every_archetype_named_in_overworld_data_has_a_real_sheet() -> void:
	# A typo'd archetype is WORSE than an empty one: it silently falls back to procedural with
	# no indication anything is wrong. This is the arm that catches that.
	var sheets := _sheets()
	var re := RegEx.create_from_string('"archetype"\\s*:\\s*"([a-z_]+)"')
	var named := 0
	var bad: Array = []
	for path in OVERWORLD_FILES:
		var src := FileAccess.get_file_as_string(path)
		for m in re.search_all(src):
			named += 1
			var a := m.get_string(1)
			if not sheets.has(a):
				bad.append("%s: archetype '%s' has no sheet — renders PROCEDURAL" % [path.get_file(), a])
	assert_gt(named, 5, "CONTROL: parsed %d archetype declarations — zero would pass this test for free" % named)
	assert_eq(bad.size(), 0, "archetypes with no sheet:\n  %s" % "\n  ".join(bad))


func test_village_npc_types_all_resolve_to_a_sheet() -> void:
	# OverworldNPC was already clean and must stay that way: every npc_type a village passes
	# must reach a registered sheet, either directly or through a name-hash pair.
	var sheets := _sheets()
	var npc_src := FileAccess.get_file_as_string("res://src/exploration/OverworldNPC.gd")
	var start := npc_src.find("NPC_TYPE_TO_ARCHETYPE")
	assert_gt(start, -1, "CONTROL: the mapping table exists")
	var table := npc_src.substr(start, npc_src.find("\n}", start) - start)
	var mapping := {}
	for m in RegEx.create_from_string('"([a-z_]+)"\\s*:\\s*"([a-z_]*)"').search_all(table):
		mapping[m.get_string(1)] = m.get_string(2)
	assert_gt(mapping.size(), 10, "CONTROL: parsed %d npc_type mappings" % mapping.size())

	# The hash-pair fallbacks the resolver uses when a mapping is deliberately blank
	for pair_member in ["young_man", "young_woman", "old_man", "old_woman", "noble", "noblewoman"]:
		assert_true(sheets.has(pair_member),
			"name-hash fallback '%s' must have a sheet — a blank mapping lands here" % pair_member)

	var dir := DirAccess.open("res://src/maps/villages")
	assert_not_null(dir, "villages dir readable")
	var type_re := RegEx.create_from_string('_create_npc\\([^,]+,\\s*"([a-z_]+)"')
	var used := {}
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		for m in type_re.search_all(FileAccess.get_file_as_string("res://src/maps/villages/" + f)):
			used[m.get_string(1)] = f
	assert_gt(used.size(), 8, "CONTROL: found %d distinct npc_types across the villages" % used.size())
	var unresolved: Array = []
	for t in used:
		if not mapping.has(t):
			unresolved.append("%s (in %s): npc_type is not in NPC_TYPE_TO_ARCHETYPE" % [t, used[t]])
			continue
		var a: String = mapping[t]
		if a != "" and not sheets.has(a):
			unresolved.append("%s (in %s) -> '%s' has no sheet" % [t, used[t], a])
	assert_eq(unresolved.size(), 0, "village NPCs that would render procedurally:\n  %s" % "\n  ".join(unresolved))
