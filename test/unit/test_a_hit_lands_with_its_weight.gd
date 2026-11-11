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


func before_each() -> void:
	_saved_scale = Engine.time_scale
	_saved_rig = BattleJuice.camera_rig
	_saved_shake = GameState.screen_shake_enabled if "screen_shake_enabled" in GameState else true


func after_each() -> void:
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


## [scene, monster, its sprite, its animator]
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
	var animator: ANIMATOR = ANIMATOR.new()
	animator.setup(es)
	scene.add_child(animator)
	scene.enemy_animators.append(animator)
	return [scene, foe, es, animator]


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


func test_a_weight_waits_on_the_sprite_for_the_swing_that_spends_it() -> void:
	var f := _fixture()
	var scene = f[0]; var foe: Combatant = f[1]; var es: AnimatedSprite2D = f[2]
	assert_eq(scene._peek_hit_weight(es)["w"], 0.0, "CONTROL: no hit is waiting")
	scene._note_hit_weight(foe, 50, false, "", 1.0)
	assert_almost_eq(float(scene._peek_hit_weight(es)["w"]), 0.5, 0.001, "half the monster's HP didn't weigh 0.5")
	scene._note_hit_weight(foe, 5, false, "", 1.0)
	assert_almost_eq(float(scene._peek_hit_weight(es)["w"]), 0.5, 0.001, "a lighter hit replaced the heavier one still waiting")
	var taken: Dictionary = scene._take_hit_weight(es)
	assert_almost_eq(float(taken["w"]), 0.5, 0.001)
	assert_eq(scene._peek_hit_weight(es)["w"], 0.0, "the weight was not spent by the hit that took it")
	foe.current_hp = 0
	foe.is_alive = false
	scene._note_hit_weight(foe, 3, false, "", 1.0)
	assert_true(bool(scene._peek_hit_weight(es)["kill"]), "a killing blow isn't marked as one")
	assert_eq(scene._peek_hit_weight(es)["w"], 1.0, "a killing blow for 3 damage isn't weight 1")


func _knocked(scene, foe: Combatant, es: AnimatedSprite2D, animator, damage: int) -> float:
	es.position = Vector2(300, 200)
	if damage > 0:
		scene._note_hit_weight(foe, damage, false, "", 1.0)
	scene._delayed_play_hit_fx(animator, es)
	var far := 0.0
	for i in 12:
		await get_tree().process_frame
		far = maxf(far, absf(es.position.x - 300.0))
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
	scene._delayed_play_hit_fx(f[3], es)
	assert_gt(rig._trauma, 0.2, "CONTROL: a heavy hit must shake the screen when the setting is on (trauma %.2f)" % rig._trauma)
	rig._trauma = 0.0
	GameState.screen_shake_enabled = false
	scene._note_hit_weight(foe, 80, false, "", 1.0)
	scene._delayed_play_hit_fx(f[3], es)
	assert_eq(rig._trauma, 0.0, "a heavy hit shook the screen with Screen Shake OFF")
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var at := src.find("func _delayed_play_hit_fx(")
	var body := src.substr(at, src.find("\nfunc ", at + 1) - at)
	assert_false(body.contains("_trigger_screen_shake("), "the hit path shakes outside the camera rig, past the Screen Shake setting")
	assert_true(body.contains("if _reduce_flashes():"), "the hit's sparks ignore Reduce Flashes")


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
	scene._note_hit_weight(foe, 80, false, "", 1.0)
	scene._delayed_play_hit_fx(f[3], es)
	assert_eq(rig._trauma, 0.0, "a heavy hit shook the screen at 16x")


func test_a_heavier_hit_still_rumbles_inside_the_gap() -> void:
	Engine.time_scale = 0.5
	var at: float = BattleJuice._last_rumble_at
	var amount: float = BattleJuice._last_rumble_amount
	BattleJuice._last_rumble_at = 100.0
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
				await wait_seconds(0.1)
				assert_not_null(scene._full_render_dmg_buffer, "the held hit landed before the attacker arrived")
				await wait_seconds(0.5)
				assert_null(scene._full_render_dmg_buffer, "the held hit never landed at contact")


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
