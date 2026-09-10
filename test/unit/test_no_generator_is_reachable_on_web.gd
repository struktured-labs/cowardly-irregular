extends GutTest

## No music generator may be reachable on the web build without a shipped bed
## in front of it.
##
## This is the CLASS behind two separate fixes on 2026-09-10, generalised so the
## third one cannot ship. Both were the same shape: a starter whose only
## manifest tier names a bed the Web preset drops, falling through to per-sample
## GDScript on the main thread.
##
##     _start_battle_music  in W4-W6   ~8,550 ms   every battle transition
##     _start_abstract_music           19,951 ms   entering the W6 overworld
##     _start_boss_music    in W4-W6    ~2,150 ms
##     _start_industrial_battle_music   1,574 ms
##
## 🔑 NO DESKTOP RUN CAN SEE ANY OF IT. On desktop every starter's own bed is
## present, tier 1 hits, and no generator is ever entered. The defect exists
## only where a file is absent, and the only place that happens is the export.
## So the check has to be made of two static facts — the Web exclude_filter and
## the manifest — rather than of behaviour.
##
## THE RULE: a function that can reach `_generate_*` or
## `_create_and_play_looping_wav` must try at least one manifest key that
## SURVIVES the Web preset. Otherwise it must be listed below as unreachable —
## and that listing carries its trigger keys, which are themselves checked, so
## the exemption cannot be a bare assertion.
##
## ⚠️ THE EXEMPTIONS ARE PROVEN, NOT GRANTED. Each names the key(s) that route
## to it, and a key qualifies only if it either SHIPS (so play_music's manifest
## tier hits first and the `match` arm is never entered) or is ABSENT from the
## manifest (so play_music rewrites it to battle_<world> and the arm is never
## entered). If a trigger key ever becomes present-but-excluded, that function
## becomes reachable on web and this test goes red asking for a tier. That is
## the failure mode both real bugs had, so it is the one the exemption must not
## be able to hide.

const SM := "res://src/audio/SoundManager.gd"
const MANIFEST := "res://data/music_manifest.json"
const PRESETS := "res://export_presets.cfg"

const UNREACHABLE_BY_DESIGN := {
	"_start_rat_king_music": ["boss_rat_king"],
	"_start_cave_music": ["dungeon_medieval"],
	"_start_void_battle_music": ["battle_void"],
	"_start_monster_music": [
		"battle_slime", "battle_bat", "battle_mushroom", "battle_imp",
		"battle_goblin", "battle_skeleton", "battle_wolf", "battle_ghost",
		"battle_snake",
	],
}


func _web_music_patterns() -> Array[String]:
	var cfg: String = FileAccess.get_file_as_string(PRESETS)
	assert_gt(cfg.length(), 500, "SCOPE control: export_presets.cfg read back %d chars" % cfg.length())
	var web: int = cfg.find("name=\"Web\"")
	assert_gt(web, 0, "SCOPE control: no Web preset")
	var tail: String = cfg.substr(web, 4000)
	var i: int = tail.find("exclude_filter=\"")
	assert_gt(i, 0, "SCOPE control: Web preset has no exclude_filter")
	var filt: String = tail.substr(i + 16, tail.find("\"", i + 16) - i - 16)
	var out: Array[String] = []
	for p in filt.split(","):
		var t: String = p.strip_edges()
		if t.begins_with("assets/audio/music/"):
			out.append(t)
	return out


func _tracks() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(MANIFEST)
	assert_gt(raw.length(), 1000, "SCOPE control: manifest read back %d chars" % raw.length())
	return (JSON.parse_string(raw) as Dictionary).get("tracks", {})


## true only if the key has a file AND that file survives the Web preset.
func _ships(tracks: Dictionary, pats: Array[String], key: String) -> bool:
	var e: Variant = tracks.get(key, null)
	if not (e is Dictionary):
		return false
	var f: String = str((e as Dictionary).get("file", ""))
	if f == "":
		return false
	for p in pats:
		if f.match(p):
			return false
	return true


