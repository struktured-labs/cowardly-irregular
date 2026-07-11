extends GutTest

## Struktured balance ruling 2026-07-11 (cowir-main msg 2376): a full-HP
## solo duelist must NEVER die to a single boss action in a spotlight duel.
##
## Standard: solo-duel clutch floor at 1 HP for any single hit that would
## take the duelist from full HP straight to 0. Fires unconditionally
## (not the death_resistance chance roll). Only applies inside a solo
## spotlight duel — normal battles keep their existing lethality.
##
## Also pinned: Lockward's masterite_precise_strike damage_multiplier
## dropped from 2.5 → 1.8 so the floor is a rare backstop rather than
## the routine experience.


## ── Behavioral: the floor engages in a live spotlight duel ─────────────

const CombatantScript = preload("res://src/battle/Combatant.gd")


func _duelist(max_hp: int = 100) -> Combatant:
	var c := CombatantScript.new()
	c.combatant_name = "Duelist"
	c.max_hp = max_hp
	c.current_hp = max_hp
	c.attack = 10
	c.defense = 5
	c.speed = 12
	c.job = {"id": "rogue"}
	c.is_alive = true
	# Combatant is a Node; the take_damage floor consults GameState via
	# get_tree() so the instance needs a tree parent.
	add_child_autofree(c)
	return c


## Ensure /root/GameLoop exposes _spotlight_duel_active for behavioral runs;
## return a "restore" callable so we can toggle back cleanly regardless of
## whether we found the real one or had to install a stub.
class _GameLoopStub extends Node:
	var _spotlight_duel_active: bool = false


func _ensure_game_loop_with_flag() -> Node:
	var existing: Node = get_tree().root.get_node_or_null("GameLoop")
	if existing != null:
		# Real GameLoop present in the test host — behavioral flip is fine.
		return existing
	var stub: _GameLoopStub = _GameLoopStub.new()
	stub.name = "GameLoop"
	get_tree().root.add_child(stub)
	return stub


func before_each() -> void:
	var gl := _ensure_game_loop_with_flag()
	gl._spotlight_duel_active = false


func after_each() -> void:
	var gl: Node = get_tree().root.get_node_or_null("GameLoop")
	if gl == null:
		return
	if gl is _GameLoopStub:
		gl.queue_free()
		return
	gl._spotlight_duel_active = false


func test_full_hp_lockward_one_shot_floors_to_one_in_solo_duel() -> void:
	var gl: Node = get_tree().root.get_node_or_null("GameLoop")
	assert_not_null(gl, "before_each should have installed a GameLoop node")
	gl._spotlight_duel_active = true
	var pc := _duelist(100)
	var actual: int = pc.take_damage(999)
	assert_gt(actual, 0, "damage still applied")
	assert_eq(pc.current_hp, 1, "full-HP → 0 in a solo spotlight duel must floor to 1")
	assert_true(pc.is_alive, "1 HP means the duelist is still alive")


func test_normal_battle_full_hp_one_shot_still_kills() -> void:
	# The floor MUST NOT engage outside a spotlight duel — normal battle
	# lethality is preserved. A dying enemy adventurer party, a boss chunk
	# in a regular fight, autogrind risk — none should get the guardrail.
	var gl: Node = get_tree().root.get_node_or_null("GameLoop")
	if gl:
		gl._spotlight_duel_active = false
	var pc := _duelist(100)
	pc.take_damage(999)
	assert_eq(pc.current_hp, 0, "normal battle one-shot kills as before")


func test_partial_hp_hit_does_not_engage_the_floor() -> void:
	# Design intent (struktured msg 2376): "from FULL HP to 0". A hit that
	# lands the duelist at 0 from partial HP is honest damage, not the
	# opener-one-shot pattern the floor protects.
	var gl: Node = get_tree().root.get_node_or_null("GameLoop")
	assert_not_null(gl, "before_each should have installed a GameLoop node")
	gl._spotlight_duel_active = true
	var pc := _duelist(100)
	pc.current_hp = 40
	pc.take_damage(999)
	assert_eq(pc.current_hp, 0, "partial-HP → 0 is NOT protected, only full-HP one-shots")


func test_fatal_hit_when_hp_gt_zero_but_below_max_still_kills_in_duel() -> void:
	# Same regression as above from the other side — even in a duel,
	# a duelist at 99/100 HP taking a 1000-damage hit dies.
	var gl: Node = get_tree().root.get_node_or_null("GameLoop")
	assert_not_null(gl, "before_each should have installed a GameLoop node")
	gl._spotlight_duel_active = true
	var pc := _duelist(100)
	pc.current_hp = 99
	pc.take_damage(999)
	assert_eq(pc.current_hp, 0, "99/100 → 0 is not a full-HP one-shot")


## ── Data pin: precise_strike multiplier landed ─────────────────────────

func test_precise_strike_multiplier_is_18() -> void:
	# Struktured msg 2376: 2.5 → ~1.8. If a future edit shifts this
	# without a matching design ruling, the pin fires.
	var f := FileAccess.open("res://data/abilities.json", FileAccess.READ)
	assert_not_null(f)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	assert_true(data.has("masterite_precise_strike"))
	var ps: Dictionary = data["masterite_precise_strike"]
	assert_almost_eq(float(ps.get("damage_multiplier", -1.0)), 1.8, 0.001,
		"masterite_precise_strike must be 1.8 per struktured msg 2376 balance ruling")


## ── Wiring pin: the floor lives at the right seam ──────────────────────

func test_floor_wired_in_take_damage_before_death_resistance() -> void:
	# Textual pin: the floor block must sit BEFORE the tick-439 death
	# resistance block so it fires unconditionally rather than getting
	# a chance roll layered on top.
	var src: String = FileAccess.get_file_as_string("res://src/battle/Combatant.gd")
	var floor_idx: int = src.find("[SPOTLIGHT-FLOOR]")
	var deathres_idx: int = src.find("death_resistance passive")
	assert_gt(floor_idx, -1, "floor block must be present")
	assert_gt(deathres_idx, -1, "death_resistance block must be present")
	assert_lt(floor_idx, deathres_idx,
		"floor must fire BEFORE death_resistance so the roll can't undo the guarantee")


func test_floor_gated_on_full_hp_condition() -> void:
	# Guard against a future refactor that drops the "old_hp == max_hp"
	# constraint — that would over-generalize the floor to any KO hit
	# and break normal battle lethality.
	var src: String = FileAccess.get_file_as_string("res://src/battle/Combatant.gd")
	var floor_idx: int = src.find("[SPOTLIGHT-FLOOR]")
	var window: String = src.substr(maxi(0, floor_idx - 400), 800)
	assert_string_contains(window, "old_hp == max_hp",
		"floor must require the pre-hit HP to be at max — otherwise partial-HP KO gets protected too")
	assert_string_contains(window, "_spotlight_duel_active",
		"floor must consult GameLoop._spotlight_duel_active — normal battles keep their lethality")
