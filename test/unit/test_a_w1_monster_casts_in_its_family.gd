extends GutTest

## main 23993: the W1 monster FAMILY table. Every non-physical ability a monster of level 12 or under can use either plays
## a sequence (its family's, or the Mage's own spell for the same element) or is DECLARED below with the reason it does not.
## The physical half (bite, claw, slam, spit) is cowir-sprites' overlay table and is not judged here.

const W1_LEVEL := 12
## The monster-only families: [the element its eruption must be, or "" for none].
const FAMILIES := {
	"family_breath_ice": "ice", "family_breath_lightning": "lightning", "family_breath_dark": "dark",
	"family_cloud": "", "family_dust": "", "family_drain": "dark", "family_screech": "", "family_buff_self": "",
}
## No sequence yet, and why. An entry that gains a sequence, or names an ability no W1 monster uses, reds.
const DECLARED := {
	"pack_call": "a summon: the spawn is its own presentation", "rat_swarm": "a summon", "royal_summon": "a summon",
	"masterite_counter_stance": "an ally buff: the shared stat-up landing (adhoc 23998) is its read",
	"masterite_haste": "an ally buff: the shared landing", "masterite_iron_guard": "an ally buff: the shared landing",
	"masterite_proclamation": "an ally buff: the shared landing", "crown_authority": "an ally buff: the shared landing",
	"coil": "a constrict: no beat drawn yet (sprites 24018)",
	"lure": "a taunt: sprites' landed_taunt is its read", "masterite_dispel": "a strip: no family yet",
	"masterite_slow": "a debuff: the shared stat-down landing", "masterite_time_tax": "a debuff: the shared stat-down landing",
	"system_crash": "a party stun with no element: sprites' landed_stun is its read",
	"adapt": "a one-off self effect", "burrow": "a one-off self effect", "mimic_ability": "a one-off self effect",
	"prismatic_reflect": "a ward: no family yet", "reflect_shield": "a ward: no family yet",
}


func _abilities() -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	return raw.get("abilities", raw)


## Every non-physical ability id a W1 monster holds.
func _w1_casts() -> Array:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var rows: Dictionary = raw.get("monsters", raw)
	var all := _abilities()
	var out: Array = []
	for id in rows:
		var row = rows[id]
		if not (row is Dictionary) or int(row.get("level", 99)) > W1_LEVEL:
			continue
		for a in row.get("abilities", []):
			var ab: Dictionary = all.get(str(a), {})
			if not ab.is_empty() and str(ab.get("type", "")) != "physical" and not (str(a) in out):
				out.append(str(a))
	return out


func _sequence_of(ab: Dictionary) -> String:
	var vfx = ab.get("vfx", {})
	return str(vfx.get("sequence", vfx.get("glory", ""))) if vfx is Dictionary else ""


func test_every_w1_cast_plays_a_sequence_or_says_why_not() -> void:
	var all := _abilities()
	var casts := _w1_casts()
	assert_gt(casts.size(), 50, "FLOOR: the census found the W1 monsters' casts (%d)" % casts.size())
	var sequenced := 0
	var problems: Array = []
	for id in casts:
		var seq := _sequence_of(all[id])
		if seq != "":
			sequenced += 1
			if FractalFX.load_sequence(seq).is_empty():
				problems.append("%s names %s, which does not exist" % [id, seq])
			if DECLARED.has(id):
				problems.append("%s has a sequence now: remove its DECLARED row" % id)
		elif not DECLARED.has(id):
			problems.append("%s plays no sequence and is not declared" % id)
	for id in DECLARED:
		if not (id in casts):
			problems.append("DECLARED names %s, which no W1 monster casts" % id)
	gut.p("W1 monster casts: %d of %d sequenced, %d declared" % [sequenced, casts.size(), DECLARED.size()])
	assert_eq(problems, [], "every W1 monster cast is sequenced or declared")


func test_a_family_is_short_and_draws_at_its_impact() -> void:
	for id in FAMILIES:
		var seq: Dictionary = FractalFX.load_sequence(id)
		assert_false(seq.is_empty(), "CONTROL: %s exists" % id)
		var start := float(seq.get("start", 9.0))
		var impact := float(seq.get("impact", -1.0))
		assert_lte(start, 0.15, "%s starts as the monster acts: it has no cast pose to wait for" % id)
		assert_lte(start + impact, 0.8, "%s lands within 0.8 s, so a monster's turn stays shorter than a Mage's" % id)
		var at_impact := 0
		for ph in seq.get("phases", []):
			if absf(float(ph.get("at", -9.0)) - impact) <= 0.001:
				at_impact += 1
			assert_false(str(ph.get("kind", "")) in ["emit", "spin_fling"], "%s uses a fractal kind" % id)
		assert_gt(at_impact, 0, "%s draws a phase AT its impact, so turbo and the console still show the hit" % id)


func test_an_elemental_family_erupts_in_its_casters_element() -> void:
	var all := _abilities()
	var judged := 0
	for id in _w1_casts():
		var seq_id := _sequence_of(all[id])
		if not FAMILIES.has(seq_id) or str(FAMILIES[seq_id]) == "":
			continue
		judged += 1
		assert_eq(str(all[id].get("element", "")), str(FAMILIES[seq_id]), "%s is %s but plays %s" % [id, all[id].get("element", ""), seq_id])
		var erupts := 0
		for ph in FractalFX.load_sequence(seq_id).get("phases", []):
			if str(ph.get("kind", "")) == "eruption":
				erupts += 1
				assert_eq(str(ph.get("element", "")), str(FAMILIES[seq_id]), "%s erupts in its own element" % seq_id)
		assert_gt(erupts, 0, "%s has an eruption" % seq_id)
	assert_gt(judged, 8, "FLOOR: elemental casts were judged (%d)" % judged)


func test_every_cue_a_family_names_is_in_the_manifest() -> void:
	var text := JSON.stringify(JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json")))
	var named := 0
	for id in FAMILIES:
		for ph in FractalFX.load_sequence(id).get("phases", []):
			if ph.has("sfx"):
				named += 1
				assert_true(("\"%s\"" % ph["sfx"]) in text, "%s names the cue %s, which the manifest lacks" % [id, ph["sfx"]])
	assert_gt(named, 8, "FLOOR: the families name cues at all")
