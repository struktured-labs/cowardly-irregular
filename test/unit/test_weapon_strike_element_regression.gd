extends GutTest

## Cycle 20 (cowir-sfx msg 2796 / cowir-main msg 2903) — elemental strike
## voice consumer. Closes the last unconsumed method from cowir-sfx's
## weapon-strike-identity arc.
##
## Their layered shape at the contact frame:
##     play_attack_hit(weapon_type, is_crit)     <- weapon body (cycle 12/14)
##     play_strike_element(weapon_element)       <- element rides over it (HERE)
##     play_weakness_flash()                     <- weakness stinger (cycle 19)
##
## The element is NOT a top-level equipment field. It's implied by a
## `<element>_damage_bonus` key inside the weapon's special_effects —
## the same data cowir-sfx mapped in their msg-2792 audit. Five weapons
## carry one today, one per element:
##     flame_sword fire · ice_blade ice · thunder_rod lightning
##     holy_staff holy · bone_staff dark
##
## WEAPON-ONLY is the load-bearing design call. BattleManager's
## _sum_equipment_special_effect sums weapon + armor + accessory for
## DAMAGE math, and that's correct there. For the strike VOICE it would
## be wrong: a fire-bonus ring must not make your sword sound like fire.
## The cue describes the thing doing the striking.

const BS_PATH: String = "res://src/battle/BattleScene.gd"
const SM_PATH: String = "res://src/audio/SoundManager.gd"
const EQUIP_PATH: String = "res://data/equipment.json"


## ── (1) The derivation helper ────────────────────────────────────────

func test_weapon_element_helper_defined() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "func _weapon_element_for(pc: Combatant) -> String:",
		"the element-derivation helper must exist")


func test_weapon_element_reads_damage_bonus_suffix() -> void:
	# Data-driven: derive the element from the KEY NAME rather than
	# matching against a hardcoded element list. A future strike_poison
	# .ogg then works with zero change here.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _weapon_element_for(pc: Combatant) -> String:")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1600)
	assert_string_contains(body, "_damage_bonus",
		"element must be derived from the <element>_damage_bonus key convention")
	assert_string_contains(body, "trim_suffix(\"_damage_bonus\")",
		"the element name is the key with its suffix stripped")


func test_weapon_element_has_no_hardcoded_element_list() -> void:
	# Same principle as cycle 15's Voltharion seam: no element-name
	# hardcodes, so the data drives it. play_strike_element is
	# manifest-guarded, making an unauthored element a clean no-op
	# rather than something this function has to know about.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _weapon_element_for(pc: Combatant) -> String:")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1600)
	for element in ["\"fire\"", "\"ice\"", "\"lightning\"", "\"holy\"", "\"dark\""]:
		assert_false(body.find(element) > -1,
			"no %s hardcode — the element comes from the data key, not a list in code" % element)


func test_weapon_element_is_weapon_only_not_armor_or_accessory() -> void:
	# The design call. Damage math sums all three slots; the strike
	# VOICE must not. Guard against someone "fixing" this to match
	# _sum_equipment_special_effect's shape.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _weapon_element_for(pc: Combatant) -> String:")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1600)
	assert_string_contains(body, "equipped_weapon",
		"must read the equipped weapon")
	assert_false(body.find("equipped_armor") > -1,
		"must NOT read armor — a fire-bonus breastplate shouldn't recolor your sword's strike voice")
	assert_false(body.find("equipped_accessory") > -1,
		"must NOT read accessories — same reason")


func test_weapon_element_deterministic_on_multi_element() -> void:
	# No dual-element weapon exists today. If one is ever authored, the
	# pick must not depend on Dictionary iteration order — a silent
	# coin-flip between two valid answers is a miserable debug.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _weapon_element_for(pc: Combatant) -> String:")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1600)
	assert_string_contains(body, "keys.sort()",
		"key iteration must be sorted for a deterministic pick if a weapon ever carries two element bonuses")


func test_weapon_element_null_and_unequipped_safe() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _weapon_element_for(pc: Combatant) -> String:")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1600)
	assert_string_contains(body, "if pc == null:",
		"null combatant guard — _last_acting_combatant is null outside an action window")
	assert_string_contains(body, "EquipmentSystem == null",
		"missing-autoload guard for headless contexts")


## ── (2) The layered call at the contact frame ────────────────────────

func test_strike_element_layered_after_attack_hit() -> void:
	# Order matters: the weapon body plays first and the element rides
	# OVER it. Reversing them would put the element under the impact.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var hit_idx: int = src.find("SoundManager.play_attack_hit(weapon_type, is_crit)")
	assert_gt(hit_idx, -1, "the cycle-12/14 weapon-hit call must still exist")
	var strike_idx: int = src.find("SoundManager.play_strike_element(", hit_idx)
	assert_gt(strike_idx, hit_idx,
		"the elemental strike must layer AFTER play_attack_hit — element over weapon body, per cowir-sfx's shape")


func test_strike_element_skipped_when_no_element() -> void:
	# Empty string means a plain weapon. play_strike_element already
	# early-returns on "", but calling it unconditionally would make
	# the intent unreadable at the call site.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("SoundManager.play_strike_element(")
	assert_gt(idx, -1)
	var before: String = src.substr(maxi(0, idx - 300), 300)
	assert_string_contains(before, "if weapon_element != \"\":",
		"guard the call on a non-empty element so the call site reads as intended")


func test_strike_element_uses_signal_cache_attacker() -> void:
	# Cycle 12 discipline: attribution comes from _last_acting_combatant,
	# never BattleManager.current_combatant (stale mid-execution). The
	# element must describe whoever actually swung.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var idx: int = src.find("func _on_damage_dealt(target: Combatant")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 3200)
	assert_string_contains(body, "_weapon_element_for(attacker)",
		"element must derive from the cached acting combatant, not a re-read of manager state")
	assert_false(body.find("BattleManager.current_combatant") > -1,
		"cycle-12 ratchet still holds — no stale-field reads in this handler")


## ── (3) Cross-lane surface + data pins ───────────────────────────────

func test_sound_manager_exposes_play_strike_element() -> void:
	var src: String = FileAccess.get_file_as_string(SM_PATH)
	assert_string_contains(src, "func play_strike_element(element: String) -> void:",
		"SoundManager.play_strike_element must exist — cowir-sfx owns it; ping before changing the signature")


func test_elemental_weapons_still_carry_damage_bonus_keys() -> void:
	# The consumer is only reachable when SOME weapon carries the key.
	# If a data refactor moved element onto a top-level field, this
	# whole feature would silently stop firing with nothing failing —
	# so pin the data shape the derivation depends on.
	var f: FileAccess = FileAccess.open(EQUIP_PATH, FileAccess.READ)
	assert_not_null(f, "equipment.json must be readable")
	var text: String = f.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "equipment.json must parse to a Dictionary")
	# Walk for any special_effects carrying a *_damage_bonus.
	var found: Array = []
	var stack: Array = [parsed]
	while not stack.is_empty():
		var node: Variant = stack.pop_back()
		if node is Dictionary:
			var se: Variant = (node as Dictionary).get("special_effects", null)
			if se is Dictionary:
				for k in (se as Dictionary).keys():
					if str(k).ends_with("_damage_bonus"):
						found.append(str(node.get("id", "?")))
						break
			for v in (node as Dictionary).values():
				if v is Dictionary or v is Array:
					stack.append(v)
		elif node is Array:
			for v in node:
				if v is Dictionary or v is Array:
					stack.append(v)
	assert_gt(found.size(), 0,
		"at least one weapon must carry a <element>_damage_bonus — the strike-element consumer is dead code otherwise")
