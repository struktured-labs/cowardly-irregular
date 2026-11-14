extends GutTest

## A COWIR1: code is grammar-checked but its ability ids are not, so a stranger's id reaches the grind's
## "unknown ability '<id>'" refusal and from there the console's BBCode log. The console must show it as text.

const RESOLVER := preload("res://src/autogrind/HeadlessBattleResolver.gd")
const HOSTILE := "[color=#00000000]hidden[/color]"

var _ui
var _res


func before_each() -> void:
	## Drives a UI node that reaches AutogrindSystem's savers; the one-hop ratchet cannot see it
	AutogrindSystem._test_disable_persistence = true
	_ui = preload("res://src/ui/autogrind/AutogrindUI.gd").new()
	add_child_autofree(_ui)
	_ui._battle_log = RichTextLabel.new()
	_ui._battle_log.bbcode_enabled = true
	add_child_autofree(_ui._battle_log)
	_ui._ludicrous_speed_enabled = false
	_res = RESOLVER.new()


func after_each() -> void:
	AutogrindSystem._test_disable_persistence = false
	if _res != null:
		_res.free()
	_res = null


func _caster() -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": "Mage", "max_hp": 100, "max_mp": 50, "attack": 10, "defense": 5, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


## The grind's own refusal for an id nobody validated, as it writes it.
func _refusal_for(ability_id: String) -> Array:
	_res._battle_log.clear()
	_res._resolve_ability(_caster(), ability_id, [])
	return _res._battle_log.duplicate()


func test_control_a_hostile_id_passes_the_share_grammar() -> void:
	var rule := {"conditions": [], "actions": [{"type": "ability", "id": HOSTILE}]}
	assert_eq(AutobattleSystem.validate_rule(rule), [] as Array[String], "CONTROL: the route is open, an unknown ability id passes the share code's grammar")


func test_the_refusal_quotes_the_id_verbatim() -> void:
	var lines := _refusal_for(HOSTILE)
	assert_eq(lines.size(), 1, "CONTROL: one refusal line for an unknown ability")
	assert_true(str(lines[0]).contains(HOSTILE), "CONTROL: the grind quotes the id as given: %s" % str(lines))


func test_the_console_shows_a_pasted_id_as_text() -> void:
	var lines := _refusal_for(HOSTILE)
	_ui.append_resolver_log(lines)
	var shown: String = _ui._battle_log.get_parsed_text()
	assert_true(shown.contains(HOSTILE), "the console must show the pasted id literally, brackets and all; it shows: %s" % shown)


func test_control_the_line_keeps_its_own_colour() -> void:
	_ui.append_resolver_log(["Mage attacks Slime for 40"])
	var shown: String = _ui._battle_log.get_parsed_text()
	assert_true(shown.contains("Mage attacks Slime for 40"), "CONTROL: plain narration still reads as written")
	assert_false(shown.contains("[color"), "the console's own colour wrapper is markup, not text: %s" % shown)
