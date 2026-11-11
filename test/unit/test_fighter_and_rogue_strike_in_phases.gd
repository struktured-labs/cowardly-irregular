extends GutTest

## struktured via cowir-main 23756/23766: "make the battle animations FANTASTIC", every ability. The Fighter's and the
## Rogue's kits were on the plain path: one pose and one burst. Eleven now play a code-drawn sequence (sprites 23767,
## approved 23768): a physical move's `vfx.melee` draws AROUND _animate_melee_attack's lunge and hit; a cast's
## `vfx.sequence` takes the ordinary sequence path; and an outcome gets its own beat, so a landed stun, blind, taunt or
## steal never looks like a failed one. Flee is not here: the escape beat (.790) owns it.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const ABILITIES := "res://data/abilities.json"
const SEQUENCES := "res://data/vfx_sequences.json"
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")

const MELEE := {"power_strike": "melee_power_strike", "cleave": "melee_cleave", "shield_bash": "melee_shield_bash",
	"slash": "melee_slash", "backstab": "melee_backstab", "mug": "melee_mug"}
const CASTS := {"provoke": "fighter_provoke", "steal": "rogue_steal", "scan": "rogue_scan",
	"smoke_bomb": "rogue_smoke_bomb", "shadow_step": "rogue_shadow_step"}
const OUTCOMES := ["landed_stun", "landed_blind", "landed_taunt", "fizzle", "steal_take", "melee_cleave_cut", "melee_backstab_crit"]
## The lunge's contact: 0.05 pull-back + 0.12 approach in _animate_melee_attack.
const CONTACT := 0.17

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


func _sheet(pos: Vector2) -> AnimatedSprite2D:
	var tex := PlaceholderTexture2D.new()
	tex.size = Vector2(16, 16)
	var sf := SpriteFrames.new()
	for n in ["idle", "attack"]:
		if not sf.has_animation(n):
			sf.add_animation(n)
		sf.add_frame(n, tex)
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


func after_each() -> void:
	Engine.time_scale = _saved_scale
	_bm_guard.restore()


func _seqs() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SEQUENCES))["sequences"]


func _fx_count() -> int:
	return EffectSystem._effects_container.get_child_count()


func _has_phase_at(seq: Dictionary, at: float) -> bool:
	for p in seq.get("phases", []):
		if absf(float(p.get("at", 0.0)) - at) <= 0.02:
			return true
	return false


func _draws(phase: Dictionary) -> int:
	## Nodes one phase adds to a bare host, run at once.
	var host := Node2D.new()
	add_child_autofree(host)
	var fx := FractalFX.new(host, 7)
	fx.play({"phases": [phase]}, Vector2(600, 300), Vector2(200, 300))
	return fx.spawned


func test_each_ability_names_its_sequence_and_the_rest_do_not() -> void:
	var abilities: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	var seqs := _seqs()
	for id in MELEE:
		assert_eq(BattleScene.melee_overlay(abilities[id], "melee"), MELEE[id], "%s draws its melee sequence" % id)
		assert_eq(AbilityVFX.resolve(abilities[id]).get("sequence"), "", "%s keeps the melee path: no cast sequence" % id)
	for id in CASTS:
		assert_eq(AbilityVFX.resolve(abilities[id]).get("sequence"), CASTS[id], "%s plays its sequence" % id)
		assert_true(seqs.has(CASTS[id]), "%s exists" % CASTS[id])
	for id in OUTCOMES:
		assert_true(seqs.has(id), "the outcome beat %s exists" % id)
	assert_eq(BattleScene.melee_overlay(abilities["cleave"], "melee_each"), "melee_cleave_cut", "Cleave cuts each foe")
	assert_eq(BattleScene.melee_overlay(abilities["backstab"], "melee_crit"), "melee_backstab_crit", "Backstab blooms on a crit")
	## CONTROLs: the escape beat owns Flee, and a monster's physical move is still on the plain path.
	assert_eq(BattleScene.melee_overlay(abilities["flee"], "melee"), "", "Flee names no melee sequence")
	assert_eq(AbilityVFX.resolve(abilities["flee"]).get("sequence"), "", "Flee names no cast sequence")
	assert_eq(BattleScene.melee_overlay(abilities["bite"], "melee"), "", "a monster's bite names none")
	assert_eq(BattleScene.melee_overlay({"vfx": {"melee": "no_such_sequence"}}, "melee"), "", "a sequence that does not exist is not played")


