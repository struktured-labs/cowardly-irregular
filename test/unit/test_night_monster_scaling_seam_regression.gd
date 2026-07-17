extends GutTest

## msg 2643 day/night directive — cowir-battle scope: night monster stat
## scaling on encounter-spawned enemies when GameState.is_night(). This
## cycle ships the SEAM only — multiplier defaults to 1.0 (identity, no
## behavioral change) until struktured rules on:
##
##   1. The suggested +15-20% range (cowir-main's proposal).
##   2. Whether it stacks or caps with cowir-autogrind's
##      monster_adaptation_level (+15%/level, same class). At night +
##      adaptation-level-5 with a pure multiplicative stack, that's
##      ~2.28× base stats. Deliberately deferring the composition
##      question by shipping identity until his ack.
##
## The seam wires:
##   spawn_encounter_enemies  ← YES scaling (overworld random encounters)
##   spawn_from_data          ← YES scaling (autogrind battles)
##   spawn_forced_enemies     ← NO scaling  (story/boss/miniboss)
##
## Defensive: GameState.is_night() may not exist yet if cowir-main's
## day/night surface hasn't landed. Helper returns stats unchanged in
## that case.

const BES_PATH: String = "res://src/battle/BattleEnemySpawner.gd"
const BESScript = preload("res://src/battle/BattleEnemySpawner.gd")


## ── Helper surface ────────────────────────────────────────────────────

func test_helper_declared_as_public() -> void:
	# PUBLIC (no leading underscore) so cowir-autogrind's create_scaled_
	# enemy_data can call it from the autogrind side and both live/headless
	# tiers inherit identical scaling by construction (msg 2655 parity).
	var src: String = FileAccess.get_file_as_string(BES_PATH)
	assert_string_contains(src, "static func apply_night_scaling_to_stats(stats: Dictionary) -> Dictionary:",
		"helper must be PUBLIC (no leading underscore) so cross-lane callers can invoke — msg 2655 parity design")
	assert_false(src.find("static func _apply_night_scaling_to_stats(") > -1,
		"the leading-underscore private version must be gone — a private helper can't fix the live/headless parity gap")


func test_night_scaled_stats_list_is_named_const() -> void:
	# Which stats scale is a design decision — max_mp and speed excluded.
	# Named const keeps that decision greppable + testable.
	var src: String = FileAccess.get_file_as_string(BES_PATH)
	assert_string_contains(src, "const NIGHT_SCALED_STATS: Array = [\"max_hp\", \"attack\", \"defense\", \"magic\"]",
		"must scale max_hp/attack/defense/magic; must NOT scale max_mp (ability cost balance) or speed (turn order compounding with adaptation)")


## ── Wired at the two encounter/autogrind sites; NOT at the forced site ─

func test_helper_called_in_spawn_encounter_enemies() -> void:
	var src: String = FileAccess.get_file_as_string(BES_PATH)
	# Anchor on the msg 2643 comment specifically added at this site so we
	# can't match against the sibling spawn_from_data comment by accident.
	var idx: int = src.find("Night scaling seam (msg 2643): applied AFTER speed variation")
	assert_gt(idx, -1, "encounter-spawn site must document the scaling seam")
	var window: String = src.substr(idx, 400)
	assert_string_contains(window, "stats = apply_night_scaling_to_stats(stats)",
		"encounter-spawn must reassign the helper's return so mutations land in stats")


func test_spawn_from_data_does_NOT_apply_night_scaling() -> void:
	# msg 2655 parity design: cowir-autogrind's create_scaled_enemy_data
	# owns the upstream call so BOTH live (spawn_from_data) AND headless
	# (_resolve_headless_battle in GameLoop) inherit the same scaled dict
	# by construction. Applying the scaling HERE would double-scale live-
	# tier grinds.
	var src: String = FileAccess.get_file_as_string(BES_PATH)
	var func_idx: int = src.find("func spawn_from_data(enemy_data_array: Array) -> void:")
	assert_gt(func_idx, -1)
	var next: int = src.find("\nfunc ", func_idx + 1)
	var body: String = src.substr(func_idx, (next - func_idx) if next > -1 else 3000)
	# Match the actual assignment form to avoid false-matching on the
	# parity-design note that mentions the helper by name in prose.
	assert_false(body.find("stats = apply_night_scaling_to_stats(") > -1,
		"spawn_from_data must NOT call apply_night_scaling_to_stats — autogrind's create_scaled_enemy_data owns that upstream to close the live/headless parity gap (msg 2655)")
	# But the CONTRACT reminder must remain so a future refactor doesn't
	# accidentally reintroduce the seam here without seeing the parity note.
	assert_string_contains(body, "msg 2655 live/headless parity",
		"the parity-design note must remain — otherwise the next dev sees a bare spawn_from_data and wonders why it's not wired")


