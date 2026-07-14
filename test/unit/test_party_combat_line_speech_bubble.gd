extends GutTest

## tick 122 regression: party combat dialogue lines must surface as
## speech bubbles over the PC's sprite, not just battle-log text.
## Pre-fix, _emit_party_line only emit battle_log_message — so a
## player who didn't have the log open / scrolled to bottom would
## miss the line entirely. Mirrors the advance_trash_talk pattern
## (line 24 signal + _spawn_quip_bubble surface).

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"
const BATTLE_SCENE := "res://src/battle/BattleScene.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_party_combat_line_signal_declared() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("signal party_combat_line(combatant: Combatant, line: String, voice_trigger: String)"),
		"BattleManager must declare party_combat_line with voice_trigger arg (msg 2105 voice convention)")


func test_emit_party_line_fires_both_log_and_bubble_signals() -> void:
	# Pin: _emit_party_line emits BOTH battle_log_message (text
	# scrollback) AND party_combat_line (bubble surface). Losing
	# either drops one path of the dual presentation.
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func _emit_party_line")
	assert_gt(idx, -1, "_emit_party_line must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("battle_log_message.emit("),
		"_emit_party_line must still emit battle_log_message — preserves scrollback")
	assert_true(body.contains("party_combat_line.emit(combatant, line, voice_trigger)"),
		"_emit_party_line must also emit party_combat_line with voice_trigger — drives the bubble + voice surface")


func test_battle_scene_connects_party_combat_line_signal() -> void:
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("BattleManager.party_combat_line.connect(_on_party_combat_line)"),
		"BattleScene must connect party_combat_line — otherwise the bubble never spawns")


func test_battle_scene_disconnect_handles_party_combat_line() -> void:
	# Pin the cleanup path — same pattern as advance_trash_talk.
	# Without disconnect on cleanup, the connection leaks across scene
	# transitions and a second BattleScene would spawn duplicate bubbles.
	var src := _read(BATTLE_SCENE)
	assert_true(src.contains("BattleManager.party_combat_line.is_connected(_on_party_combat_line)"),
		"BattleScene cleanup must check is_connected for party_combat_line — symmetric with other signals")
	assert_true(src.contains("BattleManager.party_combat_line.disconnect(_on_party_combat_line)"),
		"BattleScene cleanup must disconnect party_combat_line — prevents leaks across battles")


func test_party_combat_line_handler_uses_spawn_quip_bubble() -> void:
	# Pin: the handler routes through _spawn_quip_bubble (the
	# canonical speech-bubble path). Direct UI manipulation would
	# bypass the turbo/speed/autogrind suppression rules.
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("func _on_party_combat_line")
	assert_gt(idx, -1, "_on_party_combat_line handler must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("_spawn_quip_bubble(sprite, combatant.combatant_name, line"),
		"handler must call _spawn_quip_bubble — canonical bubble path")


func test_party_handler_respects_turbo_mode() -> void:
	# Pin: turbo_mode short-circuit. _spawn_quip_bubble has its own
	# guard but the handler's early-return saves the sprite lookup.
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("func _on_party_combat_line")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("if turbo_mode:\n\t\treturn"),
		"_on_party_combat_line must short-circuit on turbo_mode — saves cycles + matches advance_trash_talk pattern")


func test_handler_uses_job_quip_color() -> void:
	# Per-job color via _get_job_quip_color matches the established
	# pattern. A hardcoded color would clash with the rest of the
	# battle's color story.
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("func _on_party_combat_line")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("_get_job_quip_color(combatant)"),
		"handler must use _get_job_quip_color for the bubble border — matches advance_trash_talk styling")


func test_bubble_hold_time_2_seconds() -> void:
	# Pin the 2.0s hold (longer than the 1.5s default — combat
	# dialogue tends to be wordier than mid-combat quips). Trivial
	# but pinned so a future refactor doesn't silently change it.
	var src := _read(BATTLE_SCENE)
	var idx: int = src.find("func _on_party_combat_line")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("_get_job_quip_color(combatant), 2.0, audio_key)"),
		"party combat line bubble must hold for 2.0s — longer than the 1.5s default for shorter quips")
