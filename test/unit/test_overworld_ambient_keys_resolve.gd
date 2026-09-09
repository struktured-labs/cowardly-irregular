extends GutTest

## Every ambient key the overworld asks for must exist in the SFX manifest (2026-09-09).
##
## OverworldScene maps a terrain zone to an ambient key and calls
## SoundManager.play_ambient(key). play_ambient returns EARLY and SILENTLY on
## a key the manifest lacks — no warning, no error, no sound. A zone with a
## typo'd or retired key is indistinguishable from a zone deliberately left
## quiet, and the overworld is where the player spends most of their time.
##
## This is the shape three lanes shipped the same day: a consumer naming
## something the data does not carry (cowir-battle's shared animation buckets,
## cowir-sfx's 185 abilities falling through, my own ice_wolf reaching no bed).
## Nothing errored in any of them.
##
## Checked at the time of writing: all 7 zones resolve. The guard exists so a
## renamed or dropped key cannot go quiet unnoticed.
##
## The key list is PARSED FROM THE CONSUMER rather than copied here, so it
## tracks OverworldScene instead of drifting from it — a hardcoded copy would
## keep passing after someone adds an eighth zone.

const CONSUMER := "res://src/exploration/OverworldScene.gd"
const SFX_MANIFEST := "res://data/sfx_manifest.json"


func test_every_requested_ambient_key_exists() -> void:
	var src: String = FileAccess.get_file_as_string(CONSUMER)
	assert_gt(src.length(), 1000, "SCOPE control: OverworldScene.gd read back %d chars" % src.length())

	var re := RegEx.new()
	assert_eq(re.compile('ambient_key = "([^"]+)"'), OK, "SCOPE control: pattern did not compile")
	var requested: Array[String] = []
	for m in re.search_all(src):
		var k: String = m.get_string(1)
		if not requested.has(k):
			requested.append(k)
	assert_gt(requested.size(), 3,
		"SCOPE control: parsed only %d ambient keys from the consumer — the regex is stale and a green would be vacuous" % requested.size())

	var raw: String = FileAccess.get_file_as_string(SFX_MANIFEST)
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "sfx_manifest.json did not parse")
	var sounds: Dictionary = (parsed as Dictionary).get("sfx", {})
	## The root key is `sfx`, not `sounds` — reading the wrong one returns an
	## empty set and every key reads as missing, which is a confident wrong
	## finding rather than an error. Control below is what catches that.
	assert_gt(sounds.size(), 100, "SCOPE control: sfx manifest walked %d entries — wrong root key?" % sounds.size())
	assert_true(sounds.has("ambient_forest"),
		"CONTROL FAILED: a known-present key reads as absent, so this probe cannot tell missing from present")
	assert_false(sounds.has("ambient_definitely_not_real"),
		"CONTROL FAILED: a fabricated key reads as present, so this probe passes everything")

	var missing: Array[String] = []
	for k in requested:
		if not sounds.has(k):
			missing.append(k)
			continue
		var f: String = str((sounds[k] as Dictionary).get("file", ""))
		if f == "" or not FileAccess.file_exists(f if f.begins_with("res://") else "res://" + f):
			missing.append("%s (entry present, file %s)" % [k, f])

	assert_eq(missing.size(), 0,
		"overworld zones request ambient keys the SFX manifest cannot serve (%d): %s — play_ambient returns silently on a miss, so the zone is just quiet and nothing reports it" % [missing.size(), missing])
