extends GutTest

## Every item grant lands on the party leader: chests, shops, drops, quest rewards, and the
## default party's starting kit. Battle read each member's own inventory, so measured on the real
## default party only the Fighter had an Item command, and the "use a potion" rule in 17 shipped
## autobattle presets could never fire for a Cleric, Mage, Rogue or Bard. The field Items menu
## already treated inventory as one party bag. Battle now does the same: the menu lists the bag,
## a use spends the user's own stock first and then another holder's, and autobattle counts the
## bag, both live and headless. Enemies still use only their own inventory.

const MenuScript = preload("res://src/battle/BattleCommandMenu.gd")
const SceneScript = preload("res://src/battle/BattleScene.gd")
const GameLoopScript = preload("res://src/GameLoop.gd")

var _saved_party: Array
var _saved_enemies: Array
var _saved_order: Array
var _saved_index: int
var _saved_current


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()
	_saved_enemies = BattleManager.enemy_party.duplicate()
	_saved_order = BattleManager.selection_order.duplicate()
	_saved_index = BattleManager.selection_index
	_saved_current = BattleManager.current_combatant


func after_each() -> void:
	BattleManager.player_party.assign(_alive(_saved_party))
	BattleManager.enemy_party.assign(_alive(_saved_enemies))
	BattleManager.selection_order.assign(_alive(_saved_order))
	BattleManager.selection_index = _saved_index
	BattleManager.current_combatant = _saved_current if is_instance_valid(_saved_current) else null


func _alive(saved: Array) -> Array:
	return saved.filter(func(c): return is_instance_valid(c))


