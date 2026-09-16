extends GutTest

## ⛔ A KEY CAN HAVE A READER AND STILL BE DEAD FOR THE ABILITIES THAT AUTHOR IT. Every ability type is
## dispatched to ONE executor, and a key read in `_execute_physical_ability` does nothing for a `magic`
## ability — the reader exists, so a grep says "consumed", and
## test_ability_effect_keys_reach_the_engine_regression scores it CONSUMED too. That file's subject is
## "is this key read at all"; this one's is "is it read on the path this ability actually takes".
##
## Found after three lanes handed me three instances of it in one afternoon, one at a time
## (cowir-autogrind 11595 and 11601, and my own frost_armor hold). The class is worth a ratchet more
## than any one instance is worth a fix: each is a BALANCE call — every one of these abilities gets
## stronger when its key is wired, and six of the nine casters are monsters.
##
## ⚠️ NOT A CLAIM THAT ANY OF THESE SHOULD BE WIRED. The declarations record who holds the call, per
## CLAUDE.md's declare-or-explain rule. The set reds if it GROWS (a new ability authors a key its path
## cannot read) and if it SHRINKS (someone wired one and left the declaration standing — cowir-sprites'
## arm, adopted: a declaration that outlives its fact is worse than none).

## ⛔ WHAT THIS RATCHET IS STRUCTURALLY BLIND TO, named because a presence census cannot find its
## own blind spot. This asks "is the key READ on the path this ability takes" — a presence question.
## It cannot see:
##   1. A key read and its answer DISCARDED. Mutation-7's shape: `var v = ability.get("k", 0.0)`
##      followed by a branch that does nothing with `v` scores CONSUMED here.
##   2. A handler that exists and HARDCODES what the key authors. cowir-autogrind hit this in the
##      grind (11791): an arm restored 25% MP where live reads an authored 5%, so the grep was
##      correctly NON-EMPTY and the behaviour was five times off. Axis 1 and axis 2 are both green
##      on that shape; only comparing the two implementations line by line finds it.
## Both are VALUE divergences, and every arm in this file is a PRESENCE arm. Measured on live
## 2026-09-16 for case 1 — every `var x = ability.get(...)` in BattleManager uses `x` again in the
## same function, 0 dead reads — so the blind spot is real and currently unoccupied here, which is
## the honest thing to record rather than "no instances" or silence.
const BM_PATH := "res://src/battle/BattleManager.gd"
const ABILITIES := "res://data/abilities.json"
const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")

## ability type -> the executor _execute_ability dispatches it to. Pinned by a control arm below that
## reads the dispatcher, so this map cannot quietly stop describing the code.
const TYPE_EXECUTOR := {
	"physical": "_execute_physical_ability",
	"magic": "_execute_magic_ability",
	"healing": "_execute_healing_ability",
	"support": "_execute_support_ability",
	"song": "_execute_support_ability",
	"status": "_execute_support_ability",
}

## ⛔ THIS WAS A HAND-LIST OF SIX KEYS AND abilities.json AUTHORS SEVENTY. Everything not on the list
## was invisible to the ratchet — including `condition` and `threshold` on the TUTORIAL BOSS's
## `desperate_bite`, `trigger` on `counter`, and three Guardian BP keys. Same defect
## test_status_icons_cover_applied_statuses names in its own header ("a hand-list is what let nine
## accumulate"), in the file I wrote to catch that class. The set is DERIVED from the data now, and a
## key leaves scope only by being declared below with who reads it instead.
func _mechanical_keys() -> Array:
	var out: Array = []
	for id in _abilities():
		var a = _abilities()[id]
		if not (a is Dictionary):
			continue
		for k in a:
			var key: String = str(k)
			if not OUT_OF_SCOPE.has(key) and not out.has(key):
				out.append(key)
	out.sort()
	return out


## Keys whose value does NOT change what an executor does, each naming the consumer that DOES read it.
## This is the only way out of scope — you cannot silence a key green, only explain it green.
const OUT_OF_SCOPE := {
	"id": "schema",
	"name": "UI — the menu row's label (BattleCommandMenu._build_ability_menu_item)",
	"description": "UI — the row's tooltip, same function",
	"animation": "presentation — BattleScene._on_action_executed reads it to pick the cast/attack anim",
	"type": "schema — it IS the dispatch key; _execute_ability matches on it",
	"target_type": "consumed BEFORE dispatch, by the menu's row build and by AutobattleSystem",
	"mp_cost": "spent by _execute_ability through JobSystem.get_ability_mp_cost, not by any executor",
	"cost": "shop price — VillageShop, never the engine",
	"tier": "shop shelf grouping",
	"family": "shop shelf grouping",
	"magic_school": "shop shelf grouping",
	"priority": "consumed by TURN ORDER, before any executor runs — _compute_action_speed subtracts PRIORITY_OFFSET, which is why quick_strike goes first. An executor could not implement it",
	"element": "ASSESSED, not skipped: a weapon strike's element is flavour BY CONSTRUCTION — the physical executor carries the reasoning in its own body and test_weapon_strike_element_is_flavour pins it. The magic path reads it.",
}

