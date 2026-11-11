extends GutTest

## struktured 2026-11-11 (cowir-main 23993 #3 / 24001): buffs, debuffs and statuses LANDING and EXPIRING, the
## shared layer for every job and monster. Every status the game tints lands with a beat; a stat going up or
## down plays one beat in the stat's colour; anything wearing off plays a quiet puff. Changes that arrive in one
## frame are one gesture (staggered, each smaller), and turbo and the console play nothing.

const SCENE := preload("res://src/battle/BattleScene.gd")
var _battle = preload("res://test/unit/helpers/battle_state.gd").new()
var _saved_scale := 1.0


func before_each() -> void:
	_battle.snapshot()
	BattleManager.player_party.clear()
	BattleManager.enemy_party.clear()
	_saved_scale = Engine.time_scale
	Engine.time_scale = 0.5


func after_each() -> void:
	Engine.time_scale = _saved_scale
	_battle.restore()


## [scene, [combatants]]: `count` monsters with sprites, registered where the scene looks for them, their
## buff and status signals wired as the scene's own setup wires them.
func _fixture(count: int) -> Array:
	var scene = SCENE.new()
	add_child_autofree(scene)
	var foes: Array = []
	for i in count:
		var foe := Combatant.new()
		autofree(foe)
		foe.combatant_name = "Foe %d" % i
		foe.max_hp = 100
		foe.current_hp = 100
		var es := AnimatedSprite2D.new()
		es.position = Vector2(200 + 80 * i, 200)
		scene.add_child(es)
		scene.test_enemies.append(foe)
		scene.enemy_sprite_nodes.append(es)
		BattleManager.enemy_party.append(foe)
		foe.buff_changed.connect(scene._on_buff_changed.bind(foe))
		foe.status_removed.connect(scene._on_status_lapsed.bind(foe))
		foes.append(foe)
	return [scene, foes]


func _plan(scene) -> Array:
	await get_tree().process_frame
	await get_tree().process_frame
	return scene._last_change_plan


## Derived: every status BattleScene tints has a landed beat, and every beat named is a real sequence.
func test_every_tinted_status_lands_with_a_beat() -> void:
	assert_gt(SCENE.STATUS_TINTS.size(), 8, "VOID: the tint table shrank to %d" % SCENE.STATUS_TINTS.size())
	for status in SCENE.STATUS_TINTS.keys():
		var beat: String = SCENE.landed_beat(status)
		assert_ne(beat, "", "%s is tinted but lands with no beat" % status)
		assert_false(FractalFX.load_sequence(beat).is_empty(), "%s names the beat '%s', which is not a sequence" % [status, beat])
	assert_eq(SCENE.landed_beat("no_such_status"), "", "CONTROL: an unknown status has no beat")
	for beat in SCENE.LANDED_BEATS.values():
		assert_false(FractalFX.load_sequence(beat).is_empty(), "LANDED_BEATS names '%s', which is not a sequence" % beat)
	assert_false(FractalFX.load_sequence(SCENE.WORE_OFF_BEAT).is_empty(), "the wore-off beat is not a sequence")


## Derived from abilities.json: every stat a buff or debuff names resolves to a real up AND down beat, and
## the five combat stats have their OWN colour, not the plain one.
func test_every_stat_a_buff_names_has_its_beats() -> void:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var abilities: Dictionary = parsed.get("abilities", parsed)
	var stats := {}
	for id in abilities.keys():
		var row = abilities[id]
		if row is Dictionary and row.has("stat") and str(row["stat"]) != "":
			stats[str(row["stat"])] = true
	assert_gt(stats.size(), 2, "VOID: only %d stats found on ability rows" % stats.size())
	for stat in stats.keys():
		for direction in [1, -1]:
			var beat: String = SCENE.stat_beat(stat, direction)
			assert_false(FractalFX.load_sequence(beat).is_empty(), "stat '%s' %+d resolves to '%s', which is not a sequence" % [stat, direction, beat])
	for stat in ["attack", "defense", "magic", "magic_defense", "speed"]:
		assert_eq(SCENE.stat_beat(stat, 1), "stat_up_" + stat, "%s going up has no colour of its own" % stat)
		assert_eq(SCENE.stat_beat(stat, -1), "stat_down_" + stat, "%s going down has no colour of its own" % stat)
	assert_eq(SCENE.stat_beat("no_such_stat", 1), "stat_up", "CONTROL: an unknown stat falls back to the plain beat")


