extends GutTest

## An AoE row read "Acid Spray [AoE] ~N total", N summing each enemy's FULL estimate. Two enemies at
## 5 HP each against a spell that hits for hundreds read as hundreds of damage, when the most it can
## take is 10, so the total overstated exactly the moves a player compares. Each enemy now
## counts at most what it has left, and a "N KO" count matches the single-target [KILL] tag.

const ABILITY := "acid_spray"


func _c(n: String, hp: int, magic: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": n, "max_hp": maxi(hp, 1), "max_mp": 999, "attack": 10, "defense": 0, "magic": magic, "speed": 10})
	c.magic_defense = 0
	add_child_autofree(c)
	c.current_hp = hp
	return c


func _label(caster: Combatant, foes: Array[Combatant]) -> String:
	var menu = BattleCommandMenu.new(null)
	return str(menu._build_ability_menu_item(ABILITY, caster, foes, Transform2D.IDENTITY).get("label", ""))


func _total(label: String) -> int:
	var at := label.find("~")
	return label.substr(at + 1).split(" ")[0].to_int() if at >= 0 else -1  # to_int() keeps every digit: "10 total, 2 KO" -> 102


func test_the_ability_is_an_aoe_that_quotes() -> void:
	var ab: Dictionary = JobSystem.get_ability(ABILITY)
	assert_eq(str(ab.get("target_type", "")), "all_enemies", "CONTROL: %s must hit all enemies" % ABILITY)


func test_a_nearly_dead_pair_is_worth_what_it_has_left() -> void:
	var caster := _c("Mage", 100, 400)
	var a := _c("Slime A", 5, 1)
	var b := _c("Slime B", 5, 1)
	var full: int = BattleManager.estimate_ability_damage(caster, a, JobSystem.get_ability(ABILITY))
	assert_gt(full, 5, "CONTROL: the spell must out-hit 5 HP, or overkill never arises")
	var label := _label(caster, [a, b] as Array[Combatant])
	assert_eq(_total(label), 10, "two enemies at 5 HP can lose at most 10, whatever the spell's power: '%s'" % label)
	assert_string_contains(label, "2 KO", "and the row says the spell finishes both")


func test_a_healthy_pair_still_reads_the_full_estimate() -> void:
	var caster := _c("Mage", 100, 40)
	var a := _c("Golem A", 100000, 1)
	var b := _c("Golem B", 100000, 1)
	var each: int = BattleManager.estimate_ability_damage(caster, a, JobSystem.get_ability(ABILITY))
	var label := _label(caster, [a, b] as Array[Combatant])
	assert_eq(_total(label), each * 2, "with no overkill the total is the plain sum: '%s'" % label)
	assert_false(label.contains("KO"), "and promises no KO")
