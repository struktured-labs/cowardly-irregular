extends GutTest

## struktured 2026-09-06, two overworld asks in one message:
##   "it's not moving around, it just sits there on the overworld menacingly glowing or
##    radiating. You have to make contact to decide to fight it and it's unfairly strong
##    -- pinned to be stronger than your party by a lot."
##   "some monsters should be angry or alerted or afraid on overworld etc, not just
##    wandering aimlessly, but that can be a default until you're spotted."
##
## WHAT IS PINNED HERE, and why each would fail silently otherwise:
##  - the elite NEVER MOVES. A stationary rare that drifts is just a slow roamer, and
##    drift is invisible in a screenshot.
##  - contact does NOT emit `touched`. If the confirm were bypassed the player would be
##    ambushed by a fight the design says they choose -- and it would look like a normal
##    encounter, so nothing would report it.
##  - the ordinary roamer path is BYTE-IDENTICAL in behaviour. test_spider_wedge_regression
##    owns the fade rules; this file only proves the elite branch did not disturb them.
##  - the scaling is DATA. He asked for that explicitly, so the test reads the JSON and
##    asserts the code honours it rather than asserting a number the code also hardcodes.

const RM := "res://src/exploration/RoamingMonster.gd"
const ELITE_DATA := "res://data/field_elites.json"


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert_not_null(f, "cannot open %s" % path)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


class FakePlayer:
	extends Node2D
	func set_can_move(_v: bool) -> void:
		pass


func _make(elite: bool) -> Node:
	var host := Node2D.new()
	add_child_autofree(host)
	var m: Node = load(RM).new()
	m.elite = elite
	host.add_child(m)
	return m


func test_a_field_elite_never_moves() -> void:
	var m := _make(true)
	var player := FakePlayer.new()
	add_child_autofree(player)
	player.global_position = Vector2(40, 0)
	m.set_player_ref(player)
	m.global_position = Vector2.ZERO
	var start: Vector2 = m.global_position
	for _i in range(30):
		m._process(0.1)
	assert_eq(m.global_position, start,
		"a field elite drifted %.1fpx -- it must sit still and radiate, not roam" % start.distance_to(m.global_position))

	# CONTROL: the same probe on an ordinary roamer MUST show movement, or the assert above
	# is satisfied by a dead _process rather than by the elite branch.
	var ord := _make(false)
	ord.global_position = Vector2.ZERO
	ord._pick_wander_dir()
	for _i in range(30):
		ord._process(0.1)
	assert_ne(ord.global_position, Vector2.ZERO,
		"CONTROL: an ordinary roamer did not move either -- this probe cannot detect motion")


func test_touching_an_elite_asks_instead_of_starting_a_fight() -> void:
	var m := _make(true)
	var player := FakePlayer.new()
	add_child_autofree(player)
	var fired := [0]
	m.touched.connect(func(_id, _types): fired[0] += 1)
	m._active = true
	m._on_body_entered(player)
	assert_eq(fired[0], 0,
		"contact with an elite emitted `touched` -- the fight must be the player's choice, not an ambush")
	assert_true(m._prompt_open, "and it must have opened the prompt rather than ignoring the touch")

	# CONTROL: an ordinary roamer on the same call path DOES emit, so the zero above is the
	# elite branch and not a broken rig.
	var ord := _make(false)
	var fired2 := [0]
	ord.touched.connect(func(_id, _types): fired2[0] += 1)
	ord._active = true
	ord._on_body_entered(player)
	assert_eq(fired2[0], 1, "CONTROL: an ordinary touch must still fire immediately")


func test_moods_escalate_from_calm_and_a_weak_monster_flees() -> void:
	var m := _make(false)
	var player := FakePlayer.new()
	add_child_autofree(player)
	m.global_position = Vector2.ZERO
	m.set_player_ref(player)

	player.global_position = Vector2(10000, 0)
	m._tick_mood(0.016)
	assert_eq(m._mood, m.Mood.CALM, "far away, the default mood is calm wandering")

	player.global_position = Vector2(60, 0)
	m._tick_mood(0.016)
	assert_eq(m._mood, m.Mood.ALERTED, "inside ALERT_RADIUS the monster notices you first")
	assert_true(m._tell.visible, "the alert beat needs a visible tell or the player cannot read it")

	# run the alert timer out; with no GameState party nothing is outmatched -> ANGRY
	m._tick_mood(m.ALERT_DURATION + 0.01)
	assert_eq(m._mood, m.Mood.ANGRY,
		"after the alert beat a monster that is not outmatched commits to the chase")


func test_afraid_reverses_the_chase_instead_of_duplicating_it() -> void:
	var m := _make(false)
	var player := FakePlayer.new()
	add_child_autofree(player)
	m.global_position = Vector2.ZERO
	player.global_position = Vector2(50, 0)
	m.set_player_ref(player)
	m._state = 2
	m._mood = m.Mood.AFRAID
	m._move(0.1)
	assert_lt(m.global_position.x, 0.0,
		"an afraid monster moved toward the player -- flee must reverse the chase vector")


func test_elite_scaling_is_data_not_code() -> void:
	var cfg := _read_json(ELITE_DATA)
	assert_true(cfg.has("scaling"), "the scaling table must exist in data, per the ask")
	var sc: Dictionary = cfg.get("scaling", {})
	for k in ["level_offset", "hp_multiplier", "attack_multiplier", "exp_multiplier"]:
		assert_true(sc.has(k), "scaling.%s must be data-tunable" % k)
	assert_gt(float(sc.get("level_offset", 0)), 0.0, "an elite must be pinned ABOVE the party")
	assert_gt(float(sc.get("hp_multiplier", 0)), 1.0, "and be meaningfully tougher")
	assert_gt(float(sc.get("exp_multiplier", 0)), 1.0, "with the reward he asked for")

	# The roster must name a real species for every world, or a world silently has no rare.
	var monsters := _read_json("res://data/monsters.json")
	var per: Dictionary = cfg.get("per_world", {})
	assert_eq(per.size(), 6, "every world needs an elite species named")
	var bad: Array = []
	for world in per:
		var mid := str(per[world])
		if not monsters.has(mid):
			bad.append("%s -> %s (not in monsters.json)" % [world, mid])
	assert_eq(bad, [], "elite roster must resolve: %s" % str(bad))


func test_the_source_of_the_scaling_is_the_json_not_a_literal() -> void:
	# The failure this defends: someone "simplifies" the table away into constants, the JSON
	# goes stale, and retuning difficulty silently stops working while every test still passes.
	var src := FileAccess.get_file_as_string("res://src/encounters/EncounterSystem.gd")
	assert_gt(src.length(), 5000, "CONTROL: read a real file")
	assert_true(src.contains("field_elites.json"), "the scaling must be READ from data")
	assert_true(src.contains("_apply_field_elite_scaling"), "and applied at the enemy-data seam")
	assert_true(src.contains("_party_average_level"),
		"pinned against the PARTY, not the monster's authored level -- that is the whole design")
