extends GutTest

## struktured 2026-11-01: "all the bosses need their own interesting animated attacks". Batch 1 gives each W1 boss its
## own presentation of one move: monsters.json `fx_signature` (an ability in its kit) and `fx_signature_card` (a title,
## a subtitle, and for Mordaine a spoken bark). When THAT boss casts it, BattleScene plays sig_<monster_id> from
## data/vfx_sequences.json behind a title card. Anyone else casting the same ability gets the plain effect, so a shared
## ability (and W1's balance, which he locked) is untouched: no numbers move, only what you see.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const BS_SPEEDS_1X := 0.25

## The floor batch 1 must not fall below: each W1 boss and the move it was given.
const W1 := {
	"cave_rat_king": "rat_swarm",
	"fire_dragon": "inferno_rage",
	"ice_dragon": "absolute_zero",
	"lightning_dragon": "lightning_dash",
	"shadow_dragon": "void_breath",
	"chancellor_mordaine": "thundaga",
}

var _monsters: Dictionary
var _sequences: Dictionary
var _guard
var _saved_flash := false


func before_all() -> void:
	_monsters = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/vfx_sequences.json"))
	_sequences = raw.get("sequences", {}) if raw is Dictionary else {}


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


func _kit(entry: Dictionary) -> Array:
	var out: Array = []
	for a in entry.get("abilities", []):
		out.append(a if a is String else str((a as Dictionary).get("id", "")))
	return out


func test_every_w1_boss_carries_its_signature() -> void:
	for mid in W1:
		var e: Dictionary = _monsters.get(mid, {})
		assert_eq(str(e.get("fx_signature", "")), W1[mid], "%s presents %s as its own" % [mid, W1[mid]])


## Derived over every holder, so a boss added in a later batch is judged by the same rules without editing this file.
func test_every_signature_resolves_to_its_own_sequence_and_card() -> void:
	var holders := 0
	for mid in _monsters:
		var e = _monsters[mid]
		if not (e is Dictionary) or not e.has("fx_signature"):
			continue
		holders += 1
		var sig := str(e["fx_signature"])
		assert_true(sig in _kit(e), "%s's fx_signature '%s' is a move in its own kit" % [mid, sig])
		assert_true(JobSystem.get_ability(sig).size() > 0, "%s's fx_signature '%s' resolves in abilities.json" % [mid, sig])
		var seq_id := str(e.get("fx_signature_sequence", "sig_" + mid))
		var seq = _sequences.get(seq_id, {})
		assert_true(seq is Dictionary and (seq.get("phases", []) as Array).size() >= 4,
			"%s's signature plays a bespoke sequence '%s' of at least four beats" % [mid, seq_id])
		var card = e.get("fx_signature_card", {})
		assert_true(card is Dictionary and str(card.get("title", "")) != "", "%s's signature has a title card" % mid)
	assert_gte(holders, W1.size(), "CONTROL: the batch-1 bosses were found and judged (%d)" % holders)


func test_the_boss_casting_its_move_plays_its_sequence_and_nobody_else_does() -> void:
	var scene = SCENE.instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	var mordaine := Combatant.new()
	mordaine.set_meta("monster_type", "chancellor_mordaine")
	autofree(mordaine)
	assert_eq(scene.signature_sequence(mordaine, "thundaga"), "sig_chancellor_mordaine", "Mordaine's Thundaga is Summary Judgment")
	assert_eq(scene.signature_sequence(mordaine, "firaga"), "", "her other moves stay plain")
	var other := Combatant.new()
	other.set_meta("monster_type", "fire_dragon")
	autofree(other)
	assert_eq(scene.signature_sequence(other, "thundaga"), "", "another caster's Thundaga stays plain")
	assert_eq(scene.signature_sequence(other, "inferno_rage"), "sig_fire_dragon", "CONTROL: Pyrroth's own move is his")
	var party := Combatant.new()
	autofree(party)
	assert_eq(scene.signature_sequence(party, "thundaga"), "", "a party member is never a boss")


## The DISPATCH, not just the lookup: a boss's real cast through _on_action_executing raises its title card.
func test_a_bosss_real_cast_raises_its_title_card() -> void:
	var scene = SCENE.instantiate()
	scene.encounter_enemies = ["goblin"]
	add_child_autofree(scene)
	for i in 3:
		await get_tree().process_frame
	var saved := Engine.time_scale
	var boss: Combatant = BattleManager.enemy_party[0] if BattleManager.enemy_party.size() > 0 else null
	assert_not_null(boss, "CONTROL: a foe to play the boss")
	if boss == null:
		return
	boss.set_meta("monster_type", "chancellor_mordaine")
	scene._on_action_executing(boss, {"type": "ability", "ability_id": "thundaga", "targets": [BattleManager.player_party[0]]})
	await get_tree().process_frame
	var card := scene.get_node_or_null("UI/SignatureCard")
	assert_not_null(card, "Mordaine's Thundaga raises the Summary Judgment card")
	if card:
		assert_true(str((card.get_child(0).get_child(0) as Label).text) == "Summary Judgment", "and it reads her title")
	Engine.time_scale = saved


