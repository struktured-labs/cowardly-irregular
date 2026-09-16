extends GutTest

## `ignores_defense` doubles a magic ability's damage (BattleManager:5054). Live's own comment calls
## the doubling "a rough compensation for take_damage's defense formula" rather than a true-damage
## path — so the grind has to compensate the same way or the ability lands at half strength here.
##
##   phantom_byte   magic, 1.8x, "ghosts through armor"   cast by data_wraith (POOLED)
##
## One pooled caster, so a grind draws it; and the resolver read the key nowhere, so phantom_byte was
## an ordinary 1.8x cast. Seventh in this resolver's documented class.
##
## ⛔ `ignores_resistance` — the key on the NEXT LINE of the same live block — is deliberately NOT
## wired, because no grind can exercise it. Its two owners are cast only by `meta_knight`, which is in
## no enemy pool, and this lane's own extra spawn path does not reach it either: `_spawn_meta_boss`
## builds a procedural enemy with a generated name rather than instantiating a monsters.json id. That
## second check is the one a pool census alone would miss, and it is why the declaration is measured
## rather than assumed. Pinned in the parity ledger, which reds if either caster becomes drawable.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SRC := "res://src/autogrind/HeadlessBattleResolver.gd"
const LIVE := "res://src/battle/BattleManager.gd"

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _authored(ability_id: String) -> Dictionary:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	return js.get_ability(ability_id)


## HP/MP after add_child — entering the tree restores both.
func _combatant(name: String, hp: int = 99999) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": hp, "max_mp": 999,
		"attack": 20, "defense": 40, "magic": 30, "speed": 10})
	add_child_autofree(c)
	c.current_hp = hp
	c.current_mp = c.max_mp
	return c


func _cast_damage(ability_id: String, caster: Combatant, target: Combatant) -> int:
	var before: int = target.current_hp
	_res._resolve_ability(caster, ability_id, [target])
	return before - target.current_hp


func test_a_piercing_cast_lands_harder_than_its_multiplier_alone() -> void:
	var ab: Dictionary = _authored("phantom_byte")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_true(bool(ab.get("ignores_defense", false)),
		"CONTROL: phantom_byte must still author ignores_defense")
	var wraith := _combatant("Data Wraith")
	var hero := _combatant("Hero")
	_res._player_party = [hero]
	_res._enemy_party = [wraith]
	var pierced: int = _cast_damage("phantom_byte", wraith, hero)

	## The comparison is against the SAME formula without the doubling, derived from the ability's own
	## multiplier rather than from a number typed here — so a change to the damage model moves both.
	var power: float = float(ab.get("power", ab.get("damage_multiplier", 1.0)))
	var probe := _combatant("Probe")
	var undoubled: int = int(wraith.get_buffed_stat("magic", wraith.magic) * power)
	var pb: int = probe.current_hp
	probe.take_damage(max(1, undoubled), true)
	var plain: int = pb - probe.current_hp
	gut.p("    phantom_byte: pierced=%d  same cast undoubled=%d  target defense=%d" % [pierced, plain, hero.defense])
	assert_gt(pierced, plain,
		"phantom_byte dealt %d, the same cast without the doubling deals %d — the armour it 'ghosts through' is still stopping it" % [pierced, plain])


func test_an_ability_without_the_key_is_unchanged() -> void:
	## A doubling applied unconditionally would double every magic cast in the game.
	var ab: Dictionary = _authored("fire")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_false(ab.has("ignores_defense"), "CONTROL: fire must author no ignores_defense")
	var caster := _combatant("Mage")
	var hero := _combatant("Hero")
	_res._player_party = [hero]
	_res._enemy_party = [caster]
	var power: float = float(ab.get("power", ab.get("damage_multiplier", 1.0)))
	var element: String = str(ab.get("element", ""))
	var expected_base: int = int(caster.get_buffed_stat("magic", caster.magic) * power)
	var elem_mod: float = hero.calculate_elemental_modifier(element) if element != "" else 1.0
	var probe := _combatant("Probe")
	var pb: int = probe.current_hp
	probe.take_damage(max(1, int(expected_base * elem_mod)), true)
	var undoubled: int = pb - probe.current_hp
	assert_eq(_cast_damage("fire", caster, hero), undoubled,
		"an ability authoring no ignores_defense must land at its plain multiplier")


