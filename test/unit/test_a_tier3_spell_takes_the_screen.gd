extends GutTest

## struktured batch 2 (via cowir-main): the tier-3 player spells are "glory" moments. Firaga, Blizzaga and Thundaga
## carry vfx.glory in abilities.json; a PARTY member casting one plays glory_<id> through the same staging as a boss
## signature: a title card, the stage dimmed and tinted, the first cast of each spell per battle at 1x, and more of
## the sequence the stronger the caster (min_tier). Presentation only: no numbers move.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const BS_SPEEDS_1X := 0.25
const GLORY := ["firaga", "blizzaga", "thundaga"]

var _guard
var _saved_flash := false


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_saved_flash = bool(GameState.reduce_flashes)


func after_each() -> void:
	GameState.reduce_flashes = _saved_flash
	_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _scene_with_party() -> Node:
	var scene = SCENE.instantiate()
	scene.encounter_enemies = ["goblin"]
	add_child_autofree(scene)
	for i in 3:
		await get_tree().process_frame
	return scene


func test_every_tier3_spell_names_a_glory_sequence_with_its_own_tint() -> void:
	for id in GLORY:
		var ability: Dictionary = JobSystem.get_ability(id)
		assert_false(ability.is_empty(), "CONTROL: %s exists" % id)
		var vfx = ability.get("vfx", {})
		var seq_id := str(vfx.get("glory", "")) if vfx is Dictionary else ""
		assert_eq(seq_id, "glory_" + id, "%s names its glory sequence" % id)
		var seq: Dictionary = FractalFX.load_sequence(seq_id)
		assert_false(seq.is_empty(), "%s resolves in vfx_sequences.json" % seq_id)
		assert_true(seq.get("tint") is Array, "%s tints the stage its own colour" % seq_id)
		var tiered := 0
		for p in seq.get("phases", []):
			if p is Dictionary and int(p.get("min_tier", 1)) > 1:
				tiered += 1
		assert_gt(tiered, 0, "%s grows with its caster (phases gated on min_tier)" % seq_id)


func test_only_a_party_member_casting_a_tier3_spell_gets_the_glory() -> void:
	var scene = await _scene_with_party()
	assert_gt(BattleManager.player_party.size(), 0, "CONTROL: a party to cast")
	assert_gt(BattleManager.enemy_party.size(), 0, "CONTROL: a foe to cast")
	if BattleManager.player_party.is_empty() or BattleManager.enemy_party.is_empty():
		return
	var mage: Combatant = BattleManager.player_party[0]
	var foe: Combatant = BattleManager.enemy_party[0]
	for id in GLORY:
		assert_eq(scene.glory_sequence(mage, JobSystem.get_ability(id)), "glory_" + id, "a party %s is a glory moment" % id)
		assert_eq(scene.glory_sequence(foe, JobSystem.get_ability(id)), "", "a foe's %s stays plain" % id)
	assert_eq(scene.glory_sequence(mage, JobSystem.get_ability("fire")), "", "tier 1 Fire keeps its own sequence")


## The DISPATCH: a party Firaga through _on_action_executing raises its card and tints the stage in glory_firaga's colour.
func test_a_party_firaga_takes_the_stage() -> void:
	var scene = await _scene_with_party()
	var saved := Engine.time_scale
	if BattleManager.player_party.is_empty() or BattleManager.enemy_party.is_empty():
		assert_true(false, "CONTROL: a party and a foe")
		return
	var mage: Combatant = BattleManager.player_party[0]
	scene._on_action_executing(mage, {"type": "ability", "ability_id": "firaga", "targets": BattleManager.enemy_party.duplicate()})
	await get_tree().create_timer(0.3).timeout
	var card := scene.get_node_or_null("UI/SignatureCard")
	assert_not_null(card, "Firaga raises a title card")
	if card:
		var want := str(JobSystem.get_ability("firaga").get("name", ""))
		assert_eq(str((card.get_child(0).get_child(0) as Label).text), want, "naming the spell")
	var tint := scene.get_node_or_null("SignatureTint") as ColorRect
	assert_not_null(tint, "the backdrop takes the spell's colour")
	if tint:
		var c: Color = scene.signature_tint("glory_firaga")
		assert_almost_eq(tint.color.r, c.r, 0.01, "in glory_firaga's own tint")
		assert_gt(tint.color.a, 0.0, "and it is showing")
	Engine.time_scale = saved


