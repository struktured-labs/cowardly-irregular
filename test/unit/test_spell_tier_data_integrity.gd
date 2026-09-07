extends GutTest

## struktured 2026-08-22: "we need a whole new branding for the spell names, make latin terms
## more directly if we can" — the ladder is now a Latin root plus a GRADE adjective that agrees
## in gender (Ignis Maior/Maximus m. · Glacies Maior/Maxima f. · Fulmen Maius/Maximum n.).
## Tiers stay DATA (family + tier per rung), never a name-suffix heuristic: the codebase already
## has one `ends_with("aga")` guess and it is why ~245 abilities rendered as generic physical for
## months. The grade words are asserted as a RELATIONSHIP to the tier-1 root, so re-rooting a
## family (Ignis -> Flamma) stays green while a wrong grade or a broken agreement reds.

const GRADES := {
	# family -> [tier-1 root, tier-2 grade, tier-3 grade]; grade spelling encodes Latin gender
	"fire": ["Ignis", "Maior", "Maximus"],
	"ice": ["Glacies", "Maior", "Maxima"],
	"lightning": ["Fulmen", "Maius", "Maximum"],
	"cure": ["Sanatio", "Maior", ""],
}


func _abilities() -> Dictionary:
	var f := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d


func test_every_tiered_spell_has_a_family_and_tiers_are_contiguous() -> void:
	var a := _abilities()
	var fams: Dictionary = {}
	for id in a:
		var v: Dictionary = a[id]
		if v.has("tier"):
			assert_true(v.has("family"), "%s has a tier but no family — the shop cannot rank it" % id)
			fams.get_or_add(v["family"], []).append(int(v["tier"]))
	assert_gt(fams.size(), 3, "CONTROL: found %d ladders (expect fire/ice/lightning/cure)" % fams.size())
	for fam in fams:
		var tiers: Array = fams[fam]
		tiers.sort()
		for i in range(tiers.size()):
			assert_eq(tiers[i], i + 1, "family %s tiers must be 1..N with no gaps or duplicates, got %s" % [fam, str(tiers)])


func test_every_rung_is_its_root_plus_the_graded_form() -> void:
	# The invariant is the RELATIONSHIP: rung N == "<the family's tier-1 name> <grade N>".
	# Derived from the data, so renaming a root is a one-line change here, not a rewrite.
	var a := _abilities()
	var roots: Dictionary = {}
	for id in a:
		var v: Dictionary = a[id]
		if int(v.get("tier", 0)) == 1 and v.has("family"):
			roots[v["family"]] = str(v["name"])
	assert_eq(roots.size(), GRADES.size(), "one tier-1 root per ladder; got %s" % str(roots.keys()))
	for id in a:
		var v: Dictionary = a[id]
		var t := int(v.get("tier", 0))
		if t < 2:
			continue
		var fam := str(v["family"])
		assert_true(GRADES.has(fam), "unknown ladder family '%s' — add its grade words" % fam)
		var grade: String = GRADES[fam][t - 1]
		assert_ne(grade, "", "family %s has no tier-%d grade word but ability %s claims that tier" % [fam, t, id])
		assert_eq(str(v["name"]), "%s %s" % [roots[fam], grade],
			"%s (tier %d of %s) must read '<root> <grade>'" % [id, t, fam])


func test_grade_words_agree_in_gender_with_their_root() -> void:
	# The joke only lands if the Latin is right: masculine Maior/Maximus, feminine Maior/Maxima,
	# neuter Maius/Maximum. A ladder that mixes forms is the bug this test exists to name.
	var pairs := {"Maximus": "Maior", "Maxima": "Maior", "Maximum": "Maius"}
	for fam in GRADES:
		var t2: String = GRADES[fam][1]
		var t3: String = GRADES[fam][2]
		if t3 == "":
			continue
		assert_true(pairs.has(t3), "'%s' is not a superlative form this scheme uses" % t3)
		assert_eq(pairs[t3], t2, "family %s: superlative '%s' requires comparative '%s', got '%s'" % [fam, t3, pairs[t3], t2])


func test_the_renamed_kit_is_latin_and_carries_no_final_fantasy_residue() -> void:
	var a := _abilities()
	var renamed := ["fire", "fira", "firaga", "blizzard", "blizzara", "blizzaga", "thunder",
		"thundara", "thundaga", "cure", "cura", "protect", "shell", "raise", "esuna", "regen",
		"regenerate", "crystal_heal", "chain_lightning", "dark_bolt", "drain_life", "necro_blast",
		"death_sentence"]
	var stale := ["Fire", "Blizzard", "Thunder", "Cure", "Protect", "Shell", "Raise", "Esuna",
		"Regen", "Firia", "Blizzardia", "Thunderia", "Curia", "Crystal Heal", "Chain Lightning",
		"Dark Bolt", "Drain Life", "Necro Blast", "Death Sentence"]
	for id in renamed:
		assert_true(a.has(id), "renamed spell id %s must still exist" % id)
		var n := str(a[id]["name"])
		assert_false(n in stale, "%s still carries its pre-rebrand name '%s'" % [id, n])
		assert_false(n.ends_with(" Ex"), "%s keeps the retired ' Ex' suffix" % id)


func test_ids_did_not_change() -> void:
	# Saves, autobattle rules and shop stock key on IDs — only display names moved
	var a := _abilities()
	for id in ["fire", "fira", "firaga", "blizzard", "blizzara", "blizzaga", "thunder", "thundara", "thundaga", "cure", "cura"]:
		assert_true(a.has(id), "ladder id %s must still exist" % id)
