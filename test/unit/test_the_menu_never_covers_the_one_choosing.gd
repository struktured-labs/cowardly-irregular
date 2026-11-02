extends GutTest

## The two-rank party (struktured 2026-11-01: "the rogue/bard are sorta stacked") put its front rank in the command menu's
## column, and cowir-main caught it on the after-shot: the selecting Fighter stood BEHIND the menu on his own turn. The
## old guard (test_command_menu_does_not_cover_actor) only asks that the menu be translucent where it overlaps the
## column, which is still true; this one asks the stronger thing on the LIVE layout: the menu never covers the member
## who is choosing, in any formation, at 100% or 200% text. BattleCommandMenu.menu_clear_of moves it below, above, or
## to the left of that member's stepped-out figure.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BS := preload("res://src/battle/BattleScene.gd")
const CMD := preload("res://src/battle/BattleCommandMenu.gd")
const AdvanceAuraScript := preload("res://src/battle/AdvanceAura.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

const VP := Vector2(1280, 720)

var _guard
var _saved_scale := 1.0
var _saved_text := 1.0


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_saved_scale = Engine.time_scale
	_saved_text = GameState.text_size_scale


func after_each() -> void:
	GameState.set_text_size_scale(_saved_text)
	Engine.time_scale = _saved_scale
	_guard.restore()


func after_all() -> void:
	SoundState.restore()


func test_a_clear_menu_stays_put() -> void:
	var menu := Rect2(537, 100, 220, 240)
	assert_eq(CMD.menu_clear_of(Rect2(800, 100, 150, 200), menu, VP), menu.position)


func test_a_covering_menu_goes_below_the_actor() -> void:
	var actor := Rect2(600, 60, 180, 170)
	var at: Vector2 = CMD.menu_clear_of(actor, Rect2(537, 30, 220, 240), VP)
	assert_eq(at, Vector2(537, actor.end.y + 8.0), "room below the actor, so the menu sits under it")


func test_with_no_room_below_it_goes_above() -> void:
	var actor := Rect2(600, 470, 180, 180)
	var at: Vector2 = CMD.menu_clear_of(actor, Rect2(537, 420, 220, 240), VP)
	assert_eq(at, Vector2(537, actor.position.y - 8.0 - 240.0), "no room below, so above")


func test_with_no_room_either_way_it_goes_left() -> void:
	var actor := Rect2(600, 150, 180, 400)
	var at: Vector2 = CMD.menu_clear_of(actor, Rect2(537, 150, 220, 300), VP)
	assert_eq(at.x, maxf(10.0, actor.position.x - 8.0 - 220.0), "neither fits, so it stands to the left")


func test_the_live_menu_never_covers_the_one_choosing() -> void:
	var bad: Array = []
	var judged := 0
	for ts in [1.0, 2.0]:
		GameState.set_text_size_scale(ts)
		var scene = SCENE.instantiate()
		scene.encounter_enemies = ["goblin", "goblin", "goblin"]
		add_child_autofree(scene)
		Engine.time_scale = 1.0
		await get_tree().create_timer(0.4).timeout
		## The default battle story-locks all but the Hero, and the menu (rightly) never opens for a locked member.
		for m in BattleManager.player_party:
			if "autobattle_locked" in m:
				m.autobattle_locked = false
		for f in BS.FORMATION_NAMES.size():
			if f > 0:
				scene._command_menu.close_win98_menu()
				scene.cycle_formation()
				await get_tree().create_timer(0.4).timeout
			for i in scene.party_sprite_nodes.size():
				var member = BattleManager.player_party[i] if i < BattleManager.player_party.size() else null
				if member == null:
					continue
				scene._command_menu.close_win98_menu()
				scene._step_active_pc(member, true)
				scene._show_win98_command_menu(member)
				await get_tree().create_timer(0.45).timeout
				var menu = scene.active_win98_menu
				if menu == null or not is_instance_valid(menu):
					bad.append("text %.2f %s #%d: no menu opened" % [ts, BS.FORMATION_NAMES[scene.current_formation], i])
					continue
				var sprite: AnimatedSprite2D = scene.party_sprite_nodes[i]
				var fig: Rect2 = AdvanceAuraScript.figure_rect_in_sprite(sprite, &"idle")
				var body := Rect2(sprite.global_position + fig.position, fig.size)
				var mr: Rect2 = (menu as Control).get_global_rect()
				judged += 1
				if mr.intersects(body):
					bad.append("text %.2f %s: %s's menu %s covers them %s" % [ts, BS.FORMATION_NAMES[scene.current_formation],
						member.combatant_name, str(mr), str(body)])
				scene._command_menu.close_win98_menu()
				scene._step_active_pc(member, false)
				await get_tree().create_timer(0.25).timeout
		scene.queue_free()
		await get_tree().process_frame
	assert_eq(judged, 2 * BS.FORMATION_NAMES.size() * 5, "CONTROL: a menu opened for every member, every formation, both sizes")
	assert_eq(bad, [], "%d covered:\n%s" % [bad.size(), "\n".join(bad.slice(0, 8))])