func _pc(pc_name: String, job_id: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = pc_name
	c.job = {"id": job_id}
	c.max_hp = 1000
	c.current_hp = 400
	c.current_ap = 2
	c.is_alive = true
	return c


func _enemy() -> Combatant:
	var e := Combatant.new()
	autofree(e)
	e.combatant_name = "Goblin"
	e.max_hp = 900
	e.current_hp = 900
	e.is_alive = true
	return e


func _default_party() -> Array[Combatant]:
	var gl = autofree(GameLoopScript.new())
	gl._create_party()
	var party: Array[Combatant] = []
	for m in gl.party:
		party.append(m)
	return party


func _menu_ids(party: Array[Combatant], actor: Combatant, enemy: Combatant) -> Array:
	BattleManager.player_party.assign(party)
	BattleManager.selection_order.assign(party)
	BattleManager.selection_index = party.find(actor)
	BattleManager.current_combatant = actor
	var scene = autofree(SceneScript.new())
	scene.party_members.assign(party)
	scene.test_enemies.assign([enemy] as Array[Combatant])
	for i in party.size():
		var s := AnimatedSprite2D.new()
		add_child_autofree(s)
		scene.party_sprite_nodes.append(s)
	var es := AnimatedSprite2D.new()
	add_child_autofree(es)
	scene.enemy_sprite_nodes.append(es)
	add_child_autofree(scene)
	var rows: Array = MenuScript.new(scene).build_command_menu_items_with_targets(actor)
	return rows.map(func(r): return str(r.get("id", "")))


func test_floor_the_bag_this_file_drives() -> void:
	for m in ["party_item_count", "party_inventory", "take_party_item"]:
		assert_true(ItemSystem.has_method(m), "ItemSystem must still expose %s()" % m)
	## take_party_item RETURNS remove_item's verdict, so both halves of the spend are this file's
	var probe: Combatant = autofree(Combatant.new())
	for m in ["get_item_count", "remove_item", "add_item"]:
		assert_true(probe.has_method(m), "Combatant must still expose %s()" % m)
	var gl = autofree(GameLoopScript.new())
	assert_true(gl.has_method("_create_party"), "GameLoop must still expose _create_party()")


func test_every_member_of_the_default_party_gets_an_item_command() -> void:
	var party := _default_party()
	assert_gt(party.size(), 1, "CONTROL: the default party has more than one member")
	var holders := party.filter(func(m): return not m.inventory.is_empty())
	assert_eq(holders.size(), 1, "CONTROL: the default kit sits on ONE member, which is what the menu used to read")
	var enemy := _enemy()
	for m in party:
		assert_true(_menu_ids(party, m, enemy).has("item_menu"),
			"%s has no Item command — the bag is on %s and battle read only its own inventory" % [m.combatant_name, holders[0].combatant_name])


func test_a_member_without_the_item_spends_it_from_the_holder() -> void:
	var leader := _pc("Fighter", "fighter")
	var cleric := _pc("Cleric", "cleric")
	leader.add_item("potion", 3)
	BattleManager.player_party.assign([leader, cleric] as Array[Combatant])
	BattleManager._execute_item(cleric, "potion", [leader])
	assert_eq(leader.get_item_count("potion"), 2, "the Cleric's potion must come out of the leader's stock")
	assert_eq(cleric.get_item_count("potion"), 0, "CONTROL: the Cleric held none")


func test_a_holder_spends_their_own_stock_first() -> void:
	var leader := _pc("Fighter", "fighter")
	var cleric := _pc("Cleric", "cleric")
	leader.add_item("potion", 3)
	cleric.add_item("potion", 1)
	BattleManager.player_party.assign([leader, cleric] as Array[Combatant])
	BattleManager._execute_item(cleric, "potion", [leader])
	assert_eq(cleric.get_item_count("potion"), 0, "a PC holding the item must spend their own first")
	assert_eq(leader.get_item_count("potion"), 3, "the leader's stock was touched while the user held one")


func test_autobattle_counts_the_bag() -> void:
	var leader := _pc("Fighter", "fighter")
	var mage := _pc("Mage", "mage")
	leader.add_item("potion", 4)
	BattleManager.player_party.assign([leader, mage] as Array[Combatant])
	assert_eq(AutobattleSystem._get_item_count(mage, "potion"), 4,
		"a Mage's 'Has Item: potion' read its own empty inventory — every preset's potion rule was dead")


func test_a_headless_grind_spends_from_the_bag_too() -> void:
	var leader := _pc("Fighter", "fighter")
	var bard := _pc("Bard", "bard")
	leader.add_item("potion", 2)
	var resolver = HeadlessBattleResolver.new()
	resolver._player_party = [leader, bard]
	resolver._resolve_item(bard, "potion", leader)
	assert_eq(leader.get_item_count("potion"), 1, "the grind spent nothing — live and headless disagree on the bag")


func test_decoy_an_enemy_never_reaches_into_the_party_bag() -> void:
	var leader := _pc("Fighter", "fighter")
	leader.add_item("potion", 3)
	var goblin := _enemy()
	BattleManager.player_party.assign([leader] as Array[Combatant])
	BattleManager.enemy_party.assign([goblin] as Array[Combatant])
	BattleManager._execute_item(goblin, "potion", [goblin])
	assert_eq(leader.get_item_count("potion"), 3, "an enemy drank from the party's bag")


## ⛔ take_party_item RETURNS A VERDICT AND THREE CALL SITES DISCARD IT — BattleManager's live item
## executor and HeadlessBattleResolver's two. cowir-overworld reported that as a live free-item-use
## bug. It is NOT one, and the four arms below are the entire reason: a count check gates every one
## of those paths, and a counted bag always pays. BOTH halves were unpinned — every assert above
## checks a COUNT after a successful take, and the verdict itself had ZERO asserts anywhere in
## test/. So "the discard is harmless" was true by coincidence rather than by check, and an edit to
## either half would turn three sites into silent free uses with nothing to catch it.
func test_a_countable_bag_always_pays() -> void:
	var leader := _pc("Bram", "fighter")
	var cleric := _pc("Marta", "cleric")
	var outsider := _pc("Phil", "rogue")
	var bag: Array = [leader, cleric]
	## take checks the user's own stock, then every OTHER member of the bag. count sums the bag.
	## These four cases are where those two populations could diverge.
	for c in [
		{"label": "the user holds it", "holder": leader, "user": leader},
		{"label": "another member holds it", "holder": leader, "user": cleric},
		{"label": "the user is not in the bag", "holder": leader, "user": outsider},
		{"label": "the user is null", "holder": cleric, "user": null},
	]:
		leader.inventory.clear()
		cleric.inventory.clear()
		outsider.inventory.clear()
		(c["holder"] as Combatant).add_item("potion", 1)
		assert_gt(ItemSystem.party_item_count(bag, "potion"), 0,
			"PRECONDITION (%s): the bag must count one, or the arm proves nothing" % c["label"])
		assert_true(ItemSystem.take_party_item(c["user"], bag, "potion"),
			"a bag counting > 0 must pay — %s. Three call sites discard this verdict, so a false here is a free item use." % c["label"])


func test_an_unpayable_take_still_refuses() -> void:
	var leader := _pc("Bram", "fighter")
	var cleric := _pc("Marta", "cleric")
	leader.inventory.clear()
	cleric.inventory.clear()
	var bag: Array = [leader, cleric]
	assert_eq(ItemSystem.party_item_count(bag, "potion"), 0, "CONTROL: nobody holds one")
	## DECOY: without this arm `return true` satisfies the one above, and a verdict that cannot say
	## no is exactly as useless to those three call sites as one nobody reads.
	assert_false(ItemSystem.take_party_item(leader, bag, "potion"),
		"an empty bag must return false — a take that can only say yes pins nothing")


func test_a_counted_item_can_always_be_removed() -> void:
	var pc := _pc("Bram", "fighter")
	pc.inventory.clear()
	pc.add_item("potion", 1)
	assert_gt(pc.get_item_count("potion"), 0, "PRECONDITION: the stock must read one")
	## take_party_item consults get_item_count and then RETURNS remove_item's verdict. Repoint
	## either at a different store and the take reports failure after the effect already landed.
	assert_true(pc.remove_item("potion", 1),
		"get_item_count() > 0 must imply remove_item() — take_party_item returns this verdict verbatim")
	assert_eq(pc.get_item_count("potion"), 0, "and the stock must actually fall")


func test_every_discarded_take_verdict_sits_behind_a_count_check() -> void:
	## ⛔ COMMENTS STRIPPED AND THE SEARCH ANCHORED BY LINE INDEX. A function-body bound cannot
	## protect an anchor search, because the header lives inside the bound: my last ratchet of this
	## shape landed on a COMMENT naming the symbol and swept in a guard from the wrong side of the
	## call. The comment above this very arm names both symbols, so an unstripped search passes
	## whatever the code does.
	var bare := RegEx.create_from_string("^[A-Za-z_][A-Za-z0-9_.]*\\.take_party_item\\(")
	var discarded := 0
	for path in ["res://src/battle/BattleManager.gd", "res://src/autogrind/HeadlessBattleResolver.gd"]:
		## ⛔ strip_comments, NOT code_of. code_of partitions on triple-quoted regions and rejoins
		## the surviving code with
		## "\n", so it is NOT LINE-PRESERVING — measured on these two files, +57 and +4 lines of
		## drift, which is exactly how far wrong the line number this arm PRINTS would be.
		## strip_comments keeps one output line per input line, which is what a positional anchor
		## needs. Docstrings therefore survive; measured, neither file's docstring half contains
		## either token, so none can forge a gate. code_of is right for a PRESENCE assert and wrong
		## for a POSITIONAL one, and this arm is positional.
		var lines: PackedStringArray = GdSource.strip_comments(FileAccess.get_file_as_string(path)).split("\n")
		var func_start := 0
		for i in lines.size():
			var line: String = lines[i]
			if line.begins_with("func ") or line.begins_with("static func "):
				func_start = i
			if bare.search(line.strip_edges()) == null:
				continue
			var guarded := false
			for j in range(func_start, i):
				if lines[j].contains("party_item_count(") and lines[j].contains("<= 0"):
					guarded = true
					break
			assert_true(guarded,
				"%s:%d discards take_party_item()'s verdict with no party_item_count() <= 0 gate above it in its own function — that is a free item use" % [str(path).get_file(), i + 1])
			discarded += 1
	## ANTI-VACUITY: the loop proves nothing if it matched no site. No count is pinned — a new
	## discarded site must be GATED, not merely counted, so this floor is a relationship not a value.
	assert_gt(discarded, 0,
		"found no discarded take_party_item() verdict — the search is broken, not the code")
