extends GutTest

## CTB ruling (struktured 2026-10-03): the battle is CTB, not a system where selection and
## execution are the same moment. A single-ally heal/revive's target menu must let the player
## pick ANY ally — full HP, hurt, or KO'd for a heal; living or KO'd for a revive — because the
## player cannot know what state the target will be in once the queued action actually resolves.
## At execution time the guess is honored if it still holds, and otherwise the action infers a
## sensible target instead of wasting itself (struktured's follow-up ruling, same date): a
## revive whose target came back alive looks for someone else down; a heal whose target died or
## is now full looks for someone who needs it. If nobody qualifies, the action does not fire and
## costs nothing.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

class FakeScene extends Node2D:
	var party_members: Array = []
	var party_sprite_nodes: Array = []
	var test_enemies: Array = []
	var enemy_sprite_nodes: Array = []


var _bm = null


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)


func _member(cname: String, hp: int, max_hp: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": cname, "max_hp": max_hp, "max_mp": 80, "attack": 10, "defense": 10, "magic": 20, "speed": 10})
	add_child_autofree(c)
	c.current_hp = hp
	c.current_mp = 80
	c.is_alive = hp > 0
	c.learned_abilities.append_array(["cure", "raise"])
	return c


func _menu(members: Array) -> BattleCommandMenu:
	var scene := FakeScene.new()
	add_child_autofree(scene)
	scene.party_members = members
	return BattleCommandMenu.new(scene)


func _ally_row_labels(menu: BattleCommandMenu, ability_id: String, caster: Combatant) -> Array:
	var row: Dictionary = menu._build_ability_menu_item(ability_id, caster, [], Transform2D.IDENTITY)
	var out: Array = []
	for s in row.get("submenu", []):
		out.append(str(s.get("label", "")))
	return out


func _parties(heroes: Array, foes: Array) -> void:
	_bm.player_party.clear()
	_bm.enemy_party.clear()
	for h in heroes:
		_bm.player_party.append(h)
	for f in foes:
		_bm.enemy_party.append(f)


# ── Selection-time menu: any ally is pickable ───────────────────────

func test_a_full_hp_ally_appears_and_is_tagged_in_cures_target_list() -> void:
	var caster := _member("Cleric", 400, 400)
	var full := _member("Full Fighter", 400, 400)
	var menu := _menu([caster, full])
	var labels := _ally_row_labels(menu, "cure", caster)
	var hit := labels.filter(func(l): return l.begins_with("Full Fighter"))
	assert_eq(hit.size(), 1, "a full-HP ally must appear in Cure's target list")
	assert_true(str(hit[0]).contains("[Full]"), "the full-HP ally's row must carry a visible state tag, not a hardcoded label: %s" % hit[0])


func test_a_kod_ally_appears_and_is_tagged_in_cures_target_list() -> void:
	var caster := _member("Cleric", 400, 400)
	var fallen := _member("Fallen Bard", 0, 400)
	fallen.is_alive = false
	var menu := _menu([caster, fallen])
	var labels := _ally_row_labels(menu, "cure", caster)
	var hit := labels.filter(func(l): return l.begins_with("Fallen Bard"))
	assert_eq(hit.size(), 1, "a KO'd ally must still appear in Cure's target list — the player is guessing at resolution-time state")
	assert_true(str(hit[0]).contains("KO'd"), "a KO'd target's row must say so: %s" % hit[0])


func test_a_living_ally_appears_in_raises_target_list() -> void:
	var caster := _member("Cleric", 400, 400)
	var standing := _member("Standing Fighter", 400, 400)
	var menu := _menu([caster, standing])
	var labels := _ally_row_labels(menu, "raise", caster)
	var hit := labels.filter(func(l): return l.begins_with("Standing Fighter"))
	assert_eq(hit.size(), 1, "a living ally must appear in Raise's target list — the player is guessing at resolution-time state")


func test_a_kod_ally_still_appears_in_raises_target_list() -> void:
	var caster := _member("Cleric", 400, 400)
	var fallen := _member("Fallen Rogue", 0, 400)
	fallen.is_alive = false
	var menu := _menu([caster, fallen])
	var labels := _ally_row_labels(menu, "raise", caster)
	var hit := labels.filter(func(l): return l.begins_with("Fallen Rogue"))
	assert_eq(hit.size(), 1, "CONTROL: a KO'd ally must remain a Raise target")


# ── Selection-time confirm gate (BattleCommandMenu._is_valid_ability_target) ────────

func test_confirm_gate_accepts_full_hp_cure_target() -> void:
	var menu := _menu([])
	var target := _member("Full", 400, 400)
	assert_true(menu._is_valid_ability_target("cure", "ally", target),
		"confirming Cure on a full-HP ally must be accepted at selection time")


func test_confirm_gate_accepts_dead_cure_target() -> void:
	var menu := _menu([])
	var target := _member("Dead", 0, 400)
	target.is_alive = false
	assert_true(menu._is_valid_ability_target("cure", "ally", target),
		"confirming Cure on a dead ally must be accepted — execution decides the effect")


func test_confirm_gate_accepts_living_raise_target() -> void:
	var menu := _menu([])
	var target := _member("Alive", 400, 400)
	assert_true(menu._is_valid_ability_target("raise", "dead_ally", target),
		"confirming Raise on a living ally must be accepted — execution decides the effect")


func test_confirm_gate_still_rejects_a_dead_enemy() -> void:
	var menu := _menu([])
	var target := _member("Dead Enemy", 0, 400)
	target.is_alive = false
	assert_false(menu._is_valid_ability_target("fire", "enemy", target),
		"enemy targeting must be unaffected by the ruling — a dead enemy is still invalid")


func test_confirm_gate_accepts_any_ally_for_a_revive_item() -> void:
	var menu := _menu([])
	var alive := _member("Alive", 400, 400)
	assert_true(menu._is_valid_item_target("phoenix_down", "ally", alive),
		"a revive item must be confirmable on a living ally")


func test_confirm_gate_still_requires_alive_for_a_pure_buff_item() -> void:
	## elixir restores both HP and MP (heal_hp_percent + heal_mp_percent) — if items.json ever
	## adds a pure stat-buff single-ally item with no heal/revive key, it must stay alive-only.
	var menu := _menu([])
	var dead := _member("Dead", 0, 400)
	dead.is_alive = false
	assert_false(menu._is_valid_item_target("___no_such_item___", "ally", dead),
		"an item with no heal/revive effects (including an unresolvable id) must keep the alive-only gate")


# ── Execution-time: the honored guess ───────────────────────────────

func test_cure_aimed_at_the_hurt_ally_who_stayed_hurt_lands_on_them() -> void:
	var caster := _member("Cleric", 400, 400)
	var hurt := _member("Hurt Fighter", 100, 400)
	_parties([caster, hurt], [_member("Foe", 999, 999)])
	_bm._execute_ability(caster, "cure", [hurt])
	assert_gt(hurt.current_hp, 100, "the premise held (still hurt) — the heal must land on the chosen ally")


func test_raise_aimed_at_the_corpse_that_stayed_a_corpse_lands_on_them() -> void:
	var caster := _member("Cleric", 400, 400)
	var fallen := _member("Fallen Fighter", 0, 400)
	fallen.is_alive = false
	_parties([caster, fallen], [_member("Foe", 999, 999)])
	_bm._execute_ability(caster, "raise", [fallen])
	assert_true(fallen.is_alive, "the premise held (still dead) — the revive must land on the chosen ally")


# ── Execution-time: the inference when the guess was wrong ─────────

func test_raise_aimed_at_a_now_living_ally_infers_the_one_who_is_actually_down() -> void:
	var caster := _member("Cleric", 400, 400)
	var guessed_wrong := _member("Healed Mid-Turn", 400, 400)  # was dead at selection, revived by an earlier action this phase
	var actually_down := _member("Still Down", 0, 400)
	actually_down.is_alive = false
	_parties([caster, guessed_wrong, actually_down], [_member("Foe", 999, 999)])
	_bm._execute_ability(caster, "raise", [guessed_wrong])
	assert_true(actually_down.is_alive, "the guess was wrong (target came back alive) — Raise must infer the ally who is actually down")
	assert_eq(guessed_wrong.current_hp, 400, "the living ally the guess named must not be touched by revive()")


func test_raise_with_nobody_down_does_not_fire_and_spends_no_mp() -> void:
	var caster := _member("Cleric", 400, 400)
	var standing := _member("Standing Ally", 400, 400)
	_parties([caster, standing], [_member("Foe", 999, 999)])
	var mp_before := caster.current_mp
	_bm._execute_ability(caster, "raise", [standing])
	assert_eq(caster.current_mp, mp_before, "nobody is down — Raise must not fire or spend MP")


func test_cure_aimed_at_a_dead_ally_infers_the_lowest_hp_living_ally() -> void:
	var caster := _member("Cleric", 400, 400)
	var dead_target := _member("Died Mid-Turn", 0, 400)
	dead_target.is_alive = false
	var lowest := _member("Lowest HP", 40, 400)
	var higher := _member("Higher HP", 300, 400)
	_parties([caster, dead_target, lowest, higher], [_member("Foe", 999, 999)])
	_bm._execute_ability(caster, "cure", [dead_target])
	assert_gt(lowest.current_hp, 40, "the chosen target died — Cure must infer the lowest-HP% living ally")
	assert_eq(higher.current_hp, 300, "a higher-HP ally must not be the inferred target while a lower one exists")


func test_cure_aimed_at_a_now_full_hp_ally_infers_someone_who_needs_it() -> void:
	var caster := _member("Cleric", 400, 400)
	var guessed_full := _member("Topped Off Mid-Turn", 400, 400)  # was hurt at selection, healed by an earlier action
	var needs_it := _member("Still Hurt", 50, 400)
	_parties([caster, guessed_full, needs_it], [_member("Foe", 999, 999)])
	_bm._execute_ability(caster, "cure", [guessed_full])
	assert_gt(needs_it.current_hp, 50, "the guessed target is full — Cure must redirect to the ally who actually needs it")


func test_cure_with_nobody_hurt_does_not_fire_and_spends_no_mp() -> void:
	var caster := _member("Cleric", 400, 400)
	var full := _member("Full Ally", 400, 400)
	_parties([caster, full], [_member("Foe", 999, 999)])
	var mp_before := caster.current_mp
	_bm._execute_ability(caster, "cure", [full])
	assert_eq(caster.current_mp, mp_before, "nobody needs healing — Cure must not fire or spend MP")
	assert_eq(full.current_hp, full.max_hp, "the full ally must stay at max — no phantom heal")


# ── Items: Phoenix Down mirrors the ability-side inference ──────────

func test_phoenix_down_aimed_at_a_living_ally_infers_the_one_who_is_down() -> void:
	var user := _member("Feather User", 400, 400)
	user.add_item("phoenix_down", 1)
	var guessed_wrong := _member("Healed Mid-Turn", 400, 400)
	var actually_down := _member("Still Down", 0, 400)
	actually_down.is_alive = false
	_parties([user, guessed_wrong, actually_down], [_member("Foe", 999, 999)])
	_bm._execute_item(user, "phoenix_down", [guessed_wrong])
	assert_true(actually_down.is_alive, "Phoenix Down must infer the ally who is actually down")
	assert_eq(user.get_item_count("phoenix_down"), 0, "the feather is spent when the inferred revive lands")


func test_phoenix_down_with_nobody_down_does_not_spend_the_item() -> void:
	var user := _member("Feather User", 400, 400)
	user.add_item("phoenix_down", 1)
	var standing := _member("Standing Ally", 400, 400)
	_parties([user, standing], [_member("Foe", 999, 999)])
	_bm._execute_item(user, "phoenix_down", [standing])
	assert_eq(user.get_item_count("phoenix_down"), 1, "nobody is down — Phoenix Down must not be spent")
