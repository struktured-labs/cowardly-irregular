extends GutTest

## The magic counter only read the snapshot primary job, so a Fighter with
## Mage secondary (white school: Cleric secondary) got "(No one can learn
## this!)" even though that secondary is a valid learner. Eligibility is
## primary OR secondary. A live Combatant in the tree wins; otherwise the
## snapshot's job + secondary_job_id. _member_knows still disables a spell
## the character already has.

const SHOP_PATH := "res://src/exploration/ShopScene.gd"
const FIRA := {"name": "Ignis Maior", "magic_school": "black", "cost": 1200}
const FIRE := {"name": "Ignis", "magic_school": "black", "cost": 300}
const CURA := {"name": "Sanatio Maior", "magic_school": "white", "cost": 800}

const _STUB_GAMELOOP_SCRIPT := """
extends Node
var party: Array = []
"""

var _saved_party: Array = []
var _stub: Node = null


func before_each() -> void:
	_saved_party = GameState.player_party.duplicate(true)
	_stub = null


func after_each() -> void:
	if _stub != null and is_instance_valid(_stub):
		_stub.free()
		_stub = null
	GameState.player_party.clear()
	for entry in _saved_party:
		GameState.player_party.append(entry)


func _set_party(members: Array) -> void:
	GameState.player_party.clear()
	for member in members:
		GameState.player_party.append(member)


func _shop():
	var shop = load(SHOP_PATH).new()
	add_child_autofree(shop)
	return shop


func _attach_live(party: Array) -> void:
	var existing := get_tree().root.get_node_or_null("GameLoop")
	if existing != null:
		var path := ""
		if existing.get_script() != null:
			path = str(existing.get_script().resource_path)
		if path == "":
			existing.free()
	var stub_script := GDScript.new()
	stub_script.source_code = _STUB_GAMELOOP_SCRIPT
	stub_script.reload()
	var stub := Node.new()
	stub.set_script(stub_script)
	stub.name = "GameLoop"
	stub.party = party
	get_tree().root.add_child(stub)
	_stub = stub


func _fighter_with(secondary_id: String) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = "Bram"
	c.job = JobSystem.get_job("fighter").duplicate(true)
	c.job_level = 1
	c.learned_abilities.clear()
	c.secondary_job_id = secondary_id
	if secondary_id != "":
		c.secondary_job = JobSystem.get_job(secondary_id).duplicate(true)
	return c


func _open(shop, spell_id: String, spell: Dictionary) -> void:
	shop._open_character_select(spell_id, spell)


func _row(shop, id: String) -> Dictionary:
	assert_not_null(shop.current_menu, "character select must open a menu")
	if shop.current_menu == null:
		return {}
	for item in shop.current_menu.menu_items:
		if str(item.get("id", "")) == id:
			return item
	return {}


func test_snapshot_secondary_mage_can_learn_black_magic() -> void:
	_set_party([
		{"name": "Rook", "job": "rogue", "secondary_job_id": "", "learned_abilities": []},
		{"name": "Bram", "job": "fighter", "secondary_job_id": "mage", "learned_abilities": []},
		{"name": "Mira", "job": "mage", "secondary_job_id": "", "learned_abilities": ["fira"]},
		{"name": "Wynn", "job": "mage", "secondary_job_id": "", "learned_abilities": []},
	])
	var shop = _shop()
	_open(shop, "fira", FIRA)
	assert_true(_row(shop, "0").is_empty(), "a Rogue with no caster secondary is not offered black magic")
	var bram: Dictionary = _row(shop, "1")
	assert_eq(bram.get("label", ""), "Bram",
		"a Fighter with Mage secondary must be offered the spell, at his own party index")
	assert_false(bram.get("disabled", false), "an unlearned spell stays buyable")
	var mira: Dictionary = _row(shop, "2")
	assert_eq(mira.get("label", ""), "Mira - Already known",
		"_member_knows still disables a primary Mage who already learned the spell")
	assert_true(mira.get("disabled", false), "the already-known row is not selectable")
	var wynn: Dictionary = _row(shop, "3")
	assert_eq(wynn.get("label", ""), "Wynn", "a primary Mage is still offered a spell she does not know")
	assert_false(wynn.get("disabled", false))
	assert_true(_row(shop, "none").is_empty(), "a real learner must replace the '(No one can learn this!)' row")


