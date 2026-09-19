extends GutTest

## A looping bed that begins with silence replays that silence on every wrap: the bed ends at full
## level, drops out, and fades back in. Measured across all 146 runtime-looping beds (ffmpeg, 22050
## Hz mono, threshold 200/32768): 44 carry >=10 ms of lead silence, 22 >=20 ms, 6 >=50 ms, worst
## `credits_industrial` at 1214 ms. Trail silence is ~0 on nearly all of them, so the wrap is
## loud -> gap -> fade-in rather than a smooth join.
##
## `loop_offset` is the conservative repair: it moves only where a WRAP restarts and never touches
## the first play, so an opening silence that was authored on purpose still plays once. No audio
## asset is modified — regenerating music is struktured's call and this changes none of it.
##
## The six declared here are the >=50 ms cases. The 16 between 20 and 50 ms are left undeclared
## deliberately: audibility there is a judgement, and a guard that pinned them would be asserting
## my taste. This arm pins the MECHANISM plus the entries that exist.

const MANIFEST := "res://data/music_manifest.json"
const NO_OFFSET_BED := "overworld_medieval"

var _restore: Dictionary = {}
var _planted_key: String = ""
var _planted_had: bool = false


func after_each() -> void:
	## ⛔ loop_offset is written onto the SHARED cached AudioStream, so a value left behind is
	## cross-file poison for any later test that loads the same path. Captured, not assumed 0.0.
	for path in _restore.keys():
		var s = load(path)
		if s != null and "loop_offset" in s:
			s.loop_offset = float(_restore[path])
	_restore.clear()
	if _planted_key != "" and SoundManager != null:
		var e = SoundManager._music_manifest.get(_planted_key, null)
		if e is Dictionary and not _planted_had:
			(e as Dictionary).erase("loop_offset")
	_planted_key = ""
	if SoundManager != null:
		SoundManager.stop_music()


func _tracks() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(parsed is Dictionary, "the music manifest did not parse")
	if not (parsed is Dictionary):
		return {}
	var t = (parsed as Dictionary).get("tracks", {})
	return t if t is Dictionary else {}


func _offset_keys(tracks: Dictionary) -> Array:
	var out: Array = []
	for k in tracks.keys():
		var e = tracks[k]
		if e is Dictionary and (e as Dictionary).has("loop_offset"):
			out.append(str(k))
	out.sort()
	return out


func test_a_declared_offset_reaches_the_stream() -> void:
	if SoundManager == null:
		assert_true(false, "SoundManager autoload unavailable — this arm would prove nothing")
		return
	var tracks := _tracks()
	var keys := _offset_keys(tracks)
	## ANTI-VACUITY: with no declared offsets the arm passes by finding nothing to drive.
	assert_gt(keys.size(), 0,
		"ANTI-VACUITY: no manifest entry declares loop_offset, so this arm drives nothing")
	SoundManager._load_music_manifest()
	var key: String = keys[0]
	var want: float = float((tracks[key] as Dictionary)["loop_offset"])
	var path: String = str((tracks[key] as Dictionary).get("file", ""))
	if not path.begins_with("res://"):
		path = "res://" + path
	var pre = load(path)
	if pre != null and "loop_offset" in pre:
		_restore[path] = pre.loop_offset
	assert_true(SoundManager._try_play_from_manifest(key),
		"SCOPE control: %s did not play from the manifest, so the assert below is about nothing" % key)
	var stream: AudioStream = SoundManager._music_player.stream
	assert_not_null(stream, "%s produced no stream" % key)
	if stream != null:
		assert_almost_eq(float(stream.loop_offset), want, 0.001,
			"%s declares loop_offset %f and the stream restarts at %f — the wrap replays the silent lead-in the offset exists to skip" % [key, want, float(stream.loop_offset)])


