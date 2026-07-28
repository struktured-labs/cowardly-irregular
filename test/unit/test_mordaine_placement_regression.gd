extends GutTest

## PLACEMENT half of the Mordaine escalation arc. Companion to
## test_mordaine_escalation_wiring_regression (@cowir-main), which pins the
## WIRING — gates, completion flags, sequence. Nothing here duplicates it:
## those tests prove the beats can play, these prove they look right when
## they do. Deliberately a separate file so neither lane overwrites the
## other's coverage.
##
## Context (2026-07-28): the gates folded WITHOUT the placement fixes, so all
## four beats went live with the first one visibly wrong —
##   * she spawned at a FIXED coord on a 3200x2240 overworld against a
##     640x360 visible region, ~900px from where the player actually stands
##     after ch4, so the camera panned to an empty corner with the party
##     out of frame
##   * the narration "the rise was empty" played while she stood there
##   * the beat played in dead air, because the director fades music out on
##     EVERY scene including ones that declare none
##
## None of that fails a wiring test. All of it is obvious on screen.

const DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"
const CUTSCENE_DIR := "res://data/cutscenes"
const ROAD := "world1_mordaine_watch_road"

const BEATS := [
	"world1_mordaine_watch_road",
	"world1_mordaine_watch_castle",
	"world1_mordaine_speaks",
	"world1_mordaine_procedure",
]


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func _scene(id: String) -> Dictionary:
	var parsed = JSON.parse_string(_read("%s/%s.json" % [CUTSCENE_DIR, id]))
	return parsed if parsed is Dictionary else {}


## (letterbox, music, she-speaks-at-all, total steps) — "how much the game stops".
##
## NOTE: deliberately NOT dialogue-line COUNT. Beat 4 has fewer lines than
## beat 3 (4 vs 6) and is still the heavier scene — her closing lines are
## clipped on purpose ("One moment." / "There.") while the staging around
## them grows. A line-count invariant fails a correct arc and passes a wrong
## one, which is the worst pair of properties a ratchet can have. My first
## draft asserted exactly that and this test caught it.
func _weight(id: String) -> Array:
	var d := _scene(id)
	var lb := 0
	var mus := 0
	var speaks := 0
	var steps := 0
	for s in d.get("steps", []):
		if not (s is Dictionary):
			continue
		steps += 1
		match str(s.get("type", "")):
			"letterbox_in": lb += 1
			"play_music": mus += 1
			"dialogue": speaks = 1
	return [lb, mus, speaks, steps]


# ── The staging escalates, as content ─────────────────────────────────

func test_the_game_stops_for_her_progressively() -> void:
	# @cowir-main's file pins that the GATES run in sequence; this pins that
	# the CONTENT actually escalates across that sequence. Both are needed —
	# correctly-ordered beats that all weigh the same aren't an escalation.
	var prev := [-1, -1, -1, -1]
	for id in BEATS:
		var w := _weight(id)
		for i in 4:
			assert_true(int(w[i]) >= int(prev[i]),
				"escalation must never go BACKWARD: %s has %s, previous beat had %s (letterbox, music, speaks, steps)" % [
					id, str(w), str(prev)])
		prev = w
	var first := _weight(BEATS[0])
	assert_eq([first[0], first[1], first[2]], [0, 0, 0],
		"beat 1 is the LIGHTEST — no letterbox, no music, no speech. That restraint is the beat.")
	assert_gt(int(_weight(BEATS[3])[0]), 0, "the final beat must letterbox — the game fully stops")


# ── Player-relative placement ─────────────────────────────────────────

func test_road_beat_is_player_relative_not_a_fixed_coord() -> void:
	var spawns := []
	for s in _scene(ROAD).get("steps", []):
		if s is Dictionary and s.get("type") == "spawn_actor":
			spawns.append(s)
	assert_gt(spawns.size(), 0, "road beat must spawn her")
	for s in spawns:
		assert_true(s.has("at_offset"),
			"the overworld beat must place her RELATIVE to the player — a fixed coord lands wherever the author stood")
		assert_false(s.has("at"),
			"fixed 'at' wins over 'at_offset' in _step_spawn_actor — don't set both")


