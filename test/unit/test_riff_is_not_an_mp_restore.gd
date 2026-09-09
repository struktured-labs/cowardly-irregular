extends GutTest

## Riff was an MP battery once. struktured retired that 2026-08-22 ("disruption, not an MP
## battery") but its LEGACY_IDS entry outlived the design, so a damaging, enemy-targeting,
## blinding strike still resolved to MP_RESTORE and rendered the blue ether sparkle — beside
## ether/hi_ether/elixir/channel/pray, every one a genuine restorer.

func _abilities() -> Dictionary:
	var raw := FileAccess.get_file_as_string("res://data/abilities.json")
	assert_gt(raw.length(), 100, "CONTROL: read a non-empty abilities.json")
	var parsed = JSON.parse_string(raw)
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	return parsed.get("abilities", parsed)

func test_riff_deals_damage_and_is_not_a_restore() -> void:
	## The premise, read from data rather than asserted: if riff ever becomes a restore again this
	## test should be revisited, not silently satisfied.
	var r: Dictionary = _abilities()["riff"]
	assert_eq(str(r.get("type", "")), "physical", "CONTROL: riff is a physical ability")
	assert_gt(float(r.get("damage_multiplier", 0.0)), 0.0, "CONTROL: riff deals damage")
	assert_false(r.has("mp_amount"), "riff restores no MP — that is the retired design")

func test_riff_no_longer_resolves_to_mp_restore() -> void:
	var got: int = int(AbilityVFX.resolve(_abilities()["riff"])["type"])
	assert_ne(got, EffectSystem.EffectType.MP_RESTORE,
		"riff rendering as an MP restore is the stale mapping — a damage strike blooming like an ether")

func test_riff_resolves_to_physical() -> void:
	assert_eq(int(AbilityVFX.resolve(_abilities()["riff"])["type"]), EffectSystem.EffectType.PHYSICAL,
		"a 0.4x weapon-struck chord is physical")

func test_riff_keeps_its_musical_shape() -> void:
	## The type fix must not cost the .226 musical identity — riff is still played, not swung.
	assert_eq(str(AbilityVFX.resolve(_abilities()["riff"])["shape"]), "chord",
		"riff must still render musically")

func test_the_real_mp_free_moves_are_untouched() -> void:
	## riff sat beside these two, so the mutation that fixes riff could plausibly take them out.
	var ab := _abilities()
	for id in ["channel", "pray"]:
		assert_true(ab.has(id), "CONTROL: %s exists" % id)
		assert_eq(int(AbilityVFX.resolve(ab[id])["type"]), EffectSystem.EffectType.MP_RESTORE,
			"%s is a genuine MP free move and must stay MP_RESTORE" % id)
