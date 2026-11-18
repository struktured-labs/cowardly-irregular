extends GutTest

## struktured via cowir-main 26106: "animation wise I just want the magic to be even more amazing looking for starters".
## Every tier of Fire, Blizzard and Thunder now charges at the hand, pops on release, punches the target at impact
## (impact frames and a hitstop) and leaves a shockwave behind. Cure, Cura and Protect pop on release and wash the
## screen. These arms judge that shape, that none of it moves the impact the turn waits on, and both flash settings.

const FX := preload("res://src/battle/FractalFX.gd")
const BOLTS := ["fire_battle", "fira_battle", "glory_firaga", "blizzard_battle", "blizzara_battle", "thunder_battle", "thundara_battle"]
const WASHES := ["cure_battle", "cura_battle", "protect_battle"]
## BattleScene holds the battle until impact + this much; the freeze on the target must end inside it.
const HOLD_AFTER_IMPACT := 0.35

var _saved_flag = null
var _saved_bg = null
var _bg: ColorRect = null
var _tints: Array = []


func before_each() -> void:
	_saved_flag = GameState.reduce_flashes
	var found = EffectSystem.battle_background
	_saved_bg = found if is_instance_valid(found) else null
	_bg = ColorRect.new()
	add_child_autofree(_bg)
	_bg.modulate = Color.WHITE
	EffectSystem.battle_background = _bg
	_tints = []


func after_each() -> void:
	GameState.reduce_flashes = _saved_flag
	EffectSystem.battle_background = _saved_bg if is_instance_valid(_saved_bg) else null


func _seq(id: String) -> Dictionary:
	var s: Dictionary = FX.load_sequence(id)
	assert_false(s.is_empty(), "CONTROL: %s exists" % id)
	return s


## The impact relative to the sequence's own phase clock (FX.impact_time adds `start`).
func _impact(seq: Dictionary) -> float:
	return FX.impact_time(seq) - float(seq.get("start", 0.0))


## The pose's release frame is where the gather ends (Thunder's bolt leaves later, from the hand ring), as test_the_mage_casts_in_phases defines it.
func _release(seq: Dictionary) -> float:
	for ph in seq.get("phases", []):
		if str(ph.get("kind", "")) == "gather":
			return float(ph.get("at", 0.0)) + float(ph.get("dur", 0.0))
	return -1.0


func _has(seq: Dictionary, test: Callable) -> bool:
	for ph in seq.get("phases", []):
		if int((ph as Dictionary).get("min_tier", 1)) <= 1 and bool(test.call(ph)):
			return true
	return false


func test_every_tier_charges_pops_punches_and_lingers() -> void:
	for id in BOLTS:
		var seq := _seq(id)
		var impact := _impact(seq)
		var release := _release(seq)
		assert_gt(release, 0.0, "CONTROL: %s leaves the hand" % id)
		assert_true(_has(seq, func(ph): return ph["kind"] == "ring" and str(ph.get("origin", "")) == "hand" and float(ph["at"]) < release),
			"%s charges at the hand before it leaves" % id)
		assert_true(_has(seq, func(ph): return ph["kind"] == "flash" and str(ph.get("origin", "")) == "hand" and absf(float(ph["at"]) - release) <= 0.02),
			"%s pops at the hand as it leaves" % id)
		for kind in ["impact_frame", "hitstop"]:
			assert_true(_has(seq, func(ph): return ph["kind"] == kind and absf(float(ph["at"]) - impact) <= 0.02), "%s lands with a %s" % [id, kind])
		assert_true(_has(seq, func(ph): return ph["kind"] == "ring" and str(ph.get("origin", "target")) == "target" and float(ph["at"]) > impact and float(ph["at"]) + FX.phase_duration(ph) >= impact + 0.5),
			"%s leaves a shockwave that outlasts the hit" % id)
	for id in WASHES:
		var seq := _seq(id)
		assert_true(_has(seq, func(ph): return ph["kind"] == "tint" and absf(float(ph["at"]) - _impact(seq)) <= 0.02), "%s washes the screen as it lands" % id)


