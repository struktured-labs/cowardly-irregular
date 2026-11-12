extends GutTest

## struktured 2026-11-11 (cowir-main 23756/23762): make the battle animations fantastic; adhoc's seat is the
## plain hit. A hit was one fixed recipe (0.07 s hitstop, 6 px knockback, no shake unless it crit). Now every
## hit has a WEIGHT (damage ÷ max HP, + crit, + weakness; a kill is 1) and the hitstop, knockback, squash,
## sparks, zoom, shake and rumble scale from it; a chip hit is exactly the old hit. A plain attack at spotlight
## pace holds its number and its death until the swing LANDS, and every long swing declares the frame it lands on.

const SCENE := preload("res://src/battle/BattleScene.gd")
const ANIMATOR := preload("res://src/battle/BattleAnimator.gd")
const MANIFEST := "res://data/sprite_manifest.json"

## Attack sheets longer than the fast-pace window that have NO swing arc to land on: the hit stays at contact.
## A stale entry (the sheet gained an impact frame, or left the manifest) reds.
const NO_IMPACT := {
	"job guardian": "legacy pose set: six stances, no swing arc",
	"job ninja": "legacy pose set: six stances, no swing arc",
	"job speculator": "legacy pose set: a man with a briefcase, no swing",
	"job summoner": "a casting loop, no strike frame",
	"job bard_sdxl": "unshipped sdxl alternate",
	"job mage_sdxl": "unshipped sdxl alternate",
	"job rogue_sdxl": "unshipped sdxl alternate",
}

var _saved_scale := 1.0
var _saved_rig = null
var _saved_shake = true
var _battle = preload("res://test/unit/helpers/battle_state.gd").new()
var _fx_before: Array = []


func before_each() -> void:
	_battle.snapshot()
	_fx_before = EffectSystem._effects_container.get_children()
	## The scene finds a combatant's sprite through BattleManager's parties: establish them, don't inherit.
	BattleManager.player_party.clear()
	BattleManager.enemy_party.clear()
	_saved_scale = Engine.time_scale
	_saved_rig = BattleJuice.camera_rig
	_saved_shake = GameState.screen_shake_enabled if "screen_shake_enabled" in GameState else true


func after_each() -> void:
	_battle.restore()
	## Leave the shared effects layer as this arm found it: a spark or a beat frees itself on a game-time timer, and
	## one still dying when the NEXT file takes a child-count baseline makes its "the layer grew" arm red by order.
	for child in EffectSystem._effects_container.get_children():
		if not (child in _fx_before):
			child.free()
	Engine.time_scale = _saved_scale
	BattleJuice.camera_rig = _saved_rig
	if "screen_shake_enabled" in GameState:
		GameState.screen_shake_enabled = _saved_shake


func _frames() -> SpriteFrames:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	var frames := SpriteFrames.new()
	for anim in ["idle", "hit", "attack"]:
		if not frames.has_animation(anim):
			frames.add_animation(anim)
		frames.set_animation_loop(anim, anim == "idle")
		frames.set_animation_speed(anim, 30.0)
		frames.add_frame(anim, tex)
	return frames


## [scene, monster, its sprite, its animator, the attacker whose action is resolving]
func _fixture() -> Array:
	var scene = SCENE.new()
	add_child_autofree(scene)
	var foe := Combatant.new()
	autofree(foe)
	foe.combatant_name = "Bat"
	foe.max_hp = 100
	foe.current_hp = 100
	var es := AnimatedSprite2D.new()
	es.sprite_frames = _frames()
	es.position = Vector2(300, 200)
	es.set_meta("home_position", Vector2(300, 200))
	scene.add_child(es)
	es.play("idle")
	scene.test_enemies.append(foe)
	scene.enemy_sprite_nodes.append(es)
	BattleManager.enemy_party.append(foe)
	var animator: ANIMATOR = ANIMATOR.new()
	animator.setup(es)
	scene.add_child(animator)
	scene.enemy_animators.append(animator)
	var hero := Combatant.new()
	autofree(hero)
	hero.combatant_name = "Rogue"
	scene._last_acting_combatant = hero
	return [scene, foe, es, animator, hero]


