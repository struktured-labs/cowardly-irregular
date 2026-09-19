extends SceneTree
## Store shot: the full-render lightning storm (BattleScene._full_render_storm) — sky drops,
## 2-5 fat forked bolts fall staggered, each with a screen flash and a ground burst.
##
## ⚠️ THIS IS NOT THE AMBIENT WEATHER STORM. `battle_storm.png` in the .225 set showed ambient
## weather, whose tint is alpha 0.2 and whose bolt is deliberately "one thin dim bolt, no trauma
## or punch_zoom" (BattleScene.gd:1889) — which is why that shot read as nothing but a
## `~ STORM ~` text tag over a bright sky, and why re-shooting it at .239 would reproduce the
## same weak image. The tint is still 0.2 at .239. The thing that actually changed is the
## ABILITY storm, and that is what this captures.
##
## A REAL CAST, not a synthesised effect: this queues thundaga through
## BattleScene._execute_ability -> BattleManager.player_use_ability, the same path a player's
## menu selection takes, and lets the execution phase render it. Calling _full_render_storm
## directly would photograph a VFX the player might never be able to produce — the same reason
## the elite shot picks a world rather than rewriting which species lives there.
##
## Captures a BURST and keeps every frame. The bolts fall STAGGERED over a short window, so a
## single timed grab is a coin flip. Deliberately no "pick the brightest frame" heuristic: a
## threshold on pixels is an instrument with a free parameter in every pixel, and three of those
## were caught measuring the wrong thing across the fleet this morning. Frames are numbered; a
## human picks.
##
##   XDG_DATA_HOME=$PWD/tmp/shot_xdg xvfb-run -a godot --rendering-driver opengl3 \
##       --audio-driver Dummy -s tools/store_shot_storm.gd
##
## Sandboxed XDG is mandatory — user:// is one directory shared by every cowir-* checkout.

const ABILITY := "thundaga"     ## Fulmen Maximum, mp 32 — top tier buys the most bolts and widest cores
const FRAMES := 60
const FRAME_GAP := 0.06


func _init() -> void:
	await process_frame
	await process_frame
	_suppress_furniture()
	DirAccess.make_dir_recursive_absolute("res://tmp/marketing/storm")

	var gl_res := load("res://src/GameLoop.tscn")
	if gl_res == null:
		_die("GameLoop.tscn did not load")
		return
	var gl: Node = gl_res.instantiate()
	root.add_child(gl)
	for i in range(4):
		await process_frame

	var gs = root.get_node_or_null("GameState")
	if gs and "debug_all_pcs_unlocked" in gs:
		gs.debug_all_pcs_unlocked = false

	if not gl.has_method("_close_title_screen") or not gl.has_method("_create_party") \
			or not gl.has_method("_start_battle_async"):
		_die("GameLoop's battle API moved")
		return
	gl._close_title_screen()
	await process_frame
	await process_frame
	gl._create_party()
	await gl._start_battle_async(["goblin"], true)
	await create_timer(2.0).timeout

	var bs: Node = gl.get_node_or_null("BattleScene")
	if bs == null:
		for c in gl.get_children():
			if str(c.name).begins_with("BattleScene"):
				bs = c
				break
	if bs == null:
		_die("BattleScene not found under GameLoop — its name or parenting moved")
		return
	if not bs.has_method("_execute_ability"):
		_die("BattleScene._execute_ability absent — the cast entry point moved")
		return

	var bm = root.get_node_or_null("BattleManager")
	if bm == null or not ("enemy_party" in bm):
		_die("BattleManager.enemy_party unreadable — cannot target the cast")
		return
	var foes: Array = bm.enemy_party
	if foes.is_empty():
		_die("enemy_party is EMPTY — nothing to cast at, and an empty target list would render nothing while exiting 0")
		return

	# MP: thundaga costs 32. Top every caster up rather than guessing which one acts — a refused
	# cast for want of MP looks exactly like a cast that rendered nothing.
	var topped := 0
	if "party" in gl:
		for m in gl.party:
			if m and is_instance_valid(m) and "current_mp" in m:
				m.current_mp = 999
				topped += 1
	print("[SHOT] topped MP on %d party member(s); casting %s at %s" % [topped, ABILITY, str(foes[0].name if "name" in foes[0] else "?")])

	# WAIT FOR THE MAGE TO BE THE ACTIVE SELECTOR. player_use_ability casts as
	# BattleManager.current_combatant, NOT as whoever you pass — the first attempt queued
	# thundaga while the Fighter was selecting and the battle log said so out loud:
	# "Fighter can't use Fulmen Maximum right now." A refused cast renders nothing while the
	# script still exits 0, so the wait is bounded and its failure is loud.
	var caster = null
	var waited := 0.0
	while waited < 25.0:
		var cc = bm.current_combatant
		if cc != null and is_instance_valid(cc):
			var who := str(cc.name if "name" in cc else "")
			var job := str(cc.job_name if "job_name" in cc else (cc.job if "job" in cc else ""))
			if who.to_lower().find("mage") >= 0 or job.to_lower().find("mage") >= 0:
				caster = cc
				break
		await create_timer(0.25).timeout
		waited += 0.25
	if caster == null:
		_die("the Mage never became the active selector within 25s — cannot queue %s as anyone else (player_use_ability casts as current_combatant)" % ABILITY)
		return
	print("[SHOT] Mage is selecting after %.1fs — queueing %s" % [waited, ABILITY])
	bs._execute_ability(ABILITY, foes[0], false)

	# Burst. Every frame is kept and numbered; no frame is selected by the script.
	for i in range(FRAMES):
		await create_timer(FRAME_GAP).timeout
		var img := root.get_texture().get_image()
		var p := "res://tmp/marketing/storm/storm_%02d.png" % i
		img.save_png(p)
		var fa := FileAccess.open(p, FileAccess.READ)
		var sz := fa.get_length() if fa else 0
		if fa:
			fa.close()
		print("[SHOT] storm_%02d %7d B" % [i, sz])
	print("[SHOT] burst complete: %d frames in res://tmp/marketing/storm/" % FRAMES)
	quit(0)


func _die(msg: String) -> void:
	print("[SHOT] FAIL: %s" % msg)
	quit(1)


func _suppress_furniture() -> void:
	var gs = root.get_node_or_null("GameState")
	if gs == null:
		push_error("[SHOT] GameState absent — suppression cannot be applied")
		return
	# In-memory only; this flag also gates the only in-game escape past a broken world transition.
	if "debug_log_enabled" in gs:
		gs.debug_log_enabled = false
	var dbg = root.get_node_or_null("DebugLogOverlay")
	if dbg and dbg.has_method("set_enabled"):
		dbg.set_enabled(false)
	var hints_script = load("res://src/ui/TutorialHints.gd")
	if hints_script == null or not ("HINTS" in hints_script):
		push_error("[SHOT] TutorialHints.HINTS unreadable")
		return
	var ids: Array = hints_script.HINTS.keys()
	if ids.is_empty():
		push_error("[SHOT] TutorialHints.HINTS is EMPTY — suppression is vacuous")
		return
	if "game_constants" in gs:
		for id in ids:
			gs.game_constants["tutorial_" + str(id)] = true
	print("[SHOT] suppressed: debug overlay + %d tutorial hints" % ids.size())
