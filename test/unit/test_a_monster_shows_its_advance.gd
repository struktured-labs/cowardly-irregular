extends GutTest

## struktured via main 23349: "make it obvious when a monster Advances or Defers". Measured on .788 (battle 23350): an
## enemy's Advance was chosen at selection with nothing shown, executed with the PARTY's cue, and its Defer had no sound
## and no visual. Now the monster powers up at selection (aura + "×N" pip, kept until it acts, so it reads at 64x),
## spends a pip per sub-action, plays cowir-sfx's enemy_advance_N / enemy_defer, and braces on a Defer.

const SCENE := "res://src/battle/BattleScene.tscn"
const BattleState := preload("res://test/unit/helpers/battle_state.gd")

var _guard: RefCounted = null


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()


func after_each() -> void:
	if _guard != null:
		_guard.restore()


func _sprite() -> AnimatedSprite2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var frames := SpriteFrames.new()
	frames.add_animation(&"idle")
	frames.add_frame(&"idle", ImageTexture.create_from_image(img))
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.animation = &"idle"
	add_child_autofree(s)
	return s


func _foe(nm: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": nm, "max_hp": 10, "max_mp": 0, "attack": 1, "defense": 1, "magic": 1, "speed": 1})
	add_child_autofree(c)
	return c


func _advance(c: Combatant, n: int) -> Dictionary:
	var acts: Array = []
	for i in n:
		acts.append({"type": "attack", "target": null})
	return {"type": "advance", "combatant": c, "actions": acts}


## A real scene with one enemy on one sprite, wired the way _on_enemy_died's guard wires it.
func _scene_with(foe: Combatant, spr: AnimatedSprite2D) -> Node:
	var scene = load(SCENE).instantiate()
	add_child_autofree(scene)
	scene.test_enemies.assign([foe] as Array[Combatant])
	scene.enemy_sprite_nodes.assign([spr])
	BattleManager.enemy_party.assign([foe])
	var animator = load("res://src/battle/BattleAnimator.gd").new()
	animator.setup(spr)
	scene.add_child(animator)
	scene.enemy_animators.assign([animator])
	return scene


func test_the_tell_counts_down_and_clears() -> void:
	var spr := _sprite()
	var foe := _foe("Goblin")
	var t := EnemyAdvanceTell.on(spr)
	t.show_queue(3, foe, Color.WHITE)
	assert_true(t.is_showing(), "CONTROL: a ×3 queue shows")
	assert_eq(t.pip().text, "×3", "the pip says how many are coming")
	assert_true(t.aura().visible, "and the aura is up")
	t.spend()
	assert_eq(t.pip().text, "×2", "each resolved action spends one")
	t.spend()
	assert_false(t.is_showing(), "a ×1 is no longer an Advance, so the tell clears")
	assert_false(t.aura().visible, "aura included")
	assert_eq(EnemyAdvanceTell.on(spr), t, "one tell per sprite, reused")


func test_the_tell_leaves_with_a_fallen_monster() -> void:
	var spr := _sprite()
	var foe := _foe("Goblin")
	var t := EnemyAdvanceTell.on(spr)
	t.show_queue(4, foe, Color.WHITE)
	assert_true(t.is_showing(), "CONTROL: shown")
	foe.die()
	assert_false(t.is_showing(), "a monster that falls mid-queue does not keep promising its Advance")


func test_an_enemy_advance_powers_up_at_selection_and_spends_as_it_acts() -> void:
	var spr := _sprite()
	var foe := _foe("Goblin")
	var scene := _scene_with(foe, spr)
	BattleManager.pending_actions = [{"type": "attack", "combatant": foe, "target": null}]
	scene._on_selection_turn_ended(foe)
	assert_null(spr.get_node_or_null(EnemyAdvanceTell.NODE_NAME), "CONTROL: a plain attack shows no tell")
	BattleManager.pending_actions = [_advance(foe, 3)]
	scene._on_selection_turn_ended(foe)
	var t := spr.get_node_or_null(EnemyAdvanceTell.NODE_NAME) as EnemyAdvanceTell
	assert_not_null(t, "choosing an Advance raises the tell on that monster")
	if t == null:
		return
	assert_eq(t.pip().text, "×3", "sized to the queue it chose")
	scene._on_action_executed(foe, {"type": "attack", "target": null}, [])
	assert_eq(t.pip().text, "×2", "a resolved sub-action spends one")
	scene._on_action_executed(foe, {"type": "advance", "actions": []}, [])
	assert_false(t.is_showing(), "the Advance's own resolution clears the rest")


func test_each_rung_plays_the_monsters_own_cue() -> void:
	var spr := _sprite()
	var scene := _scene_with(_foe("Goblin"), spr)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))["sfx"]
	for n in [2, 3, 4]:
		var played: String = scene._play_enemy_advance_cue(n)
		assert_eq(played, "enemy_advance_%d" % n, "×%d plays its own rung of the monster ladder" % n)
		assert_true(manifest.has(played), "and that cue is authored (%s)" % played)
	assert_eq(scene._play_enemy_advance_cue(6), "enemy_advance_4", "a longer queue tops out at the last rung")


func test_the_execution_flourish_is_a_monsters_not_a_pcs() -> void:
	var spr := _sprite()
	var foe := _foe("Goblin")
	var scene := _scene_with(foe, spr)
	var pc := _foe("Fighter")
	pc.job = {"id": "fighter"}
	scene.party_members.assign([pc] as Array[Combatant])
	scene._spawn_advance_flourish(pc, spr, 3, false)
	assert_eq(scene._last_advance_cue, "advance_flourish_3", "CONTROL: a PC's Advance plays the party cue")
	scene._spawn_advance_flourish(foe, spr, 3, false)
	assert_eq(scene._last_advance_cue, "enemy_advance_3", "a monster's Advance plays the monster ladder, not the PC's cue")


func test_a_monster_defer_braces() -> void:
	var spr := _sprite()
	var foe := _foe("Goblin")
	var scene := _scene_with(foe, spr)
	var before: int = scene.find_children("EnemyBrace", "Line2D", false, false).size()
	scene._on_action_executing(foe, {"type": "defer", "combatant": foe})
	assert_eq(before, 0, "CONTROL: no brace before")
	assert_eq(scene.find_children("EnemyBrace", "Line2D", false, false).size(), 1, "a monster's Defer shows its brace")


func test_turbo_and_the_grind_console_keep_the_tell_but_not_the_ladder() -> void:
	var spr := _sprite()
	var foe := _foe("Goblin")
	var scene := _scene_with(foe, spr)
	BattleManager.pending_actions = [_advance(foe, 4)]
	scene._on_selection_turn_ended(foe)
	assert_eq(scene._enemy_ladder_played, 3, "CONTROL: at normal speed a ×4 climbs three rungs")
	scene.turbo_mode = true
	scene._on_selection_turn_ended(foe)
	assert_eq(scene._enemy_ladder_played, 0, "at turbo the ladder is quiet, like a boss signature (autogrind 23371)")
	var t := spr.get_node_or_null(EnemyAdvanceTell.NODE_NAME) as EnemyAdvanceTell
	assert_true(t != null and t.is_showing(), "but the tell still shows: it is state, so it reads at any speed")
