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
	m.touched.connect(func(_id, _types, _elite): fired[0] += 1)
	m._active = true
	m._on_body_entered(player)
	assert_eq(fired[0], 0,
		"contact with an elite emitted `touched` -- the fight must be the player's choice, not an ambush")
	assert_true(m._prompt_open, "and it must have opened the prompt rather than ignoring the touch")

	# CONTROL: an ordinary roamer on the same call path DOES emit, so the zero above is the
	# elite branch and not a broken rig.
	var ord := _make(false)
	var fired2 := [0]
	ord.touched.connect(func(_id, _types, _elite): fired2[0] += 1)
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


## THE SIMULATION CLAIM, and the reason the source-text test below is not enough on its own.
## That one asserts this file CONTAINS the right words. It shipped green in .225 while the
## scaling read a DEFAULT LEVEL OF 1 -- "level" was never copied into the enemy-data dict --
## so growth compounded from 1 instead of the monster's authored level and every field elite
## fought 1.4x-1.7x tougher than the table says, worst at low party levels. dark_knight
## (authored 12) resolved to LEVEL 6. A test that reads source can never see that; only
## resolving a monster through the real path can.
func test_an_elite_actually_resolves_to_the_stats_the_table_describes() -> void:
	var es: Node = get_tree().root.get_node_or_null("EncounterSystem")
	var gs: Node = get_tree().root.get_node_or_null("GameState")
	assert_not_null(es, "EncounterSystem autoload")
	assert_not_null(gs, "GameState autoload")
	if es == null or gs == null:
		return

	var cfg := _read_json(ELITE_DATA)
	var sc: Dictionary = cfg.get("scaling", {})
	var monsters := _read_json("res://data/monsters.json")
	var dk: Dictionary = monsters.get("dark_knight", {})
	assert_true(dk.get("field_elite", false), "dark_knight must be the authored field elite")
	var authored_level := float(dk.get("level", 0))
	var authored_hp := float(dk.get("stats", {}).get("max_hp", 0))
	assert_gt(authored_level, 1.0, "CONTROL: the authored level must be > 1, or the bug this defends is unobservable")

	var saved: Array[Dictionary] = gs.player_party
	var party: Array[Dictionary] = []
	for i in range(4):
		party.append({"name": "probe%d" % i, "job_level": 10})
	gs.player_party = party

	var d: Dictionary = es._create_enemy_data("dark_knight")

	# level is pinned ABOVE the party, never below the monster's own authored level
	var expect_level := maxf(10.0 + float(sc.get("level_offset", 5)), authored_level)
	assert_eq(int(d.get("level", -1)), int(round(expect_level)),
		"an elite met by a level-10 party must be level %d" % int(round(expect_level)))

	# growth is measured from the AUTHORED level, which is the half that was broken
	var growth := 1.0 + maxf(0.0, expect_level - authored_level) * float(sc.get("per_level_stat_growth", 0.0))
	var expect_hp := int(round(authored_hp * float(sc.get("hp_multiplier", 1.0)) * growth))
	assert_eq(int(d.get("max_hp", -1)), expect_hp,
		"hp must follow authored x multiplier x growth-from-AUTHORED-level (%d). Reading a default base of 1 inflates this ~1.7x" % expect_hp)

	# CONTROL: a non-elite must come back untouched, or "scaled" is meaningless
	var plain: Dictionary = es._create_enemy_data("goblin")
	var goblin_hp := float(monsters.get("goblin", {}).get("stats", {}).get("max_hp", 0))
	assert_eq(int(plain.get("max_hp", -1)), int(goblin_hp),
		"CONTROL: an ordinary monster must resolve to its authored hp, unscaled")

	# THE LOW-PARTY CASE, where the authored floor is load-bearing. Without it a party below
	# (authored_level - level_offset) meets an elite WEAKER than its own table entry -- the
	# opposite of "unfairly strong". Mutating the floor away is green at party 10 (the target
	# already clears the authored level there), so this case is what actually guards it.
	var low: Array[Dictionary] = []
	for i in range(3):
		low.append({"name": "low%d" % i, "job_level": 5})
	gs.player_party = low
	var dlow: Dictionary = es._create_enemy_data("dark_knight")
	assert_gte(float(dlow.get("level", 0)), authored_level,
		"a field elite met by a weak party must never resolve BELOW its authored level %d" % int(authored_level))
	assert_gte(float(dlow.get("max_hp", 0)), authored_hp * float(sc.get("hp_multiplier", 1.0)),
		"nor below its authored hp times the table's multiplier")

	gs.player_party = saved