func test_the_weight_grows_with_damage_crit_and_weakness_and_stays_bounded() -> void:
	var last := -1.0
	for dmg in [0, 5, 10, 25, 50, 75, 100, 400]:
		var w: float = SCENE.hit_weight(dmg, 100)
		assert_between(w, 0.0, 1.0, "weight %.2f out of bounds at %d damage" % [w, dmg])
		assert_gte(w, last, "weight fell as damage rose (%d)" % dmg)
		last = w
		assert_gte(SCENE.hit_weight(dmg, 100, true), w, "a crit weighs less than the same hit")
		assert_gte(SCENE.hit_weight(dmg, 100, false, 2.0), w, "a weakness hit weighs less than the same hit")
	assert_gt(SCENE.hit_weight(20, 100, true), SCENE.hit_weight(20, 100), "CONTROL: a crit must add weight")
	assert_gt(SCENE.hit_weight(20, 100, false, 1.5), SCENE.hit_weight(20, 100), "CONTROL: a weakness must add weight")
	assert_eq(SCENE.hit_weight(1, 100, false, 1.0, true), 1.0, "a killing blow isn't the heaviest hit")
	## A chip hit is .790's hit exactly; the top of each range is bolder; a kill has its own, longest stop.
	assert_almost_eq(SCENE.hitstop_for({"w": 0.0, "kill": false}), 0.07, 0.0001, "a chip hit's hitstop changed from .790's 0.07 s")
	assert_eq(SCENE.HIT_KNOCKBACK.x, 6.0, "a chip hit's knockback changed from .790's 6 px")
	assert_eq(SCENE.hit_trauma(0.05), 0.0, "a chip hit shakes the screen")
	assert_gt(SCENE.hit_trauma(0.5), SCENE.hit_trauma(0.15), "the shake doesn't grow with the weight")
	assert_gt(SCENE.hitstop_for({"w": 1.0, "kill": true}), SCENE.hitstop_for({"w": 1.0, "kill": false}), "the killing blow has no beat of its own")


func test_a_weight_waits_on_the_sprite_for_the_attacker_that_dealt_it() -> void:
	var f := _fixture()
	var scene = f[0]; var foe: Combatant = f[1]; var es: AnimatedSprite2D = f[2]; var hero: Combatant = f[4]
	assert_eq(scene._peek_hit_weight(es, hero, scene._action_serial)["w"], 0.0, "CONTROL: no hit is waiting")
	scene._note_hit_weight(foe, 50, false, "", 1.0)
	assert_almost_eq(float(scene._peek_hit_weight(es, hero, scene._action_serial)["w"]), 0.5, 0.001, "half the monster's HP didn't weigh 0.5")
	scene._note_hit_weight(foe, 5, false, "", 1.0)
	assert_almost_eq(float(scene._peek_hit_weight(es, hero, scene._action_serial)["w"]), 0.5, 0.001, "a lighter hit of the same action replaced the heavier one")
	## cowir-battle 23777: a cast's 50% must not land on the NEXT attacker's chip, and a tick nobody dealt notes nothing.
	var other := Combatant.new()
	autofree(other)
	assert_eq(scene._peek_hit_weight(es, other, scene._action_serial)["w"], 0.0, "another attacker's contact would spend this attacker's weight")
	assert_eq(scene._land_hit_weight(es, other, scene._action_serial)["w"], 0.0, "another attacker's contact landed with this attacker's weight")
	## And the SAME attacker's earlier action (a Fira, then a swing, in one Advance) doesn't lend it either.
	assert_eq(scene._peek_hit_weight(es, hero, scene._action_serial + 1)["w"], 0.0, "the attacker's next action would spend its previous action's weight")
	var landed: Dictionary = scene._land_hit_weight(es, hero, scene._action_serial)
	assert_almost_eq(float(landed["w"]), 0.5, 0.001, "the attacker's own contact didn't get its weight")
	assert_eq(scene._peek_hit_weight(es, hero, scene._action_serial)["w"], 0.0, "the weight was not spent by the hit that took it")
	scene._last_acting_combatant = null
	scene._note_hit_weight(foe, 90, false, "", 1.0)
	assert_false(es.has_meta("hit_weight"), "a hit with no acting combatant (a poison tick) left a weight waiting")
	scene._last_acting_combatant = hero
	foe.current_hp = 0
	foe.is_alive = false
	scene._note_hit_weight(foe, 3, false, "", 1.0)
	assert_true(bool(scene._peek_hit_weight(es, hero, scene._action_serial)["kill"]), "a killing blow isn't marked as one")
	assert_eq(scene._peek_hit_weight(es, hero, scene._action_serial)["w"], 1.0, "a killing blow for 3 damage isn't weight 1")


