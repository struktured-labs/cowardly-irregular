extends GutTest

## struktured 2026-08-22, live playtest: the victory message is "too subdued and boring",
## "but I like the idea of it pooping into center and travleing to top after", "just jazz it
## up", "and it should look more amazing against bosses or OP monsters".
##
## So the centre→top motion is KEPT and the spectacle is GRADED by who you beat. This pins the
## grading and the monotonicity — assert the RELATIONSHIP (a boss out-spectacles an elite
## out-spectacles a mob) rather than the literal tuning numbers, which are his to move.
## Also pins the skip contract for the nodes the grade adds: a ring or letterbox bar left
## on screen after the first accept press is the failure this class of change invites.

const VO := preload("res://src/battle/VictoryOverlay.gd")

## Named explicitly — a class const cannot be read by name off the script, and a helper that
## looked them up dynamically would silently check nothing if a name were misspelled.
func _tables() -> Dictionary:
	return {"GRADE_FONT": VO.GRADE_FONT, "GRADE_TRAUMA": VO.GRADE_TRAUMA, "GRADE_ZOOM": VO.GRADE_ZOOM,
		"GRADE_RINGS": VO.GRADE_RINGS, "GRADE_HOLD": VO.GRADE_HOLD, "GRADE_TINT": VO.GRADE_TINT}


class FakeScene extends Node:
	var test_enemies: Array = []
	var party_members: Array = []


func _enemy(level: int, boss_meta: bool = false, monster_type: String = "") -> Combatant:
	var c := Combatant.new()
	c.job_level = level
	c.combatant_name = monster_type if monster_type != "" else "Mob"
	if boss_meta:
		c.set_meta("is_boss", true)
		c.set_meta("monster_type", monster_type)
	return c


func _overlay(enemies: Array, party_levels: Array) -> VictoryOverlay:
	var ov := VO.new()
	add_child_autofree(ov)
	var sc := FakeScene.new()
	add_child_autofree(sc)
	for e in enemies:
		sc.test_enemies.append(e)
		ov.add_child(e)
	for lv in party_levels:
		var p := Combatant.new()
		p.job_level = int(lv)
		sc.party_members.append(p)
		ov.add_child(p)
	ov._scene = sc
	return ov


# ── grading ───────────────────────────────────────────────────────────────

func test_a_plain_mob_is_the_normal_grade() -> void:
	var ov := _overlay([_enemy(5)], [5, 5, 5])
	assert_eq(ov._victory_grade(), VO.Grade.NORMAL, "a same-level mob gets no extra spectacle")


func test_a_flagged_boss_outranks_a_miniboss() -> void:
	# cave_rat_king is boss:true in monsters.json; cave_troll is miniboss:true. The spawner
	# stamps is_boss for BOTH, so the split has to come from the monster data, not the meta.
	var boss := _overlay([_enemy(10, true, "cave_rat_king")], [8, 8, 8])
	assert_eq(boss._victory_grade(), VO.Grade.BOSS, "a boss-flagged monster grades BOSS")
	var mini := _overlay([_enemy(8, true, "cave_troll")], [8, 8, 8])
	assert_eq(mini._victory_grade(), VO.Grade.ELITE, "a miniboss carries the same meta but grades ELITE")
	assert_gt(VO.Grade.BOSS, VO.Grade.ELITE, "CONTROL: the grades are actually ordered")


func test_an_overlevelled_mob_counts_as_OP_without_any_boss_flag() -> void:
	# His words were "bosses or OP monsters" — an ordinary monster punching far above the
	# party is the second half of that, and it carries no flag anywhere in the data.
	var ov := _overlay([_enemy(11)], [7, 7, 7])
	assert_eq(ov._victory_grade(), VO.Grade.ELITE, "level gap >= OP_LEVEL_GAP reads as OP")
	var near := _overlay([_enemy(9)], [7, 7, 7])
	assert_eq(near._victory_grade(), VO.Grade.NORMAL, "a mob just above the party is still a mob")


func test_the_grade_is_the_strongest_enemy_present() -> void:
	var ov := _overlay([_enemy(5), _enemy(10, true, "cave_rat_king"), _enemy(4)], [8, 8])
	assert_eq(ov._victory_grade(), VO.Grade.BOSS, "one boss in a mixed group sets the grade")


func test_grading_survives_a_scene_that_cannot_answer() -> void:
	var ov := VO.new()
	add_child_autofree(ov)
	assert_eq(ov._victory_grade(), VO.Grade.NORMAL, "no scene, no crash — headless//autogrind path")


# ── the spectacle escalates, whatever the numbers are ─────────────────────

func test_every_grade_has_an_entry_in_every_spectacle_table() -> void:
	var tables := _tables()
	assert_eq(tables.size(), 6, "CONTROL: six spectacle tables are being checked, not zero")
	for t in tables:
		var table: Dictionary = tables[t]
		for g in [VO.Grade.NORMAL, VO.Grade.ELITE, VO.Grade.BOSS]:
			assert_true(table.has(g), "%s is missing grade %d — a half-added grade renders wrong" % [t, g])


func test_spectacle_is_monotonic_in_the_grade() -> void:
	# The tuning values are his to move; what must hold is that beating something bigger never
	# looks SMALLER. Numeric tables only — the tint table is a colour choice, not a magnitude.
	var tables := _tables()
	for t in ["GRADE_FONT", "GRADE_TRAUMA", "GRADE_ZOOM", "GRADE_RINGS", "GRADE_HOLD"]:
		var table: Dictionary = tables[t]
		var mob: float = float(table[VO.Grade.NORMAL])
		var elite: float = float(table[VO.Grade.ELITE])
		var boss: float = float(table[VO.Grade.BOSS])
		assert_gt(elite, mob, "%s: an elite kill must out-read a mob kill" % t)
		assert_gt(boss, elite, "%s: a boss kill must out-read an elite kill" % t)


func test_op_level_gap_is_a_real_threshold() -> void:
	assert_gt(VO.OP_LEVEL_GAP, 0, "a gap of 0 would grade every fight ELITE")
	assert_lt(VO.OP_LEVEL_GAP, 10, "a gap this large would never fire")


# ── the skip contract still holds for the nodes the grade adds ────────────

func test_one_press_leaves_no_ring_or_bar_on_screen() -> void:
	# complete_now() is the first accept press. Rings and letterbox bars are additions of this
	# change; if one lacks a snap it freezes mid-flight over the results the player wants to read.
	var ov := _overlay([_enemy(10, true, "cave_rat_king")], [8, 8, 8])
	ov.build({"char_results": []}, ov._scene)
	ov.complete_now()
	await get_tree().process_frame
	await get_tree().process_frame
	var leftovers: Array = []
	for child in ov.get_children():
		if child is Panel and is_instance_valid(child) and not child.is_queued_for_deletion():
			leftovers.append(child.name)
		if child is ColorRect and is_instance_valid(child) and not child.is_queued_for_deletion():
			if child.size.y < ov.size.y * 0.5 and child.color.a > 0.5:
				leftovers.append("bar:" + child.name)
	assert_eq(leftovers.size(), 0, "left on screen after the skip press: %s" % str(leftovers))
	assert_true(ov.is_complete(), "the overlay reports itself complete")
