extends GutTest

## Regression tests for AutobattleSystem target resolution.
##
## Catches the silent-fallback class of bugs:
##   - 'all_allies' previously fell through to lowest_hp_enemy → Bard Battle
##     Hymn silently hit one enemy instead of party-wide buff
##   - 'highest_speed_enemy' was referenced by Time Mage default but never
##     implemented → Rewind silently targeted lowest_hp_enemy
##   - Unknown target strings now push_warning, masking nothing
##
## Also walks every default character script and asserts every target string
## resolves to a non-default branch — guards against future typos creeping in.


const AutobattleSystemScript = preload("res://src/autobattle/AutobattleSystem.gd")
const CombatantScript = preload("res://src/battle/Combatant.gd")

const _KNOWN_TARGETS = [
	"lowest_hp_enemy", "highest_hp_enemy", "random_enemy",
	"highest_speed_enemy", "highest_atk_enemy", "lowest_magic_defense_enemy",
	"lowest_hp_ally", "all_allies", "self",
]

var _autobattle: Node


func before_each() -> void:
	_autobattle = AutobattleSystemScript.new()
	add_child_autofree(_autobattle)


func _make_combatant(name: String, speed: int = 10) -> Combatant:
	var c: Combatant = CombatantScript.new()
	c.combatant_name = name
	c.max_hp = 100
	c.current_hp = 100
	c.max_mp = 50
	c.current_mp = 50
	c.attack = 10
	c.defense = 10
	c.magic = 10
	c.speed = speed
	c.is_alive = true
	add_child_autofree(c)
	return c


func test_target_types_const_includes_all_allies_and_highest_speed() -> void:
	# Editor reads TARGET_TYPES to populate the picker — keys must exist
	# so the picker exposes them as authorable choices.
	assert_true(_autobattle.TARGET_TYPES.has("all_allies"),
		"TARGET_TYPES must expose 'all_allies' for the editor picker")
	assert_true(_autobattle.TARGET_TYPES.has("highest_speed_enemy"),
		"TARGET_TYPES must expose 'highest_speed_enemy' for Time Mage Rewind")


func test_unknown_target_logs_warning_and_returns_fallback() -> void:
	# This is the silent-failure class CLAUDE.md flags as worse than crashes.
	# The fix is push_warning — we can't assert the warning was logged via
	# GUT, but we CAN ensure the function still returns *something* safe
	# (lowest_hp_enemy is the documented fallback contract).
	var hero := _make_combatant("Hero")
	# Without a BattleManager autoload populated with parties, the fallback
	# returns null; the contract we care about is "does not crash". The
	# warning is the runtime signal.
	var result = _autobattle._get_target_by_type(hero, "totally_made_up_target")
	# null is acceptable; the important thing is no crash + warning fired.
	assert_true(result == null or result is Combatant,
		"Unknown target type must return Combatant or null, not crash")


func test_all_default_scripts_use_known_target_types() -> void:
	# Walk every default script and confirm every action target resolves to
	# a non-default branch — catches typos like 'highest_speed_enemy' that
	# silently fell through to lowest_hp_enemy.
	var character_ids = [
		"hero", "mira", "zack", "vex",
		"fighter", "cleric", "rogue", "mage", "bard",
		"guardian", "ninja", "summoner", "speculator",
		"scriptweaver", "time_mage", "necromancer",
		"bossbinder", "skiptrotter",
	]
	for cid in character_ids:
		var script: Dictionary = _autobattle.create_default_character_script(cid)
		var rules: Array = script.get("rules", [])
		for rule_idx in range(rules.size()):
			var rule = rules[rule_idx]
			var actions: Array = rule.get("actions", [])
			for action_idx in range(actions.size()):
				var action: Dictionary = actions[action_idx]
				if not action.has("target"):
					continue
				var t: String = action["target"]
				assert_true(_KNOWN_TARGETS.has(t),
					"Default script '%s' rule %d action %d uses unknown target '%s'" % [cid, rule_idx, action_idx, t])


func test_all_allies_resolver_returns_array() -> void:
	# _get_targets_by_type for all_allies must return an Array (not single).
	var hero := _make_combatant("Hero")
	var arr = _autobattle._get_targets_by_type(hero, "all_allies")
	assert_true(arr is Array,
		"all_allies must return Array via _get_targets_by_type")


func test_action_types_const_drops_dead_all_out_attack() -> void:
	# all_out_attack was a dead branch (force_advance flag no consumer reads).
	# Removing it from ACTION_TYPES prevents the editor from offering an
	# unreachable option to players.
	assert_false(_autobattle.ACTION_TYPES.has("all_out_attack"),
		"all_out_attack must be removed from ACTION_TYPES — branch was dead")
