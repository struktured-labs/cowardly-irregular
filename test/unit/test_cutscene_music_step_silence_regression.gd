extends GutTest

## A cutscene `play_music` step naming a track that doesn't resolve does NOT
## leave the music untouched — it leaves the scene SILENT.
##
## SoundManager.play_music crossfades the current track out and clears state
## BEFORE it tries to resolve the id; an unknown id then falls all the way
## through to push_warning("Unknown music track") having started nothing. So
## a single typo, or a track referenced before its manifest entry is folded,
## kills the audio for the rest of the scene and warns only to the log.
##
## Found 2026-07-26 while sequencing @cowir-music's Mordaine tracks: their
## branch was unfolded, so wiring `cutscene_mordaine_theme` into the throne
## room would have silenced it rather than harmlessly no-op'd. That is the
## exact "silent failure is worse than a crash" class the project calls out.
##
## Fix: SoundManager.has_music_track() reports whether a call would produce
## audio, and _step_play_music keeps the map's music when it wouldn't.

const DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"
const CUTSCENE_DIR := "res://data/cutscenes"

var _saved_music: String = ""


func before_each() -> void:
	if SoundManager:
		_saved_music = SoundManager._current_music


func after_each() -> void:
	if SoundManager:
		SoundManager._current_music = _saved_music


func _new_director():
	var d = load(DIRECTOR).new()
	add_child_autofree(d)
	return d


# ── The resolver ──────────────────────────────────────────────────────

func test_has_music_track_accepts_manifest_entries() -> void:
	assert_true(SoundManager.has_music_track("village_medieval"),
		"a real manifest track must resolve")


func test_has_music_track_accepts_procedural_arms() -> void:
	# These have no manifest entry on some builds but DO generate audio.
	for t in ["battle", "boss", "title", "victory", "game_over"]:
		assert_true(SoundManager.has_music_track(t),
			"'%s' has a procedural arm in play_music — it must resolve" % t)


func test_has_music_track_rejects_nonsense() -> void:
	assert_false(SoundManager.has_music_track("not_a_real_track_zzz"),
		"an unresolvable id must report false — otherwise the guard is useless")
	assert_false(SoundManager.has_music_track(""),
		"empty id must not resolve")


# ── The guard ─────────────────────────────────────────────────────────

func test_unknown_track_keeps_current_music() -> void:
	# THE regression. Pre-fix this call silenced the scene.
	var d = _new_director()
	SoundManager._current_music = "sentinel_track"
	d._step_play_music({"track": "not_a_real_track_zzz"})
	assert_eq(SoundManager._current_music, "sentinel_track",
		"an unknown track must leave the existing music playing, not crossfade to silence")


func test_empty_track_is_a_noop() -> void:
	var d = _new_director()
	SoundManager._current_music = "sentinel_track"
	d._step_play_music({})
	assert_eq(SoundManager._current_music, "sentinel_track",
		"a play_music step with no track must not disturb the music")


# ── The audit that would have caught it ───────────────────────────────

func test_every_authored_music_track_resolves() -> void:
	# Bidirectional ratchet over the whole corpus: any play_music step whose
	# track can't resolve would silence that scene at runtime, and nothing
	# else in the suite looks. This is what catches a track referenced before
	# its manifest entry lands, or a plain typo.
	var d := DirAccess.open(CUTSCENE_DIR)
	assert_not_null(d, "cutscene dir must open")
	var offenders: Array = []
	var checked := 0
	for f in d.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [CUTSCENE_DIR, f]))
		if not (parsed is Dictionary):
			continue
		var idx := 0
		for step in _flatten_steps(parsed.get("steps", [])):
			if step is Dictionary and step.get("type") == "play_music":
				var track := str(step.get("track", ""))
				checked += 1
				if not SoundManager.has_music_track(track):
					offenders.append("%s[step %d] track '%s'" % [f, idx, track])
			idx += 1
	assert_gt(checked, 50, "sanity: the corpus should have many play_music steps to audit")
	assert_eq(offenders.size(), 0,
		"these cutscene music steps name tracks that won't resolve — each one silences its scene:\n  %s" % "\n  ".join(offenders))


func test_throne_room_approach_plays_mordaines_theme() -> void:
	# @cowir-music built cutscene_mordaine_theme as four notes of the battle
	# theme with long silences, so the player learns her music across the arc
	# and the throne room pays it off. That only works if the earlier beats
	# actually use it — an unwired theme is the failure mode, and it's silent.
	# The intro scene that follows deliberately stop_music's, so the shape is
	# theme -> silence as she speaks -> boss_mordaine. Don't "fix" that gap.
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(
		"%s/world1_throne_room_approach.json" % CUTSCENE_DIR))
	assert_true(parsed is Dictionary, "throne room approach must parse")
	var tracks: Array = []
	for step in parsed.get("steps", []):
		if step is Dictionary and step.get("type") == "play_music":
			tracks.append(str(step.get("track", "")))
	assert_true(tracks.has("cutscene_mordaine_theme"),
		"the throne room approach must play Mordaine's theme — it is the payoff for the whole leitmotif arc. found: %s" % str(tracks))


## Flattens branch sub-steps. The corpus audit walked the top-level array
## only, so the FOUR nested play_music steps in world6_chapter3 — the W6
## ending themes @cowir-music wired — were never checked for resolution.
## They all resolve today; the coverage gap was the finding. Same shape as
## @cowir-ai's "I checked verbs and stopped, the layer below is fields":
## I checked that tracks resolve and stopped at the layer the walk reached.
static func _flatten_steps(steps: Array) -> Array:
	var out: Array = []
	for step in steps:
		if not (step is Dictionary):
			continue
		out.append(step)
		for case_steps in (step.get("cases", {}) as Dictionary).values():
			if case_steps is Array:
				out.append_array(_flatten_steps(case_steps))
		for key in ["if_true", "if_false"]:
			if step.get(key) is Array:
				out.append_array(_flatten_steps(step[key]))
	return out


func test_the_track_audit_reaches_branch_nested_music_steps() -> void:
	# POSITIVE CONTROL. A flatten that silently stopped at the top level would
	# leave this file green while never seeing the game's four ending themes.
	# Counted independently of the walker so it can't agree with a broken one.
	var nested := 0
	var dir := DirAccess.open(CUTSCENE_DIR)
	assert_not_null(dir, "cutscene dir must open")
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [CUTSCENE_DIR, f]))
		if not (parsed is Dictionary):
			continue
		for step in parsed.get("steps", []):
			if not (step is Dictionary):
				continue
			for case_steps in (step.get("cases", {}) as Dictionary).values():
				if case_steps is Array:
					for sub in case_steps:
						if sub is Dictionary and sub.get("type") == "play_music":
							nested += 1
	assert_gt(nested, 0,
		"the corpus must contain branch-nested play_music steps for this audit to be doing anything — the W6 endings are four of them")
	var flat := 0
	var top := 0
	for f2 in dir.get_files():
		if not f2.ends_with(".json"):
			continue
		var p2 = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [CUTSCENE_DIR, f2]))
		if p2 is Dictionary:
			flat += _flatten_steps(p2.get("steps", [])).size()
			top += (p2.get("steps", []) as Array).size()
	assert_gt(flat, top,
		"the flattened walk must reach MORE steps than the top-level array — equal means the recursion is dead and this audit is scoped to top-level only")