func _generators(src: String) -> Dictionary:
	## name -> the manifest keys it tries, for every _start_* that can generate.
	var out: Dictionary = {}
	var re := RegEx.new()
	re.compile("func (_start_[a-z_0-9]+)\\(")
	var hits: Array[RegExMatch] = re.search_all(src)
	for i in hits.size():
		var name: String = hits[i].get_string(1)
		var from: int = hits[i].get_start()
		var to: int = src.length() if i + 1 >= hits.size() else hits[i + 1].get_start()
		var body: String = src.substr(from, to - from)
		if not (body.contains("_create_and_play_looping_wav(") or body.contains("_generate_")):
			continue
		var keys: Array[String] = []
		var kre := RegEx.new()
		kre.compile("_try_play_from_manifest\\(\"([a-z_0-9]+)\"\\)")
		for m in kre.search_all(body):
			if not keys.has(m.get_string(1)):
				keys.append(m.get_string(1))
		out[name] = keys
	return out


func test_control_the_web_preset_still_drops_music() -> void:
	## The whole file is vacuous if it does not. Every arm would pass while
	## defending nothing, and the two real bugs would be shippable again.
	var pats: Array[String] = _web_music_patterns()
	assert_gt(pats.size(), 3,
		"the Web preset excludes %d music patterns — if this reached zero this file defends nothing and should be retired deliberately, not left green" % pats.size())
	var tracks: Dictionary = _tracks()
	assert_false(_ships(tracks, pats, "battle_industrial"),
		"CONTROL FAILED: battle_industrial reports as SHIPPING on web, but the preset drops *industrial* — the filter parse is wrong, so nothing below can detect anything")
	assert_true(_ships(tracks, pats, "battle_medieval"),
		"CONTROL FAILED: battle_medieval reports as EXCLUDED — the parse is over-matching and every arm below would demand impossible tiers")


func test_every_reachable_generator_has_a_shipped_bed_in_front_of_it() -> void:
	var src: String = FileAccess.get_file_as_string(SM)
	assert_gt(src.length(), 5000, "SCOPE control: SoundManager.gd read back %d chars" % src.length())
	var gens: Dictionary = _generators(src)
	assert_gt(gens.size(), 15,
		"SCOPE control: found only %d generating starters — the parse is broken and a green here would be vacuous" % gens.size())

	var pats: Array[String] = _web_music_patterns()
	var tracks: Dictionary = _tracks()
	var naked: Array[String] = []
	for name in gens.keys():
		if UNREACHABLE_BY_DESIGN.has(name):
			continue
		var covered: bool = false
		for k in gens[name]:
			if _ships(tracks, pats, str(k)):
				covered = true
				break
		if not covered:
			naked.append("%s (tries %s)" % [name, gens[name]])
	assert_eq(naked.size(), 0,
		"generators the web build can reach with no shipped bed in front (%d of %d): %s — on web these fall through to per-sample GDScript on the main thread, which measured 1.4s to 19.9s. Add a tier, or list it as unreachable WITH its trigger keys." % [naked.size(), gens.size(), naked])


func test_the_unreachable_exemptions_are_still_true() -> void:
	## An exemption that stops being true is worse than no exemption: it is a
	## reachable generator with a note saying not to look.
	var tracks: Dictionary = _tracks()
	var pats: Array[String] = _web_music_patterns()
	var broken: Array[String] = []
	var checked: int = 0
	for name in UNREACHABLE_BY_DESIGN.keys():
		for k in UNREACHABLE_BY_DESIGN[name]:
			checked += 1
			var key: String = str(k)
			var present: bool = tracks.has(key)
			## Absent from the manifest is fine: play_music rewrites it to
			## battle_<world> and the arm is never entered. Present-and-shipping
			## is fine: the manifest tier hits first. Present-and-EXCLUDED is the
			## failure — the arm becomes reachable on web with no bed behind it.
			if present and not _ships(tracks, pats, key):
				broken.append("%s <- %s" % [name, key])
	assert_gt(checked, 5,
		"SCOPE control: only %d trigger keys checked" % checked)
	assert_eq(broken.size(), 0,
		"exemptions that are no longer true (%d): %s — the trigger key is in the manifest but dropped from the web build, so play_music's manifest tier misses and the `match` arm IS entered. That generator now needs a shipped-bed tier like the others." % [broken.size(), broken])


func test_the_generator_walk_finds_the_two_that_were_actually_broken() -> void:
	## Positive control aimed at the real defects. If the walk stops seeing these
	## two names, it has stopped covering the class it was written for, and the
	## green above would mean nothing.
	var gens: Dictionary = _generators(FileAccess.get_file_as_string(SM))
	for name in ["_start_battle_music", "_start_abstract_music"]:
		assert_true(gens.has(name),
			"CONTROL FAILED: %s is no longer recognised as a generating starter — the parse has drifted off the functions this file exists for" % name)
