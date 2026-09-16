extends GutTest

## ⛔ AN AUTOBATTLE ACTION WITH NO TARGET WAS AIMED AT THE ENEMY — EVERY ACTION, INCLUDING HEALS.
## `_action_def_to_action` defaulted `target` to `lowest_hp_enemy` for everything, and
## `_resolve_ability_targets` overrode that only for `all_allies` / `all_enemies` / `dead_ally`.
## Measured on the live evaluator (cleric, hurt ally Bram 100/500, Goblin 60/300):
##
##   {"type":"ability","id":"cure"}      -> ["Goblin"]   ability declares single_ally
##   protect · esuna                     -> ["Goblin"]   single_ally
##   channel (the Mage's self-only MP restore) -> ["Goblin"]   self
##   {"type":"item","id":"potion"}       -> ["Goblin"]
##
## Consequences measured separately: the enemy-aimed `cure` healed nobody and spent no MP — a wasted
## turn with the ally still hurt — and the potion was worse: ItemSystem healed the GOBLIN 60 -> 300 and
## consumed the item.
##
## The grid editor always writes a target, so the reachable paths are shared `COWIR1:` codes, hand-edited
## JSON and older saved scripts. cowir-ai fixed the LLM composer's half (11481) and left this default here.

var _saved_party: Array
var _saved_enemies: Array
var _saved_persist: bool


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()
	_saved_enemies = BattleManager.enemy_party.duplicate()
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true


func after_each() -> void:
	BattleManager.player_party.assign(_alive(_saved_party))
	BattleManager.enemy_party.assign(_alive(_saved_enemies))
	AutobattleSystem._test_disable_persistence = _saved_persist


func _alive(saved: Array) -> Array:
	var out: Array = []
	for c in saved:
		if is_instance_valid(c):
			out.append(c)
	return out


func _combatant(name: String, job: String, hp: int, max_hp: int) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = name
	c.job = {"id": job}
	c.max_hp = max_hp
	c.current_hp = hp
	c.max_mp = 99
	c.current_mp = 99
	c.is_alive = true
	return c


## A cleric whose ally is hurt and whose enemy is hurt WORSE — so "lowest HP" alone cannot pick the
## right side, and a target that lands on the ally proves the side was chosen deliberately.
func _party_with_hurt_ally() -> Dictionary:
	var cleric := _combatant("Mira", "cleric", 500, 500)
	var ally := _combatant("Bram", "fighter", 100, 500)
	var goblin := _combatant("Goblin", "", 60, 300)
	BattleManager.player_party.assign([cleric, ally] as Array[Combatant])
	BattleManager.enemy_party.assign([goblin] as Array[Combatant])
	return {"cleric": cleric, "ally": ally, "goblin": goblin}


func _targets(caster: Combatant, action_def: Dictionary) -> Array[String]:
	var action: Dictionary = AutobattleSystem._action_def_to_action(caster, action_def)
	var names: Array[String] = []
	for t in action.get("targets", [action.get("target")]):
		names.append(str(t.combatant_name) if t != null else "null")
	return names


func test_the_fixtures_really_declare_what_this_guard_assumes() -> void:
	## CONTROL: if `cure` ever stops being single_ally, the arms below would pass for the wrong reason.
	assert_eq(str(JobSystem.get_ability("cure").get("target_type", "")), "single_ally", "cure heals one ally")
	assert_eq(str(JobSystem.get_ability("channel").get("target_type", "")), "self", "channel restores the caster's own MP")
	assert_eq(str(JobSystem.get_ability("fire").get("target_type", "")), "single_enemy", "fire is offensive")
	assert_eq(int(ItemSystem.get_item("potion").get("target_type", -1)), ItemSystem.TargetType.SINGLE_ALLY, "a potion is for an ally")
	assert_eq(int(ItemSystem.get_item("bomb_fragment").get("target_type", -1)), ItemSystem.TargetType.SINGLE_ENEMY, "a bomb is not")


func test_an_untargeted_heal_lands_on_the_hurt_ally() -> void:
	var cast := _party_with_hurt_ally()
	var offenders: Array = []
	for ability_id in ["cure", "protect", "esuna", "regen"]:
		var names: Array[String] = _targets(cast["cleric"], {"type": "ability", "id": ability_id})
		if names != ["Bram"]:
			offenders.append("%s -> %s" % [ability_id, str(names)])
	assert_eq(offenders.size(), 0, "an untargeted ally ability aimed somewhere else: " + str(offenders))


func test_an_untargeted_self_ability_lands_on_the_caster() -> void:
	var cast := _party_with_hurt_ally()
	assert_eq(_targets(cast["cleric"], {"type": "ability", "id": "channel"}), ["Mira"] as Array[String],
		"a self-only ability aims at the caster, not at the enemy and not at the hurt ally")


func test_an_untargeted_potion_is_not_fed_to_the_goblin() -> void:
	var cast := _party_with_hurt_ally()
	assert_eq(_targets(cast["cleric"], {"type": "item", "id": "potion"}), ["Bram"] as Array[String],
		"an ally item goes to the party — ItemSystem healed the goblin 60 -> 300 on the old default")
	assert_eq(_targets(cast["cleric"], {"type": "item", "id": "bomb_fragment"}), ["Goblin"] as Array[String],
		"and an enemy item still goes to the enemy")


func test_offensive_actions_are_untouched() -> void:
	## CONTROL: the old default was right for everything offensive, which is most of the roster.
	var cast := _party_with_hurt_ally()
	assert_eq(_targets(cast["cleric"], {"type": "ability", "id": "fire"}), ["Goblin"] as Array[String], "an attack spell still aims at the enemy")
	assert_eq(_targets(cast["cleric"], {"type": "attack"}), ["Goblin"] as Array[String], "so does a plain attack")
	assert_eq(_targets(cast["cleric"], {"type": "ability", "id": "no_such_ability_id"}), ["Goblin"] as Array[String],
		"and an unknown id keeps the old default rather than guessing")


func test_a_target_the_player_wrote_is_obeyed_exactly() -> void:
	## The implied target is a DEFAULT, not a correction: the grid editor writes targets, and a player
	## who aims a heal somewhere odd gets what they asked for.
	var cast := _party_with_hurt_ally()
	assert_eq(_targets(cast["cleric"], {"type": "ability", "id": "cure", "target": "lowest_hp_enemy"}), ["Goblin"] as Array[String],
		"an explicit enemy target on a heal is still obeyed")
	assert_eq(_targets(cast["cleric"], {"type": "ability", "id": "fire", "target": "lowest_hp_ally"}), ["Bram"] as Array[String],
		"and an explicit ally target on an attack spell is too")
