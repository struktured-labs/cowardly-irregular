extends GutTest

## Mode 7 terrain-vs-player displacement (struktured screenshot, msg 2830:
## standing ~4 tiles inside rendered water, unblocked).
##
## MEASURED DIAGNOSIS — not a source-guess. cowir-main listed three candidate
## causes; the real one is arithmetic and falls out of the shader:
##
##   mode7.gdshader:  source_v = ground_y + near_scale * ln(uv.y - horizon)
##
## The shader is a post-process. Terrain is rendered flat, THEN warped. The
## player is NOT in that texture — Mode7Overlay draws them on a separate
## overlay at a fixed screen row (player_screen_pos.y = viewport * 0.75).
## So at the player's drawn row the shader samples source row
## `ground_y + near_scale*ln(0.75)` = 0.3618 → 260.5 px, while the player's
## own body renders at the camera centre, 380.0 px. The terrain pixels under
## the player's feet therefore belong to tiles ~119.5 source-px NORTH of the
## player, or 140.6 WORLD px after the 0.85 Mode 7 camera zoom — 4.39 tiles.
## That is struktured's "4 tiles inside the water," predicted to the tile.
##
## THE KEY STRUCTURAL POINT (this is what makes a constant fix legitimate):
## the log warp is non-linear, so a fixed offset is normally wrong — it can
## only be correct at one depth. But the player is SCREEN-LOCKED at row 0.75
## and never leaves it, so the displacement *at the player* is the same
## number at every position on every map. It is a global constant, not a
## per-depth curve. Verified below across all six world presets.
##
## TileMap physics is unwarped, so colliders sit at logical tile positions
## while the pixels have moved — hence walking visually-deep into water
## while still physically on land.
##
## This file pins the measurement. It does NOT fix the bug: the fix
## interacts with InteractGeometry.MODE7_TRIGGER_Y_OFFSET (cowir-main's
## contract — see test_mode7_trigger_offset_is_under_compensated below),
## so the correction is theirs to rule on.

const MODE7 := "res://src/exploration/Mode7Overlay.gd"
const TILE := 32.0

## Mode 7 render constants, mirrored from the live call sites. If any of
## these move, the displacement moves with them and this file must be
## re-measured — that is the point of pinning them.
const VIEWPORT_H := 720.0        # project.godot window/size/viewport_height
const MODE7_ZOOM := 0.85         # Mode7Overlay.apply_camera (mode7 branch)
const MODE7_CAM_OFFSET_Y := -20.0
const PLAYER_SCREEN_V := 0.75    # Mode7Overlay.player_screen_pos = h * 0.75

## Measured 2026-07-25 against the live overlay, all six world presets.
const MEASURED_DISPLACEMENT_WORLD_PX := 140.6
const MEASURED_DISPLACEMENT_TILES := 4.39
const MEASURE_TOLERANCE_PX := 1.0


func _displacement_world_px(near_scale: float, ground_y: float, horizon: float) -> float:
	var source_v: float = ground_y + near_scale * log(PLAYER_SCREEN_V - horizon)
	var source_px: float = source_v * VIEWPORT_H
	var player_source_px: float = VIEWPORT_H / 2.0 - MODE7_CAM_OFFSET_Y
	return (player_source_px - source_px) / MODE7_ZOOM


## The headline number. If this drifts, either the shader math or the
## camera setup changed and the water bug's magnitude changed with it.
func test_measured_displacement_matches_the_screenshot() -> void:
	var overlay = load(MODE7).new()
	autofree(overlay)
	var d := _displacement_world_px(overlay.near_scale, overlay.ground_y, overlay.horizon)
	assert_almost_eq(d, MEASURED_DISPLACEMENT_WORLD_PX, MEASURE_TOLERANCE_PX,
		"Mode 7 terrain sits %.1f world px from the player's drawn feet" % d)
	assert_almost_eq(d / TILE, MEASURED_DISPLACEMENT_TILES, 0.05,
		"displacement in tiles — struktured observed ~4, measured %.2f" % (d / TILE))