## Mechanical keys the live engine reads NOWHERE AT ALL. That is axis 1 —
## test_ability_effect_keys_reach_the_engine_regression's subject — and listing them here keeps this
## file's anti-vacuity arm honest rather than letting a key be "not read on its path" when the truth
## is "not read anywhere". Four of the eight are one authored feature each:
##   bp_cost · bp_gain · damage_reduction   the Guardian's Brave/Default BP stacking, which CLAUDE.md
##                                          lists under "Future: Combat System Mutation" — unbuilt by
##                                          design, not broken
##   condition · threshold                  desperate_bite, see DECLARED_ORPHANS
##   next_crit                              shadow_step's guaranteed crit IS wired, by status rather
##                                          than by this key (BattleManager:5272) — decorative, not dead
##   reflect_damage_element                 frost_armor, held for struktured
##   trigger                                counter, see DECLARED_ORPHANS
const UNREAD_BY_THE_LIVE_ENGINE := ["bp_cost", "bp_gain", "condition", "damage_reduction",
	"next_crit", "reflect_damage_element", "threshold", "trigger"]

## key -> ability ids whose own executor does not read it, and who holds the call.
## Every entry is a BALANCE decision, not an oversight to fix quietly.
const DECLARED_ORPHANS := {
	"secondary_effect:subset_drain": "magic; _apply_secondary_effect is called only from _execute_support_ability. Description promises 'reducing magic and attack' and only attack lands. Caster empty_set is POOLED — wiring it makes W6 encounters harder. struktured's call (cowir-autogrind 11595, cowir-battle 11599)",
	"secondary_effect:toxic_embrace": "physical; same reader. Description promises 'poisoning and slowing' and only poison lands. Caster toxic_sludge is POOLED. struktured's call",
	"scales_with:complement": "magic; scales_with is read only in _execute_physical_ability, and `target_defense` has no reader anywhere — it scales from attack in both engines. Caster empty_set is POOLED (cowir-autogrind 11601)",
	"scales_with:player_knowledge": "magic; same reader, and `most_used_ability` has no reader anywhere either",
	"drain_percentage:dark_slash": "physical; drain_percentage is read only in _execute_magic_ability, so the one physical drain heals its caster nothing",
	"hits:temporal_strike": "magic; hits is read only in _execute_physical_ability, so the one magic multi-hit lands once in LIVE. ⚠️ The GRIND now loops both arms (cowir-autogrind 04f2b2f8), so this ability is the one place the grind hits HARDER than live — flagged to that lane",
	"effect_chance:bark": "support; effect_chance is read in the physical and magic executors. Support rolls `success_rate` instead, which defaults to 1.0 — so the authored chance is ignored and the effect always lands",
	"effect_chance:peace_sign": "support; same",
	"effect_chance:puppy_eyes": "support; same",
	"effect_chance:lullaby": "song; same, routed to the support executor. The Bard's sleep is authored at 0.6 and lands at 1.0",
	## ── surfaced 2026-09-16 when the key set stopped being hand-picked ──
	"condition:desperate_bite": "physical; `condition` and `threshold` have NO reader in the battle code, so the 2.0 multiplier applies unconditionally while the description says 'deals double damage when below 30% HP'. ⚠️ THE FIX DIRECTION IS AMBIGUOUS AND THAT IS WHY IT IS HERE: read 2.0 as the CONDITIONAL value and the ability is currently twice as strong as authored; read it as the BASE and the condition should double it to 4.0. Both are grammatical. Measured: 2.0 is 5th of 62 monster physical abilities (median 1.30), and the Rat King's other physical is 0.8. Casters are cave_rat_king — the TUTORIAL BOSS every player fights — and cleric_survive_target, the Cleric's spotlight duel. struktured's call",
	"threshold:desperate_bite": "physical; the other half of the same key pair. Wiring one without the other is meaningless",
	"trigger:counter": "physical; `trigger: on_hit` has no reader, so Counter is a normal turn action rather than a reaction. The reactive mechanic EXISTS but is monster-only — _trigger_monster_counter returns early unless the counter-er is in enemy_party — so giving the Ninja a real on_hit reaction is new behaviour, not a repair. Its `target_type: last_attacker` is also read nowhere and degrades to the first alive enemy through the live menu's default arm",
	"bp_cost:brave": "support; the Guardian's Brave/Default BP stacking is listed in CLAUDE.md under 'Future: Combat System Mutation'. Unbuilt by design — declared so it cannot be mistaken for a regression",
	"bp_gain:default": "support; see bp_cost:brave",
	"damage_reduction:default": "support; see bp_cost:brave",
	"next_crit:shadow_step": "support; DECORATIVE, not dead — the guaranteed crit is wired through the shadow_step STATUS (_calculate_crit_chance returns 1.0 for it, BattleManager:5272), so the behaviour the description promises does happen and this key is simply not how. Wiring it would be a refactor with no player-visible change",
	"evasion_bonus:shadow_step": "support; same shape — the 100%% dodge is wired through the status (BattleManager:8929), not through this key",
	"reflect_damage_element:frost_armor": "support; the retaliation itself is unwired and HELD for struktured (lane/frost-armor-bites-back). This key only names the element the retaliation would use, so it cannot be assessed before the retaliation is",
	"secondary_modifier:subset_drain": "magic; travels with secondary_effect and is read in the same helper. Wiring one without the other is meaningless",
	"secondary_modifier:toxic_embrace": "physical; see secondary_modifier:subset_drain",
}


