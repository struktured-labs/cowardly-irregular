extends GutTest

## A W2-W6 cave was lit like a medieval one, and every existing guard said it was fine.
##
## FOUND 2026-10-29, CrossCode spec phase 4 (docs/superpowers/specs/2026-08-21-crosscode-environment-design.md
## section 5). The rig shipped 2026-08-22 and `test_every_dungeon_is_lit` proves all sixteen dungeons
## build one -- so the feature reads as done. It asks "is this dungeon lit", never "is it lit like ITS
## world", and those are different questions: Suburban Underground, the Grand Mechanism and the
## Assembly Core each fell through `DragonCave._get_dungeon_ambient` to the W1 cave ambient, and ALL
## SEVEN later-world dungeons -- including the four that already had their own ambient -- placed the
## W1 flame, because `_place_torches` hardcoded `Color(1.0, 0.80, 0.45)` with no seam at all. A
## digital kernel lit by torchlight. The giveaway was that the AUDIO already knew which world it was
## in: Suburban overrides `_get_ambient_fx_theme` to "drain" and Assembly Core to "steam", in the
## very same classes that were taking W1's light.
##
## WORLD IS DERIVED, NOT LISTED. `overworld_exit_map` is the overworld a cave returns you to -- the
## lens `test_later_dungeon_exits_land_at_their_doors` already uses. W1 leaves it at "overworld". A
## new later-world dungeon is in this corpus the day it is added, with no list to update, and a new
## W1 cave is correctly silent. The dungeon corpus itself is selected by SHAPE, borrowed from
## `test_every_dungeon_is_lit` after the fleet's suppression audit, so a component or a base dropped
## into that directory is never mistaken for a map.
##
## THE LENS HAS ONE GAP AND IT IS MADE LOUD, NOT EXEMPT. WhisperingCave predates the property: it
## extends Node2D and hardcodes `target_map = "overworld"`, so it has no `overworld_exit_map` at all.
## Defaulting absence to W1 would be right for it and would silently exempt a future later-world map
## that also skipped the seam -- and reading the exit off the built AreaTransition instead is worse,
## because `AreaTransition.target_map` DEFAULTS to "overworld", so an unset stairs-up transition
## reports W1 for any cave. So an unclassifiable dungeon is collected and checked against the set of
## later-world exit maps the rest of the corpus actually uses: naming one is a failure, naming none
## makes it a W1-era map. The set is derived from the corpus, so it needs no list of world names.
##
## WHY DISTINCTNESS IS NOT ASSERTED. Null Chamber and Vertex Apex share one ambient today, both being
## W6 rooms, and that is a defensible authoring choice. Pinning "every cave differs from every other"
## would red that correct state. The defect is falling back to W1, so that is what is asserted.
##
## WHY LUMINANCE IS NOT THE IDENTITY SIGNAL. Suburban's new ambient has the same luminance as the W1
## default to four places (0.3615) -- deliberately, so it is as legible as the value struktured asked
## for on 2026-10-06. A brightness comparison would call it identical. The colour is compared.
##
## AMBIENT IS READ OFF THE APPLIED COLOUR AFTER A PROCESS FRAME, not off the constructor:
## DungeonLighting._ready sets WHITE and _process installs the real ambient, so a physics-only probe
## reports every dungeon white and the whole feature inert.
##
## EVERY ASSERT IN THE TWO SWEEP ARMS SITS AFTER ITS LOOP. A GDScript error aborts its enclosing
## function, and an arm that has already asserted once scores the abort as a pass -- so a corpus
## control placed above the loop would convert a mid-sweep abort from EC=4 into a green file.

const DUNGEON_DIR := "res://src/maps/dungeons"
const DL := preload("res://src/exploration/DungeonLighting.gd")
const VL := preload("res://src/exploration/VillageLighting.gd")
const W1_EXIT_MAP := "overworld"


