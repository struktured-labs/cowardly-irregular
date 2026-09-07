extends GutTest

## Healing abilities author `heal_amount` (6 of 7; regenerate is a regen effect with none) and
## author `power`/`damage_multiplier` 0 of 7. The resolver read `power`, got the 1.0 default, and
## healed magic*1 — cure at magic 20 restored 20 HP where BattleManager:5227 gives ~1300. A ~65x
## silent nerf to every heal in a headless battle, and the reason a grinding party could not
## sustain itself. Same field-mismatch class as the two fixes commented directly above it in
## _resolve_ability; this is the arm nobody revisited.


func _combatant(cname: String, magic: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname, "max_hp": 2000, "max_mp": 60,
		"attack": 10, "defense": 10, "magic": magic, "speed": 10
	})
	add_child_autofree(c)
	return c


func test_a_heal_uses_the_authored_amount() -> void:
	var resolver := HeadlessBattleResolver.new()
	var healer := _combatant("Healer", 20)
	var patient := _combatant("Patient", 20)
	patient.current_hp = 100
	resolver._resolve_ability(healer, "cure", [patient])
	var restored: int = patient.current_hp - 100
	assert_gt(restored, 200,
		"cure authors heal_amount 650 — restoring %d means the 1.0 power default is being read" % restored)


func test_the_heal_scales_with_the_casters_magic() -> void:
	# ARM+: pins that the magic term still applies, so the fix did not replace one constant
	# with another. A stronger caster must heal more from the same ability.
	var weak := _combatant("Weak", 4)
	var strong := _combatant("Strong", 60)
	var p1 := _combatant("P1", 4)
	var p2 := _combatant("P2", 4)
	p1.current_hp = 100
	p2.current_hp = 100
	var r := HeadlessBattleResolver.new()
	r._resolve_ability(weak, "cure", [p1])
	r._resolve_ability(strong, "cure", [p2])
	assert_gt(p2.current_hp - 100, p1.current_hp - 100,
		"a higher-magic caster must heal more — the magic term must survive the fix")


func test_healing_never_returns_below_one() -> void:
	# The max(1, ...) floor is load-bearing for abilities with no authored amount.
	var healer := _combatant("Healer", 1)
	var patient := _combatant("Patient", 1)
	patient.current_hp = 500
	var r := HeadlessBattleResolver.new()
	r._resolve_ability(healer, "regenerate", [patient])
	assert_true(patient.current_hp >= 500, "a regen-effect ability must never reduce HP")
