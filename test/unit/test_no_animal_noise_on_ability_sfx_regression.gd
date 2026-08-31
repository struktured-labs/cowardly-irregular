extends GutTest

## struktured 2026-08-30, playing v3.33.214-alpha: "the cure sfx with the bird chirp is crap ...
## it literally says like a bird chirp actually not figuratively, no animal noises for ability
## sounds (unless its applicable)".
##
## heal.ogg was a literal bird recording. The manifest PROMPT asked for "gentle wind chimes in a
## warm breeze" — the generator returned a bird and nobody listened before wiring it. It was the
## cue BattleScene plays when a heal LANDS (play_battle("heal")), so every Cure in the game ended
## on a chirp, and ItemsMenu/InnInterior played it too.
##
## MEASURED, so the numbers here are evidence rather than adjectives (FFT, 1024-sample frames,
## frames below 0.005 RMS skipped):
##   heal.ogg           mean peak 9380 Hz   93.9% of energy >4 kHz   <- the bird
##   heal_v3.ogg        mean peak 5953 Hz   80.5%
##   w2_ability_heal    mean peak 8826 Hz   86.9%
##   w3_ability_heal    mean peak 9875 Hz   82.9%
##   heal_v2.ogg        mean peak  999 Hz    9.2%   <- warm, and matched in loudness (0.246/0.259)
##   ability_heal.ogg   mean peak  425 Hz    8.4%   <- the cast, already warm
##
## This pins the ROUTING, not the audio: a test cannot hear a bird, but it can refuse the exact
## files measured to be one. If a replacement lands, repoint the key and update the reject list —
## do not silence this by widening it.

const MANIFEST := "res://data/sfx_manifest.json"

## Files measured as shrill/animal-like. A heal cue must never resolve to one of these.
const REJECTED_FOR_HEAL := ["heal.ogg", "heal_v3.ogg", "ability_heal_v2.ogg"]

## Keys that play when healing happens, in battle or out.
const LIVE_HEAL_KEYS := ["heal", "ability_heal", "w2_ability_heal", "w3_ability_heal"]


func _manifest() -> Dictionary:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	assert_not_null(f, "CONTROL: the sfx manifest must be readable")
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}


func _entry(key: String) -> Dictionary:
	var stack: Array = [_manifest()]
	while not stack.is_empty():
		var n = stack.pop_back()
		if not (n is Dictionary):
			continue
		var nd: Dictionary = n
		if nd.has(key) and nd[key] is Dictionary:
			return nd[key]
		for k in nd:
			stack.append(nd[k])
	return {}


func test_the_manifest_is_readable_and_populated() -> void:
	# CONTROL: every assertion below reads through _entry, so a dead walk would pass them all.
	assert_false(_manifest().is_empty(), "manifest must parse")
	assert_false(_entry("ability_heal").is_empty(), "CONTROL: a known-present key must resolve")
	assert_true(_entry("no_such_sfx_key_xyz").is_empty(), "CONTROL: an absent key must NOT resolve")


func test_no_live_heal_cue_resolves_to_a_measured_bird() -> void:
	# THE load-bearing assertion. heal -> heal.ogg is the exact wiring he heard.
	var offenders: Array = []
	var checked := 0
	for key in LIVE_HEAL_KEYS:
		var e := _entry(key)
		if e.is_empty():
			continue
		checked += 1
		# get_file() so the compare is on the BASENAME. `ends_with` is wrong here and passed
		# review: "ability_heal.ogg".ends_with("heal.ogg") is TRUE, so the warm sample the fix
		# points AT was reported as the bird it replaced.
		var base: String = str(e.get("file", "")).get_file()
		if REJECTED_FOR_HEAL.has(base):
			offenders.append("%s -> %s" % [key, base])
	assert_eq(checked, LIVE_HEAL_KEYS.size(),
		"CONTROL: inspected %d of %d heal keys — a shortfall means the walk missed one" % [checked, LIVE_HEAL_KEYS.size()])
	assert_eq(offenders, [], "heal cues resolving to a file measured as a bird chirp: %s" % [offenders])


func test_every_live_heal_cue_points_at_a_file_that_exists() -> void:
	# A repoint that typos the path resolves to nothing and the cue goes SILENT — which reads as
	# "fixed" to anyone checking that the chirp is gone.
	var missing: Array = []
	for key in LIVE_HEAL_KEYS:
		var e := _entry(key)
		if e.is_empty():
			continue
		var f: String = str(e.get("file", ""))
		assert_ne(f, "", "%s must declare a file" % key)
		if not ResourceLoader.exists("res://" + f.trim_prefix("res://")):
			missing.append("%s -> %s" % [key, f])
	assert_eq(missing, [], "heal cues pointing at a nonexistent file: %s" % [missing])


func test_the_repointed_world_cues_landed_on_the_warm_sample() -> void:
	# Named explicitly: these two were birds and now share the cast's warm sample via the
	# manifest rather than via play_ability's fallback, so the intent is visible in the data.
	for key in ["w2_ability_heal", "w3_ability_heal"]:
		var e := _entry(key)
		assert_false(e.is_empty(), "%s must still exist in the manifest" % key)
		assert_eq(str(e.get("file", "")).get_file(), "ability_heal.ogg",
			"%s must resolve to the warm cast sample" % key)