## A heavy stop pauses the lunge, so a held attack's stage hold grows by the stop's extra (once per action).
func test_a_killing_blow_holds_the_stage_for_its_stop() -> void:
	var saved: float = BattleManager.presentation_hold
	var f := _fixture()
	var scene = f[0]; var foe: Combatant = f[1]
	scene._hold_melee_damage(5.0)
	BattleManager.presentation_hold = 1.0
	scene._note_hit_weight(foe, 3, false, "", 1.0)
	assert_almost_eq(BattleManager.presentation_hold, 1.0 + SCENE.hitstop_for({"w": 0.03}) - SCENE.HIT_HITSTOP.x, 0.0001, "a chip hit's stage hold moved by more than its own stop")
	foe.current_hp = 0
	foe.is_alive = false
	scene._note_hit_weight(foe, 3, false, "", 1.0)
	scene._note_hit_weight(foe, 3, false, "", 1.0)
	assert_almost_eq(BattleManager.presentation_hold, 1.0 + SCENE.HIT_KILL_HITSTOP - SCENE.HIT_HITSTOP.x, 0.0001, "a killing blow's stage hold is %.3f, not the lunge plus its 0.28 s stop (added once)" % BattleManager.presentation_hold)
	scene._land_held_hit()
	BattleManager.presentation_hold = 0.0
	scene._hold_melee_damage(5.0)
	scene._note_hit_weight(foe, 3, false, "", 1.0)
	assert_eq(BattleManager.presentation_hold, 0.0, "a stage hold appeared where none was set (turbo, 4x+)")
	scene._land_held_hit()
	BattleManager.presentation_hold = saved

func _knocked(scene, foe: Combatant, es: AnimatedSprite2D, animator, damage: int) -> float:
	es.position = Vector2(300, 200)
	if damage > 0:
		scene._note_hit_weight(foe, damage, false, "", 1.0)
	scene._land_hit_weight(es, scene._last_acting_combatant, scene._action_serial)
	scene._delayed_play_hit_fx(animator, es)
	## Stepped by hand to the knockback's peak (its first 0.05 s): a sampled maximum misses it whenever one
	## headless frame is long, which the first frame after a spark spawns is.
	var knock: Tween = es.get_meta("knockback_tween")
	knock.pause()
	knock.custom_step(0.05)
	var far: float = absf(es.position.x - 300.0)
	knock.play()
	await wait_seconds(0.4)
	return far

