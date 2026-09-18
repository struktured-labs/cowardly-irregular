extends GutTest

## A rule names the AUTHORED word — the ability says Burn, the ring offers `burn`, the composer's
## vocabulary emits `burn` — and the engine stores `burning`, because BattleManager aliases the
## authored effect at apply. `status in combatant.status_effects` is literal, so the rule never fired.
##
## Four surfaces, one mechanism: the autogrind console ring, a saved rule, a shared COWIR1: code,
## and an LLM-composed rule. Fixed on the RULE side (Combatant.resolve_status_alias) rather than by
## renaming the words, so rules already saved or already shared start working instead of staying dead.
##
## ⚠️ `burn` is the second instance of the `slow` defect removed from the ring on 2026-09-17. The
## guard installed then derives applicability from the AUTHORED effect set, and `burn` IS authored by
## 5 abilities — so it was green on this the whole time. It measured what the engine ACCEPTS; the
## evaluator matches what the engine STORES. Found by cowir-ai on the composer's copy of the table.

const AutobattleScript = preload("res://src/autobattle/AutobattleSystem.gd")
const AutogrindScript = preload("res://src/autogrind/AutogrindSystem.gd")
const UI_PATH := "res://src/ui/autogrind/AutogrindUI.gd"
const BM_PATH := "res://src/battle/BattleManager.gd"
const HBR_PATH := "res://src/autogrind/HeadlessBattleResolver.gd"

var _ab
var _ag
## The ally/enemy arm drives BattleManager's SHARED party arrays. Restoring inline is not enough:
## an error between the swap and the restore aborts the function and strands the autoload holding
## this file's freed fixtures for every later test in the process.
var _saved_players: Array = []
var _saved_enemies: Array = []
var _parties_taken: bool = false


func before_each() -> void:
	_ab = AutobattleScript.new()
	_ag = AutogrindScript.new()
	for sys in [_ab, _ag]:
		if "_test_disable_persistence" in sys:
			sys._test_disable_persistence = true
	add_child_autofree(_ab)
	add_child_autofree(_ag)


func after_each() -> void:
	if not _parties_taken:
		return
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm != null and "player_party" in bm:
		bm.player_party = _saved_players
		bm.enemy_party = _saved_enemies
	_parties_taken = false


