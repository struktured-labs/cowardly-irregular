extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const GRIND := "res://src/autogrind/HeadlessBattleResolver.gd"

## THE LARGEST OPEN ITEM IN THIS LANE, AND UNTIL NOW ITS ONLY RECORD WAS A COMMENT.
## A grinding party gets ZERO of its equipped passives. The measurement has existed for weeks in one
## prose line inside _resolve_ability (HeadlessBattleResolver:998), guarded by nothing and read by
## nobody who had not already opened that function.
##
## @cowir-sfx and @cowir-music both measured the same gap in their own lanes tonight: their open
## asks to struktured appeared in ZERO tag notes, so "awaiting his ruling" was false in the way that
## matters — he was never asked where he reads. Mine differs only in that I DID ask, repeatedly, and
## did not RECORD. A conversation is not a durable record, and the other two decisions this lane is
## holding (`recoil_pct`, `meta_effect`) are DECLARED entries with arms behind them while this one —
## the biggest — had the weakest home of the three.
##
## ⚠️ THE COUNT IS PRINTED, NEVER ASSERTED. Pinning "45" would be a coincidental-value ratchet:
## authoring a 46th passive is a correct change and must not red. What IS pinned is the SET of
## stat_mods keys, so a NEW KIND of modifier arrives named rather than silently widening the ask.

## Struktured's call, recorded where the next reader is. @cowir-battle's discriminator.
const DECIDER := "Model a passive when it moves the EXPECTATION of what the grind reports; declare it when it only moves the SPREAD. The answer decides how much of the passive system the resolver must mirror, which is why this is unscoped rather than backlogged."

## The 12 distinct stat_mods keys authored today. A thirteenth means the ask got bigger.
const KNOWN_STAT_MODS := [
	"attack_multiplier", "crit_chance", "crit_damage_bonus", "defense_multiplier",
	"evasion", "healing_multiplier", "magic_multiplier", "max_hp_multiplier",
	"max_mp_multiplier", "mp_cost_multiplier", "speed_multiplier", "steal_chance",
]


func _passives() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string("res://data/passives.json")
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = {}
	for k in (parsed as Dictionary):
		var v: Variant = (parsed as Dictionary)[k]
		if typeof(v) != TYPE_DICTIONARY:
			continue
		if (v as Dictionary).has("stat_mods") or (v as Dictionary).has("meta_effects") or (v as Dictionary).has("description"):
			out[k] = v
		else:
			for k2 in (v as Dictionary):
				var v2: Variant = (v as Dictionary)[k2]
				if typeof(v2) == TYPE_DICTIONARY:
					out[k2] = v2
	return out


func test_the_gap_is_still_the_size_it_is_declared_to_be() -> void:
	var p: Dictionary = _passives()
	assert_gt(p.size(), 20, "CONTROL: passives.json must actually parse, or every zero below is vacuous")
	var mods: Dictionary = {}
	for v in p.values():
		var s: Variant = (v as Dictionary).get("stat_mods")
		if typeof(s) == TYPE_DICTIONARY:
			for k in (s as Dictionary):
				mods[k] = true
	gut.p("    %d passives authored · %d distinct stat_mods keys · 0 modelled in the grind" % [p.size(), mods.size()])
	var unnamed: Array = []
	for k in mods:
		if not KNOWN_STAT_MODS.has(k):
			unnamed.append(k)
	assert_eq(unnamed, [],
		"a NEW KIND of passive modifier is authored and not named here, so the open question just got bigger without anyone saying so: %s" % str(unnamed))


func test_the_grind_still_models_none_of_them() -> void:
	## ⛔ THE ARM THAT RETIRES THIS FILE. It reds the day somebody wires passives into the resolver —
	## which means the ruling was made and this note is stale, not that anything broke. Read through
	## GdSource so the prose at :998 describing the gap cannot be mistaken for code closing it.
	var code: String = GdSource.code_of(GRIND)
	assert_gt(code.length(), 10000, "CONTROL: the resolver was actually read")
	var reads: Array = []
	for probe in ["PassiveSystem", "stat_mods", "get_passive_mods", "equipped_passives"]:
		if code.contains(probe):
			reads.append(probe)
	assert_eq(reads, [],
		"the resolver now reads passives — the scoping call was answered, so retire this file and move the entry into the parity ledger's closed set: %s" % str(reads))


func test_the_decision_is_recorded_with_its_decider() -> void:
	## A bare "unscoped" rots into "nobody remembers why". The rule that would settle it is the
	## durable half, not the status.
	assert_gt(DECIDER.length(), 80,
		"the decider must state the RULE that settles this, not merely that it is open")
	assert_true(DECIDER.contains("EXPECTATION") and DECIDER.contains("SPREAD"),
		"the decider is @cowir-battle's expectation-vs-spread rule; if it has been replaced, say by what")