func test_a_heavy_hit_knocks_further_and_shakes_and_a_chip_hit_does_neither() -> void:
	Engine.time_scale = 0.5
	var f := _fixture()
	var scene = f[0]; var foe: Combatant = f[1]; var es: AnimatedSprite2D = f[2]
	var rig := BattleCameraRig.new()
	add_child_autofree(rig)
	BattleJuice.camera_rig = rig
	GameState.screen_shake_enabled = true
	assert_eq(BattleJuice.battle_tier(), BattleJuice.Tier.FULL, "VOID: this arm needs the FULL tier at 0.5x")
	var chip: float = await _knocked(scene, foe, es, f[3], 3)
	assert_between(chip, 3.0, 8.0, "a chip hit knocked the monster %.1f px, not .790's ~6" % chip)
	assert_eq(rig._trauma, 0.0, "a chip hit (3% of max HP) shook the screen")
	var heavy: float = await _knocked(scene, foe, es, f[3], 80)
	assert_gt(heavy, chip + 6.0, "a hit for 80%% of max HP knocked %.1f px, a chip %.1f" % [heavy, chip])
	assert_almost_eq(es.position.x, 300.0, 0.01, "the heavy knockback didn't come home")
	## The Screen Shake setting is the one switch.
	rig._trauma = 0.0
	scene._note_hit_weight(foe, 80, false, "", 1.0)
	scene._land_hit_weight(es, f[4], scene._action_serial)
	scene._delayed_play_hit_fx(f[3], es)
	assert_gt(rig._trauma, 0.2, "CONTROL: a heavy hit must shake the screen when the setting is on (trauma %.2f)" % rig._trauma)
	rig._trauma = 0.0
	GameState.screen_shake_enabled = false
	scene._note_hit_weight(foe, 80, false, "", 1.0)
	scene._land_hit_weight(es, f[4], scene._action_serial)
	scene._delayed_play_hit_fx(f[3], es)
	assert_eq(rig._trauma, 0.0, "a heavy hit shook the screen with Screen Shake OFF")
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var at := src.find("func _delayed_play_hit_fx(")
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_false(body.contains("_trigger_screen_shake("), "the hit path shakes outside the camera rig, past the Screen Shake setting")
	assert_true(body.contains("if _flashes_suppressed():"), "the hit's sparks ignore Reduce Flashes")
	assert_true(src.contains("func _apply_hitstop(attacker_sprite: Node2D, target_sprite: Node2D) -> void:\n\t## The stop's length is the hit's"), "the hitstop no longer takes the hit's length")
	assert_true(body.contains("minf(w, HIT_SPARK_REDUCED_MAX) if _flashes_suppressed() else w"), "the weapon spark grows to full size under Reduce Flashes")


func test_turbo_and_the_console_get_the_old_hit() -> void:
	Engine.time_scale = 0.5
	var f := _fixture()
	var scene = f[0]; var foe: Combatant = f[1]; var es: AnimatedSprite2D = f[2]
	var rig := BattleCameraRig.new()
	add_child_autofree(rig)
	BattleJuice.camera_rig = rig
	GameState.screen_shake_enabled = true
	Engine.time_scale = 4.0
	assert_eq(BattleJuice.battle_tier(), BattleJuice.Tier.OFF, "VOID: 16x must be the OFF tier")
	## At the OFF tier the hit is .790's: the old effect and its one fixed shake, whatever the hit weighed.
	## Only what THIS arm draws: an earlier arm's sparks free themselves on a timer and may still be here.
	var earlier: Array = EffectSystem._effects_container.get_children()
	var before: int = earlier.size()
	scene._delayed_play_hit_fx(f[3], es)
	var chip_trauma: float = rig._trauma
	rig._trauma = 0.0
	scene._note_hit_weight(foe, 80, false, "", 1.0)
	scene._land_hit_weight(es, f[4], scene._action_serial)
	scene._delayed_play_hit_fx(f[3], es)
	assert_almost_eq(rig._trauma, chip_trauma, 0.0001, "at 16x a heavy hit shook differently (%.2f) from a chip hit (%.2f)" % [rig._trauma, chip_trauma])
	var sparks := 0
	for child in EffectSystem._effects_container.get_children():
		if not (child in earlier) and child.has_meta("shape"):
			sparks += 1
	assert_eq(sparks, 0, "the weapon spark drew at 16x")
	assert_gt(EffectSystem._effects_container.get_child_count(), before, "CONTROL: the old hit effect must still draw at 16x")
	Engine.time_scale = 0.5
	var at_16x: Array = EffectSystem._effects_container.get_children()
	scene._delayed_play_hit_fx(f[3], es)
	var drawn := 0
	for child in EffectSystem._effects_container.get_children():
		if not (child in at_16x) and child.has_meta("shape"):
			drawn += 1
	assert_gt(drawn, 0, "CONTROL: at 2x the weapon spark must draw")