## A file is out if its extends-chain roots at something other than Node2D (a component), or if
## another file here extends it (a base). Same derivation as test_every_dungeon_is_lit.
func _dungeon_scripts() -> Array:
	var files: Array = []
	var dir := DirAccess.open(DUNGEON_DIR)
	if dir == null:
		return files
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".gd"):
			files.append(f)
		f = dir.get_next()

	var base_of := {}
	var extended := {}
	for name in files:
		var src := FileAccess.get_file_as_string("%s/%s" % [DUNGEON_DIR, name])
		var rx := RegEx.new()
		rx.compile("(?m)^extends\\s+(\\w+)")
		var m := rx.search(src)
		base_of[name] = (m.get_string(1) if m != null else "")
		for other in files:
			if other != name and base_of[name] == other.get_basename():
				extended[other] = true

	var out: Array = []
	for name in files:
		if extended.has(name):
			continue
		var cur: String = name
		var root: String = base_of.get(cur, "")
		var hops := 0
		while hops < 8:
			var parent_file := root + ".gd"
			if not (parent_file in files):
				break
			cur = parent_file
			root = base_of.get(cur, "")
			hops += 1
		if root == "Node2D":
			out.append(name)
	out.sort()
	return out


func _build(name: String) -> Node:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	var d = load("%s/%s" % [DUNGEON_DIR, name]).new()
	vp.add_child(d)
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	return d


func _lamp_colors(d: Node) -> Array:
	var out: Array = []
	var lighting = d.get_node_or_null("Lighting")
	if lighting == null:
		return out
	for ch in lighting.get_children():
		if ch is PointLight2D:
			out.append((ch as PointLight2D).color)
	return out


func _has_color(colors: Array, want: Color) -> bool:
	for c in colors:
		if (c as Color).is_equal_approx(want):
			return true
	return false


## FLOOR. _get_torch_tint is new, so its only consumers are DragonCave and this file -- nothing else
## in the corpus would red if it were renamed, and an instance call that cannot resolve aborts the
## enclosing function, scoring the sweep arms as passing on asserts they never reached. Its own arm,
## so it cannot shift any other arm's statement order.
func test_the_seams_this_file_drives_exist() -> void:
	var d = load("%s/RootProcess.gd" % DUNGEON_DIR).new()
	autofree(d)
	assert_true(d.has_method("_get_torch_tint"),
		"DragonCave._get_torch_tint is gone or renamed -- every torch finding below would be vacuous")
	assert_true(d.has_method("_get_dungeon_ambient"),
		"DragonCave._get_dungeon_ambient is gone or renamed")
	assert_true("overworld_exit_map" in d,
		"overworld_exit_map is the world lens this file derives its corpus from")