func test_a_bigger_spell_never_holds_the_turn_longer() -> void:
	for id in BOLTS:
		var seq := _seq(id)
		var impact := _impact(seq)
		for ph in seq.get("phases", []):
			if str(ph.get("kind", "")) == "hitstop":
				assert_lte(float(ph["at"]) + float(ph.get("dur", 0.09)), impact + HOLD_AFTER_IMPACT, "%s: the freeze ends inside the hold the battle already waits" % id)
	## The tail is free: the hold reads the impact, never the sequence's total, so a longer afterglow costs no turn time.
	var seq := _seq("fire_battle")
	var total := 0.0
	for ph in seq.get("phases", []):
		total = maxf(total, float(ph.get("at", 0.0)) + FX.phase_duration(ph))
	assert_gt(total, _impact(seq) + HOLD_AFTER_IMPACT, "CONTROL: Fire's afterglow runs past the hold, which only the impact sets")


func _tint_after_frame(reduced: bool) -> Color:
	var host := Node2D.new()
	add_child_autofree(host)
	var target := AnimatedSprite2D.new()
	host.add_child(target)
	var fx := FX.new(host, 3)
	fx.actors = {"target": target}
	fx.reduce_flashes = reduced
	fx.play({"phases": [{"kind": "impact_frame", "at": 0.0, "actor": "target", "frame": 0.1}]}, Vector2.ZERO, Vector2.ZERO)
	var mat := target.material as ShaderMaterial
	assert_not_null(mat, "CONTROL: the impact frame put its silhouette on the target")
	## Read off the material, not the actor: a late frame that also restores the actor still leaves the white on it.
	await get_tree().create_timer(0.15).timeout
	return mat.get_shader_parameter("tint") if mat != null else Color.TRANSPARENT


func test_reduce_flashes_keeps_the_dark_impact_frame_and_drops_the_white() -> void:
	var white := await _tint_after_frame(false)
	assert_true(white.is_equal_approx(Color(1, 1, 1, 1)), "CONTROL: the second impact frame is white (%s)" % str(white))
	var dark := await _tint_after_frame(true)
	assert_lt(dark.r, 0.5, "with Reduce Flashes the target never goes white (%s)" % str(dark))


func _tinted_within(frames: int) -> bool:
	for i in frames:
		await get_tree().process_frame
		if not _bg.modulate.is_equal_approx(Color.WHITE):
			return true
	return false


func test_a_heal_washes_the_screen_unless_flashes_are_reduced() -> void:
	GameState.reduce_flashes = false
	var played: Dictionary = EffectSystem.spawn_sequence("cure_battle", Vector2(900, 300), Vector2(300, 300), 1.0, {}, 1, true)
	assert_false(played.is_empty(), "CONTROL: Cure played")
	assert_true(await _tinted_within(6), "Cure's landing tints the battle backdrop")
	if EffectSystem._background_tint_tween != null and EffectSystem._background_tint_tween.is_valid():
		EffectSystem._background_tint_tween.kill()
	_bg.modulate = Color.WHITE
	GameState.reduce_flashes = true
	EffectSystem.spawn_sequence("cure_battle", Vector2(900, 300), Vector2(300, 300), 1.0, {}, 1, true)
	assert_false(await _tinted_within(6), "with Reduce Flashes the backdrop holds still")


func _note_tint(color: Color, dur: float) -> void:
	_tints.append([color, dur])


func test_a_tint_phase_reaches_whoever_owns_the_backdrop() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var fx := FX.new(host, 5)
	fx.on_tint = _note_tint
	fx.play({"phases": [{"kind": "tint", "at": 0.0, "dur": 0.45, "color": [1.25, 1.2, 1.0, 1.0]}]}, Vector2.ZERO, Vector2.ZERO)
	assert_eq(_tints.size(), 1, "the tint phase calls its owner once")
	if _tints.size() == 1:
		assert_true((_tints[0][0] as Color).is_equal_approx(Color(1.25, 1.2, 1.0, 1.0)), "with its authored colour")
		assert_almost_eq(float(_tints[0][1]), 0.45, 0.001, "and its authored length")
