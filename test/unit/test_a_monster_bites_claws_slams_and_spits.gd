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
## The shared effects layer's children when an arm starts: after_each frees whatever the arm left there.
var _fx_before: Array = []


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
	_fx_before = EffectSystem._effects_container.get_children() if is_instance_valid(EffectSystem._effects_container) else []
	BattleManager.impact_hold = 0.0


func after_each() -> void:
	## Leave the shared effects layer as this arm found it. A sequence's flames free themselves on battle-time timers,
	## and ones still dying when the NEXT file takes a child-count baseline red its "the layer grew" arm by order
	## (autogrind 24109: test_fire_is_fractal, which sorts right after this file).
	if is_instance_valid(EffectSystem._effects_container):
		for child in EffectSystem._effects_container.get_children():
			if not (child in _fx_before):
				child.free()
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


func test_a_plain_attack_takes_the_family_the_creature_fights_in() -> void:
	## adhoc 24048: a monster row's `hit_spark` names the family its PLAIN attack plays at contact (a wolf bites, a
	## slime slams). Each row's value is the family most of its own physical moves belong to.
	var monsters := _json("res://data/monsters.json")
	var seqs: Dictionary = _json("res://data/vfx_sequences.json")["sequences"]
	var named := 0
	for id in monsters:
		var row = monsters[id]
		if not (row is Dictionary) or not row.has("hit_spark"):
			continue
		named += 1
		assert_true(str(row["hit_spark"]) in ["bite", "claw", "slam"], "%s: '%s' is not a contact family" % [id, row["hit_spark"]])
		assert_true(seqs.has("family_" + str(row["hit_spark"])), "%s names family_%s, which does not exist" % [id, row["hit_spark"]])
		assert_eq(BattleSceneScript.hit_mark("", str(row["hit_spark"])), "family", "%s's plain attack plays its family" % id)
	assert_gt(named, 30, "CONTROL: the W1 monsters' rows were found (%d)" % named)
	assert_eq(str(monsters["wolf"].get("hit_spark", "")), "bite", "a wolf bites")
	assert_eq(str(monsters["slime"].get("hit_spark", "")), "slam", "a slime slams")
	assert_false(monsters["goblin"].has("hit_spark"), "CONTROL: a goblin swings a sword, so it keeps the weapon spark")
	assert_eq(BattleSceneScript.hit_mark("", ""), "spark", "CONTROL: a row naming nothing rakes")


func test_a_line_wide_move_spans_the_targets_it_hits() -> void:
	## struktured via main 24179/24186 ("aims center"): Cleave's crescent played at the MEAN of its targets, the same
	## size whatever they were, so with two foes far apart it sat between them on nobody.
	var near: Rect2 = BattleSceneScript.line_span([Vector2(300, 200), Vector2(310, 280)])
	var far: Rect2 = BattleSceneScript.line_span([Vector2(300, 80), Vector2(320, 560)])
	assert_almost_eq(near.size.y, 80.0, 0.01, "the span is the targets' extent")
	assert_almost_eq(far.get_center().y, 320.0, 0.01, "and its centre is the middle of that extent")
	assert_eq(BattleSceneScript.line_span([Vector2(5, 7)]).size, Vector2.ZERO, "one target is a point")
	var seqs: Dictionary = _json("res://data/vfx_sequences.json")["sequences"]
	for id in ["melee_cleave", "family_slam_quake", "family_spray"]:
		assert_gt(float(seqs[id].get("span", 0.0)), 0.0, "%s names the span it was authored for" % id)
		assert_true(bool(seqs[id].get("scale_offsets", false)), "%s moves its offsets with its size" % id)
	assert_false(seqs["family_bite"].has("span"), "CONTROL: a single-target family names no span")
	## The scale a span gets, floor to cap, and what it does to a phase: a puff 100 px off its target at power 0.5.
	var k_of := func(extent: float, authored: float) -> float:
		return clampf((extent + BattleSceneScript.LINE_SPAN_PAD) / authored, BattleSceneScript.LINE_SPAN_MIN, BattleSceneScript.LINE_SPAN_MAX)
	assert_lt(k_of.call(near.size.y, 530.0), k_of.call(far.size.y, 530.0), "two foes far apart get a bigger crescent than two side by side")
	assert_almost_eq(k_of.call(0.0, 530.0), BattleSceneScript.LINE_SPAN_MIN, 0.001, "one foe gets the floor")
	var host := Node2D.new()
	add_child_autofree(host)
	var puff := {"kind": "puff", "at": 0.0, "count": 1, "spread": [0, 0], "offset": [100, 0]}
	var fx := FractalFX.new(host, 7)
	fx.play({"scale_offsets": true, "phases": [puff]}, Vector2(900, 300), Vector2(500, 300), 0.5)
	assert_almost_eq((host.get_child(0) as Node2D).position.x, 550.0, 1.0, "a scaled sequence's offset shrinks with it")
	var fx2 := FractalFX.new(host, 7)
	fx2.play({"phases": [puff]}, Vector2(900, 300), Vector2(500, 300), 0.5)
	assert_almost_eq((host.get_child(1) as Node2D).position.x, 600.0, 1.0, "CONTROL: an ordinary sequence's offset does not")


