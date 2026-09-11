extends GutTest

## Every key the game passes to play_ambient must be covered, not every key
## NAMED like ambience.
##
## test_ambient_cues_actually_loop walks `sounds.keys()` filtered by
## `begins_with("ambient_")`. That is a naming convention, and the game does not
## route by name — it routes by call site. Derived from the consumer instead,
## the real corpus is larger and the extra members are the interesting ones:
##
##     ambient_*          13   covered by the existing guard
##     weather_*           6   WeatherSystem:182-187, literal keys      NOT covered
##     night_crickets_wind 1   SoundManager.NIGHT_AMBIENCE_KEY          NOT covered
##
## 🔑 AND THE UNCOVERED SET IS WHERE THE DEFECTS ARE. All six weather beds have
## `loop: false` in the manifest AND `loop=false` in their .import, so they do
## not stream-loop at all — they continue only because _on_ambient_finished
## re-calls play(). They are 5s long (storm 10s), so that restart happens
## TWELVE TIMES A MINUTE, and three of them have a broken wrap:
##
##     weather_steam    +59.0 dB    tail -83.8 dBFS — digital silence — head -24.8
##     weather_smog     +14.6 dB
##     weather_glitch   +10.6 dB
##
## weather_steam is the trailing-silence defect this lane fixed across 19 music
## beds, live in the steampunk world at 12 restarts a minute. Measured
## 2026-09-11; WeatherSystem is shipped (weather v2, .225/.226).
##
## ⚠️ THE ASSETS ARE cowir-sfx's AND THE PIN IS NOT A VERDICT. assets/audio/sfx/
## is their corpus; re-encoding it from this lane would be working in someone
## else's tree. So the six are PINNED with their measurements and handed over,
## not silently demanded to change. The pin goes RED when one starts looping, so
## it cannot outlive the handover.
##
## ⛔ AND loop=true ALONE WOULD MAKE weather_steam WORSE, which is why this is a
## pin and not a one-line fix. A stream loop removes the restart gap but plays
## the seam MORE cleanly — the +59 dB snap stays and arrives on a tighter
## schedule. The seam has to be fixed first; tools/trim_wrap_padding.py handles
## exactly this shape (trailing silence, no gain change, source rate preserved).

const SFX_MANIFEST := "res://data/sfx_manifest.json"

## Six weather beds, measured 2026-09-11. Owner: cowir-sfx. Each entry is the
## reason it is here, not permission to stay.
## ✅ EMPTIED 2026-09-11 — @cowir-sfx fixed all six and the pin retired itself.
## This file SHIPPED with six entries and a stale-detection arm that goes RED
## when a pinned key starts looping. It did exactly that the moment their fix
## merged, which is the arm working — and it is also a cross-lane ratchet break
## of the kind that turned up twice in gate 129/130, so it is repaired here
## rather than left for the folder to discover at 3am.
##
## ⚠️ THE DEPENDENCY RUNS BOTH WAYS, which is why this branch CONTAINS theirs:
## pins removed without their fix = six unpinned non-loopers, RED. Their fix
## without this = a stale pin, RED. Neither half is safe alone.
##
## ⛔ AND ONE OF THE SIX WAS NOT A SEAM DEFECT AT ALL. weather_steam carried
## 3.0s of fade in a 5.0s file; trimming the seam would have left a 2-second bed
## looping 30x a minute. @cowir-sfx synthesised a periodic buffer instead
## (tools/gen_steam_bed.py, built in the frequency domain so the wrap is
## seamless as a property of the maths). My handover offered trim_wrap_padding
## for all six and it would have no-opped on five — they measured instead of
## taking the tool I pointed at them, and were right to.
const KNOWN_NON_LOOPING := {}


func _sfx() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(SFX_MANIFEST)
	assert_gt(raw.length(), 1000, "SCOPE control: sfx_manifest read back %d chars" % raw.length())
	## The root key is 'sfx', not 'sounds' — a wrong root returns {} and every
	## arm below passes having walked nothing.
	return (JSON.parse_string(raw) as Dictionary).get("sfx", {})


func _gd_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	d.list_dir_begin()
	var n: String = d.get_next()
	while n != "":
		var p: String = root + "/" + n
		if d.current_is_dir():
			out.append_array(_gd_files(p))
		elif n.ends_with(".gd"):
			out.append(p)
		n = d.get_next()
	d.list_dir_end()
	return out


