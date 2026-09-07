extends GutTest

## struktured reported the fireball whoop, I re-voiced ability_fire, and he reported it AGAIN --
## because ability_fire rotates through _v2/_v3 and I had only replaced the base, so two casts in
## three still played the old audio. Then the same thing on lightning. Then the cure spell, where
## a swap had parked the rejected bird ON a variant the rotation still reached.
##
## Three reports, one shape: a base and its variants are ONE surface to the player and separate
## entries in the manifest. Fixing the base fixes 1/N of what they hear.

const MANIFEST := "res://data/sfx_manifest.json"


func _sfx() -> Dictionary:
	var raw := FileAccess.get_file_as_string(MANIFEST)
	assert_ne(raw, "", "manifest unreadable — every check below would be vacuous")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "manifest did not parse")
	return (parsed as Dictionary).get("sfx", {})


func test_every_variant_a_rotation_names_actually_exists() -> void:
	var sfx := _sfx()
	var rotations := 0
	var dangling: Array = []
	for key in sfx:
		var v: Variant = (sfx[key] as Dictionary).get("variants", null)
		if not (v is Array) or (v as Array).is_empty():
			continue
		rotations += 1
		for name in (v as Array):
			if not sfx.has(str(name)):
				dangling.append("%s -> %s" % [key, name])
	assert_gt(rotations, 2, "fewer than 3 rotations found — the scan is reading almost nothing")
	if not dangling.is_empty():
		fail_test("rotation names a variant with no manifest entry — that slot plays silence: %s" % [dangling])


func test_a_source_locked_base_has_source_locked_variants() -> void:
	# The rotation is one sound to the player. A synthesised base beside generated variants means
	# the player hears the fix 1/N of the time — which is exactly what he reported, twice.
	var sfx := _sfx()
	var checked := 0
	var mixed: Array = []
	for key in sfx:
		var e := sfx[key] as Dictionary
		var src := str(e.get("source", ""))
		if not src.begins_with("tools/"):
			continue
		var v: Variant = e.get("variants", null)
		if not (v is Array) or (v as Array).is_empty():
			continue
		checked += 1
		for name in (v as Array):
			var ve := sfx.get(str(name), {}) as Dictionary
			if not str(ve.get("source", "")).begins_with("tools/"):
				mixed.append("%s (locked) -> %s (not)" % [key, name])
	assert_gt(checked, 0, "no source-locked base with a rotation found — this guard is watching nothing")
	if not mixed.is_empty():
		fail_test("a synthesised base rotates into cues that are NOT synthesised — the player hears the fix only some of the time: %s" % [mixed])


func test_the_mage_attack_kit_is_fully_source_locked() -> void:
	# fire / blizzard / thunder are the mage's starting kit and dark_bolt arrives at L4. Every slot
	# the rotation can reach, not just the base.
	var sfx := _sfx()
	var unlocked: Array = []
	for k in ["ability_fire", "ability_fire_v2", "ability_fire_v3",
			"ability_lightning", "ability_lightning_v2", "ability_lightning_v3",
			"ability_ice", "ability_ice_v2", "ability_ice_v3", "ability_dark"]:
		assert_true(sfx.has(k), "manifest lacks %s" % k)
		if not str((sfx[k] as Dictionary).get("source", "")).begins_with("tools/"):
			unlocked.append(k)
	if not unlocked.is_empty():
		fail_test("mage attack cues not source-locked — a generator run restores the whoop on these slots: %s" % [unlocked])
