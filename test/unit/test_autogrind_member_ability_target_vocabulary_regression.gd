extends GutTest

## member_ability was inert for a target the grammar itself describes.
##
## Found by censusing all six autogrind actions end-to-end through a live controller cycle after
## stop_grinding turned out inert (e949058d). Five worked with a discriminating control —
## heal_party 400->450, restore_mp 10->40, flee_battle skipped the next battle. member_ability
## measured 400->400 against a control that also measured 400->400, and the diagnostic said
## "no valid target".
##
## `target` went straight to _resolve_member, which matches a job id or character name. So
## {"target": "lowest_hp_ally"} named no member and the action did nothing — while the autogrind
## grammar says the target "defaults to the lowest-HP living ally" without saying what a target
## may BE, and DialoguePrompts carries the autobattle target words in the SAME FILE. A Rule
## Composer emitting the phrase the grammar uses produced a rule that validated clean, printed one
## line, and silently did nothing. validate_rule checks member and ability, never target.
##
## The grid-editor path was never affected: only switch_profile declares has_target, so the UI
## erases target for member_ability and gets the default. I checked that rather than assuming it,
## because "the UI writes target: all" was my first theory and it was wrong.

var _ags: Node = null


func before_each() -> void:
	_ags = get_node_or_null("/root/AutogrindSystem")
	if _ags:
		_ags._test_disable_persistence = true
	var abs_node := get_node_or_null("/root/AutobattleSystem")
	if abs_node:
		abs_node._test_disable_persistence = true


func after_each() -> void:
	if _ags:
		_ags.set_autogrind_rules([])
		_ags.is_grinding = false


func _grind(tag: String) -> Array:
	var ctrl = preload("res://src/autogrind/AutogrindController.gd").new()
	add_child_autofree(ctrl)
	var party: Array[Combatant] = []
	for n in ["%s Cleric" % tag, "%s Mage" % tag]:
		var c := Combatant.new()
		c.initialize({"name": n, "max_hp": 1000, "max_mp": 100,
			"attack": 20, "defense": 20, "magic": 30, "speed": 20})
		c.job = JobSystem.get_job("cleric" if n.ends_with("Cleric") else "mage")
		c.job_level = 5
		add_child_autofree(c)
		c.add_item("potion", 10)
		c.current_hp = 400
		party.append(c)
	ctrl.start_grind(party, {"headless": true, "auto_advance": false}, "plains")
	return [ctrl, party]


func _tick(ctrl: Node) -> void:
	ctrl._state = ctrl.State.BETWEEN_BATTLES
	ctrl._between_battle_timer = 0.0
	ctrl._process(0.1)


func _cast_rule(target: String) -> Array:
	var action: Dictionary = {"type": "member_ability", "member": "cleric", "ability": "cure"}
	if target != "":
		action["target"] = target
	return [{"conditions": [{"type": "always"}], "actions": [action], "enabled": true}]


func test_the_grammars_own_target_word_actually_heals() -> void:
	var g := _grind("Vocab")
	var ctrl: Node = g[0]
	var party: Array = g[1]
	var before: int = party[0].current_hp
	_ags.set_autogrind_rules(_cast_rule("lowest_hp_ally"))
	_tick(ctrl)
	assert_gt(party[0].current_hp, before,
		"a target using the phrase the grammar itself uses must heal — 'no valid target' is what it did before, and the rule validated clean while doing it")
	ctrl.stop_grind("test")


func test_the_control_does_not_heal_without_the_action() -> void:
	## The census control. member_ability first measured 400->400 against a control that ALSO
	## measured 400->400, which is how a broken action hides: both arms agree.
	var g := _grind("Control")
	var ctrl: Node = g[0]
	var party: Array = g[1]
	var before: int = party[0].current_hp
	_ags.set_autogrind_rules([])
	_tick(ctrl)
	assert_eq(party[0].current_hp, before,
		"with no rules nothing may heal, or the test above cannot show the action did it")
	ctrl.stop_grind("test")


func test_omitting_the_target_still_uses_the_default() -> void:
	var g := _grind("Default")
	var ctrl: Node = g[0]
	var party: Array = g[1]
	var before: int = party[0].current_hp
	_ags.set_autogrind_rules(_cast_rule(""))
	_tick(ctrl)
	assert_gt(party[0].current_hp, before,
		"omitting target has always meant the lowest-HP ally and must keep meaning it")
	ctrl.stop_grind("test")


func test_naming_a_member_still_targets_that_member() -> void:
	var g := _grind("Named")
	var ctrl: Node = g[0]
	var party: Array = g[1]
	party[1].current_hp = 900              # the mage is the HEALTHIEST, so the default would skip it
	var before: int = party[1].current_hp
	_ags.set_autogrind_rules(_cast_rule("mage"))
	_tick(ctrl)
	assert_gt(party[1].current_hp, before,
		"naming a member must target THAT member — if the generic-target change swallowed member keys, the healthiest member would never be healed")
	ctrl.stop_grind("test")


func test_a_typod_member_target_still_fails_loudly() -> void:
	## The guard against fixing this by making every target mean the default: a member key that
	## resolves to nobody is an authoring error and must not be silently redirected.
	var g := _grind("Typo")
	var ctrl: Node = g[0]
	var party: Array = g[1]
	var before: int = party[0].current_hp
	_ags.set_autogrind_rules(_cast_rule("clric"))
	_tick(ctrl)
	assert_eq(party[0].current_hp, before,
		"a target naming no member must NOT quietly heal someone else — that would hide the typo it should surface")
	ctrl.stop_grind("test")
