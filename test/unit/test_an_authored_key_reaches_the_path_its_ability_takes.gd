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

## Keys whose value changes what an ability DOES. Cosmetic and schema keys are out of scope: `name`,
## `description`, `animation` and friends are read by the UI or by nobody, which is the other file's
## subject.
const MECHANICAL_KEYS := ["secondary_effect", "scales_with", "drain_percentage", "hits", "effect_chance", "max_multiplier"]

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
func _orphans() -> Dictionary:
	var code: String = GdSourceHelper.code_of(BM_PATH)
	var bodies := {}
	for type in TYPE_EXECUTOR.values():
		bodies[type] = _reachable_body(code, str(type))
	var out := {}
	for id in _abilities():
		var ability = _abilities()[id]
		if not (ability is Dictionary):
			continue
		var executor: String = str(TYPE_EXECUTOR.get(str(ability.get("type", "")), ""))
		if executor == "":
			continue
		for key in MECHANICAL_KEYS:
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
	for key in MECHANICAL_KEYS:
		assert_true(code.contains('"%s"' % key), "%s must be read somewhere in the live engine" % key)


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
