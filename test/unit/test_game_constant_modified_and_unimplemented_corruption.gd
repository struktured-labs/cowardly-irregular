extends GutTest

## tick 179 regression: two follow-up gaps from tick 178's audit:
##
##   1. game_constant_modified signal (declared at GameState.gd:14,
##      emitted by modify_constant) had ZERO listeners. Same
##      silent-failure class as tick 178's save_corrupted gap.
##      Scriptweaver's main verb (modify_constant) silently
##      succeeded with no UI surface.
##
##   2. _apply_random_corruption_effect adds 5 effects to
##      corruption_effects, but only `stat_drain` has a runtime
##      handler in BattleManager._apply_corruption_effects_on_
##      round_start. The other 4 (visual_glitch / bp_instability
##      / encounter_surge / ability_corruption) are authored-but-
##      unimplemented — silently no-op. Player saw the tick-178
##      Toast announcing the effect but nothing happened
##      mechanically. CLAUDE.md design principle #7: silent
##      failures are worse than crashes.

const GAME_STATE := "res://src/meta/GameState.gd"
const GAME_LOOP := "res://src/GameLoop.gd"
const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── game_constant_modified wiring ───────────────────────────────────────

func test_gameloop_connects_game_constant_modified() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("GameState.game_constant_modified.connect(_on_game_constant_modified)"),
		"GameLoop._ready must connect game_constant_modified to the Toast handler")


func test_gameloop_uses_is_connected_guard_on_game_constant_modified() -> void:
	var src := _read(GAME_LOOP)
	assert_true(src.contains("not GameState.game_constant_modified.is_connected(_on_game_constant_modified)"),
		"connect must be guarded by is_connected check")


func test_game_constant_handler_uses_arrow_display_format() -> void:
	# Pin: format shows "OLD → NEW" so the player sees what changed.
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _on_game_constant_modified")
	assert_gt(idx, -1, "_on_game_constant_modified must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	# Pin the ✎ pencil marker + → arrow + Toast.show
	assert_true(body.contains("✎ %s: %s → %s"),
		"Toast format must show '✎ <name>: <old> → <new>' so player sees what changed")
	assert_true(body.contains("Toast.show(self,"),
		"handler must call Toast.show")


func test_game_constant_handler_uses_default_color() -> void:
	# Pin: DEFAULT_COLOR (yellow) since this is a PLAYER-initiated
	# edit, not corruption (which is WARNING/DANGER).
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _on_game_constant_modified")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("Toast.DEFAULT_COLOR"),
		"player-initiated edit uses DEFAULT_COLOR (yellow) — distinct from corruption WARNING/DANGER")


func test_game_constant_handler_prettifies_name() -> void:
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _on_game_constant_modified")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("constant_name.replace(\"_\", \" \").capitalize()"),
		"constant name must be prettified for display (snake_case → Title Case)")


# ── Unimplemented corruption effects surface push_warning ───────────────

func test_unimplemented_corruption_effects_push_warning() -> void:
	var src := _read(BATTLE_MANAGER)
	# Find _apply_corruption_effects_on_round_start body.
	var idx: int = src.find("func _apply_corruption_effects_on_round_start")
	assert_gt(idx, -1, "_apply_corruption_effects_on_round_start must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	# Pin the push_warning fragment.
	assert_true(body.contains("push_warning(\"[BattleManager] corruption effect"),
		"unimplemented corruption effects must push_warning so they surface in CI runs")
	# Pin all 4 unimplemented names in the iterated list.
	for name in ["visual_glitch", "bp_instability", "encounter_surge", "ability_corruption"]:
		var quoted: String = "\"" + name + "\""
		assert_true(body.contains(quoted),
			"unimplemented-list iteration must include '%s'" % name)


func test_implemented_corruption_effects_still_handled() -> void:
	# Negative regression: stat_drain (implemented) and
	# time_distortion (the other implemented effect) must still
	# have their runtime handlers.
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func _apply_corruption_effects_on_round_start")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("if \"stat_drain\" in active_effects:"),
		"stat_drain runtime handler preserved")
	assert_true(body.contains("if \"time_distortion\" in active_effects:"),
		"time_distortion runtime handler preserved")


func test_push_warning_message_explains_gap() -> void:
	# Pin: the push_warning message references where the effect
	# was added so devs can find both ends of the gap.
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func _apply_corruption_effects_on_round_start")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("GameState._apply_random_corruption_effect"),
		"warning must reference GameState._apply_random_corruption_effect (the source side of the gap)")
	assert_true(body.contains("never consumed"),
		"warning must say 'never consumed' so the silent-failure framing is clear")


# ── Cross-pin: tick 178 emit still in place ─────────────────────────────

func test_tick_178_corruption_effect_added_signal_still_wired() -> void:
	# Don't regress tick 178 while building on it.
	var src := _read(GAME_LOOP)
	assert_true(src.contains("GameState.corruption_effect_added.connect(_on_corruption_effect_added)"),
		"tick 178's corruption_effect_added connect must remain")
	assert_true(src.contains("GameState.save_corrupted.connect(_on_save_corruption_increased)"),
		"tick 178's save_corrupted connect must remain")