func test_at_offset_lands_her_inside_the_visible_frame() -> void:
	# RUNTIME, not source. Asserts the property that actually matters:
	# wherever the player stands, she lands on screen.
	var stage := Node2D.new()
	add_child_autofree(stage)
	var saved = MapSystem.current_map if MapSystem else null
	if MapSystem:
		MapSystem.current_map = stage
	var player := Node2D.new()
	player.add_to_group("player")
	stage.add_child(player)
	player.global_position = Vector2(2100, 1450)   # arbitrary, far from any authored coord

	var d = load(DIRECTOR).new()
	add_child_autofree(d)
	var offset: Array = []
	for s in _scene(ROAD).get("steps", []):
		if s is Dictionary and s.get("type") == "spawn_actor" and s.get("at_offset") is Array:
			offset = s["at_offset"]
	assert_gt(offset.size(), 1, "road beat must declare at_offset")
	d._step_spawn_actor({"id": "mordaine", "kind": "npc", "archetype": "chancellor_mordaine",
		"at_offset": offset, "facing": "down"})
	var actor = d._actors.get("mordaine")
	assert_not_null(actor, "she must spawn")
	var delta: Vector2 = actor.global_position - player.global_position
	# Half the visible region, minus a margin so she isn't clipped at the edge.
	assert_true(absf(delta.x) < 288.0 and absf(delta.y) < 148.0,
		"she must land inside the visible frame relative to the player (delta %s) — a fixed map coord is what put her off-screen" % str(delta))
	assert_true(delta.length() > 64.0,
		"…but not on top of the party either; she is a figure at a distance")
	if MapSystem:
		MapSystem.current_map = saved


func test_spawn_actor_consumes_at_offset() -> void:
	# Guards against the field being authored but never read — the same
	# authored-but-inert class as an ungated cutscene.
	var src := _read(DIRECTOR)
	var fn := src.find("func _step_spawn_actor")
	assert_gt(fn, -1)
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_gt(body.find('"at_offset"'), -1, "spawn_actor must read at_offset")
	assert_gt(body.find("_get_live_player()"), -1, "at_offset must resolve against the live player")


func test_road_beat_camera_follows_the_actor() -> void:
	# With player-relative placement, a FIXED camera target frames empty
	# ground. Targeting the actor id keeps her and the party both on screen.
	var targets := []
	for s in _scene(ROAD).get("steps", []):
		if s is Dictionary and s.get("type") == "camera_focus":
			targets.append(s.get("target"))
	assert_gt(targets.size(), 0, "road beat must move the camera")
	assert_true(targets.has("mordaine"),
		"camera must target the actor id, not a fixed coord, now that she is placed relative to the player: %s" % str(targets))


# ── Narration must match what's on screen ─────────────────────────────

func test_she_is_gone_before_the_narration_says_she_is_gone() -> void:
	# Nothing else in the suite compares prose to staging, and this reads as
	# a bug the instant anyone watches it.
	var steps: Array = _scene(ROAD).get("steps", [])
	var despawn_at := -1
	var empty_line_at := -1
	for i in steps.size():
		var s = steps[i]
		if not (s is Dictionary):
			continue
		if s.get("type") == "despawn_actor" and str(s.get("id", "")) == "mordaine":
			despawn_at = i
		if s.get("type") == "narration" and str(s.get("text", "")).find("rise was empty") > -1:
			empty_line_at = i
	assert_gt(despawn_at, -1, "the road beat must despawn her — the narration says the rise is empty")
	assert_gt(empty_line_at, -1, "sanity: the absence line must still exist")
	assert_true(despawn_at < empty_line_at,
		"she must vanish BEFORE the line describing her absence (despawn step %d, line step %d)" % [despawn_at, empty_line_at])


# ── Dead air ──────────────────────────────────────────────────────────

func test_road_beat_does_not_play_in_dead_air() -> void:
	# The director fades music out on EVERY scene, even one declaring none,
	# so the beat designed as "the game does not stop" was the one that
	# stopped it hardest. keep_music opts this scene out.
	assert_true(bool(_scene(ROAD).get("keep_music", false)),
		"the ambient beat must keep the map music — fading to dead air announces it harder than a letterbox")
	assert_gt(_read(DIRECTOR).find('data.get("keep_music"'), -1,
		"the director must honor keep_music, or the field is authored-but-inert")


func test_keep_music_defaults_off_for_every_other_scene() -> void:
	# Deliberate restraint: the fade is corpus-wide behavior struktured has
	# already heard. Only the ambient beat opts out.
	var dir := DirAccess.open(CUTSCENE_DIR)
	var opted: Array = []
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(_read("%s/%s" % [CUTSCENE_DIR, f]))
		if parsed is Dictionary and bool(parsed.get("keep_music", false)):
			opted.append(f)
	assert_eq(opted, ["world1_mordaine_watch_road.json"],
		"only the ambient road beat should opt out of the music fade so far — a new opt-in is fine, but it's a deliberate audio change worth noticing: %s" % str(opted))
