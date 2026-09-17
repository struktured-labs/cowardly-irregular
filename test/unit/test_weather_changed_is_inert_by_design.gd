extends GutTest

## `weather_changed` has ZERO consumers, and its emit contract is inconsistent. That is fine today
## and is a trap for whoever connects it first.
##
##     set_weather()            assigns, then EMITS          GameState:398-401
##     roll (the timer path)    assigns, then EMITS          GameState:385-387
##     _apply_save_data() (LOAD)  assigns, and does NOT emit   GameState:511
##                                  (`from_dict` is a 109-char wrapper that calls it)
##
## Nothing breaks now because `WeatherSystem` POLLS `get_weather()` every frame rather than
## listening — so the missing emit on load costs nothing and the signal is dead weight.
##
## ⛔ THE TRAP IS THE ORDER A LANE MEETS THIS IN: you connect the signal because it exists, you
## test it by changing the weather (which emits), and the path that does NOT emit is the one you
## only reach by LOADING A SAVE. So it works in every test you would think to write.
##
## This pins the state rather than changing it. Emitting from `from_dict` is NOT an obvious repair:
## it would fire mid-load, while the rest of GameState is still half-restored, at a listener that
## does not exist yet. That is struktured's call if the signal ever gains a consumer.
##
## AUTHORED_AHEAD, per CLAUDE.md's passive-roster pattern: this reds when the claim stops being
## true, in EITHER direction.

const GAMESTATE := "res://src/meta/GameState.gd"
const GdSource := preload("res://test/unit/helpers/gd_source.gd")


func _code() -> String:
	var s: String = GdSource.code_of(GAMESTATE)
	assert_ne(s, "", "CONTROL: GameState.gd must read back as code")
	return s


func test_the_signal_is_still_declared() -> void:
	## Without this the arms below pass on a signal that was deleted — which would be a fine
	## outcome, but a silent one, and this file would then be describing nothing.
	assert_true(_code().contains("signal weather_changed"),
		"weather_changed is gone — delete this guard too, it exists only to describe that signal")


func test_nothing_connects_it_yet() -> void:
	## The moment this reds, someone has a consumer and the arm below becomes load-bearing for them.
	var connections: int = 0
	for path in _gd_files("res://src"):
		var body: String = GdSource.code_of(path)
		if body.contains("weather_changed") and body.contains("connect"):
			for line in body.split("\n"):
				if line.contains("weather_changed") and line.contains("connect"):
					connections += 1
	assert_eq(connections, 0,
		"weather_changed now has %d consumer(s) — read the next arm: the LOAD path does not emit, so a restored save will not notify them" % connections)


func test_the_load_path_still_does_not_emit() -> void:
	## The asymmetry itself, pinned where a reader will find it. If someone MAKES from_dict emit,
	## this reds and they update the guard deliberately rather than the contract drifting silently.
	## ⛔ THE LOAD PATH IS `_apply_save_data`, NOT `from_dict` — which is a 109-char wrapper that
	## calls it. My first version named the wrapper and the CONTROL below caught it: the arm
	## described nothing, which is exactly what a control is for.
	var body: String = _func_body(_code(), "func _apply_save_data")
	assert_ne(body, "", "CONTROL: GameState must declare _apply_save_data")
	assert_true(body.contains("weather_condition = str(save_data"),
		"CONTROL: _apply_save_data must still restore weather_condition, or this arm describes nothing")
	assert_false(body.contains("weather_changed.emit"),
		"_apply_save_data now emits weather_changed — that is a contract CHANGE, not a fix: it fires mid-load while the rest of GameState is half-restored. Update this guard on purpose.")


func test_the_setters_do_emit() -> void:
	## The other side of the asymmetry, so "nothing emits" can never be mistaken for the claim.
	var body: String = _func_body(_code(), "func set_weather")
	assert_ne(body, "", "CONTROL: GameState must declare set_weather")
	assert_true(body.contains("weather_changed.emit"),
		"set_weather no longer emits — the asymmetry this guard describes is gone in the other direction")


func _gd_files(root: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(root + "/" + f)
	for sub in d.get_directories():
		out.append_array(_gd_files(root + "/" + sub))
	return out


## The body of `header`'s function, or "" when absent — a whole-file `contains` cannot tell a CALL
## from the DEFINITION it is named after.
func _func_body(src: String, header: String) -> String:
	var i: int = src.find(header)
	if i < 0:
		return ""
	var j: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (j - i) if j > i else -1)
