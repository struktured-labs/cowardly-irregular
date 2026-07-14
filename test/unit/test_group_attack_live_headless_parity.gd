extends GutTest

## PARITY HARNESS (F2, 2026-07-05, coordinated with cowir-autogrind).
## Live BattleManager and headless HeadlessBattleResolver each have their OWN
## group-attack damage path. They MUST produce identical damage, or ludicrous/
## headless play diverges from live (the parity class autogrind has been closing).
## Runs all_out_attack (RNG-free — no crit/variance in that formula) through both
## on an identical setup and asserts equal enemy HP loss.
##   case1 (no buff): guards the F2 defense double-count parity (both paths).
##   case2 (+50% attack buff): guards Divergence A — live reads get_buffed_stat
##     ("attack",…) since v3.33.18; headless must too. Until HBR mirrors it, this
##     case FAILS by construction (that's the point).

const HBR := preload("res://src/autogrind/HeadlessBattleResolver.gd")


func _make(cname: String, attack: int, defense: int, hp: int) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = cname
	c.attack = attack
	c.defense = defense
	c.max_hp = hp
	c.current_hp = hp
	c.current_ap = 4
	c.is_alive = true
	return c


func _live_damage(buff: bool) -> int:
	var hero := _make("Hero", 40, 0, 100)
	if buff:
		hero.add_buff("t_atk", "attack", 1.5, 3)
	var enemy := _make("Foe", 0, 20, 1_000_000)
	var participants: Array = [hero]
	var enemies: Array[Combatant] = [enemy]
	# _execute_physical_group uses its params (not BattleManager party state) and
	# emits signals with no listeners here — safe to call in isolation.
	BattleManager._execute_physical_group(participants, enemies, "all_out_attack", 1)
	return 1_000_000 - enemy.current_hp


func _headless_damage(buff: bool) -> int:
	var hero := _make("Hero", 40, 0, 100)
	if buff:
		hero.add_buff("t_atk", "attack", 1.5, 3)
	var enemy := _make("Foe", 0, 20, 1_000_000)
	var resolver = HBR.new()  # RefCounted — freed automatically
	resolver._player_party = [hero]
	resolver._enemy_party = [enemy]
	resolver._execute_group_physical([hero], "all_out_attack")
	return 1_000_000 - enemy.current_hp


func test_case1_no_buff_parity() -> void:
	var live := _live_damage(false)
	var headless := _headless_damage(false)
	assert_gt(live, 0, "sanity: all_out_attack deals damage")
	assert_eq(live, headless,
		"no-buff all_out_attack must deal IDENTICAL damage live vs headless (F2 defense parity)")


func test_case2_attack_buff_parity() -> void:
	var live := _live_damage(true)
	var headless := _headless_damage(true)
	assert_eq(live, headless,
		"buffed all_out_attack must deal IDENTICAL damage — live reads buffed attack, headless must too (Divergence A)")
