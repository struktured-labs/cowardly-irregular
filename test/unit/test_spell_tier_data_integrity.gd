extends GutTest

## struktured 2026-08-20: spell ladders get a NAMED tier scheme — "Blizzard, then
## Blizzardia, then Blizzardia Ex" — and the shop must know which spell outranks which.
## Tiers are DATA (family + tier on each rung), never a name-suffix heuristic: the
## codebase already has one `ends_with("aga")` guess and it is the reason ~245 abilities
## rendered as generic physical for months. This pins the data, not the spelling guesses.

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


func test_ladder_names_follow_the_ia_then_ex_scheme() -> void:
	# Struktured's rule, literally: base → base+ia → that + " Ex". Silent trailing 'e' dropped (Fire→Firia, Cure→Curia).
	var a := _abilities()
	assert_eq(a["blizzara"]["name"], "Blizzardia", "his own example, tier 2")
	assert_eq(a["blizzaga"]["name"], "Blizzardia Ex", "his own example, tier 3")
	assert_eq(a["fira"]["name"], "Firia", "Fire drops the silent e before -ia")
	assert_eq(a["firaga"]["name"], "Firia Ex")
	assert_eq(a["thundara"]["name"], "Thunderia")
	assert_eq(a["thundaga"]["name"], "Thunderia Ex")
	assert_eq(a["cura"]["name"], "Curia")
	for id in a:
		var v: Dictionary = a[id]
		if int(v.get("tier", 0)) == 2:
			assert_true(str(v["name"]).ends_with("ia"), "%s is tier 2 → name must end in 'ia'" % id)
		if int(v.get("tier", 0)) == 3:
			assert_true(str(v["name"]).ends_with("ia Ex"), "%s is tier 3 → name must end in 'ia Ex'" % id)


func test_ids_did_not_change() -> void:
	# Saves, autobattle rules and shop stock key on IDs — only display names moved
	var a := _abilities()
	for id in ["fire", "fira", "firaga", "blizzard", "blizzara", "blizzaga", "thunder", "thundara", "thundaga", "cure", "cura"]:
		assert_true(a.has(id), "ladder id %s must still exist" % id)
