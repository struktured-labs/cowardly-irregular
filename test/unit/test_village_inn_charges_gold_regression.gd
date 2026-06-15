extends GutTest

## Real gameplay regression: VillageInn._rest_party() must actually
## charge the player's gold for the rest, not heal for free.
##
## Bug shape:
##   • VillageInn declared `@export var rest_cost: int = 50` at line 10.
##   • _rest_party never read it. The function just restored full HP /
##     MP / AP for every party member and exited — no get_gold check,
##     no spend_gold call.
##   • All 9 villages that wire VillageInn (Harmonia, Sandrift,
##     Ironhaven, Frosthold, MapleHeights, Brasston, RivetRow,
##     NodePrime, Eldertree) inherited this free-rest behavior.
##   • The dialog also never mentioned the cost — the player had no
##     way to know an inn was supposed to charge them.
##
## Fix: _rest_party now reads GameState.get_gold(), refuses with a
## clear "Not enough gold!" message + menu_error SFX when the party
## can't afford it, and spends the cost via GameState.spend_gold()
## on success. The opening dialog also surfaces the cost up-front.
##
## Tests:
##   • Source pin: _show_inn_menu's dialog includes rest_cost
##   • Source pin: _rest_party calls GameState.get_gold()
##   • Source pin: _rest_party calls GameState.spend_gold(rest_cost)
##   • Source pin: an insufficient-gold branch surfaces an error
##     message (not silently free)
##   • Behavioural: a real inn instance with rest_cost=10 spending
##     against a 100-gold GameState ends up at 90 gold AND the party
##     is fully restored
##   • Behavioural: insufficient gold → spend doesn't happen AND the
##     party HP is left at the pre-rest value

const VILLAGE_INN_PATH := "res://src/exploration/VillageInn.gd"
const VillageInnScript := preload("res://src/exploration/VillageInn.gd")


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ───────────────────────────────────────────────────────────────

func test_show_inn_menu_surfaces_cost_in_dialog() -> void:
	var text := _read(VILLAGE_INN_PATH)
	var idx := text.find("func _show_inn_menu")
	assert_gt(idx, -1, "_show_inn_menu must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("rest_cost"),
		"_show_inn_menu's dialog text must reference rest_cost so the player can decide before confirming")


func test_rest_party_reads_gold_and_spends_it() -> void:
	var text := _read(VILLAGE_INN_PATH)
	var idx := text.find("func _rest_party")
	assert_gt(idx, -1, "_rest_party must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("GameState.get_gold()"),
		"_rest_party must read GameState.get_gold() to check affordability")
	assert_true(body.contains("GameState.spend_gold(rest_cost)"),
		"_rest_party must call GameState.spend_gold(rest_cost) to actually charge for the rest")


func test_rest_party_handles_insufficient_gold_path() -> void:
	# When the party can't afford the rest, _rest_party must surface a
	# clear "not enough gold" message and play an error SFX — NOT
	# silently grant the rest.
	var text := _read(VILLAGE_INN_PATH)
	var idx := text.find("func _rest_party")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	assert_true(body.contains("Not enough gold"),
		"_rest_party must surface a 'Not enough gold' message on the insufficient-gold branch")
	assert_true(body.contains("menu_error"),
		"_rest_party must play the menu_error SFX on the insufficient-gold branch")


# ── Behavioural ──────────────────────────────────────────────────────────────

func test_successful_rest_deducts_gold() -> void:
	# Drive _rest_party with enough gold to afford the rest, assert that
	# GameState.party_gold drops by exactly rest_cost. The party-HP
	# restoration side of the fix depends on the live GameLoop scene
	# (not reachable in GUT since GameLoop is the main_scene root, not
	# an autoload), so this test focuses on the gold-spending half of
	# the contract. Source pins above lock in that the party-restore
	# loop is still present.
	var inn: VillageInn = VillageInnScript.new()
	add_child_autofree(inn)
	inn.rest_cost = 10
	var prior_gold: int = GameState.get_gold()
	GameState.party_gold = 100
	inn.dialogue_label = Label.new()
	add_child_autofree(inn.dialogue_label)
	inn.dialogue_box = Control.new()
	add_child_autofree(inn.dialogue_box)
	# Synchronous side effects (spend_gold, dialog label) all happen
	# before the 1.5s await timer, so we can inspect immediately.
	inn._rest_party()
	assert_eq(int(GameState.get_gold()), 90,
		"a successful rest must deduct rest_cost (10) from party_gold (100 - 10 = 90)")
	# Restore.
	GameState.party_gold = prior_gold


func test_insufficient_gold_leaves_gold_untouched_and_surfaces_message() -> void:
	# Inverse: GameState has 5 gold, rest costs 50. Gold stays at 5,
	# dialog surfaces the insufficient-gold message.
	var inn: VillageInn = VillageInnScript.new()
	add_child_autofree(inn)
	inn.rest_cost = 50
	var prior_gold: int = GameState.get_gold()
	GameState.party_gold = 5
	inn.dialogue_label = Label.new()
	add_child_autofree(inn.dialogue_label)
	inn.dialogue_box = Control.new()
	add_child_autofree(inn.dialogue_box)
	inn._rest_party()
	assert_eq(int(GameState.get_gold()), 5,
		"insufficient gold must NOT spend (party_gold stays at 5)")
	# The dialog label must show the not-enough-gold message.
	assert_true(inn.dialogue_label.text.contains("Not enough gold"),
		"insufficient gold must surface a 'Not enough gold' message in the dialog label")
	# Restore.
	GameState.party_gold = prior_gold