func test_the_three_new_phase_kinds_draw_and_an_unknown_one_does_not() -> void:
	assert_gt(_draws({"kind": "puff", "at": 0.0, "count": 6}), 0, "a puff draws at once")
	assert_eq(_draws({"kind": "no_such_kind", "at": 0.0}), 0, "CONTROL: an unknown kind draws nothing")
	## arc and streak draw in order over their sweep, so their flames arrive on timers.
	for kind in ["arc", "streak"]:
		var host := Node2D.new()
		add_child_autofree(host)
		var fx := FractalFX.new(host, 7)
		fx.play({"phases": [{"kind": kind, "at": 0.0, "dur": 0.05, "glow": false}]}, Vector2(600, 300), Vector2(200, 300))
		await get_tree().create_timer(0.2).timeout
		assert_gt(fx.spawned, 3, "%s draws a line of flames across its sweep (%d)" % [kind, fx.spawned])


func test_a_reversed_bolt_starts_at_the_target() -> void:
	for reverse in [false, true]:
		var host := Node2D.new()
		add_child_autofree(host)
		var fx := FractalFX.new(host, 7)
		fx.play({"phases": [{"kind": "bolt", "at": 0.0, "dur": 0.4, "reverse": reverse}]}, Vector2(600, 300), Vector2(200, 300))
		var head: Node2D = host.get_child(0)
		assert_almost_eq(head.position.x, 200.0 if reverse else 600.0, 1.0,
			"the bolt's head starts at the %s" % ("target (the take comes BACK)" if reverse else "caster (CONTROL)"))


func test_a_melee_sequence_is_timed_from_contact_and_shows_its_impact_at_turbo() -> void:
	var seqs := _seqs()
	for id in MELEE:
		var seq: Dictionary = seqs[MELEE[id]]
		assert_almost_eq(float(seq.get("start", -1.0)), CONTACT, 0.001, "%s starts at the lunge's contact" % MELEE[id])
		assert_almost_eq(FractalFX.impact_time(seq), CONTACT, 0.001, "%s lands at contact" % MELEE[id])
		assert_true(_has_phase_at(seq, 0.0), "%s has a phase AT its impact, so turbo shows the hit" % MELEE[id])
		for p in seq["phases"]:
			assert_gte(float(p.get("at", 0.0)), -CONTACT, "%s: a %s phase cannot start before the lunge does" % [MELEE[id], p.get("kind")])
	for id in CASTS:
		var seq: Dictionary = seqs[CASTS[id]]
		assert_true(seq.has("impact"), "%s names its impact" % CASTS[id])
		assert_true(_has_phase_at(seq, float(seq["impact"])), "%s has a phase AT its impact" % CASTS[id])
		assert_lte(FractalFX.impact_time(seq), 0.62, "%s lands inside today's ability hold" % CASTS[id])


func test_the_big_moves_fill_the_enemy_side() -> void:
	var seqs := _seqs()
	var widest := func(id: String, kind: String, field: String) -> float:
		var best := 0.0
		for p in seqs[id]["phases"]:
			if str(p.get("kind", "")) == kind:
				best = maxf(best, float(p.get(field, 0.0)))
		return best
	## A ring's texture is 32 px, so scale 11 is a 350 px crack; the enemy side of a 1280 px screen is about 600 px.
	assert_gte(widest.call("melee_power_strike", "ring", "scale"), 16.0, "Power Strike's ground crack spans the enemy side")
	assert_gt(widest.call("melee_power_strike", "ring", "scale"), widest.call("melee_shield_bash", "ring", "scale"),
		"and is bigger than a Shield Bash's ring")
	assert_gte(widest.call("melee_cleave", "arc", "radius"), 280.0, "Cleave's crescent sweeps the whole line")
	assert_gt(widest.call("melee_cleave", "arc", "radius"), 3.0 * widest.call("melee_backstab_crit", "arc", "radius"),
		"CONTROL: a single-target arc is a third of it")


