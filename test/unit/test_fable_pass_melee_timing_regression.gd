extends GutTest

## Fable pass 2026-07-16 (struktured): "even basic attack should feel
## snappier and cleaner, feels like alignment of weapon to monster is
## off, timing and emphasis of what frame does what is wrong and should
## be nonlinear (the attack slows down slightly during impact)... font
## for showing damage is too small, should prob be fatter and bigger."
##
## Three engine changes pinned here:
## 1. Contact distance derives from BOTH sprites' rendered half-widths
##    (fixed 40px put attackers inside 300px monsters).
## 2. Nonlinear timing: EASE_IN approach → _apply_hitstop at contact
##    (hit fx + damage land AT the contact callback, not a later timer)
##    → EASE_OUT settle.
## 3. Damage numbers: base 16→24, tiers to 34, outline 2→5.

const SCENE := "res://src/battle/BattleScene.gd"
const DMG := "res://src/ui/DamageNumber.gd"


func _melee_body() -> String:
	var src := FileAccess.get_file_as_string(SCENE)
	var i := src.find("func _animate_melee_attack")
	var next: int = src.find("\nfunc _apply_hit_knockback", i)
	return src.substr(i, (next - i) if next > -1 else 4000)


func test_contact_distance_derives_from_sprite_widths() -> void:
	var body := _melee_body()
	# Composite resolution: cowir-battle's _melee_contact_gap (mercy+fallback consts) won over the parallel half-width draft.
	assert_true("_melee_contact_gap(attacker_sprite, target_sprite)" in body,
		"stop distance must derive from both rendered half-widths via _melee_contact_gap — the fixed 40px was the weapon-alignment complaint")
	assert_false("direction * 40  #" in body,
		"the bare fixed-40px stop must be gone")


func test_nonlinear_timing_shape() -> void:
	var body := _melee_body()
	var ease_in_at := body.find("Tween.EASE_IN)")
	var hitstop_at := body.find("_apply_hitstop(")
	var ease_out_at := body.find("Tween.EASE_OUT)")
	assert_gt(ease_in_at, -1, "approach must accelerate (EASE_IN)")
	assert_gt(hitstop_at, ease_in_at, "hitstop fires at contact, after the approach")
	assert_gt(ease_out_at, hitstop_at, "settle decelerates (EASE_OUT), after contact")
	assert_true("_delayed_play_hit_fx(target_anim, target_sprite)" in body,
		"hit fx + damage must land AT the contact callback — the old fixed 0.1s later timer desynced emphasis from the frame")


func test_hitstop_helper_is_visual_only_and_restores() -> void:
	var src := FileAccess.get_file_as_string(SCENE)
	var i := src.find("func _apply_hitstop")
	assert_gt(i, -1)
	var next: int = src.find("\nfunc ", i + 1)
	var body := src.substr(i, (next - i) if next > -1 else 900)
	assert_false("Engine.time_scale" in body,
		"hitstop must NOT touch Engine.time_scale — timers/music/battle logic stay real-time")
	assert_true("speed_scale = 0.05" in body, "freeze via AnimatedSprite2D.speed_scale")
	assert_true("speed_scale = 1.0" in body, "must restore playback")
	assert_true("is_instance_valid(s)" in body, "restore must be validity-guarded (sprite can free mid-stop)")


func test_damage_numbers_bigger_and_fatter() -> void:
	var src := FileAccess.get_file_as_string(DMG)
	assert_true("var base_size = 24" in src, "base damage font 16→24")
	assert_true("base_size = 34" in src, "top tier 24→34")
	assert_true("outline_size\", 5" in src, "outline 2→5 — the 'fatter' half")
