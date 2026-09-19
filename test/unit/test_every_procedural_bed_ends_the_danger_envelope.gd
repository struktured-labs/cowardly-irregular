extends GutTest

## The danger envelope writes `_music_player.pitch_scale` (up to 1.15x) and `volume_db`, and a bed
## that starts without ending it INHERITS the last fight's detune. `reset_danger()` is the single
## repair, and it lives in the ENTRY POINTS — `play_music` and `play_area_music` — not in the dozen
## `_start_*_music` helpers that actually assign the stream.
##
## ⛔ THIS CLASS HAS SHIPPED THREE TIMES AND EVERY EXISTING GUARD IS PER-INSTANCE.
##   2026-09-06  play_music        struktured: "victory music speeds up when the party is mostly dead"
##   2026-09-12  play_area_music   danger at full -> cave bed at pitch 1.034 / vol -11.3
##   2026-09-19  _ability_player   the tavern piano, detuned by the last ability cue
## Six files guard those three beds. A FOURTEENTH procedural starter added tomorrow, reachable from
## a caller that forgets, leaves all six green — which is why this one derives the population
## instead of naming a bed.

const SM_PATH := "res://src/audio/SoundManager.gd"

## The two facts a raw play consists of. Both, in one function, is the shape that bypasses every
## reset: `_try_play_from_manifest` and `_play_sound` each write pitch themselves.
const STREAM_WRITE := "_music_player.stream ="
const PLAY_CALL := "_music_player.play()"
const RESET_CALL := "reset_danger()"


func _functions(code: String) -> Dictionary:
	var out: Dictionary = {}
	var name: String = ""
	var buf: PackedStringArray = []
	for raw_line in code.split("\n"):
		var line: String = str(raw_line)
		if line.begins_with("func "):
			if name != "":
				out[name] = "\n".join(buf)
			name = line.substr(5, max(0, line.find("(") - 5)).strip_edges()
			buf = [line]
		elif name != "":
			buf.append(line)
	if name != "":
		out[name] = "\n".join(buf)
	return out


## A call by NAME or by STRING. `play_area_music` reaches its starter through
## `call_deferred("_start_area_music_deferred", area_type)` — a name-only grep sees no caller
## there, reports the function unreachable, and a coverage walk keyed to it silently passes
## everything downstream of the deferral.
func _calls(body: String, target: String) -> bool:
	if body.contains("\"%s\"" % target):
		return true
	var re := RegEx.new()
	re.compile("(^|[^A-Za-z0-9_.])%s\\s*\\(" % target)
	return re.search(body) != null


func test_every_raw_music_play_is_reached_only_through_a_reset() -> void:
	var code: String = GdSource.code_of(SM_PATH)
	assert_gt(code.length(), 50000, "SCOPE control: SoundManager read back %d chars" % code.length())
	## MUST-SURVIVE control for the stripper: a quote-aware pass keeps code, and a truncating one
	## would shorten every window below while reporting a clean derivation.
	assert_true(code.contains(STREAM_WRITE), "the stripper cut live code — the stream write is gone")

	var bodies: Dictionary = _functions(code)
	## A LOOSE structural floor, deliberately. Its job is "the splitter still returns functions",
	## not "SoundManager has N" — a tight count is a coincidental-value ratchet that reds on any
	## correct refactor. Measured 193 today; 100 cannot be reached by a broken split.
	assert_gt(bodies.size(), 100, "ANTI-VACUITY: split %s into only %d functions — the splitter stopped matching" % [SM_PATH, bodies.size()])

	var raw: Array[String] = []
	var resetters: Array[String] = []
	for fn in bodies.keys():
		var b: String = str(bodies[fn])
		if b.contains(STREAM_WRITE) and b.contains(PLAY_CALL):
			raw.append(str(fn))
		if b.contains(RESET_CALL):
			resetters.append(str(fn))
	raw.sort()
	resetters.sort()

	## ANTI-VACUITY, both halves. An empty raw set passes the property by construction, and a
	## renamed `_music_player` is exactly how it would empty.
	assert_gt(raw.size(), 5,
		"ANTI-VACUITY: derived only %d raw-play functions (%s) — either _music_player was renamed or the two-token shape stopped matching, and an empty population cannot fail" % [raw.size(), str(raw)])
	assert_true(resetters.has("play_music") and resetters.has("play_area_music"),
		"the two known entry points must both still reset; derived resetters: %s" % str(resetters))

	## Transitive: a function is covered if it resets, or if it has callers and ALL of them are
	## covered. "Has callers" matters — an orphan is not covered by vacuous quantification.
	var covered: Dictionary = {}
	for r in resetters:
		covered[r] = true
	for _pass in range(12):
		var grew: bool = false
		for fn in bodies.keys():
			if covered.has(fn):
				continue
			var callers: Array[String] = []
			for other in bodies.keys():
				if other != fn and _calls(str(bodies[other]), str(fn)):
					callers.append(str(other))
			if callers.is_empty():
				continue
			var all_covered: bool = true
			for c in callers:
				if not covered.has(c):
					all_covered = false
					break
			if all_covered:
				covered[fn] = true
				grew = true
		if not grew:
			break

	var orphans: Array[String] = []
	for fn in raw:
		if not covered.has(fn):
			orphans.append(fn)

	assert_eq(orphans, [],
		"a procedural bed assigns _music_player.stream and plays it on a path that never calls reset_danger(), so it inherits the last fight's pitch (up to 1.15x) and volume boost: %s — either call reset_danger() there or route it through play_music / play_area_music" % str(orphans))