func test_a_later_world_cave_does_not_fall_back_to_the_w1_look() -> void:
	var scripts := _dungeon_scripts()
	var later: Array = []
	var w1: Array = []
	var unlit: Array = []
	var medieval_ambient: Array = []
	var w1_flame: Array = []
	var seam_ignored: Array = []
	var too_bright: Array = []
	var knee: float = VL.LAMP_FADE_START - VL.LAMP_FADE_SPAN

	var unclassified: Array = []
	var later_exit_maps: Dictionary = {}

	for name in scripts:
		var d = await _build(name)
		var has_lens: bool = "overworld_exit_map" in d
		var exit_map: String = str(d.overworld_exit_map) if has_lens else ""
		var lighting = d.get_node_or_null("Lighting")
		if lighting == null:
			unlit.append(name)
			continue
		var applied: Color = (lighting as CanvasModulate).color

		# The coupling that makes a "bright void" ambient silently wrong, checked on every dungeon:
		# VillageLighting.lamp_energy_for fades a lamp out as the modulate GAINS luminance, hitting
		# zero at LAMP_FADE_START. An ambient above the full-energy knee dims every torch in the
		# room with nothing in the scene saying so. Derived from the rig's constants, not a literal.
		if applied.get_luminance() > knee:
			too_bright.append("%s lum=%.3f > knee=%.3f" % [name, applied.get_luminance(), knee])

		if not has_lens:
			unclassified.append(name)
			continue
		if exit_map == W1_EXIT_MAP:
			w1.append(name)
			continue

		later.append(name)
		later_exit_maps[exit_map] = true
		var colors := _lamp_colors(d)
		var own_torch: Color = d._get_torch_tint()
		if applied.is_equal_approx(DL.CAVE_AMBIENT):
			medieval_ambient.append("%s (%s)" % [name, exit_map])
		if _has_color(colors, DL.TORCH_TINT):
			w1_flame.append("%s (%s)" % [name, exit_map])
		if not _has_color(colors, own_torch):
			seam_ignored.append("%s declares %s and placed none" % [name, str(own_torch)])

	# CONTROLS first, because a true zero in the findings answers nothing unless the corpus could
	# have held the defect, and the knee has to sit where a cave can actually fail it.
	assert_gt(scripts.size(), 8,
		"CONTROL: only %d dungeon maps found -- the scan is looking in the wrong place" % scripts.size())
	assert_gt(later.size(), 3,
		"CONTROL: only %d later-world dungeons in the corpus: %s" % [later.size(), str(later)])
	assert_gt(w1.size(), 0, "CONTROL: no W1 dungeon found, so the sibling W1 arm is empty")
	assert_between(knee, 0.0, 1.0, "CONTROL: the lamp-fade knee is outside reachable luminance, so nothing could fail it")

	# A dungeon outside the lens is only safe if nothing in it names a later world's overworld.
	var evaded: Array = []
	for name in unclassified:
		var src := FileAccess.get_file_as_string("%s/%s" % [DUNGEON_DIR, name])
		for m in later_exit_maps:
			if src.contains(str(m)):
				evaded.append("%s names %s but declares no overworld_exit_map" % [name, str(m)])
	assert_gt(later_exit_maps.size(), 0, "CONTROL: no later-world exit maps derived, so the evasion check is empty")
	assert_eq(evaded, [],
		"a later-world dungeon is invisible to the world lens, so its lighting is never checked: %s" % str(evaded))

	assert_eq(unlit, [], "a dungeon built no lighting rig: %s" % str(unlit))
	assert_eq(medieval_ambient, [],
		"a later world's cave is tinted with W1's cave ambient -- it reads as the medieval dungeon it is not: %s" % str(medieval_ambient))
	assert_eq(w1_flame, [],
		"a later world's cave is lit by the W1 flame; a kernel and a factory floor are not torchlit: %s" % str(w1_flame))
	assert_eq(seam_ignored, [],
		"_place_torches ignored _get_torch_tint, so the override is declared and inert: %s" % str(seam_ignored))
	assert_eq(too_bright, [],
		"a dungeon ambient above the lamp-fade knee dims its own torches: %s" % str(too_bright))


func test_w1_caves_still_look_medieval() -> void:
	# The detector has to distinguish "no world identity" from "no ambient at all", and this fold
	# must not have moved W1. Without this arm the sweep above passes just as well against a rig
	# that hands every cave a different random colour.
	var seen: Array = []
	var defaulted: Array = []
	var flamelit: Array = []

	for name in _dungeon_scripts():
		var d = await _build(name)
		if not ("overworld_exit_map" in d):
			continue
		if str(d.overworld_exit_map) != W1_EXIT_MAP:
			continue
		seen.append(name)
		var lighting = d.get_node_or_null("Lighting")
		if lighting == null:
			continue
		if (lighting as CanvasModulate).color.is_equal_approx(DL.CAVE_AMBIENT):
			defaulted.append(name)
		if _has_color(_lamp_colors(d), DL.TORCH_TINT):
			flamelit.append(name)

	assert_gt(seen.size(), 2, "CONTROL: only %d W1 dungeons found: %s" % [seen.size(), str(seen)])
	assert_gt(defaulted.size(), 0,
		"no W1 cave carries the default ambient any more -- this fold moved W1, or the default became unreachable")
	assert_gt(flamelit.size(), 0,
		"no W1 cave is lit by the W1 flame any more -- _get_torch_tint's default stopped being the flame")