func test_forced_enemies_skip_night_scaling() -> void:
	# spawn_forced_enemies handles boss/miniboss/story spawns. Applying
	# night scaling to Mordaine or Lockward would break their precisely-
	# tuned encounters (msg 2586 balance-rule).
	var src: String = FileAccess.get_file_as_string(BES_PATH)
	# The forced-spawn function's body must NOT contain the helper call.
	# Locate the function by its distinctive is_boss_battle guard.
	var idx: int = src.find("var is_boss_battle = false")
	assert_gt(idx, -1, "spawn_forced_enemies anchor must exist")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 3000)
	assert_false(body.find("apply_night_scaling_to_stats(") > -1,
		"forced-enemy spawn (boss/miniboss/story) must NOT go through night scaling — msg 2586 balance-rule protects precise boss tuning")


## ── Behavioral: helper is truly identity when multiplier==1.0 ─────────

func test_helper_is_noop_without_game_state() -> void:
	# In the GUT headless env there's no GameState autoload — the helper
	# must return stats unchanged rather than error.
	var input: Dictionary = {"max_hp": 100, "attack": 10, "defense": 5, "magic": 3, "speed": 8, "max_mp": 20}
	var expected: Dictionary = input.duplicate()
	var actual: Dictionary = BESScript.apply_night_scaling_to_stats(input)
	assert_eq(actual["max_hp"], expected["max_hp"], "max_hp unchanged when GameState missing")
	assert_eq(actual["attack"], expected["attack"], "attack unchanged when GameState missing")
	assert_eq(actual["defense"], expected["defense"], "defense unchanged when GameState missing")
	assert_eq(actual["magic"], expected["magic"], "magic unchanged when GameState missing")


func test_helper_returns_original_dict_when_gs_lacks_is_night() -> void:
	# Defensive against cowir-main's parallel work landing timing.
	# Install a GameState stub WITHOUT is_night() and confirm the helper
	# short-circuits before touching anything.
	var stub := _NightStub.new()
	stub.name = "GameState"
	# NOTE: not setting has_method - actual `has_method` reflection is what
	# the code guards on. The stub doesn't define is_night; the check should
	# skip the whole scaling path.
	get_tree().root.add_child(stub)
	var input: Dictionary = {"max_hp": 100, "attack": 10}
	var result: Dictionary = BESScript.apply_night_scaling_to_stats(input)
	stub.queue_free()
	assert_eq(result["max_hp"], 100, "unchanged when is_night() method missing")
	assert_eq(result["attack"], 10, "unchanged when is_night() method missing")


## Minimal GameState stub without is_night — exercises the has_method guard.
class _NightStub extends Node:
	var game_constants: Dictionary = {"night_monster_multiplier": 1.5}


## ── Source pin: the identity contract stays even after future edits ───

func test_helper_returns_early_when_multiplier_is_identity() -> void:
	var src: String = FileAccess.get_file_as_string(BES_PATH)
	var idx: int = src.find("static func apply_night_scaling_to_stats(stats: Dictionary) -> Dictionary:")
	assert_gt(idx, -1)
	var next: int = src.find("\nstatic func ", idx + 1)
	if next == -1:
		next = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 2000)
	assert_string_contains(body, "if absf(mult - 1.0) < 0.001:",
		"the identity guard must remain — otherwise every encounter runs the multiply loop unnecessarily")
	assert_string_contains(body, "night_monster_multiplier",
		"multiplier key must be spelled exactly night_monster_multiplier — cowir-main's day/night surface will look for this exact key")