func _combatant(nm: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": nm, "max_hp": 100, "max_mp": 50,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	return c


func test_a_rule_saying_burn_matches_a_burning_combatant() -> void:
	## The defect, on the surface a player touches. "burning" is what the engine stores — asserted
	## here rather than assumed, because the whole bug is that the two words differ.
	var c := _combatant("Victim")
	c.add_status("burning", 3)
	assert_false(c.has_status("burn"), "CONTROL: the engine stores 'burning', not 'burn'")
	assert_true(_ab._evaluate_grid_condition(c, {"type": "has_status", "status": "burn"}),
		"a rule naming the word the ability uses must fire")


func test_the_negative_form_agrees_with_the_positive() -> void:
	## not_has_status resolved separately, so it can disagree — and a rule pair that contradicts
	## itself is worse than one that never fires.
	var c := _combatant("Victim")
	c.add_status("burning", 3)
	assert_false(_ab._evaluate_grid_condition(c, {"type": "not_has_status", "status": "burn"}),
		"not_has_status must see the same burn the positive form sees")


func test_the_ally_and_enemy_forms_resolve_too() -> void:
	## Five grid conditions read the word from the same key and each resolved it separately, so a
	## fix applied to has_status alone leaves a rule fired from the other side still dead.
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm == null or not ("player_party" in bm):
		pass_test("BattleManager autoload unavailable")
		return
	var me := _combatant("Me")
	var ally := _combatant("Ally")
	var foe := _combatant("Foe")
	_saved_players = bm.player_party.duplicate()
	_saved_enemies = bm.enemy_party.duplicate()
	_parties_taken = true
	## Typed, deliberately: player_party is Array[Combatant] and an untyped literal ABORTS the
	## assignment, taking every assert below it with it (the file scored Risky, not Failed).
	var players: Array[Combatant] = [me, ally]
	var foes: Array[Combatant] = [foe]
	bm.player_party = players
	bm.enemy_party = foes
	ally.add_status("burning", 3)
	foe.add_status("burning", 3)
	var ally_hit: bool = _ab._evaluate_grid_condition(me, {"type": "ally_has_status", "status": "burn"})
	var enemy_hit: bool = _ab._evaluate_grid_condition(me, {"type": "enemy_has_status", "status": "burn"})
	var enemy_absent: bool = _ab._evaluate_grid_condition(me, {"type": "not_enemy_has_status", "status": "burn"})
	assert_true(ally_hit, "ally_has_status must resolve the authored word")
	assert_true(enemy_hit, "enemy_has_status must resolve the authored word")
	assert_false(enemy_absent, "not_enemy_has_status must see the same burn its positive form sees")


func test_the_console_ring_condition_resolves_too() -> void:
	## The grind's member_status is a different evaluator with its own read of the word.
	var c := _combatant("Member")
	c.add_status("burning", 3)
	assert_true(_ag._evaluate_party_condition([c], {"type": "member_status", "value": "burn"}),
		"the console ring's own condition must fire for the word the ring offers")


func test_resolution_does_not_invent_a_match() -> void:
	## The resolver widens matching, so the cheap failure is a rule that now matches anything.
	var c := _combatant("Healthy")
	assert_false(_ab._evaluate_grid_condition(c, {"type": "has_status", "status": "burn"}),
		"an unafflicted combatant must not match")
	c.add_status("poison", 3)
	assert_false(_ab._evaluate_grid_condition(c, {"type": "has_status", "status": "burn"}),
		"a different status must not match")
	assert_false(_ab._evaluate_grid_condition(c, {"type": "has_status", "status": "slow"}),
		"`slow` lands nowhere and must stay false — it was removed from the ring for that reason")


func _applier_aliases(path: String = BM_PATH) -> Dictionary:
	## Derived from an APPLIER, which is the authority on what lands. BOTH engines alias, so the
	## path is a parameter — pinning the rule side to live alone leaves a grind-side drift invisible,
	## on a fix whose whole subject is the two engines disagreeing about a key (cowir-battle).
	var out: Dictionary = {}
	var guard := RegEx.create_from_string("if\\s+status_to_add\\s*==\\s*\"([a-z_]+)\"\\s*:")
	var assign := RegEx.create_from_string("^\\s*status_to_add\\s*=\\s*\"([a-z_]+)\"")
	var pending: String = ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var l: String = str(line)
		if l.strip_edges().begins_with("#"):
			continue
		var g := guard.search(l)
		if g != null:
			pending = g.get_string(1)
			continue
		if pending != "":
			var a := assign.search(l)
			if a != null:
				out[pending] = a.get_string(1)
			pending = ""
	return out


func test_the_rule_side_table_matches_the_applier() -> void:
	## The rule side holds its own copy. If the applier adds an alias and this does not, the new
	## status is exactly as unmatchable as burn was — the defect returns under a different name.
	var applier: Dictionary = _applier_aliases()
	assert_gt(applier.size(), 2, "CONTROL: the applier's alias table must be found, or this is vacuous")
	var rules: Dictionary = Combatant.STATUS_ALIASES
	var a_keys: Array = applier.keys()
	a_keys.sort()
	var r_keys: Array = rules.keys()
	r_keys.sort()
	gut.p("    applier=%s" % str(a_keys))
	gut.p("    rules  =%s" % str(r_keys))
	assert_eq(r_keys, a_keys, "the rule side must know every alias the applier performs")
	for k in a_keys:
		assert_eq(str(rules.get(k, "")), str(applier[k]), "both sides must agree on where %s lands" % k)


func test_both_engines_alias_alike_and_the_rule_side_knows_it() -> void:
	## The rule side is ONE table and there are TWO appliers. They agree today and nothing said so.
	var live: Dictionary = _applier_aliases(BM_PATH)
	var grind: Dictionary = _applier_aliases(HBR_PATH)
	assert_gt(grind.size(), 2, "CONTROL: the grind applier's table must be found, or this is vacuous")
	var g_keys: Array = grind.keys()
	g_keys.sort()
	var l_keys: Array = live.keys()
	l_keys.sort()
	gut.p("    grind=%s" % str(g_keys))
	assert_eq(g_keys, l_keys, "the two appliers must alias the same effects")
	for k in l_keys:
		assert_eq(str(grind.get(k, "")), str(live[k]), "both appliers must send %s to the same key" % k)
		assert_eq(str(Combatant.STATUS_ALIASES.get(k, "")), str(grind[k]),
			"the rule side must agree with the GRIND applier too, not only with live")


func test_every_ring_entry_can_be_true_after_resolution() -> void:
	## The ring guard's question, asked against what LANDS rather than what is authored — the
	## distinction that let `burn` sit in the ring while `slow` was removed for the same defect.
	var ab: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var applier: Dictionary = _applier_aliases()
	var landed: Dictionary = {}
	for d in ab.values():
		for key in ["effect", "secondary_effect"]:
			var e: String = str((d as Dictionary).get(key, ""))
			if e != "":
				landed[str(applier.get(e, e))] = true
	assert_gt(landed.size(), 30, "CONTROL: the landed set must be real")
	var code: String = FileAccess.get_file_as_string(UI_PATH)
	var at: int = code.find("const MEMBER_STATUS_RING")
	assert_gt(at, 0, "CONTROL: the ring must be locatable")
	var dead: Array[String] = []
	for m in RegEx.create_from_string('"([a-z_]+)"').search_all(code.substr(at, code.find("]", at) - at)):
		var entry: String = m.get_string(1)
		if not landed.has(Combatant.resolve_status_alias(entry)):
			dead.append(entry)
	gut.p("    ring dead-after-resolution: %s" % str(dead))
	assert_eq(dead.size(), 0, "a ring entry still cannot be true even after resolution: " + str(dead))


func test_the_landed_derivation_can_actually_say_dead() -> void:
	## Without this the arm above is green whenever the derivation is broken.
	var applier: Dictionary = _applier_aliases()
	assert_true(applier.has("burn"), "the derivation must see the burn alias it is built around")
	assert_eq(str(applier.get("burn", "")), "burning", "and read where it lands")
	assert_eq(Combatant.resolve_status_alias("slow"), "slow",
		"CONTROL: an unaliased name resolves to itself, so a dead entry stays dead")


func test_zz_the_shared_parties_were_handed_back() -> void:
	## Declared last so it runs after the arm that swaps them. Without it the strand is invisible:
	## an aborting arm still scores PASSING on the asserts it reached before the abort.
	var bm: Node = get_node_or_null("/root/BattleManager")
	if bm == null or not ("player_party" in bm):
		pass_test("BattleManager autoload unavailable")
		return
	var mine := ["Me", "Ally", "Foe"]
	var strays: Array[String] = []
	## ⛔ A FREED fixture is the dangerous case and the obvious check SKIPS it: add_child_autofree
	## frees these at arm end, so a strand leaves INVALID instances, not named ones. Guarding the
	## name lookup behind is_instance_valid made this arm pass under the very abort it defends.
	for c in bm.player_party + bm.enemy_party:
		if c == null or not is_instance_valid(c):
			strays.append("<freed>")
		elif str(c.combatant_name) in mine:
			strays.append(str(c.combatant_name))
	assert_eq(strays.size(), 0, "this file left its fixtures in the shared parties: " + str(strays))
