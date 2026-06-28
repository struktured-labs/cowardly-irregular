extends GutTest

## tick 315: magic shop spell purchases mirror to the LIVE Combatant
## learned_abilities so the spell survives the next
## _sync_party_to_game_state.
##
## Pre-fix _attempt_magic_purchase only appended to
## game_state.player_party[char_index]["learned_abilities"] — the
## snapshot. On the next menu open / pre-save sync,
## _sync_party_to_game_state copied LIVE Combatant.learned_abilities
## back over the snapshot, silently un-learning the just-purchased
## spell. Gold was spent; the player saw "X learned Y!" then opened
## the menu and Y was gone.
##
## Same overwrite class as tick 314's potion-purchase fix.

const SHOP_PATH := "res://src/exploration/ShopScene.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: magic purchase calls _resolve_live_party + learn_ability

func test_magic_purchase_writes_to_live_combatant() -> void:
	var src := _read(SHOP_PATH)
	var fn_idx: int = src.find("func _attempt_magic_purchase")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_resolve_live_party()"),
		"_attempt_magic_purchase must call _resolve_live_party() to reach the live party")
	assert_true(body.contains("learn_ability(pending_spell_id)"),
		"_attempt_magic_purchase must call Combatant.learn_ability so the spell survives the next sync")


# ── Stub GameLoop helper: a Node with a real `party` property ───────

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


# ── Behavioral: spell purchase shows up on live Combatant ───────────

func test_purchase_updates_live_learned_abilities() -> void:
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return

	var combatant_script: GDScript = load("res://src/battle/Combatant.gd")
	var live: Object = combatant_script.new()
	add_child_autofree(live)
	live.learned_abilities = []
	# Seed enough HP for the combatant to be considered "alive" (some
	# code paths may guard on this).
	live.max_hp = 100
	live.current_hp = 100

	# Snapshot — magic shop reads char_index against this size.
	GameState.player_party = [{"name": "Mira", "learned_abilities": []}]
	# Seed gold so spend_gold succeeds.
	GameState.party_gold = 1000

	var stub_gl: Node = _make_stub_gameloop([live])

	var script: GDScript = load(SHOP_PATH)
	var shop: Object = script.new()
	add_child_autofree(shop)
	# Drive the inputs _attempt_magic_purchase reads.
	shop.pending_spell_id = "fire"
	shop.pending_spell_data = {"cost": 100, "name": "Fire"}

	shop._attempt_magic_purchase("0")

	stub_gl.free()

	assert_true("fire" in live.learned_abilities,
		"live Combatant.learned_abilities must include the purchased spell (pre-fix: snapshot-only append, clobbered on next sync)")
	# Sanity: snapshot also updated (legacy behavior preserved).
	var snapshot_learned: Array = GameState.player_party[0].get("learned_abilities", [])
	assert_true("fire" in snapshot_learned,
		"snapshot dict must still include the spell (kept for backward compat with menu code that reads the snapshot)")
	# Sanity: gold was spent.
	assert_eq(GameState.party_gold, 900,
		"spend_gold must have applied the cost")


# ── Behavioral: empty snapshot path is a no-op ──────────────────────

func test_no_party_member_is_noop() -> void:
	assert_not_null(GameState, "GameState autoload required")
	if GameState == null:
		return

	GameState.player_party = []
	var prior_gold: int = GameState.party_gold

	var script: GDScript = load(SHOP_PATH)
	var shop: Object = script.new()
	add_child_autofree(shop)
	shop.pending_spell_id = "fire"
	shop.pending_spell_data = {"cost": 100, "name": "Fire"}

	# char_index 0 against empty array — early return, no gold spent.
	shop._attempt_magic_purchase("0")
	assert_eq(GameState.party_gold, prior_gold,
		"empty party must early-return — no gold spent, no crash")
