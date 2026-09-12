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
		var at := l.find("#")
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
	assert_false(code.contains("#"),
		"a # survived _code() — comments are reaching the source arms as if they were code")
	assert_true(code.contains("func _get_music_area_id"),
		"CONTROL the other way: the stripper did NOT eat the real declaration")
	assert_true(code.contains("_place_readables"),
		"CONTROL: ordinary code outside any docstring survives")
