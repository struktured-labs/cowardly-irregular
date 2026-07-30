extends GutTest

## Aria rendered as procedural pixels while her artist frames sat on disk, used. 2026-07-30.
##
## struktured: "aria is a horrific proc gen guy … dancer still awful proc gen on inside of inn
## (same pic)". Both reports are the SAME sprite — `_create_npc("Aria", "dancer", …)` in
## TavernInterior is the only dancer NPC in the game, and InnInterior has none.
##
##   assets/sprites/npcs/dancer/frame_0..3.png   artist-anchored, 32x32, four distinct images,
##                                              landed 42b0c123 on 2026-07-18
##   VillageBar                                  loaded them from day one
##   OverworldNPC                                did NOT — the npc_type alias table carried
##                                              `# "dancer" stays procedural — it has its own
##                                              animation system`
##
## That comment was TRUE WHEN WRITTEN and stale the moment the frames landed. Having its own
## animation system is the reason to keep four frames; it was never a reason to draw them by hand.
## Two consumers, one shared set of files, and the one that refused them did so in a comment
## nobody revisited — the stale-body class, in art wiring rather than in a memory entry.
##
## The two path lists are REDUNDANT sources, so per the project rule this asserts AGREEMENT rather
## than modelling precedence: if both agree, which one wins is moot.

const NPC := "res://src/exploration/OverworldNPC.gd"
const BAR := "res://src/exploration/VillageBar.gd"


func _npc_script() -> GDScript:
	return load(NPC) as GDScript


func _bar_script() -> GDScript:
	return load(BAR) as GDScript


# ── the frames exist and are real ───────────────────────────────────

func test_all_four_artist_frames_are_on_disk() -> void:
	# Positive control for everything below: an absent frame set makes the fallback correct, and
	# every other assertion here would then be defending nothing.
	var paths: Array = _npc_script().get_script_constant_map()["DANCER_FRAME_PATHS"]
	assert_eq(paths.size(), 4, "the dance cycle is four frames")
	var missing: Array = []
	for p in paths:
		if not ResourceLoader.exists(str(p)):
			missing.append(str(p))
	assert_eq(missing, [], "artist dancer frames must be present: %s" % str(missing))


func test_the_four_frames_are_distinct_pictures() -> void:
	# struktured's "(same pic)". Four identical frames animate to a still image, which would make
	# the artist path look as bad as the procedural one and read as the fix not having landed.
	var paths: Array = _npc_script().get_script_constant_map()["DANCER_FRAME_PATHS"]
	var seen: Dictionary = {}
	for p in paths:
		var tex: Texture2D = load(str(p))
		assert_not_null(tex, "%s must load" % p)
		if tex == null:
			continue
		var img: Image = tex.get_image()
		seen[img.get_data().hex_encode()] = true
	assert_eq(seen.size(), 4, "all four frames must differ — identical frames animate to a still")


func test_frames_match_the_procedural_footprint() -> void:
	# The procedural path drew at TILE_SIZE x TILE_SIZE. A different size would silently rescale
	# Aria relative to every other NPC rather than fail, which is the quiet-wrong outcome.
	var tile: int = int(_npc_script().get_script_constant_map()["TILE_SIZE"])
	var paths: Array = _npc_script().get_script_constant_map()["DANCER_FRAME_PATHS"]
	for p in paths:
		var img: Image = (load(str(p)) as Texture2D).get_image()
		assert_eq(img.get_width(), tile, "%s width must match TILE_SIZE" % p)
		assert_eq(img.get_height(), tile, "%s height must match TILE_SIZE" % p)


# ── both consumers read the same files ──────────────────────────────

func test_both_consumers_agree_on_the_paths() -> void:
	# Redundant sources: assert agreement, never precedence. If these drift, one consumer silently
	# falls back to procedural and the other does not — which is exactly the split that produced
	# the bug, with VillageBar loading the art and OverworldNPC drawing its own.
	var npc_paths: Array = _npc_script().get_script_constant_map()["DANCER_FRAME_PATHS"]
	var bar_paths: Array = _bar_script().get_script_constant_map()["DANCER_FRAME_PATHS"]
	assert_eq(npc_paths, bar_paths,
		"OverworldNPC and VillageBar must read the SAME dancer frames — divergence means one of "
		+ "them is quietly procedural")


func test_the_stale_carve_out_is_gone() -> void:
	# The comment that caused it. Not a style pin: while it stands, the next person to touch the
	# alias table has a documented reason to route dancer back to procedural.
	var src := FileAccess.get_file_as_string(NPC)
	assert_false(src.contains("\"dancer\" stays procedural"),
		"the carve-out claiming dancer must stay procedural was written before the artist frames "
		+ "existed — it is a live instruction to reintroduce the bug")


func test_the_procedural_fallback_survives() -> void:
	# Deleting the fallback would be the over-correction: the frames could be excluded from a web
	# export, and a dancer with no texture at all is worse than an ugly one.
	var src := FileAccess.get_file_as_string(NPC)
	assert_true(src.contains("_draw_dancer_frame("),
		"the procedural path must remain as the fallback for a missing or excluded frame set")
	var at: int = src.find("func _generate_dance_frames")
	assert_gt(at, -1, "the generator must still exist")
	var body: String = src.substr(at, 400)
	assert_true(body.contains("_try_load_artist_dance_frames("),
		"artist frames must be tried FIRST — otherwise the procedural draw wins and nothing changed")


# ── the loader is all-or-nothing ────────────────────────────────────

func test_a_partial_frame_set_falls_back_entirely() -> void:
	# Half artist, half hand-drawn would animate as a flicker between two art styles — worse than
	# either alone, and it would pass a naive "did we load any frames" check.
	var npc = _npc_script().new()
	var ok: bool = npc._try_load_artist_dance_frames([
		"res://assets/sprites/npcs/dancer/frame_0.png",
		"res://assets/sprites/npcs/dancer/does_not_exist.png",
		"res://assets/sprites/npcs/dancer/frame_2.png",
		"res://assets/sprites/npcs/dancer/frame_3.png",
	])
	assert_false(ok, "a missing frame must reject the WHOLE set, not load three of four")
	npc.free()


func test_a_wrong_length_set_is_refused() -> void:
	var npc = _npc_script().new()
	assert_false(npc._try_load_artist_dance_frames(["res://assets/sprites/npcs/dancer/frame_0.png"]),
		"a set that is not DANCE_FRAMES long cannot drive the cycle")
	npc.free()


func test_the_real_set_loads() -> void:
	# Positive control for the two negatives above: they pass against a loader that always
	# returns false, which would leave Aria procedural exactly as before.
	var npc = _npc_script().new()
	assert_true(npc._try_load_artist_dance_frames(),
		"the real four-frame set must load — if this fails the fix is inert and Aria is still procedural")
	npc.free()