## A buff appearing plays ONE up beat; refreshed while active, nothing; running out, one wore-off; and a
## dead owner's lapse, nothing.
func test_a_buff_plays_once_when_it_lands_and_once_when_it_lapses() -> void:
	var f := _fixture(1)
	var scene = f[0]; var foe: Combatant = f[1][0]
	foe.add_buff("iron_guard", "defense", 1.5, 2)
	var plan: Array = await _plan(scene)
	assert_eq(plan.size(), 1, "a buff landing played %d beats" % plan.size())
	assert_eq(str(plan[0]["seq"]) if plan.size() > 0 else "", "stat_up_defense", "the wrong beat for defense going up")
	scene._last_change_plan = []
	foe.add_buff("iron_guard", "defense", 1.5, 2)
	plan = await _plan(scene)
	assert_eq(plan.size(), 0, "a buff REFRESHED while active played a second landing")
	foe.add_debuff("slow", "speed", 0.5, 2)
	plan = await _plan(scene)
	assert_eq(str(plan[0]["seq"]) if plan.size() > 0 else "", "stat_down_speed", "the wrong beat for speed going down")
	scene._last_change_plan = []
	for turn in 3:
		foe.update_buff_durations()
	plan = await _plan(scene)
	assert_eq(plan.size(), 1, "a buff and a debuff running out together played %d wore-off beats, not one" % plan.size())
	assert_eq(str(plan[0]["seq"]) if plan.size() > 0 else "", SCENE.WORE_OFF_BEAT)
	## A dead owner: its buffs lapse silently.
	scene._last_change_plan = []
	foe.add_buff("enrage", "attack", 1.5, 1)
	await _plan(scene)
	scene._last_change_plan = []
	foe.is_alive = false
	for turn in 2:
		foe.update_buff_durations()
	plan = await _plan(scene)
	assert_eq(plan.size(), 0, "a dead monster's buff wore off with a beat")


## A party-wide buff is ONE gesture: five beats staggered, each drawn smaller, and under Reduce Flashes the
## whole gesture is no brighter than a single beat.
func test_a_party_wide_buff_is_one_gesture() -> void:
	var f := _fixture(5)
	var scene = f[0]
	for foe in f[1]:
		foe.add_buff("howl", "attack", 1.25, 3)
	var plan: Array = await _plan(scene)
	assert_eq(plan.size(), 5, "VOID: five buffs landing planned %d beats" % plan.size())
	for i in range(1, plan.size()):
		assert_gt(float(plan[i]["delay"]), float(plan[i - 1]["delay"]), "two beats of one gesture start on the same frame")
	assert_almost_eq(float(plan[0]["power"]), 1.0 / sqrt(5.0), 0.001, "five beats were not each drawn smaller")
	assert_eq(SCENE.change_beat_power(1, false), 1.0, "CONTROL: a single beat is full size")
	assert_almost_eq(SCENE.change_beat_power(5, true) * 5.0, 1.0, 0.001, "under Reduce Flashes five beats add up to more than one")
	assert_lt(SCENE.change_beat_power(5, true), SCENE.change_beat_power(5, false), "Reduce Flashes doesn't shrink a party-wide gesture")


## Turbo and the grind console play nothing (cowir-autogrind 24003): a buff landing or lapsing draws 0 nodes.
func test_turbo_and_the_console_play_no_change_beat() -> void:
	for mode in ["normal", "turbo", "console"]:
		var f := _fixture(1)
		var scene = f[0]; var foe: Combatant = f[1][0]
		scene.turbo_mode = mode == "turbo"
		scene.autogrind_console_mode = mode == "console"
		var before: int = EffectSystem._effects_container.get_child_count()
		foe.add_buff("iron_guard", "defense", 1.5, 1)
		var plan: Array = await _plan(scene)
		var drew: int = EffectSystem._effects_container.get_child_count() - before
		match mode:
			"normal":
				assert_eq(plan.size(), 1, "CONTROL: at 2x a buff landing must plan a beat")
				assert_gt(drew, 0, "CONTROL: at 2x a buff landing must draw")
			_:
				assert_eq(plan.size(), 0, "a buff landing planned a beat in %s" % mode)
				assert_eq(drew, 0, "a buff landing drew %d nodes in %s" % [drew, mode])
		scene._last_change_plan = []
		foe.update_buff_durations()
		foe.update_buff_durations()
		plan = await _plan(scene)
		if mode != "normal":
			assert_eq(plan.size(), 0, "a buff wearing off planned a beat in %s" % mode)


