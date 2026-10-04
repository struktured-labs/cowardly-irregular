extends SceneTree

## Visual proof for the battle VFX pass (struktured 2026-10-03: "bahamut summon was not nearly
## wild enough... same with bard's status effects, speculators abilities... couldnt tell that u
## summoned another summoner... we need VISUALS").
##
##   XDG_DATA_HOME=$PWD/tmp/shot_xdg xvfb-run -a godot --audio-driver Dummy --rendering-driver opengl3 \
##     --resolution 2560x1440 -s tools/vfx_wild_shots.gd
##
## Drives BattleManager._execute_ability directly against a live BattleScene -- this bypasses the
## turn queue (no UI input), but it is the SAME function and the SAME action_executing signal
## _on_action_executing routes off of, so the captured frames are the real spectacle, not a mock.

const ShotGuard = preload("res://tools/shot_guard.gd")
const OUT := "res://tmp/vfx_shots"

var _scene: Node = null
var _enemies: Array = []
var _fail: int = 0


func _init() -> void:
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute(OUT)
	var gs = root.get_node_or_null("GameState")
	if gs and "debug_log_enabled" in gs:
		gs.debug_log_enabled = false
	var hints = load("res://src/ui/TutorialHints.gd")
	var hint_ids: Array = hints.HINTS.keys() if hints and ("HINTS" in hints) else []
	for id in hint_ids:
		gs.game_constants["tutorial_" + str(id)] = true

	var summoner := _make("Sage", "summoner", 10)
	var bard := _make("Lyra", "bard", 10)
	var speculator := _make("Val", "speculator", 10)
	var party: Array[Combatant] = [summoner, bard, speculator]

	_scene = (load("res://src/battle/BattleScene.tscn") as PackedScene).instantiate()
	_scene.set_party(party)
	_scene.forced_enemies = ["slime", "goblin"]
	root.add_child(_scene)
	await process_frame
	await process_frame
	await process_frame

	_enemies = _scene.test_enemies.duplicate()
	for e in _enemies:
		e.max_hp = 999999
		e.current_hp = 999999

	## 1x "spotlight" speed -- the gate (_full_render_active) requires Engine.time_scale <= 0.55.
	Engine.time_scale = 0.25

	## Autobattle for the whole party keeps the command menu / tutorial hint from popping over
	## every shot. full_render_on_autobattle defaults TRUE (BattleJuice.flags), so the spectacle
	## still plays -- this only suppresses UI that has nothing to do with the VFX under test.
	var auto_sys = root.get_node("AutobattleSystem")
	for pc in party:
		auto_sys.set_autobattle_enabled(pc.combatant_name.to_lower().replace(" ", "_"), true)

	await _shoot_bahamut(summoner)
	await _shoot_recursive_summon(summoner)
	await _shoot_bard_status(bard, "lullaby")
	await _shoot_bard_status(bard, "discord")
	await _shoot_speculator(speculator, "circuit_breaker", "win")
	await _shoot_speculator(speculator, "leverage_position", "loss")

	print("[VFX SHOTS] done, fail=%d" % _fail)
	quit(1 if _fail > 0 else 0)


func _make(name_str: String, job_id: String, lvl: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name_str, "max_hp": 99999, "max_mp": 9999,
		"attack": 80, "defense": 80, "magic": 300, "speed": 40})
	c.job_level = lvl
	root.add_child(c)
	root.get_node("JobSystem").assign_job(c, job_id)
	c.current_ap = 4
	return c


func _settle() -> void:
	await process_frame
	await process_frame


func _snap(tag: String) -> void:
	## The command menu for whichever ally's turn it is next keeps popping during these staged
	## casts -- it is unrelated UI, not part of the VFX under test, so hide it for a clean shot.
	if "active_win98_menu" in _scene and _scene.active_win98_menu and is_instance_valid(_scene.active_win98_menu):
		_scene.active_win98_menu.visible = false
	await _settle()
	var img: Image = root.get_texture().get_image()
	if not ShotGuard.save_or_refuse(img, "%s/%s.png" % [OUT, tag]):
		_fail += 1
	else:
		print("[VFX SHOTS] wrote %s" % tag)


func _hold(seconds: float) -> void:
	var t: SceneTreeTimer = create_timer(seconds / Engine.time_scale)
	await t.timeout


## Samples real wall-clock frames at fixed REAL-time steps across the spectacle's whole arc
## instead of guessing beat durations -- timing drifts with menu-recovery frame cost, so a burst
## is the only way to reliably catch the beast/portal/reel mid-flight.
func _burst(prefix: String, step_real_seconds: float, count: int) -> void:
	for i in range(count):
		await _snap("%s_%02d" % [prefix, i])
		var t: SceneTreeTimer = create_timer(step_real_seconds)
		await t.timeout


func _shoot_bahamut(summoner: Combatant) -> void:
	var BM = root.get_node("BattleManager")
	summoner.current_mp = summoner.max_mp
	BM._execute_ability(summoner, "summon_bahamut", [_enemies[0]])
	await _burst("bahamut", 0.3, 10)


func _shoot_recursive_summon(summoner: Combatant) -> void:
	var BM = root.get_node("BattleManager")
	## First cast builds the first stack with no on-screen caption requirement; the second cast
	## is the one that must show the caption with depth >= 2 ("SUMMON x3"). MP is topped up
	## between casts -- unrelated to the VFX under test, a pre-existing MP-cost interaction with
	## this harness's stacked passives otherwise starves the second cast.
	summoner.current_mp = summoner.max_mp
	BM._execute_ability(summoner, "recursive_summon", [summoner])
	await _hold(1.0)
	summoner.current_mp = summoner.max_mp
	BM._execute_ability(summoner, "recursive_summon", [summoner])
	await _burst("recursive_summon", 0.2, 10)


func _shoot_bard_status(bard: Combatant, ability_id: String) -> void:
	var BM = root.get_node("BattleManager")
	bard.current_mp = bard.max_mp
	var targets: Array = [_enemies[0]] if ability_id == "lullaby" else _enemies.duplicate()
	BM._execute_ability(bard, ability_id, targets)
	await _burst("bard_%s" % ability_id, 0.15, 8)


func _shoot_speculator(speculator: Combatant, ability_id: String, label: String) -> void:
	var BM = root.get_node("BattleManager")
	speculator.current_mp = speculator.max_mp
	speculator.current_hp = speculator.max_hp
	var targets: Array = [speculator] if ability_id in ["leverage_position", "forecast", "circuit_breaker"] else [_enemies[0]]
	BM._execute_ability(speculator, ability_id, targets)
	await _burst("speculator_%s" % label, 0.2, 10)