func test_the_source_of_the_scaling_is_the_json_not_a_literal() -> void:
	# The failure this defends: someone "simplifies" the table away into constants, the JSON
	# goes stale, and retuning difficulty silently stops working while every test still passes.
	var src := FileAccess.get_file_as_string("res://src/encounters/EncounterSystem.gd")
	assert_gt(src.length(), 5000, "CONTROL: read a real file")
	assert_true(src.contains("field_elites.json"), "the scaling must be READ from data")
	assert_true(src.contains("_apply_field_elite_scaling"), "and applied at the enemy-data seam")
	assert_true(src.contains("_party_average_level"),
		"pinned against the PARTY, not the monster's authored level -- that is the whole design")

## BestiarySystem is a class_name with STATIC functions, NOT an autoload. Seven call sites in
## this lane reached it with get_node_or_null("BestiarySystem"), which returns null forever,
## so both helpers silently returned their fallbacks and TWO shipped features were inert:
## field elites never fought alone, and every monster read as level 1 so AFRAID fired for the
## whole bestiary once the party passed level 5. Nothing errored -- a null check took the
## other branch and returned a plausible default.
func test_the_bestiary_is_reached_by_the_static_call_not_a_node_lookup() -> void:
	var monsters := _read_json("res://data/monsters.json")
	var goblin_level := int(monsters.get("goblin", {}).get("level", 0))
	assert_gt(goblin_level, 1, "CONTROL: goblin's authored level must exceed the fallback of 1, or this cannot detect the bug")

	var rm = load("res://src/exploration/RoamingMonster.gd").new()
	var host := Node2D.new()
	add_child_autofree(host)
	host.add_child(rm)
	rm.monster_id = "goblin"
	assert_eq(rm._monster_level(), goblin_level,
		"a monster must report its AUTHORED level; a fallback of 1 makes every monster read as trivially weak")

	rm.monster_id = "zzz_not_a_monster"
	assert_eq(rm._monster_level(), 1, "CONTROL: an unknown id still falls back rather than crashing")

	# and the pattern itself must not come back anywhere in the lane
	var offenders: Array = []
	var dir := DirAccess.open("res://src/exploration")
	if dir:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".gd"):
				var src := FileAccess.get_file_as_string("res://src/exploration/%s" % f)
				if src.contains("get_node_or_null(\"BestiarySystem\")"):
					offenders.append(f)
			f = dir.get_next()
	assert_eq(offenders, [],
		"BestiarySystem has no autoload to find; these look it up as a node and get null every time: %s" % str(offenders))


## The solo-elite guard depends on that lookup, so it was inert in all six worlds.
func test_an_elite_is_recognised_as_one() -> void:
	var scene = load("res://src/exploration/OverworldScene.gd").new()
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	vp.add_child(scene)
	await get_tree().physics_frame
	assert_true(scene._is_field_elite("dark_knight"),
		"the authored field elite must be recognised, or it spawns with the 0-2 random duplicates any roamer gets")
	assert_false(scene._is_field_elite("goblin"),
		"CONTROL: an ordinary monster must not be treated as an elite")

