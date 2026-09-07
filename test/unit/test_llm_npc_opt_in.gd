extends GutTest

## Wave F — NPC dynamic-opt-in scope guard (bug #6, design doc :157).
##
## Per docs/llm-integration-design.md:157, ONLY 3 showcase NPCs in W1 should
## have dynamic=true: Elder Theron, Scholar Milo, Guard Boris. This test
## instantiates the HarmoniaVillage scene and asserts exactly that — no more,
## no less. Catches accidental retrofit (e.g., a refactor that sets dynamic=true
## on every villager).
##
## The village scene is large (overworld scene tree); we instantiate it via
## the .tscn so the populated _create_npc calls actually run.


const HARMONIA_TSCN: String = "res://src/maps/villages/HarmoniaVillage.tscn"

const EXPECTED_DYNAMIC_NAMES: Array[String] = [
	"Elder Theron",
	"Scholar Milo",
	"Guard Boris",
]


# ── Helpers ──────────────────────────────────────────────────────────────────

func _collect_npcs(root: Node, out: Array) -> void:
	# Walks the subtree collecting OverworldNPC + WanderingNPC instances by class.
	for child in root.get_children():
		var script: Script = child.get_script()
		if script != null:
			var class_str: String = ""
			if "get_global_name" in script:
				class_str = str(script.get_global_name())
			# Soft-check: anything with the dynamic/persona pair we care about.
			if "dynamic" in child and "persona" in child and "npc_name" in child:
				out.append(child)
		_collect_npcs(child, out)


# ── Tests ────────────────────────────────────────────────────────────────────

func test_harmonia_scene_loads() -> void:
	assert_true(FileAccess.file_exists(HARMONIA_TSCN), "HarmoniaVillage.tscn must exist")


func test_only_three_npcs_are_dynamic() -> void:
	var packed: PackedScene = load(HARMONIA_TSCN)
	assert_not_null(packed, "HarmoniaVillage scene must load")
	if packed == null:
		return
	var scene: Node = packed.instantiate()
	add_child_autofree(scene)
	# The village populates NPCs in _ready(). Wait a frame so deferred
	# children are added.
	await get_tree().process_frame

	var npcs: Array = []
	_collect_npcs(scene, npcs)
	assert_gt(npcs.size(), 0, "Expected at least some NPCs in HarmoniaVillage")

	var dynamic_names: Array[String] = []
	var non_dynamic_names: Array[String] = []
	for npc in npcs:
		var name: String = str(npc.npc_name)
		if bool(npc.dynamic):
			dynamic_names.append(name)
		else:
			non_dynamic_names.append(name)

	# Exactly 3 dynamic NPCs — the showcase set.
	assert_eq(dynamic_names.size(), EXPECTED_DYNAMIC_NAMES.size(),
		"Expected exactly %d dynamic NPCs (showcase set); got %s" % [
			EXPECTED_DYNAMIC_NAMES.size(), str(dynamic_names)
		])
	for expected_name in EXPECTED_DYNAMIC_NAMES:
		assert_true(dynamic_names.has(expected_name),
			"Expected showcase NPC '%s' to have dynamic=true; current dynamic set: %s" % [
				expected_name, str(dynamic_names)
			])

	# Defensive: every dynamic NPC must have a non-empty persona.
	for npc in npcs:
		if bool(npc.dynamic):
			assert_ne(str(npc.persona).strip_edges(), "",
				"Dynamic NPC '%s' must have a non-empty persona" % npc.npc_name)
