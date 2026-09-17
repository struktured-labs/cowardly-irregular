extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const GRIND := "res://src/autogrind/HeadlessBattleResolver.gd"

## THE SECOND PARITY AXIS, and it exists because my FIRST one cannot see it.
## test_autogrind_parity_gap_is_named_regression censuses `abilities.json`'s 70 top-level keys. Gear
## carries its own battle behaviour in `equipment.json` -> `special_effects`, and NONE of those keys
## appears in abilities.json — so every one of them is invisible to that ledger's ratchet, which is
## the arm whose whole job is "a new divergence announces itself". It announced nothing for fifteen
## keys because they were never in its corpus.
##
## Found via @cowir-battle's resist_ring fix: `status_resistance` had one reader, on the ATTACKER's
## on-hit path, so the ring protected a player only from their own poison_dagger. Their repair is
## live-side. The grind-side question their finding raises is this file: a grinding party's GEAR does
## nothing at all, so the grind reports survivability and rewards for a party wearing no equipment
## effects — measured, it reads 0 of 15.
##
## ⚠️ INSTRUMENT, STATED, and it cost me two wrong answers before this one.
##   (1) My first corpus was BattleManager + the resolver, TWO FILES. `fire_damage_bonus` and
##       `fire_resistance` are named in EquipmentSystem.gd, so that corpus called them "dead in both
##       engines" — a claim about a file I had not looked in. Corpus is now ALL of src/.
##   (2) Widening it then produced the opposite error: EquipmentSystem holds a HARDCODED FALLBACK
##       COPY of equipment.json, so the same two keys read as CONSUMED. A data copy in a .gd file is
##       indistinguishable from a consumer to a text search. CLAUDE.md documents this exact shape for
##       `autobattle_advanced`. The discriminator below is structural: a line of the form
##       `"key": value` is a dict-literal ENTRY, never a read.

## Real live behaviour the grind does not model. Each is read in BattleManager through
## _sum_equipment_special_effect or an equivalent lookup, verified line by line rather than by count.
## This set may SHRINK freely — that is someone closing a gap — but it may not GROW unnamed.
const GRIND_IGNORES := [
	"critical_bonus", "evasion_bonus", "exp_while_dead", "familiar_weight_bonus",
	"poison_chance", "sleep_chance", "status_resistance", "steal_bonus",
]

## Authored on gear a player can buy or find, and consumed by NOTHING anywhere in src/. Not a grind
## gap — a live one, and the same class as the resist_ring: an authored number with no reader.
## Pinned so that wiring one reds here and is noticed, rather than silently leaving this list wrong.
const INERT_EVERYWHERE := [
	"dark_damage_bonus", "dark_resistance", "fire_damage_bonus", "fire_resistance",
	"holy_damage_bonus", "ice_damage_bonus", "lightning_damage_bonus",
]

## Assessed and deliberately not modelled. Empty today and kept so the next reader has somewhere to
## put a reason instead of deleting an entry from the list above.
const DECLARED := {}

## ⛔ KEYS AUTHORED IN BOTH CORPORA, WITH THE OWNER NAMED. The disjointness arm below found this on
## its first run, and it is the precise failure it was written to describe: `evasion_bonus` is an
## abilities.json key AND a gear special_effect, and the abilities ledger had already parked it in
## UNDECIDED_LIVE_SIDE for the reason "read off equipment rather than the ability" — correctly
## identifying that it did not own the key, at a time when no equipment census existed to pick it up.
## So it belonged to nobody. It belongs HERE: the read is equipment-side, and it is in GRIND_IGNORES.
const OVERLAP_OWNED := {
	"evasion_bonus": "read off EQUIPMENT, not off the ability — the abilities ledger parks it in UNDECIDED_LIVE_SIDE for exactly that reason, so this file owns it and lists it in GRIND_IGNORES",
}


func _authored_effect_keys() -> Array:
	var raw: String = FileAccess.get_file_as_string("res://data/equipment.json")
	var eq: Dictionary = JSON.parse_string(raw)
	var keys: Dictionary = {}
	for v in eq.values():
		if typeof(v) != TYPE_DICTIONARY:
			continue
		var se: Variant = (v as Dictionary).get("special_effects")
		if typeof(se) == TYPE_DICTIONARY:
			for k in (se as Dictionary):
				keys[k] = true
		else:
			for v2 in (v as Dictionary).values():
				if typeof(v2) != TYPE_DICTIONARY:
					continue
				var se2: Variant = (v2 as Dictionary).get("special_effects")
				if typeof(se2) == TYPE_DICTIONARY:
					for k2 in (se2 as Dictionary):
						keys[k2] = true
	var out: Array = keys.keys()
	out.sort()
	return out


func _gd_files() -> Array:
	var found: Array = []
	var stack: Array = ["res://src"]
	while not stack.is_empty():
		var dir: String = str(stack.pop_back())
		var d := DirAccess.open(dir)
		if d == null:
			continue
		d.list_dir_begin()
		var name := d.get_next()
		while name != "":
			var full: String = "%s/%s" % [dir, name]
			if d.current_is_dir():
				stack.append(full)
			elif name.ends_with(".gd"):
				found.append(full)
			name = d.get_next()
		d.list_dir_end()
	return found


