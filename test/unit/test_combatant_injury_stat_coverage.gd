extends GutTest

## tick 287: apply_permanent_injury match statement now covers max_mp
## AND has a default arm that surfaces unknown stats.
##
## Pre-fix the match handled only max_hp / attack / defense / magic /
## speed. Two silent-fail cases:
##
##   1. max_mp injury (not in BattleManager.INJURY_TYPES but valid
##      from Scriptweaver / custom paths): silently no-op'd. The
##      injury was still appended to permanent_injuries but max_mp
##      was unchanged.
##
##   2. typo'd / unknown stat (e.g. "luck" before it became a real
##      stat, or "atck" misspelled): same silent no-op. UI showed
##      the injury but the player's stats stayed put.


const COMBATANT_SCRIPT := "res://src/battle/Combatant.gd"


func _make_combatant() -> Combatant:
	var script: GDScript = load(COMBATANT_SCRIPT)
	var c: Combatant = script.new()
	c.combatant_name = "Test"
	c.max_hp = 100
	c.current_hp = 100
	c.max_mp = 50
	c.current_mp = 50
	c.attack = 20
	c.defense = 15
	c.magic = 10
	c.speed = 12
	c.is_alive = true
	add_child_autofree(c)
	return c


# ── max_mp injury now actually reduces max_mp ─────────────────────

func test_max_mp_injury_reduces_max_mp() -> void:
	var c := _make_combatant()
	c.apply_permanent_injury({"stat": "max_mp", "penalty": 8})
	assert_eq(c.max_mp, 42,
		"max_mp injury must reduce max_mp by penalty (was silent no-op pre-tick-287)")
	assert_eq(c.current_mp, 42,
		"current_mp must clamp to new max_mp ceiling")


func test_max_mp_injury_no_overclamp_when_below_new_ceiling() -> void:
	var c := _make_combatant()
	c.current_mp = 30  # Already below the new ceiling
	c.apply_permanent_injury({"stat": "max_mp", "penalty": 8})
	# Pre: 30/50. Post: max_mp=42, current_mp stays at 30.
	assert_eq(c.max_mp, 42, "max_mp still reduced")
	assert_eq(c.current_mp, 30, "current_mp unchanged when already under new ceiling")


# ── Unknown stat injury triggers push_warning (source pin) ────────

func test_unknown_stat_pushes_warning() -> void:
	# We can't easily capture push_warning output in GUT, so pin at
	# the source level — the default arm with a "unknown stat" warning
	# must exist.
	var src: String = FileAccess.get_file_as_string(COMBATANT_SCRIPT)
	var fn_idx: int = src.find("func apply_permanent_injury")
	assert_gt(fn_idx, -1, "apply_permanent_injury must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_:") and body.contains("apply_permanent_injury: unknown stat"),
		"apply_permanent_injury must have a default arm with a push_warning naming the unknown stat")


# ── Unknown stat injury still records in permanent_injuries ───────

func test_unknown_stat_still_recorded_in_list() -> void:
	# The injury slot was burned — record it so the player can see
	# the data drift / typo (and the SaveScreen permanent injuries
	# display still shows it).
	var c := _make_combatant()
	c.apply_permanent_injury({"stat": "luck_made_up_stat", "penalty": 3})
	assert_eq(c.permanent_injuries.size(), 1,
		"unknown-stat injury must still append to permanent_injuries list (transparency)")


# ── Existing match arms still work ────────────────────────────────

func test_attack_injury_still_applies() -> void:
	var c := _make_combatant()
	var prev: int = c.attack
	c.apply_permanent_injury({"stat": "attack", "penalty": 5})
	assert_eq(c.attack, prev - 5, "attack injury still applies (regression check)")


func test_max_hp_injury_still_emits_hp_changed() -> void:
	# Tick 284 invariant must survive the tick 287 refactor.
	var c := _make_combatant()
	watch_signals(c)
	c.apply_permanent_injury({"stat": "max_hp", "penalty": 10})
	assert_signal_emitted(c, "hp_changed",
		"tick 284 hp_changed emit must survive the tick 287 match-arm addition")
