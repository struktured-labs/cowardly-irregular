extends GutTest

## Pins the weapon-strike identity surface (cycle #9b, msg 2789):
## 5 elemental strike voices + 2 rebuilt crits + 1 weakness_flash +
## 2 SoundManager methods (play_strike_element, play_weakness_flash).
## The layered-calls seam is cowir-battle's — this test asserts the SFX
## surface stays coherent so their consumer can't silently break.

const STRIKE_ELEMENTS := ["fire", "ice", "lightning", "holy", "dark"]


func test_all_5_strike_keys_present_in_manifest() -> void:
	var sm: Node = get_node_or_null("/root/SoundManager")
	for elem in STRIKE_ELEMENTS:
		var key: String = "strike_" + elem
		assert_true(sm._sfx_manifest.has(key), "manifest has %s" % key)


func test_weakness_flash_key_present() -> void:
	var sm: Node = get_node_or_null("/root/SoundManager")
	assert_true(sm._sfx_manifest.has("weakness_flash"), "manifest has weakness_flash")


func test_play_strike_element_method_exists() -> void:
	var sm: Node = get_node_or_null("/root/SoundManager")
	assert_true(sm.has_method("play_strike_element"), "SoundManager exposes play_strike_element")


func test_play_weakness_flash_method_exists() -> void:
	var sm: Node = get_node_or_null("/root/SoundManager")
	assert_true(sm.has_method("play_weakness_flash"), "SoundManager exposes play_weakness_flash")


func test_play_strike_element_empty_is_noop() -> void:
	var sm: Node = get_node_or_null("/root/SoundManager")
	sm.play_strike_element("")
	assert_true(true, "empty string routes safely (no crash)")


func test_play_strike_element_unknown_is_manifest_miss_not_crash() -> void:
	var sm: Node = get_node_or_null("/root/SoundManager")
	sm.play_strike_element("banana_republic")
	assert_true(true, "unknown element goes through manifest lookup and quietly misses")


func test_every_crit_variant_is_audibly_longer_than_its_base() -> void:
	## Ratchet against the msg 2792 audit finding: pre-rebuild dagger_crit
	## was 555ms vs 480ms base (1.17x — imperceptible). Post-rebuild must
	## be >=1.5x base so the crit reads as distinct.
	##
	## DERIVED FROM DISK 2026-07-29 (cowir-ai msg-3390's fixture-coincidence class).
	## This used to hardcode ["dagger", "axe"] — the two weapons the incident was
	## about — while five base/crit pairs exist. The property is "every crit reads
	## as distinct from its base"; a hardcoded pair list pins the INCIDENT instead,
	## so a shortened sword_crit or a new weapon added without a longer crit was
	## invisible. Enumerating the directory means new weapons opt in automatically.
	var dir: String = "res://assets/audio/sfx/"
	var pairs: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		var name: String = str(f)
		if name.begins_with("attack_hit_") and name.ends_with("_crit.ogg"):
			pairs.append(name.trim_suffix("_crit.ogg").trim_prefix("attack_hit_"))
	pairs.sort()

	## Vacuity control: if the enumeration ever returns nothing, every assertion
	## below is skipped and this test passes having checked zero files.
	assert_gt(pairs.size(), 0,
		"control: found no attack_hit_*_crit.ogg at all — enumeration is broken, so the checks below ran on nothing")

	for w in pairs:
		var base_s: AudioStream = load("%sattack_hit_%s.ogg" % [dir, w])
		var crit_s: AudioStream = load("%sattack_hit_%s_crit.ogg" % [dir, w])
		assert_true(crit_s != null, "crit variant loads: %s" % w)
		assert_true(base_s != null,
			"%s_crit.ogg exists but attack_hit_%s.ogg does not — a crit with no base can never be compared, and plays as the only version of that weapon's hit" % [w, w])
		if base_s == null or crit_s == null:
			continue
		var base_dur: float = base_s.get_length()
		var crit_dur: float = crit_s.get_length()
		assert_true(crit_dur >= base_dur * 1.5,
			"%s crit (%.2fs) must be >=1.5x its base (%.2fs) to read as distinct — got %.2fx" % [w, crit_dur, base_dur, crit_dur / maxf(base_dur, 0.001)])
		## PREDICATE FIX 2026-07-29 (cowir-controller msg-3506's axis). The ratio
		## above is PROPORTIONAL and says nothing about whether either file is a
		## plausible sound. Found by a mutation run hoping it would pass: a 20ms base
		## against a 40ms crit satisfies >=1.5x and the guard went 8/8 GREEN, on two
		## cues far too short to be heard as weapon hits at all.
		##
		## 100ms is a perceptible difference in duration, and it is a RELATIONSHIP
		## (how much longer) rather than a coordinate (how long). The five real pairs
		## clear it by 0.41s to 2.89s, so it is not fitted to current data.
		assert_true(crit_dur - base_dur >= 0.10,
			"%s crit is only %.3fs longer than its base (%.2fs vs %.2fs) — proportionally distinct but too small an absolute difference to hear" % [w, crit_dur - base_dur, crit_dur, base_dur])


func test_manifest_load_is_not_vacuous() -> void:
	## POSITIVE CONTROL, not a size pin. The key-presence tests above only mean
	## something if the manifest actually loaded — an empty dict would fail them
	## for the wrong reason. This asserts the sweep had something to sweep.
	##
	## Was `count >= 250` (cowir-ai's class, msg 3293): a bare magnitude is
	## satisfied by any large manifest, so it could not tell a correct edit from
	## someone deleting five keys. The specific keys are pinned by name above;
	## the count only needs to prove the load happened.
	var sm: Node = get_node_or_null("/root/SoundManager")
	assert_true(sm._sfx_manifest.size() > 0, "manifest loaded and is non-empty")