func test_a_move_is_aimed_at_the_body_not_at_the_frame() -> void:
	## cutscenes 24028: a battler's anchor is its FRAME centre, and the Fighter's figure stands ~95 px off it. A figure
	## drawn in the left third of a 96 px frame, at 2x: the body is 2 x (16 - 48) = 64 px left of the anchor.
	var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 16, 32, 64), Color.WHITE)
	var sf := SpriteFrames.new()
	sf.add_animation("idle")
	sf.add_frame("idle", ImageTexture.create_from_image(img))
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = sf
	spr.position = Vector2(700, 300)
	spr.scale = Vector2(2, 2)
	_scene.add_child(spr)
	var anchor: Vector2 = _scene._stable_sprite_anchor(spr)
	var body: Vector2 = _scene._figure_anchor(spr)
	assert_almost_eq(body.x - anchor.x, -64.0, 2.0, "the aim follows the figure, not the frame (%.1f px)" % (body.x - anchor.x))
	spr.flip_h = true
	assert_almost_eq(_scene._figure_anchor(spr).x - anchor.x, 64.0, 2.0, "and its mirror when the sprite is flipped")
	## CONTROL: a figure that fills its frame is aimed at its anchor.
	var full: AnimatedSprite2D = _scene.enemy_sprite_nodes[0]
	assert_almost_eq(_scene._figure_anchor(full).x, _scene._stable_sprite_anchor(full).x, 1.0, "a centred figure is aimed at its anchor")


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


## struktured's clips, 2026-11-12: the skeleton's bone had landed before its throwing pose reached the throw. A ranged
## move's sequence now starts later by the pose's own impact frame, and the hit is held for the same time.
func test_a_thrown_thing_leaves_on_the_poses_release_frame() -> void:
	assert_eq(BattleSceneScript.sequence_start_after("family_spit", 0.0), -1.0, "CONTROL: a pose with no wind-up plays the sequence as authored")
	var authored: float = float(FractalFX.load_sequence("family_spit").get("start", 0.0))
	assert_almost_eq(BattleSceneScript.sequence_start_after("family_spit", 0.375), authored + 0.375, 0.001, "a 0.375 s wind-up starts the sequence that much later")
	var foe_sprite: AnimatedSprite2D = _scene.enemy_sprite_nodes[0]
	var fa: BattleAnimator = _scene.enemy_animators[0]
	_scene._on_action_executing(_foe, {"type": "ability", "ability_id": "bone_throw", "targets": [_hero]})
	var plain_hold: float = BattleManager.impact_hold
	assert_gt(plain_hold, 0.1, "CONTROL: with a one-frame pose the hit waits only for the bone's flight (%.2f s)" % plain_hold)
	BattleManager.impact_hold = 0.0
	await get_tree().create_timer(0.8).timeout
	## Now a throwing pose of four frames whose throw is its fourth.
	var sf: SpriteFrames = foe_sprite.sprite_frames
	for i in 3:
		sf.add_frame("attack", _solid(64))
	sf.set_animation_speed("attack", 8.0)
	sf.set_meta("impact_frames", {"attack": 3})
	assert_eq(fa.shown_animation_for("special"), "attack", "a monster's 'special' move is drawn with its attack frames (no special, no cast on the sheet)")
	var wind_up: float = fa.impact_time("attack")
	assert_gt(wind_up, 0.05, "CONTROL: the pose now has a wind-up before its impact frame (%.3f s)" % wind_up)
	_scene._on_action_executing(_foe, {"type": "ability", "ability_id": "bone_throw", "targets": [_hero]})
	assert_almost_eq(BattleManager.impact_hold, plain_hold + wind_up, 0.02,
		"the bone lands a wind-up later than it did (%.2f s after %.2f + %.3f)" % [BattleManager.impact_hold, plain_hold, wind_up])


## The gap I stated with the .793 tip: each hero's splat of a line-wide spray was steel grey whatever was sprayed.
func test_a_sprays_splat_on_each_hero_takes_the_moves_colour() -> void:
	var painted := 0
	for phase in FractalFX.load_sequence("family_spray_hit").get("phases", []):
		if phase is Dictionary and phase.has("palette"):
			painted += 1
			assert_eq(str(phase["palette"]), "spark", "the per-hero splat's %s is drawn in a fixed colour, so no tint can reach it" % str(phase.get("kind", "")))
	assert_gt(painted, 1, "CONTROL: the splat has painted phases to tint")
	var abilities: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	if abilities.has("abilities"):
		abilities = abilities["abilities"]
	var sprays := 0
	var plain: Array = []
	for id in abilities:
		var a: Dictionary = abilities[id]
		var vfx = a.get("vfx", {})
		if vfx is Dictionary and bool(vfx.get("ranged", false)) and str(a.get("target_type", "")) == "all_enemies":
			sprays += 1
			if BattleSceneScript.family_tint(a) == "":
				plain.append(id)
	assert_gt(sprays, 2, "CONTROL: line-wide ranged moves exist (%d)" % sprays)
	assert_eq(plain, [], "a line-wide ranged move names no colour (vfx.palette, an element or an effect with a tint), so its splats are the bare spark")
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_true(src.contains('family_tint(ability) if seq_override != "" else "")'), "the cast path hands a family delivery its move's tint")

