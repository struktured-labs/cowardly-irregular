extends GutTest

## Every terrain the game can emit must reach a bed that EXISTS.
##
## `_get_terrain_battle_track` had two arms naming beds that are not manifest keys —
## `battle_urban` (emitted by nothing, so unreachable) and `battle_void` (emitted by
## AbstractOverworld, and reaching the right bed only by FALLTHROUGH: play_music rewrites an
## unknown `battle_*` to `battle_<world suffix>`). Neither had a symptom. Both were an arm claiming
## a dedicated bed that does not exist, and `abstract` is the inverse — no arm at all, landing on
## battle_abstract because the terrain name happens to equal the world suffix, which nothing stated.
## Handed over with evidence by cowir-music (msg 10472) and re-measured here rather than adopted.
##
## The arms are now honest. This pins the property instead of the arm list, so a terrain added
## without a bed reds on the day it is added rather than playing silence for a release.

const BS := "res://src/battle/BattleScene.gd"
const GL := "res://src/GameLoop.gd"
const SM := "res://src/audio/SoundManager.gd"


func _manifest_keys() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/music_manifest.json"))
	assert_not_null(parsed, "CONTROL: the music manifest parses")
	var out: Dictionary = {}
	var stack: Array = [parsed]
	while stack.size() > 0:
		var node = stack.pop_back()
		if node is Dictionary:
			for k in (node as Dictionary).keys():
				out[str(k)] = true
				stack.append((node as Dictionary)[k])
		elif node is Array:
			for v in node:
				stack.append(v)
	assert_gt(out.size(), 50, "CONTROL: the manifest read non-empty (%d keys)" % out.size())
	return out


