extends GutTest

## tick 314: shop purchases / sales write to the LIVE Combatant
## inventory in addition to the snapshot dict, so changes survive
## the next _sync_party_to_game_state.
##
## Pre-fix shop mutated only game_state.player_party (the serialized
## snapshot dict). On the next menu open / pre-save sync,
## _sync_party_to_game_state copied LIVE Combatant.inventory back over
## the snapshot, OVERWRITING every shop change. Net effects:
##
##   - Purchases: gold spent, item silently lost on next sync.
##   - Sales: gold credited, item kept after next sync — a free-money
##     exploit triggered every successful sell.
##
## ShopScene now resolves the live party via GameLoop and mirrors
## the dict mutation to live Combatant.add_item / remove_item.

const SHOP_PATH := "res://src/exploration/ShopScene.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: resolver exists ─────────────────────────────────────

func test_live_party_resolver_exists() -> void:
	var src := _read(SHOP_PATH)
	assert_true(src.contains("func _resolve_live_party()"),
		"_resolve_live_party helper must exist as the canonical way to reach live Combatants from the shop")
	assert_true(src.contains("get_node_or_null(\"GameLoop\")"),
		"resolver must reach GameLoop via the scene tree root (autoload-style lookup)")


# ── Source pin: add path mirrors to live ────────────────────────────

func test_add_item_writes_to_live_combatant() -> void:
	var src := _read(SHOP_PATH)
	var fn_idx: int = src.find("func _add_item_to_inventory")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_resolve_live_party()"),
		"_add_item_to_inventory must call _resolve_live_party() to reach the live party")
	assert_true(body.contains("add_item(item_id"),
		"_add_item_to_inventory must call Combatant.add_item on the live leader so the next sync sees the purchase")


# ── Source pin: remove path mirrors to live ─────────────────────────

func test_remove_item_writes_to_live_combatant() -> void:
	var src := _read(SHOP_PATH)
	var fn_idx: int = src.find("func _remove_item_from_inventory")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_resolve_live_party()"),
		"_remove_item_from_inventory must call _resolve_live_party()")
	assert_true(body.contains("remove_item(item_id"),
		"_remove_item_from_inventory must call Combatant.remove_item so sells survive the next sync (pre-fix: free-money exploit)")


# ── Stub GameLoop helper: a Node with a real `party` property ───────
# Node.set("party", ...) creates metadata, not a property — `"party" in
# node` returns false. We need a real script-backed Node so the shop's
# `"party" in gl` check passes.

const _STUB_GAMELOOP_SCRIPT := """
extends Node
var party: Array = []
var equipment_pool: Dictionary = {}
"""


func _make_stub_gameloop(live_party: Array) -> Node:
	var stub_script := GDScript.new()
	stub_script.source_code = _STUB_GAMELOOP_SCRIPT
	stub_script.reload()
	var stub: Node = Node.new()
	stub.set_script(stub_script)
	stub.name = "GameLoop"
	stub.party = live_party
	get_tree().root.add_child(stub)
	return stub


# ── Behavioral: purchase mirrors to live Combatant ──────────────────

func test_purchase_updates_live_combatant() -> void:
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return

	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var live: Object = combatant_script.new()
	add_child_autofree(live)
	live.inventory = {}

	GameState.player_party = [{"name": "Test", "inventory": {}}]

	var stub_gl: Node = _make_stub_gameloop([live])

	var script: GDScript = load(SHOP_PATH)
	var shop: Object = script.new()
	add_child_autofree(shop)
	shop.shop_type = 0  # ShopType.ITEM

	var ok: bool = shop._add_item_to_inventory("potion")
	# Free immediately, not deferred — otherwise a stale "GameLoop" node
	# from this test leaks into the next test's _resolve_live_party
	# lookup (gets the OLD stub, not the new one).
	stub_gl.free()

	assert_true(ok, "purchase must succeed when a recipient is available")
	assert_eq(live.inventory.get("potion", 0), 1,
		"live Combatant.inventory must reflect the purchase (pre-fix: only snapshot mutated, overwritten on next sync)")


# ── Behavioral: sell mirrors to live Combatant ──────────────────────

func test_sell_updates_live_combatant() -> void:
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return

	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var live: Object = combatant_script.new()
	add_child_autofree(live)
	live.inventory = {"potion": 1}

	GameState.player_party = [{"name": "Test", "inventory": {"potion": 1}}]

	var stub_gl: Node = _make_stub_gameloop([live])

	var script: GDScript = load(SHOP_PATH)
	var shop: Object = script.new()
	add_child_autofree(shop)

	var ok: bool = shop._remove_item_from_inventory("potion")
	# Free immediately, not deferred — otherwise a stale "GameLoop" node
	# from this test leaks into the next test's _resolve_live_party
	# lookup (gets the OLD stub, not the new one).
	stub_gl.free()

	assert_true(ok, "sell must succeed when the item is present in the snapshot")
	assert_eq(live.inventory.get("potion", 0), 0,
		"live Combatant.inventory must reflect the sale (pre-fix: live unchanged, sync re-introduced item — free-money exploit)")