func test_live_still_doubles_rather_than_bypassing() -> void:
	## The compensation is live's CHOICE, not the obvious implementation — a true-damage path would
	## bypass take_damage entirely. If live ever switches to that, doubling here becomes wrong.
	var live: String = GdSource.code_of(LIVE)
	assert_gt(live.length(), 50000, "CONTROL: BattleManager was actually read")
	var at: int = live.find("if ignores_defense:")
	assert_gt(at, 0, "CONTROL: live must still branch on it")
	assert_true(live.substr(at, 60).contains("damage *= 2"),
		"live no longer compensates by doubling — the grind mirrors the doubling and must follow whatever replaced it")
	var owner: int = live.substr(0, at).rfind("func _execute_")
	assert_true(live.substr(owner, 44).begins_with("func _execute_magic_ability"),
		"live reads ignores_defense outside the magic executor now — the grind doubles only there")


func test_the_unreachable_sibling_is_still_unreachable() -> void:
	## The declaration's own evidence, measured rather than remembered. `ignores_resistance` sits on the
	## next line of the same live block and is NOT wired; this reds if a grind can ever cast it.
	var abilities: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var monsters: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var es: Node = get_node_or_null("/root/EncounterSystem")
	if es == null or not ("enemy_pools" in es):
		pass_test("EncounterSystem unavailable")
		return
	var owners: Array = []
	for aid in abilities.keys():
		if bool((abilities[aid] as Dictionary).get("ignores_resistance", false)):
			owners.append(aid)
	assert_gt(owners.size(), 0, "CONTROL: abilities.json must still author ignores_resistance somewhere")
	var pooled: Dictionary = {}
	for region in es.enemy_pools.keys():
		for entry in es.enemy_pools[region]:
			pooled[str(entry.get("id", entry) if entry is Dictionary else entry)] = true
	var drawable: Array = []
	for mid in monsters.keys():
		if not pooled.has(mid):
			continue
		for aid in (monsters[mid] as Dictionary).get("abilities", []):
			if owners.has(aid):
				drawable.append("%s/%s" % [mid, aid])
	gut.p("    ignores_resistance owners: %s   grind-drawable casters: %s" % [str(owners), str(drawable)])
	assert_eq(drawable, [],
		"a pooled monster can now cast %s — ignores_resistance is reachable in a grind and the declaration is stale" % str(drawable))

	## ⛔ FORM 4, ADDED AFTER THIS ARM SHIPPED WITHOUT IT. `build_meta_boss_enemy_data` instantiates any
	## monster flagged `autogrind_spawned` straight out of monsters.json — so the pool check above is
	## not the whole question, and an arm that asked only it would go on passing if meta_knight ever
	## gained the flag. @cowir-cutscenes' rule is why this matters more than the omission looks: an
	## oracle that wrongly says UNREACHABLE passes an offender, so its errors have to fall toward
	## crying wolf, and mine fell the silencing way.
	var spawnable: Array = []
	for mid in monsters.keys():
		if not bool((monsters[mid] as Dictionary).get("autogrind_spawned", false)):
			continue
		for aid in (monsters[mid] as Dictionary).get("abilities", []):
			if owners.has(aid):
				spawnable.append("%s/%s" % [mid, aid])
	assert_eq(spawnable, [],
		"a monster the GRIND'S OWN SPAWNER instantiates can cast %s — reachable by form 4, which this arm did not check when the declaration was written" % str(spawnable))
	## And the form-4 mechanism must still be the one described, or the check above measures nothing.
	assert_gt(_autogrind_spawnable_count(monsters), 0,
		"no monster carries autogrind_spawned any more — form 4 reaches nothing and this check is vacuous rather than clean")
	## The second path, which a pool census alone would miss: this lane spawns meta-bosses itself.
	var sys_code: String = GdSource.code_of("res://src/autogrind/AutogrindSystem.gd")
	assert_gt(sys_code.length(), 5000, "CONTROL: AutogrindSystem was actually read")
	assert_true(sys_code.contains("_generate_meta_boss_name"),
		"the meta-boss is still procedurally NAMED rather than instantiated from a monsters.json id — if that changes, meta_knight could become spawnable and the declaration must be re-measured")


func test_the_resolver_reads_the_key_the_live_engine_reads() -> void:
	var code: String = GdSource.code_of(SRC)
	assert_gt(code.length(), 5000, "CONTROL: the resolver was actually read")
	assert_true(code.contains('ability.get("ignores_defense", false)'),
		"the resolver must read the same authored key live reads")
	assert_false(code.contains('ability.get("ignores_resistance"'),
		"the resolver wired ignores_resistance — no grind can cast it, so this adds a mechanism nothing exercises")


