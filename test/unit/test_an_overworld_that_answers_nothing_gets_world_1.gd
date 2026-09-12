extends GutTest

## `GameLoop._derive_current_scene_music_key()` asks the live exploration scene which bed it wants,
## and when nothing answers it returns the literal `"overworld"` — World 1's key.
##
## ⛔ NOT ONE OF THE SIX OVERWORLD SCENES ANSWERED. The convention is BaseVillage's
## (`_get_music_area_id`), villages all carry it, and every overworld passed its key as a LITERAL to
## `play_area_music` in `_ready` instead — which serves entry and nothing else. Both callers of the
## deriver are RE-entry: `_stop_autogrind`, and the pause-menu restore when the snapshot was lost.
## So: grind in the Industrial overworld, stop the session, and World 1's bed comes back.
##
## 🔑 THIS IS NOT THE DISPATCHER'S `_:` ARM, and the distinction is the whole reason this file
## exists. @cowir-music's `.322` work makes an UNRECOGNISED area key compose its own world's bed.
## `"overworld"` is recognised — it has its own arm, which calls `_start_overworld_music`, which
## hardcodes `overworld_medieval`. A key that MATCHES an arm never reaches the default, so a
## world-aware default cannot see this one. Two fixes, two files, neither redundant.
##
## The floor arm below proves the floor is still W1's key rather than assuming it: if someone makes
## the deriver world-aware too, that arm reds and this file's premise gets re-read instead of quietly
## guarding nothing.

const WORLDS := {
	"res://src/exploration/OverworldScene.gd": ["overworld", "medieval"],
	"res://src/exploration/SuburbanOverworld.gd": ["overworld_suburban", "suburban"],
	"res://src/exploration/SteampunkOverworld.gd": ["overworld_steampunk", "steampunk"],
	"res://src/exploration/IndustrialOverworld.gd": ["overworld_industrial", "industrial"],
	"res://src/exploration/FuturisticOverworld.gd": ["overworld_futuristic", "digital"],
	"res://src/exploration/AbstractOverworld.gd": ["overworld_abstract", "abstract"],
}


## ⚠️ GameLoop is the MAIN SCENE's root node, NOT an autoload — there is no /root/GameLoop in a
## headless run, and looking for one sends both behaviour arms to pending, which reads as a pass.
## `.new()` does not run _ready, and the deriver only touches _exploration_scene and has_method.
func _game_loop() -> Node:
	return autofree(load("res://src/GameLoop.gd").new())


func _sound() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("SoundManager")


## What world does SoundManager think this area key belongs to? Its own vocabulary, asked directly.
func _suffix_for(sm: Node, key: String) -> String:
	var prior_area = sm._current_area
	var prior_suffix = sm._current_world_suffix
	sm._current_area = key
	var out: String = str(sm._get_current_world_suffix())
	sm._current_area = prior_area
	sm._current_world_suffix = prior_suffix
	return out


## THE REAL DERIVER, not a reimplementation of its three branches. The scene does not need to be
## built for this: the deriver only calls has_method and the method, neither of which needs _ready.
func test_every_overworld_tells_the_deriver_its_own_world() -> void:
	var gl := _game_loop()
	var sm := _sound()
	assert_not_null(sm, "PRECONDITION: SoundManager autoload")
	assert_true(gl != null and gl.has_method("_derive_current_scene_music_key"),
		"PRECONDITION: a bare GameLoop exposes the deriver — if this fails the arms below are vacuous")
	if gl == null or sm == null:
		return
	var prior_scene = gl._exploration_scene

	var wrong: Array = []
	var checked := 0
	for path in WORLDS:
		var want_key: String = WORLDS[path][0]
		var want_suffix: String = WORLDS[path][1]
		var scene = autofree(load(path).new())
		gl._exploration_scene = scene
		var key: String = str(gl._derive_current_scene_music_key())
		checked += 1
		var got_suffix: String = _suffix_for(sm, key)
		if key != want_key or got_suffix != want_suffix:
			wrong.append("%s -> key %s (world %s), wanted %s (%s)" % [
				str(path).get_file(), key, got_suffix, want_key, want_suffix])
	gl._exploration_scene = prior_scene
	wrong.sort()

	assert_eq(checked, WORLDS.size(), "swept %d of %d overworlds" % [checked, WORLDS.size()])
	assert_eq(wrong, [],
		"an overworld tells the music deriver the wrong world — on autogrind stop, or on a " +
		"pause-menu restore, that is another world's bed playing over this one: %s" % str(wrong))


