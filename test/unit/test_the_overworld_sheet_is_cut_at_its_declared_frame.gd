extends GutTest

## The player's overworld walk sheet was cut at a hardcoded 32 px, guarded only by "is the image
## BIG ENOUGH" (`get_width() < 128 or get_height() < 128`). A sheet authored at any other frame
## size passes that and is sliced into 32 px squares: the character renders as a quarter of a
## figure, in the overworld, and nothing errors.
##
## All 14 sheets are 128x128 at 32 px today, which is exactly why it held — the same reason
## cowir-cutscenes' CutsceneActor held on 159-for-159 uniform sheets until they measured it
## (2026-09-16, `62dc0776`). A convention that every file happens to satisfy is indistinguishable
## from a rule that is enforced, right up until someone re-exports one sheet.
##
## 🔑 THE FRAME SIZE WAS ALREADY DECLARED. `overworld_player_sheets` carries frame_width and
## frame_height on all 14 entries and NOTHING read the section — one of six sections in this
## manifest with no reader at all. So the authored geometry sat beside a consumer that guessed it.
## This wires the two together, which is why the fix is a reader rather than a declaration.
##
## ⚠️ A SECTION whose FIELDS are all read elsewhere is invisible to a field-level census:
## frame_width IS read, by the battle sheet loader, so test_a_manifest_field_is_read_or_declared
## sees nothing wrong here. That guard asks about fields; this one is why sections need their own
## question.
const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const MANIFEST := "res://data/sprite_manifest.json"
const SECTION := "overworld_player_sheets"
const WALK_FRAMES := 4
const ROWS := 4


func _section() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "sprite_manifest.json must parse")
	return (parsed as Dictionary).get(SECTION, {}) if parsed is Dictionary else {}


## The owner, driven directly, including every reason it must fall back.
func test_the_declared_frame_size_is_what_the_owner_returns() -> void:
	var section := _section()
	assert_gt(section.size(), 10, "ANTI-VACUITY: only %d overworld player sheets registered" % section.size())
	for job in section:
		var entry: Dictionary = section[job]
		var want := Vector2i(int(entry.get("frame_width", 0)), int(entry.get("frame_height", 0)))
		assert_eq(Loader.overworld_frame_size(str(job)), want,
			"%s's overworld frame must come from its manifest entry, not from a convention" % job)
	# An unregistered job keeps the 32px convention — the fallback must stay, 0 would refuse every sheet.
	assert_eq(Loader.overworld_frame_size("__no_such_job__"), Vector2i(32, 32),
		"an unregistered job falls back to the 32px convention rather than to nothing")


## ⚠️ THE LIMIT OF THE ARM ABOVE, STATED RATHER THAN PAPERED OVER. Every entry declares 32x32 and
## the fallback is 32x32, so a hardcoded owner returns the right answer for every shipped job:
## WHILE THE ROSTER IS UNIFORM, NO DIRECT COMPARISON CAN TELL "reads the manifest" FROM "returns
## a constant". cowir-autogrind hit the same shape on `max_multiplier` and said so instead of
## inventing a check (2026-09-16) — an unreachable value is untestable by construction.
##
## 🔑 WHAT DOES DISCRIMINATE is the grid arm below, driven by a manifest edit: change one entry's
## frame_width to 48 and a 128px sheet stops dividing, so the arm reds — but ONLY if the owner
## actually read the change. A constant owner keeps returning 32, 128 still divides, and the arm
## stays green. That mutation is the behavioural proof; this arm records why it is needed.
func test_the_uniform_roster_is_why_a_direct_comparison_cannot_discriminate() -> void:
	var section := _section()
	var sizes := {}
	for job in section:
		sizes[str(Loader.overworld_frame_size(str(job)))] = true
	assert_eq(sizes.size(), 1,
		"the roster is no longer uniform (%s) — good: the comparison arm above now discriminates on its own, and this note is stale" % [sizes.keys()])
	assert_eq(Loader.overworld_frame_size("__no_such_job__"), Vector2i(32, 32),
		"...and the fallback matches it, which is the other half of why a constant would pass")

	# The owner must READ, not restate. A source pin, and labelled as one: it cannot see an owner
	# that reads the entry and then ignores it — the grid mutation is what covers that.
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of("res://src/battle/sprites/HybridSpriteLoader.gd")
	assert_true(code.contains("_overworld_player_sheets.get(job_id"),
		"overworld_frame_size must look the job up in the manifest section, not answer from a constant")
	assert_true(code.contains("json.data.get(\"overworld_player_sheets\""),
		"the section must actually be loaded, or the lookup above is permanently empty and the fallback is the whole function")