func test_snapshot_secondary_cleric_can_learn_white_magic() -> void:
	_set_party([
		{"name": "Bram", "job": "fighter", "secondary_job_id": "cleric", "learned_abilities": []},
		{"name": "Ada", "job": "bard", "secondary_job_id": "cleric", "learned_abilities": ["cura"]},
		{"name": "Nyx", "job": "fighter", "secondary_job_id": "mage", "learned_abilities": []},
	])
	var shop = _shop()
	_open(shop, "cura", CURA)
	var bram: Dictionary = _row(shop, "0")
	assert_eq(bram.get("label", ""), "Bram", "a Fighter with Cleric secondary must be offered white magic")
	assert_false(bram.get("disabled", false))
	var ada: Dictionary = _row(shop, "1")
	assert_eq(ada.get("label", ""), "Ada - Already known",
		"a secondary Cleric who already learned the spell is listed and disabled")
	assert_true(ada.get("disabled", false))
	assert_true(_row(shop, "2").is_empty(), "Mage secondary does not make a character a white-magic learner")


func test_unrelated_secondary_still_has_no_learner() -> void:
	_set_party([
		{"name": "Bram", "job": "fighter", "secondary_job_id": "rogue", "learned_abilities": []},
	])
	var shop = _shop()
	_open(shop, "fira", FIRA)
	var none: Dictionary = _row(shop, "none")
	assert_eq(none.get("label", ""), "(No one can learn this!)",
		"only mage/cleric secondaries qualify — Rogue secondary still cannot buy black magic")
	assert_true(none.get("disabled", false))


func test_live_secondary_overrides_a_snapshot_that_omits_it() -> void:
	var bram := _fighter_with("mage")
	_set_party([
		{"name": "Bram", "job": "fighter", "learned_abilities": []},
	])
	_attach_live([bram])
	var shop = _shop()
	_open(shop, "fira", FIRA)
	var row: Dictionary = _row(shop, "0")
	assert_eq(row.get("label", ""), "Bram",
		"live Mage secondary is eligible even when the snapshot only stored the Fighter primary")
	assert_false(row.get("disabled", false), "fira is outside the level-1 Mage kit, so the row stays buyable")
	_open(shop, "fire", FIRE)
	var known: Dictionary = _row(shop, "0")
	assert_eq(known.get("label", ""), "Bram - Already known",
		"the secondary kit reaches _member_knows, so Ignis is not sold again")
	assert_true(known.get("disabled", false))


func test_live_secondary_id_and_job_dict_each_qualify_on_their_own() -> void:
	var by_id := _fighter_with("mage")
	by_id.secondary_job = null
	var by_dict := _fighter_with("mage")
	by_dict.secondary_job_id = ""
	_set_party([
		{"name": "Ida", "job": "fighter", "learned_abilities": []},
		{"name": "Dicta", "job": "fighter", "learned_abilities": []},
	])
	_attach_live([by_id, by_dict])
	var shop = _shop()
	_open(shop, "fira", FIRA)
	assert_eq(_row(shop, "0").get("label", ""), "Ida",
		"secondary_job_id alone makes a live Fighter a black-magic learner")
	assert_false(_row(shop, "0").get("disabled", false))
	assert_eq(_row(shop, "1").get("label", ""), "Dicta",
		"secondary_job's id alone makes a live Fighter a black-magic learner")
	assert_false(_row(shop, "1").get("disabled", false))


func test_live_non_caster_hides_a_stale_snapshot_mage() -> void:
	var bram := _fighter_with("rogue")
	_set_party([
		{"name": "Bram", "job": "mage", "secondary_job_id": "mage", "learned_abilities": []},
	])
	_attach_live([bram])
	var shop = _shop()
	_open(shop, "fira", FIRA)
	var none: Dictionary = _row(shop, "none")
	assert_eq(none.get("label", ""), "(No one can learn this!)",
		"live Fighter/Rogue wins over a stale snapshot that still says Mage")


func test_live_learned_spell_disables_when_the_snapshot_list_is_empty() -> void:
	var bram := _fighter_with("cleric")
	bram.learn_ability("cura")
	_set_party([
		{"name": "Bram", "job": "fighter", "secondary_job_id": "", "learned_abilities": []},
	])
	_attach_live([bram])
	var shop = _shop()
	_open(shop, "cura", CURA)
	var row: Dictionary = _row(shop, "0")
	assert_eq(row.get("label", ""), "Bram - Already known",
		"live learned_abilities disable the row when the snapshot learned list is empty")
	assert_true(row.get("disabled", false))


func test_schools_stay_mage_and_cleric() -> void:
	var shop = _shop()
	assert_eq(shop._get_eligible_jobs_for_school("black"), ["mage"])
	assert_eq(shop._get_eligible_jobs_for_school("white"), ["cleric"])
	assert_eq(shop._get_eligible_jobs_for_school(""), [])