## ELITE IS A PROPERTY OF THE SPAWN, NOT OF THE SPECIES -- the distinction the data model
## could not express until 2026-09-09, and the reason a correct-looking fix was reverted.
## Five of six worlds promote an ORDINARY monster to elite duty (only dark_knight was authored
## elite-only), so setting field_elite on the species would have made every routine encounter
## with a rust elemental, a brass golem, a suburban dog, a data wraith or optimization_itself
## a party-average+5, x3 HP, x8 EXP fight -- a difficulty inversion and a grind exploit in five
## worlds, shipping as a bug fix.
func test_a_promoted_species_is_only_elite_when_the_SPAWN_says_so() -> void:
	var es: Node = get_tree().root.get_node_or_null("EncounterSystem")
	var gs: Node = get_tree().root.get_node_or_null("GameState")
	assert_not_null(es); assert_not_null(gs)
	if es == null or gs == null:
		return
	var cfg := _read_json(ELITE_DATA)
	var monsters := _read_json("res://data/monsters.json")
	var pools := _read_json("res://data/enemy_pools.json")
	var saved: Array[Dictionary] = gs.player_party
	var party: Array[Dictionary] = []
	for i2 in range(4):
		party.append({"name": "p%d" % i2, "job_level": 10})
	gs.player_party = party

	var checked := 0
	var offenders: Array = []
	for world in cfg.get("per_world", {}):
		var sp := str(cfg["per_world"][world])
		checked += 1
		var flagged := bool(monsters.get(sp, {}).get("field_elite", false))
		var in_ordinary_pool := false
		for pk in pools:
			var ids = pools[pk]
			if ids is Array and sp in ids:
				in_ordinary_pool = true

		# BIDIRECTIONAL. A species that also roams ordinarily must NOT carry the flag, or every
		# routine encounter with it becomes an elite fight. A species that exists only as an
		# elite MUST carry it, or it never scales however it spawns.
		if flagged and in_ordinary_pool:
			offenders.append("%s: %s carries field_elite AND appears in an ordinary pool -- every routine encounter with it is now a party-average+5, x3 HP, x8 EXP fight" % [world, sp])
		if not flagged and not in_ordinary_pool:
			offenders.append("%s: %s exists only as an elite but carries no field_elite flag -- it will never scale" % [world, sp])

		if in_ordinary_pool:
			var authored_hp := float(monsters.get(sp, {}).get("stats", {}).get("max_hp", 0))
			var ordinary: Dictionary = es._create_enemy_data(sp)
			var elite: Dictionary = es._create_enemy_data(sp + EncounterSystem.ELITE_SUFFIX)
			if int(ordinary.get("max_hp", -1)) != int(authored_hp):
				offenders.append("%s: an ORDINARY %s resolved to %s hp, not its authored %d" % [world, sp, str(ordinary.get("max_hp")), int(authored_hp)])
			if int(elite.get("max_hp", -1)) <= int(authored_hp):
				offenders.append("%s: a SPAWN-MARKED %s resolved to %s hp, not scaled above its authored %d" % [world, sp, str(elite.get("max_hp")), int(authored_hp)])

	assert_eq(checked, 6, "all six worlds' elite species must be examined, saw %d" % checked)
	assert_eq(offenders, [], "\n  ".join(offenders))

	var dk: Dictionary = es._create_enemy_data("dark_knight")
	assert_true(bool(dk.get("field_elite", false)),
		"dark_knight is authored elite-only and must stay elite with no spawn marker")
	gs.player_party = saved

