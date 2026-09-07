extends GutTest

## Mordaine escalation arc — four staged beats authored by @cowir-story
## (2026-07-26), wired here into _get_pending_story_cutscene.
##
## THE DESIGN CONTRACT, which is what these actually defend: she is not
## stalking the party, she is SUPERVISING them (novella :809 — "Mordaine
## designed our journey. All of it."). So escalation is NOT proximity; she
## was always the same distance away. What escalates is HOW MUCH THE GAME
## STOPS FOR HER — letterbox, then music, then speech, then full staging.
## That's a monotonic property of the data, so it can be pinned rather than
## trusted, and a later edit that makes beat 2 louder than beat 3 fails here.
##
## Also pins the two failure modes that don't announce themselves:
##   1. A missing _CUTSCENE_COMPLETION_FLAGS entry doesn't error — the gate
##      simply re-fires the scene on every qualifying entry. That was the
##      original Elder Theron bug (@cowir-battle flagged it on this arc).
##   2. A fixed map coord on the overworld puts the actor wherever the AUTHOR
##      was, not near the player. The road beat's authored coord sat ~900px
##      from the player spawn on a 3200x2240 map — valid, in-bounds, and
##      completely off-camera with the party out of frame.

const GAMELOOP := "res://src/GameLoop.gd"
const DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"
const CUTSCENE_DIR := "res://data/cutscenes"

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
## them grows. Counting lines would fail a correct arc and pass a wrong one,
## which is the coincidental-value trap. Speech PRESENCE is the real step
## change; total step count carries the rest.
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


# ── The beats exist and are staged ────────────────────────────────────

func test_all_four_beats_exist_and_are_staged() -> void:
	for id in BEATS:
		var d := _scene(id)
		assert_false(d.is_empty(), "%s.json must exist and parse" % id)
		assert_eq(str(d.get("presentation", "")), "staged",
			"%s must be staged — it puppets Mordaine on the live map" % id)


# ── The escalation is monotonic ───────────────────────────────────────

func test_the_game_stops_for_her_progressively() -> void:
	# The whole arc's point. A player who shrugged off beat 1 should feel it
	# when the letterbox finally comes down on the same figure.
	# NON-DECREASING IS NOT ESCALATION. Measured 2026-07-29: stripping beat 3's
	# letterbox and dialogue down to beat 2's shape left this guard 13/13 GREEN
	# — she stops speaking, the game stops stopping, and "never goes backward"
	# is perfectly satisfied. The contract is that each beat stops the game
	# MORE than the last, so every consecutive pair needs at least one STRICT
	# increase. @cowir-controller's predicate axis (msg-3506); found by running
	# a mutation I expected to survive, which @cowir-sfx measured as the only
	# kind that has taught anyone anything tonight.
	var prev := [-1, -1, -1, -1]
	var prev_id := ""
	for id in BEATS:
		var w := _weight(id)
		for i in 4:
			assert_true(int(w[i]) >= int(prev[i]),
				"escalation must never go BACKWARD: %s has %s, previous beat had %s (letterbox, music, speaks, steps)" % [
					id, str(w), str(prev)])
		if prev_id != "":
			var rose := false
			for i in 4:
				if int(w[i]) > int(prev[i]):
					rose = true
			assert_true(rose,
				"%s must stop the game MORE than %s, not merely not-less — identical weight %s is a flat beat in an arc whose whole subject is escalation" % [
					id, prev_id, str(w)])
		prev = w
		prev_id = id
	# ABSOLUTE MILESTONES, because relational checks cannot express them.
	# The strict-increase rule above was ALSO insufficient (measured): padding
	# beat 3's step count satisfies "some dimension rose" while its letterbox
	# and speech drop to zero. Step count is the weakest dimension and the one
	# that can always be padded, so a relational guard can always be bought off
	# with filler. @cowir-story's design names WHERE the arc arrives:
	#   road = nothing · F1 = leitmotif · F2 = SHE SPEAKS · F3 = full staging
	# Beat 3 is the one the mutation destroyed and the one no relative rule can
	# defend, so it is asserted directly.
	var third := _weight(BEATS[2])
	assert_eq(third[0], 1,
		"beat 3 must LETTERBOX — it is where the game first stops for her, and no relative rule can express that")
	assert_eq(third[2], 1,
		"beat 3 must be where she SPEAKS — the arc's whole shape is silence, then presence, then voice")
	var first := _weight(BEATS[0])
	assert_eq([first[0], first[1], first[2]], [0, 0, 0],
		"beat 1 is the LIGHTEST — no letterbox, no music, no speech. That restraint is the beat.")
	assert_gt(int(_weight(BEATS[3])[0]), 0, "the final beat must letterbox — the game fully stops")


# ── Completion flags (silent-reroll guard) ────────────────────────────

