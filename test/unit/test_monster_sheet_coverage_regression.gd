extends GutTest

## Every monster in monsters.json must have a sheet that LOADS and is VISIBLE.
##
## Two real defects, both silent, both shipped:
##
##   1. Unregistered id -> HybridSpriteLoader.load_monster_sprite_frames()
##      returns null and the battle falls back to a procedural drawing.
##      chancellor_mordaine sat like that from 2026-07-17; three more
##      monsters (rogue_automaton, rogue_mailbox, time_phantom) had been
##      in monsters.json since forever with no sheet at all.
##
##   2. Registered but BLANK -> masterite_tempo_abstract shipped with 5
##      opaque pixels in its idle frame and masterite_curator_abstract
##      with 140. Nothing errored. The boss was invisible until it swung,
##      and its Bestiary entry was an empty box, because BestiaryMenu
##      renders the IDLE animation specifically (BestiaryMenu.gd:511 sets
##      _detail_sprite.visible = false rather than drawing a placeholder).
##
## Defect 2 is why this test reads PIXELS and not just the manifest. A
## coverage check that only asks "is there an entry" passes happily on a
## fully transparent PNG — it would have called both invisible bosses
## covered. Same trap as pinning source text: the cheap proxy agrees with
## the expensive truth right up until it doesn't.
##
## Coverage is currently complete (98/98 as of 2026-07-28, steampunk
## masterites being the last world-shaped hole). This test exists to keep
## it that way: adding a monster without art now fails here rather than
## in front of a player.

const MIN_IDLE_OPAQUE := 500


func _monster_ids() -> Array:
	var raw := FileAccess.get_file_as_string("res://data/monsters.json")
	assert_ne(raw, "", "monsters.json must be readable")
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "monsters.json must parse to a Dictionary")
	if not (parsed is Dictionary):
		return []
	var mons = parsed.get("monsters", parsed)
	return mons.keys()


func test_every_monster_has_a_sheet_that_loads() -> void:
	var ids := _monster_ids()
	assert_gt(ids.size(), 50,
		"sanity: expected the full monster roster, got %d — if this fires the parse is wrong and every assertion below is vacuous" % ids.size())
	var missing: Array = []
	for id in ids:
		if HybridSpriteLoader.load_monster_sprite_frames(id) == null:
			missing.append(id)
	assert_eq(missing, [],
		"every monster must resolve to a sheet — these fall back to a procedural drawing in battle and to an EMPTY BOX in the Bestiary: %s" % [missing])


func test_every_monster_idle_frame_is_actually_visible() -> void:
	# The check that would have caught the two invisible masterites.
	# Reads the idle frame's alpha, because "has a manifest entry" and
	# "can be seen" are different claims and only one of them matters.
	var ids := _monster_ids()
	var blank: Array = []
	for id in ids:
		# NOTE: this returns a SpriteFrames, NOT a Dictionary of arrays.
		# I wrote frames["idle"] first and the test failed 0/2 on a clean
		# tree — which is the argument for behavioural tests in one line:
		# a source-reading guard would have "passed" while asserting
		# against an API that does not exist.
		var frames: SpriteFrames = HybridSpriteLoader.load_monster_sprite_frames(id)
		if frames == null or not frames.has_animation("idle"):
			continue
		if frames.get_frame_count("idle") == 0:
			blank.append("%s (no idle frames)" % id)
			continue
		var tex: Texture2D = frames.get_frame_texture("idle", 0)
		if tex == null:
			blank.append("%s (null idle texture)" % id)
			continue
		var img := tex.get_image()
		if img == null:
			continue
		var opaque := 0
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				if img.get_pixel(x, y).a > 0.03:
					opaque += 1
		if opaque * 4 < MIN_IDLE_OPAQUE:
			blank.append("%s (~%d opaque px)" % [id, opaque * 4])
	assert_eq(blank, [],
		"these monsters are registered but effectively INVISIBLE in their idle pose — blank in battle until they attack, and a blank Bestiary entry permanently: %s" % [blank])