## The displacement must be world-INDEPENDENT. Presets override curvature
## and fog, never near_scale/ground_y — so one constant covers every map.
## If a future preset overrides those, this fails and the fix needs to
## become per-world instead of global.
func test_displacement_is_uniform_across_all_world_presets() -> void:
	var overlay = load(MODE7).new()
	autofree(overlay)
	if not overlay.has_method("apply_world_preset"):
		pass_test("no per-world presets to check")
		return
	var seen: Array = []
	for world in ["medieval", "suburban", "steampunk", "industrial", "digital", "void"]:
		overlay.apply_world_preset(world)
		var d := _displacement_world_px(overlay.near_scale, overlay.ground_y, overlay.horizon)
		seen.append(d)
		assert_almost_eq(d, MEASURED_DISPLACEMENT_WORLD_PX, MEASURE_TOLERANCE_PX,
			"%s preset displacement %.1f — a preset overriding near_scale/ground_y would make the fix per-world" % [world, d])
	assert_eq(seen.size(), 6, "all six presets measured")


## The player being screen-locked is WHY one constant can be correct
## against a logarithmic warp. If the player ever becomes free-moving in
## screen space, the constant-offset approach dies and this must be
## revisited — so pin the anchor.
func test_player_is_screen_locked_which_is_what_makes_a_constant_valid() -> void:
	var src := FileAccess.get_file_as_string(MODE7)
	assert_true(src.contains("player_screen_pos"),
		"player is drawn at a fixed screen anchor")
	assert_true(src.contains("viewport_height * 0.75"),
		"anchor is 75%% down the screen — the value the measurement assumes")


## CROSS-SURFACE FINDING (cowir-main's contract, reported not changed):
## MODE7_TRIGGER_Y_OFFSET was hand-tuned to -96 px to compensate this same
## warp for AreaTransition triggers. The measured displacement is 140.6 px,
## so triggers are under-compensated by ~44.6 px (~1.4 tiles). That is a
## plausible explanation for interactions still reading slightly off after
## the ultracode overhaul. Pinned as a KNOWN gap rather than silently
## "corrected" — retuning that constant is cowir-main's call and their
## tests pin its value.
const TRIGGER_OFFSET_EXPECTED := -96.0
const KNOWN_UNDER_COMPENSATION_PX := 44.6


func test_mode7_trigger_offset_is_under_compensated() -> void:
	var geo := load("res://src/exploration/InteractGeometry.gd")
	assert_eq(geo.MODE7_TRIGGER_Y_OFFSET, TRIGGER_OFFSET_EXPECTED,
		"trigger offset unchanged — this file reports the gap, it does not close it")
	var gap: float = MEASURED_DISPLACEMENT_WORLD_PX - absf(geo.MODE7_TRIGGER_Y_OFFSET)
	assert_almost_eq(gap, KNOWN_UNDER_COMPENSATION_PX, MEASURE_TOLERANCE_PX,
		"triggers compensate %.1f of the measured %.1f px — %.1f px short" % [
			absf(geo.MODE7_TRIGGER_Y_OFFSET), MEASURED_DISPLACEMENT_WORLD_PX, gap])


## Viability note for whichever fix is chosen: TileMapLayer exposes
## `collision_enabled`, so the terrain fix can be a collision-only clone
## (visible layer physics off + an invisible layer shifted south by the
## displacement) rather than cowir-main's "kludgy" synthesized StaticBody
## walls. Pinned so the option doesn't get rediscovered from scratch.
func test_collision_only_clone_is_available_as_a_fix_path() -> void:
	var layer := TileMapLayer.new()
	autofree(layer)
	assert_true("collision_enabled" in layer,
		"TileMapLayer.collision_enabled exists — a physics-only clone is viable")
	assert_true(layer.collision_enabled,
		"defaults true, so the visible layer must be explicitly disabled if cloned")
