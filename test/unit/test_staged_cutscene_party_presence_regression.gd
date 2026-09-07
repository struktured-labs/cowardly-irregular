extends GutTest

## Regression 2026-07-30: in all four Mordaine escalation beats the player's
## party VANISHED for the length of the scene.
##
## `presentation: "staged"` plays on the live map, and _begin_staging() hid the
## real player unconditionally so puppets could own the frame. Both proof scenes
## spawn all five party members as `kind: "party"` puppets, so the party is still
## on screen and hiding the real player is correct. The four Mordaine beats spawn
## ONE actor — Mordaine — and nothing takes the party's place.
##
## Measured on the corpus before the fix:
##   world1_chapter1              9 spawns · 5 kind=party   player hidden, replaced
##   world1_harmonia_after_cave  10 spawns · 5 kind=party   player hidden, replaced
##   the four mordaine beats       1 spawn  · 0 kind=party   player hidden, NOT replaced
##
## So the player watched their own character blink out, an NPC appear alone, and
## narration talk about a party that wasn't on screen — `watch_castle` even says
## "she did not follow them across the foyer" over an empty foyer.
##
## No structural ratchet could see it: the JSON is valid, every step type is
## known, every mark is on walkable ground (checked — F1 (17,6), F2 (16,7),
## F3 (15,7) are all floor tiles in CastleHarmonia's own layouts). The defect is
## that hiding is unconditional while replacing is optional.
##
## Fix: take the frame from the real player only when a party puppet replaces it.
##
## This is my own defect from earlier the same session. `watch_road`'s authored
## description claims the placement fix keeps "both" the actor and the party in
## frame — an intent the engine could not deliver, because the party was never
## renderable in that scene at all.

const DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"
const CUTSCENE_DIR := "res://data/cutscenes"


func _director() -> Node:
	var d = load(DIRECTOR).new()
	assert_not_null(d, "CutsceneDirector script must instantiate")
	add_child_autofree(d)
	return d


## A Node2D in the "player" group — exactly what _get_live_player() resolves.
func _stub_player() -> Node2D:
	var p := Node2D.new()
	p.add_to_group("player")
	add_child_autofree(p)
	return p


func test_staging_keeps_the_player_when_no_puppet_replaces_it() -> void:
	# THE regression. A scene that spawns no party puppet must not blank the party.
	var d := _director()
	var p := _stub_player()
	assert_true(p.visible,
		"PRECONDITION: the stub player must start visible, or the assertion below proves nothing")
	d._begin_staging(false)
	assert_true(p.visible,
		"with no party puppet to replace it, the real player must STAY VISIBLE — otherwise the party blinks out for the whole scene and the narration talks about characters who aren't on screen")
	d._end_staging()


func test_staging_still_hides_the_player_when_a_puppet_replaces_it() -> void:
	# The other direction, and the half that must NOT change: both proof scenes
	# put five party puppets on stage, so the real player has to give up the frame
	# or it stands next to its own double.
	var d := _director()
	var p := _stub_player()
	assert_true(p.visible, "PRECONDITION: stub player starts visible")
	d._begin_staging(true)
	assert_false(p.visible,
		"when party puppets own the frame the real player must be hidden, or it renders beside its own puppet")
	d._end_staging()
	assert_true(p.visible,
		"_end_staging must restore it — a scene that ends with the player invisible is unrecoverable without a map reload")


## ── The predicate, driven against the real corpus ─────────────────────

func _staged_scenes() -> Dictionary:
	# Derived from the files, never a hand-list. The geometry smoke in this lane
	# hardcodes two paths and was silent about the four beats added after it.
	var out: Dictionary = {}
	var dir := DirAccess.open(CUTSCENE_DIR)
	assert_not_null(dir, "cutscenes dir must open")
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [CUTSCENE_DIR, f]))
		if parsed is Dictionary and str(parsed.get("presentation", "")) == "staged":
			out[f] = parsed
	return out


func test_the_predicate_agrees_with_the_authored_spawns() -> void:
	# Drives the real _scene_spawns_party_puppet against every staged scene and
	# compares it with an INDEPENDENT count of kind=party spawns, so the predicate
	# cannot agree with a broken walk by construction.
	var d := _director()
	var scenes := _staged_scenes()
	assert_gt(scenes.size(), 4,
		"POSITIVE CONTROL: the corpus must yield several staged scenes — a tiny parse makes everything below vacuous")
	var with_party := 0
	var without := 0
	for f in scenes:
		var data: Dictionary = scenes[f]
		var expected := _count_party_spawns(data.get("steps", [])) > 0
		var actual: bool = d._scene_spawns_party_puppet(data)
		assert_eq(actual, expected,
			"%s: predicate says party_puppet=%s but the file has %d kind=party spawn(s)" % [
				f, actual, _count_party_spawns(data.get("steps", []))])
		if expected:
			with_party += 1
		else:
			without += 1
	# Both branches must be represented or this file tests one code path.
	assert_gt(with_party, 0,
		"POSITIVE CONTROL: at least one staged scene must spawn party puppets, else the hide-branch is untested")
	assert_gt(without, 0,
		"POSITIVE CONTROL: at least one staged scene must spawn none, else the keep-visible branch — the regression — is untested")


func _count_party_spawns(steps) -> int:
	# Independent of the director's walk, and recursive: a party spawn inside a
	# branch case still represents the party. Counting rather than short-circuiting
	# so a disagreement reports a number instead of a bare false.
	if not (steps is Array):
		return 0
	var n := 0
	for step in steps:
		if not (step is Dictionary):
			continue
		if str(step.get("type", "")) == "spawn_actor" and str(step.get("kind", "")) == "party":
			n += 1
		for case_steps in (step.get("cases", {}) as Dictionary).values():
			n += _count_party_spawns(case_steps)
		for key in ["if_true", "if_false"]:
			n += _count_party_spawns(step.get(key))
	return n


func test_the_recursive_walk_reaches_branch_nested_spawns() -> void:
	# The walk is recursive on purpose — an earlier audit in this lane read only
	# the top-level array and missed 35 branch-nested steps. Synthetic, because
	# no shipped staged scene nests a party spawn today, so the corpus cannot
	# prove the recursion works and its absence would be silent.
	var d := _director()
	var nested := {"steps": [
		{"type": "branch", "condition": "x", "cases": {
			"a": [{"type": "spawn_actor", "id": "fighter", "kind": "party", "job": "fighter"}]}}]}
	assert_true(d._scene_spawns_party_puppet(nested),
		"a kind=party spawn inside a branch case must count — it still puts the party on stage")
	var flat_only := {"steps": [
		{"type": "branch", "condition": "x", "cases": {
			"a": [{"type": "spawn_actor", "id": "mordaine", "kind": "npc", "archetype": "chancellor_mordaine"}]}}]}
	assert_false(d._scene_spawns_party_puppet(flat_only),
		"NEGATIVE CONTROL: an npc spawn in a branch must NOT count as the party, or the predicate is always true")
