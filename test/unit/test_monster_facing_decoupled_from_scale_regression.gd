extends GutTest

## Two bugs in one day, one root cause: frame size silently meant TWO unrelated
## things — how big to draw a monster, AND which way it faces.
##
##   cave_rat_king         a 256px sheet authored facing LEFT rendered backwards
##                         in battle (struktured, 2026-07-25: "I saw a rat sprite
##                         backwards in battle")
##   chancellor_mordaine   re-exported 256px -> 128px purely to gain the scale
##                         bump; that ALSO reversed her facing. It renders right
##                         only because she happens to be drawn facing left
##                         (caught at fold review 2026-07-26)
##
## The second is the dangerous one and the reason for this test. A resolution
## change is a SIZING decision. It must not be able to reverse a monster's facing
## as a side effect, with every check green, and be discovered by a player.
##
## So facing is DECLARED (manifest "flip_h") and only falls back to the frame-size
## convention. These assert the two decisions are genuinely independent — which a
## source read cannot tell you, because the old code produced correct output while
## conflating them.
##
## Note the shape: nothing here needs an allowlist or a suppression flag. The
## correct state today passes clean.

const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const SMALL := 128


func test_scale_bump_is_decided_by_frame_size_alone() -> void:
	assert_true(Loader.monster_needs_scale_bump(128, SMALL), "128px is at the threshold — bump")
	assert_true(Loader.monster_needs_scale_bump(64, SMALL), "smaller than threshold — bump")
	assert_false(Loader.monster_needs_scale_bump(256, SMALL), "256px proc-gen scale — no bump")
	assert_false(Loader.monster_needs_scale_bump(0, SMALL), "a zero/absent frame must not bump")


func test_declared_facing_overrides_the_frame_size_convention_in_both_directions() -> void:
	# cave_rat_king is the live case: 256px (convention says "don't flip") but
	# authored facing left, so the manifest declares flip_h true.
	assert_true(
		Loader.monster_faces_party("cave_rat_king", false),
		"cave_rat_king declares flip_h — the declaration must beat the frame-size convention, "
		+ "or it renders facing away from the party again"
	)
	# And the reverse direction must work too, or the mechanism only fixes one
	# of the two ways a sheet can be drawn wrong.
	assert_true(
		Loader.monster_faces_party("cave_rat_king", true),
		"a declared facing must not depend on what the convention happened to say"
	)


func test_undeclared_sheets_still_follow_the_convention() -> void:
	# The fallback must remain intact — 90-odd sheets rely on it and none of them
	# should need to declare anything.
	assert_true(Loader.monster_faces_party("__no_such_monster__", true),
		"an undeclared sheet takes the convention default (small frame -> flip)")
	assert_false(Loader.monster_faces_party("__no_such_monster__", false),
		"an undeclared sheet takes the convention default (large frame -> no flip)")


func test_a_resolution_change_cannot_silently_reverse_a_declared_facing() -> void:
	# THE regression. Simulate Mordaine's re-export: same monster, frame height
	# changes 256 -> 128, which flips the convention default. A declared facing
	# must be unmoved by that.
	var big_default := Loader.monster_needs_scale_bump(256, SMALL)   # false
	var small_default := Loader.monster_needs_scale_bump(128, SMALL) # true
	assert_ne(big_default, small_default,
		"precondition: the convention default really does invert across the threshold")

	var before := Loader.monster_faces_party("cave_rat_king", big_default)
	var after := Loader.monster_faces_party("cave_rat_king", small_default)
	assert_eq(before, after,
		"re-exporting a DECLARED monster at a different resolution changed its facing — "
		+ "a sizing decision must never reverse facing as a side effect")


func test_both_battle_sites_use_the_facing_helper_not_a_local_rule() -> void:
	# Battle-start and summon must agree; a summoned monster facing the wrong way
	# while its battle-start twin is correct is the parity bug this replaced.
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_eq(src.count("HybridSpriteLoader.monster_faces_party("), 2,
		"exactly two flip sites (battle-start + summon) must resolve facing through the helper")
	assert_eq(src.count("HybridSpriteLoader.monster_needs_scale_bump("), 2,
		"and both must take sizing from the sizing helper, so neither can drift back into one boolean")


func test_declared_flip_entries_are_explained() -> void:
	# A bare "flip_h": true is a magic value; the next person needs to know the
	# sheet is drawn against convention and why. Requires the DELIVERABLE (the
	# note), never permission to skip — you can't silence this green.
	var raw := FileAccess.get_file_as_string("res://data/sprite_manifest.json")
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "sprite_manifest must parse")
	var sheets: Dictionary = parsed.get("monster_sheets", {})
	var undocumented: Array = []
	for mid in sheets:
		var e = sheets[mid]
		if e is Dictionary and e.has("flip_h") and str(e.get("flip_h_reason", "")) == "":
			undocumented.append(mid)
	assert_eq(undocumented, [],
		"every sheet declaring flip_h must also carry flip_h_reason saying which way it is "
		+ "authored and why it differs from the frame-size convention: %s" % [undocumented])


