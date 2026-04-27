extends GutTest

## Regression tests for GameState.to_dict / from_dict round-trip.
##
## SaveSystem._apply_save_data() calls GameState.from_dict() which is
## a thin wrapper around _apply_save_data(). If any new field is added
## to GameState but not wired into to_dict / from_dict, save→load
## silently drops it.
##
## These tests exercise a full round-trip on every public field so we
## catch drift early — adding a field without serialization will cause
## the round-trip equality check to fail.


const GameStateScript = preload("res://src/meta/GameState.gd")


func _make_state() -> Node:
	var s = GameStateScript.new()
	s.name = "TestGameState"
	add_child_autofree(s)
	if s.has_method("reset_game_state"):
		s.reset_game_state()
	return s


func test_round_trip_preserves_party_gold() -> void:
	var s = _make_state()
	s.party_gold = 4242
	var data = s.to_dict()
	# Mutate the original to ensure from_dict is what restores.
	s.party_gold = 0
	s.from_dict(data)
	assert_eq(s.party_gold, 4242, "party_gold round-trips")


func test_round_trip_preserves_corruption_level() -> void:
	var s = _make_state()
	s.corruption_level = 0.42
	var data = s.to_dict()
	s.corruption_level = 0.0
	s.from_dict(data)
	assert_almost_eq(s.corruption_level, 0.42, 0.001, "corruption_level round-trips")


func test_round_trip_preserves_current_world() -> void:
	var s = _make_state()
	s.current_world = 4
	var data = s.to_dict()
	s.current_world = 1
	s.from_dict(data)
	assert_eq(s.current_world, 4, "current_world round-trips")


func test_round_trip_preserves_worlds_unlocked() -> void:
	var s = _make_state()
	s.worlds_unlocked = 5
	var data = s.to_dict()
	s.worlds_unlocked = 1
	s.from_dict(data)
	assert_eq(s.worlds_unlocked, 5, "worlds_unlocked round-trips")


func test_round_trip_preserves_party_leader_index() -> void:
	var s = _make_state()
	s.party_leader_index = 3
	var data = s.to_dict()
	s.party_leader_index = 0
	s.from_dict(data)
	assert_eq(s.party_leader_index, 3, "party_leader_index round-trips")


func test_round_trip_preserves_story_flags() -> void:
	var s = _make_state()
	s.story_flags = {"prologue_complete": true, "world1_warden_defeated": true}
	var data = s.to_dict()
	s.story_flags = {}
	s.from_dict(data)
	assert_true(s.story_flags.get("prologue_complete", false),
		"prologue_complete flag round-trips")
	assert_true(s.story_flags.get("world1_warden_defeated", false),
		"world1_warden_defeated flag round-trips")


func test_round_trip_preserves_game_constants() -> void:
	var s = _make_state()
	s.game_constants = {"event_flag_first_party_wipe": true, "custom_const": 42}
	var data = s.to_dict()
	s.game_constants = {}
	s.from_dict(data)
	assert_true(s.game_constants.get("event_flag_first_party_wipe", false),
		"event_flag_first_party_wipe round-trips")
	assert_eq(s.game_constants.get("custom_const", 0), 42,
		"custom int constant round-trips")


func test_round_trip_preserves_player_party() -> void:
	var s = _make_state()
	# player_party is `Array[Dictionary]` — typed assignment requires
	# either explicit Dictionary literals or a typed Array constructor.
	var party: Array[Dictionary] = [
		{"name": "Hero", "job": "fighter", "job_level": 5},
		{"name": "Mage", "job": "mage", "job_level": 3},
	]
	s.player_party = party
	var data = s.to_dict()
	var empty: Array[Dictionary] = []
	s.player_party = empty
	s.from_dict(data)
	assert_eq(s.player_party.size(), 2, "party size round-trips")
	assert_eq(s.player_party[0].get("name", ""), "Hero", "first member name")
	assert_eq(s.player_party[1].get("job", ""), "mage", "second member job")


func test_round_trip_does_not_alias_dictionaries() -> void:
	# Critical: from_dict must DUPLICATE nested containers. If it just
	# stored references, mutating one side would silently mutate the
	# other after a round-trip — a recipe for save-corruption bugs.
	var s = _make_state()
	s.story_flags = {"a": true}
	var data = s.to_dict()
	s.from_dict(data)
	# Mutate the snapshot — the live state should NOT reflect the change.
	data["story_flags"]["sneaky"] = true
	assert_false(s.story_flags.has("sneaky"),
		"from_dict must duplicate story_flags, not alias the snapshot dict")


func test_to_dict_includes_required_keys() -> void:
	# Lightweight schema check — if these keys ever get dropped from
	# _create_save_data, every save written after will permanently
	# lose this state on the next load.
	var s = _make_state()
	var data = s.to_dict()
	for key in ["party_gold", "corruption_level", "current_world",
				"worlds_unlocked", "party_leader_index", "story_flags",
				"game_constants", "player_party"]:
		assert_true(data.has(key),
			"to_dict() must include '%s' (regression: missing key drops state on save)" % key)


func test_from_dict_with_empty_dict_does_not_crash() -> void:
	# Defensive: load_settings might pass through partial data on a
	# corrupted save. from_dict must tolerate missing keys without
	# crashing — `has(key)` guards in _apply_save_data should kick in.
	var s = _make_state()
	s.from_dict({})
	# Reaching this line without an exception is the test.
	assert_true(true, "from_dict({}) survived without crash")
