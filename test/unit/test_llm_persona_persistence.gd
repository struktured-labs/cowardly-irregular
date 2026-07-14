extends GutTest

## R5 — Showcase NPC persona survives save → load → village re-spawn.
##
## ROOT CAUSE (regression target): OverworldNPC._setup_persona_data() was ONLY
## invoked from _ready(), gated on `dynamic` at that exact instant. The persona
## overlay (persona text + opening lines + fallback dialogue, loaded from
## data/cutscenes/npc_showcase_personas.json by npc_name) therefore applied
## ONLY when `dynamic = true` was already set BEFORE the node entered the tree.
##
## Any code path that assigned `dynamic`/`persona` AFTER _ready silently dropped
## the overlay — the node stayed dynamic=true but with an EMPTY persona and NO
## opening lines, so the 3 W1 showcase NPCs (Elder Theron / Scholar Milo /
## Guard Boris) reverted to scene defaults after a save → load → re-spawn cycle.
##
## FIX: `dynamic` and `persona` are now setters that re-run _setup_persona_data()
## (idempotently) for post-construction assignments, plus a public
## refresh_persona(). This test pins BOTH the unit-level ordering hazard AND the
## full-scene re-instantiation that a load triggers.
##
## (CLAUDE.md principle #7 — silent failures are worse than crashes; every fixed
## bug gets a runtime test that would have caught it.)


const NPC_SCRIPT_PATH: String = "res://src/exploration/OverworldNPC.gd"
const HARMONIA_TSCN: String = "res://src/maps/villages/HarmoniaVillage.tscn"
const PERSONA_JSON: String = "res://data/cutscenes/npc_showcase_personas.json"

const SHOWCASE_NAMES: Array[String] = [
	"Elder Theron",
	"Scholar Milo",
	"Guard Boris",
]


# ── Helpers ──────────────────────────────────────────────────────────────────

func _collect_npcs(root: Node, out: Array) -> void:
	for child in root.get_children():
		if "dynamic" in child and "persona" in child and "npc_name" in child:
			out.append(child)
		_collect_npcs(child, out)


func _find_by_name(npcs: Array, wanted: String) -> Node:
	for n in npcs:
		if str(n.npc_name) == wanted:
			return n
	return null


# ── Data-path sanity: the JSON the overlay reads is well-formed ───────────────

func test_persona_json_has_all_showcase_entries() -> void:
	# Underlying data path — persona resolution from npc_showcase_personas.json
	# by name must remain correct (this is what _setup_persona_data consumes).
	assert_true(FileAccess.file_exists(PERSONA_JSON), "persona JSON must exist")
	var f := FileAccess.open(PERSONA_JSON, FileAccess.READ)
	assert_not_null(f, "persona JSON must open")
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	assert_true(parsed is Dictionary, "persona JSON must parse to Dictionary")
	if not (parsed is Dictionary):
		return
	var d: Dictionary = parsed
	for name in SHOWCASE_NAMES:
		assert_true(d.has(name), "persona JSON must contain showcase NPC '%s'" % name)
		var entry: Variant = d[name]
		assert_true(entry is Dictionary, "%s entry must be a Dictionary" % name)
		assert_true((entry as Dictionary).has("persona"), "%s must have 'persona'" % name)
		assert_ne(str((entry as Dictionary).get("persona", "")).strip_edges(), "",
			"%s persona must be non-empty" % name)
		assert_true((entry as Dictionary).has("openings"), "%s must have 'openings'" % name)
		assert_gt(((entry as Dictionary).get("openings", []) as Array).size(), 0,
			"%s must have at least one opening line" % name)


# ── Core root-cause guard: dynamic/persona assigned AFTER _ready ──────────────

func test_persona_loads_when_dynamic_set_after_ready() -> void:
	# This is the EXACT ordering that used to silently drop the persona:
	# add_child (→ _ready runs with dynamic=false), THEN flip dynamic=true.
	# Pre-fix: persona stayed "" and openings stayed []. Post-fix: the setter
	# re-runs _setup_persona_data and the overlay attaches.
	var NPC: Script = load(NPC_SCRIPT_PATH)
	assert_not_null(NPC, "OverworldNPC script must load")

	var npc: Node = NPC.new()
	npc.npc_name = "Elder Theron"
	npc.npc_type = "elder"
	# Deliberately DO NOT set dynamic before entering the tree.
	add_child_autofree(npc)
	await get_tree().process_frame

	# Precondition: _ready ran with dynamic=false → no overlay yet.
	assert_eq(str(npc.persona), "", "precondition: persona empty before dynamic flip")

	# Now flip dynamic — the setter must re-hydrate the overlay.
	npc.dynamic = true
	await get_tree().process_frame

	assert_true(bool(npc.dynamic), "npc must be dynamic after flip")
	assert_ne(str(npc.persona).strip_edges(), "",
		"persona MUST be non-empty after dynamic set post-_ready (R5 regression)")
	assert_gt((npc._persona_openings as Array).size(), 0,
		"opening lines MUST hydrate after dynamic set post-_ready (R5 regression)")


