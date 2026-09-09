extends GutTest

## Of the 18 keys HeadlessBattleResolver._build_results returns, `log` was the ONLY one with zero
## consumers — swept with the definer excluded and a fabricated-key control at 0. The console has
## had a battle-log panel the whole time, fed by 50 of its OWN status calls, while the narration of
## the fight it is watching went nowhere.
##
## It matters more than a stray key. Every named refusal the resolver emits writes into that log:
## "unknown ability", "unmodelled type — no effect", member_ability's does-not-know / lacks-MP, the
## MAX_ROUNDS stalemate reason. A day spent turning silent failures into refusals that name
## themselves, and not one of them reached a player.

var _ui


func before_each() -> void:
	_ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)
	_ui._battle_log = RichTextLabel.new()
	_ui._battle_log.bbcode_enabled = true
	add_child_autofree(_ui._battle_log)


func _panel_text() -> String:
	return _ui._battle_log.get_parsed_text()


func test_resolver_narration_reaches_the_panel() -> void:
	_ui._ludicrous_speed_enabled = false
	_ui.append_resolver_log(["Cleric heals Mage for 650", "Mage attacks Slime for 40"])
	assert_true(_panel_text().contains("heals Mage for 650"), "the narration must reach the panel")
	assert_true(_panel_text().contains("attacks Slime"), "every line, not just the first")


func test_a_refusal_reaches_the_player() -> void:
	## The whole point. These strings are what the resolver emits when something cannot fire, and
	## before this they existed only in headless print output.
	_ui._ludicrous_speed_enabled = false
	_ui.append_resolver_log(["Cleric: unknown ability 'zzq' — no effect"])
	assert_true(_panel_text().contains("unknown ability"),
		"a named refusal must be visible where the player is already looking")


func test_ludicrous_speed_suppresses_it() -> void:
	## Mirrors BattleScene:4279 — the round banner is suppressed at 4x+ "same convention as speech
	## bubbles". At ludicrous the point is throughput, and 45 log sites per battle would bury the
	## console's own status lines.
	_ui._ludicrous_speed_enabled = true
	_ui.append_resolver_log(["Cleric heals Mage for 650"])
	assert_false(_panel_text().contains("heals Mage"), "ludicrous speed must suppress the narration")


func test_suppression_is_speed_scoped_not_a_global_off_switch() -> void:
	# ARM+: without this, an append_resolver_log that never appended would pass the arm above.
	_ui._ludicrous_speed_enabled = true
	_ui.append_resolver_log(["suppressed line"])
	_ui._ludicrous_speed_enabled = false
	_ui.append_resolver_log(["visible line"])
	assert_true(_panel_text().contains("visible line"), "turning ludicrous off must restore it")
	assert_false(_panel_text().contains("suppressed line"), "and the suppressed one stays gone")


func test_the_console_own_messages_still_work() -> void:
	# ARM+ for the trim change: _log_message is used by 50 existing call sites and must be intact.
	_ui._log_message("Autogrind started")
	assert_true(_panel_text().contains("Autogrind started"), "the console's own logging must survive")


func test_the_panel_does_not_grow_without_limit() -> void:
	## Pre-existing: the panel never trimmed, so a long grind grew it unbounded. Forwarding a
	## 45-line-per-battle narration into it makes that worse, so the bound lands in the same change.
	for i in range(_ui.BATTLE_LOG_MAX_LINES + 120):
		_ui._log_message("line %d" % i)
	assert_lt(_ui._battle_log.get_line_count(), _ui.BATTLE_LOG_MAX_LINES + 60,
		"the panel must stay bounded, got %d lines" % _ui._battle_log.get_line_count())
	assert_true(_panel_text().contains("line %d" % (_ui.BATTLE_LOG_MAX_LINES + 119)),
		"and trimming must keep the NEWEST lines — the tail is what scroll_following shows")


func test_an_empty_log_is_a_no_op() -> void:
	_ui._ludicrous_speed_enabled = false
	_ui.append_resolver_log([])
	assert_eq(_panel_text().strip_edges(), "", "an empty result log must add nothing")
