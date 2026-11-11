extends GutTest

## struktured via cowir-main 23993/23999: since .791, 68 monsters attack with their idle picture, so what a monster's
## physical move LOOKS like is whatever is drawn around its lunge. The 48 monsters a player meets by level 12 use 39
## physical abilities; 4 are the Fighter's (sequenced in .792) and the other 35 now name one of four FAMILIES (bite,
## claw, slam, spit, with a heavy or line-wide form): one sequence each, sized to the creature and tinted by the move.
## A sequence authored for an attacker on the right is `handed`, and is reflected for a monster, which stands on the left.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BattleSceneScript := preload("res://src/battle/BattleScene.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const FAMILIES := ["bite", "bite_big", "claw", "slam", "slam_quake", "spit", "spray"]
const W1_MAX_LEVEL := 12
const WORLD_SUFFIXES := ["_suburban", "_steampunk", "_industrial", "_digital", "_abstract", "_futuristic"]
## A W1 physical ability that deliberately resolves no sequence, with its reason. Empty: every one resolves.
const DECLARED_PLAIN := {}

var _scene
var _bm_guard
var _saved_scale := 1.0
var _hero: Combatant
var _foe: Combatant


func _c(n: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": n, "max_hp": 400, "max_mp": 80, "attack": 20, "defense": 10, "magic": 20, "speed": 10})
	add_child_autofree(c)
	return c


func _solid(px: int) -> Texture2D:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _sheet(pos: Vector2, px: int = 64) -> AnimatedSprite2D:
	var sf := SpriteFrames.new()
	for n in ["idle", "attack"]:
		if not sf.has_animation(n):
			sf.add_animation(n)
		sf.add_frame(n, _solid(px))
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = sf
	spr.animation = "idle"
	spr.position = pos
	_scene.add_child(spr)
	return spr


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_bm_guard = BattleStateGuard.new()
	_bm_guard.snapshot()
	_saved_scale = Engine.time_scale
	_scene = SCENE.instantiate()
	add_child_autofree(_scene)
	Engine.time_scale = 1.0
	_hero = _c("Fighter")
	_foe = _c("Goblin")
	_scene.party_members.assign([_hero] as Array[Combatant])
	_scene.test_enemies.assign([_foe] as Array[Combatant])
	BattleManager.player_party.assign([_hero] as Array[Combatant])
	BattleManager.enemy_party.assign([_foe] as Array[Combatant])
	var hs := _sheet(Vector2(900, 300))
	var fs := _sheet(Vector2(300, 300))
	var ha := BattleAnimator.new()
	_scene.add_child(ha)
	ha.setup(hs)
	var fa := BattleAnimator.new()
	_scene.add_child(fa)
	fa.setup(fs)
	_scene.party_sprite_nodes.assign([hs])
	_scene.enemy_sprite_nodes.assign([fs])
	_scene.party_animators.assign([ha])
	_scene.enemy_animators.assign([fa])
	_scene.turbo_mode = false
	_scene.autogrind_console_mode = false
	BattleManager.impact_hold = 0.0


func after_each() -> void:
	Engine.time_scale = _saved_scale
	BattleManager.impact_hold = 0.0
	_bm_guard.restore()


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _w1_physical() -> Dictionary:
	## ability id -> the W1 monsters that use it, derived from monsters.json and abilities.json.
	var abilities := _json("res://data/abilities.json")
	var monsters := _json("res://data/monsters.json")
	var out := {}
	for id in monsters:
		var row = monsters[id]
		if not (row is Dictionary) or int(row.get("level", 99)) > W1_MAX_LEVEL:
			continue
		var variant := false
		for suffix in WORLD_SUFFIXES:
			variant = variant or str(id).ends_with(suffix)
		if variant:
			continue
		for a in row.get("abilities", []):
			if abilities.has(a) and str(abilities[a].get("type", "")) == "physical":
				if not out.has(a):
					out[a] = []
				out[a].append(id)
	return out


func test_every_w1_physical_ability_draws_a_move() -> void:
	var abilities := _json("res://data/abilities.json")
	var used := _w1_physical()
	assert_gt(used.size(), 30, "CONTROL: the W1 monsters' physical abilities were derived (%d)" % used.size())
	var plain: Array = []
	for id in used:
		if BattleSceneScript.melee_overlay(abilities[id], "melee") == "" and not DECLARED_PLAIN.has(id):
			plain.append("%s (%s)" % [id, ", ".join(used[id].slice(0, 3))])
	assert_eq(plain, [], "W1 physical abilities still on the plain path: %s" % str(plain))
	for id in DECLARED_PLAIN:
		assert_true(used.has(id) and BattleSceneScript.melee_overlay(abilities[id], "melee") == "", "%s is declared plain but is not: remove the entry" % id)
	## CONTROLs: a family is a physical monster move's fallback, and an authored sequence still wins.
	assert_eq(BattleSceneScript.melee_overlay(abilities["bite"], "melee"), "family_bite")
	assert_eq(BattleSceneScript.melee_overlay(abilities["power_strike"], "melee"), "melee_power_strike", "the Fighter's own sequence wins")
	assert_eq(BattleSceneScript.melee_overlay(abilities["fire"], "melee"), "", "a spell names no family")
	assert_eq(BattleSceneScript.melee_overlay({"vfx": {"family": "no_such_family"}}, "melee"), "", "a family with no sequence draws nothing")
	## The row's OWN `family` is the spell line a shop sells by (battle 24017): it never names a sequence.
	assert_eq(BattleSceneScript.melee_overlay({"family": "bite"}, "melee"), "", "a top-level family is not a move")
	assert_eq(str(abilities["fire"].get("family", "")), "fire", "CONTROL: Fire's row still carries its spell line")
	assert_eq(BattleSceneScript.melee_overlay(abilities["filth_spray"], "melee_each"), "family_spray_hit", "a line-wide spray splats each target")


func test_every_family_sequence_is_handed_and_lands_at_contact() -> void:
	var seqs: Dictionary = _json("res://data/vfx_sequences.json")["sequences"]
	for f in FAMILIES:
		var id: String = "family_" + str(f)
		assert_true(seqs.has(id), "%s exists" % id)
		if not seqs.has(id):
			continue
		var seq: Dictionary = seqs[id]
		assert_true(bool(seq.get("handed", false)), "%s is handed, so a monster's is reflected" % id)
		var at_impact := false
		for p in seq["phases"]:
			at_impact = at_impact or absf(float(p.get("at", 0.0)) - float(seq.get("impact", 0.0))) <= 0.02
			assert_false(p.has("sfx"), "%s names no cue: cowir-sfx keys the family cues in its own tip" % id)
		assert_true(at_impact, "%s has a phase AT its impact, so turbo shows the hit" % id)


func _first_x(seq: Dictionary, from: Vector2, to: Vector2) -> float:
	var host := Node2D.new()
	add_child_autofree(host)
	var fx := FractalFX.new(host, 7)
	fx.play(seq, from, to)
	return (host.get_child(0) as Node2D).position.x if host.get_child_count() > 0 else NAN


func test_a_handed_sequence_is_reflected_for_an_attacker_on_the_left() -> void:
	var puff := {"kind": "puff", "at": 0.0, "count": 1, "spread": [0, 0], "offset": [60, 0]}
	var target := Vector2(500, 300)
	var right := Vector2(900, 300)
	var left := Vector2(100, 300)
	assert_almost_eq(_first_x({"handed": true, "phases": [puff]}, right, target), 560.0, 1.0, "CONTROL: an attacker on the right draws it as authored")
	assert_almost_eq(_first_x({"handed": true, "phases": [puff]}, left, target), 440.0, 1.0, "an attacker on the left gets it reflected")
	assert_almost_eq(_first_x({"phases": [puff]}, left, target), 560.0, 1.0, "CONTROL: a sequence that is not handed is never reflected")
	## An angle reflects about the vertical: 0 degrees (toward +x) becomes 180.
	var host := Node2D.new()
	add_child_autofree(host)
	var fx := FractalFX.new(host, 7)
	fx.mirror = true
	assert_almost_eq(fx._angle(0.0), PI, 0.001)
	assert_almost_eq(fx._angle(-90.0), PI + PI * 0.5, 0.001, "straight up stays straight up")
	fx.mirror = false
	assert_almost_eq(fx._angle(0.0), 0.0, 0.001)


func test_a_family_is_tinted_by_the_move_and_sized_to_the_creature() -> void:
	var abilities := _json("res://data/abilities.json")
	assert_eq(BattleSceneScript.family_tint(abilities["bite"]), "", "a plain bite keeps the family's own colour")
	assert_eq(BattleSceneScript.family_tint(abilities["dark_slash"]), "void", "an element tints it")
	assert_eq(BattleSceneScript.family_tint(abilities["venomous_bite"]), "rot", "a poison rider tints it")
	assert_eq(BattleSceneScript.family_tint(abilities["glitch_strike"]), "glitch", "an authored palette wins over the element")
	## The tint replaces `spark` only, and only with a palette that exists.
	var host := Node2D.new()
	add_child_autofree(host)
	var fx := FractalFX.new(host, 7)
	var plain: Color = fx._ramp("spark").sample(0.3)
	fx.tint = "void"
	fx._ramps.clear()
	assert_ne(fx._ramp("spark").sample(0.3), plain, "spark is drawn in the tint")
	fx.tint = "no_such_palette"
	fx._ramps.clear()
	assert_eq(fx._ramp("spark").sample(0.3), plain, "CONTROL: an unknown tint changes nothing")
	## A 64 px figure: at scale 150/64 it is the reference creature; tiny and huge ones hit the floor and the cap.
	var spr: AnimatedSprite2D = _scene.enemy_sprite_nodes[0]
	spr.scale = Vector2.ONE * (BattleSceneScript.FAMILY_REFERENCE_PX / 64.0)
	assert_almost_eq(_scene._attacker_scale(spr), 1.0, 0.02, "a reference-sized attacker draws it as authored")
	spr.scale = Vector2.ONE * 0.2
	assert_almost_eq(_scene._attacker_scale(spr), BattleSceneScript.FAMILY_SCALE_MIN, 0.001, "a rat's is floored")
	spr.scale = Vector2.ONE * 20.0
	assert_almost_eq(_scene._attacker_scale(spr), BattleSceneScript.FAMILY_SCALE_MAX, 0.001, "a dragon's is capped")


func test_a_thrown_move_does_not_walk_up_to_its_target() -> void:
	var foe_sprite: AnimatedSprite2D = _scene.enemy_sprite_nodes[0]
	## A melee move just before it, so a stale contact clock exists to be cleared.
	_scene._on_action_executing(_hero, {"type": "ability", "ability_id": "power_strike", "targets": [_foe]})
	assert_not_null(_scene._melee_contact_timer, "CONTROL: the melee move armed its contact clock")
	_scene._on_action_executing(_foe, {"type": "ability", "ability_id": "bone_throw", "targets": [_hero]})
	assert_false(foe_sprite.has_meta("attack_tween"), "a bone throw starts no lunge")
	assert_null(_scene._melee_contact_timer, "and leaves no contact clock for its outcome beat to wait on")
	assert_gt(BattleManager.impact_hold, 0.1, "its hit waits for the bone to land (%.2f s)" % BattleManager.impact_hold)
	BattleManager.impact_hold = 0.0
	await get_tree().create_timer(0.8).timeout
	## CONTROL: a tackle is a melee move and does lunge, and nothing holds its hit here.
	_scene._on_action_executing(_foe, {"type": "ability", "ability_id": "tackle", "targets": [_hero]})
	assert_true(foe_sprite.has_meta("attack_tween"), "CONTROL: a tackle lunges")
