extends GutTest

## tick 182 regression: MapSystem error/warning prints converted
## to push_error/push_warning. Two sites:
##   - load_map: missing map → push_error
##   - _position_player_at_spawn: missing spawn point → push_warning
##
## Real impact pre-fix: load_map's silent return left current_map
## unchanged, callers had no surface to distinguish "transition
## succeeded" from "transition no-op'd". Missing spawn marker
## left the player at their previous position which looked like
## a broken transition.
##
## Also: two risky tests in the suite ("did not assert" from
## ticks 151/152's typed-array trap class). Both now have
## explicit typed-locals to dodge the SCRIPT ERROR abort.

const MAP_SYSTEM := "res://src/maps/MapSystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── MapSystem ───────────────────────────────────────────────────────────

func test_load_map_missing_pushes_error() -> void:
	var src := _read(MAP_SYSTEM)
	assert_true(src.contains("push_error(\"[MapSystem] load_map: map not found at"),
		"load_map must push_error when ResourceLoader.exists returns false")
	# Negative: old print Error gone.
	assert_false(src.contains("print(\"Error: Map not found:"),
		"old print() Error must be gone")


func test_load_map_warning_explains_consequence() -> void:
	# Pin: warning must say current_map is unchanged so callers
	# know the no-op semantic.
	var src := _read(MAP_SYSTEM)
	assert_true(src.contains("current_map unchanged"),
		"load_map error must explain that current_map stays at the previous map (no-op semantic)")


func test_spawn_point_missing_pushes_warning() -> void:
	var src := _read(MAP_SYSTEM)
	assert_true(src.contains("push_warning(\"[MapSystem] _position_player_at_spawn: spawn point"),
		"_position_player_at_spawn must push_warning when marker not found")
	assert_false(src.contains("print(\"Warning: Spawn point not found:"),
		"old print() Warning must be gone")


func test_spawn_warning_explains_player_position() -> void:
	# Pin: warning must explain that player will remain at last
	# position — devs need to know the symptom maps to "player
	# didn't move" not "player teleported wrong".
	var src := _read(MAP_SYSTEM)
	assert_true(src.contains("player will remain at last position"),
		"spawn-point warning must explain the visible consequence")


# ── Risky test fixes (typed-array trap class) ──────────────────────────

func test_party_dialogue_extra_test_uses_typed_local() -> void:
	# Pin: the previously-risky test now constructs Array[Combatant]
	# explicitly to dodge the typed-array assignment trap.
	var src := _read("res://test/unit/test_party_dialogue_extra_triggers_regression.gd")
	assert_true(src.contains("var typed_party: Array[Combatant] = [c]"),
		"test_damage_handler_no_ops_for_zero_amount must build a typed local before assigning to bm.player_party")
	assert_true(src.contains("bm.player_party = typed_party"),
		"test must assign via the typed local — direct [c] literal silently SCRIPT ERRORs")


func test_party_llm_dialogue_test_uses_typed_local() -> void:
	var src := _read("res://test/unit/test_party_llm_dialogue_regression.gd")
	assert_true(src.contains("var typed_party: Array[Combatant] = [c]"),
		"test_maybe_fire_party_line_no_op_when_flag_off must build a typed local")


# ── Cross-pin: tick 181 warnings still in place ────────────────────────

func test_tick_181_save_warnings_still_present() -> void:
	# Non-regression: don't accidentally lose tick 181's work.
	var src := _read("res://src/save/SaveSystem.gd")
	assert_true(src.contains("push_warning(\"[SaveSystem] _write_save_file"),
		"tick 181 SaveSystem write warning preserved")
	assert_true(src.contains("push_warning(\"[SaveSystem] _read_save_file"),
		"tick 181 SaveSystem read warning preserved")
