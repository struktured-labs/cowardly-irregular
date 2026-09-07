extends GutTest

## tick 71 regression: every npc_type used by interior NPCs must
## resolve to (a) a non-narrator THEME_COLORS arm and (b) either a
## PORTRAIT_SPRITES file or a procedural draw arm — otherwise dialogue
## with that NPC falls back to the generic narrator theme/portrait.
##
## Original silent gap (caught in tick 71 audit): Warden Trygg
## (Frosthold) and Drogal (Ironhaven Watchtower) both use
## npc_type="guard". OverworldNPC passes npc_type as both "theme" and
## "portrait" through NPCDialogue → CutsceneDialogue. The guard arm
## existed in NEITHER CHARACTER_THEMES nor PORTRAIT_SPRITES, so:
##   - theme = narrator (generic blue) instead of military steel
##   - portrait = narrator (generic) instead of brigadier
## Both NPCs rendered visually indistinct from a random villager NPC.
##
## Tick 71 added a "guard" → brigadier.png alias (interim reuse of an
## existing asset). v3.33.200 fold repointed "guard" → guard.png once
## the real guard portrait landed via cowir-sprites Batch C.

const CUTSCENE_DIALOGUE := "res://src/cutscene/CutsceneDialogue.gd"
const GUARD_SPRITE := "res://assets/sprites/portraits/npcs/guard.png"

## Every npc_type used by an interior NPC.
const INTERIOR_NPC_TYPES: Array[String] = ["scholar", "merchant", "guard"]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_every_interior_npc_type_has_theme_colors_arm() -> void:
	# Look up the CHARACTER_THEMES const body and assert each
	# npc_type appears as a key.
	var src := _read(CUTSCENE_DIALOGUE)
	# Anchor on the const declaration to scope the search.
	var idx: int = src.find("CHARACTER_THEMES")
	assert_gt(idx, -1, "CHARACTER_THEMES const must exist")
	# Search forward from that point for each type.
	var scope: String = src.substr(idx)
	for npc_type in INTERIOR_NPC_TYPES:
		var key: String = "\"" + npc_type + "\":"
		assert_true(scope.contains(key),
			"CHARACTER_THEMES must have a '%s' arm — otherwise interior NPCs of that type render with narrator fallback theme" % npc_type)


func test_guard_theme_distinct_from_narrator() -> void:
	# Specifically pin the new guard palette so a future rename doesn't
	# silently revert it to a generic color.
	var src := _read(CUTSCENE_DIALOGUE)
	assert_true(src.contains("\"guard\": {"),
		"guard CHARACTER_THEMES arm must exist as an opening dict literal")
	# Steel-blue palette — distinct from elder (warm gold) and scholar (teal).
	assert_true(src.contains("Color(0.55, 0.62, 0.72)"),
		"guard arm must use the steel-blue border (0.55, 0.62, 0.72) — military authority palette, distinct from scholar's teal")


func test_guard_portrait_wired_to_guard_sprite() -> void:
	# PORTRAIT_SPRITES must have "guard" → guard.png — the bespoke
	# guard portrait shipped in Batch C (cowir-sprites) replaces the
	# earlier brigadier.png alias so guard NPCs (Trygg, Drogal) get a
	# real portrait instead of a repurposed sheet crop. (The interim
	# repoint-before-art attempt was correctly caught by the old pin.)
	var src := _read(CUTSCENE_DIALOGUE)
	assert_true(src.contains("\"guard\": \"res://assets/sprites/portraits/npcs/guard.png\""),
		"PORTRAIT_SPRITES must wire 'guard' to guard.png — bespoke portrait from Batch C, not the brigadier.png interim alias")
	# Sanity: the wired file must actually exist on disk.
	assert_true(FileAccess.file_exists(GUARD_SPRITE),
		"guard.png must exist on disk — the guard portrait wire depends on it")


func test_guard_procedural_fallback_arm_exists() -> void:
	# Defensive: if PORTRAIT_SPRITES sprite is ever missing, the
	# procedural match arm must still draw SOMETHING — not fall
	# through to narrator (which would erase visual identity).
	var src := _read(CUTSCENE_DIALOGUE)
	assert_true(src.contains("\"guard\", \"brigadier\":"),
		"procedural _create_portrait match must have a 'guard'/'brigadier' arm — defensive fallback if PORTRAIT_SPRITES sprite is missing")


func test_existing_scholar_and_merchant_arms_still_present() -> void:
	# Negative-side check: scholar and merchant arms (added before
	# this tick) must not be removed by accident. The interior NPCs
	# depend on them too.
	var src := _read(CUTSCENE_DIALOGUE)
	# THEME_COLORS arms.
	assert_true(src.contains("\"scholar\": {"),
		"scholar CHARACTER_THEMES arm must remain — 8 interior NPCs depend on it")
	assert_true(src.contains("\"merchant\": {"),
		"merchant CHARACTER_THEMES arm must remain — Senga and Crusher Pete depend on it")
	# Procedural fallback covers merchant via the shared shopkeeper arm.
	# 2026-07-16 (scout round 3): villager joined this arm — 36 uses of
	# `portrait: "villager"` were falling through to narrator. Both merchant
	# and villager are now covered by the same procedural draw.
	assert_true(src.contains("\"shopkeeper\", \"merchant\", \"villager\":"),
		"procedural _create_portrait shared arm must remain — merchant, shopkeeper, and villager all depend on this fallback")
