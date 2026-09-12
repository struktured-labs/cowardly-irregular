extends GutTest

## Data-driven boss/monster music routing (2026-09-06).
##
## Before this, a boss theme required a hardcoded `elif boss_type == ...`
## arm in BattleScene. Two bosses had one (rat king, Mordaine); the other
## 18 — all four elemental dragons, castle_warden, the_calibrant, every
## Spotlight Duel miniboss — shared the generic boss_<world> bed. Monster
## variants had the same problem one level down: giant_bat fell through to
## battle_<world> while battle_bat sat shipped and unused.
##
## monsters.json `music_track` now outranks every derived key on both
## paths. These arms guard the contract, not the implementation: a
## music_track naming a track that does not exist is silent at runtime
## (SoundManager falls back to generic), so only a test can catch it.

const MONSTERS := "res://data/monsters.json"
const MANIFEST := "res://data/music_manifest.json"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


func _json(p: String) -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(p)
	assert_gt(raw.length(), 1000, "SCOPE control: %s read back %d chars" % [p, raw.length()])
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "%s must parse to a Dictionary" % p)
	return parsed as Dictionary


func test_every_declared_music_track_resolves_to_real_audio() -> void:
	var mons: Dictionary = _json(MONSTERS)
	var tracks: Dictionary = _json(MANIFEST).get("tracks", {})
	assert_gt(tracks.size(), 100, "SCOPE control: manifest carries %d tracks" % tracks.size())

	var declared: int = 0
	var broken: Array[String] = []
	for mid in mons.keys():
		var rec: Variant = mons[mid]
		if not (rec is Dictionary):
			continue
		var key: String = str((rec as Dictionary).get("music_track", ""))
		if key == "":
			continue
		declared += 1
		var entry: Variant = tracks.get(key, null)
		if entry == null:
			broken.append("%s -> %s (no manifest entry)" % [mid, key])
			continue
		var f: String = str((entry as Dictionary).get("file", ""))
		if f == "":
			broken.append("%s -> %s (manifest entry has no file key)" % [mid, key])
		elif not FileAccess.file_exists("res://" + f):
			broken.append("%s -> %s (file missing: %s)" % [mid, key, f])

	assert_gt(declared, 0, "SCOPE control: no monster declares music_track — the walk found nothing to check")
	assert_eq(broken.size(), 0,
		"music_track keys that do not resolve to shipped audio (%d): %s — this is SILENT at runtime, SoundManager just plays the generic world bed" % [broken.size(), broken])


func test_the_bosses_with_their_own_theme_still_have_real_audio() -> void:
	var tracks: Dictionary = _json(MANIFEST).get("tracks", {})
	## struktured asked whether Mordaine shipped; these are the dedicated beds.
	for key in ["boss_mordaine", "boss_rat_king", "boss_medieval"]:
		assert_true(tracks.has(key), "%s vanished from the manifest" % key)
		var f: String = str((tracks[key] as Dictionary).get("file", ""))
		assert_ne(f, "", "%s has no file key — it would silently fall back to procedural" % key)
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes("res://" + f)
		assert_gt(bytes.size(), 50000, "%s read back only %d bytes — LFS pointer or truncated" % [key, bytes.size()])
		assert_eq(bytes.slice(0, 4), "OggS".to_ascii_buffer(), "%s is not Ogg audio" % key)


func test_declared_track_outranks_the_derived_key_in_source() -> void:
	## The helper is useless if the derived arms are still checked first.
	##
	## ⛔ READS CODE, NOT PROSE ABOUT IT. This arm was raw `contains`/`find` until 2026-09-12.
	## Measured: delete the boss path's call, name it in an EARLIER docstring -> fully GREEN,
	## with monsters.json themes ignored on the boss path. Two other placements DID red, and
	## that was positional luck rather than detection — the order assert only fires when the
	## prose happens to sit after the masterite arm.
	var src: String = GdSource.code_of("res://src/battle/BattleScene.gd")
	var doc: String = str(GdSource.split(FileAccess.get_file_as_string("res://src/battle/BattleScene.gd"))["doc"])
	assert_gt(src.length(), 1000, "SCOPE control: BattleScene.gd read back %d chars of code" % src.length())
	assert_gt(src.count("func "), 50,
		"CONTROL: only %d func headers survived the strip — over-stripping and a real absence look identical below" % src.count("func "))
	assert_gt(doc.length(), 1000,
		"CONTROL: only %d chars of docstring split off — the strip did nothing, so prose still answers every assert below" % doc.length())

	assert_true(src.contains("func _declared_music_track"), "the _declared_music_track helper is gone")
	assert_true(src.contains("_declared_music_track(dominant_monster)"), "the non-boss path no longer consults the declared track — variants fall back to battle_<world>")

	## Anchor on the CALL, not the variable name: a mutant that kept
	## `var declared_boss` but stubbed it to "" passed an earlier version
	## of this guard while the routing was dead.
	var declared_at: int = src.find("_declared_music_track(boss_type)")
	var masterite_at: int = src.find("elif masterite_type != \"\"")
	assert_gt(declared_at, -1, "the boss path no longer CALLS _declared_music_track(boss_type)")
	assert_gt(masterite_at, -1, "the masterite arm is gone — this guard's anchor is stale, re-derive it")
	assert_lt(declared_at, masterite_at,
		"the declared-track check must precede the masterite arm, otherwise a Masterite can never override its per-role bed")


## Three rows, because the parity flip fails in TWO directions and one row cannot fail for both:
## real code leaves the code half AND prose enters it. @cowir-sprites measured these against the
## real scanner and inverted each to prove it fires; the prose row is the one a "does the code
## survive" instinct leaves out, and it is the only one that catches a leak in the GOOD order.
func test_a_fence_hidden_in_a_comment_does_not_flip_parity() -> void:
	var q: String = "\"\"\""
	var haz: String = "func a():\n\t# see the %s block below\n\tvar x = 1\n\t%sdoc naming FOO%s\n\tvar y = 2" % [q, q, q]
	var code: String = str(GdSource.split(haz)["code"])
	assert_true(code.contains("var x = 1"), "a %s inside a # comment must not flip parity — var x survives" % q)
	assert_true(code.contains("var y = 2"), "...and neither does var y")
	assert_false(code.contains("doc naming FOO"), "...and the PROSE never enters the code half")


## ⛔ PIN THE HELPER, NOT THE CORPUS (this lane's rule, earned across four lanes): six stripper
## costumes broke in one afternoon and each fix was blind to the next. A case table answers all
## of them in milliseconds and reds on the seventh.
func test_the_source_helper_itself() -> void:
	var cases: Array = [
		["var a = 1  # play_music(\"x\")", "var a = 1  ", "a trailing comment goes"],
		["var s = \"# not a comment\"", "var s = \"# not a comment\"", "a # inside a string stays"],
		["var s = \"a \\\" # b\"", "var s = \"a \\\" # b\"", "an escaped quote does not end the string"],
		## The removed region leaves a newline behind on purpose: joining the surviving halves
		## bare would glue `a"""b` into `ab` and invent a token neither side wrote.
		["func f():\n\t\"\"\"names play_music(\"x\")\"\"\"\n\tvar b = 2", "func f():\n\t\n\n\tvar b = 2", "a docstring region goes, leaving a separator"],
		["var keep = \"play_music\"", "var keep = \"play_music\"", "a real literal survives — it IS the consumer"],
	]
	for c in cases:
		assert_eq(GdSource.split(str(c[0]))["code"], str(c[1]), str(c[2]))