## Keys the game actually hands to play_ambient, plus the one named constant.
func _consumer_keys() -> Dictionary:
	var out: Dictionary = {}
	var re := RegEx.new()
	re.compile("play_ambient\\(\\s*\"([a-z_0-9]+)\"\\s*\\)")
	for f in _gd_files("res://src"):
		var body: String = FileAccess.get_file_as_string(f)
		for m in re.search_all(body):
			out[m.get_string(1)] = f
	## NIGHT_AMBIENCE_KEY is passed by constant, not literal, so the regex above
	## cannot see it — the same blind spot one level down.
	var sm: String = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	var cre := RegEx.new()
	cre.compile("NIGHT_AMBIENCE_KEY\\s*:\\s*String\\s*=\\s*\"([a-z_0-9]+)\"")
	var cm: RegExMatch = cre.search(sm)
	if cm != null:
		out[cm.get_string(1)] = "res://src/audio/SoundManager.gd (NIGHT_AMBIENCE_KEY)"
	return out


func test_control_the_consumer_walk_finds_the_known_call_sites() -> void:
	## Without this, a broken walk returns {} and every arm passes vacuously.
	var keys: Dictionary = _consumer_keys()
	assert_gt(keys.size(), 4,
		"SCOPE control: only %d play_ambient keys found — the walk is broken" % keys.size())
	assert_true(keys.has("weather_rain"),
		"CONTROL FAILED: weather_rain not found, but WeatherSystem:182 passes it literally — the regex has drifted off the call shape")
	assert_true(keys.has("night_crickets_wind"),
		"CONTROL FAILED: the NIGHT_AMBIENCE_KEY constant was not resolved — that is the blind spot this file exists to close, so missing it makes the rest hollow")


func test_every_consumer_key_exists_in_the_sfx_manifest() -> void:
	var sfx: Dictionary = _sfx()
	assert_gt(sfx.size(), 100,
		"SCOPE control: walked %d sfx entries — wrong root key? It is 'sfx', not 'sounds'." % sfx.size())
	var missing: Array[String] = []
	var keys: Dictionary = _consumer_keys()
	for k in keys.keys():
		if not sfx.has(k):
			missing.append("%s (from %s)" % [k, keys[k]])
	assert_eq(missing.size(), 0,
		"play_ambient is called with keys that are not in the sfx manifest (%d): %s — the ambient player gets nothing and the area is silent" % [missing.size(), missing])


func test_every_consumer_key_loops_or_is_pinned() -> void:
	var sfx: Dictionary = _sfx()
	var keys: Dictionary = _consumer_keys()
	var checked: int = 0
	var unpinned: Array[String] = []
	var stale: Array[String] = []
	for key in keys.keys():
		var k: String = str(key)
		var e: Variant = sfx.get(k, null)
		if not (e is Dictionary):
			continue
		checked += 1
		var loops: bool = bool((e as Dictionary).get("loop", false))
		if not loops and not KNOWN_NON_LOOPING.has(k):
			unpinned.append("%s (from %s)" % [k, keys[k]])
		elif loops and KNOWN_NON_LOOPING.has(k):
			stale.append(k)
	assert_gt(checked, 4,
		"SCOPE control: only %d consumer keys resolved against the manifest" % checked)
	assert_eq(unpinned.size(), 0,
		"ambient keys that do not loop and are not pinned (%d of %d): %s — the ambient player relies on _on_ambient_finished re-calling play(), which is a restart, not a loop" % [unpinned.size(), checked, unpinned])
	## The handover must expire on its own or the pin becomes the documentation
	## of a permanent state instead of a tracked one.
	assert_eq(stale.size(), 0,
		"KNOWN_NON_LOOPING names keys that now LOOP (%s) — cowir-sfx fixed them; delete the entries so they are covered like the rest" % [stale])


func test_the_existing_prefix_guard_is_the_narrower_one() -> void:
	## Pins the relationship rather than duplicating the other file: if the
	## prefix walk ever covers everything the consumer uses, this file's reason
	## for existing is gone and it should be retired deliberately.
	var keys: Dictionary = _consumer_keys()
	var outside: Array[String] = []
	for k in keys.keys():
		if not str(k).begins_with("ambient_"):
			outside.append(str(k))
	outside.sort()
	assert_gt(outside.size(), 0,
		"every play_ambient key now begins with 'ambient_' — test_ambient_cues_actually_loop covers the whole corpus and this file is redundant; retire it rather than leave two walks")
	assert_true(outside.has("night_crickets_wind"),
		"SCOPE control: night_crickets_wind should be outside the prefix walk; if it is not, the comparison is measuring the wrong thing")
