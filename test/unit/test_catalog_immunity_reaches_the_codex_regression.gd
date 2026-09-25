extends GutTest

## Null Entity authors immunities=["physical"]. A swing deals 0 and the log says
## IMMUNE. The bestiary and the scanned enemy panel never say so.
##
## Spawn copies weaknesses and resistances onto the combatant and leaves
## elemental_immunities empty. The panel only reads that empty array, and the
## bestiary entry never carries the catalog field. After the fight the codex
## says "Resist: Physical", which is half damage, while the fight was zero.
## Abstract overworld puts this monster in a pool a player actually draws.


const UIM := preload("res://src/battle/BattleUIManager.gd")

const _KEYS: Array[String] = [
	"seen_monsters", "defeated_monsters", "defeated_counts", "seen_monsters_last_location",
]

var _snap: Dictionary = {}


func before_each() -> void:
	_snap = {}
	for key in _KEYS:
		var cur: Variant = GameState.game_constants.get(key, {})
		_snap[key] = (cur as Dictionary).duplicate(true) if cur is Dictionary else {}
		if not GameState.game_constants.has(key) or not (GameState.game_constants[key] is Dictionary):
			GameState.game_constants[key] = {}
		(GameState.game_constants[key] as Dictionary).erase("null_entity")
		(GameState.game_constants[key] as Dictionary).erase("slime")


func after_each() -> void:
	for key in _snap:
		GameState.game_constants[key] = _snap[key]


func _null_entity(revealed: bool) -> Combatant:
	# The shape spawn_encounter_enemies actually leaves: weaknesses and
	# resistances copied, immunities never written onto the combatant.
	var enemy := Combatant.new()
	add_child_autofree(enemy)
	enemy.combatant_name = "Null Entity"
	enemy.set_meta("monster_type", "null_entity")
	if revealed:
		enemy.set_meta("intel_revealed", true)
	enemy.elemental_weaknesses = ["holy"] as Array[String]
	enemy.elemental_resistances = ["physical", "dark"] as Array[String]
	return enemy


func _hint(enemy: Combatant) -> String:
	return UIM.new(null)._enemy_intel_hint(enemy)


func _null_entry() -> Dictionary:
	for entry in BestiarySystem.get_seen_entries_sorted():
		if str(entry.get("id", "")) == "null_entity":
			return entry
	return {}


func test_a_defeated_null_entity_row_carries_the_catalog_immunity() -> void:
	BestiarySystem.mark_defeated("null_entity")
	var entry := _null_entry()
	assert_false(entry.is_empty(), "defeating a Null Entity must open its bestiary row")
	assert_true("physical" in entry.get("immunities", []),
		"the row must carry immunities=[physical] — combat already deals 0 from that field, and the panel was printing only Resist")


func test_the_codex_prints_immune_physical_after_the_kill() -> void:
	BestiarySystem.mark_defeated("null_entity")
	var entry := _null_entry()
	assert_false(entry.is_empty(), "CONTROL: the defeated row must exist before the panel is asked to render it")
	var menu := BestiaryMenu.new()
	add_child_autofree(menu)
	await wait_frames(3)
	menu._entries = [entry]
	menu._selected = 0
	menu._refresh_detail()
	await wait_frames(2)
	# .get so a missing label fails this assert. A typed read of a member that is
	# gone is a parse error, and the file would never run.
	var immune = menu.get("_detail_immune")
	assert_not_null(immune, "the detail panel must have an immunity line")
	if immune == null:
		return
	assert_string_contains(str(immune.text), "Immune: Physical",
		"after the kill the codex must say the Null Entity is immune to physical — got '%s'" % immune.text)
	assert_string_contains(str(menu._detail_resist.text), "Physical",
		"CONTROL: the authored resistance stays; immunity is a second fact, not a rename of resist")


func test_a_scan_shows_the_immunity_the_spawner_never_copied() -> void:
	var hint := _hint(_null_entity(true))
	assert_string_contains(hint, "Immune: Physical",
		"Scan promises immunities, and this foe's physical immunity is the whole fight — got '%s'" % hint)
	assert_string_contains(hint, "Weak: Holy", "CONTROL: the scan still names the authored weakness")
	assert_string_contains(hint, "Resist:", "CONTROL: resistances still render beside the immunity")


func test_a_return_visit_shows_the_immunity_without_another_scan() -> void:
	BestiarySystem.mark_defeated("null_entity")
	var hint := _hint(_null_entity(false))
	assert_string_contains(hint, "Immune: Physical",
		"a monster you have already beaten must show its catalog immunity on the next fight — got '%s'" % hint)


func test_an_unearned_null_entity_does_not_leak_the_immunity() -> void:
	var hint := _hint(_null_entity(false))
	assert_eq(hint, "",
		"seeing the sprite is not enough — immunity stays hidden until a scan or a kill, got '%s'" % hint)


func test_a_monster_with_no_authored_immunity_does_not_invent_one() -> void:
	BestiarySystem.mark_defeated("slime")
	var slime := Combatant.new()
	add_child_autofree(slime)
	slime.set_meta("monster_type", "slime")
	slime.elemental_weaknesses = ["fire"] as Array[String]
	var hint := _hint(slime)
	assert_string_contains(hint, "Weak: Fire", "CONTROL: the slime's weakness still shows")
	assert_false(hint.contains("Immune:"),
		"a catalog with no immunities must not grow an Immune line — got '%s'" % hint)
