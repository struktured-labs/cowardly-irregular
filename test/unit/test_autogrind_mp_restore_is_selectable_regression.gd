extends GutTest

## The other half of "who selects it, and can they?" applied to the headless mp_restore arm.
## pray and channel are the game's only two mp_restore abilities, and both are per-job FREE MOVES.
##
## Two different answers, which is why the question had to be asked twice:
##   · The shipped preset catalog DOES cast them (5 rules across templates 3/4/6/7/8), so the
##     resolver arm is reachable for any player who applies a preset — test one drives that.
##   · The grid editor CANNOT offer them. Its sub-picker enumerates get_known_abilities(), which
##     walks kit + level unlocks + learned + purchased + secondary kit and omits free_move, while
##     knows_ability() includes it. The docstring between the two claims they can never disagree.
##     A rule the catalog ships is one the player cannot author by hand — test two pins that.

const GridEditorScript = preload("res://src/ui/autobattle/AutobattleGridEditor.gd")

var _abs: Node = null
var _fixture_ids: Array[String] = []


func before_each() -> void:
	_abs = get_node_or_null("/root/AutobattleSystem")
	if _abs:
		_abs._test_disable_persistence = true
	_fixture_ids.clear()


func after_each() -> void:
	if _abs:
		for cid in _fixture_ids:
			_abs.character_profiles.erase(cid)


func _cleric(cname: String, mp_now: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname, "max_hp": 500, "max_mp": 40,
		"attack": 12, "defense": 50, "magic": 20, "speed": 10
	})
	c.job = JobSystem.get_job("cleric")
	c.job_level = 1
	add_child_autofree(c)
	## AFTER tree entry: Combatant._ready refills current_mp to max_mp, so a pool set before
	## add_child silently reads 100% and the guard condition is then false for the right reason,
	## proving nothing. The precondition below is what caught it.
	c.current_mp = mp_now
	return c


func _punching_bag() -> Combatant:
	var e := Combatant.new()
	e.initialize({
		"name": "Mpprobe Dummy", "max_hp": 999999, "max_mp": 0,
		"attack": 1, "defense": 999, "magic": 1, "speed": 1
	})
	add_child_autofree(e)
	return e


func _shipped_rule_casting(ability_id: String) -> Dictionary:
	var f := FileAccess.open("res://data/autobattle_rule_templates.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return {}
	for tmpl in (parsed as Dictionary).get("templates", []):
		if not (tmpl is Dictionary):
			continue
		for rule in (tmpl as Dictionary).get("rules", []):
			if not (rule is Dictionary):
				continue
			for act in (rule as Dictionary).get("actions", []):
				if act is Dictionary and str(act.get("type", "")) == "ability" \
						and str(act.get("id", "")) == ability_id:
					return rule
	return {}


func test_the_shipped_pray_preset_actually_restores_mp_in_a_grind() -> void:
	## Catalog templates 3/4: {mp_percent < 15} -> ability pray, target self. pray authors
	## mp_cost 0 and mp_amount 6, so the arithmetic is exact: 1 MP of 40 is 2.5% and fires; 7 of
	## 40 is 17.5% and does not. Deterministic — nothing here rides on a damage roll.
	var rule := _shipped_rule_casting("pray")
	assert_false(rule.is_empty(),
		"precondition: the shipped catalog must still contain a pray rule to measure")

	var cleric := _cleric("Mpprobe Cleric", 1)
	assert_true(cleric.knows_ability("pray"),
		"precondition: the Cleric fixture must know the free move being selected")
	assert_lt(cleric.get_mp_percentage(), 15.0,
		"precondition: the fixture must actually start below the rule's threshold, or the rule is false for the right reason and proves nothing")
	var cid: String = cleric.combatant_name.to_lower().replace(" ", "_")
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, {"rules": [rule]})

	var resolver := HeadlessBattleResolver.new()
	var result: Dictionary = resolver.resolve_battle([cleric], [_punching_bag()])
	assert_true(is_instance_valid(cleric), "precondition: the fixture survived the battle to be read")
	assert_gt(result.get("log", []).size(), 0, "precondition: the battle produced a log")

	assert_eq(cleric.current_mp, 7,
		"pray must restore its authored 6 MP once and then stop firing — 1 MP means the mp_restore arm is never selected in a grind, 40 means the guard condition never turned it off")


func test_the_grid_editor_can_author_what_the_catalog_ships() -> void:
	## The picker's own list. `cure` is the control: a Cleric kit ability that must be present, so
	## an empty or wrongly-built list cannot pass this by returning nothing.
	var editor = GridEditorScript.new()
	add_child_autofree(editor)
	var cleric := _cleric("Pickerprobe Cleric", 40)
	editor.combatant = cleric

	var offered: Array = editor._get_character_abilities()
	var ids: Array = []
	for entry in offered:
		ids.append(str((entry as Dictionary).get("id", "")))

	assert_true(ids.has("cure"),
		"control: a Cleric's kit ability must be offered — if this fails the list is broken, not the free move")
	assert_true(cleric.knows_ability("pray"),
		"control: knows_ability already says the Cleric can cast pray")
	assert_true(ids.has("pray"),
		"the editor must offer every ability the character can cast; pray is a free move, and a rule has no free-move row — the ability action is the only way to script it, and the catalog already ships rules that do")
