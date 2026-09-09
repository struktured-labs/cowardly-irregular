extends GutTest

## struktured asked for lightning "flashier and more absurd ... fat and the whole screen is like a
## storm with bolts" (2026-09-07). He also told us the autobattle system is "incredible to watch
## when u pop it off", and he plays with it on constantly.
##
## _full_render_active required a MANUAL turn, so the storm — and every other Full Render cinematic
## — could not play on an automated one. The player who asked for the spectacle was configured never
## to see it. Found because cowir-deploy could not photograph the storm across six capture attempts
## while the cast demonstrably landed; their control (the Bard's chord captured cleanly from the
## same dispatch site) is what made it a gate question rather than a timing one.
##
## SPEED is the intent signal, and the gate already reads it: 1x/2x is watching, 4x+ is grinding.

const BS_SRC := "res://src/battle/BattleScene.gd"


func _gate_body() -> String:
	var src := FileAccess.get_file_as_string(BS_SRC)
	var i: int = src.find("func _full_render_active")
	assert_gt(i, -1, "CONTROL: the Full Render gate still exists")
	var nxt: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (nxt - i) if nxt > i else 1600)


func test_an_automated_turn_is_no_longer_refused_outright() -> void:
	var body := _gate_body()
	## Pin the STATEMENT, not the NAME. The first version of this asserted the flag name appeared
	## anywhere in the body — and the explanatory comment above the code satisfies that, so
	## reverting the gate to manual-only left this test GREEN. Four lanes hit that same substitution
	## today; mine was inside the guard against it.
	assert_true(body.contains('or BattleJuice.flag("full_render_on_autobattle")'),
		"the gate must CONSULT the flag in an expression, not merely mention it in prose")
	assert_true(body.contains("return allowed"),
		"and must return the widened decision, not `manual` bare")


func test_the_speed_gate_is_untouched() -> void:
	## The whole argument is that SPEED already draws the watching/grinding line. If this arm ever
	## goes, the cinematic starts firing at 4x and turbo and the change becomes indefensible.
	var body := _gate_body()
	assert_true(body.contains("Engine.time_scale > 0.55"),
		"Full Render must still be refused above 2x speed")
	assert_true(body.contains("turbo_mode") and body.contains("autogrind_console_mode"),
		"turbo and the autogrind console must still refuse it outright")


func test_the_flag_defaults_on_and_can_be_turned_off() -> void:
	# Unknown names default TRUE by design, so the widening is live without a registry entry;
	# GameState.battle_fx_flags is the off switch for anyone who wants the old behaviour.
	assert_true(BattleJuice.flag("full_render_on_autobattle"),
		"default must be ON — it is what he asked for")
	if GameState and "battle_fx_flags" in GameState:
		GameState.battle_fx_flags["full_render_on_autobattle"] = false
		assert_false(BattleJuice.flag("full_render_on_autobattle"),
			"and it must be switchable off, or it is not a toggle")
		GameState.battle_fx_flags.erase("full_render_on_autobattle")
		assert_true(BattleJuice.flag("full_render_on_autobattle"), "restored")


func test_a_player_character_is_still_required() -> void:
	# Widening the manual test must not widen the party test — an enemy cast has never had a
	# cinematic and this change is not the place to give it one.
	var body := _gate_body()
	assert_true(body.contains("BattleManager.player_party"),
		"only a player character's cast gets Full Render")


func test_the_storm_has_exactly_one_dispatch_site_and_it_is_behind_this_gate() -> void:
	## Why the gate mattered so much for THIS effect: `storm` is reachable from nowhere else, so a
	## refused gate is not a downgraded cinematic, it is no storm at all.
	var src := FileAccess.get_file_as_string(BS_SRC)
	var release_at: int = src.find("func _full_render_release_visual")
	var storm_at: int = src.find('"storm":\n\t\t\t_full_render_storm', release_at)
	assert_gt(release_at, -1, "CONTROL: the release visual still exists")
	assert_gt(storm_at, release_at,
		"the storm shape must be dispatched from inside the Full Render release, which is what makes the gate decisive")