func test_a_heavier_hit_still_rumbles_inside_the_gap() -> void:
	Engine.time_scale = 0.5
	var at: float = BattleJuice._last_rumble_at
	var amount: float = BattleJuice._last_rumble_amount
	BattleJuice._last_rumble_at = 100.0
	BattleJuice._last_rumble_amount = 0.0
	assert_false(BattleJuice.should_rumble(0.6, 100.0 + BattleJuice.RUMBLE_MIN_GAP * 0.5), "CONTROL: with no rumble on record the gap holds for any hit")
	BattleJuice._last_rumble_amount = 0.2
	assert_false(BattleJuice.should_rumble(0.2, 100.0 + BattleJuice.RUMBLE_MIN_GAP * 0.5), "CONTROL: an equal hit inside the gap must stay dropped")
	assert_true(BattleJuice.should_rumble(0.6, 100.0 + BattleJuice.RUMBLE_MIN_GAP * 0.5), "a combo's heavy finisher was dropped by the rumble gap")
	assert_true(BattleJuice.should_rumble(0.2, 100.0 + BattleJuice.RUMBLE_MIN_GAP * 2.0), "CONTROL: after the gap any hit rumbles")
	BattleJuice._last_rumble_at = at
	BattleJuice._last_rumble_amount = amount


## Derived from the manifest: every attack sheet longer than the fast-pace window names the frame its hit
## lands on, or is declared above with its reason.
func test_every_long_swing_names_the_frame_it_lands_on() -> void:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	HybridSpriteLoader._load_manifest()
	var long_swings := 0
	var seen := {}
	for section in ["sheets", "monster_sheets"]:
		for id in (m[section] as Dictionary).keys():
			var entry = m[section][id]
			if not (entry is Dictionary) or not entry.has("path"):
				continue
			var frames: SpriteFrames = HybridSpriteLoader._load_external_sheet(entry, str(id)) if section == "sheets" else HybridSpriteLoader.load_monster_sprite_frames(str(id))
			if frames == null or not frames.has_animation("attack"):
				continue
			var length: float = float(frames.get_frame_count("attack")) / frames.get_animation_speed("attack")
			if length <= SCENE.SWING_WINDOW + 0.001:
				continue
			long_swings += 1
			var label := ("job " if section == "sheets" else "monster ") + str(id)
			var impact: int = int((frames.get_meta("impact_frames", {}) as Dictionary).get("attack", 0))
			if NO_IMPACT.has(label):
				seen[label] = true
				assert_eq(impact, 0, "%s is declared to have no impact frame but authors one: remove the declaration" % label)
			else:
				assert_gt(impact, 0, "%s swings for %.2f s and names no impact frame, so its hit lands before it moves" % [label, length])
	assert_gt(long_swings, 20, "VOID: only %d long swings found" % long_swings)
	for label in NO_IMPACT.keys():
		assert_true(seen.has(label), "stale NO_IMPACT entry: %s is no longer a long swing" % label)


## A plain attack at spotlight pace holds its number and its death until contact even with NO impact frame
## (the fighter): unheld, a kill's death had finished before the attacker arrived.
func test_a_plain_attack_holds_its_hit_until_contact() -> void:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for turbo in [false, true]:
		Engine.time_scale = 0.5
		var scene = SCENE.new()
		add_child_autofree(scene)
		scene.turbo_mode = turbo
		var fighter: SpriteFrames = HybridSpriteLoader._load_external_sheet(m["sheets"]["fighter"], "fighter")
		var attacker := AnimatedSprite2D.new()
		attacker.sprite_frames = fighter
		attacker.position = Vector2(600, 0)
		scene.add_child(attacker)
		var animator: ANIMATOR = ANIMATOR.new()
		animator.setup(attacker)
		scene.add_child(animator)
		animator.swing_budget_provider = scene.swing_budget
		var target := AnimatedSprite2D.new()
		target.position = Vector2(100, 0)
		scene.add_child(target)
		assert_eq(animator.impact_time("attack"), 0.0, "VOID: the fighter gained an impact frame; use a sheet without one")
		scene._animate_melee_attack(attacker, target, animator, null, 0.0, "", true)
		match turbo:
			true:
				assert_null(scene._full_render_dmg_buffer, "turbo held a plain hit; it must resolve at once as in .790")
			false:
				assert_not_null(scene._full_render_dmg_buffer, "a plain attack at spotlight pace didn't hold its hit for contact")
				## The lunge stepped by hand: 0.1 s in, the attacker is still on its way (contact is at 0.12-0.17 s).
				var lunge: Tween = attacker.get_meta("attack_tween")
				lunge.pause()
				lunge.custom_step(0.1)
				assert_not_null(scene._full_render_dmg_buffer, "the held hit landed before the attacker arrived")
				lunge.custom_step(0.2)
				assert_null(scene._full_render_dmg_buffer, "the held hit never landed at contact")
				lunge.kill()


