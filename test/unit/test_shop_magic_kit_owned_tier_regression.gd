extends GutTest

## Magic buy rows counted "[N learned]" and green upgrade marks from the snapshot
## learned_abilities list only. Character select already asked the live Combatant
## via _member_knows, so a Mage whose kit includes Ignis saw "Already known" on
## the learner row while the shelf still painted Ignis as unowned and as an upgrade.
##
## A character who knows a kit spell through knows_ability, with an empty snapshot
## learned list, must count toward owned and must set that family's best-known tier
## so a same-tier shelf spell is not an upgrade.

const SHOP_PATH := "res://src/exploration/ShopScene.gd"
const ShopScript = preload(SHOP_PATH)

const _STUB_GAMELOOP_SCRIPT := """
extends Node
var party: Array = []
"""

var _prior_party: Array = []
var _stub: Node = null


func before_each() -> void:
	_prior_party = GameState.player_party.duplicate(true)


func after_each() -> void:
	if _stub != null and is_instance_valid(_stub):
		_stub.free()
		_stub = null
	_restore_party(_prior_party)


func _restore_party(prior: Array) -> void:
	var typed: Array[Dictionary] = []
	for entry in prior:
		if entry is Dictionary:
			typed.append((entry as Dictionary).duplicate(true))
	GameState.player_party = typed


func _make_stub_gameloop(live_party: Array) -> Node:
	var stub_script := GDScript.new()
	stub_script.source_code = _STUB_GAMELOOP_SCRIPT
	stub_script.reload()
	var stub: Node = Node.new()
	stub.set_script(stub_script)
	stub.name = "GameLoop"
	stub.party = live_party
	get_tree().root.add_child(stub)
	_stub = stub
	return stub


func _combatant(job: Dictionary) -> Object:
	var live: Object = (load("res://src/battle/Combatant.gd") as GDScript).new()
	add_child_autofree(live)
	live.learned_abilities.clear()
	live.purchased_abilities.clear()
	live.job_level = 1
	live.job = job
	return live


func _magic_shop() -> ShopScene:
	var shop := ShopScript.new()
	add_child_autofree(shop)
	shop.shop_type = ShopScript.ShopType.BLACK_MAGIC
	return shop


func _row(shop: ShopScene, item_id: String) -> Dictionary:
	for row in shop.current_menu.menu_items:
		if str(row.get("id", "")) == item_id:
			return row as Dictionary
	return {}


func test_kit_spell_counts_as_owned_and_is_not_an_upgrade() -> void:
	var fire: Dictionary = JobSystem.get_ability("fire")
	var fire_tier := int(fire.get("tier", 0))
	var snap: Array[Dictionary] = [
		{"name": "Vesper", "job": "mage", "learned_abilities": []},
		{"name": "Bram", "job": "fighter", "learned_abilities": []},
	]
	GameState.player_party = snap
	var mage := _combatant({"id": "mage", "abilities": ["fire"]})
	var fighter := _combatant({"id": "fighter", "abilities": ["attack"]})
	_make_stub_gameloop([mage, fighter])
	var shop := _magic_shop()

	var knows_live: bool = mage.knows_ability("fire")
	var snapshot_empty: bool = snap[0]["learned_abilities"].is_empty()
	var owned_fire: int = shop._get_owned_count("fire")
	var owned_fira: int = shop._get_owned_count("fira")
	var best: int = shop._best_known_tier(str(fire.get("family", "")))
	var same_tier: bool = shop._is_spell_upgrade({"family": fire.get("family", ""), "tier": fire_tier})
	var next_tier: bool = shop._is_spell_upgrade({"family": fire.get("family", ""), "tier": fire_tier + 1})

	shop.shop_inventory.clear()
	shop.shop_inventory.append("fire")
	shop.shop_inventory.append("fira")
	shop._open_buy_menu()
	var fire_row: Dictionary = _row(shop, "fire")
	var fira_row: Dictionary = _row(shop, "fira")
	var fire_label := str(fire_row.get("label", ""))
	var fira_label := str(fira_row.get("label", ""))

	assert_true(knows_live, "fixture: the live mage knows Ignis from his kit")
	assert_true(snapshot_empty, "fixture: the snapshot learned list is empty — the pre-fix shelf only read this")
	assert_gt(fire_tier, 0, "fixture: Ignis has a family tier")
	assert_eq(owned_fire, 1, "the kit spell counts as owned on the buy list")
	assert_eq(owned_fira, 0, "a higher spell nobody has is still unowned")
	assert_eq(best, fire_tier, "best-known tier for the family is the kit spell's tier")
	assert_false(same_tier, "a same-tier shelf spell is not an upgrade when the kit already has that rung")
	assert_true(next_tier, "the next tier in the family is still an upgrade")
	assert_true("[1 learned]" in fire_label, "the buy row says one party member already has Ignis. Got: %s" % fire_label)
	assert_false(fire_label.begins_with("▲"), "an owned kit spell is not marked as an upgrade. Got: %s" % fire_label)
	assert_eq(fire_row.get("text_color"), ShopScript.BUY_ROW_OWNED_COLOR, "the owned tint wins over the upgrade green")
	assert_true(fira_label.begins_with("▲"), "the next rung on the shelf is still highlighted as an upgrade. Got: %s" % fira_label)
	assert_eq(fira_row.get("text_color"), ShopScript.BUY_ROW_UPGRADE_COLOR, "fira stays upgrade-green")


