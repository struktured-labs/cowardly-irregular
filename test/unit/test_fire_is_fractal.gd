extends GutTest

## #399, struktured via cowir-main 2026-10-31: "wire it into Fire first, playable" (Fire's own look since 2026-11-11,
## test_fire_erupts_in_phases; the fractal is Edit Formula's). An ability whose vfx
## names a data/vfx_sequences.json sequence plays it (bolt from the caster, burst on the target), the
## damage numbers wait for the burst, and the battle holds until just past it. Blizzard (no sequence)
## is the control: the ordinary path, unchanged.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const ABILITIES := "res://data/abilities.json"
const SEQUENCES := "res://data/vfx_sequences.json"
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")

var _scene
var _bm_guard
var _saved_scale := 1.0
var _hero: Combatant
var _foe: Combatant
var _drawn := 0


func _note_drawn(_n: Node) -> void:
	_drawn += 1


func _c(n: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": n, "max_hp": 400, "max_mp": 80, "attack": 20, "defense": 10, "magic": 20, "speed": 10})
	add_child_autofree(c)
	return c


func _sheet(pos: Vector2) -> AnimatedSprite2D:
	var tex := PlaceholderTexture2D.new()
	tex.size = Vector2(16, 16)
	var sf := SpriteFrames.new()
	for n in ["idle", "cast"]:
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
	## After the scene: its _ready re-applies the battle speed. At 1.0 (above 0.55) the control spell takes the
	## ordinary path instead of the spotlight, which arms the same damage buffer and would hide the difference.
	Engine.time_scale = 1.0
	_hero = _c("Mage")
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


func after_each() -> void:
	var layer: Node = EffectSystem._effects_container
	if layer != null and is_instance_valid(layer) and layer.child_entered_tree.is_connected(_note_drawn):
		layer.child_entered_tree.disconnect(_note_drawn)
	Engine.time_scale = _saved_scale
	_bm_guard.restore()


func _until(cond: Callable, bound_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(bound_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await get_tree().process_frame
	return bool(cond.call())


func _cast(id: String) -> void:
	_scene._on_action_executing(_hero, {"type": "ability", "ability_id": id, "targets": [_foe]})


func test_fire_names_its_sequence_and_every_named_sequence_exists() -> void:
	assert_eq(AbilityVFX.resolve(JobSystem.get_ability("fire")).get("sequence"), "fire_battle", "Fire plays its sequence")
	var abilities: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ABILITIES))
	var seqs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SEQUENCES))["sequences"]
	var named := 0
	for id in abilities:
		var vfx = abilities[id].get("vfx", {}) if abilities[id] is Dictionary else {}
		if vfx is Dictionary and vfx.has("sequence"):
			named += 1
			assert_true(seqs.has(str(vfx["sequence"])), "%s names sequence '%s', which vfx_sequences.json lacks" % [id, vfx["sequence"]])
	assert_gte(named, 1, "CONTROL: the derivation must find Fire's sequence")


func test_the_impact_is_the_end_of_the_bolt() -> void:
	var seq := FractalFX.load_sequence("fire_battle")
	var bolt_end := 0.0
	for p in seq.get("phases", []):
		if str(p.get("kind", "")) == "bolt" and int(p.get("min_tier", 1)) <= 1:
			bolt_end = float(p.get("at", 0.0)) + float(p.get("dur", 0.0))
	assert_gt(bolt_end, 0.0, "CONTROL: Fire has a bolt")
	assert_almost_eq(FractalFX.impact_time(seq), float(seq.get("start", 0.0)) + bolt_end, 0.001, "lands when the bolt arrives, after the cast's release frame")


func test_a_fire_cast_plays_the_sequence_and_holds_the_damage_for_the_burst() -> void:
	var host: Node = EffectSystem._effects_container
	## Counted by ARRIVAL, not by the layer's size: an earlier file's sparks dying in this window cancelled the cast's own nodes (.793 sweep).
	_drawn = 0
	host.child_entered_tree.connect(_note_drawn)
	BattleManager.presentation_hold = 0.0
	_cast("fire")
	## #763: the wait moved from the damage NUMBERS to the whole resolution — BattleManager holds the
	## HP drop / death until the impact, so the scene hands it the impact time instead of buffering.
	var lands: float = FractalFX.impact_time(FractalFX.load_sequence("fire_battle"))
	assert_almost_eq(BattleManager.impact_hold, lands, 0.05, "the HP drop and death must wait for the burst, not land on the cast")
	assert_eq(_scene._full_render_dmg_buffer, null, "damage arrives at the impact itself, nothing to buffer")
	BattleManager.impact_hold = 0.0
	assert_gte(BattleManager.presentation_hold, lands, "the battle must hold until the fire lands (hold %.2f)" % BattleManager.presentation_hold)
	assert_true(await _until(func() -> bool: return _drawn > 0, 2.0), "the sequence must draw into the effects layer")
	assert_true(await _until(func() -> bool: return _scene._full_render_dmg_buffer == null, 3.0),
		"the held damage must be released at the burst")


func test_a_spell_without_a_sequence_takes_the_ordinary_path() -> void:
	assert_eq(AbilityVFX.resolve(JobSystem.get_ability("blizzard")).get("sequence"), "", "CONTROL: Blizzard names no sequence")
	_cast("blizzard")
	assert_eq(_scene._full_render_dmg_buffer, null, "an ordinary spell must not hold its damage")
