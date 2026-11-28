extends GutTest

## His .808 log: "Rogue uses Mug!" lands with `attack_hit`, the generic thwack, while her plain attacks play the dagger.
## Measured in a real battle (cowir-sfx probe, .812): action_executed fires in the action's own frame and clears
## _last_acting_combatant, and the lunge makes contact 60-100 frames later, so the contact read a null attacker: 15 of 15
## hits drew the claw spark, and a physical ability (which has no other hit cue) never played its weapon's hit or crit.
## The landing now carries its attacker, and the crit, to the contact.

const SCENE := preload("res://src/battle/BattleScene.gd")
const BattleSceneFixture := preload("res://test/unit/helpers/battle_scene_fixture.gd")
const ANIMATOR := preload("res://src/battle/BattleAnimator.gd")
const STARTERS: Array[String] = ["fighter", "cleric", "mage", "rogue", "bard"]

var _battle = preload("res://test/unit/helpers/battle_state.gd").new()
var _fx_before: Array = []
var _saved_scale := 1.0


func before_each() -> void:
	_battle.snapshot()
	_fx_before = EffectSystem._effects_container.get_children()
	BattleManager.player_party.clear()
	BattleManager.enemy_party.clear()
	_saved_scale = Engine.time_scale
	SoundManager._battle_player.stop()
	SoundManager._battle_player.stream = null


func after_each() -> void:
	_battle.restore()
	for child in EffectSystem._effects_container.get_children():
		if not (child in _fx_before):
			child.free()
	Engine.time_scale = _saved_scale
	SoundManager._battle_player.stop()


func _frames() -> SpriteFrames:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	var frames := SpriteFrames.new()
	for anim in ["idle", "hit", "attack"]:
		if not frames.has_animation(anim):
			frames.add_animation(anim)
		frames.set_animation_loop(anim, anim == "idle")
		frames.add_frame(anim, tex)
	return frames


## [scene, foe, its sprite, its animator, a hero holding `weapon_id`]
func _fixture(weapon_id: String) -> Array:
	var scene = BattleSceneFixture.build()
	add_child_autofree(scene)
	## The real scene's _ready spawned its own foes; this fixture's foe must be index 0, where the scene looks.
	scene.test_enemies.clear()
	scene.enemy_sprite_nodes.clear()
	scene.enemy_animators.clear()
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
	scene.test_enemies.append(foe)
	scene.enemy_sprite_nodes.append(es)
	## One foe per scene: the scene finds a sprite by its index in BattleManager's party, so an earlier fixture's foe must go.
	BattleManager.enemy_party.clear()
	BattleManager.enemy_party.append(foe)
	var animator: ANIMATOR = ANIMATOR.new()
	animator.setup(es)
	scene.add_child(animator)
	scene.enemy_animators.append(animator)
	var hero := Combatant.new()
	autofree(hero)
	hero.combatant_name = "Rogue"
	hero.equipped_weapon = weapon_id
	return [scene, foe, es, animator, hero]


## weapon type -> one weapon id of it, for every type that has its own hit cue.
func _weapons() -> Dictionary:
	var out := {}
	for id in EquipmentSystem.weapons.keys():
		var t := str((EquipmentSystem.weapons[id] as Dictionary).get("weapon_type", ""))
		if t != "" and not out.has(t) and SoundManager._sfx_manifest.has("attack_hit_" + t):
			out[t] = str(id)
	return out


## The action as the battle runs it: damage is noted while the attacker is the acting combatant, the action then ENDS
## (the cache is cleared), and only later does the lunge land. Returns [cue path on the battle voice, spark shape].
func _contact(f: Array, crit: bool, ability_id: String, landing_names_attacker: bool = true, damage: int = 10) -> Array:
	var scene = f[0]; var es: AnimatedSprite2D = f[2]; var hero: Combatant = f[4]
	scene._current_ability_id = ability_id
	scene._last_acting_combatant = hero
	scene._action_serial += 1
	scene._note_hit_weight(f[1], damage, crit, "", 1.0)
	var serial: int = scene._action_serial
	if damage > 0:
		assert_gt(float(scene._peek_hit_weight(es, hero, serial)["w"]), 0.0, "PREMISE: the hit left its weight on the target (else a crit has nowhere to ride)")
	scene._last_acting_combatant = null  # what _on_action_executed does, in the action's own frame
	if landing_names_attacker:
		scene._land_hit_weight(es, hero, serial)
	else:
		es.set_meta("hit_landing", {"w": 0.1, "kill": false})  # the shipped landing: a weight and nothing else
	SoundManager._sfx_cooldowns.clear()
	SoundManager._battle_player.stop()
	SoundManager._battle_player.stream = null
	var earlier: Array = EffectSystem._effects_container.get_children()
	scene._delayed_play_hit_fx(f[3], es)
	var shape := ""
	for child in EffectSystem._effects_container.get_children():
		if not (child in earlier) and child.has_meta("shape"):
			shape = str(child.get_meta("shape"))
	var stream = SoundManager._battle_player.stream
	scene._current_ability_id = ""
	return [str(stream.resource_path) if stream != null else "", shape]