## IGNORING A RARE MUST NOT DESTROY IT. The elite is a landmark you decide about -- "it just
## sits there", "you have to make contact to DECIDE to fight it". Distance culling made that
## decision one-way: FIGHTING it preserved it (it fades and respawns at its spawn origin),
## while DECLINING and walking past DESPAWN_DISTANCE deleted it outright, and the cooldown
## then had to elapse before another could roll anywhere at all. Walking away was the
## destructive option, which is the opposite of what a decision should cost.
func test_walking_away_from_an_elite_does_not_delete_it() -> void:
	var Spawner = load("res://src/exploration/MonsterSpawner.gd")
	var RM = load("res://src/exploration/RoamingMonster.gd")
	var sp = Spawner.new()
	add_child_autofree(sp)
	var host := Node2D.new()
	add_child_autofree(host)

	var player := Node2D.new()
	add_child_autofree(player)
	player.global_position = Vector2.ZERO
	sp._player = player

	var elite = RM.new()
	elite.elite = true
	host.add_child(elite)
	var ordinary = RM.new()
	ordinary.elite = false
	host.add_child(ordinary)
	await get_tree().physics_frame

	# both parked well beyond the cull radius
	var far := Vector2(sp.DESPAWN_DISTANCE * 3.0, 0.0)
	elite.global_position = far
	ordinary.global_position = far
	sp._monsters = [elite, ordinary]

	sp._cull_far_monsters()

	assert_true(is_instance_valid(elite) and elite in sp._monsters,
		"a field elite must survive the player walking away -- declining a fight cannot be the destructive choice")
	# CONTROL: an ordinary roamer at the same distance MUST still be culled, or the exemption
	# is really a broken cull and this test proves nothing about elites.
	assert_false(ordinary in sp._monsters,
		"CONTROL: an ordinary roamer at the same distance must still be culled")

## "SOME monsters should be angry or alerted or AFRAID" -- a MIX, and the level gap alone
## cannot deliver one. It is an absolute threshold, so it swallows the whole roster as the
## party levels: measured 2026-09-09, at party level 10 every monster in W1/W2/W3 flees and by
## 20 every monster in every world does. You outlevel a world before you leave it, so the
## common case was "everything runs away", and since the player moves at 240 against a flee
## speed of 130 that is a chase on every single encounter rather than an escape.
func test_fear_is_a_disposition_so_a_world_always_has_both_kinds() -> void:
	var RM := load("res://src/exploration/RoamingMonster.gd")
	var host := Node2D.new()
	add_child_autofree(host)

	var timid := 0
	var bold := 0
	for i in range(120):
		var m = RM.new()
		m.monster_id = "goblin"
		host.add_child(m)
		m._spawn_origin = Vector2((i * 37) % 3000, (i * 53) % 2000)
		if m._is_timid():
			timid += 1
		else:
			bold += 1

	assert_gt(timid, 10, "a world with no timid monsters has no AFRAID mood at all (%d/120)" % timid)
	assert_gt(bold, 10, "a world where every outmatched monster flees makes every late-game encounter a chase (%d/120 bold)" % bold)

	# STABILITY: a monster must not change its nerve while the player is looking at it.
	var m2 = RM.new()
	m2.monster_id = "goblin"
	host.add_child(m2)
	m2._spawn_origin = Vector2(512, 384)
	var first: bool = m2._is_timid()
	for i in range(30):
		assert_eq(m2._is_timid(), first, "timidity must be a fixed disposition, not a per-frame roll")

	# and a BOLD monster stays bold even when the party badly outlevels it
	var gs: Node = get_tree().root.get_node_or_null("GameState")
	if gs != null:
		var saved: Array[Dictionary] = gs.player_party
		var party: Array[Dictionary] = []
		for i in range(4):
			party.append({"name": "p%d" % i, "job_level": 30})
		gs.player_party = party
		var found_bold := false
		for i in range(120):
			var m3 = RM.new()
			m3.monster_id = "goblin"
			host.add_child(m3)
			m3._spawn_origin = Vector2((i * 91) % 2500, (i * 41) % 1700)
			if not m3._is_timid():
				found_bold = true
				assert_false(m3._is_outmatched(),
					"a BOLD monster must charge even a level-30 party -- otherwise the mix collapses back to all-flee")
				break
		assert_true(found_bold, "CONTROL: the sweep must actually find a bold monster, or the assert above never ran")
		gs.player_party = saved