func test_persona_loads_when_set_before_ready() -> void:
	# Control: the existing HarmoniaVillage ordering (dynamic before add_child)
	# must keep working — no regression from the setter change.
	var NPC: Script = load(NPC_SCRIPT_PATH)
	var npc: Node = NPC.new()
	npc.npc_name = "Guard Boris"
	npc.npc_type = "guard"
	npc.dynamic = true  # set BEFORE add_child, exactly like HarmoniaVillage
	add_child_autofree(npc)
	await get_tree().process_frame

	assert_ne(str(npc.persona).strip_edges(), "",
		"persona must hydrate on the before-_ready ordering too")
	assert_gt((npc._persona_openings as Array).size(), 0,
		"openings must hydrate on the before-_ready ordering too")


func test_refresh_persona_public_api_is_idempotent() -> void:
	# The explicit refresh hook a save-restore path can call. Calling it twice
	# must not corrupt or duplicate the overlay.
	var NPC: Script = load(NPC_SCRIPT_PATH)
	var npc: Node = NPC.new()
	npc.npc_name = "Scholar Milo"
	npc.npc_type = "villager"
	add_child_autofree(npc)
	await get_tree().process_frame

	npc.dynamic = true
	npc.refresh_persona()
	npc.refresh_persona()
	await get_tree().process_frame

	assert_ne(str(npc.persona).strip_edges(), "", "refresh_persona must populate persona")
	assert_gt((npc._persona_openings as Array).size(), 0, "refresh_persona must populate openings")
	# Idempotent: openings list size matches the JSON entry (3), not 6/9 from
	# repeated appends — _persona_openings is replaced, not appended-to.
	assert_eq((npc._persona_openings as Array).size(), 3,
		"refresh_persona must REPLACE openings, not accumulate them")


# ── Full-scene guard: save → load → village re-spawn keeps all 3 dynamic ──────

func test_showcase_npcs_survive_village_respawn() -> void:
	# A save → load cycle re-instantiates the village scene from scratch (the
	# Continue path: SaveSystem.load_game → MapSystem.load_map, and GameLoop's
	# _start_exploration → HarmoniaVillageRes.instantiate()). We simulate the
	# load by instantiating the scene, freeing it, and instantiating AGAIN —
	# asserting the showcase NPCs come back fully dynamic with persona+openings
	# on the SECOND (post-"load") spawn, not just the first.
	var packed: PackedScene = load(HARMONIA_TSCN)
	assert_not_null(packed, "HarmoniaVillage scene must load")
	if packed == null:
		return

	# --- First spawn (pre-save) ---
	var scene1: Node = packed.instantiate()
	add_child(scene1)
	await get_tree().process_frame
	var npcs1: Array = []
	_collect_npcs(scene1, npcs1)
	_assert_showcase_dynamic(npcs1, "first spawn")

	# Tear down (simulates leaving the map on save/quit).
	scene1.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# --- Second spawn (post-load re-spawn) ---
	var scene2: Node = packed.instantiate()
	add_child_autofree(scene2)
	await get_tree().process_frame
	var npcs2: Array = []
	_collect_npcs(scene2, npcs2)
	_assert_showcase_dynamic(npcs2, "post-load re-spawn")


func _assert_showcase_dynamic(npcs: Array, phase: String) -> void:
	assert_gt(npcs.size(), 0, "[%s] expected NPCs in HarmoniaVillage" % phase)
	for wanted in SHOWCASE_NAMES:
		var npc: Node = _find_by_name(npcs, wanted)
		assert_not_null(npc, "[%s] showcase NPC '%s' must exist" % [phase, wanted])
		if npc == null:
			continue
		assert_true(bool(npc.dynamic),
			"[%s] '%s' must be dynamic=true" % [phase, wanted])
		assert_ne(str(npc.persona).strip_edges(), "",
			"[%s] '%s' must have a non-empty persona" % [phase, wanted])
		assert_gt((npc._persona_openings as Array).size(), 0,
			"[%s] '%s' must have opening lines" % [phase, wanted])
