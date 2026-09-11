extends GutTest

## Walk toward any map edge and the Mode 7 view clears the tilemap before the boundary wall stops you.
## What fills that gap is the scene's Background ColorRect, sampled by the shader like any other ground.
##
## FOUND 2026-09-10 by rendering the NW corner of all five Mode 7 worlds: every background was a
## near-black slab unrelated to the sky above it, so the world ended in a hard-edged trapezoid of
## void. Measured on the industrial corner: bg (0.14,0.12,0.10) fogged 61% toward fog_color gave a
## flat (76,71,66) band under a (102,97,92) horizon — a visible wall, 60% of the frame.
##
## The fix is that the fill IS the horizon band's own lower edge, sky_bottom lerped toward fog_color
## by fog_strength, so the map edge dissolves into the same haze the far ground fades into.
##
## Both tests read the LIVE scene's node rather than the helper, so re-hardcoding a colour reds them.
## Every one of the five shipped literals failed the luminance test: medieval 0.19 vs 0.63,
## suburban 0.65 vs 0.77, steampunk 0.10 vs 0.46, industrial 0.12 vs 0.39, digital 0.03 vs 0.19.

## Scene -> the preset id it passes to Mode7Overlay.apply_preset(). W6 is absent on purpose: it
## disables Mode 7, and its near-white void is The Absence, not a bug.
const MODE7_WORLDS := {
	"res://src/exploration/OverworldScene.gd": "medieval",
	"res://src/exploration/SuburbanOverworld.gd": "suburban",
	"res://src/exploration/SteampunkOverworld.gd": "steampunk",
	"res://src/exploration/IndustrialOverworld.gd": "industrial",
	"res://src/exploration/FuturisticOverworld.gd": "digital",
}
const ABSTRACT_SCENE := "res://src/exploration/AbstractOverworld.gd"
## Half of the widest supported viewport — the fill has to outrun it or raw black shows past the rect.
const WIDEST_HALF_VIEW := 640.0
## A slab reads as a slab well before this; the smallest real offender was suburban at 0.12.
const MAX_LUMINANCE_GAP := 0.08


func _background_of(path: String) -> ColorRect:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var scene = load(path).new()
	vp.add_child(scene)
	await get_tree().physics_frame
	return scene.get_node_or_null("Background") as ColorRect


## The band's lower edge, recomputed from the presets so this never reads back the helper it checks.
func _horizon_band_bottom(world_id: String) -> Color:
	var preset: Dictionary = Mode7Overlay.WORLD_PRESETS[world_id]
	var sky: Color = preset.get("sky_bottom", Color(0.55, 0.65, 0.85))
	var fog: Color = preset.get("fog_color", Color(0.50, 0.60, 0.78))
	return sky.lerp(fog, float(preset.get("fog_strength", 0.45)))


func test_every_mode7_world_fills_its_void_from_the_shared_horizon() -> void:
	var checked := 0
	for path in MODE7_WORLDS:
		var world_id: String = MODE7_WORLDS[path]
		assert_true(Mode7Overlay.WORLD_PRESETS.has(world_id),
			"CONTROL: '%s' must name a real Mode 7 preset" % world_id)
		var bg: ColorRect = await _background_of(path)
		assert_not_null(bg, "%s has no Background node" % path)
		if bg == null:
			continue
		checked += 1
		var want := Mode7Overlay.void_color(world_id)
		assert_almost_eq(bg.color.r, want.r, 0.002, "%s background R" % world_id)
		assert_almost_eq(bg.color.g, want.g, 0.002, "%s background G" % world_id)
		assert_almost_eq(bg.color.b, want.b, 0.002, "%s background B" % world_id)
	assert_eq(checked, MODE7_WORLDS.size(), "CONTROL: every Mode 7 world must have been built")


func test_the_off_map_fill_is_never_a_slab_against_its_own_sky() -> void:
	var offenders: Array = []
	var checked := 0
	for path in MODE7_WORLDS:
		var world_id: String = MODE7_WORLDS[path]
		var bg: ColorRect = await _background_of(path)
		if bg == null:
			continue
		checked += 1
		var gap: float = absf(bg.color.get_luminance() - _horizon_band_bottom(world_id).get_luminance())
		if gap > MAX_LUMINANCE_GAP:
			offenders.append("%s: fill %.2f vs horizon %.2f" %
				[world_id, bg.color.get_luminance(), _horizon_band_bottom(world_id).get_luminance()])
	assert_eq(checked, MODE7_WORLDS.size(), "CONTROL: every Mode 7 world must have been built")
	assert_eq(offenders, [], "off-map fill reads as a slab, not as distance")


func test_the_fill_reaches_past_the_widest_view_in_every_world() -> void:
	var paths: Array = MODE7_WORLDS.keys()
	paths.append(ABSTRACT_SCENE)
	var checked := 0
	for path in paths:
		var bg: ColorRect = await _background_of(path)
		assert_not_null(bg, "%s has no Background node" % path)
		if bg == null:
			continue
		checked += 1
		assert_lt(bg.position.x, -WIDEST_HALF_VIEW, "%s fill starts inside the view" % path)
		assert_lt(bg.position.y, -WIDEST_HALF_VIEW, "%s fill starts inside the view" % path)
		var parent = bg.get_parent()
		var map_w: float = float(parent.MAP_WIDTH * parent.TILE_SIZE)
		var map_h: float = float(parent.MAP_HEIGHT * parent.TILE_SIZE)
		assert_gt(bg.position.x + bg.size.x, map_w + WIDEST_HALF_VIEW, "%s fill ends inside the view" % path)
		assert_gt(bg.position.y + bg.size.y, map_h + WIDEST_HALF_VIEW, "%s fill ends inside the view" % path)
	assert_eq(checked, paths.size(), "CONTROL: every overworld must have been built")
