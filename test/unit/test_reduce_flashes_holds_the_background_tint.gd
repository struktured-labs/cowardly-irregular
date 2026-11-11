extends GutTest

## cowir-controller's Reduce Flashes read of the .792 stack (23883): a fire, ice, holy or dark eruption snapped the
## WHOLE battle background to its colour (fire to (1.3, 0.7, 0.5) in 0.06 s), and only lightning's was gated. Firaga now
## erupts once per foe and again 0.32 s later, so the setting has to hold the background too.

var _saved_flag = null
var _saved_bg = null
var _bg: ColorRect = null


func before_each() -> void:
	_saved_flag = GameState.reduce_flashes
	_saved_bg = EffectSystem.battle_background
	_bg = ColorRect.new()
	add_child_autofree(_bg)
	_bg.modulate = Color.WHITE
	EffectSystem.battle_background = _bg


func after_each() -> void:
	GameState.reduce_flashes = _saved_flag
	EffectSystem.battle_background = _saved_bg


func _tinted_after(frames: int) -> bool:
	for i in frames:
		await get_tree().process_frame
		if not _bg.modulate.is_equal_approx(Color.WHITE):
			return true
	return false


func test_an_eruption_tints_the_background_unless_flashes_are_reduced() -> void:
	GameState.reduce_flashes = false
	EffectSystem._tint_battle_background(Color(1.3, 0.7, 0.5, 1.0), 0.4)
	assert_true(await _tinted_after(6), "CONTROL: with the setting off, the eruption tints the background")
	if EffectSystem._background_tint_tween != null and EffectSystem._background_tint_tween.is_valid():
		EffectSystem._background_tint_tween.kill()
	_bg.modulate = Color.WHITE
	GameState.reduce_flashes = true
	EffectSystem._tint_battle_background(Color(1.3, 0.7, 0.5, 1.0), 0.4)
	assert_false(await _tinted_after(6), "with Reduce Flashes on, the background keeps its colour")


func test_every_eruption_element_goes_through_the_gated_tint() -> void:
	## A source pin with both boundaries: the gate is in the one tint function, and no caller writes the background itself.
	var src := FileAccess.get_file_as_string("res://src/battle/EffectSystem.gd")
	var fn := src.substr(src.find("func _tint_battle_background("))
	fn = fn.substr(0, fn.find("\nfunc ", 1))
	assert_true(fn.contains("_reduce_flashes()"), "the tint function itself reads the setting")
	assert_gt(src.count("_tint_battle_background("), 4, "CONTROL: several elements call it")
	assert_eq(src.count("battle_background, \"modulate\""), fn.count("battle_background, \"modulate\""),
		"nothing tweens the background's colour outside the gated function")


func test_a_second_tint_replaces_the_first() -> void:
	GameState.reduce_flashes = false
	EffectSystem._tint_battle_background(Color(1.3, 0.7, 0.5, 1.0), 0.4)
	var first: Tween = EffectSystem._background_tint_tween
	EffectSystem._tint_battle_background(Color(0.65, 0.75, 1.0, 1.0), 0.4)
	assert_false(first.is_valid() and first.is_running(), "an eruption per foe must not leave tweens fighting over the background")
	assert_true(EffectSystem._background_tint_tween.is_valid(), "CONTROL: the newest tint is the live one")
	EffectSystem._background_tint_tween.kill()
