extends GutTest

## Equipment stat_mods are FLAT, so a percentage claim in a description is a claim
## about a different KIND of quantity than the item holds.
##
## glass_amulet said "+50% damage, -30% defense" over stat_mods {attack: 150,
## magic: 150, defense: -100}. A flat bonus cannot be a fixed percentage — +150
## attack is +50% only at exactly 300 base, and base attack varies by job and level.
## Every other accessory in the file describes its flat mods qualitatively
## ("Increases physical strength" for attack: 100); glass_amulet was the only one
## quoting percentages, and it was the only one whose numbers could not be true.
##
## THE PREMISE, measured 2026-07-29: all 92 stat_mods values across the file are
## flat integers (min -100, max 500), zero multiplier-shaped. That is what makes
## this decidable rather than a judgement call, and it is asserted below — if
## equipment ever gains multiplier mods, this rule needs revisiting, not silencing.
##
## A percentage IS legitimate when backed by a `special_effects` multiplier, which
## is a real fractional quantity. returned_sword's "+10% damage against any enemy
## the party has seen before" is honest: special_effects.familiar_weight_bonus =
## 0.1, consumed by BattleManager._apply_familiar_weight_bonus at two call sites.
## So the rule is not "no percentages" — it is "percentages must name a multiplier
## that exists, and match it".
##
## EquipmentMenu renders description verbatim while the player is choosing what to
## wear, and this one is a 2500g purchase.

const EQUIPMENT := "res://data/equipment.json"


func _equipment() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(EQUIPMENT))
	return d if d is Dictionary else {}


## Every item at any nesting depth — the file groups by weapons/armors/accessories,
## and a top-level-only reader silently finds zero.
func _items() -> Array:
	var out: Array = []
	var stack: Array = [_equipment()]
	while not stack.is_empty():
		var node = stack.pop_back()
		if not (node is Dictionary):
			continue
		for k in node:
			var v = node[k]
			if not (v is Dictionary):
				continue
			if v.has("id"):
				out.append([str(k), v])
			else:
				stack.append(v)
	return out


## FLOOR + PREMISE. A walker that finds nothing makes the guard vacuous, and the
## rule below only holds while stat_mods are flat.
func test_control_items_found_and_stat_mods_are_flat() -> void:
	var items := _items()
	assert_gt(items.size(), 30, "must walk real equipment entries — 0 makes every check below vacuous")

	var n_mods := 0
	var fractional: Array = []
	for pair in items:
		var mods = pair[1].get("stat_mods", {})
		if not (mods is Dictionary):
			continue
		for k in mods:
			var v = mods[k]
			if not (v is float or v is int):
				continue
			n_mods += 1
			if absf(float(v)) < 3.0 and float(v) != float(int(v)):
				fractional.append("%s.%s = %s" % [pair[0], k, v])
	assert_gt(n_mods, 50, "must find stat_mods values, else the premise below is untested")
	assert_eq(fractional, [], "equipment stat_mods gained a multiplier-shaped value. This file's "
		+ "rule assumes they are all FLAT, which is what makes a percentage claim unbackable. "
		+ "Revisit the rule rather than silencing it: %s" % [fractional])


## THE GUARD. A percentage must name a multiplier that exists and match it.
func test_percent_claims_match_a_real_multiplier() -> void:
	var re := RegEx.new()
	assert_eq(re.compile("([0-9]+)\\s*%"), OK, "pattern must compile")

	var claimed := 0
	var unbacked: Array = []
	for pair in _items():
		var item: Dictionary = pair[1]
		var desc: String = str(item.get("description", ""))
		var hits := re.search_all(desc)
		if hits.is_empty():
			continue
		claimed += 1
		var effects = item.get("special_effects", {})
		var pcts: Array = []
		if effects is Dictionary:
			for k in effects:
				var v = effects[k]
				if v is float or v is int:
					pcts.append(int(round(float(v) * 100.0)))
		for m in hits:
			if not (int(m.get_string(1)) in pcts):
				unbacked.append("%s: claims %s%% but special_effects offer %s" % [pair[0], m.get_string(1), pcts])

	assert_gt(claimed, 0, "must find at least one percentage claim, else this guard is vacuous")
	assert_eq(unbacked, [], "equipment stat_mods are FLAT, so a percentage here is unbackable unless "
		+ "a special_effects multiplier provides it. EquipmentMenu shows this while the player is "
		+ "deciding what to buy. State the flat numbers, or add the multiplier that makes the "
		+ "percentage true: %s" % [unbacked])
