extends GutTest

## _on_damage_dealt fires weakness_flash, then attack_hit, then strike_element — one function, no await, one frame.
## All three were on _battle_player, so only the LAST survived: the stinger and the weapon impact were authored, shipped, and never heard on a basic attack.
## Seventh instance of the shared-player class. _sub_player's own comment states the rule these two broke.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const BATTLE_SCENE := "res://src/battle/BattleScene.gd"
const ELEMENTS := ["fire", "ice", "lightning", "dark", "holy"]


func _sm() -> Node:
	return get_node_or_null("/root/SoundManager")


func _holds(player: AudioStreamPlayer, key: String) -> bool:
	return player != null and player.stream != null and str(player.stream.resource_path).contains(key)


func before_each() -> void:
	var sm: Node = _sm()
	if sm:
		sm._sfx_cooldowns.clear()
		sm._combo_step = 0


func test_the_three_hit_layers_have_three_voices() -> void:
	var sm: Node = _sm()
	assert_not_null(sm, "CONTROL: SoundManager autoload must be present")
	if sm == null:
		return
	## Through get() for the same reason as the cap const: a direct reference to a renamed voice
	## aborts, and an abort scores Risky or Passing — never Failing. This file's whole subject is
	## that these two voices EXIST, so their absence has to be the loudest thing it can say.
	for vname in ["_strike_player", "_flash_player"]:
		assert_ne(sm.get(vname), null, "SoundManager has no %s — the voice this file defends is gone or renamed" % vname)
	for p in [sm.get("_strike_player"), sm.get("_flash_player")]:
		assert_not_null(p, "a hit-layer voice is missing")
		assert_ne(p, sm._battle_player, "a layered cue is back on _battle_player — it replaces the weapon hit it was meant to ride over")
	assert_ne(sm.get("_strike_player"), sm.get("_flash_player"), "the stinger shares the element's voice — a weakness hit with an elemental weapon loses one of them")


func test_the_weapon_hit_no_longer_replaces_the_weakness_stinger() -> void:
	# THE live bug, in BattleScene's order: the stinger fires at :5079, the hit at :5120.
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_weakness_flash()
	var stinger = sm._flash_player.stream
	assert_true(_holds(sm._flash_player, "weakness_flash"), "CONTROL: weakness_flash must have loaded, or 'not replaced' is vacuous")
	sm.play_attack_hit("sword", false)
	assert_eq(sm._flash_player.stream, stinger, "the weapon hit replaced weakness_flash — the stinger is silent on every basic attack that exploits a weakness")
	assert_true(sm._battle_player.stream != null, "CONTROL: the weapon hit must genuinely have played")


func test_the_element_no_longer_replaces_the_weapon_hit() -> void:
	# BattleScene :5127 says the element "rides over" the hit. On one voice it replaced it.
	var sm: Node = _sm()
	if sm == null:
		return
	var checked := 0
	for element in ELEMENTS:
		if not sm._sfx_manifest.has("strike_" + element):
			continue
		sm._sfx_cooldowns.clear()
		sm._combo_step = 0
		sm.play_attack_hit("sword", false)
		var impact = sm._battle_player.stream
		assert_not_null(impact, "CONTROL: the weapon hit must have loaded for %s" % element)
		sm.play_strike_element(element)
		assert_eq(sm._battle_player.stream, impact, "strike_%s replaced the weapon hit — the sword stops sounding like a sword" % element)
		assert_true(_holds(sm._strike_player, "strike_" + element), "CONTROL: strike_%s must genuinely have played on the element voice" % element)
		checked += 1
	assert_gt(checked, 0, "CONTROL: no element has a strike cue, so this arm checked nothing")


func test_a_weakness_hit_with_an_elemental_weapon_is_all_three() -> void:
	# The full BattleScene sequence, in its source order, in one frame.
	var sm: Node = _sm()
	if sm == null:
		return
	sm.play_weakness_flash()
	sm.play_attack_hit("sword", false)
	sm.play_strike_element("fire")
	var streams := [sm._flash_player.stream, sm._battle_player.stream, sm._strike_player.stream]
	for s in streams:
		assert_not_null(s, "a layer of the weakness hit is not sounding")
	assert_eq(len({streams[0]: 0, streams[1]: 0, streams[2]: 0}), 3, "two layers resolved to one stream — the compound beat is fewer sounds than it reads as")
	assert_true(_holds(sm._flash_player, "weakness_flash"), "the stinger is not the one sounding on the flash voice")
	assert_true(_holds(sm._strike_player, "strike_fire"), "the element is not the one sounding on the strike voice")


func test_the_three_calls_really_do_share_one_frame() -> void:
	# The bug only exists because they are in ONE synchronous body. Pin that, so a future
	# await between them doesn't leave these arms defending a hazard that has moved.
	var code: String = GdSource.code_of(BATTLE_SCENE)
	assert_ne(code, "", "CONTROL: BattleScene source must have loaded")
	var start: int = code.find("func _on_damage_dealt(")
	assert_gt(start, -1, "CONTROL: _on_damage_dealt is gone — these arms no longer describe the caller")
	var nxt: int = code.find("\nfunc ", start + 1)
	var body: String = code.substr(start, nxt - start) if nxt > start else code.substr(start)
	for call in ["play_weakness_flash(", "play_attack_hit(", "play_strike_element("]:
		assert_true(body.contains(call), "%s left _on_damage_dealt — the same-frame premise is stale" % call)
	assert_false(body.contains("await"), "_on_damage_dealt gained an await — the three layers may no longer share a frame")
