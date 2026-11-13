extends GutTest

## The inn's night (cutscenes' InnRestSequence) writes "HP + MP RESTORED" across the dawn sky; the innkeeper's box then
## said "HP and MP restored." again. The sky now carries the restore and who did not wake; the box keeps her line, the
## receipt and the permanent dead. Seam agreed with cowir-cutscenes for .795: the inn sets `seq.restored_lines`.

const INN_PATH := "res://src/maps/interiors/InnInterior.gd"
const CombatantRes = preload("res://src/battle/Combatant.gd")
const _STUB_GAMELOOP := "extends Node\nvar party: Array = []\n"

var _prior_gold: int = 0
var _stub: Node = null


func before_each() -> void:
	_prior_gold = GameState.party_gold


func after_each() -> void:
	GameState.party_gold = _prior_gold
	if _stub and is_instance_valid(_stub):
		_stub.free()
	_stub = null
	## A night outlives its test (it runs for seconds); left in root, the next arm's lookup found the PREVIOUS night.
	for n in get_tree().root.get_children():
		if n is InnRestSequence:
			n.free()
	InputLockManager.pop_lock(InnRestSequence.LOCK_ID)
	if SoundManager:
		SoundManager.stop_music()


func _member(name_str: String, alive: bool, permakilled: bool = false) -> Combatant:
	var c: Combatant = CombatantRes.new()
	add_child_autofree(c)
	c.combatant_name = name_str
	c.max_hp = 100
	c.current_hp = 0 if not alive else 40
	c.max_mp = 40
	c.is_alive = alive
	if permakilled:
		c.add_status("permakilled", -1)
	return c


## Rests the real inn with `party` and returns the night it started, before the night has drawn anything.
func _night_for(party: Array) -> InnRestSequence:
	var script := GDScript.new()
	script.source_code = _STUB_GAMELOOP
	script.reload()
	_stub = Node.new()
	_stub.set_script(script)
	_stub.name = "GameLoop"
	_stub.party = party
	get_tree().root.add_child(_stub)
	var inn: Node2D = load(INN_PATH).new()
	add_child_autofree(inn)
	GameState.party_gold = 500
	var before: Array = get_tree().root.get_children().filter(func(n): return n is InnRestSequence)
	inn._do_rest()
	for n in get_tree().root.get_children():
		if n is InnRestSequence and not before.has(n):
			return n
	return null


func test_the_night_names_who_did_not_wake() -> void:
	var seq := _night_for([_member("Bard", false, true), _member("Fighter", false), _member("Mage", true)])
	assert_not_null(seq, "CONTROL: a paid rest starts the night")
	if seq == null:
		return
	assert_eq(Array(seq.restored_lines), ["HP + MP RESTORED", "BARD DID NOT WAKE"], "the sky says the restore and names the permanent dead")


func test_a_whole_party_wakes_to_one_line() -> void:
	var seq := _night_for([_member("Fighter", false), _member("Mage", true)])
	assert_not_null(seq, "CONTROL: a paid rest starts the night")
	if seq == null:
		return
	assert_eq(Array(seq.restored_lines), ["HP + MP RESTORED"], "a KO revived overnight is not named")


func test_many_dead_are_a_count_not_a_column() -> void:
	var inn_script = load(INN_PATH)
	var three: Array[String] = ["Bard", "Rogue", "Cleric"]
	assert_eq(Array(inn_script.rest_readout(three)), ["HP + MP RESTORED", "3 DID NOT WAKE"], "two rows at most, whatever the losses")


func test_every_letter_the_sky_writes_has_a_glyph() -> void:
	var inn_script = load(INN_PATH)
	var one: Array[String] = ["Bard"]
	var many: Array[String] = ["A", "B"]
	var lines: Array = Array(inn_script.rest_readout(one)) + Array(inn_script.rest_readout(many))
	var missing := []
	for line in lines:
		for ch in str(line).to_upper():
			if ch != " " and not PixelText.GLYPHS.has(ch):
				missing.append(ch)
	assert_gt(lines.size(), 2, "CONTROL: the lines were built")
	assert_eq(missing, [], "the pixel face draws '?' for a letter it lacks")


func test_the_morning_box_does_not_repeat_the_sky() -> void:
	var inn_script = load(INN_PATH)
	var none: Array[String] = []
	var text: String = inn_script.morning_text("Dawn already.", none)
	assert_true(text.begins_with("Dawn already."), "her line leads")
	assert_true(text.contains("(-%d G)" % int(inn_script.REST_COST)), "the receipt stays")
	assert_false(text.to_lower().contains("restored"), "the restore is the sky's to say")
	var dead: Array[String] = ["Bard"]
	assert_true(inn_script.morning_text("Dawn already.", dead).contains("Bard cannot be roused"), "the permanent dead are still named in words")
