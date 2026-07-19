extends GutTest

## Archetype sheet top-row density ratchet (struktured msg 2826).
##
## Diagnosis: OverworldScene Lost Pilgrim (traveler) reported "head cut
## off when walking UP." Not a Rect2i math bug in _try_load_archetype
## (I verified — row=3 gives Rect2i(0, 96, 32, 32), exact). Not a
## direction-derivation bug (up = _current_dir=3, sheet row 3, correct).
## The root cause is ART: two sheets draw their up-facing (row 3) with
## the head/hood filling the very top row of the 32-cell:
##
##   traveler.png row 3: 27/32 opaque pixels at cell y+0
##   monk.png     row 3: 22/32 opaque pixels at cell y+0
##   typical archetypes: 0-14 opaque pixels at cell y+0
##
## At 3× billboard scale near the Mode 7 horizon (which up-walking
## triggers because the NPC moves toward the horizon in screen space),
## that wide top slab lands near the viewport top and gets clipped.
##
## Fix path is TWO-lane:
##   1. cowir-sprites reauthors the offender rows with proper top margin
##      (2-4 px of transparent cell y+0 like other archetypes).
##   2. WanderingNPC applies a small runtime Y offset to the sprite when
##      it's showing a heavy-top row (belt-and-suspenders, cheap).
##
## This ratchet names the current offenders + prevents future sheets
## from drifting into the same shape. Once the art is fixed, tighten
## KNOWN_HEAVY_TOP down or set it to []; the general threshold catches
## any new sheet that grows a heavy-top row.

const NPCS_DIR := "res://assets/sprites/npcs"
const FRAME_W: int = 32
const FRAME_H: int = 32

## Currently-known heavy-top offenders — reauthor these in the sprite lane.
## Empty when art fixes land.
const KNOWN_HEAVY_TOP: PackedStringArray = []  # 2026-07-18: traveler/monk fixed by cowir-sprites 3ec923b1 — the workaround at WanderingNPC._apply_uprow_offset is now dormant per its density-≤18 gate but retained as a general safety net for future ≥18 sheets

## The threshold below which a sheet's up-facing row is considered
## healthy. Typical archetypes: 0-14. Traveler is 27, monk 22.
const HEAVY_TOP_DENSITY: int = 18


func _sheet_row3_top_density(sheet_name: String) -> int:
	var path := "%s/%s/overworld.png" % [NPCS_DIR, sheet_name]
	if not ResourceLoader.exists(path):
		return -1
	var tex = load(path) as Texture2D
	if tex == null:
		return -1
	var img: Image = tex.get_image()
	if img == null or img.get_width() < 128 or img.get_height() < 128:
		return -1
	var y := 3 * FRAME_H  # row 3 = up-facing, cell y+0
	var count := 0
	for x in range(FRAME_W):
		if img.get_pixel(x, y).a > 0.5:
			count += 1
	return count


## Every listed offender must still exceed the threshold — if a sprite
## fix lands, the tightening step is to remove that name from KNOWN_HEAVY_TOP.
func test_known_heavy_top_offenders_still_offend() -> void:
	for sheet in KNOWN_HEAVY_TOP:
		var d := _sheet_row3_top_density(sheet)
		assert_ne(d, -1, "sheet %s must exist to be tested" % sheet)
		if d < 0:
			continue
		assert_gt(d, HEAVY_TOP_DENSITY,
			"%s is in KNOWN_HEAVY_TOP but row 3 top density is %d (≤ threshold %d) — remove it from the list" % [
				sheet, d, HEAVY_TOP_DENSITY])


## Every OTHER sheet must have a healthy row-3 top density. A new sheet
## drifting above threshold is a regression the art review should catch
## before merge — this ratchet enforces it.
func test_no_unnamed_sheet_regresses_to_heavy_top() -> void:
	var dir := DirAccess.open(NPCS_DIR)
	assert_not_null(dir, "npcs sprite dir readable")
	var offenders: Array = []
	for entry in dir.get_directories():
		if entry in KNOWN_HEAVY_TOP:
			continue
		var d := _sheet_row3_top_density(entry)
		if d < 0:
			continue
		if d > HEAVY_TOP_DENSITY:
			offenders.append("%s row 3 top density=%d > %d" % [
				entry, d, HEAVY_TOP_DENSITY])
	assert_eq(offenders.size(), 0,
		"new heavy-top sheet(s) — either fix the art or add to KNOWN_HEAVY_TOP with a bug ref:\n  %s" % [
			"\n  ".join(offenders)])


## WanderingNPC.gd must scan each row's top density at sheet load AND
## apply an offset at frame-swap time. Source-pin so a refactor can't
## silently drop the workaround while the art is still uncorrected.
func test_wandering_npc_scans_and_offsets_heavy_top() -> void:
	var src := FileAccess.get_file_as_string("res://src/exploration/WanderingNPC.gd")
	assert_true(src.contains("_archetype_row_top_density"),
		"WanderingNPC caches per-row top density at sheet load")
	assert_true(src.contains("HEAVY_TOP_DENSITY"),
		"threshold constant declared")
	assert_true(src.contains("HEAVY_TOP_SPRITE_Y_OFFSET"),
		"offset constant declared")
	# The offset must be applied inside _update_archetype_frame so it
	# tracks direction changes, not once at load.
	var fn_idx := src.find("func _update_archetype_frame")
	assert_gt(fn_idx, 0, "_update_archetype_frame present")
	var next_fn := src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_archetype_row_top_density"),
		"heavy-top check runs in _update_archetype_frame (per-direction)")
	assert_true(body.contains("HEAVY_TOP_SPRITE_Y_OFFSET"),
		"offset applied when heavy row is active")