## A formation stance is a posture, not a spell: it lands with no beat. A status that runs out by itself gets
## the wore-off; one removed inside an action (a cure) does not.
func test_a_stance_and_a_cure_play_no_beat() -> void:
	var f := _fixture(1)
	var scene = f[0]; var foe: Combatant = f[1][0]
	foe.add_buff("formation_front_line", "attack", 1.2, 99)
	var plan: Array = await _plan(scene)
	assert_eq(plan.size(), 0, "a formation stance landed with a stat-up beat")
	foe.add_buff("enrage", "attack", 1.5, 3)
	plan = await _plan(scene)
	assert_eq(plan.size(), 1, "CONTROL: a real buff on the same stat must still land")
	scene._last_change_plan = []
	scene._last_acting_combatant = null
	scene._on_status_lapsed("poison", foe)
	plan = await _plan(scene)
	assert_eq(str(plan[0]["seq"]) if plan.size() > 0 else "", SCENE.WORE_OFF_BEAT, "a status that ran out played no wore-off")
	scene._last_change_plan = []
	scene._last_acting_combatant = foe
	scene._on_status_lapsed("poison", foe)
	plan = await _plan(scene)
	assert_eq(plan.size(), 0, "a status removed inside an action (a cure) played the wore-off")
	scene._last_acting_combatant = null
	scene._on_status_lapsed("no_such_status", foe)
	plan = await _plan(scene)
	assert_eq(plan.size(), 0, "a status with no landed beat wore off with one")


## cowir-sprites 24010: an ability with its own melee overlay owns the cut, so the hit path draws NO weapon spark
## under it (Power Strike's crack had a sword arc beneath it); a plain attack still draws its weapon's spark, or
## its monster's family sequence when the row names one that exists.
func test_an_overlay_owns_the_cut_and_a_family_replaces_the_spark() -> void:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var abilities: Dictionary = parsed.get("abilities", parsed)
	var with_overlay := ""
	var without := ""
	for id in abilities.keys():
		var row = abilities[id]
		if not (row is Dictionary) or str(row.get("type", "")) != "physical":
			continue
		if SCENE.melee_overlay(row, "melee") != "" or SCENE.melee_overlay(row, "melee_each") != "":
			with_overlay = str(id) if with_overlay == "" else with_overlay
		elif without == "":
			without = str(id)
	assert_ne(with_overlay, "", "VOID: no physical ability carries a melee overlay")
	assert_ne(without, "", "VOID: every physical ability carries a melee overlay")
	assert_eq(SCENE.hit_mark(with_overlay, "sword"), "overlay", "%s has its own overlay and still draws the weapon spark" % with_overlay)
	assert_eq(SCENE.hit_mark(without, "sword"), "spark", "CONTROL: %s has no overlay and must draw the weapon spark" % without)
	assert_eq(SCENE.hit_mark("", "sword"), "spark", "CONTROL: a plain attack draws its weapon's spark")
	assert_eq(SCENE.hit_mark("", "no_such_family"), "spark", "an unnamed family must fall back to the spark")
	## A family that exists as a sequence replaces the spark on a PLAIN attack only.
	var family := ""
	var seqs: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/vfx_sequences.json")) as Dictionary).get("sequences", {})
	for id in seqs.keys():
		if str(id).begins_with(SCENE.HIT_FAMILY_PREFIX) and not str(id).trim_prefix(SCENE.HIT_FAMILY_PREFIX).contains("_"):
			family = str(id).trim_prefix(SCENE.HIT_FAMILY_PREFIX)
			break
	assert_ne(family, "", "VOID: no family_<name> sequence exists")
	assert_eq(SCENE.hit_mark("", family), "family", "a plain attack whose row names family '%s' still rakes like a claw" % family)
	assert_eq(SCENE.hit_mark(without, family), "spark", "an ABILITY must not take the attacker's plain-attack family")
	## And the hit path obeys it: with an overlay ability acting, no weapon spark node is drawn.
	var f := _fixture(1)
	var scene = f[0]; var foe: Combatant = f[1][0]
	var es: AnimatedSprite2D = scene.enemy_sprite_nodes[0]
	var frames := SpriteFrames.new()
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	for anim in ["idle", "hit"]:
		if not frames.has_animation(anim):
			frames.add_animation(anim)
		frames.add_frame(anim, ImageTexture.create_from_image(img))
	es.sprite_frames = frames
	var animator = preload("res://src/battle/BattleAnimator.gd").new()
	animator.setup(es)
	scene.add_child(animator)
	for case in [[with_overlay, 0], ["", 1]]:
		scene._current_ability_id = case[0]
		var earlier: Array = EffectSystem._effects_container.get_children()
		scene._delayed_play_hit_fx(animator, es)
		var sparks := 0
		for child in EffectSystem._effects_container.get_children():
			if not (child in earlier) and child.has_meta("shape"):
				sparks += 1
		assert_eq(sparks, case[1], "with ability '%s' acting the hit drew %d weapon sparks, not %d" % [case[0], sparks, case[1]])
	scene._current_ability_id = ""
