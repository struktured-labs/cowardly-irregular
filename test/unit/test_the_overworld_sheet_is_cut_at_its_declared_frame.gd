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
