extends GutTest

## tick 69 regression: every npc_type the interior NPCs use must have
## a real arm in OverworldNPC._get_clothes_color, not just fall
## through to the random-villager default.
##
## Original silent gap (tick 34-66): I assigned npc_type='scholar' and
## npc_type='merchant' to 9 of the 12 interior NPCs (Sister Concord,
## Cantor Vell, Greenleaf, Mire, Clavis, Vetch, SUDO-1, The Witness,
## Senga, Crusher Pete). Neither type had a case arm in
## _get_clothes_color, so they rendered as randomly-colored villagers
## instead of types with intentional palettes.
##
## OverworldNPC's own docstring listed both as valid types — the
## clothes_color arms just hadn't been added.

const OVERWORLD_NPC := "res://src/exploration/OverworldNPC.gd"


## Every npc_type the 12 interior NPCs use.
const INTERIOR_NPC_TYPES: Array[String] = ["scholar", "guard", "merchant"]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_get_clothes_color_handles_every_interior_npc_type() -> void:
	# Find the _get_clothes_color match arms and verify each interior
	# type has an explicit `"type":` case.
	var src := _read(OVERWORLD_NPC)
	var idx := src.find("func _get_clothes_color")
	assert_gt(idx, -1, "_get_clothes_color must exist")
	var next_fn := src.find("\nfunc ", idx + 1)
	var body := src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	for npc_type in INTERIOR_NPC_TYPES:
		var quoted: String = "\"" + npc_type + "\":"
		assert_true(body.contains(quoted),
			"_get_clothes_color must have an arm for '%s' — interior NPCs use this type, falling through to default loses the intentional palette" % npc_type)


func test_scholar_and_merchant_have_distinct_colors() -> void:
	# Pin literally: the new arms must NOT just return the same color
	# as another existing arm. If they did, the distinction would be
	# nominal only.
	var src := _read(OVERWORLD_NPC)
	# Scholar's deep teal-grey
	assert_true(src.contains("Color(0.30, 0.40, 0.45)"),
		"scholar arm must use the teal-grey palette (0.30, 0.40, 0.45) — distinguishes from elder's purple")
	# Merchant's earthy mustard
	assert_true(src.contains("Color(0.60, 0.45, 0.20)"),
		"merchant arm must use the mustard palette (0.60, 0.45, 0.20) — distinguishes from innkeeper's brown and bard's tan")
