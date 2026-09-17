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

		# ⛔ ASSERT BEFORE ANYTHING THAT CAN ABORT. With _update_sprite stubbed to `return`, the
		# texture stays null and `(sprite.texture as Texture2D).get_image()` RAISES — so this arm
		# aborted at rung 1, asserted nothing, and scored Risky. run_tests.sh's EC=4 caught it;
		# the arm itself said nothing. A named failure beats a wrapper noticing the silence.
		player.set("current_direction", 0)
		player.set("_anim_frame", 0)
		player.call("_update_sprite")
		assert_not_null(sprite.texture,
			"%s: _update_sprite produced no texture, so it did not run and nothing below means anything" % job)
		if sprite.texture == null:
			continue

		var placed := {}
		var raw := {}
		var textures := {}
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
				textures[(sprite.texture as Texture2D).get_instance_id()] = true
				n += 1
			if n == 0:
				continue
			raw[dir] = sum_raw / float(n)
			placed[dir] = sum_placed / float(n)

		assert_gt(placed.size(), 3, "%s: fewer than four directions rendered" % job)
		# ⛔ LIVENESS, ASSERTED HERE RATHER THAN BORROWED. Every quantity below is read AFTER
		# _update_sprite, so a no-op version returns the same texture and the same offset for all
		# four directions — spread 0, which is what PERFECT CORRECTION looks like. Measured: stub
		# _update_sprite to `return` and this arm PASSED; only a sibling arm's precondition
		# reddened. cowir-controller's shape — a still cursor is ambiguous between "broken" and
		# "the handler early-returned", so the arm that owns the property must prove it ran.
		assert_gt(textures.size(), 1,
			("%s: every direction drew the SAME texture object, so _update_sprite did not run and "
			+ "the agreement below is between four copies of one value") % job)
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


## ⛔ THE PLAYER'S FACING ROWS COME FROM THE DECLARATION, like the roaming monsters'.
##
## OverworldPlayer hardcoded [DOWN, LEFT, RIGHT, UP] while RoamingMonster read its rows from the
## manifest. All 53 shipped sheets use that order today, so nothing renders wrong — the ASYMMETRY
## is the defect: one consumer deriving and one guessing disagree only for the sheet that would
## have needed the fix, which is cowir-cutscenes' rule and the reason I went looking.
func test_the_players_walk_rows_come_from_the_manifest() -> void:
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	assert_true(m is Dictionary, "sprite_manifest.json must parse")
	var node: Dictionary = (m as Dictionary).get("overworld_player_sheets", {})
	assert_gt(node.size(), 10, "ANTI-VACUITY: only %d player sheets declared" % node.size())

	var checked := 0
	for job in node:
		var anims = (node[job] as Dictionary).get("animations", {})
		if not (anims is Dictionary) or anims.is_empty():
			continue
		var rows: Dictionary = Loader.overworld_player_rows(str(job))
		for name in anims:
			if not rows.has(name):
				continue
			assert_eq(int(rows[name]), int((anims[name] as Dictionary).get("row", -1)),
				"%s's %s row must come from its declaration, not from a constant" % [job, name])
			checked += 1
	assert_gt(checked, 40, "ANTI-VACUITY: only %d declared rows were compared" % checked)

	# An unregistered job keeps the convention — absence must never refuse a sheet.
	var fallback: Dictionary = Loader.overworld_player_rows("__no_such_job__")
	assert_eq(int(fallback["walk_left"]), 1, "an unregistered job keeps the documented row order")
	assert_eq(int(fallback["walk_up"]), 3, "...including the up row")


## ⚠️ AND THE SOURCE HALF, because the accessor being CORRECT does not mean the consumer CALLS it.
## The behavioural arm above cannot tell the two apart: every shipped sheet declares the same
## order the constant encoded, so a player still reading the constant passes it. Same shape as the
## roaming-monster guard — the proof is a PAIR, and this is the half that discriminates.
func test_the_player_no_longer_carries_a_hardcoded_row_order() -> void:
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var code: String = GdSource.code_of("res://src/exploration/OverworldPlayer.gd")
	assert_gt(code.length(), 1000, "PRECONDITION: OverworldPlayer must be readable and stripped")
	assert_true(code.contains("HybridSpriteLoader.overworld_player_rows("),
		"the row order must be read from the manifest owner")
	assert_false(code.contains("[Direction.DOWN, Direction.LEFT, Direction.RIGHT, Direction.UP]"),
		"the hardcoded row order is the constant this change replaced")


