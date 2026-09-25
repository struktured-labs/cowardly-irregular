extends GutTest

## Reduce Flashes promises to suppress full-screen flash effects in battle.
## Fire, Blizzard and Thunder still painted a screen-sized ColorRect, and Thunder
## also strobed the whole backdrop white. Shake on those same spells already
## obeyed its own toggle. The banner text and the spell particles are not flashes.

class TintProbe extends EffectSystemClass:
	var tints: Array[Color] = []
	func _tint_battle_background(tint_color: Color, _duration: float = 0.3) -> void:
		tints.append(tint_color)


var _saved_flashes: bool = false
var _saved_shake: bool = true


func before_each() -> void:
	_saved_flashes = GameState.reduce_flashes
	_saved_shake = GameState.screen_shake_enabled
	GameState.screen_shake_enabled = false


func after_each() -> void:
	GameState.reduce_flashes = _saved_flashes
	GameState.screen_shake_enabled = _saved_shake


func test_spell_flashes_are_suppressed_when_reduce_flashes_is_on() -> void:
	GameState.reduce_flashes = true
	for which in ["fire", "ice", "lightning"]:
		var found := _cast(which)
		assert_eq(found["flashes"], 0,
			"%s still covers the screen with a flash while Reduce Flashes is on" % which)
		if which == "lightning":
			assert_eq(found["tints"].size(), 0,
				"Thunder still strobes the battle background white while Reduce Flashes is on")


func test_spell_flashes_still_play_when_reduce_flashes_is_off() -> void:
	GameState.reduce_flashes = false
	for which in ["fire", "ice", "lightning"]:
		var found := _cast(which)
		assert_eq(found["flashes"], 1,
			"%s must still flash the screen when Reduce Flashes is off" % which)
		if which == "lightning":
			assert_eq(found["tints"].size(), 1, "Thunder's background strobe must still run when the setting is off")
			assert_true((found["tints"][0] as Color).is_equal_approx(Color(2.0, 2.0, 2.5, 1.0)),
				"Thunder's strobe is the full-screen white blowout, not a mild tint")


func _cast(which: String) -> Dictionary:
	var es := TintProbe.new()
	add_child_autofree(es)
	var host := Node2D.new()
	es.add_child(host)
	match which:
		"fire":
			es._animate_fire(host, Callable(), 0.5)
		"ice":
			es._animate_ice(host, Callable(), 0.5)
		"lightning":
			es._animate_lightning(host, Callable(), 0.5)
	var flashes := 0
	for c in host.get_children():
		if c is ColorRect:
			flashes += 1
	return {"flashes": flashes, "tints": es.tints}