func _abilities() -> Dictionary:
	var file := FileAccess.open(ABILITIES, FileAccess.READ)
	assert_not_null(file, "abilities.json must load")
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	return data.get("abilities", data)


## The executor's own body PLUS the bodies of the helpers it calls, one level deep.
## ⚠️ Without the expansion this reported seven correct abilities as orphans: `_execute_support_ability`
## reads `secondary_effect` through `_apply_secondary_effect`, so the literal never appears in the
## executor itself. A reader one call away is still a reader.
func _reachable_body(code: String, executor: String) -> String:
	var body: String = _function_body(code, executor)
	var seen := {}
	for m in RegEx.create_from_string("(_[a-z_]+)\\(").search_all(body):
		var helper: String = m.get_string(1)
		if helper == executor or seen.has(helper):
			continue
		seen[helper] = true
		body += _function_body(code, helper)
	return body


func _function_body(code: String, fn: String) -> String:
	var at: int = code.find("func %s(" % fn)
	if at < 0:
		return ""
	var next: int = code.find("\nfunc ", at + 1)
	return code.substr(at, (next - at) if next > at else 4000)


## Every (key, ability) whose executor does not read that key, derived from the data and the source.
## ⚠️ THE DISPATCHER IS PART OF EVERY PATH, and leaving it out reported five correct keys as orphans.
## `_execute_ability` runs before the type match for every ability, and it is where `steals`,
## `success_rate`, `countdown`, `priority` and `guaranteed_escape` are read — so a key read there is
## read on the physical path AND the magic path. Its own body plus its direct helpers, MINUS the four
## executors it dispatches to: including those would union all four bodies and erase the distinction
## this whole file is about.
func _dispatcher_body(code: String) -> String:
	var body: String = _function_body(code, "_execute_ability")
	var seen := {}
	for m in RegEx.create_from_string("(_[a-z_]+)\\(").search_all(body):
		var helper: String = m.get_string(1)
		if TYPE_EXECUTOR.values().has(helper) or helper == "_execute_ability" or seen.has(helper):
			continue
		seen[helper] = true
		body += _function_body(code, helper)
	return body


func _orphans() -> Dictionary:
	var code: String = GdSourceHelper.code_of(BM_PATH)
	var shared: String = _dispatcher_body(code)
	var bodies := {}
	for type in TYPE_EXECUTOR.values():
		bodies[type] = shared + _reachable_body(code, str(type))
	var out := {}
	var keys: Array = _mechanical_keys()
	for id in _abilities():
		var ability = _abilities()[id]
		if not (ability is Dictionary):
			continue
		var executor: String = str(TYPE_EXECUTOR.get(str(ability.get("type", "")), ""))
		if executor == "":
			continue
		for key in keys:
			if ability.has(key) and not str(bodies[executor]).contains('"%s"' % key):
				out["%s:%s" % [key, id]] = executor
	return out


func test_the_dispatcher_still_sends_each_type_where_this_guard_thinks() -> void:
	## CONTROL: the whole measurement rests on this map. If a type is re-routed, every orphan below is
	## about the wrong function and the arms could pass while describing nothing.
	var code: String = GdSourceHelper.code_of(BM_PATH)
	var at: int = code.find("func _execute_ability(")
	assert_gt(at, -1, "the dispatcher survives stripping")
	## Bounded by the FUNCTION, not by a character count: my first version read 3000 chars and stopped
	## short of the match arms, redding on correct code — the magnitude-window shape this fleet has
	## corrected three times today.
	var next_func: int = code.find("\nfunc ", at + 1)
	var body: String = code.substr(at, (next_func - at) if next_func > at else 8000)
	for type in TYPE_EXECUTOR:
		assert_true(body.contains('"%s"' % type), "the dispatcher still matches ability type '%s'" % type)
	for executor in TYPE_EXECUTOR.values():
		assert_true(body.contains(executor + "("), "and still dispatches to %s" % executor)
	assert_true(body.contains('"support", "song", "status":'),
		"support, song and status share one executor — three of the declared orphans depend on that")