func test_every_beat_has_a_completion_flag() -> void:
	# A missing entry doesn't fail loudly — the scene re-fires forever.
	var src := _read(GAMELOOP)
	var map_start := src.find("const _CUTSCENE_COMPLETION_FLAGS")
	assert_gt(map_start, -1, "flag map must exist")
	var map_body := src.substr(map_start, src.find("\n}", map_start) - map_start)
	for id in BEATS:
		assert_gt(map_body.find('"%s":' % id), -1,
			"%s has no _CUTSCENE_COMPLETION_FLAGS entry — it will replay on every qualifying map entry" % id)


func test_beat_flag_matches_the_gate_that_reads_it() -> void:
	# The flag the map WRITES must be the flag the gate READS, or the beat
	# both re-fires and never advances the chain.
	var src := _read(GAMELOOP)
	for id in BEATS:
		var flag := "cutscene_flag_%s_complete" % id
		assert_gt(src.find('"%s"' % flag), -1,
			"%s must be written by the completion map AND read by its gate" % flag)


# ── Gates ─────────────────────────────────────────────────────────────

func test_every_beat_is_reachable_from_the_story_gate() -> void:
	# An authored-but-never-gated cutscene is the class the tick-97/98/99
	# comments in GameLoop describe: it ships, and nobody ever sees it.
	var src := _read(GAMELOOP)
	var fn := src.find("func _get_pending_story_cutscene")
	assert_gt(fn, -1)
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	for id in BEATS:
		assert_gt(body.find('return "%s"' % id), -1,
			"%s is authored but no gate returns it — it would never play" % id)


func test_castle_beats_do_not_collide_with_the_boss_floor() -> void:
	# Castle Harmonia is FOUR floors; the boss trigger is on F4. The three
	# castle beats sit on F1-F3 (@cowir-battle verified the floor helper
	# transfers). A beat gated >= 4 would fire on top of the finale.
	# Scan the Mordaine gate BLOCK rather than a specific variable name — the
	# folded gates use `_cave_floor` (the shared helper), and an earlier draft
	# of this test pinned `_castle_floor`, which made it unfailable. A check
	# whose only outcome is "pass" is worse than no check.
	var src := _read(GAMELOOP)
	var start := src.find("world1_mordaine_watch_road")
	assert_gt(start, -1, "the Mordaine gates must exist in GameLoop")
	var stop := src.find('return "world1_mordaine_procedure"', start)
	assert_gt(stop, -1, "the gate block must run through the last beat")
	var block := src.substr(start, stop - start)
	for f in [1, 2, 3]:
		assert_gt(block.find(">= %d" % f), -1,
			"a castle beat must gate on floor %d — the three beats spread across F1-F3" % f)
	for bad in [4, 5]:
		assert_eq(block.find(">= %d" % bad), -1,
			"no Mordaine escalation beat may gate on floor %d — F4 is the boss floor and belongs to world1_mordaine_intro" % bad)


# ── Player-relative placement ─────────────────────────────────────────

func test_road_beat_is_player_relative_not_a_fixed_coord() -> void:
	# THE placement regression. The overworld is 3200x2240; the authored
	# fixed coord was ~900px from the player spawn, so the pan showed her
	# alone in a far corner with the party off-screen entirely.
	var d := _scene("world1_mordaine_watch_road")
	var spawns := []
	for s in d.get("steps", []):
		if s is Dictionary and s.get("type") == "spawn_actor":
			spawns.append(s)
	assert_gt(spawns.size(), 0, "road beat must spawn her")
	for s in spawns:
		assert_true(s.has("at_offset"),
			"the overworld beat must place her RELATIVE to the player — a fixed coord lands wherever the author stood")
		assert_false(s.has("at"),
			"fixed 'at' would win over 'at_offset' in _step_spawn_actor — don't set both")


func test_road_beat_does_not_play_in_dead_air() -> void:
	# @cowir-sfx's finding via @cowir-story: the director fades music out on
	# EVERY scene, even one that declares none — so beat 1 as authored killed
	# the overworld track and played in silence. That is a LOUDER announcement
	# than the letterbox deliberately withheld, and it inverts the stated
	# intent ("the game does not stop"). keep_music opts this scene out.
	var d := _scene("world1_mordaine_watch_road")
	assert_true(bool(d.get("keep_music", false)),
		"the ambient beat must keep the map music — fading to dead air announces it harder than a letterbox")
	var src := _read(DIRECTOR)
	assert_gt(src.find('data.get("keep_music"'), -1,
		"the director must honor keep_music, or the field is authored-but-inert")


func test_keep_music_defaults_off_for_every_other_scene() -> void:
	# Deliberate restraint: the fade is corpus-wide behavior struktured has
	# already heard. Only the ambient beat opts out; flipping the default
	# would silently change audio in dozens of scenes nobody asked about.
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


func test_spawn_actor_consumes_at_offset() -> void:
	# Guards against the field being authored but never read — the same
	# authored-but-inert class as an ungated cutscene.
	var src := _read(DIRECTOR)
	var fn := src.find("func _step_spawn_actor")
	assert_gt(fn, -1)
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_gt(body.find('"at_offset"'), -1, "spawn_actor must read at_offset")
	assert_gt(body.find("_get_live_player()"), -1, "at_offset must resolve against the live player")


