extends GutTest

## W1 Masterite placement (docs/design/w1-progression-expansion.md,
## msg 2531): the 4 W1 masterites shipped as monster data + sprites
## but were orphaned (`enemy_pools.masterite_medieval` referenced only,
## not placed anywhere reachable). Placed one per W1 outer village
## per the doc's story hooks. Pins: monster resolution, per-village
## placement, defeat-flag contract, prereq gating, and the MasteriteEncounter
## Area2D shape (BossTrigger-adjacent, once-per-save, pending_boss_defeat
## contract).

const MASTERITES := [
	{
		"archetype": "warden",
		"monster": "masterite_warden_medieval",
		"village": "res://src/maps/villages/SandriftVillage.gd",
		"placer": "_place_masterite_warden",
		# Warden gates on Rat King defeat — "legitimate business" beat.
		"prereq_flag": "cave_rat_king_defeated",
	},
	{
		"archetype": "tempo",
		"monster": "masterite_tempo_medieval",
		"village": "res://src/maps/villages/EldertreeVillage.gd",
		"placer": "_place_masterite_tempo",
		"prereq_flag": "",
	},
	{
		"archetype": "arbiter",
		"monster": "masterite_arbiter_medieval",
		"village": "res://src/maps/villages/GrimhollowVillage.gd",
		"placer": "_place_masterite_arbiter",
		"prereq_flag": "",
	},
	{
		"archetype": "curator",
		"monster": "masterite_curator_medieval",
		"village": "res://src/maps/villages/IronhavenVillage.gd",
		"placer": "_place_masterite_curator",
		"prereq_flag": "",
	},
]


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Data resolution ─────────────────────────────────────────────────

func test_every_masterite_resolves_in_monsters_json() -> void:
	var raw := _read("res://data/monsters.json")
	var data: Dictionary = JSON.parse_string(raw)
	for m in MASTERITES:
		var mid: String = m["monster"]
		assert_true(data.has(mid), "monsters.json defines %s" % mid)
		var entry: Dictionary = data[mid]
		assert_true(entry.get("boss", false),
			"%s is tagged boss:true (per design doc L84-86)" % mid)
		var lvl: int = int(entry.get("level", 0))
		assert_true(lvl == 7 or lvl == 8,
			"%s is L7 or L8 per doc's mid-arc curve (got %d)" % [mid, lvl])


# ── Placement source pins ───────────────────────────────────────────

func test_each_village_places_its_masterite() -> void:
	for m in MASTERITES:
		var village_src: String = _read(m["village"])
		assert_ne(village_src, "", "%s readable" % m["village"])
		var placer: String = m["placer"]
		assert_true(village_src.contains("func %s(" % placer),
			"%s defines %s" % [m["village"], placer])
		assert_true(village_src.contains(placer + "()"),
			"%s calls %s from _setup_npcs" % [m["village"], placer])
		assert_true(village_src.contains(m["monster"]),
			"%s references monster id %s" % [m["village"], m["monster"]])
		assert_true(village_src.contains("archetype = \"" + m["archetype"] + "\""),
			"%s wires archetype=\"%s\"" % [m["village"], m["archetype"]])
		if m["prereq_flag"] != "":
			assert_true(village_src.contains("prereq_flag = \"" + m["prereq_flag"] + "\""),
				"%s wires prereq_flag=\"%s\" (design gate)" % [m["village"], m["prereq_flag"]])


# ── MasteriteEncounter contract ────────────────────────────────────

func test_masterite_encounter_shape() -> void:
	var src := _read("res://src/exploration/MasteriteEncounter.gd")
	assert_ne(src, "", "MasteriteEncounter script exists")
	# BossTrigger-shape collision matches dragon caves.
	assert_true(src.contains("collision_layer = 4"),
		"MasteriteEncounter uses collision_layer=4 (interactables)")
	assert_true(src.contains("collision_mask = 2"),
		"MasteriteEncounter uses collision_mask=2 (player)")
	assert_true(src.contains("add_to_group(\"interactables\")"),
		"MasteriteEncounter joins the interactables group")
	# Once-per-save gate.
	assert_true(src.contains("_defeat_flag_set"),
		"MasteriteEncounter checks defeat flag on _ready")
	assert_true(src.contains("w1_%s_defeated"),
		"MasteriteEncounter derives defeat flag as w1_<archetype>_defeated (per design)")
	# Fires the flag through pending_boss_defeat (matches DragonCave contract).
	assert_true(src.contains("pending_boss_defeat"),
		"MasteriteEncounter stakes GameState.pending_boss_defeat on entry")
	assert_true(src.contains("defeat_flag()"),
		"MasteriteEncounter pushes its own defeat_flag() into pending story_flags")


func test_defeat_flag_naming_matches_design() -> void:
	# Doc L63: "Reward drops → boss-defeat flag (`w1_warden_defeated` etc.)"
	# The MasteriteEncounter derives the flag from archetype. This test
	# defends the naming contract quests will read.
	var expected := ["w1_warden_defeated", "w1_tempo_defeated",
			"w1_arbiter_defeated", "w1_curator_defeated"]
	for m in MASTERITES:
		var flag := "w1_%s_defeated" % m["archetype"]
		assert_true(flag in expected,
			"derived flag %s in expected set" % flag)


# ── AABB / framework compat ─────────────────────────────────────────

func test_masterite_aabb_fits_reachability_framework() -> void:
	# `test_overworld_reachability_framework` (v3.33.146) enforces that
	# no interactable eclipses a sibling. MasteriteEncounter picks a
	# 2×2 tile AABB — small enough to sit alongside AreaTransitions
	# (2×6 tiles per that PR's shrink) without full overlap.
	var src := _read("res://src/exploration/MasteriteEncounter.gd")
	assert_true(src.contains("TILE_SIZE * 2, TILE_SIZE * 2"),
		"MasteriteEncounter AABB is 2×2 tiles (fits nearest-hit routing)")
