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

## Strongest first: the storm scales with the tier, so the top tier buys the most bolts and widest
## cores. Only a tier this Mage can REALLY cast is used (JobSystem.can_use_ability): at .555 the
## starting Mage was refused Fulmen Maximum, and teaching it to her would be a state hack in the
## frame, like the old MP 999.
const ABILITY_TIERS: Array[String] = ["thundaga", "thundara", "thunder"]  ## Fulmen Maximum, Maius, Fulmen
const RING_BEFORE := 10   ## a few frames of context only: nothing visual happens before the hit
## The trigger is the HP state change, and the full-render cinematic plays AFTER it: measured at .555,
## the dim and the first bolt arrive ~40 frames past the hit and are still striking at +76. The old
## 80-frame window cut the storm off mid-strike. 160 covers it (~2.7s at time_scale 0.5).
const RING_AFTER := 160


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

	# UNLOCKED, so each member follows the autobattle flag set below. A spotlight-locked PC is
	# AI-driven whatever its flag says (BattleManager's turn gate), so with this false the Mage
	# auto-cast Ignis in round 1 and killed the goblin before thundaga could be queued (.555).
	var gs = root.get_node_or_null("GameState")
	if gs and "debug_all_pcs_unlocked" in gs:
		gs.debug_all_pcs_unlocked = true

	if not gl.has_method("_close_title_screen") or not gl.has_method("_create_party") \
			or not gl.has_method("_start_battle_async"):
		_die("GameLoop's battle API moved")
		return
	gl._close_title_screen()
	await process_frame
	await process_frame
	gl._create_party()
	# Everyone but the Mage fights on autobattle, so the turn order reaches the Mage with no human.
	# The Fighter's default is MANUAL: once is_mage stopped matching him, his selection waited for
	# input forever and the Mage wait below timed out at 25s. The substring bug had hidden this by
	# spending his turn on a refused thundaga. Keys are combatant_name lowercased, as BattleScene reads them.
	var abs_pre = root.get_node_or_null("AutobattleSystem")
	if abs_pre and abs_pre.has_method("set_autobattle_enabled") and "party" in gl:
		for m in gl.party:
			if m and is_instance_valid(m) and "combatant_name" in m:
				abs_pre.set_autobattle_enabled(m.combatant_name.to_lower().replace(" ", "_"), not is_mage(m))
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
	# cast for want of MP looks exactly like a cast that rendered nothing. To max_mp, NOT 999:
	# the party panel is in the frame, and 999 rendered as "MP: 999/34" on the shipped store shot.
	var topped := 0
	if "party" in gl:
		for m in gl.party:
			if m and is_instance_valid(m) and "current_mp" in m and "max_mp" in m:
				m.current_mp = m.max_mp
				topped += 1
	print("[SHOT] topped MP on %d party member(s); target %s" % [topped, str(foes[0].name if "name" in foes[0] else "?")])

	# ⛔ THE CINEMATIC REQUIRES A MANUAL TURN. `_full_render_active` (BattleScene) returns
	# false when the caster's autobattle is on, when turbo/console mode is set, or when
	# Engine.time_scale > 0.55 — and "storm" is dispatched at exactly ONE site, inside
	# _full_render_release_visual, reachable only through that gate. My rig enables
	# autobattle so the fight plays itself, which silently took the ordinary
	# EffectSystem.LIGHTNING path: the cast landed, damage applied, the enemy died, and the
	# cinematic never ran. Four capture configurations found nothing because there was
	# nothing to find (diagnosed by cowir-main, 2026-09-09).
	#
	# The Bard's `chord` captured cleanly on this same rig at .239 from that same switch —
	# the only difference was that its turn happened to be manual. That control is why this
	# is a gate condition rather than "the effect is too fast".
	var abs_sys = root.get_node_or_null("AutobattleSystem")
	if abs_sys and abs_sys.has_method("set_autobattle_enabled"):
		abs_sys.set_autobattle_enabled("mage", false)
		print("[SHOT] autobattle DISABLED for mage — the storm only renders on a manual turn")
	else:
		print("[SHOT] ⚠ AutobattleSystem.set_autobattle_enabled absent — the cinematic gate cannot be opened, expect no storm")
	Engine.time_scale = 0.5   # must stay <= 0.55 or the gate closes again

	# WAIT FOR THE MAGE TO BE THE ACTIVE SELECTOR. player_use_ability casts as
	# BattleManager.current_combatant, NOT as whoever you pass — the first attempt queued
	# thundaga while the Fighter was selecting and the battle log said so out loud:
	# "Fighter can't use Fulmen Maximum right now." A refused cast renders nothing while the
	# script still exits 0, so the wait is bounded and its failure is loud.
	var caster = null
	var waited := 0.0
	while waited < 25.0:
		var cc = bm.current_combatant
		if is_mage(cc):
			caster = cc
			break
		await create_timer(0.25).timeout
		waited += 0.25
	if caster == null:
		_die("the Mage never became the active selector within 25s — cannot queue the cast as anyone else (player_use_ability casts as current_combatant)")
		return
	# The target must still be alive, or the hit trigger below fires on frame 1 against a corpse:
	# at .555 round 1 killed the goblin first and the burst read "KILLING BLOW (hp 0 -> 0)".
	if not ("current_hp" in foes[0]) or int(foes[0].current_hp) <= 0:
		_die("the goblin was already dead when the Mage came up — an earlier turn killed it, so there is no strike to photograph")
		return
	var js = root.get_node_or_null("JobSystem")
	var ability := ""
	for id in ABILITY_TIERS:
		if js and js.can_use_ability(caster, id):
			ability = id
			break
	if ability == "":
		_die("the Mage can cast none of %s — no lightning storm to photograph" % str(ABILITY_TIERS))
		return
	print("[SHOT] Mage is selecting after %.1fs — queueing %s (strongest tier she can cast)" % [waited, ability])
	bs._execute_ability(ability, foes[0], false)

	# ── RING BUFFER, TRIGGERED ON THE HIT ────────────────────────────────────
	# Two earlier attempts failed for the same reason and it was NOT the window length:
	# save_png() of a 1280x720 frame costs far more than the frame gap I was asking for, so
	# a "0.05s" burst really sampled every ~0.15s and the bolt — a tween of roughly a fifth
	# of a second — fell between samples. Widening the window from 3.6s to 7.5s found the
	# cast (frame 36) and still missed the bolt, which is what proved the rate was the
	# problem rather than the timing.
	#
	# So: no encoding inside the loop. Frames are held as Images in a ring and written after,
	# which decouples capture rate from encode cost entirely.
	#
	# The trigger is the ENEMY'S HP DROPPING — an event in the game's own state, not a clock
	# and not a pixel threshold. A ring means the frames BEFORE the hit are kept too, which
	# is where the bolt actually is: the strike lands, then damage applies.
	var foe = foes[0]
	if not ("current_hp" in foe):
		_die("enemy has no current_hp — cannot trigger on the hit")
		return
	var hp_before: int = int(foe.current_hp)
	var ring: Array = []
	var post: Array = []
	var fired := false
	var waited_frames := 0

	while waited_frames < 4000:                      # time_scale 0.5 halves game time per frame
		await process_frame
		waited_frames += 1
		var img := root.get_texture().get_image()
		if not fired:
			ring.append(img)
			if ring.size() > RING_BEFORE:
				ring.pop_front()
			# TRIGGER ON DEATH, NOT ON THE FIRST HIT. The first run fired at hp 736 -> 567,
			# a 169-damage chip from an earlier attacker in the turn order, and photographed
			# somebody else's swing. The Mage acts LAST and hits for ~1878, so the killing
			# blow IS the lightning cast. Death is an exact state change — no damage
			# threshold, which would be a free parameter picked to match one observed run.
			if is_instance_valid(foe) and int(foe.current_hp) <= 0:
				fired = true
				print("[SHOT] KILLING BLOW at frame %d (hp %d -> %d) — keeping %d before, %d after"
					% [waited_frames, hp_before, int(foe.current_hp), ring.size(), RING_AFTER])
		else:
			post.append(img)
			if post.size() >= RING_AFTER:
				break

	if not fired:
		_die("the enemy never took damage within %d frames — the cast did not land, so there is no strike to photograph" % waited_frames)
		return

	var all: Array = ring + post
	print("[SHOT] writing %d frames (%d pre-hit, %d post-hit)" % [all.size(), ring.size(), post.size()])
	for i in range(all.size()):
		var im: Image = all[i]
		var path := "res://tmp/marketing/storm/storm_%03d.png" % i
		im.save_png(path)
	print("[SHOT] burst complete: %d frames in res://tmp/marketing/storm/ (hit at index %d)" % [all.size(), ring.size() - 1])
	quit(0)


## True only for a combatant whose job id IS "mage". The old test searched str(cc.job) for the
## substring "mage", and the Fighter's job Dictionary contains "damage": the wait ended at 0.0s on
## the Fighter, who refused thundaga ("Fighter cannot use Fulmen Maximum"), and the store frame
## caught the Mage's own tier-1 Fulmen instead. Measured at v3.33.549 and v3.33.555.
static func is_mage(cc) -> bool:
	if cc == null or not is_instance_valid(cc) or not ("job" in cc):
		return false
	var j = cc.job
	if j is Dictionary:
		return str(j.get("id", "")) == "mage"
	return false


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
