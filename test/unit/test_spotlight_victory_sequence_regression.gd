extends GutTest

## struktured 2026-09-07: "spotlight should have a victory sequence just like reg battles, maybe
## make it special because its a spotlight tho". Before: GameLoop's spotlight short-circuit
## emitted spotlight_battle_ended the instant the win fired, start_solo_battle tore the scene
## down under the cutscene layer, and the VictoryOverlay BattleScene had just built was freed
## unseen. Now the duelist gets the same confirm-gated sequence, graded SPOTLIGHT and billed
## to them by name.

const VO := preload("res://src/battle/VictoryOverlay.gd")
const GL_SRC := "res://src/GameLoop.gd"
const RD_SRC := "res://src/battle/BattleResultsDisplay.gd"


class FakeScene extends Node:
	var test_enemies: Array = []
	var party_members: Array = []


func _overlay(with_boss: bool) -> VictoryOverlay:
	var ov := VO.new()
	add_child_autofree(ov)
	var sc := FakeScene.new()
	add_child_autofree(sc)
	var e := Combatant.new()
	e.job_level = 8
	e.combatant_name = "Skeleton Knight"
	if with_boss:
		e.set_meta("is_boss", true)
		e.set_meta("monster_type", "cave_rat_king")
	sc.test_enemies.append(e)
	ov.add_child(e)
	var p := Combatant.new()
	p.job_level = 5
	sc.party_members.append(p)
	ov.add_child(p)
	ov._scene = sc
	return ov


func test_a_duelist_makes_the_grade_spotlight_above_any_boss() -> void:
	var plain := _overlay(true)
	assert_eq(plain._victory_grade(), VO.Grade.BOSS, "CONTROL: without a duelist the same foe grades BOSS")
	var duel := _overlay(true)
	duel.spotlight_duelist = "Fighter"
	assert_eq(duel._victory_grade(), VO.Grade.SPOTLIGHT, "a live duel outranks the foe's own grade")
	assert_gt(VO.Grade.SPOTLIGHT, VO.Grade.BOSS, "CONTROL: SPOTLIGHT is the top grade")


func test_spotlight_spectacle_is_at_least_boss_scale_in_every_table() -> void:
	for table in [VO.GRADE_FONT, VO.GRADE_TRAUMA, VO.GRADE_ZOOM, VO.GRADE_RINGS, VO.GRADE_HOLD, VO.GRADE_TINT]:
		assert_true(table.has(VO.Grade.SPOTLIGHT), "every spectacle table needs a SPOTLIGHT row or the slam crashes on lookup")
	for table in [VO.GRADE_FONT, VO.GRADE_TRAUMA, VO.GRADE_ZOOM, VO.GRADE_RINGS, VO.GRADE_HOLD]:
		assert_true(float(table[VO.Grade.SPOTLIGHT]) >= float(table[VO.Grade.BOSS]),
			"'make it special' — a spotlight win must never be quieter than a boss kill")


func test_the_subtitle_bills_the_duelist_by_name() -> void:
	var ov := _overlay(false)
	ov.spotlight_duelist = "Bard"
	var sub: Label = ov._build_subtitle(Vector2(100, 100), Vector2(300, 60), Color.WHITE, false)
	assert_not_null(sub, "a spotlight win gets a subtitle even when no boss meta names a foe")
	assert_true(sub.text.contains("BARD"), "the duelist is the headline: %s" % sub.text)
	var boss := _overlay(true)
	boss.spotlight_duelist = "Cleric"
	var sub2: Label = boss._build_subtitle(Vector2(100, 100), Vector2(300, 60), Color.WHITE, false)
	assert_true(sub2.text.contains("CLERIC") and sub2.text.contains("SKELETON KNIGHT"),
		"with a named foe both are billed: %s" % sub2.text)


func test_the_results_display_tags_the_overlay_from_the_live_duel_flag() -> void:
	var src := FileAccess.get_file_as_string(RD_SRC)
	var i: int = src.find("func show_victory_results")
	var body := src.substr(i, 1200)
	assert_true(body.contains("_spotlight_duel_active") and body.contains("spotlight_duelist ="),
		"show_victory_results must read GameLoop's duel flag and stamp the duelist on the overlay")


func test_the_spotlight_short_circuit_waits_for_the_victory_confirm_before_handing_back() -> void:
	# The fix is an ORDER: confirm first, emit second. Pinned by index, not by presence.
	var src := FileAccess.get_file_as_string(GL_SRC)
	var block_start: int = src.find("if _spotlight_duel_active:", src.find("func _on_battle_ended"))
	assert_gt(block_start, 0, "CONTROL: the spotlight short-circuit still exists in _on_battle_ended")
	var emit_at: int = src.find("spotlight_battle_ended.emit(victory)", block_start)
	var wait_at: int = src.find("await _wait_for_confirm_victory()", block_start)
	assert_gt(emit_at, 0, "CONTROL: the emit is still there")
	assert_true(wait_at > 0 and wait_at < emit_at,
		"the duelist must get to see (and dismiss) the victory overlay BEFORE the cutscene resumes and frees the scene")