## ⛔ THE SAME BUG, ON A SECOND SURFACE, SEVEN WEEKS LATER (2026-09-16). Everything above pins
## the OWNER and the two battle sites. The bestiary drew its own conclusion from frame height
## — its comment even said "mirror BattleScene's rule" — and mirrored the FALLBACK without the
## DECLARATION, so cave_rat_king faced one way in the fight and the other way in the menu.
##
## The arms below ask the question of the corpus instead of a named pair, because "which files
## decide a facing" is not a list anyone can keep current.
const BESTIARY := "res://src/ui/BestiaryMenu.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## A line that names one of these is reading a FRAME SIZE. That is the owner's fallback
## argument and never a facing decision on its own.
const HEIGHT_TOKENS: Array[String] = ["get_height()", ".size.y", "frame_height"]

## Monster ids are `<base>_<world>` for the 25 re-dressed sheets. Kept explicit: deriving it as
## "any id whose prefix is also an id" reads cave_rat_king as cave_rat + "king", and cave_rat_king
## is the one entry that declares a facing — the derivation would flag the very row it exists for.
const WORLD_SUFFIXES: Array[String] = ["suburban", "steampunk", "industrial", "digital", "abstract", "futuristic"]


func _monster_sheets() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	assert_true(parsed is Dictionary, "sprite_manifest.json must parse")
	return (parsed as Dictionary).get("monster_sheets", {}) if parsed is Dictionary else {}


func _gd_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var dirs: Array[String] = [root]
	while not dirs.is_empty():
		var cur: String = dirs.pop_back()
		var d := DirAccess.open(cur)
		if d == null:
			continue
		d.list_dir_begin()
		var n := d.get_next()
		while n != "":
			var full: String = cur.path_join(n)
			if d.current_is_dir():
				if not n.begins_with("."):
					dirs.append(full)
			elif n.ends_with(".gd"):
				out.append(full)
			n = d.get_next()
		d.list_dir_end()
	return out


## Regression: struktured's 2026-07-25 "I saw a rat sprite backwards in battle", re-opened in the
## bestiary. The anti-vacuity arm is the load-bearing one — if every declaration ever agrees with
## the convention again, a surface using the convention alone looks right and this guards nothing.
func test_the_bestiary_shows_the_face_the_battle_shows() -> void:
	var sheets := _monster_sheets()
	assert_gt(sheets.size(), 50, "ANTI-VACUITY: only %d monster sheets — wrong corpus" % sheets.size())
	var would_reverse: Array = []
	for mid in sheets:
		var e: Dictionary = sheets[mid]
		if not e.has("flip_h"):
			continue
		var h: int = int(e.get("frame_height", 0))
		var convention: bool = h > 0 and h <= SMALL
		if Loader.monster_faces_party(str(mid), convention) != convention:
			would_reverse.append(mid)
	assert_gt(would_reverse.size(), 0,
		"ANTI-VACUITY: every declared facing now agrees with the frame-size convention, so a surface "
		+ "reading frame height alone would still look correct — check whether this guard still earns its place")
	var code: String = GdSource.code_of(BESTIARY)
	assert_ne(code, "", "PRECONDITION: %s must be readable" % BESTIARY)
	assert_true(code.contains("monster_faces_party("),
		"the bestiary must resolve facing through the owner — without it these render reversed in the "
		+ "menu while the fight has them right: %s" % [would_reverse])


## The class, not the instance: ANY file may draw a monster, and any of them can re-derive the
## convention. A facing decision that reads a frame size must hand that size to the owner.
func test_no_surface_decides_a_facing_from_a_frame_height_alone() -> void:
	var files := _gd_files("res://src")
	assert_gt(files.size(), 100,
		"ANTI-VACUITY: only %d .gd files walked — a short corpus finds no offender by construction" % files.size())
	var assignments: int = 0
	var offenders: Array = []
	for path in files:
		for raw in GdSource.code_of(path).split("\n"):
			var line: String = str(raw)
			if not line.contains("flip_h") or not line.contains("="):
				continue
			assignments += 1
			var reads_a_size: bool = false
			for t in HEIGHT_TOKENS:
				if line.contains(t):
					reads_a_size = true
			if reads_a_size and not line.contains("monster_faces_party("):
				offenders.append("%s: %s" % [path.get_file(), line.strip_edges()])
	assert_gt(assignments, 8,
		"ANTI-VACUITY: only %d flip_h expressions seen across src/ — the stripper or the walk is eating them" % assignments)
	assert_eq(offenders, [],
		"a facing is being decided from a frame size without the owner, which is how a re-export "
		+ "reverses a monster as a side effect: %s" % [offenders])