## ⛔ EVERY CONSUMER THAT PICKS A WALK ROW MUST ASK THE MANIFEST — and the corpus is DERIVED, which
## is the whole point of this arm.
##
## I fixed RoamingMonster, then OverworldPlayer, and reported the pattern "consistent across
## monsters and player". It was not. Deriving the corpus by four different spellings found SIX
## files picking a sheet row; I had looked at TWO. OverworldNPC carried a hardcoded match, and
## WanderingNPC was worse than hardcoded — `_current_dir` WAS the row index, coupled by nothing
## but a trailing comment, at two sites (the frame key and the heavy-top density lookup, which is
## keyed by row). Fixing one of those two would have nudged the wrong direction's headroom.
##
## 🔑 cowir-controller's root cause, arrived at the same evening on menus: THE INSTRUMENT AND THE
## WORK HAD THE SAME BLIND SPOT, so the instrument could not report it. Their ledger searched for
## the pattern their conversions used; my search was the two files I was already editing. A
## hand-listed corpus can only confirm what you already looked at.
##
## ⚠️ THE DISCRIMINATOR IS SHEET RESOLUTION, NOT ROW ARITHMETIC. `row * frame_h` also appears in
## MapleCommunityCenterInterior, which draws a decorative photo wall and consumes no sheet at all.
## Requiring a file to obtain an overworld sheet PATH keeps it out without naming it.
func test_every_overworld_sheet_consumer_reads_its_rows_from_the_manifest() -> void:
	const GdSource := preload("res://test/unit/helpers/gd_source.gd")
	var resolves := ["npc_overworld_path(", "overworld_frame_size(", "monsters/overworld/"]
	var owners := ["overworld_walk_rows(", "overworld_player_rows(", "overworld_monster_geometry("]

	var consumers: Array = []
	var offenders: Array = []
	var stack: Array[String] = ["res://src"]
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		var d := DirAccess.open(cur)
		if d == null:
			continue
		d.list_dir_begin()
		var n := d.get_next()
		while n != "":
			var full: String = "%s/%s" % [cur, n]
			if d.current_is_dir():
				if not n.begins_with("."):
					stack.append(full)
			elif n.ends_with(".gd"):
				var code: String = GdSource.code_of(full)
				var gets_sheet := false
				for r in resolves:
					if code.contains(r):
						gets_sheet = true
				# Slicing BY ROW is what makes row order matter; a whole-sheet load does not.
				var slices := code.contains("_frame.y") or code.contains("FRAME_H") \
					or code.contains("frame_h") or code.contains("_ARCHETYPE_FRAME_H")
				if gets_sheet and slices:
					consumers.append(full)
					var asks := false
					for o in owners:
						if code.contains(o):
							asks = true
					if not asks:
						offenders.append(full)
			n = d.get_next()
		d.list_dir_end()

	consumers.sort()
	offenders.sort()
	assert_gt(consumers.size(), 2,
		("ANTI-VACUITY: only %d sheet-slicing consumers were derived. The extraction is broken, and "
		+ "an empty corpus reports a clean repo: %s") % [consumers.size(), consumers])
	assert_eq(offenders, [],
		("a file resolves an overworld sheet and slices it BY ROW without asking the manifest which "
		+ "row is which. Every shipped sheet uses the same order today, so it renders correctly and "
		+ "nothing fails — until one declares a different order, at which point this consumer faces "
		+ "the wrong way while the others do not: %s") % [offenders])


## ⛔ MUTATION 7, ON MY OWN LEDGER. The arm above checks a consumer CALLS the rows owner. Keep the
## call and DISCARD its answer — `var rows := …` then a hardcoded match — and every guard I had
## stayed green: 10 · 3 · 7, EC=0. A source arm cannot tell a used answer from an ignored one.
##
## 🔑 AND A REAL SHEET CANNOT DISCRIMINATE EITHER, which is why the order is INJECTED. All 53 ship
## the same order, so a consumer ignoring the declaration renders identically to one obeying it.
## The proof needs an order no sheet declares — the roaming-monster facing arm's shape.
##
## ⚠️ NO TEST-ONLY FIELD. The sliced row is read back out of the PIXELS: each row of the fixture
## carries its own index as a red value, so the arm observes what was drawn rather than what the
## node recorded about itself.
func test_an_npc_renders_the_row_its_declaration_names() -> void:
	const NPC := preload("res://src/exploration/OverworldNPC.gd")
	var npc = NPC.new()
	add_child_autofree(npc)
	var sprite: Sprite2D = npc.get("sprite")
	assert_not_null(sprite, "PRECONDITION: the NPC must have built a sprite node")

	# Each row tagged with its own index at the frame's top-left pixel.
	var sheet := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for r in 4:
		sheet.set_pixel(0, r * 32, Color(float(r) / 8.0, 0.0, 0.0, 1.0))
	npc.set("_archetype_sheet", sheet)
	# An order NO shipped sheet declares, or a consumer ignoring the declaration would pass.
	npc.set("_archetype_rows", {"walk_down": 2, "walk_left": 3, "walk_right": 0, "walk_up": 1})

	var cases := {0: 2, 1: 1, 2: 3, 3: 0}  # facing_direction -> the row its declaration names
	for facing in cases:
		npc.set("facing_direction", facing)
		npc.call("_apply_facing")
		var drawn: Image = (sprite.texture as Texture2D).get_image()
		var got := int(roundf(drawn.get_pixel(0, 0).r * 8.0))
		assert_eq(got, int(cases[facing]),
			("facing %d must slice the row its DECLARATION names (%d), not the one the convention "
			+ "would give (%d) — a consumer that calls the owner and ignores its answer renders "
			+ "correctly on every shipped sheet and wrongly on the first one that differs")
			% [facing, cases[facing], got])


