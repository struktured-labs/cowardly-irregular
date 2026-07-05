extends GutTest

## Finding guard (2026-07-05): physical/magic abilities apply their `effect`
## status ONLY when they author effect_chance > 0 — a deliberate "opt in
## explicitly" design (BattleManager ~line 4280; random_debuff is special-cased
## to default 1.0). So a damage ability that names an `effect` but omits
## effect_chance has an INERT effect: it deals damage but never applies the
## status its name implies (armor_break doesn't lower DEF, cursed_strike doesn't
## curse, ice_breath doesn't slow, etc.).
##
## 27 abilities are in that state today (mix of player + enemy). Whether each is
## a forgotten effect_chance or a deliberate WIP is a BALANCE call for the owner,
## so this test doesn't change anything — it SNAPSHOTS the set so a NEW ability
## can't silently join it (add effect_chance to activate the effect, or add the
## id here to acknowledge it's intentionally inert). Surfaces the whole set in
## one place for review.

const KNOWN_INERT := [
	"acid_splash", "acid_spray", "armor_break", "cascade_failure", "chill",
	"corrode", "corruption_wave", "cursed_strike", "death_sentence",
	"disease_cloud", "fester", "filth_spray", "final_death", "hollow_echo",
	"ice_breath", "memory_leak", "null_field", "null_touch", "oxidize",
	"permakill_strike", "rending_bite", "soul_wail", "spectral_touch",
	"stack_smash", "static_field", "subset_drain", "void_breath",
]


func test_no_new_ability_silently_gets_an_inert_effect() -> void:
	var abilities = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	assert_eq(typeof(abilities), TYPE_DICTIONARY, "abilities.json must parse")
	var known := {}
	for id in KNOWN_INERT:
		known[id] = true

	var new_inert: Array[String] = []
	for aid in abilities:
		var ab = abilities[aid]
		if typeof(ab) != TYPE_DICTIONARY:
			continue
		var t := str(ab.get("type", ""))
		var eff := str(ab.get("effect", ""))
		# physical/magic ability, names a real status effect, no effect_chance,
		# and not random_debuff (which the engine defaults to 1.0).
		if t in ["physical", "magic"] and eff != "" and eff != "random_debuff" \
				and not ab.has("effect_chance") and not known.has(aid):
			new_inert.append(aid)

	assert_eq(new_inert.size(), 0,
		"new damage ability(s) name an 'effect' but omit effect_chance, so the status is INERT " +
		"(opt-in design). Add effect_chance to activate it, or add the id to KNOWN_INERT: %s" % str(new_inert))
