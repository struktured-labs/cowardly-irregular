extends GutTest

## Real gameplay regression: CharacterCustomization.apply_stat_bonus()'s
## personality stat bonuses (+2 ATK / +2 DEF / +2 MAG / +2 SPD / +2
## MAG +1 SPD) must persist through recalculate_stats(), not get wiped
## the same frame they land.
##
## Bug shape:
##   • apply_stat_bonus mutated DERIVED stats:
##       combatant.attack += 2
##       combatant.recalculate_stats()
##   • Combatant.recalculate_stats's first action is:
##       attack = base_attack
##       defense = base_defense
##       …
##     So the +2 on the derived field was wiped instantly. Every
##     subsequent recalc — job assignment, level up, equipment change,
##     passive toggle — also wiped it. Net: every personality bonus
##     advertised in the character-creation UI was effectively dead
##     from the moment it landed.
##   • Player picks "BRAVE" → "+2 ATK" splash on screen → combatant
##     spawns with NO ATK bonus on inspect.
##
## Fix: apply_stat_bonus modifies the BASE stat instead. The bonus
## becomes intrinsic to the character — recalculate_stats picks it up
## just like job mods, level multiplier, passives.
##
## Tests:
##   • Source pin: apply_stat_bonus modifies base_X (not the derived X)
##   • Behavioural: each personality applies the documented bonus to the
##     correct base stat; the derived stat reflects it after recalc
##   • Behavioural: a subsequent recalculate_stats does NOT wipe the
##     bonus (the original bug shape)

const CharacterCustomizationScript := preload("res://src/character/CharacterCustomization.gd")
const CHAR_CUSTOM_PATH := "res://src/character/CharacterCustomization.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pin ────────────────────────────────────────────────────────────────

func test_apply_stat_bonus_modifies_base_stats() -> void:
	var text := _read(CHAR_CUSTOM_PATH)
	var idx := text.find("func apply_stat_bonus")
	assert_gt(idx, -1, "apply_stat_bonus must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nfunc ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# Each of the four primary stats must be written via base_X. The bug
	# shape was `combatant.X += 2` on the derived field; the fix is
	# `combatant.base_X += 2`.
	for base_stat in ["base_attack", "base_defense", "base_magic", "base_speed"]:
		assert_true(body.contains("combatant.%s" % base_stat),
			"apply_stat_bonus must mutate combatant.%s (not the derived stat — recalculate_stats would wipe it)" % base_stat)
	# Negative pin: the legacy `combatant.attack +=`, etc. on derived
	# stats must NOT appear in non-comment code. (Comments may still
	# cite the legacy shape for teaching.)
	var lines := body.split("\n")
	var code_only: PackedStringArray = PackedStringArray()
	for line in lines:
		var ln: String = str(line)
		if ln.strip_edges().begins_with("#"):
			continue
		code_only.append(ln)
	var code := "\n".join(code_only)
	for derived in ["combatant.attack +=", "combatant.defense +=", "combatant.magic +=", "combatant.speed +="]:
		assert_false(code.contains(derived),
			"apply_stat_bonus must NOT mutate the derived stat (%s) — the next recalculate_stats wipes it. Use base_X instead." % derived)


# ── Behavioural ──────────────────────────────────────────────────────────────

func _make_combatant(base_atk: int = 10, base_def: int = 10, base_mag: int = 10, base_spd: int = 10) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "PersonalityTester"
	c.base_max_hp = 100
	c.base_max_mp = 50
	c.base_attack = base_atk
	c.base_defense = base_def
	c.base_magic = base_mag
	c.base_speed = base_spd
	add_child_autofree(c)
	return c


func test_brave_personality_persists_through_recalc() -> void:
	# Pre-fix: brave's "+2 ATK" was wiped by recalculate_stats inside
	# apply_stat_bonus, leaving combatant.attack == base_attack (10).
	# Post-fix: base_attack becomes 12, so attack ends up at 12 after
	# recalc — AND a SECOND recalc still leaves it at 12.
	var c := _make_combatant(10, 10, 10, 10)
	var custom = CharacterCustomizationScript.new("Hero")
	custom.personality = CharacterCustomizationScript.Personality.BRAVE
	custom.apply_stat_bonus(c)
	assert_eq(c.attack, 12,
		"BRAVE personality must leave attack at 12 (base 10 + 2) after apply_stat_bonus")
	# The bug-shape regression: a subsequent recalculate_stats must NOT
	# wipe the bonus. This is the actual test that fails pre-fix.
	c.recalculate_stats()
	assert_eq(c.attack, 12,
		"BRAVE personality bonus must SURVIVE a subsequent recalculate_stats (the pre-fix bug shape)")


func test_cautious_personality_persists_through_recalc() -> void:
	var c := _make_combatant(10, 10, 10, 10)
	var custom = CharacterCustomizationScript.new("Mira")
	custom.personality = CharacterCustomizationScript.Personality.CAUTIOUS
	custom.apply_stat_bonus(c)
	c.recalculate_stats()
	assert_eq(c.defense, 12,
		"CAUTIOUS personality bonus must persist through recalc (base 10 + 2)")


func test_scholarly_personality_persists_through_recalc() -> void:
	var c := _make_combatant(10, 10, 10, 10)
	var custom = CharacterCustomizationScript.new("Vex")
	custom.personality = CharacterCustomizationScript.Personality.SCHOLARLY
	custom.apply_stat_bonus(c)
	c.recalculate_stats()
	assert_eq(c.magic, 12,
		"SCHOLARLY personality bonus must persist through recalc (base 10 + 2)")


func test_quick_personality_persists_through_recalc() -> void:
	var c := _make_combatant(10, 10, 10, 10)
	var custom = CharacterCustomizationScript.new("Zack")
	custom.personality = CharacterCustomizationScript.Personality.QUICK
	custom.apply_stat_bonus(c)
	c.recalculate_stats()
	assert_eq(c.speed, 12,
		"QUICK personality bonus must persist through recalc (base 10 + 2)")


func test_charismatic_persists_both_mag_and_spd() -> void:
	var c := _make_combatant(10, 10, 10, 10)
	var custom = CharacterCustomizationScript.new("Bard")
	custom.personality = CharacterCustomizationScript.Personality.CHARISMATIC
	custom.apply_stat_bonus(c)
	c.recalculate_stats()
	assert_eq(c.magic, 12,
		"CHARISMATIC personality must give +2 MAG (10 + 2 = 12) through recalc")
	assert_eq(c.speed, 11,
		"CHARISMATIC personality must give +1 SPD (10 + 1 = 11) through recalc")