## Every weapon type the game can equip draws its OWN spark; bare hands and monsters rake like a claw.
func test_every_weapon_type_draws_its_own_spark() -> void:
	var equipment: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment.json"))
	var types := {}
	var stack: Array = [equipment]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node is Dictionary:
			if node.has("weapon_type"):
				types[str(node["weapon_type"])] = true
			stack.append_array(node.values())
		elif node is Array:
			stack.append_array(node)
	assert_gt(types.size(), 3, "VOID: only %d weapon types found in equipment.json" % types.size())
	for weapon_type in types.keys():
		assert_eq(EffectSystem.hit_spark_shape(weapon_type), weapon_type, "weapon type '%s' has no spark of its own and rakes like a claw" % weapon_type)
	assert_eq(EffectSystem.hit_spark_shape(""), "claw", "CONTROL: bare hands fall back to the claw")
	assert_eq(EffectSystem.hit_spark_shape("no_such_weapon"), "claw", "CONTROL: an unknown type falls back to the claw")
	## Each shape really draws, differently, and bigger for a heavier hit.
	var strokes := {}
	for shape in EffectSystem.HIT_SPARK_SHAPES:
		var light: Node2D = EffectSystem.spawn_hit_spark(Vector2(200, 200), shape, 0.0)
		var heavy: Node2D = EffectSystem.spawn_hit_spark(Vector2(200, 200), shape, 1.0)
		assert_eq(light.get_meta("shape"), shape)
		assert_gt(light.get_child_count(), 0, "%s draws nothing" % shape)
		strokes[shape] = "%d:%s" % [light.get_child_count(), str((light.get_child(0) as Line2D).points)]
		assert_gt(_reach(heavy), _reach(light) * 1.5, "%s is no bigger at weight 1 than at weight 0" % shape)
		var brief: Node2D = EffectSystem.spawn_hit_spark(Vector2(200, 200), shape, 0.5, -1.0, Color.WHITE, true)
		assert_lte(brief.get_child_count(), light.get_child_count(), "%s draws MORE in its brief form" % shape)
		for n in [light, heavy, brief]:
			n.queue_free()
	var distinct := {}
	for shape in strokes.keys():
		distinct[strokes[shape]] = true
	assert_eq(distinct.size(), EffectSystem.HIT_SPARK_SHAPES.size(), "two weapon types draw the same spark")


func _reach(spark: Node2D) -> float:
	var far := 0.0
	for child in spark.get_children():
		if child is Line2D:
			for p in (child as Line2D).points:
				far = maxf(far, p.length())
	return far


## An effect freed before its tween ends (a battle torn down, a grind restart mid-spark, a test's cleanup) must
## not break its own finishing callback: the callback called queue_free on the freed node, raised a script error
## and never reached on_complete. Driven through every effect type, so every builder's callback is exercised.
func test_an_effect_freed_mid_flight_still_finishes() -> void:
	var saved: float = Engine.time_scale
	Engine.time_scale = 1.0
	var was: Node2D = EffectSystem._effects_container
	var host := Node2D.new()
	add_child_autofree(host)
	EffectSystem._effects_container = host
	var done := {}
	var types: Array = EffectSystem.EffectType.values()
	assert_gt(types.size(), 8, "VOID: the effect type list shrank to %d" % types.size())
	for t in types:
		done[t] = 0
		EffectSystem.spawn_effect(t, Vector2(200, 200), func(): done[t] += 1)
	assert_eq(host.get_child_count(), types.size(), "CONTROL: every type put one effect on the layer")
	## The control: one type left alone finishes by itself, so "finished" below is the callback, not the test.
	var kept: Node = host.get_child(0)
	for child in host.get_children():
		if child != kept:
			child.free()
	await get_tree().create_timer(2.5, true, false, true).timeout
	EffectSystem._effects_container = was
	Engine.time_scale = saved
	for t in types:
		assert_eq(done[t], 1, "effect type %s: its finishing callback ran %d times after the effect was freed mid-flight" % [EffectSystem.EffectType.keys()[t], done[t]])