## Every terrain string the game can produce: the map-id table, plus the terrain a scene hands to
## battle_triggered. Derived, because a hand-list is what let `urban` sit here unreachable.
func _emittable_terrains() -> Array:
	var out: Dictionary = {}
	var gl: String = FileAccess.get_file_as_string(GL)
	var start: int = gl.find("func _get_terrain_for_map")
	assert_gt(start, -1, "CONTROL: the map-id terrain table exists")
	var body: String = gl.substr(start, gl.find("\nfunc ", start + 10) - start)
	var re := RegEx.new()
	re.compile("return \"([a-z_]+)\"")
	for m in re.search_all(body):
		out[m.get_string(1)] = true
	## The other emitter shape: a scene naming the terrain as it triggers the fight.
	var emit_re := RegEx.new()
	emit_re.compile("battle_triggered\\.emit\\([^)]*\"([a-z_]+)\"\\s*\\)")
	for path in ["res://src/exploration/AbstractOverworld.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		for m in emit_re.search_all(src):
			out[m.get_string(1)] = true
	var list: Array = out.keys()
	list.sort()
	assert_gt(list.size(), 10, "CONTROL: the terrain vocabulary read non-empty (%s)" % str(list))
	for known in ["plains", "abstract", "void"]:
		assert_true(list.has(known),
			"CONTROL: '%s' must be in the derived vocabulary or the derivation is broken" % known)
	return list


func test_no_terrain_arm_names_a_bed_that_does_not_exist() -> void:
	## The defect, stated as a property. An arm exists to name a DEDICATED bed; naming one that is
	## not in the manifest is a promise the manifest cannot keep, and it fails SILENTLY because the
	## unknown-key rewrite quietly substitutes the world bed.
	var keys := _manifest_keys()
	var scene = load(BS).new()
	autofree(scene)
	var liars: Array = []
	var specific: int = 0
	for terrain in _emittable_terrains():
		scene._current_terrain = terrain
		var track: String = scene._get_terrain_battle_track()
		if track == "battle":
			continue  # the generic path, covered by its own arm below
		specific += 1
		if not keys.has(track):
			liars.append("%s -> %s" % [terrain, track])
	assert_gt(specific, 2, "CONTROL: some terrains DO claim a dedicated bed (%d) — without this the "
		% specific + "arm passes by finding nothing to check")
	assert_eq(liars.size(), 0,
		"a terrain arm names a bed the manifest does not have; it plays the world bed instead and "
		+ "nothing says so: " + str(liars))


func test_the_generic_path_resolves_for_every_world() -> void:
	## Every terrain without a dedicated arm returns "battle", which play_music rewrites to
	## `battle_<world suffix>`. That is only correct while every suffix HAS such a bed — otherwise
	## the fallthrough the arms above rely on lands on nothing.
	var keys := _manifest_keys()
	var sm: String = FileAccess.get_file_as_string(SM)
	var start: int = sm.find("func _get_current_world_suffix")
	assert_gt(start, -1, "CONTROL: the world-suffix function exists")
	var body: String = sm.substr(start, sm.find("\nfunc ", start + 10) - start)
	var re := RegEx.new()
	re.compile("return \"([a-z]+)\"")
	var suffixes: Dictionary = {}
	for m in re.search_all(body):
		suffixes[m.get_string(1)] = true
	assert_gt(suffixes.size(), 3, "CONTROL: world suffixes read non-empty (%s)" % str(suffixes.keys()))
	var missing: Array = []
	for s in suffixes.keys():
		if not keys.has("battle_%s" % s):
			missing.append("battle_%s" % s)
	assert_eq(missing.size(), 0,
		"a world has no generic battle bed, so every arm-less terrain there falls through to "
		+ "nothing: " + str(missing))


func test_the_dropped_arms_stay_dropped_while_their_beds_do_not_exist() -> void:
	## Bidirectional, so this cannot outlive its reason: if someone authors battle_void.ogg, the
	## right move is to restore the arm, and this arm reds to say so rather than leaving the
	## terrain quietly on the generic bed.
	var keys := _manifest_keys()
	var src: String = FileAccess.get_file_as_string(BS)
	var start: int = src.find("func _get_terrain_battle_track")
	assert_gt(start, -1, "CONTROL: the terrain track function exists")
	var body: String = _code_only(src.substr(start, src.find("\nfunc ", start + 10) - start))
	## CONTROL for the stripper — STRUCTURAL, not phrase-keyed (@cowir-music, msg 10585). My first
	## version asserted a specific sentence was gone, which goes vacuous the moment anyone rewords
	## the comment: green because the phrase left, not because the stripper works. That is the same
	## fragility as a guard passing only because prose used backticks where the assert wanted quotes.
	## ANTI-VACUITY first: the window must actually CONTAIN both forms, or stripping proves nothing.
	var ctrl_raw: String = src.substr(src.find("func _get_terrain_battle_track"), 1200)
	assert_true(ctrl_raw.contains("#"), "ANTI-VACUITY: the control window must hold a # comment")
	assert_true(ctrl_raw.contains("\"\"\""), "ANTI-VACUITY: and a docstring")
	var ctrl: String = _code_only(ctrl_raw)
	assert_false(ctrl.contains("#"), "no # comment may survive the strip")
	assert_false(ctrl.contains("\"\"\""), "no docstring may survive the strip")
	for pair in [["void", "battle_void"], ["urban", "battle_urban"]]:
		var bed: String = pair[1]
		if keys.has(bed):
			assert_true(body.contains("\"%s\"" % bed),
				"%s now EXISTS — give %s its arm back instead of leaving it on the world bed" % [bed, pair[0]])
		else:
			assert_false(body.contains("\"%s\"" % bed),
				"%s is not a manifest key, so an arm naming it promises a bed nothing can play" % bed)


## Source with BOTH comment forms removed. `#` lines and trailing `#`, AND `"""` blocks — GDScript
## docstrings are string LITERALS, so a `#`-only strip leaves prose that names a token and a scan
## reads that prose as the token (cowir-music, msg 10577). Not used on arms that deliberately read
## a string CONSTANT, where stripping would delete the very thing being checked.
## ⚠️ KNOWN LIMIT, measured not assumed: a triple quote that is neither at the start nor the end of
## its line — `var s := """x"""` — is NOT dropped, because the branch keys on begins_with. Across the
## four files these guards scan there are 419 triple-quote lines and ZERO of that shape, so nothing
## is exposed today; and it fails LOUDLY where it matters, since a survivor inside a control window
## reds the structural assert rather than passing quietly. The `#` half truncates at the first `#`,
## so a `#` inside a string literal would cut live code — same measurement, same direction.
##
## Both halves are verified INDEPENDENTLY (@cowir-overworld's tautology note via @cowir-music, msg
## 10590): removing only the docstring branch reds "no docstring may survive", removing only the `#`
## strip reds "no # comment may survive". A pass-through neutering kills both at once and cannot
## tell a real assert from one that merely restates the implementation.
func _code_only(src: String) -> String:
	var out := PackedStringArray()
	var in_doc := false
	for line in src.split("\n"):
		var t := line.strip_edges()
		if in_doc:
			if t.ends_with("\"\"\""):
				in_doc = false
			continue
		if t.begins_with("\"\"\""):
			if not (t.length() > 5 and t.ends_with("\"\"\"")):
				in_doc = true
			continue
		var h: int = line.find("#")
		out.append(line.substr(0, h) if h >= 0 else line)
	return "\n".join(out)