## CONTROL for the dispatch arm: plain Fire never stages the screen, so the tint above is Firaga's doing.
func test_a_party_fire_does_not_take_the_stage() -> void:
	var scene = await _scene_with_party()
	var saved := Engine.time_scale
	if BattleManager.player_party.is_empty() or BattleManager.enemy_party.is_empty():
		assert_true(false, "CONTROL: a party and a foe")
		return
	scene._on_action_executing(BattleManager.player_party[0], {"type": "ability", "ability_id": "fire", "targets": [BattleManager.enemy_party[0]]})
	await get_tree().create_timer(0.3).timeout
	assert_null(scene.get_node_or_null("SignatureTint"), "Fire plays without the glory stage")
	Engine.time_scale = saved


## He plays at 4x: the FIRST cast of each glory spell per battle is shown at 1x; a repeat compresses, a new spell slows again.
func test_each_glory_spell_is_shown_once_at_1x() -> void:
	var scene = await _scene_with_party()
	var saved := Engine.time_scale
	if BattleManager.player_party.is_empty() or BattleManager.enemy_party.is_empty():
		assert_true(false, "CONTROL: a party and a foe")
		return
	var mage: Combatant = BattleManager.player_party[0]
	var foes: Array = BattleManager.enemy_party.duplicate()
	var firaga: Dictionary = JobSystem.get_ability("firaga")
	scene._set_battle_time_scale(1.0)
	scene._play_signature(mage, null, null, firaga, foes, "glory_firaga")
	await get_tree().process_frame
	assert_almost_eq(Engine.time_scale, BS_SPEEDS_1X, 0.001, "the first Firaga is shown at 1x")
	var beat: float = (scene.SIGNATURE_WINDUP + scene.sequence_total("glory_firaga") + 1.0) / BS_SPEEDS_1X
	var deadline := Time.get_ticks_msec() + int(beat * 1500.0)
	while Time.get_ticks_msec() < deadline and not is_equal_approx(Engine.time_scale, 1.0):
		await get_tree().process_frame
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "then the player's speed comes back")
	scene._play_signature(mage, null, null, firaga, foes, "glory_firaga")
	await get_tree().process_frame
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "a second Firaga compresses")
	scene._play_signature(mage, null, null, JobSystem.get_ability("thundaga"), foes, "glory_thundaga")
	await get_tree().process_frame
	assert_almost_eq(Engine.time_scale, BS_SPEEDS_1X, 0.001, "but the first Thundaga is a new moment, shown at 1x")
	scene._set_battle_time_scale(1.0)
	Engine.time_scale = saved


## Intensity tiers: a tier-3 caster's glory spawns more than a tier-1's (min_tier phases join in).
func test_a_stronger_caster_gets_a_grander_glory() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	for id in GLORY:
		var counts := {}
		for t in [1, 3]:
			var fx := FractalFX.new(host, 7)
			fx.tier = t
			fx.play(FractalFX.load_sequence("glory_" + id), Vector2(200, 300), Vector2(900, 300))
			await get_tree().create_timer(2.2).timeout
			counts[t] = fx.spawned
			for c in host.get_children():
				c.queue_free()
			await get_tree().process_frame
		assert_gt(counts[1], 0, "CONTROL: glory_%s spawned at tier 1" % id)
		assert_gt(counts[3], counts[1], "glory_%s grows at tier 3 (%d vs %d)" % [id, counts[3], counts[1]])