## The same proof for the WANDERING npc, whose exposure was the worst of the three: `_current_dir`
## used to BE the row index, so "uses the declaration" and "ignores it" were the same code.
func test_a_wandering_npc_shows_the_row_its_declaration_names() -> void:
	const WNPC := preload("res://src/exploration/WanderingNPC.gd")
	var npc = WNPC.new()
	add_child_autofree(npc)
	var sprite: Sprite2D = npc.get("_sprite")
	assert_not_null(sprite, "PRECONDITION: the wandering NPC must have built a sprite node")

	# One tagged texture per (row, col), so the drawn frame names its own row.
	var frames := {}
	for r in 4:
		for c in 4:
			var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
			img.fill(Color(float(r) / 8.0, 0.0, 0.0, 1.0))
			frames["%d_%d" % [r, c]] = ImageTexture.create_from_image(img)
	npc.set("_archetype_frames", frames)
	# An order no shipped sheet declares. Index i is this file's direction i (0=down, 1=left,
	# 2=right, 3=up); the value is the row that direction must draw.
	npc.set("_dir_to_row", PackedInt32Array([2, 3, 0, 1]))
	npc.set("_anim_frame", 0)

	for dir in 4:
		npc.set("_current_dir", dir)
		npc.call("_update_archetype_frame")
		var drawn: Image = (sprite.texture as Texture2D).get_image()
		var got := int(roundf(drawn.get_pixel(0, 0).r * 8.0))
		var want := int(PackedInt32Array([2, 3, 0, 1])[dir])
		assert_eq(got, want,
			("direction %d must draw row %d as its declaration says, not row %d as the old "
			+ "dir-IS-the-row coupling gave") % [dir, want, dir])


## ⛔ THE SECOND ROUTE. test_turning_does_not_move_the_avatar only exercises the ARTIST path, so
## it says nothing about the procedural fallback — and a consequence arm is scoped to a ROUTE, not
## to a feature (cowir-autogrind, whose end-to-end arm covered one of two selection paths).
##
## ⚠️ AND NO SHIPPED JOB REACHES THAT FALLBACK. All 14 have jobs/<id>/overworld.png, measured
## 2026-09-16, so the procedural branch in _generate_all_sprites is unreachable for real content
## and can only be driven by an id with no sheet. Stated because "untested" and "unreachable" are
## different claims and the arm below would otherwise read as covering live behaviour.
##
## 🔑 THE ROUTE THAT MATTERS IS THE TRANSITION. Procedural frames are generated centred, so a
## correction derived from artist art must not survive onto them — and `_static_sprite_cache`
## persists across instances, so a stale offset would misplace a sprite that needs none.
func test_leaving_the_artist_path_clears_the_registration_offset() -> void:
	const OWP := preload("res://src/exploration/OverworldPlayer.gd")
	var player = OWP.new()
	player.current_job = "time_mage"
	add_child_autofree(player)
	var sprite: Sprite2D = player.get_node_or_null("Sprite")
	assert_not_null(sprite, "PRECONDITION: the player must have built a sprite node")

	var cache: Dictionary = player.get("_sprite_cache")
	assert_true(cache.has(OWP.OFFSETS_KEY),
		"PRECONDITION: time_mage must reach the ARTIST path, or this proves nothing about leaving it")

	# ⛔ LEAVE THE SPRITE CARRYING A NON-ZERO OFFSET. Iterating and stopping wherever the dictionary
	# happens to end left it on a direction whose offset was 0, so the "cleared" assert below was
	# satisfied by a value that had never been set — the mutation that stops clearing PASSED.
	var worst_dir = null
	var biggest := 0.0
	for dir in (cache[OWP.OFFSETS_KEY] as Dictionary):
		player.set("current_direction", dir)
		player.call("_update_sprite")
		if absf(sprite.offset.x) > biggest:
			biggest = absf(sprite.offset.x)
			worst_dir = dir
	assert_gt(biggest, 0.0,
		"PRECONDITION: time_mage must apply a non-zero offset, or the clear below is vacuous")
	player.set("current_direction", worst_dir)
	player.call("_update_sprite")
	assert_almost_eq(absf(sprite.offset.x), biggest, 0.001,
		"PRECONDITION: the sprite must be LEFT carrying that offset, or nothing needs clearing")

	# An id with no sheet is the only way to reach the procedural branch.
	player.call("set_job", "__no_such_job__")
	assert_false((player.get("_sprite_cache") as Dictionary).has(OWP.OFFSETS_KEY),
		"PRECONDITION: an unknown job must fall back to procedural")
	for dir in 4:
		player.set("current_direction", dir)
		player.call("_update_sprite")
		assert_almost_eq(sprite.offset.x, 0.0, 0.001,
			("a procedural frame is generated CENTRED, so a correction derived from artist art must "
			+ "not survive the switch — direction %d still carries %.2fpx") % [dir, sprite.offset.x])