func test_a_hit_that_lands_after_its_action_ended_is_its_weapons() -> void:
	var weapons := _weapons()
	assert_gt(weapons.size(), 3, "VOID: only %d weapon types have a hit cue" % weapons.size())
	for t in weapons:
		var f := _fixture(weapons[t])
		assert_eq(EquipmentSystem.get_weapon_type(f[4]), t, "PREMISE: the hero holds a %s" % t)
		var got := _contact(f, false, "")
		assert_true(str(got[0]).contains("attack_hit_%s." % t), "a %s landed with %s" % [t, got[0]])
		assert_eq(got[1], EffectSystem.hit_spark_shape(t), "a %s drew the '%s' spark" % [t, got[1]])
	## CONTROL: a landing that does not name its attacker is the shipped state: the generic hit, the unnamed spark.
	var old := _contact(_fixture(weapons["dagger"]), false, "", false)
	assert_true(str(old[0]).contains("attack_hit.") and not str(old[0]).contains("dagger"), "CONTROL: with nobody named the hit is the generic one: %s" % old[0])
	assert_eq(old[1], EffectSystem.HIT_SPARK_DEFAULT, "CONTROL: with nobody named the spark is the default")


## An ability's hit has no second cue behind it (_on_damage_dealt skips abilities), so this is the only place it can sound.
func test_every_starter_physical_ability_lands_with_the_weapon() -> void:
	var jobs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/jobs.json"))
	jobs = jobs.get("jobs", jobs)
	var dagger: String = _weapons().get("dagger", "")
	assert_ne(dagger, "", "PREMISE: a dagger exists")
	var judged: Array[String] = []
	for job in STARTERS:
		var ids: Array = (jobs[job] as Dictionary).get("abilities", []).duplicate()
		for lv in ((jobs[job] as Dictionary).get("abilities_at_level", {}) as Dictionary).values():
			ids.append_array(lv if lv is Array else [lv])
		for id in ids:
			if str(JobSystem.get_ability(str(id)).get("type", "")) != "physical" or judged.has(str(id)):
				continue
			judged.append(str(id))
			var got := _contact(_fixture(dagger), false, str(id))
			assert_true(str(got[0]).contains("attack_hit_dagger."), "%s with a dagger landed with %s" % [id, got[0]])
	assert_true(judged.has("mug") and judged.has("backstab"), "VOID: the Rogue's Mug and Backstab were not judged: %s" % str(judged))
	assert_gt(judged.size(), 4, "VOID: only %d physical abilities found" % judged.size())


func test_a_crit_reaches_the_weapons_crit_cue() -> void:
	var dagger: String = _weapons().get("dagger", "")
	assert_true(SoundManager._sfx_manifest.has("attack_hit_dagger_crit"), "PREMISE: the dagger has a crit cue")
	var plain := _contact(_fixture(dagger), false, "mug")
	assert_true(str(plain[0]).contains("attack_hit_dagger.") , "CONTROL: an ordinary Mug is the plain dagger hit: %s" % plain[0])
	var crit := _contact(_fixture(dagger), true, "mug")
	assert_true(str(crit[0]).contains("attack_hit_dagger_crit."), "a critical Mug landed with %s" % crit[0])
	var swing := _contact(_fixture(dagger), true, "")
	assert_true(str(swing[0]).contains("attack_hit_dagger_crit."), "a critical plain attack's contact is %s" % swing[0])


## A monster's counter sets the acting combatant itself and lands with no lunge: the fallback still serves it.
func test_a_landing_that_names_nobody_falls_back_to_the_acting_combatant() -> void:
	var f := _fixture(_weapons().get("sword", ""))
	assert_eq(SCENE.hit_attacker({"w": 0.0, "kill": false}, f[4]), f[4], "no name on the landing: the acting combatant")
	assert_eq(SCENE.hit_attacker({"by": (f[1] as Combatant).get_instance_id()}, f[4]), f[1], "CONTROL: a named attacker outranks the cache")
	assert_null(SCENE.hit_attacker({"by": 1}, null), "a stale id is nobody, not a crash")


## A swing that dealt nothing (a miss, a blocked hit) notes no weight, so only the lunge itself can say who swung.
func test_a_hit_that_dealt_nothing_still_lands_as_its_weapon() -> void:
	var dagger: String = _weapons().get("dagger", "")
	var f := _fixture(dagger)
	var got := _contact(f, false, "", true, 0)
	assert_eq(float(f[0]._peek_hit_weight(f[2], f[4], f[0]._action_serial)["w"]), 0.0, "CONTROL: no weight was noted for this swing")
	assert_true(str(got[0]).contains("attack_hit_dagger."), "a dagger swing that dealt nothing landed with %s" % got[0])
	assert_eq(got[1], EffectSystem.hit_spark_shape("dagger"), "and drew the '%s' spark" % got[1])
