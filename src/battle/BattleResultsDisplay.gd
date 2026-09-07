extends RefCounted
class_name BattleResultsDisplay

## BattleResultsDisplay - Handles victory results, damage numbers, and battle feedback overlays
## Extracted from BattleScene to reduce god class complexity

const DamageNumber = preload("res://src/ui/DamageNumber.gd")

var _scene  # Reference to parent BattleScene (untyped to avoid circular dependency)


func _init(scene) -> void:
	_scene = scene


func on_damage_dealt(target: Combatant, amount: int, is_crit: bool, _element: String = "", _elemental_mod: float = 1.0) -> void:
	"""Show floating damage number near target and trigger screen shake"""
	var pos = _get_combatant_sprite_position(target)
	if pos != Vector2.ZERO:
		spawn_damage_number(pos, amount, false, is_crit)
	else:
		print("[DMG NUM] Could not find sprite position for %s" % target.combatant_name)

	if is_crit:
		EffectSystem._trigger_screen_shake(9.0, 0.2)
	else:
		EffectSystem._trigger_screen_shake(3.5, 0.1)


func on_healing_done(target: Combatant, amount: int) -> void:
	"""Show floating heal number AND a soft expanding glow under target.
	The glow gives healing visual parity with damage (which gets screen shake
	+ a number). Previously a heal only spawned a green number — visually
	indistinguishable from any other floaty popup. Now there's a moment."""
	if amount <= 0:
		return  # no "+0" popup/glow — a no-op heal (target already full) produces no feedback
	var pos = _get_combatant_sprite_position(target)
	if pos != Vector2.ZERO:
		spawn_damage_number(pos, amount, true, false)
		spawn_heal_glow(pos)


## Spawn a soft expanding green glow under the target sprite. Tweens alpha
## up over 0.18s and back down over 0.62s while scaling 0.5 → 1.3, then
## queue_frees. Two independent tweens because chain()/parallel()/set_parallel
## are easy to mis-stage; two tweens against the same target are robust.
func spawn_heal_glow(pos: Vector2) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.35, 1.0, 0.5, 0.32)
	sb.corner_radius_top_left = 40
	sb.corner_radius_top_right = 40
	sb.corner_radius_bottom_left = 40
	sb.corner_radius_bottom_right = 40
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_color = Color(0.6, 1.0, 0.7, 0.8)
	panel.add_theme_stylebox_override("panel", sb)
	panel.size = Vector2(90.0, 90.0)
	panel.pivot_offset = panel.size / 2.0
	# Anchored slightly below sprite center so the glow reads as ground-up.
	panel.position = pos - panel.size / 2.0 + Vector2(0.0, 10.0)
	panel.scale = Vector2(0.5, 0.5)
	panel.modulate.a = 0.0
	_scene.add_child(panel)

	# Tween 1: alpha fade in (0.18s) then out (0.62s), then cleanup.
	var fade: Tween = panel.create_tween()
	fade.tween_property(panel, "modulate:a", 0.85, 0.18) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade.tween_property(panel, "modulate:a", 0.0, 0.62) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	fade.tween_callback(panel.queue_free)

	# Tween 2: scale from 0.5 to 1.3 across the full 0.8s envelope.
	var grow: Tween = panel.create_tween()
	grow.tween_property(panel, "scale", Vector2(1.3, 1.3), 0.8) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func on_attack_missed(target: Combatant) -> void:
	"""Show floating MISS text near target"""
	var pos = _get_combatant_sprite_position(target)
	if pos != Vector2.ZERO:
		spawn_miss_number(pos)


func spawn_damage_number(pos: Vector2, amount: int, is_heal: bool, is_crit: bool) -> void:
	"""Spawn a floating damage/heal number"""
	var dmg_num = DamageNumber.new()
	dmg_num.setup(amount, is_heal, is_crit)
	# Tick 208: stagger near-duplicate positions so multi-hit attacks don't cluster into one mushy popup pile.
	var stagger_y: float = _count_recent_popups_near(pos) * STAGGER_STEP
	dmg_num.position = pos + Vector2(randf_range(-10, 10), -30 - stagger_y)
	_scene.add_child(dmg_num)


func spawn_miss_number(pos: Vector2) -> void:
	"""Spawn a floating MISS text"""
	var dmg_num = DamageNumber.new()
	dmg_num.setup_miss()
	# Tick 208: same stagger logic as damage popups — multiple misses on one target (e.g., blind) shouldn't overlap.
	var stagger_y: float = _count_recent_popups_near(pos) * STAGGER_STEP
	dmg_num.position = pos + Vector2(randf_range(-10, 10), -30 - stagger_y)
	_scene.add_child(dmg_num)


# Tick 208: 18px per stacked popup — readable separation without flying immediately off-screen.
const STAGGER_STEP := 18.0
# Tick 208: any DamageNumber within 40px (~0.6s of float time) of the spawn pos counts as a "fresh overlap" and pushes the new one upward.
const STAGGER_RADIUS_SQUARED := 40.0 * 40.0


# Tick 208: count live DamageNumber children near pos. O(N) but N is tiny (4-8 max typically) and runs once per spawn.
func _count_recent_popups_near(pos: Vector2) -> int:
	var count: int = 0
	for child in _scene.get_children():
		if is_instance_valid(child) and child is DamageNumber:
			if child.position.distance_squared_to(pos) < STAGGER_RADIUS_SQUARED:
				count += 1
	return count


func show_victory_results() -> void:
	"""Victory overlay revamp (2026-08-18): VICTORY slam → character-anchored cards → loot strip. Node keeps the "VictoryResults" name — Select toggle, quip suppression, and cleanup key off it."""
	var results = BattleManager.get_battle_results()
	if results.is_empty():
		return
	var overlay := VictoryOverlay.new()
	overlay.name = "VictoryResults"
	_scene.add_child(overlay)
	overlay.build(results, _scene)


func _get_combatant_sprite_position(combatant: Combatant) -> Vector2:
	"""Get the anchor position of a combatant's sprite for damage/heal popups. Prefers the stable base position (idle rest) so a target mid-tween (knockback, lunge, group-attack return) doesn't drag the number off with it. Falls back to live global_position when the base isn't tracked. msg 2569 sprite-misplacement sweep — same class as v3.33.158/167/170 fixes."""
	# Check party members (use BattleManager's array for consistency)
	var party_idx = BattleManager.player_party.find(combatant)
	if party_idx >= 0 and party_idx < _scene.party_sprite_nodes.size():
		var sprite = _scene.party_sprite_nodes[party_idx]
		if is_instance_valid(sprite):
			if party_idx < _scene._party_base_positions.size():
				return _scene._party_base_positions[party_idx]
			return sprite.global_position

	# Check enemies (use BattleManager's array for consistency)
	var enemy_idx = BattleManager.enemy_party.find(combatant)
	if enemy_idx >= 0 and enemy_idx < _scene.enemy_sprite_nodes.size():
		var sprite = _scene.enemy_sprite_nodes[enemy_idx]
		if is_instance_valid(sprite):
			if enemy_idx < _scene._enemy_base_positions.size():
				return _scene._enemy_base_positions[enemy_idx]
			return sprite.global_position

	return Vector2.ZERO