func test_every_mechanical_key_is_read_by_some_executor() -> void:
	## Anti-vacuity: if a key were read by NO executor, every ability authoring it would count as an
	## orphan and the set below would be full of noise rather than findings. That case belongs to
	## test_ability_effect_keys_reach_the_engine_regression, not here.
	var code: String = GdSourceHelper.code_of(BM_PATH)
	var unread: Array = []
	for key in _mechanical_keys():
		if not code.contains('"%s"' % key):
			unread.append(key)
	assert_eq(unread, UNREAD_BY_THE_LIVE_ENGINE,
		"a mechanical key the live engine reads NOWHERE is the other file's subject, not this one — add it to UNREAD_BY_THE_LIVE_ENGINE or to OUT_OF_SCOPE with its consumer: " + str(unread))


func test_no_ability_authors_a_key_its_own_path_cannot_read() -> void:
	var found: Dictionary = _orphans()
	var undeclared: Array = []
	for orphan in found:
		if not DECLARED_ORPHANS.has(orphan):
			undeclared.append("%s (its type goes to %s, which never reads that key)" % [orphan, found[orphan]])
	assert_eq(undeclared.size(), 0,
		"a new ability authors a key the executor for its type does not read. Wire it, re-type the ability, or DECLARE it in DECLARED_ORPHANS with who holds the call: " + str(undeclared))


func test_a_declaration_does_not_outlive_the_thing_it_declares() -> void:
	## cowir-sprites' arm, adopted: the moment one of these is wired, the declaration becomes a lie that
	## the next reader trusts. Reds in the GOOD direction and says which way to close it.
	var found: Dictionary = _orphans()
	var stale: Array = []
	for declared in DECLARED_ORPHANS:
		if not found.has(declared):
			stale.append(declared)
	assert_eq(stale.size(), 0,
		"GOOD NEWS: these are no longer orphaned — someone wired the key, or the ability changed type. Delete the line(s) from DECLARED_ORPHANS: " + str(stale))


func test_the_set_is_not_empty_and_names_its_worst_case() -> void:
	## If this ever empties, the guard has outlived its subject and should be deleted rather than kept
	## as a green nothing. Until then, the two that a player meets in a POOLED fight are named here so
	## the list cannot quietly become a pile.
	assert_gt(DECLARED_ORPHANS.size(), 0, "an empty set means the class is gone — delete this file rather than keep it green")
	for pooled in ["secondary_effect:subset_drain", "secondary_effect:toxic_embrace"]:
		assert_true(DECLARED_ORPHANS.has(pooled), "%s is cast by a pooled monster and stays named" % pooled)
		assert_true(str(DECLARED_ORPHANS[pooled]).contains("struktured"), "and records whose call it is")


func test_every_authored_key_is_either_in_scope_or_explains_itself() -> void:
	## ⛔ THE ARM THIS FILE WAS MISSING. MECHANICAL_KEYS was six names I thought of, so seventy-minus-six
	## authored keys were exempt from the ratchet by omission and nothing said so. Now a new key in
	## abilities.json is IN SCOPE by default and leaves only by being declared in OUT_OF_SCOPE with the
	## consumer that reads it — the deliverable, never permission to skip.
	var authored: Dictionary = {}
	for id in _abilities():
		var a = _abilities()[id]
		if a is Dictionary:
			for k in a:
				authored[str(k)] = true
	assert_gt(authored.size(), 40, "CONTROL: abilities.json must yield a real key surface; got %d" % authored.size())
	var in_scope: Array = _mechanical_keys()
	var unaccounted: Array = []
	for key in authored:
		if not in_scope.has(key) and not OUT_OF_SCOPE.has(str(key)):
			unaccounted.append(key)
	assert_eq(unaccounted, [], "every authored key is in scope or explained: " + str(unaccounted))
	assert_eq(in_scope.size() + OUT_OF_SCOPE.size(), authored.size(),
		"the two sets partition the authored surface exactly — an overlap or a gap means a key is counted twice or not at all")


func test_the_out_of_scope_list_names_a_consumer_for_every_entry() -> void:
	## A one-word exemption is a suppression flag wearing a reason's clothes. Each must say WHO reads it.
	var thin: Array = []
	for key in OUT_OF_SCOPE:
		if str(OUT_OF_SCOPE[key]).length() < 8:
			thin.append(key)
	assert_eq(thin, ["id"], "only `id` may be exempted without naming a consumer, because nothing reads it: " + str(thin))