## Monsters the grind's own spawner can instantiate. A FLOOR for the form-4 check: if this is zero the
## check above is vacuous, and a vacuous unreachability check is precisely the silencing error.
func _autogrind_spawnable_count(monsters: Dictionary) -> int:
	var n := 0
	for mid in monsters.keys():
		if bool((monsters[mid] as Dictionary).get("autogrind_spawned", false)):
			n += 1
	return n


## FLOOR. Measured 2026-09-16: renaming a member this file reaches leaves it SILENT —
## e.g. pierces_what_it_pierces went Asserts 17 -> 15 at EC=0, Passing unchanged, no Risky.
## That is rung 3, which `.366`'s exit 4 cannot reach: the arms assert and THEN abort, so GUT
## scores them Passing. `get()` and `has_method()` ANSWER rather than raise — an existence arm
## written with a direct read aborts alongside the arms it exists to catch.
## ⚠️ THIS LIST IS A SNAPSHOT, NOT A DERIVATION, and that is the live limit. It was derived once by
## a script from this file's own `_res.` / AutogrindSystem reaches and then written as literals — so
## a member reached by a NEW arm added later is not covered, and the list goes quietly incomplete
## rather than loudly wrong. @cowir-cutscenes' rule puts it on the wrong side of the line: a figure
## the guard's claim DEPENDS on should be derived, and this is one.
## Deliberately not converted to a runtime derivation, per @cowir-sfx's reasoning: doing that needs
## @cowir-ai's bare-Object exclusion, because a runtime scan of this file would collect the `get` and
## `has_method` calls THIS ARM ITSELF makes and pin the mechanism it is written in. That is a real
## defence against a real hazard, and writing it tonight would be shipping it untested. Correct as of
## 2026-09-16; if you add an arm that reaches a new member, add it here or derive the set properly.
const _FLOOR_ARM_NAME := "test_every_resolver_member_this_file_reaches_still_exists"
const _PINNED_COUNT := 3

func test_every_resolver_member_this_file_reaches_still_exists() -> void:
	## @cowir-ai's counter to the snapshot limit above, and it converts the failure mode rather than
	## documenting it: a static list fails toward INCOMPLETENESS — add a reach tomorrow and the floor
	## silently covers all-but-one. This counts the distinct members reached in the text BEFORE this
	## function, so the arm cannot count its own `get`/`has_method` calls — @cowir-ai's bare-Object
	## exclusion replaced by SCOPING, which they named as the alternative. A new reach reds here.
	var own_src: String = FileAccess.get_file_as_string(get_script().resource_path)
	var cut: int = own_src.find("func %s(" % _FLOOR_ARM_NAME)
	assert_gt(cut, 0, "CONTROL: located this arm, so the scoped slice is real")
	var before: String = own_src.substr(0, cut)
	var reached: Dictionary = {}
	## ⛔ SKIP PATH LITERALS. `AutogrindSystem.gd` inside a res:// string matched as a member named
	## "gd" — the same false positive fixed in the generator and reintroduced here.
	for raw_line in before.split("\n"):
		if raw_line.contains("res://") or raw_line.strip_edges().begins_with("#"):
			continue
		for m in RegEx.create_from_string("(?:_res|AutogrindSystem)\\.([A-Za-z_][A-Za-z_0-9]*)").search_all(raw_line):
			reached[m.get_string(1)] = true
	reached.erase("_test_disable_persistence")
	reached.erase("PER_BATTLE_METAS")   ## read from SOURCE on purpose — see the arm above
	gut.p("    reaches before this arm: %d | pinned: %d" % [reached.size(), _PINNED_COUNT])
	assert_gt(reached.size(), 0, "CONTROL: the scan found reaches, or this count proves nothing")
	assert_eq(reached.size(), _PINNED_COUNT,
		"this file now reaches %d distinct members and the floor pins %d — add the new one, the list is a snapshot: %s" % [reached.size(), _PINNED_COUNT, str(reached.keys())])

	var missing: Array = []
	if _res.get("_enemy_party") == null: missing.append("_enemy_party")
	if _res.get("_player_party") == null: missing.append("_player_party")
	if not _res.has_method("_resolve_ability"): missing.append("_resolve_ability()")
	assert_eq(missing, [],
		"the resolver no longer has these, so the arms above would ABORT into a silent pass: %s" % str(missing))