## THE FLOOR, stated as behaviour. Without this the arm above is free: six scenes agreeing with
## themselves says nothing about what happens to a scene that does not answer.
func test_a_scene_that_answers_nothing_still_gets_world_1() -> void:
	var gl := _game_loop()
	var sm := _sound()
	assert_not_null(sm, "PRECONDITION: SoundManager autoload")
	assert_true(gl != null and gl.has_method("_derive_current_scene_music_key"),
		"PRECONDITION: a bare GameLoop exposes the deriver — if this fails the arms below are vacuous")
	if gl == null or sm == null:
		return
	var prior_scene = gl._exploration_scene
	var mute = autofree(Node2D.new())
	gl._exploration_scene = mute
	var key: String = str(gl._derive_current_scene_music_key())
	gl._exploration_scene = prior_scene

	assert_eq(key, "overworld",
		"the deriver's floor moved. It was the literal \"overworld\" — W1's key — which is why a " +
		"silent scene got World 1's bed. If the floor is world-aware now, re-read this file.")
	assert_eq(_suffix_for(sm, key), "medieval",
		"...and that floor resolves to MEDIEVAL, which is the defect: it is W1's bed, not a neutral one")


## ⚠️ A `#` INSIDE A STRING IS NOT A COMMENT, and my window has one: IndustrialOverworld's
## `_create_npc("Worker #4471", ...)`. A naive `find("#")` truncates that line and deletes real code
## from the scan. Harmless for a PRESENCE assert (a lost symbol reds loudly); silent and wrong for a
## BAN assert, where a forbidden name after the cut simply stops being seen. @cowir-music flagged the
## shape and measured their own window clean; mine was not.
func _comment_start(line: String) -> int:
	var in_double := false
	var in_single := false
	var i := 0
	while i < line.length():
		var c := line[i]
		if c == "\\":
			i += 2
			continue
		if c == "\"" and not in_single:
			in_double = not in_double
		elif c == "'" and not in_double:
			in_single = not in_single
		elif c == "#" and not in_double and not in_single:
			return i
		i += 1
	return -1

## ⛔ PROSE IS NOT CODE, and this scanner learned that by failing the experiment. @cowir-music
## 2026-09-12: a `#`-only strip leaves GDScript docstrings, which are string LITERALS, so a comment
## quoting a signature satisfies a presence assert. Run against this very file — real method deleted,
## `func _get_music_area_id` planted in a docstring — the arm below scored a CLEAN PASS while the
## behaviour arm above correctly redded. Backstopped, which is exactly why it was invisible.
## Split on the triple quote and keep the even pieces: inside/outside alternate, so the odd ones are
## the docstring bodies. `#` comments go after, never before — a docstring may legitimately contain one.
func _code(path: String) -> String:
	var raw := FileAccess.get_file_as_string(path)
	var out := ""
	var chunks: PackedStringArray = raw.split("\"\"\"")
	for i in range(chunks.size()):
		if i % 2 == 0:
			out += str(chunks[i])
	var stripped := ""
	for line in out.split("\n"):
		var l := str(line)
		var at := _comment_start(l)
		stripped += (l.substr(0, at) if at >= 0 else l) + "\n"
	return stripped


## SOURCE. The behaviour arms pass the moment a scene answers; this is what makes DELETING an
## answer red rather than silently sending that world back to the floor above.
func test_every_overworld_script_carries_the_method() -> void:
	var missing: Array = []
	for path in WORLDS:
		var src := _code(path)
		assert_gt(src.length(), 500, "CONTROL: %s is readable" % str(path).get_file())
		if not src.contains("func _get_music_area_id"):
			missing.append(str(path).get_file())
	missing.sort()
	assert_eq(missing, [],
		"an overworld dropped _get_music_area_id — it will fall to the deriver's \"overworld\" " +
		"floor and play World 1 on autogrind stop: %s" % str(missing))


