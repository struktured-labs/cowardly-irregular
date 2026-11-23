extends GutTest

## struktured 2026-11-14: "when u lose to a boss with autobattle on it should turn off automatically on the 'retry'
## option" — then "or any monster for that matter". A retry turns every PC's autobattle OFF; scripts and Continue stay.

const GameLoopScript := preload("res://src/GameLoop.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const GAMELOOP_SRC := "res://src/GameLoop.gd"
const RETRY_CALL := "_autobattle_off_for_retry()"
const FIGHT_CALL := "await _start_battle_async(_last_battle_enemies, _last_battle_is_encounter)"

var _gl = null
var _saved: Dictionary = {}


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_saved = AutobattleSystem.autobattle_enabled.duplicate()
	_gl = GameLoopScript.new()


func after_each() -> void:
	AutobattleSystem.autobattle_enabled = _saved
	AutobattleSystem._test_disable_persistence = false
	if _gl != null:
		_gl.free()
	_gl = null


func _pc(name_str: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name_str, "max_hp": 100, "max_mp": 10, "attack": 10, "defense": 5, "magic": 5, "speed": 5})
	add_child_autofree(c)
	return c


func _id(c: Combatant) -> String:
	return c.combatant_name.to_lower().replace(" ", "_")


## The function body from `func <name>(` to the next column-0 `func `, comments and docstrings stripped.
func _body(fn: String) -> String:
	var code := GdSource.code_of(GAMELOOP_SRC)
	var at := code.find("\nfunc %s(" % fn)
	if at < 0:
		return ""
	var end := code.find("\nfunc ", at + 1)
	return code.substr(at, (end if end > 0 else code.length()) - at)


func test_floor_the_retry_helper_exists() -> void:
	assert_true(_gl.has_method("_autobattle_off_for_retry"), "FLOOR: GameLoop._autobattle_off_for_retry is gone")


func test_a_retry_turns_every_pcs_autobattle_off() -> void:
	var a := _pc("Retry Fighter")
	var b := _pc("Retry Mage")
	_gl.party = [a, b] as Array[Combatant]
	AutobattleSystem.set_autobattle_enabled(_id(a), true)
	AutobattleSystem.set_autobattle_enabled(_id(b), true)
	assert_true(AutobattleSystem.is_autobattle_enabled(_id(a)), "CONTROL: autobattle starts on")
	var switched: Array = _gl._autobattle_off_for_retry()
	assert_false(AutobattleSystem.is_autobattle_enabled(_id(a)), "the retry must hand %s back to the player" % _id(a))
	assert_false(AutobattleSystem.is_autobattle_enabled(_id(b)), "the retry must hand %s back to the player" % _id(b))
	assert_eq(switched.size(), 2, "both PCs are reported switched off: %s" % str(switched))


func test_a_retry_keeps_the_scripts() -> void:
	var a := _pc("Retry Cleric")
	_gl.party = [a] as Array[Combatant]
	AutobattleSystem.set_autobattle_enabled(_id(a), true)
	var before: Dictionary = AutobattleSystem.get_character_script(_id(a)).duplicate(true)
	_gl._autobattle_off_for_retry()
	assert_eq(AutobattleSystem.get_character_script(_id(a)), before, "only the enabled flag goes; the script stays")


func test_control_nothing_on_reports_nothing() -> void:
	var a := _pc("Retry Rogue")
	_gl.party = [a] as Array[Combatant]
	AutobattleSystem.set_autobattle_enabled(_id(a), false)
	assert_eq(_gl._autobattle_off_for_retry().size(), 0, "CONTROL: a party with autobattle off is not reported switched")


func test_both_retry_arms_switch_it_off_before_the_refight() -> void:
	for fn in ["_show_game_over_screen", "_maybe_diegetic_retry"]:
		var body := _body(fn)
		assert_ne(body, "", "VOID: GameLoop.%s not found" % fn)
		var call_at := body.find(RETRY_CALL)
		var fight_at := body.find(FIGHT_CALL)
		assert_gt(fight_at, -1, "CONTROL: %s re-fights the last battle" % fn)
		assert_gt(call_at, -1, "%s must switch autobattle off on a retry" % fn)
		assert_lt(call_at, fight_at, "%s must switch it off BEFORE the re-fight starts" % fn)


func test_control_continue_leaves_autobattle_as_it_was() -> void:
	var body := _body("_show_game_over_screen")
	var cont := body.find("\n\telse:", body.find("if retry[0]:"))
	assert_gt(cont, -1, "CONTROL: the Continue arm is found")
	assert_eq(body.substr(cont).find(RETRY_CALL), -1, "Continue loads a save and must not touch autobattle")