## The stage is the boss's (cowir-main 2026-11-04): a real cast dims it and tints the backdrop in the sequence's colour.
func test_a_signature_takes_the_stage() -> void:
	var scene = SCENE.instantiate()
	scene.encounter_enemies = ["goblin"]
	add_child_autofree(scene)
	for i in 3:
		await get_tree().process_frame
	var saved := Engine.time_scale
	var boss: Combatant = BattleManager.enemy_party[0] if BattleManager.enemy_party.size() > 0 else null
	assert_not_null(boss, "CONTROL: a foe to play the boss")
	if boss == null:
		return
	boss.set_meta("monster_type", "chancellor_mordaine")
	scene._on_action_executing(boss, {"type": "ability", "ability_id": "thundaga", "targets": [BattleManager.player_party[0]]})
	await get_tree().create_timer(0.3).timeout
	var tint := scene.get_node_or_null("SignatureTint") as ColorRect
	assert_not_null(tint, "the backdrop takes the boss's colour")
	if tint:
		var want: Color = scene.signature_tint("sig_chancellor_mordaine")
		assert_almost_eq(tint.color.r, want.r, 0.01, "in the sequence's own tint")
		assert_gt(tint.color.a, 0.0, "and it is showing")
	Engine.time_scale = saved


## A self-aimed signature (Rat Swarm) still lands on the PARTY: its _wave sequence rolls onto every living member.
func test_a_self_aimed_signature_rolls_onto_the_party() -> void:
	var scene = SCENE.instantiate()
	scene.encounter_enemies = ["goblin"]
	add_child_autofree(scene)
	for i in 3:
		await get_tree().process_frame
	var boss: Combatant = BattleManager.enemy_party[0] if BattleManager.enemy_party.size() > 0 else null
	if boss == null:
		fail_test("CONTROL: a foe to play the boss")
		return
	boss.set_meta("monster_type", "cave_rat_king")
	var host: Node = EffectSystem._effects_container
	assert_not_null(host, "CONTROL: the effects layer exists")
	if host == null:
		return
	var before := host.get_child_count()
	scene._spawn_signature_wave(boss, scene.enemy_sprite_nodes[0], JobSystem.get_ability("rat_swarm"), [boss], "sig_cave_rat_king")
	await get_tree().process_frame
	var living := BattleManager.player_party.filter(func(m): return m.is_alive).size()
	assert_gte(host.get_child_count() - before, living, "one wave per living member (%d members)" % living)
	before = host.get_child_count()
	scene._spawn_signature_wave(boss, scene.enemy_sprite_nodes[0], JobSystem.get_ability("thundaga"), [BattleManager.player_party[0]], "sig_chancellor_mordaine")
	await get_tree().process_frame
	assert_eq(host.get_child_count() - before, 0, "CONTROL: a party-aimed signature needs no wave")


func test_the_verdict_card_carries_its_title_and_bark() -> void:
	var card: Dictionary = _monsters["chancellor_mordaine"]["fx_signature_card"]
	assert_eq(str(card.get("title", "")), "Summary Judgment")
	assert_eq(str(card.get("bark", "")), "The assessment is complete. I am only reading it into the record.",
		"the bark is keyed to its recording on this exact text")


func test_reduce_flashes_dims_the_signature_but_still_plays_it() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var sizes := {}
	for reduce in [false, true]:
		var fx := FractalFX.new(host, 7)
		fx.reduce_flashes = reduce
		var before := host.get_child_count()
		var total: float = fx.play(FractalFX.load_sequence("sig_chancellor_mordaine"), Vector2(200, 300), Vector2(900, 300))
		assert_gt(total, 0.5, "the signature plays with reduce_flashes=%s" % reduce)
		await get_tree().create_timer(0.9).timeout
		var biggest := 0.0
		for i in range(before, host.get_child_count()):
			var c = host.get_child(i)
			if c is Sprite2D:
				biggest = maxf(biggest, (c as Sprite2D).scale.x)
		sizes[reduce] = biggest
		for c in host.get_children():
			c.queue_free()
		await get_tree().process_frame
	assert_gt(sizes[false], 0.0, "CONTROL: the flash was measured")
	assert_lt(sizes[true], sizes[false], "Reduce Flashes shrinks the verdict's flash (%.2f vs %.2f)" % [sizes[true], sizes[false]])


## He plays at 4x (cowir-main 2026-11-01): a boss's FIRST signature each battle runs at 1x pacing, the rest compress,
## and autogrind/turbo never slows. A speed the player picks mid-beat is left alone.
func test_the_first_signature_plays_at_1x_then_the_speed_comes_back() -> void:
	var scene = SCENE.instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	var saved := Engine.time_scale
	var king := Combatant.new()
	king.set_meta("monster_type", "cave_rat_king")
	king.combatant_name = "Cave Rat King"
	autofree(king)
	var sprite: Node2D = scene.enemy_sprite_nodes[0] if scene.enemy_sprite_nodes.size() > 0 else null
	var ability: Dictionary = JobSystem.get_ability("rat_swarm")
	var picked: int = scene._battle_speed_index
	scene._set_battle_time_scale(1.0)
	scene._play_signature(king, sprite, null, ability, [king], "sig_cave_rat_king")
	await get_tree().process_frame
	assert_almost_eq(Engine.time_scale, BS_SPEEDS_1X, 0.001, "the first Rat Swarm of the battle is shown at 1x")
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline and not is_equal_approx(Engine.time_scale, 1.0):
		await get_tree().process_frame
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "then the player's 4x comes back")
	assert_eq(scene._battle_speed_index, picked, "the 1x beat is a transient override: the persisted speed choice never moved")
	scene._play_signature(king, sprite, null, ability, [king], "sig_cave_rat_king")
	await get_tree().process_frame
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "a second Rat Swarm in the same battle compresses")
	var dragon := Combatant.new()
	dragon.set_meta("monster_type", "fire_dragon")
	autofree(dragon)
	scene.turbo_mode = true
	scene._play_signature(dragon, sprite, null, JobSystem.get_ability("inferno_rage"), [dragon], "sig_fire_dragon")
	await get_tree().process_frame
	assert_almost_eq(Engine.time_scale, 1.0, 0.001, "turbo never slows, even for a first cast")
	scene.turbo_mode = false
	Engine.time_scale = saved
