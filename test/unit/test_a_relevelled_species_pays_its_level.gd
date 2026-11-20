extends GutTest

## cowir-battle 26350: a re-levelled spawn's EXP was linear in level, so an L1 slime @15 paid 225 beside a goblin's 124 and
## plains slimes became W1's best grind. A spawn now keeps its share of its OWN level's median reward, at the target level's median.

const LEVELS := [13, 15, 18, 20, 23]
const SPREAD_LOW := 0.75
const SPREAD_HIGH := 1.3

var _es: Node


func before_each() -> void:
	_es = get_tree().root.get_node_or_null("EncounterSystem")


## Ordinary catalog species the bands are read from, with a reward of their own.
func _species() -> Array:
	var out: Array = []
	for id in _es.monster_database:
		var row: Variant = _es.monster_database[id]
		if not (row is Dictionary) or row.get("boss", false) or row.get("miniboss", false) or row.get("field_elite", false):
			continue
		var lv := int(row.get("level", 0))
		if lv >= 1 and lv <= _es.BAND_TOP_LEVEL and int(row.get("exp_reward", 0)) > 0:
			out.append(str(id))
	out.sort()
	return out


func _median(vals: Array) -> float:
	vals.sort()
	var mid := vals.size() / 2
	return float(vals[mid]) if vals.size() % 2 == 1 else (float(vals[mid - 1]) + float(vals[mid])) / 2.0


func test_the_floor_names_what_this_file_drives() -> void:
	assert_not_null(_es, "FLOOR: the EncounterSystem autoload")
	for m in ["apply_spawn_level", "spawn_pay_ratio", "native_bands", "band_at", "_create_enemy_data"]:
		assert_true(_es.has_method(m), "FLOOR: EncounterSystem.%s" % m)
	assert_gt(_species().size(), 10, "FLOOR: the catalog has ordinary species to re-level")
	assert_true(_es.monster_database.has("slime") and int(_es.monster_database["slime"].get("level", 0)) == 1, "FLOOR: the slime is the catalog's L1")


## THE DEFECT: at one level no species pays far from the rest. Linear pay put the slime at 1.76x the median.
func test_at_one_level_no_species_out_pays_the_rest() -> void:
	var bad: Array = []
	var judged := 0
	for lv in LEVELS:
		var pays := {}
		for id in _species():
			if int(_es.monster_database[id].get("level", 0)) == lv:
				continue
			pays[id] = int(_es._create_enemy_data("%s@L%d" % [id, lv]).get("exp_reward", 0))
		var med := _median(pays.values())
		assert_gt(med, 0.0, "CONTROL @L%d: the re-levelled species pay something" % lv)
		for id in pays:
			judged += 1
			var share := float(pays[id]) / med
			if share < SPREAD_LOW or share > SPREAD_HIGH:
				bad.append("%s@L%d pays %d, %.2fx the median %d" % [id, lv, pays[id], share, int(med)])
	assert_gt(judged, 0, "CONTROL: species were judged")
	assert_eq(bad, [], "a level's species pay alike:\n%s" % "\n".join(PackedStringArray(bad)))


## CONTROL that the pay still climbs: a higher level always pays more, for the slime and for a mid species.
func test_a_higher_level_still_pays_more() -> void:
	for id in ["slime", "goblin"]:
		var last := int(_es._create_enemy_data(id).get("exp_reward", 0))
		assert_gt(last, 0, "CONTROL: the catalog %s pays" % id)
		for lv in LEVELS:
			var now := int(_es._create_enemy_data("%s@L%d" % [id, lv]).get("exp_reward", 0))
			assert_gt(now, last, "%s@L%d pays more than the level below it" % [id, lv])
			last = now


## The W1 tiers hand into W2: a top-tier spawn pays in the range of W2's own first monsters, not a cliff either way.
func test_the_top_tier_pays_like_the_world_it_leads_into() -> void:
	var w2: Array = []
	for id in _es.monster_database:
		var row: Variant = _es.monster_database[id]
		if row is Dictionary and not row.get("boss", false) and not row.get("miniboss", false) and int(row.get("level", 0)) in [25, 26]:
			w2.append(int(row.get("exp_reward", 0)))
	assert_gt(w2.size(), 0, "FLOOR: the catalog has ordinary L25-26 rows")
	var native := _median(w2)
	var goblin := float(_es._create_enemy_data("goblin@L23").get("exp_reward", 0))
	gut.p("    goblin@L23 pays %d; W2's L25-26 median is %d" % [int(goblin), int(native)])
	assert_between(goblin, native * 0.7, native * 1.15, "an L23 goblin pays near, and not above, a native L25-26")


## Gold rides the same rule, so the slime is not the best purse either.
func test_gold_keeps_its_share_too() -> void:
	var slime := float(_es._create_enemy_data("slime@L15").get("gold_reward", 0))
	var goblin := float(_es._create_enemy_data("goblin@L15").get("gold_reward", 0))
	assert_gt(goblin, 0.0, "CONTROL: a re-levelled goblin carries gold")
	assert_between(slime / goblin, SPREAD_LOW, SPREAD_HIGH, "slime@L15 gold %d vs goblin@L15 %d" % [int(slime), int(goblin)])