## CONTROL FOR THE STRIPPER. Structural, not phrase-keyed: the previous version asserted that the
## literal "Castle Harmonia opens only after" was gone, which reds on a correct tree the moment
## somebody rewords that docstring — @cowir-battle's near-miss in the other direction. Anti-vacuity
## first, because "nothing survived" is free when there was nothing to remove. OverworldScene is the
## only one of the six carrying docstrings (2, measured), so it is the only valid subject here.
func test_the_stripper_actually_strips() -> void:
	var path := "res://src/exploration/OverworldScene.gd"
	var raw := FileAccess.get_file_as_string(path)
	# DERIVED from the file, not a phrase: chunk 1 of a split on the triple quote IS the first
	# docstring's body. Naming a phrase reds on a reword; asserting "no triple quote survives" is
	# WORSE — split() consumes its delimiter, so that holds for a BROKEN stripper too. Measured.
	var parts: PackedStringArray = raw.split("\"\"\"")
	assert_gte(parts.size(), 3,
		"ANTI-VACUITY: the scanned file holds no docstring, so nothing below is evidence")
	var body: String = str(parts[1])
	assert_gt(body.strip_edges().length(), 20,
		"ANTI-VACUITY: the first docstring is too short to tell a strip from a no-op")
	assert_true(raw.contains("#"),
		"ANTI-VACUITY: the scanned file holds no # comment, so the comment arm is free")

	var code := _code(path)
	assert_false(code.contains(body),
		"the first docstring's BODY survived _code() — prose is reaching the source arms as code")
	# NOT `code.contains("#")`: a `#` inside a string LEGITIMATELY survives now, so that assert would
	# red on a correct tree the moment a scanned file gains a "Worker #4471". Ask the property instead.
	var surviving_comments := 0
	for line in code.split("\n"):
		if _comment_start(str(line)) >= 0:
			surviving_comments += 1
	assert_eq(surviving_comments, 0,
		"%d line(s) still carry a comment after _code() — comments are reaching the source arms as code" % surviving_comments)
	assert_true(code.contains("func _get_music_area_id"),
		"CONTROL the other way: the stripper did NOT eat the real declaration")
	assert_true(code.contains("_place_readables"),
		"CONTROL: ordinary code outside any docstring survives")


## THE STRING-AWARE HALF, which is new logic and therefore owes its own arm. IndustrialOverworld is
## the live instance: `_create_npc("Worker #4471", ...)`. A naive strip cuts that line and silently
## deletes the rest of it from the scan.
func test_a_hash_inside_a_string_is_not_a_comment() -> void:
	assert_eq(_comment_start("var a = 1  # real comment"), 11, "a bare # starts a comment")
	assert_eq(_comment_start("_create_npc(\"Worker #4471\", \"villager\")"), -1,
		"a # inside a string is NOT a comment — cutting there deletes live code from the scan")
	assert_eq(_comment_start("var s = \"a\"  # after a closed string"), 13,
		"...and a # after the string closes still is one")
	var code := _code("res://src/exploration/IndustrialOverworld.gd")
	assert_true(code.contains("Worker #4471"),
		"the live instance must survive the strip intact")
	assert_true(code.contains("villager") and code.contains("MAP_SCALE"),
		"CONTROL: the code AFTER that # survives — the whole point of the string-aware scan")

## Every file this guard's stripper is pointed at — the source arm walks all six.
func _stripper_corpus() -> Array:
	return WORLDS.keys()


## ⛔ `"""` MEANS DOCUMENTATION ONLY UNTIL SOMEBODY ASSIGNS IT (@cowir-ai, via @cowir-music,
## 2026-09-12). In `DialoguePrompts` the triple-quoted regions are `AUTOBATTLE_GRAMMAR_DESCRIPTION`
## and friends — SHIPPING PROMPT TEXT. A blanket stripper there would delete the subject, and a guard
## reading it would be reading the product, not prose. My stripper is safe because every scanned file
## has ZERO assigned regions; that is a per-file property that can change in one commit, so it is
## asserted here rather than relied on.
func test_no_scanned_file_keeps_content_in_a_triple_quote() -> void:
	var offenders: Array = []
	var scanned := 0
	for path in _stripper_corpus():
		var raw := FileAccess.get_file_as_string(path)
		assert_gt(raw.length(), 200, "CONTROL: %s is readable" % str(path).get_file())
		scanned += 1
		for line in raw.split("\n"):
			var l := str(line)
			var q := l.find("\"\"\"")
			if q < 0:
				continue
			var before := l.substr(0, q).strip_edges()
			if (before.begins_with("const ") or before.begins_with("var ")) and before.ends_with("="):
				offenders.append("%s: %s" % [str(path).get_file(), l.strip_edges().substr(0, 60)])
	offenders.sort()
	assert_gt(scanned, 0, "CONTROL: the corpus is non-empty, or the zero below is free")
	assert_eq(offenders, [],
		"a scanned file ASSIGNS a triple-quoted region to a name — that is CONTENT, not a docstring, " +
		"and this file's stripper would delete the very thing a source arm is looking for: %s" % str(offenders))
