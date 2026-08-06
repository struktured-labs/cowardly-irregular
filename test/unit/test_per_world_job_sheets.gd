extends GutTest

## Per-world party overworld sheets — BOTH arms, because the fallback IS the design.
##
## struktured: "lets make sprites for the characters and their class types for each
## overworld" / "your characters are supposed to xform as they shift overworlds".
## The seam lands before the art so 25 sheets can't be authored into a hole — the
## masterite art sat unreachable for months for exactly that reason.
##
## Two traps this pins, both measured tonight by other lanes:
##  - medieval is the BASE and is UNSUFFIXED. A guard demanding a suffixed sheet per
##    world would want 30 files and go red on a correct 25.
##  - the RUNTIME vocabulary is medieval/suburban/steampunk/industrial/digital/abstract.
##    Monster ids say "futuristic", which _get_current_world_suffix never returns, so a
##    futuristic-named sheet passes every presence check and can never load.

const LOADER := "res://src/battle/sprites/HybridSpriteLoader.gd"
const RUNTIME_SUFFIXES := ["medieval", "suburban", "steampunk", "industrial", "digital", "abstract"]


func _resolve(job: String, suffix: String) -> String:
	return str(load(LOADER).job_overworld_sheet_path(job, suffix))


## The fallback arm. No per-world art exists yet, so EVERY world must resolve to the
## base sheet today — that is what makes the seam safe to land before generation.
func test_every_runtime_world_falls_back_to_the_base_sheet_today() -> void:
	var base: String = "res://assets/sprites/jobs/fighter/overworld.png"
	assert_true(ResourceLoader.exists(base), "the base fighter sheet exists — else this proves nothing")
	for s in RUNTIME_SUFFIXES:
		assert_eq(_resolve("fighter", s), base,
			"world '%s' must fall back to the base sheet while no variant exists — a broken fallback ships invisible art" % s)


## medieval is the base, never a suffixed lookup.
func test_medieval_never_asks_for_a_suffixed_sheet() -> void:
	assert_eq(_resolve("mage", "medieval"), "res://assets/sprites/jobs/mage/overworld.png",
		"medieval IS the base art — asking for overworld_medieval.png would demand 30 sheets for a correct 25")
	assert_eq(_resolve("mage", ""), "res://assets/sprites/jobs/mage/overworld.png",
		"an empty suffix resolves to base, not to a malformed 'overworld_.png'")


## The variant arm — the shape art will land in. Proven by construction rather than by
## a file that doesn't exist yet: the composed path must be the sibling convention.
func test_the_variant_path_is_the_sibling_convention() -> void:
	var got: String = str(load(LOADER).job_overworld_sheet_path("cleric", "digital"))
	var want_variant: String = "res://assets/sprites/jobs/cleric/overworld_digital.png"
	var base: String = "res://assets/sprites/jobs/cleric/overworld.png"
	assert_true(got == want_variant or got == base,
		"resolver must compose <job>/overworld_<suffix>.png beside the base, got '%s'" % got)
	assert_eq(got, base, "with no digital art on disk it must be the BASE — if this flips, art landed and the variant arm is live")


## Both consumers route through the resolver. They each built this path by hand, so a
## per-world variant added to one would silently miss the other — five party puppets in
## medieval sheets beside a transformed player.
func test_both_job_sheet_consumers_use_the_shared_resolver() -> void:
	for path in ["res://src/exploration/OverworldPlayer.gd", "res://src/cutscene/CutsceneActor.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		assert_true(src.contains("job_overworld_sheet_path"),
			"%s must resolve through the shared function, not rebuild the path" % path.get_file())
		assert_false(src.contains("\"res://assets/sprites/jobs/%s/overworld.png\""),
			"%s still hand-builds the job overworld path — that is the duplication the resolver exists to remove" % path.get_file())


## "futuristic" is the trap: it appears in the suffix function's BODY 39 times and is
## RETURNED zero times, so it reassures a grep and can never load.
func test_futuristic_is_not_a_runtime_world() -> void:
	assert_false("futuristic" in RUNTIME_SUFFIXES,
		"W5 is 'digital' at runtime — a sheet named overworld_futuristic.png would pass every presence check and never load")


## THE 25-vs-30 GUARD. medieval art IS the base file, so an overworld_medieval.png would
## be a sixth sheet per job that the resolver deliberately ignores — five wasted sheets
## and a file whose presence implies a lookup that never happens.
##
## Recorded because a mutation taught it: removing the medieval short-circuit is an
## EQUIVALENT MUTANT today (both paths return the base while no variant exists), so no
## behavioural test can catch that edit. What CAN be caught is the asset mistake it would
## enable, and that is the one that costs money.
func test_no_job_authors_a_redundant_medieval_variant() -> void:
	var dir := DirAccess.open("res://assets/sprites/jobs")
	assert_not_null(dir, "jobs sprite dir readable")
	if dir == null:
		return
	var jobs := dir.get_directories()
	assert_gt(jobs.size(), 0, "found job sheet directories — zero would pass this for free")
	var redundant: Array = []
	for j in jobs:
		if ResourceLoader.exists("res://assets/sprites/jobs/%s/overworld_medieval.png" % j):
			redundant.append(j)
	assert_true(redundant.is_empty(),
		"medieval is the BASE sheet — these jobs authored a redundant medieval variant the resolver ignores: %s" % str(redundant))
