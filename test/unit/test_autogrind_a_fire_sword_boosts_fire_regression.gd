extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const GRIND := "res://src/autogrind/HeadlessBattleResolver.gd"

## flame_sword authors fire_damage_bonus 1.5, and a grinding Mage casting fire got none of it.
## Live applies it in _execute_magic_ability (:5089); this file's magic arm did not.
##
## 🔑 THE DERIVED-KEY SHAPE, and the reason I retracted a wrong finding about these five keys last
## night: live builds the key by CONCATENATION — `element + "_damage_bonus"` — so four of the five
## occur ZERO times in src/ and a literal census reports them inert. @cowir-battle's third shape.
##
## ⚠️ WHAT IS **NOT** A GAP, measured rather than assumed, because the neighbouring keys look
## identical: `fire_resistance` / `dark_resistance` are consumed by Combatant.take_elemental_damage,
## which live calls ONLY from _tick_summon_followup — a summon path already declared in the parity
## ledger. Both engines' magic arms call calculate_elemental_modifier, which does NOT consult
## equipment resistance (Combatant:914-928 vs :929-985). So the two engines already agree there, and
## wiring resistance into this arm would make the grind resist where the real game does not.
##
## ⚠️ AND THE PHYSICAL PATH IS DELIBERATE IN BOTH ENGINES: BattleManager:4880 records that a weapon
## strike's element is flavour by construction, and cites THIS FILE as its corroboration. Not a gap.

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _caster(name: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 9999, "max_mp": 9999,
		"attack": 30, "defense": 10, "magic": 60, "speed": 10})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	return c


