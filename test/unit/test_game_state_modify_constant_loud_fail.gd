extends GutTest

## tick 303: GameState.modify_constant now push_warnings on unknown
## constants instead of using a silent print().
##
## Same silent-fail class as tick 180's JobSystem.assign_job fix.
## Pre-fix a Scriptweaver typo'd constant name returned false with no
## diagnostic — invisible in the production debugger panel and CI.
## Looked like the modification "succeeded but rolled back" since no
## visible error fired and the constant didn't change.


const GAME_STATE := "res://src/meta/GameState.gd"


# ── Source pin: push_warning on unknown constant ──────────────────

func test_unknown_constant_pushes_warning() -> void:
	var src: String = FileAccess.get_file_as_string(GAME_STATE)
	var fn_idx: int = src.find("func modify_constant")
	assert_gt(fn_idx, -1, "modify_constant must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("push_warning(\"[GameState] modify_constant: constant"),
		"modify_constant must push_warning on unknown constant name")


# ── Negative pin: silent print path gone ─────────────────────────

func test_silent_print_path_removed() -> void:
	var src: String = FileAccess.get_file_as_string(GAME_STATE)
	var fn_idx: int = src.find("func modify_constant")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_false(body.contains("print(\"Error: Unknown game constant:"),
		"silent 'Error: Unknown game constant' print must be replaced with push_warning")


# ── Behavioral: returns false on unknown, doesn't mutate state ───

func test_unknown_constant_returns_false() -> void:
	var ok: bool = GameState.modify_constant("__definitely_not_a_real_constant_xyz", 42.0)
	assert_false(ok, "modify_constant must return false on unknown constant")
	# Defensive: confirm the bogus key wasn't created as a side effect.
	assert_false(GameState.game_constants.has("__definitely_not_a_real_constant_xyz"),
		"unknown-constant modify must NOT create the key in game_constants (no silent insertion)")


# ── Behavioral: known constant still modifies + returns true ─────

func test_known_constant_still_modifies() -> void:
	# damage_multiplier ships as a default game_constant (verified at
	# tick time).
	var prior = GameState.game_constants.get("damage_multiplier", null)
	assert_ne(prior, null, "test precondition: damage_multiplier must exist as a default constant")
	var ok: bool = GameState.modify_constant("damage_multiplier", 2.5)
	assert_true(ok, "modify_constant must return true on known constant")
	assert_eq(GameState.game_constants["damage_multiplier"], 2.5,
		"known constant must be updated to the new value")
	# Restore.
	GameState.game_constants["damage_multiplier"] = prior


# ── game_constant_modified signal still fires on success ────────

func test_signal_fires_on_known_constant() -> void:
	var prior = GameState.game_constants.get("damage_multiplier", null)
	watch_signals(GameState)
	GameState.modify_constant("damage_multiplier", 3.0)
	assert_signal_emitted(GameState, "game_constant_modified",
		"game_constant_modified must still fire on successful modify (tick 179 invariant)")
	# Restore.
	GameState.game_constants["damage_multiplier"] = prior


# ── Negative: signal must NOT fire on unknown ────────────────────

func test_signal_does_not_fire_on_unknown() -> void:
	watch_signals(GameState)
	GameState.modify_constant("__never_existed_zzz", 1.0)
	assert_signal_not_emitted(GameState, "game_constant_modified",
		"game_constant_modified must NOT fire when the constant was unknown")
