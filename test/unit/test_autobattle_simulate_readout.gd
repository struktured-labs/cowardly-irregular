extends GutTest

## Simulate — "what does this grid actually DO?" (2026-08-06)
##
## CLAUDE.md: "mastering autobattle scripting IS the game." There was no way to test a
## script except walking into a fight and inferring from the log. This adds a readout in
## the grid editor: for sampled combatant states, which rule fires and what it does.
##
## ⚠️ IT DELIBERATELY DOES NOT RUN A BATTLE. `HeadlessBattleResolver.resolve_battle`
## CLEARS AND REPOPULATES THE LIVE `BattleManager` parties (:81-88, restoring at three
## exit points). That is correct for autogrind, which runs with no live battle, and unsafe
## beside a live session — and the grid editor IS reachable mid-battle (GameLoop:997 picks
## the current combatant via `if current in BattleManager.player_party`). Three ways it
## bites: the empty-party guard in `_check_victory_conditions` returns true on two empty
## parties; anything reading the parties during the window sees []; an error between clear
## and restore leaves the live battle with no combatants.
##
## Measured instead: `_evaluate_grid_rule` and `_evaluate_condition` read ZERO live state.
## So pure evaluation answers the same question with nothing to restore and nothing to race.

const EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"


func _editor() -> Node:
	var e: Node = load(EDITOR).new()
	e.character_id = "sim_probe_hero"
	e.character_name = "Probe"
	add_child_autofree(e)
	return e


## ── the safety property, asserted rather than assumed ────────────────

func test_simulate_never_touches_the_live_battle_manager() -> void:
	# The whole reason this is pure evaluation. If a future edit routes Simulate through
	# the resolver, this fails — and the failure is the point.
	var src := FileAccess.get_file_as_string(EDITOR)
	assert_ne(src, "", "the editor must be readable or this assertion is vacuous")
	var start := src.find("func _open_simulate")
	assert_gt(start, -1, "_open_simulate must exist")
	var stop := src.find("func _open_rename_profile")
	assert_gt(stop, start, "the simulate block must be bounded, or the region below is wrong")
	var region := src.substr(start, stop - start)
	assert_gt(region.length(), 400,
		"the parsed region must be substantial — a truncated region satisfies the absence checks below without reading the code they defend")
	assert_false(region.contains("HeadlessBattleResolver"),
		"Simulate must not run a battle — the resolver mutates the LIVE BattleManager parties")
	assert_false(region.contains("BattleManager"),
		"Simulate must not read or write BattleManager state; rule evaluation is pure")


func test_the_evaluators_it_relies_on_are_still_pure() -> void:
	# The premise. If rule evaluation ever starts reading live parties, the pure-evaluation
	# design silently becomes wrong and Simulate would report against an empty battlefield.
	var src := FileAccess.get_file_as_string("res://src/autobattle/AutobattleSystem.gd")
	var start := src.find("func _evaluate_grid_rule")
	var stop := src.find("func _evaluate_grid_condition")
	assert_gt(start, -1, "_evaluate_grid_rule must exist")
	assert_gt(stop, start, "the region must be bounded by the NEXT function, not a distant one — a wide window swept in unrelated helpers that legitimately read live parties")
	var region := src.substr(start, stop - start)
	assert_false(region.contains("_get_enemies_for"),
		"rule evaluation must stay free of live-party reads, or Simulate's pure probe diverges from the real executor")
	assert_false(region.contains("_get_allies_for"),
		"same — allies")


## ── the readout says something true ──────────────────────────────────

func test_an_empty_grid_reports_the_fallback_rather_than_nothing() -> void:
	# A blank readout would read as "Simulate is broken". It must say what actually happens.
	var e := _editor()
	var lines: Array = e._simulate_report([])
	assert_eq(lines.size(), 1, "an empty grid must produce exactly one explanatory line")
	assert_true(str(lines[0]).to_lower().contains("no rules"),
		"the line must say the grid is empty, not leave the panel blank: '%s'" % str(lines[0]))


func test_a_threshold_rule_fires_only_in_the_states_it_should() -> void:
	# The feature's whole value: seeing a threshold work. A rule gated on low HP must fire
	# in the low-HP samples and NOT in the full-HP one — one line proves the readout is
	# state-sensitive rather than printing the same rule four times.
	var e := _editor()
	var rules: Array = [{
		"enabled": true,
		"conditions": [{"type": "hp_percent", "op": "<", "value": 30}],
		"actions": [{"type": "ability", "ability_id": "cure"}],
	}]
	var lines: Array = e._simulate_report(rules)
	assert_eq(lines.size(), 4, "one line per sampled state")
	assert_true(str(lines[0]).contains("no rule matches"),
		"at full HP an hp_below_30 rule must NOT fire: '%s'" % str(lines[0]))
	assert_true(str(lines[3]).contains("rule 1"),
		"at critical HP it must fire: '%s'" % str(lines[3]))


func test_a_disabled_rule_is_skipped() -> void:
	# Disabled rows are a real editor feature; a readout that ignored the flag would
	# advertise behaviour the game will not perform.
	var e := _editor()
	var rules: Array = [
		{"enabled": false, "conditions": [], "actions": [{"type": "attack"}]},
		{"enabled": true, "conditions": [], "actions": [{"type": "defend"}]},
	]
	var lines: Array = e._simulate_report(rules)
	assert_true(str(lines[0]).contains("rule 2"),
		"a disabled first row must be skipped and rule 2 reported: '%s'" % str(lines[0]))


func test_the_probe_never_mutates_the_edited_combatant() -> void:
	# Mutating the real character's HP to answer a UI question is the two-writers class.
	var e := _editor()
	var real: Combatant = autofree(Combatant.new())
	real.combatant_name = "Probe"
	real.max_hp = 500
	real.current_hp = 500
	real.max_mp = 80
	real.current_mp = 80
	e.combatant = real
	e._simulate_report([{"enabled": true, "conditions": [{"type": "hp_percent", "op": "<", "value": 30}], "actions": [{"type": "attack"}]}])
	assert_eq(real.current_hp, 500, "the edited combatant's HP must be untouched by simulation")
	assert_eq(real.current_mp, 80, "and its MP")


## ── controller-first, per the standing rule ──────────────────────────

func test_simulate_is_bound_to_an_existing_pad_action_not_a_new_key() -> void:
	var src := FileAccess.get_file_as_string(EDITOR)
	assert_true(src.contains('is_action_pressed("battle_advance")'),
		"Simulate must bind the existing battle_advance action (R shoulder + R key), not invent a keyboard-only binding")
	var proj := FileAccess.get_file_as_string("res://project.godot")
	assert_true(proj.contains("battle_advance"),
		"battle_advance must exist as a project action, or the binding is unreachable on a pad")


func test_a_battlefield_rule_is_reported_undecidable_not_guessed() -> void:
	# A pure probe has no enemies. Evaluating enemy_hp_percent against nothing would
	# answer confidently about a fight that isn't happening — the "UI lies" defect.
	var e := _editor()
	var lines: Array = e._simulate_report([{
		"enabled": true,
		"conditions": [{"type": "enemy_hp_percent", "op": "<", "value": 50}],
		"actions": [{"type": "attack"}],
	}])
	assert_true(str(lines[0]).contains("battlefield"),
		"a rule reading enemy state must be reported as unsimulatable, not evaluated against an empty field: '%s'" % str(lines[0]))