func test_a_landed_effect_and_a_failed_one_never_share_a_beat() -> void:
	assert_eq(BattleScene.landed_beat("stun"), "landed_stun")
	assert_eq(BattleScene.landed_beat("blind"), "landed_blind")
	assert_eq(BattleScene.landed_beat("taunted_Fighter"), "landed_taunt", "Provoke's status carries the taunter's name")
	assert_eq(BattleScene.landed_beat("poison"), "", "CONTROL: a status without a beat lands with its aura alone")
	for s in ["stun", "blind", "taunted_x"]:
		assert_ne(BattleScene.landed_beat(s), BattleScene.FIZZLE_BEAT, "%s landing is not the fizzle" % s)
	var seqs := _seqs()
	var kinds := func(id: String) -> Array:
		return (seqs[id]["phases"] as Array).map(func(p): return str(p["kind"]))
	assert_true(kinds.call("steal_take").has("bolt"), "a steal that lands sends the take back")
	assert_false(kinds.call("fizzle").has("bolt"), "a fizzle sends nothing back")
	assert_true(kinds.call("fizzle").has("puff"), "a fizzle is dust")


func test_the_scene_draws_the_move_and_the_outcome() -> void:
	var before := _fx_count()
	_scene._on_action_executing(_hero, {"type": "ability", "ability_id": "power_strike", "targets": [_foe]})
	await get_tree().create_timer(0.35).timeout
	assert_gt(_fx_count(), before, "Power Strike draws into the effects layer")
	before = _fx_count()
	_scene._on_steal_resolved(_hero, _foe, true)
	assert_gt(_fx_count(), before, "a landed steal draws its take")
	before = _fx_count()
	_scene._on_status_landed("stun", _foe)
	await get_tree().process_frame
	assert_gt(_fx_count(), before, "a landed stun draws its stars")
	before = _fx_count()
	_scene._on_status_landed("poison", _foe)
	assert_eq(_fx_count(), before, "CONTROL: a status with no beat draws nothing")


func test_an_outcome_of_a_melee_move_waits_for_the_blow_to_arrive() -> void:
	## A melee move's status resolves at the action's start; its beat must not pop before the lunge lands.
	_scene._on_action_executing(_hero, {"type": "ability", "ability_id": "shield_bash", "targets": [_foe]})
	assert_not_null(_scene._melee_contact_timer, "a melee ability arms the contact clock")
	var host := Node2D.new()
	add_child_autofree(host)
	var was: Node2D = EffectSystem._effects_container
	EffectSystem._effects_container = host
	_scene._on_status_landed("stun", _foe)
	var at_once := host.get_child_count()
	await get_tree().create_timer(BattleScene.MELEE_CONTACT_S + 0.1).timeout
	var after := host.get_child_count()
	EffectSystem._effects_container = was
	assert_eq(at_once, 0, "the stars do not appear while the shield is still on its way")
	assert_gt(after, 0, "CONTROL: they do appear once it has landed")


func test_a_drawn_in_order_phase_is_as_long_as_its_last_flame() -> void:
	assert_almost_eq(FractalFX.phase_duration({"kind": "arc", "dur": 0.2, "life": 0.4}), 0.6, 0.001, "an arc outlasts its sweep by its life")
	assert_almost_eq(FractalFX.phase_duration({"kind": "streak", "dur": 0.1, "life": 0.3}), 0.4, 0.001, "so does a streak")
	assert_almost_eq(FractalFX.phase_duration({"kind": "puff", "dur": 0.7}), 0.7, 0.001, "a puff is its dur")
	assert_almost_eq(FractalFX.phase_duration({"kind": "ring", "dur": 0.3}), 0.3, 0.001, "CONTROL: a ring is its dur")


func test_turbo_draws_no_outcome_beat() -> void:
	_scene.turbo_mode = true
	var before := _fx_count()
	_scene._on_steal_resolved(_hero, _foe, true)
	_scene._on_status_landed("stun", _foe)
	assert_eq(_fx_count(), before, "an outcome beat is never the impact, so turbo skips it")
	_scene.turbo_mode = false
	_scene._on_steal_resolved(_hero, _foe, false)
	assert_gt(_fx_count(), before, "CONTROL: at spotlight pace the fizzle draws")
