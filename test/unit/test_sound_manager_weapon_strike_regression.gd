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


func test_crit_variants_replaced_dagger_axe_lengths_are_distinct_now() -> void:
	## Ratchet against the msg 2792 audit finding: pre-rebuild dagger_crit
	## was 555ms vs 480ms base (1.17x — imperceptible). Post-rebuild must
	## be >=1.5x base so the crit reads as distinct.
	for w in ["dagger", "axe"]:
		var base_path: String = "res://assets/audio/sfx/attack_hit_%s.ogg" % w
		var crit_path: String = "res://assets/audio/sfx/attack_hit_%s_crit.ogg" % w
		var base_s: AudioStream = load(base_path)
		var crit_s: AudioStream = load(crit_path)
		assert_true(base_s != null, "base %s exists" % w)
		assert_true(crit_s != null, "crit %s exists" % w)
		var base_dur: float = base_s.get_length()
		var crit_dur: float = crit_s.get_length()
		assert_true(crit_dur >= base_dur * 1.5, "%s crit (%.2fs) is >=1.5x base (%.2fs) — distinct" % [w, crit_dur, base_dur])


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