## The re-dressed sheets are worn by id `<base>_<world>` but BattleScene resolves facing from the
## BASE id, so a declaration on the variant row is read by nothing. Declaring it there is not a
## smaller version of declaring it — it is silence that looks like a decision.
##
## 20 of the 25 have no base row at all (the masterites ship dressed-only), so for those the
## engine asks an id that is not in the manifest and takes the convention. Requiring the base to
## exist would have excluded exactly the rows where a declaration is most thoroughly ignored.
func test_a_world_variant_cannot_declare_a_facing_the_engine_never_reads() -> void:
	var sheets := _monster_sheets()
	var variants: int = 0
	var unread: Array = []
	for mid in sheets:
		var id: String = str(mid)
		var base: String = ""
		for s in WORLD_SUFFIXES:
			if id.ends_with("_" + s):
				base = id.substr(0, id.length() - s.length() - 1)
		if base == "":
			continue
		variants += 1
		if (sheets[mid] as Dictionary).has("flip_h"):
			unread.append("%s declares flip_h but battle asks '%s'" % [id, base])
	assert_gt(variants, 20,
		"ANTI-VACUITY: only %d world-variant sheets found — the suffix vocabulary no longer matches the data" % variants)
	assert_eq(unread, [],
		"a world variant's facing is never read — drop it, or teach the variant lookup to resolve "
		+ "facing from the sheet it actually wore: %s" % [unread])


## ⛔ THE END-TO-END ARM, and the reason the two source arms above are not enough: they pass on
## any file that merely MENTIONS the owner. This drives the real menu and reads back the facing
## the player would see, so a rewrite that keeps the call and drops its answer still reds.
func test_the_bestiary_really_renders_the_declared_facing() -> void:
	var menu: Node = load("res://src/ui/BestiaryMenu.gd").new()
	add_child_autofree(menu)
	await wait_frames(3)
	var spr = menu.get("_detail_sprite")
	assert_ne(spr, null, "PRECONDITION: the bestiary must build its detail sprite")
	if spr == null:
		return

	# Seed the WRONG answer first — without this the arm passes on a call that never ran.
	spr.flip_h = false
	menu.call("_load_sprite", "cave_rat_king")
	assert_true(spr.visible, "PRECONDITION: cave_rat_king's sheet must load, or nothing was decided")
	assert_true(spr.flip_h,
		"the bestiary drew cave_rat_king facing the opposite way to the fight — its declared flip_h was ignored")

	# Controls BOTH WAYS, or the fix reads as a blanket flip. cave_rat is the king's undeclared
	# 256px sibling (convention: no flip); slime is 128px (convention: flip).
	spr.flip_h = true
	menu.call("_load_sprite", "cave_rat")
	assert_true(spr.visible, "PRECONDITION: cave_rat's sheet must load")
	assert_false(spr.flip_h,
		"an undeclared 256px sheet must still follow the convention — the owner is not a flip switch")

	spr.flip_h = false
	menu.call("_load_sprite", "slime")
	assert_true(spr.visible, "PRECONDITION: slime's sheet must load")
	assert_true(spr.flip_h,
		"an undeclared 128px sheet must still get the convention's flip — the owner must not swallow the fallback")


## ⛔ THE SAME SILENT-PASS EXPOSURE AS THIS LANE'S ROAMING-MONSTER GUARD, measured on this file
## 2026-09-16 before this arm existed — rename `_load_sprite` away and the run reports:
##
##     EC=0 · Passing 10 · Failing 0 · no Risky line · Asserts 32 -> 26
##
## The end-to-end arm asserts, then drives a method that no longer exists, then aborts. GUT scores
## it Passing; `run_tests.sh`'s exit 4 fires only when a test asserted NOTHING, so it cannot see
## this rung at all (cowir-ai, 2026-09-16).
##
## ⚠️ AND THE OTHER HALF OF THIS FILE WAS ALREADY COVERED BY ACCIDENT, which is why only the method
## needs a floor: renaming `_detail_sprite` reds at EC=1, because the end-to-end arm seeds the wrong
## answer and asserts the sprite exists BEFORE using it. That PRECONDITION is a floor I wrote for a
## different reason — to stop the arm passing on a call that never ran — and it happens to cover the
## property reach too. The method reach had no such guard.
##
## 🔑 Derived from this file's own text, `has_method` because it ANSWERS rather than raising, and
## inline rather than shared — see the retirement condition on the roaming-monster copy.
func test_every_method_this_guard_drives_by_name_exists() -> void:
	var own_src := FileAccess.get_file_as_string("res://test/unit/test_monster_facing_decoupled_from_scale_regression.gd")
	assert_gt(own_src.length(), 500,
		"VOID: this guard could not read its own source, so the name list below is empty by construction")
	var re := RegEx.new()
	re.compile('\\.call\\("([a-zA-Z_][a-zA-Z_0-9]*)"')
	var names := {}
	for m in re.search_all(own_src):
		names[m.get_string(1)] = true
	assert_gt(names.size(), 0,
		"VOID: no `.call(\"name\")` found in this file's own text — the extraction is broken, not the subject")

	var subject: Node = load(BESTIARY).new()
	add_child_autofree(subject)
	var missing: Array = []
	for n in names:
		if not subject.has_method(str(n)):
			missing.append(str(n))
	missing.sort()
	assert_eq(missing, [],
		("this guard drives the bestiary BY NAME and those methods are gone, so the end-to-end arm "
		+ "would ABORT INTO A SILENT PASS — EC=0, nothing failing, nothing risky: %s") % [missing])