## A CONSUMER names the key somewhere other than a dict-literal entry or a comment. `"key": value` is
## data; `get("key")` is a read. This is the discriminator the two-file corpus did not have.
func _consumer_lines(key: String, files: Array) -> Array:
	var quoted: String = '"%s"' % key
	var hits: Array = []
	for f in files:
		var code: String = GdSource.code_of(str(f))
		if not code.contains(quoted):
			continue
		for line in code.split("\n"):
			if not line.contains(quoted):
				continue
			var t: String = line.strip_edges()
			if t.begins_with("#"):
				continue
			if RegEx.create_from_string('^"%s"\\s*:' % key).search(t) != null:
				continue   ## a dict-literal entry: DATA, not a read
			hits.append("%s: %s" % [str(f).get_file(), t.substr(0, 70)])
	return hits


func test_the_sweep_actually_reads_the_tree() -> void:
	## CONTROL. Every arm below fires on a ZERO, and a zero is what an empty corpus looks like too.
	var files: Array = _gd_files()
	gut.p("    swept %d .gd files under res://src" % files.size())
	assert_gt(files.size(), 50, "CONTROL: the walk must find the source tree, or every 'nothing reads this' below is vacuous")
	var probe: Array = _consumer_lines("status_resistance", files)
	assert_gt(probe.size(), 0, "CONTROL: a key with a KNOWN reader must be found by this instrument, or its zeroes mean nothing")


func test_every_authored_gear_effect_is_named_here() -> void:
	## The ratchet, and the reason this file exists: the abilities ledger's equivalent arm could never
	## fire on these, because equipment.json is not in its corpus.
	var known: Dictionary = {}
	for k in GRIND_IGNORES:
		known[k] = true
	for k in INERT_EVERYWHERE:
		known[k] = true
	for k in DECLARED:
		known[k] = true
	var authored: Array = _authored_effect_keys()
	assert_gt(authored.size(), 10, "CONTROL: equipment.json must actually yield special_effects keys")
	var unnamed: Array = []
	for k in authored:
		if not known.has(k):
			unnamed.append(k)
	gut.p("    authored gear effects: %d | grind ignores: %d | inert: %d" % [authored.size(), GRIND_IGNORES.size(), INERT_EVERYWHERE.size()])
	assert_eq(unnamed, [],
		"a gear effect is authored and named nowhere in this file: %s — add it to GRIND_IGNORES, INERT_EVERYWHERE, or DECLARED with a reason" % str(unnamed))


func test_the_inert_ones_really_have_no_consumer_anywhere() -> void:
	## A live finding, kept honest. If someone wires one of these, this reds and the entry moves —
	## which is the point: the list must not quietly become wrong in the direction of "still broken".
	var files: Array = _gd_files()
	var now_consumed: Array = []
	for k in INERT_EVERYWHERE:
		var hits: Array = _consumer_lines(k, files)
		if not hits.is_empty():
			now_consumed.append("%s <- %s" % [k, hits[0]])
	assert_eq(now_consumed, [],
		"a gear effect listed as consumed by nothing now has a reader — move it out of INERT_EVERYWHERE: %s" % str(now_consumed))


func test_the_grind_side_gap_is_real_and_not_a_bad_pattern() -> void:
	## The grind reads none of the 15. That is a ZERO, which this file's own instrument note calls the
	## trustworthy direction — but only once the CONTROL above has shown the pattern can match.
	var grind: String = GdSource.code_of(GRIND)
	assert_gt(grind.length(), 10000, "CONTROL: the resolver was actually read")
	var modelled: Array = []
	for k in GRIND_IGNORES:
		if grind.contains('"%s"' % k):
			modelled.append(k)
	gut.p("    gear effects the grind now models: %s" % str(modelled))
	assert_true(modelled.size() < GRIND_IGNORES.size(),
		"every gear effect is modelled in the grind now — retire this list deliberately rather than leaving it asserting nothing")


func test_this_axis_is_invisible_to_the_abilities_ledger() -> void:
	## ⛔ THE ARM THAT JUSTIFIES A SECOND FILE. If a gear key ever also appeared in abilities.json, the
	## two censuses would overlap and each could assume the other covered it. They are disjoint today,
	## which is exactly why the abilities ratchet stayed green through fifteen unmodelled keys.
	var ab: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var ability_keys: Dictionary = {}
	for a in ab.values():
		for k in (a as Dictionary):
			ability_keys[k] = true
	assert_gt(ability_keys.size(), 50, "CONTROL: abilities.json keys were actually collected")
	var unnamed: Array = []
	var overlap: Array = []
	for k in _authored_effect_keys():
		if ability_keys.has(k):
			overlap.append(k)
			if not OVERLAP_OWNED.has(k):
				unnamed.append(k)
	gut.p("    ability keys: %d | gear effect keys: %d | overlap: %s" % [ability_keys.size(), _authored_effect_keys().size(), str(overlap)])
	assert_eq(unnamed, [],
		"a key is authored in BOTH corpora and neither census claims it, so each may assume the other owns it: %s" % str(unnamed))
	assert_gt(OVERLAP_OWNED.size(), 0,
		"the overlap has emptied — if no key is shared any more, delete OVERLAP_OWNED deliberately rather than leaving it asserting nothing")
