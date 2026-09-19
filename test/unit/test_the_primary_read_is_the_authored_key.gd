extends GutTest

## cowir-main, .448: `ability.get("power", ability.get("damage_multiplier", …))` reads as
## "power is the field, damage_multiplier is legacy" and the truth is exactly reversed —
## NOTHING authors `power`. Three sites across both engines, and the fallback is the only
## live read. A cleanup that deletes "the legacy fallback" zeroes every damage number.
##
## This pins the RELATIONSHIP, not the counts: whichever key the data authors must be the
## one the code reads FIRST. Both directions matter —
##   author `power` on an ability and the primary wakes up, silently changing damage for
##   anything carrying both;
##   drop `damage_multiplier` and the fallback stops resolving.
## Either way this arm names the key instead of the number moving unexplained.
##
## ⚠️ FOUR SITES, AND THEY ARE NOT ALL THE SAME SHAPE. Three read `power` first (inverted).
## BattleManager.estimate_ability_breakdown already reads `damage_multiplier` first and records
## the measurement in its own comment (0 of 288) — found independently for Formula Sight's
## preview. It also divides `power` by 10 and multiplies the result by 10, so it treats the two
## keys as different SCALES where the other three treat them as aliases. Precedence and units
## are separate questions: do not unify the sites by copying one expression into the others.
##
## My first sweep found 3 of the 4 — the pattern required the nested get to follow the comma
## directly, and a wrapping float() hid the fixed one. The site that already had the answer is
## the one the corpus missed.
##
## Corpus is BOTH producers. `abilities.json` is the obvious one; JobSystem's
## _create_default_abilities is a hardcoded table used when the file is absent, and a
## corpus of the JSON alone would not have contained it.

const ABILITIES_JSON := "res://data/abilities.json"
const JOBSYSTEM_SRC := "res://src/jobs/JobSystem.gd"
const RESOLVER_SRC := "res://src/autogrind/HeadlessBattleResolver.gd"
const BATTLEMANAGER_SRC := "res://src/battle/BattleManager.gd"

## The read as it appears in both engines, primary first.
const POWER_READ := 'ability.get("power", ability.get("damage_multiplier"'


func _authored_counts() -> Dictionary:
	var f := FileAccess.open(ABILITIES_JSON, FileAccess.READ)
	assert_not_null(f, "CONTROL: abilities.json must be readable")
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_true(parsed is Dictionary, "CONTROL: abilities.json must parse to a Dictionary")
	var root: Dictionary = parsed
	var abilities: Dictionary = root.get("abilities", root)
	var out := {"power": 0, "damage_multiplier": 0, "total": 0}
	for id in abilities:
		var a: Variant = abilities[id]
		if not (a is Dictionary):
			continue
		out["total"] = int(out["total"]) + 1
		if a.has("power"):
			out["power"] = int(out["power"]) + 1
		if a.has("damage_multiplier"):
			out["damage_multiplier"] = int(out["damage_multiplier"]) + 1
	return out


func test_the_authored_key_is_damage_multiplier_not_power() -> void:
	var c := _authored_counts()
	assert_gt(int(c["total"]), 100,
		"CONTROL: the corpus must be the real ability table, not an empty parse")
	assert_gt(int(c["damage_multiplier"]), 0,
		"damage_multiplier is the key both engines actually resolve through — if nothing " +
		"authors it, the fallback stops resolving and every damage read takes its default")
	assert_eq(int(c["power"]), 0,
		"an ability now authors `power`, which BOTH engines read BEFORE damage_multiplier. " +
		"Anything carrying both silently changes damage. Either stop authoring it, or swap " +
		"the read order at HeadlessBattleResolver and BattleManager so the authored key is first")


func test_the_hardcoded_fallback_table_agrees_with_the_file() -> void:
	## JobSystem._create_default_abilities is the SECOND producer, used when the JSON is
	## absent. A corpus of the file alone misses it, which is how this sweep nearly ended
	## one producer short.
	var src := FileAccess.get_file_as_string(JOBSYSTEM_SRC)
	var at: int = src.find("func _create_default_abilities")
	assert_gt(at, -1, "CONTROL: the hardcoded ability table must still exist")
	var next: int = src.find("\nfunc ", at + 10)
	var body: String = src.substr(at, next - at) if next > at else src.substr(at)
	assert_true(body.contains('"damage_multiplier"'),
		"the hardcoded table stopped authoring damage_multiplier — the engines read it second " +
		"and would fall through to the default for every ability it defines")
	assert_false(body.contains('"power"'),
		"the hardcoded table now authors `power`, which both engines read FIRST — the same " +
		"inversion this file exists to catch, arriving from the producer nobody checks")


func test_both_engines_still_read_damage_multiplier_at_all() -> void:
	## If someone deletes the "legacy" fallback, this is the arm that says what it cost.
	for path in [RESOLVER_SRC, BATTLEMANAGER_SRC]:
		var src := FileAccess.get_file_as_string(path)
		assert_true(src.contains('ability.get("damage_multiplier"'),
			"%s no longer reads damage_multiplier anywhere. Nothing authors `power`, so the " % path +
			"remaining read resolves to its default for all 161 abilities that carry it")