func test_at_offset_lands_her_inside_the_visible_frame() -> void:
	# RUNTIME, not source. The authored fixed coord was ~900px from the player
	# against a 640x360 visible region (1280x720 viewport at the villages'
	# zoom 2), so she was several screens off. Assert the property that
	# actually matters: wherever the player stands, she lands in frame.
	var stage := Node2D.new()
	add_child_autofree(stage)
	var saved = MapSystem.current_map if MapSystem else null
	if MapSystem:
		MapSystem.current_map = stage
	var player := Node2D.new()
	player.add_to_group("player")
	stage.add_child(player)

	var d = load(DIRECTOR).new()
	add_child_autofree(d)
	var offset: Array = []
	for s in _scene("world1_mordaine_watch_road").get("steps", []):
		if s is Dictionary and s.get("type") == "spawn_actor" and s.get("at_offset") is Array:
			offset = s["at_offset"]
	assert_gt(offset.size(), 1, "road beat must declare at_offset")

	# SWEEP, not one fixture. The property is "wherever the player stands",
	# and whether a single sample exposes a break is a fact about that sample
	# rather than about the code (@cowir-ai msg-3390: the mutant is wrong, the
	# one input didn't reveal it). Includes near-origin and far-corner, since
	# a clamp would only misbehave at an edge.
	for spot in [Vector2(2100, 1450), Vector2(96, 96), Vector2(3100, 2180), Vector2(1600, 40)]:
		player.global_position = spot
		d._step_spawn_actor({"id": "mordaine", "kind": "npc", "archetype": "chancellor_mordaine",
			"at_offset": offset, "facing": "down"})
		var actor = d._actors.get("mordaine")
		assert_not_null(actor, "she must spawn (player at %s)" % str(spot))
		var delta: Vector2 = actor.global_position - player.global_position
		# Half the visible region, minus a margin so she isn't clipped at the edge.
		assert_true(absf(delta.x) < 288.0 and absf(delta.y) < 148.0,
			"she must land inside the visible frame relative to the player (delta %s, player %s) — a fixed map coord is what put her off-screen" % [str(delta), str(spot)])
		assert_true(delta.length() > 64.0,
			"…but not on top of the party either; she is a figure at a distance (player %s)" % str(spot))
		# DIRECTION, not just distance. The narration the player reads says
		# "a figure on the RISE, EAST of the road" — so +x and above. absf() on
		# both axes was direction-blind: negating at_offset puts her west and
		# downhill, contradicting the prose, and all 13 assertions stayed green
		# (measured 2026-07-29).
		# MAGNITUDE, not just sign. `> 0` defends the DIRECTION and not the
		# MEANING: measured 2026-07-29, at_offset [1,-96] (east by one pixel)
		# and [208,-1] ("the rise" is one pixel of elevation) both passed a
		# sign-only predicate. A figure one pixel east of you is not "on the
		# rise east of the road". Floors are in TILE_SIZE units (32px) so they
		# say something about the world rather than being chosen numbers:
		# two tiles east, one tile above — the authored [208,-96] is 6.5 and 3.
		# @cowir-controller's axis (msg-3506): exhausting the set says nothing
		# about whether the predicate is right; only an awkward mutation does.
		assert_true(delta.x > 64.0,
			"she must stand MEANINGFULLY EAST of the party — 'east of the road', not east by a pixel (delta %s, player %s)" % [str(delta), str(spot)])
		assert_true(delta.y < -32.0,
			"…and MEANINGFULLY ABOVE them: it is 'the rise', and the beat closes on 'the rise was empty' (delta %s, player %s)" % [str(delta), str(spot)])
	if MapSystem:
		MapSystem.current_map = saved


func test_road_beat_camera_follows_the_actor() -> void:
	# With player-relative placement, a FIXED camera target would frame empty
	# ground. Targeting the actor id keeps her and the party both on screen.
	var d := _scene("world1_mordaine_watch_road")
	var targets := []
	for s in d.get("steps", []):
		if s is Dictionary and s.get("type") == "camera_focus":
			targets.append(s.get("target"))
	assert_gt(targets.size(), 0, "road beat must move the camera")
	assert_true(targets.has("mordaine"),
		"camera must target the actor id, not a fixed coord, now that she is placed relative to the player: %s" % str(targets))


# ── Narration must match what's on screen ─────────────────────────────

func test_she_is_gone_before_the_narration_says_she_is_gone() -> void:
	# Authored order had the "rise was empty" line play while the puppet was
	# still standing there. Nothing in the suite compares prose to staging,
	# and it reads as a bug the instant anyone watches it.
	var d := _scene("world1_mordaine_watch_road")
	var steps: Array = d.get("steps", [])
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