func _target(name: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 999999, "max_mp": 0,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	return c


## Median damage of a fire spell, so the per-cast roll cannot decide the comparison.
func _median_cast(caster: Combatant, ability_id: String, n: int) -> float:
	var rolls: Array = []
	for i in n:
		var t := _target("T")
		_res._player_party = [caster]
		_res._enemy_party = [t]
		caster.current_mp = caster.max_mp
		_res._resolve_ability(caster, ability_id, [t])
		var dealt: int = t.max_hp - t.current_hp
		if dealt > 0:
			rolls.append(dealt)
	rolls.sort()
	return float(rolls[rolls.size() / 2]) if rolls.size() > 0 else 0.0


func test_the_sword_and_the_spell_are_still_authored_as_this_arm_assumes() -> void:
	var eq: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment.json"))
	var sword: Dictionary = (eq.get("weapons", {}) as Dictionary).get("flame_sword", {})
	assert_almost_eq(float((sword.get("special_effects", {}) as Dictionary).get("fire_damage_bonus", 0.0)), 1.5, 0.001,
		"flame_sword no longer authors fire_damage_bonus 1.5 — the band below is derived from it")
	var ab: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var fire: Dictionary = ab.get("fire", {})
	assert_eq(str(fire.get("element", "")), "fire",
		"`fire` is no longer a fire-element ability — this arm needs an element-carrying magic spell")
	assert_eq(str(fire.get("type", "")), "magic",
		"`fire` is no longer magic-typed — the bonus is applied on the MAGIC path only")


func test_a_flame_sword_boosts_a_fire_spell() -> void:
	var armed := _caster("Armed")
	armed.equipped_weapon = "flame_sword"
	var bare := _caster("Bare")
	var with_sword: float = _median_cast(armed, "fire", 90)
	var without: float = _median_cast(bare, "fire", 90)
	gut.p("    fire spell — flame_sword %.0f · bare %.0f (expect ~1.5x)" % [with_sword, without])
	assert_gt(without, 0.0, "CONTROL: the spell must land damage, or the ratio is meaningless")
	assert_gt(with_sword, without * 1.25,
		"a flame_sword did not boost a fire spell — live multiplies by element + \"_damage_bonus\" at :5089 and the grind's magic arm was not reading it")


func test_the_bonus_multiplies_rather_than_adding() -> void:
	## ⛔ THE ARM THAT PINS THE ARITHMETIC. Live writes `multiplier *= elem_bonus`, so 1.5 is a 1.5x
	## SCALE. Reading it as +150% (x2.5) also "boosts fire" and would pass the arm above — the two
	## differ by 67% of the spell's damage, which is a balance change wearing a fix's clothes.
	var armed := _caster("Armed")
	armed.equipped_weapon = "flame_sword"
	var bare := _caster("Bare")
	var with_sword: float = _median_cast(armed, "fire", 90)
	var without: float = _median_cast(bare, "fire", 90)
	var ratio: float = with_sword / maxf(without, 1.0)
	gut.p("    ratio %.2f (1.5 = multiply · 2.5 = the additive misreading)" % ratio)
	assert_lt(ratio, 2.0,
		"the element bonus is being ADDED rather than multiplied — live's `multiplier *= elem_bonus` makes 1.5 a 1.5x scale, not +150%%")


func test_an_element_less_spell_gets_nothing() -> void:
	## Live skips the lookup entirely when the ability carries no element — "no fire scroll, no fire
	## bonus". Without that gate the sword would boost every spell the Mage owns.
	var ab: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var elementless: String = ""
	for id in ab:
		var d: Dictionary = ab[id]
		if str(d.get("type", "")) == "magic" and str(d.get("element", "")) == "" and not d.has("hits"):
			elementless = str(id)
			break
	assert_ne(elementless, "", "CONTROL: an element-less magic ability must exist, or this arm is vacuous")
	var armed := _caster("Armed")
	armed.equipped_weapon = "flame_sword"
	var bare := _caster("Bare")
	var with_sword: float = _median_cast(armed, elementless, 90)
	var without: float = _median_cast(bare, elementless, 90)
	gut.p("    element-less `%s` — flame_sword %.0f · bare %.0f (must match)" % [elementless, with_sword, without])
	assert_almost_eq(with_sword, without, maxf(without * 0.08, 1.0),
		"a flame_sword boosted an ELEMENT-LESS spell — live gates the lookup on `element != \"\"`")


func test_every_authored_element_bonus_lands_on_its_own_element() -> void:
	## ⛔ THE CORPUS ARM, added after the fact because the arms above exercise ONE of five elements.
	## The key is CONSTRUCTED (`element + "_damage_bonus"`), so a hardcoded `"fire_damage_bonus"`
	## satisfies every fire assertion in this file and silently drops ice, holy, lightning and dark.
	## The census catches that exact mutation by source — its empty-promise arm reds when the
	## construction string disappears — but a source check cannot see an element computed WRONGLY,
	## and only a behavioural sweep over the whole authored set can. @cowir-ai's "the corpus was my
	## intent", one layer over: my corpus was the one element I happened to name in the file title.
	##
	## ⚠️ bone_staff authors 1.3 where the other four author 1.5, so this also reds on a hardcoded
	## magnitude — the authored value is read per piece rather than assumed uniform.
	var eq: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/equipment.json"))
	var ab: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	## every gear piece that authors an <element>_damage_bonus, derived not listed
	var pieces: Array = []
	for cat in eq:
		if typeof(eq[cat]) != TYPE_DICTIONARY:
			continue
		for item_id in (eq[cat] as Dictionary):
			var d: Variant = (eq[cat] as Dictionary)[item_id]
			if typeof(d) != TYPE_DICTIONARY:
				continue
			var se: Variant = (d as Dictionary).get("special_effects", {})
			if typeof(se) != TYPE_DICTIONARY:
				continue
			for k in (se as Dictionary):
				if str(k).ends_with("_damage_bonus"):
					pieces.append([str(item_id), str(k).trim_suffix("_damage_bonus"), float((se as Dictionary)[k])])
	assert_gt(pieces.size(), 3, "CONTROL: equipment.json must author several element bonuses, or this sweep is vacuous")
	var missed: Array = []
	var seen: Array = []
	for row in pieces:
		var item_id: String = str(row[0])
		var element: String = str(row[1])
		var authored: float = float(row[2])
		## a magic ability of that element, single-target, no multi-hit
		var spell: String = ""
		for aid in ab:
			var a: Dictionary = ab[aid]
			if str(a.get("type", "")) == "magic" and str(a.get("element", "")) == element and not a.has("hits"):
				spell = str(aid)
				break
		if spell == "":
			continue  ## no spell of that element to drive it; not this arm's failure to report
		var armed := _caster("Armed_%s" % element)
		armed.equipped_weapon = item_id
		var bare := _caster("Bare_%s" % element)
		var with_gear: float = _median_cast(armed, spell, 60)
		var without: float = _median_cast(bare, spell, 60)
		var ratio: float = with_gear / maxf(without, 1.0)
		seen.append("%s/%s %.2fx (authored %.2f)" % [element, spell, ratio, authored])
		## band is wide enough for the per-cast roll and narrow enough to separate 1.3 from 1.5
		if absf(ratio - authored) > 0.18:
			missed.append("%s via %s: authored %.2f, measured %.2f" % [element, item_id, authored, ratio])
	gut.p("    %s" % str(seen))
	assert_gt(seen.size(), 2, "CONTROL: at least three elements must actually have been driven, or a green says nothing")
	assert_eq(missed, [],
		"an authored element bonus did not land at its authored strength — a constructed key that works for one element and not the others: %s" % str(missed))


func test_equipment_resistance_is_still_absent_on_purpose() -> void:
	## ⚠️ THE NEIGHBOURING KEYS, declared rather than wired. fire_resistance/dark_resistance are read
	## by Combatant.take_elemental_damage, which live calls only from _tick_summon_followup. Both
	## engines' magic arms use calculate_elemental_modifier, which does not consult them — so the
	## engines AGREE today, and wiring them here would make the grind resist where the game does not.
	var code: String = GdSource.code_of(GRIND)
	assert_true(code.contains("calculate_elemental_modifier"),
		"the grind's magic arm no longer uses calculate_elemental_modifier — if it moved to take_elemental_damage, equipment resistance is now in play and this declaration is stale")
	assert_false(code.contains("take_elemental_damage"),
		"the resolver now calls take_elemental_damage, which DOES consult equipment resistance — the two engines' element paths have diverged and this note needs re-deriving")
	var combatant: String = GdSource.code_of("res://src/battle/Combatant.gd")
	assert_true(combatant.contains("_has_equipment_resistance"),
		"CONTROL: Combatant still carries the equipment-resistance reader this declaration is about")