## ⛔ THE ARM THAT NEEDS THE WRITE TO BE UNCONDITIONAL — AND MY FIRST VERSION OF IT DID NOT.
## It played an offset bed then a DIFFERENT bed with no offset and asserted 0.0, which passed with
## the write made conditional: loop_offset lives on the cached resource PER PATH, so two different
## files can never inherit from one another. The hazard needs ONE FILE named by SEVERAL KEYS, which
## is the .446 aliasing shape on a second axis. Planted in the cached manifest, restored in
## after_each, because no shipped entry pair disagrees today and this must not require one to.
func test_a_sibling_key_on_one_file_does_not_inherit_the_offset() -> void:
	if SoundManager == null:
		assert_true(false, "SoundManager autoload unavailable")
		return
	SoundManager._load_music_manifest()
	## Find a file named by >=2 keys in the LOADED manifest — derived, so a renamed family still works.
	var by_file: Dictionary = {}
	for k in SoundManager._music_manifest.keys():
		var e = SoundManager._music_manifest[k]
		if not (e is Dictionary):
			continue
		var f: String = str((e as Dictionary).get("file", ""))
		if f == "":
			continue
		if not by_file.has(f):
			by_file[f] = []
		(by_file[f] as Array).append(str(k))
	var pair: Array = []
	for f in by_file.keys():
		if (by_file[f] as Array).size() >= 2:
			pair = by_file[f]
			break
	assert_gt(pair.size(), 1,
		"ANTI-VACUITY: no file in the loaded manifest is named by two keys, so inheritance is untestable")
	if pair.size() < 2:
		return

	var lead: String = pair[0]
	var sibling: String = pair[1]
	var path: String = str((SoundManager._music_manifest[lead] as Dictionary).get("file", ""))
	if not path.begins_with("res://"):
		path = "res://" + path
	var st = load(path)
	if st != null and "loop_offset" in st:
		_restore[path] = st.loop_offset

	_planted_key = lead
	_planted_had = (SoundManager._music_manifest[lead] as Dictionary).has("loop_offset")
	(SoundManager._music_manifest[lead] as Dictionary)["loop_offset"] = 0.164
	assert_false((SoundManager._music_manifest[sibling] as Dictionary).has("loop_offset"),
		"SCOPE control: %s already declares an offset, so it cannot test inheritance" % sibling)

	assert_true(SoundManager._try_play_from_manifest(lead),
		"SCOPE control: %s did not play, so nothing was left behind to inherit" % lead)
	assert_almost_eq(float(SoundManager._music_player.stream.loop_offset), 0.164, 0.001,
		"SCOPE control: the planted offset did not reach the stream, so the assert below is about nothing")
	assert_true(SoundManager._try_play_from_manifest(sibling),
		"SCOPE control: %s did not play" % sibling)
	assert_eq(float(SoundManager._music_player.stream.loop_offset), 0.0,
		"%s names the SAME FILE as %s and declares no offset, yet its stream restarts at the sibling's offset — one runtime value serves both keys, so an absent field must WRITE 0.0 rather than leave the last key's value standing" % [sibling, lead])


func test_every_declared_offset_is_inside_its_own_bed() -> void:
	var tracks := _tracks()
	var keys := _offset_keys(tracks)
	assert_gt(keys.size(), 0, "ANTI-VACUITY: no declared offsets to check")
	var bad: Array = []
	for k in keys:
		var e: Dictionary = tracks[k]
		var off: float = float(e["loop_offset"])
		var path: String = str(e.get("file", ""))
		if not path.begins_with("res://"):
			path = "res://" + path
		var s = load(path)
		if s == null:
			bad.append("%s names %s which does not load" % [k, path])
			continue
		var len_s: float = float(s.get_length())
		if off <= 0.0:
			bad.append("%s declares loop_offset %f, which skips nothing" % [k, off])
		elif off >= len_s:
			bad.append("%s declares loop_offset %f past its %f s bed — the loop restarts past the end" % [k, off, len_s])
	assert_eq(bad.size(), 0, "a declared loop_offset cannot work: " + " · ".join(bad))


## Second axis of the .446 aliasing rule: one FILE named by several keys gets ONE runtime
## loop_offset, so two keys disagreeing means the last one played wins for both.
func test_two_names_for_one_bed_agree_on_where_it_loops() -> void:
	var tracks := _tracks()
	var by_file: Dictionary = {}
	for k in tracks.keys():
		var e = tracks[k]
		if not (e is Dictionary):
			continue
		var f: String = str((e as Dictionary).get("file", ""))
		if f == "":
			continue
		if not by_file.has(f):
			by_file[f] = []
		(by_file[f] as Array).append(str(k))
	var shared: int = 0
	var disagree: Array = []
	for f in by_file.keys():
		var ks: Array = by_file[f]
		if ks.size() < 2:
			continue
		shared += 1
		var seen: Dictionary = {}
		for k in ks:
			seen[float((tracks[k] as Dictionary).get("loop_offset", 0.0))] = true
		if seen.size() > 1:
			disagree.append("%s is named by %s with offsets %s" % [f, str(ks), str(seen.keys())])
	## ANTI-VACUITY: the property only exists while some file IS named by more than one key.
	assert_gt(shared, 0,
		"ANTI-VACUITY: no file is named by more than one key, so agreement is untestable here")
	assert_eq(disagree.size(), 0,
		"two keys name one file and ask it to loop from different points; one runtime value serves both: " + " · ".join(disagree))
