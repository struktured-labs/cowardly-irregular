extends GutTest

## cowir-ai 21928 / cowir-main 21929: the battle log built an item's name from its ID, so a player read "Fighter has
## no Phoenix Down left." while the item menu said "Resurgo Plume" (hi_potion: "Hi Potion" vs "Potio Maior"). The
## id-in-words is the retired Final Fantasy name, and a literal-string sweep cannot see a name BUILT from an id.
## BattleManager._item_display_name goes through ItemNameResolver (data first); the id in words only for an unknown id.

const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")

var _guard


func before_each() -> void:
	_guard = BattleStateGuard.new()
	_guard.snapshot()


func after_each() -> void:
	_guard.restore()


## Items whose menu name is NOT their id in words: the ones the old code got wrong. Derived, not hand-listed.
func _renamed() -> Array:
	var out: Array = []
	for id in ItemSystem.items:
		var shown := str(ItemSystem.get_item(id).get("name", ""))
		var built := str(id).replace("_", " ").capitalize()
		# Skip a menu name that CONTAINS its id in words ("The Returned Sword"): "never says it" can't hold there.
		if shown != "" and shown != built and not (built in shown):
			out.append(str(id))
	return out


func test_a_renamed_item_reads_as_its_menu_name_in_the_log() -> void:
	var ids := _renamed()
	assert_gte(ids.size(), 10, "CONTROL: renamed items were found (%d)" % ids.size())
	assert_true("phoenix_down" in ids and "hi_potion" in ids, "CONTROL: the two the report named are in the corpus")
	var lines: Array = []
	var grab := func(msg: String) -> void: lines.append(msg)
	BattleManager.battle_log_message.connect(grab)
	var user := Combatant.new()
	user.combatant_name = "Fighter"
	add_child_autofree(user)
	for id in ids:
		lines.clear()
		BattleManager._execute_item(user, id, [])
		var menu := str(ItemSystem.get_item(id).get("name", ""))
		var built := id.replace("_", " ").capitalize()
		var said := " | ".join(PackedStringArray(lines))
		assert_string_contains(said, menu, "%s: the log names it as the menu does" % id)
		assert_false(built in said, "%s: the log never says the id-built '%s'" % [id, built])
	BattleManager.battle_log_message.disconnect(grab)


func test_an_unknown_item_still_has_a_readable_name() -> void:
	assert_eq(BattleManager._item_display_name("zz_no_such_item"), "Zz No Such Item", "an id ItemSystem doesn't know keeps the id in words")


## controller 21937 / sprites 21938: the same defect for ABILITIES, in the corrupted-cast / negate / mimic / adapt
## lines ("Cure comes out as Raise" where the menu says Sanatio / Anima Reddita). Derived from abilities.json.
func test_an_ability_reads_as_its_own_name_not_its_id() -> void:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var table: Dictionary = raw.get("abilities", raw) if raw is Dictionary else {}
	var renamed: Array = []
	for id in table:
		var shown := str((table[id] as Dictionary).get("name", "")) if table[id] is Dictionary else ""
		var built := str(id).replace("_", " ").capitalize()
		if shown != "" and shown != built and not (built in shown):
			renamed.append(str(id))
	assert_gte(renamed.size(), 10, "CONTROL: renamed abilities were found (%d)" % renamed.size())
	assert_true("cure" in renamed and "raise" in renamed, "CONTROL: cure and raise, the report's pair, are in the corpus")
	for id in renamed:
		var name := BattleManager._ability_display_name(id)
		assert_eq(name, str(JobSystem.get_ability(id).get("name", "")), "%s reads as its own name" % id)
		assert_ne(name, str(id).replace("_", " ").capitalize(), "%s never reads as its id in words" % id)
	assert_eq(BattleManager._ability_display_name("zz_no_such_spell"), "Zz No Such Spell", "an unknown id keeps its words")


## Every battle-log line that names an ability or item goes through a helper, not .capitalize() on an id.
func test_no_log_line_builds_a_name_from_an_id() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_gt(src.length(), 10000, "CONTROL: read the real file")
	var rx := RegEx.new()
	rx.compile("(?:item_id|ability_id|_last_ability_cast_id|swapped)\\.capitalize\\(\\)|item_id\\.replace\\(\"_\", \" \"\\)\\.capitalize\\(\\)")
	var hits: Array = []
	for line in src.split("\n"):
		if "battle_log_message.emit" in line or "_display: String" in line:
			if rx.search(line) != null:
				hits.append(line.strip_edges().left(110))
	assert_eq(hits, [], "a log line built a name from an id")
