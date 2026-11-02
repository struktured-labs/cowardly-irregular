extends SceneTree

const ShotGuard = preload("res://tools/shot_guard.gd")

## Visual proof that every status reads ON the battler (struktured 2026-11-01: "the sleep indicator could be animated,
## the poison, all stats"). A real battle through GameLoop, each party member and enemy given a different status set,
## then one full frame plus a short frame sequence for a clip. Run through tools/status_aura_shots.sh (sandboxed).
## Writes tmp/status_aura/frame.png and tmp/status_aura/seq_NN.png.

const OUT := "res://tmp/status_aura"
const PARTY_SETS := [["sleep"], ["poison", "attack_up"], ["stun", "defense_down", "speed_up"], ["confuse", "magic_up", "magic_down"], ["burning", "regen", "silence"]]
const ENEMY_SETS := [["blind", "attack_down"], ["charm", "barrier"], ["fear", "slow", "curse"]]


func _init() -> void:
	await process_frame
	await process_frame
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		print("[SHOT] FAIL: no GameState")
		quit(1)
		return
	gs.current_world = 1
	var hints = load("res://src/ui/TutorialHints.gd")
	for id in (hints.HINTS.keys() if hints and ("HINTS" in hints) else []):
		gs.game_constants["tutorial_" + str(id)] = true
	DirAccess.make_dir_recursive_absolute(OUT)
	var gl: Node = (load("res://src/GameLoop.tscn") as PackedScene).instantiate()
	root.add_child(gl)
	for i in 4:
		await process_frame
	if gl.has_method("_close_title_screen"):
		gl._close_title_screen()
	await process_frame
	gl._create_party()
	await gl._start_battle_async(["goblin", "goblin", "goblin"], true)
	var scene: Node = _find(root)
	if scene == null:
		print("[SHOT] FAIL: no BattleScene")
		quit(1)
		return
	await create_timer(1.0, true, false, true).timeout
	var applied := 0
	for i in scene.party_members.size():
		for s in PARTY_SETS[i % PARTY_SETS.size()]:
			scene.party_members[i].add_status(s, 3)
			applied += 1
	var enemies: Array = root.get_node("BattleManager").enemy_party
	for i in enemies.size():
		for s in ENEMY_SETS[i % ENEMY_SETS.size()]:
			enemies[i].add_status(s, 3)
			applied += 1
	_hide_menus(root)
	await create_timer(1.2, true, false, true).timeout
	var auras := 0
	for c in scene._status_auras.keys():
		if is_instance_valid(scene._status_auras[c]) and scene._status_auras[c].visible:
			auras += 1
	print("[SHOT] statuses applied %d · auras showing %d" % [applied, auras])
	var ok := ShotGuard.save_or_refuse(root.get_viewport().get_texture().get_image(), ProjectSettings.globalize_path(OUT + "/frame.png"))
	for f in 12:
		await create_timer(0.1, true, false, true).timeout
		ok = ShotGuard.save_or_refuse(root.get_viewport().get_texture().get_image(), ProjectSettings.globalize_path(OUT + "/seq_%02d.png" % f)) and ok
	quit(0 if ok and auras >= 5 else 1)


func _find(n: Node) -> Node:
	if n.get_script() and str(n.get_script().resource_path).ends_with("BattleScene.gd"):
		return n
	for c in n.get_children():
		var r := _find(c)
		if r:
			return r
	return null


func _hide_menus(n: Node) -> void:
	for c in n.get_children():
		if c is Control and (c.name.contains("Menu") or c.name.contains("Command")):
			c.visible = false
		_hide_menus(c)