## Every shipped sheet must be an exact grid at its DECLARED size — the property the consumer now
## refuses on. A sheet that is merely "big enough" is the input that produced a quarter-figure.
func test_every_shipped_sheet_is_an_exact_grid_at_its_declared_frame() -> void:
	var section := _section()
	var bad: Array = []
	var checked := 0
	for job in section:
		var entry: Dictionary = section[job]
		var path := str(entry.get("path", ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		var tex := load(path) as Texture2D
		if tex == null:
			continue
		var img := tex.get_image()
		if img == null:
			continue
		checked += 1
		var f: Vector2i = Loader.overworld_frame_size(str(job))
		if img.get_width() % f.x != 0 or img.get_height() % f.y != 0:
			bad.append("%s: %dx%d is not a whole number of %dx%d frames" % [job, img.get_width(), img.get_height(), f.x, f.y])
		elif img.get_width() / f.x < WALK_FRAMES or img.get_height() / f.y < ROWS:
			bad.append("%s: %dx%d gives %dx%d frames, short of %d columns x %d rows"
				% [job, img.get_width(), img.get_height(), img.get_width() / f.x, img.get_height() / f.y, WALK_FRAMES, ROWS])
	assert_gt(checked, 10, "ANTI-VACUITY: only %d sheets were loadable — the scan is measuring nothing" % checked)
	assert_eq(bad, [], "an overworld sheet is not an exact grid at the size the manifest declares: %s" % [bad])


## The WORLD-DRESSED sheets are cut by the same code at the same declared size, and they are NOT
## in the manifest — `overworld_<world>.png` is resolved by path convention. A costume authored at
## a different frame size is the live route to the defect, so it is checked against the base's
## declaration rather than against itself.
func test_every_world_dressed_sheet_matches_its_jobs_declared_frame() -> void:
	var section := _section()
	var suffixes: Array = []
	for s in Loader.WORLD_SUFFIXES:
		if s != "":
			suffixes.append(s)
	assert_gt(suffixes.size(), 3, "ANTI-VACUITY: the world vocabulary is empty, so no costume is checked")
	var bad: Array = []
	var found := 0
	for job in section:
		var f: Vector2i = Loader.overworld_frame_size(str(job))
		for s in suffixes:
			var path := "res://assets/sprites/jobs/%s/overworld_%s.png" % [job, s]
			if not ResourceLoader.exists(path):
				continue
			found += 1
			var tex := load(path) as Texture2D
			if tex == null:
				continue
			var img := tex.get_image()
			if img == null:
				continue
			if img.get_width() % f.x != 0 or img.get_height() % f.y != 0 \
					or img.get_width() / f.x < WALK_FRAMES or img.get_height() / f.y < ROWS:
				bad.append("%s/%s: %dx%d against a declared %dx%d frame" % [job, s, img.get_width(), img.get_height(), f.x, f.y])
	assert_gt(found, 20,
		"ANTI-VACUITY: only %d world-dressed overworld sheets found — this arm is checking almost nothing" % found)
	assert_eq(bad, [], "a world costume is cut at a frame size its own art does not divide by: %s" % [bad])


## ⛔ THE CONSUMER MUST ASK THE OWNER. Both halves: the call is present, and the superseded rule
## — a hardcoded frame with a "big enough" check — is ABSENT. A copy of either passes every arm
## above while the shipped screen regresses.
func test_the_overworld_loader_reads_the_declaration() -> void:
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of("res://src/exploration/OverworldPlayer.gd")
	assert_gt(code.length(), 1000, "PRECONDITION: OverworldPlayer must be readable and stripped")
	assert_true(code.contains("HybridSpriteLoader.overworld_frame_size("),
		"OverworldPlayer must take its frame size from the manifest owner")
	assert_false(code.contains("var frame_w = 32"),
		"the hardcoded 32px frame is the rule this file replaced")
	assert_false(code.contains("img.get_width() < 128"),
		"the 'big enough' check is what let a wrong-shaped sheet through to be mis-sliced")
	# The CALL SITE, not just the helper. A correct _fit_to_sprite_size that the cut loop never
	# calls passes every arm above — this lane's mutation 7, and the reason this line exists.
	assert_true(code.contains("_fit_to_sprite_size(frame_img)"),
		"the cut loop must normalise each frame to SPRITE_SIZE, or a correctly-sliced 48px sheet renders oversized")


## ⛔ THE HALF THIS FIX NEARLY BROKE. Deriving the CUT while everything else still assumes 32 is
## worse than assuming both: the two agree on every sheet EXCEPT the ones the fix was written for.
## A 48px sheet would go from mis-sliced (wrong art, right size) to correctly sliced and oversized
## (right art, wrong size), 1.5x the procedural fallback and 1.5x a STEP_DISTANCE tile.
##
## cowir-cutscenes hit this exact shape one branch after their slicer fix (2026-09-16, d92d368f):
## `_load_sheet` measured the frame while `show_emote` kept computing from the constant. Their
## sentence is the rule — ONE HALF DERIVED AND ONE HALF GUESSING IS WORSE THAN BOTH GUESSING —
## and I went looking here because of it rather than finding it myself.
func test_a_frame_cut_at_any_size_still_renders_at_sprite_size() -> void:
	const OWP := preload("res://src/exploration/OverworldPlayer.gd")
	var player = OWP.new()
	add_child_autofree(player)
	var sprite_size: int = OWP.SPRITE_SIZE
	assert_eq(sprite_size, 32, "PRECONDITION: the overworld renders at 32px, one STEP_DISTANCE tile")

	# A frame larger than SPRITE_SIZE must come back AT SPRITE_SIZE, not at its own size.
	var big := Image.create(48, 48, true, Image.FORMAT_RGBA8)
	big.fill(Color(1, 0, 0, 1))
	var fitted: Image = player.call("_fit_to_sprite_size", big)
	assert_eq(Vector2i(fitted.get_width(), fitted.get_height()), Vector2i(sprite_size, sprite_size),
		"a 48px frame must be normalised to %dpx — otherwise the player renders 1.5x the tile" % sprite_size)

	# Smaller too, or a 16px sheet would render half-size beside the procedural fallback.
	var small := Image.create(16, 16, true, Image.FORMAT_RGBA8)
	small.fill(Color(0, 1, 0, 1))
	var up: Image = player.call("_fit_to_sprite_size", small)
	assert_eq(Vector2i(up.get_width(), up.get_height()), Vector2i(sprite_size, sprite_size),
		"a 16px frame must also land at %dpx" % sprite_size)

	# ⛔ AND THE CONTROL: a frame ALREADY at SPRITE_SIZE must be returned untouched, or every
	# shipped 32px sheet pays a resize it does not need and the arms above pass on a no-op.
	var exact := Image.create(sprite_size, sprite_size, true, Image.FORMAT_RGBA8)
	exact.fill(Color(0, 0, 1, 1))
	var same: Image = player.call("_fit_to_sprite_size", exact)
	assert_eq(Vector2i(same.get_width(), same.get_height()), Vector2i(sprite_size, sprite_size),
		"a frame already at SPRITE_SIZE stays at SPRITE_SIZE")
	assert_eq(same.get_pixel(0, 0), Color(0, 0, 1, 1),
		"...and is returned unaltered — the fitted path must not touch a sheet that needs no fitting")

	# Aspect is preserved, foot-aligned: a WIDE frame keeps its shape rather than being squashed.
	var wide := Image.create(64, 32, true, Image.FORMAT_RGBA8)
	wide.fill(Color(1, 1, 0, 1))
	var w: Image = player.call("_fit_to_sprite_size", wide)
	assert_eq(Vector2i(w.get_width(), w.get_height()), Vector2i(sprite_size, sprite_size),
		"a non-square frame still lands on a square canvas")
	assert_eq(w.get_pixel(sprite_size / 2, sprite_size - 1), Color(1, 1, 0, 1),
		"...foot-aligned to the bottom, same baseline as the procedural sprite")
	assert_eq(w.get_pixel(sprite_size / 2, 0), Color(0, 0, 0, 0),
		"...with the headroom left transparent rather than the art stretched into it")


## ⛔ TURNING MUST NOT MOVE THE AVATAR — driven through a real node and read off the SPRITE.
##
## A sprite drawn off-centre in its cell and mirrored IN PLACE lands at the mirrored offset, so
## the left and right rows sit at different x inside the frame. `_sprite` is centred on the node,
## so that displacement is literal on-screen motion at a position that never changed. Measured
## 2026-09-16 on the systematic metric: 9 of 14 job sheets drift, worst 1.75px. Smaller than the
## roaming monsters' 4.0px, on the one sprite that is on screen for the entire run.
##
## 🔑 READ `_sprite.offset`, NOT THE OFFSETS DICT. The first version of the equivalent arm on
## RoamingMonster read the computed dictionary, so deleting the line that APPLIES it left the arm
## green — an arm that runs, asserts, and defends nothing (cowir-controller). The rendered offset
## is the subject.
func test_turning_does_not_move_the_avatar() -> void:
	const OWP := preload("res://src/exploration/OverworldPlayer.gd")
	var drifted := 0
	var probed := 0
	# EVERY job, not a sample. My first list was fighter/mage/cleric/rogue/bard/time_mage/
	# necromancer, and the two with real drift fall back to procedural so they were SKIPPED — the
	# five that loaded all spread under the tolerance, and the mutation passed.
	for job in ["fighter", "mage", "cleric", "rogue", "bard", "guardian", "ninja", "summoner",
			"speculator", "scriptweaver", "time_mage", "necromancer", "bossbinder", "skiptrotter"]:
		var player = OWP.new()
		player.current_job = job
		add_child_autofree(player)
		var sprite: Sprite2D = player.get_node_or_null("Sprite")
		if sprite == null:
			continue
		var cache: Dictionary = player.get("_sprite_cache")
		if not cache.has(OWP.OFFSETS_KEY):
			continue  # procedural fallback: no artist sheet for this job, nothing to correct
		probed += 1

		var placed := {}
		var raw := {}
		# ⛔ THE MEAN OVER FRAMES, matching what a per-row CONSTANT can remove. Sampling frame 0
		# alone measures the within-row stride variation too, and that reddened this arm on
		# correct code at 0.25px for fighter — the same mean-vs-per-frame distinction that made
		# cowir-adhoc's 29 and my 21 both right.
		for dir in (cache[OWP.OFFSETS_KEY] as Dictionary):
			var sum_raw := 0.0
			var sum_placed := 0.0
			var n := 0
			for f in OWP.WALK_FRAMES:
				player.set("current_direction", dir)
				player.set("_anim_frame", f)
				player.call("_update_sprite")
				var img: Image = (sprite.texture as Texture2D).get_image()
				var centre: float = player.call("_bbox_centre_x", img)
				if centre < 0.0:
					continue
				sum_raw += centre
				sum_placed += centre + sprite.offset.x
				n += 1
			if n == 0:
				continue
			raw[dir] = sum_raw / float(n)
			placed[dir] = sum_placed / float(n)

		assert_gt(placed.size(), 3, "%s: fewer than four directions rendered" % job)
		var lo := 1e9
		var hi := -1e9
		var rlo := 1e9
		var rhi := -1e9
		for dir in placed:
			lo = minf(lo, placed[dir])
			hi = maxf(hi, placed[dir])
			rlo = minf(rlo, raw[dir])
			rhi = maxf(rhi, raw[dir])
		if rhi - rlo >= 0.5:
			drifted += 1
		# The offsets are exact rather than rounded, so every direction must land ON the anchor.
		# A tolerance wide enough to admit rounding was wide enough to admit NO CORRECTION: the
		# first version allowed 1.01px and the mutation that deletes the offset passed under it.
		assert_almost_eq(hi - lo, 0.0, 0.01,
			("%s: after correction the directions still draw %.2fpx apart inside the frame, so the "
			+ "avatar slides sideways when it turns while its position is unchanged (uncorrected "
			+ "spread %.2fpx)") % [job, hi - lo, rhi - rlo])
	assert_gt(probed, 3, "ANTI-VACUITY: only %d jobs reached the artist-sheet path" % probed)
	assert_gt(drifted, 0,
		("ANTI-VACUITY: none of the probed jobs was off-centre at all, so the correction was proved "
		+ "on nothing — 9 of 14 job sheets drifted when this was written, worst 1.75px"))
