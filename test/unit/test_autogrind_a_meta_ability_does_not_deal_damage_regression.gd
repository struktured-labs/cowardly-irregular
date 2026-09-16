extends GutTest

## `type: "meta"` has an executor in live and NO ARM in the grind, so all 24 meta abilities fell to
## the type-dispatch default — which deals MAGIC DAMAGE when the target is on the opposing side.
##
## Live's `_execute_meta_ability` (BattleManager:6427) matches on `meta_effect` and does reality
## manipulation: battle-log narrative plus `GameState.add_corruption(corruption_risk)`. It deals no
## damage on any branch. So the grind invented a damage number the game never deals.
##
## EIGHT of the 24 target the opposing side and therefore reach the damaging branch:
##   single_enemy  permakill · mind_swap · boss_puppet · control_override · mutual_destruction
##   all_enemies   corrupt_save · save_deletion · time_stop
##
## 🔑 REACHABLE BY THE GRIND'S OWN SPAWNER, which is what makes this more than a meta-job curiosity:
## `permadeath_reaper` casts `save_deletion` and carries `autogrind_spawned: true`, so
## AutogrindSystem.build_meta_boss_enemy_data instantiates it directly (form 4). Its target_type is
## `all_enemies` — from the reaper's side that is the PARTY. A grind's meta boss was dealing magic
## damage to the whole party that live does not deal, in the one context where damage matters most:
## the fatigue-collapse boss fight, with permadeath staking available.
##
## ⚠️ THE MECHANICS ARE NOT PORTED AND THIS ARM DOES NOT PORT THEM. Save deletion, permakill and
## mind-swap are save-side and scene-side, and `corruption_risk` / `corruption_amount` are already
## DECLARED in the parity ledger as struktured's stakes ruling rather than a parity repair. The fix
## is that an unmodelled meta ability is a NO-OP — the rule this file's support arm already states:
## "an effect we do not model is a NO-OP, never damage."
##
## ⛔ AND I MISCOUNTED THESE TWICE WHILE SCOUTING. `'enemy' in 'all_enemies'` is FALSE — the plural is
## "enemies" — so my first filter reported 5 of 8 and hid the three that matter, including the one
## the grind's own spawner casts. An English pluralisation assumption inside a substring test.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _combatant(name: String, hp: int = 5000) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": hp, "max_mp": 999,
		"attack": 40, "defense": 10, "magic": 400, "speed": 10})
	add_child_autofree(c)
	c.current_mp = c.max_mp
	c.current_hp = hp
	return c


func _authored(ability_id: String) -> Dictionary:
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return {}
	return js.get_ability(ability_id)


func test_a_meta_ability_cast_at_an_enemy_deals_no_damage() -> void:
	var ab: Dictionary = _authored("permakill")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	assert_eq(str(ab.get("type", "")), "meta", "CONTROL: permakill must still be meta-typed")
	var caster := _combatant("Necromancer")
	var foe := _combatant("Victim")
	_res._player_party = [caster]
	_res._enemy_party = [foe]
	var hp_before: int = foe.current_hp
	_res._resolve_ability(caster, "permakill", [foe])
	gut.p("    permakill: foe hp %d -> %d" % [hp_before, foe.current_hp])
	assert_eq(foe.current_hp, hp_before,
		"live's meta executor deals no damage on any branch — the grind's default arm invented %d" % (hp_before - foe.current_hp))


func test_the_grinds_own_meta_boss_does_not_invent_damage() -> void:
	## The reachable one. save_deletion is cast by permadeath_reaper, which the grind's meta-boss
	## builder instantiates directly, and its all_enemies target is the PARTY.
	var ab: Dictionary = _authored("save_deletion")
	if ab.is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var reaper := _combatant("Permadeath Reaper")
	var hero_a := _combatant("Hero A")
	var hero_b := _combatant("Hero B")
	_res._player_party = [hero_a, hero_b]
	_res._enemy_party = [reaper]
	var a0: int = hero_a.current_hp
	var b0: int = hero_b.current_hp
	_res._resolve_ability(reaper, "save_deletion", [hero_a, hero_b])
	gut.p("    save_deletion: party %d/%d -> %d/%d" % [a0, b0, hero_a.current_hp, hero_b.current_hp])
	assert_eq(hero_a.current_hp, a0, "the meta boss must not damage the party with a save-corruption ability")
	assert_eq(hero_b.current_hp, b0, "and not the second member either")


func test_a_self_targeted_meta_ability_is_still_a_no_op() -> void:
	## The 14 self-targeted ones already produced "no effect" via the default's same-side branch.
	## Pinned so the new arm does not accidentally change what already behaved.
	if _authored("quicksave").is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var mage := _combatant("Time Mage")
	_res._player_party = [mage]
	_res._enemy_party = [_combatant("Foe")]
	var hp0: int = mage.current_hp
	_res._resolve_ability(mage, "quicksave", [mage])
	assert_eq(mage.current_hp, hp0, "a self-targeted meta ability must not damage its caster")


func test_a_real_damage_ability_still_damages() -> void:
	## CONTROL. Without it the fix could be "nothing damages anything" and every arm above passes.
	if _authored("fire").is_empty():
		pass_test("JobSystem autoload unavailable")
		return
	var mage := _combatant("Mage")
	var foe := _combatant("Foe")
	_res._player_party = [mage]
	_res._enemy_party = [foe]
	var hp0: int = foe.current_hp
	_res._resolve_ability(mage, "fire", [foe])
	assert_lt(foe.current_hp, hp0, "a magic ability must still deal damage — this fix is about type=meta only")


func test_the_reachability_this_rests_on_still_holds() -> void:
	## Crying-wolf arm: if permadeath_reaper stops being autogrind_spawned or stops casting
	## save_deletion, the severity argument in the header weakens and should be re-read.
	var es: Node = get_node_or_null("/root/EncounterSystem")
	if es == null or es.monster_database.is_empty():
		pass_test("EncounterSystem unavailable")
		return
	var reaper: Dictionary = es.monster_database.get("permadeath_reaper", {})
	assert_false(reaper.is_empty(), "permadeath_reaper must still exist — it is the grind's own meta boss")
	assert_true(bool(reaper.get("autogrind_spawned", false)),
		"and must still be autogrind_spawned, or form 4 no longer reaches it")
	assert_true("save_deletion" in (reaper.get("abilities", []) as Array),
		"and must still cast save_deletion, which is the meta ability that reaches the party")