func test_snapshot_learned_still_sets_owned_and_tier_without_a_live_party() -> void:
	var fira: Dictionary = JobSystem.get_ability("fira")
	var fira_tier := int(fira.get("tier", 0))
	var snap: Array[Dictionary] = [
		{"name": "Vesper", "job": "mage", "learned_abilities": ["fira"]},
	]
	GameState.player_party = snap
	var shop := _magic_shop()

	assert_null(get_tree().root.get_node_or_null("GameLoop"), "this arm is the no-live-party fallback")
	assert_eq(shop._get_owned_count("fira"), 1, "a spell on the snapshot learned list still counts as owned")
	assert_eq(shop._get_owned_count("fire"), 0, "a spell absent from the snapshot stays unowned when nobody is live")
	assert_eq(shop._best_known_tier("fire"), fira_tier, "best-known tier still reads the snapshot learned list")
	assert_false(shop._is_spell_upgrade({"family": "fire", "tier": fira_tier}), "matching the snapshot tier is not an upgrade")
	assert_true(shop._is_spell_upgrade({"family": "fire", "tier": fira_tier + 1}), "a higher tier than the snapshot is still an upgrade")


func test_snapshot_counts_when_the_live_member_does_not_know_the_spell() -> void:
	var snap: Array[Dictionary] = [
		{"name": "Vesper", "job": "mage", "learned_abilities": ["fira"]},
	]
	GameState.player_party = snap
	var mage := _combatant({"id": "mage", "abilities": ["fire"]})
	_make_stub_gameloop([mage])
	var shop := _magic_shop()

	assert_false(mage.knows_ability("fira"), "fixture: the live kit does not include fira")
	assert_eq(shop._get_owned_count("fira"), 1, "the snapshot learned list still counts when a live member is reachable but lacks the spell")
	assert_eq(shop._get_owned_count("fire"), 1, "the live kit still counts on the same shelf")


func test_owned_count_and_best_tier_call_member_knows() -> void:
	var src := FileAccess.get_file_as_string(SHOP_PATH)
	for fn in ["_get_owned_count", "_best_known_tier"]:
		var i := src.find("func " + fn)
		assert_gt(i, -1, fn + " must exist")
		var next_fn := src.find("\nfunc ", i + 1)
		var body := src.substr(i, next_fn - i) if next_fn > i else src.substr(i)
		assert_true("_member_knows(" in body, fn + " must use _member_knows, not the snapshot learned list alone")
