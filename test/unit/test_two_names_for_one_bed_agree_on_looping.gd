extends GutTest

## `music_manifest.json` lets several keys name ONE file — `battle_brute.ogg` is named by five under
## the monster-family ruling. `load()` returns ONE cached AudioStream per path, so
## `_try_play_from_manifest`'s `stream.loop = should_loop` writes an object every one of those keys shares,
## and that any player already holding it is playing.
##
## ⛔ SO A LOOP FLAG IS A PROPERTY OF THE FILE AT RUNTIME WHILE THE MANIFEST AUTHORS IT PER KEY.
## Add one alias with `loop: false` — or a `stinger_`-prefixed alias, which the force-override makes
## false whatever the manifest says — and the last key played decides whether the OTHER four loop.
## The bed then ends in silence with nothing in the manifest looking wrong: the key that was played
## says `loop: true` and the entry that broke it is somewhere else in the file.
##
## Zero violations today: 161 distinct files, 1 named by more than one key, all 5 keys agreeing.
## This is the guard for the authoring step, not a report of a live defect.
##
## 🔑 THE CORPUS IS THE FILE ON DISK, AND THAT IS ONLY THE RIGHT CORPUS BECAUSE THE RUNTIME KEY SET
## IS THE SAME SET. Measured, because a corpus keyed to where data LIVES cannot answer a question
## about how it COMES INTO EXISTENCE: `_music_manifest` has ONE writer (`= parsed["tracks"]`, a
## verbatim assignment), `_load_music_manifest` synthesizes no keys, there are zero reflection
## writes to it, and nothing in `src/` mutates an entry. Runtime ids built by concatenation
## (`"village_" + suffix`) must already be in the manifest to play, so they are a subset.

const MANIFEST_PATH := "res://data/music_manifest.json"


func _tracks() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(MANIFEST_PATH)
	assert_gt(raw.length(), 1000, "SCOPE control: the manifest read back %d chars" % raw.length())
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "the manifest did not parse as a Dictionary")
	if not (parsed is Dictionary):
		return {}
	return (parsed as Dictionary).get("tracks", {})


## The two ways SoundManager decides it, in its order: a stinger is forced false at :2062.
func _resolved_loop(key: String, entry: Dictionary) -> bool:
	if bool(entry.get("stinger", key.begins_with("stinger_"))):
		return false
	return bool(entry.get("loop", true))


## ⛔ THE ARM THAT MAKES THE DATA ARM LOAD-BEARING. Without the sharing there is nothing wrong with
## two keys disagreeing, and the guard below would be pedantry about a JSON file. Measured, not
## assumed: I expected a per-player copy.
func test_one_path_is_one_shared_stream_object() -> void:
	var path := "res://assets/audio/music/battle_brute.ogg"
	var a := load(path) as AudioStream
	var b := load(path) as AudioStream
	assert_not_null(a, "SCOPE control: %s did not load, so this arm drives nothing" % path)
	if a == null or b == null:
		return
	assert_eq(a.get_instance_id(), b.get_instance_id(),
		"two load()s of one path returned DIFFERENT objects — the aliasing premise is gone and the guard below is about nothing")

	var player := AudioStreamPlayer.new()
	add_child_autofree(player)
	player.stream = a
	var restore: bool = bool(a.loop)
	a.loop = not restore
	var seen_b: bool = bool(b.loop)
	var seen_player: bool = bool(player.stream.loop)
	a.loop = restore
	assert_eq(seen_b, not restore,
		"a write through one handle was NOT visible through the other — load() is no longer sharing, so a per-key loop flag is safe")
	assert_eq(seen_player, not restore,
		"a write through the resource was NOT visible through a player already holding it")
	assert_eq(bool(a.loop), restore,
		"the fixture was left FLIPPED — battle_brute.ogg is cached with the wrong loop flag for every later test in this process")


func test_every_alias_of_one_file_resolves_to_the_same_loop() -> void:
	var tracks: Dictionary = _tracks()
	assert_gt(tracks.size(), 100,
		"SCOPE control: only %d tracks — the walk broke and a green here would be about nothing" % tracks.size())

	var keys_by_file: Dictionary = {}
	for k in tracks.keys():
		var entry = tracks[k]
		if not (entry is Dictionary):
			continue
		var f: String = str((entry as Dictionary).get("file", ""))
		if f == "":
			continue
		if not keys_by_file.has(f):
			keys_by_file[f] = []
		keys_by_file[f].append(str(k))

	var shared: Array[String] = []
	var disagreeing: Array[String] = []
	for f in keys_by_file.keys():
		var ks: Array = keys_by_file[f]
		if ks.size() < 2:
			continue
		shared.append(str(f).get_file())
		var resolved: Dictionary = {}
		for k in ks:
			resolved[_resolved_loop(str(k), tracks[k])] = true
		if resolved.size() > 1:
			var detail: Array[String] = []
			for k in ks:
				detail.append("%s=%s" % [str(k), str(_resolved_loop(str(k), tracks[k]))])
			disagreeing.append("%s (%s)" % [str(f).get_file(), ", ".join(detail)])

	## ANTI-VACUITY: the property only exists while some file HAS two names. Retire the aliases and
	## this arm passes by construction, saying nothing — which is the shape that would let the next
	## alias land unguarded.
	assert_gt(shared.size(), 0,
		"ANTI-VACUITY: no file in the manifest is named by more than one key, so nothing here can fail — either the monster-family aliases were retired (delete this guard and say so) or the walk stopped matching")

	assert_eq(disagreeing, [],
		"two keys naming ONE file resolve to DIFFERENT loop flags: %s — load() hands both the same AudioStream, so whichever plays last decides whether the other loops, and a bed authored `loop: true` ends in silence with nothing in its own entry looking wrong" % str(disagreeing))
