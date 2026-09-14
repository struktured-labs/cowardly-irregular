extends GutTest

## struktured 2026-09-14: "I didn't see animated flourishes as u hit advance more — or animated
## auras, etc." The resolution flourish fires once, when the queue is SPENT. Nothing escalated while
## the player was building it — which is the part they do by hand.
##
## And the flourish that did exist was masked: BattleManager._execute_advance emitted the advance
## beat and then ran the first sub-action SYNCHRONOUSLY, so its lunge started the same frame. A
## presentation_hold set by the scene could not help, because nothing awaited it until AFTER that
## first sub-action. Both halves are pinned here.

const AuraScript = preload("res://src/battle/AdvanceAura.gd")
const SceneScript = preload("res://src/battle/BattleScene.gd")
const CommandMenuScript = preload("res://src/battle/BattleCommandMenu.gd")
const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const SettingsScript = preload("res://src/ui/SettingsMenu.gd")
const GdSource = preload("res://test/unit/helpers/gd_source.gd")

var _saved_time_scale: float
var _saved_party: Array
var _saved_current
var _saved_flags: Dictionary
var _saved_persist: bool


func before_each() -> void:
	_saved_time_scale = Engine.time_scale
	_saved_party = BattleManager.player_party.duplicate()
	_saved_current = BattleManager.current_combatant
	_saved_flags = GameState.battle_fx_flags.duplicate()
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	GameState.battle_fx_flags.erase("advance_aura")


func after_each() -> void:
	Engine.time_scale = _saved_time_scale
	BattleManager.player_party.clear()
	for c in _saved_party:
		BattleManager.player_party.append(c)
	BattleManager.current_combatant = _saved_current
	GameState.battle_fx_flags = _saved_flags
	AutobattleSystem._test_disable_persistence = _saved_persist


# ─── the aura's own contract ───

func test_every_channel_rises_with_the_count() -> void:
	## Many channels at once is what "grows" means. One flat channel and 4 reads the same as 3.
	var flat: Array = []
	for key in ["radius", "fill_alpha", "rim_width", "pulse_hz", "glyphs", "spin", "outline_grow", "outline_alpha"]:
		for n in range(2, 6):
			var lo = AuraScript.params_for(n - 1, false)[key]
			var hi = AuraScript.params_for(n, false)[key]
			if not (float(hi) > float(lo)):
				flat.append("%s %d->%d (%s -> %s)" % [key, n - 1, n, str(lo), str(hi)])
	assert_eq(flat.size(), 0, "a channel failed to rise with the queue: " + str(flat))


## ⛔ THE BAR THE FIRST PASS MISSED. Every channel rose, and cowir-main still could not see counts
## 1-4 in the folded frames — a ring stepping a few px per press is monotone and invisible. So the
## thresholds live HERE, not beside the table: a floor declared next to what it bounds can be lowered
## in the same edit that flattens the table, and stay green.
const VISIBLE_STEP := {"radius": 6.0, "fill_alpha": 0.06, "rim_width": 1.0}
const VISIBLE_FIRST_FILL: float = 0.15

func test_every_press_is_a_visible_step_not_just_a_bigger_number() -> void:
	var faint: Array = []
	for key in VISIBLE_STEP.keys():
		for n in range(1, 6):
			var step: float = float(AuraScript.params_for(n, false)[key]) - float(AuraScript.params_for(n - 1, false)[key])
			if step < float(VISIBLE_STEP[key]):
				faint.append("%s %d->%d steps %.3f, needs %.3f" % [key, n - 1, n, step, float(VISIBLE_STEP[key])])
	assert_eq(faint.size(), 0, "a press changes the aura by less than reads at couch distance: " + str(faint))
	assert_gte(float(AuraScript.params_for(1, false)["fill_alpha"]), VISIBLE_FIRST_FILL,
		"press 1 must read on its own — a filled disc from the first action, not only relative to the second")


## ⛔ THE SECOND BAR THE STEP ARM MISSED. Comparing the tables at rest said every press was a visible
## step. But three channels PULSE, and the outline pulsed ±4% in scale against a +2% step — so at the
## wrong phase count 2 drew SMALLER than count 1 (cowir-adhoc caught it in clear_1 vs clear_2, the exact
## step struktured said he couldn't see). One steady frame per count samples one arbitrary phase, so the
## proof couldn't show it either. This samples every phase of every count, on a live aura with a body
## bound, reading what is drawn this frame — not the tables.
const PHASE_SAMPLES := 400

func _drawn_ranges(n: int, body: AnimatedSprite2D) -> Dictionary:
	var aura = AuraScript.new()
	body.add_child(aura)
	aura.bind_body(body)
	aura.set_state(n, n >= 5, Color.RED, "runes")
	var hz: float = float(AuraScript.params_for(n, n >= 5)["pulse_hz"])
	var out := {"radius": [INF, -INF], "outline_alpha": [INF, -INF], "outline_scale": [INF, -INF]}
	for i in PHASE_SAMPLES:
		aura._t = (float(i) / float(PHASE_SAMPLES)) / hz
		aura._kick = 0.0
		aura._sync_outline()
		var v := {"radius": aura.current_radius(), "outline_alpha": aura.current_outline_alpha(),
			"outline_scale": aura.outline().scale.x / body.scale.x}
		for k in v.keys():
			out[k] = [minf(out[k][0], v[k]), maxf(out[k][1], v[k])]
	aura.free()
	return out

func test_no_pulse_phase_makes_a_higher_count_look_smaller() -> void:
	var body := AnimatedSprite2D.new()
	body.sprite_frames = _frames()
	body.scale = Vector2(0.8, 0.8)
	add_child_autofree(body)
	var ranges: Array = [{}]
	for n in range(1, 6):
		ranges.append(_drawn_ranges(n, body))
	assert_gt(float(ranges[3]["radius"][1]), float(ranges[3]["radius"][0]),
		"CONTROL: the disc really breathes, so this is sampling a range and not a constant")
	var overlaps: Array = []
	for n in range(1, 5):
		for key in ["radius", "outline_alpha", "outline_scale"]:
			var hi_n: float = float(ranges[n][key][1])
			var lo_up: float = float(ranges[n + 1][key][0])
			if not (lo_up > hi_n):
				overlaps.append("%s: count %d at its lowest (%.3f) is not above count %d at its highest (%.3f)" % [key, n + 1, lo_up, n, hi_n])
	assert_eq(overlaps.size(), 0, "a pulse phase draws a higher count smaller than a lower one: " + str(overlaps))


func test_a_full_bank_is_its_own_state_not_a_louder_fourth() -> void:
	var five := AuraScript.params_for(5, false)
	var bank := AuraScript.params_for(5, true)
	assert_true(bool(bank["gold_rim"]), "5/5 at a full bank carries the gold rim")
	assert_false(bool(five["gold_rim"]), "CONTROL: the rim is the full-bank state, not the count")
	assert_gt(float(bank["pulse_hz"]), float(five["pulse_hz"]), "and it pulses faster than a plain 5")
	assert_false(bool(AuraScript.params_for(0, true)["gold_rim"]), "an empty queue has no rim at all")


func test_it_is_off_at_minimal_and_at_the_turbo_console_tier() -> void:
	## OFF already covers turbo, the grind console and 4x, so the three exclusions reduce to this.
	assert_true(AuraScript.should_show(BattleJuice.Tier.FULL, true), "on at full render")
	assert_true(AuraScript.should_show(BattleJuice.Tier.REDUCED, true), "on at 1x")
	assert_false(AuraScript.should_show(BattleJuice.Tier.MINIMAL, true), "off at 2x+")
	assert_false(AuraScript.should_show(BattleJuice.Tier.OFF, true), "off in turbo, the console and 4x")
	assert_false(AuraScript.should_show(BattleJuice.Tier.FULL, false), "and off when the player turns it off")


func test_the_disc_stays_within_its_actors_figure() -> void:
	## ⛔ This was "stays under the battle-start quip" against a 105 px anchor, and cowir-cutscenes
	## measured that for the lead PC the bubble is clamped DOWN onto the body — the arm passed while
	## the overlap existed. Bubble placement is BattleSpeechBubble's to guarantee; this only keeps the
	## disc, at its most extreme moment (full bank, pulse peak, mid-kick), inside its own actor's figure.
	var half: float = SceneScript.PARTY_SPRITE_HEIGHT / 2.0
	assert_gt(half, 50.0, "CONTROL: the party figure height reads as real (%.1f)" % half)
	assert_lt(AuraScript.max_reach(), half,
		"the disc reaches %.1f px, past its own %.1f px figure" % [AuraScript.max_reach(), half])


func test_a_press_that_raises_the_count_pops_and_an_undo_does_not() -> void:
	var aura = autofree(AuraScript.new())
	assert_true(aura.set_state(1, false, Color.RED, "runes"), "0 -> 1 rises")
	assert_eq(aura.kick_amount(), 1.0, "and a rising press kicks the ring")
	aura._process(AuraScript.KICK_DECAY_S)
	assert_eq(aura.kick_amount(), 0.0, "the kick settles within its decay")
	assert_true(aura.set_state(2, false, Color.RED, "runes"), "1 -> 2 rises")
	assert_false(aura.set_state(2, false, Color.RED, "runes"), "a repeat of the same count does not pop")
	var r_two: float = float(AuraScript.params_for(aura.count, false)["radius"])
	aura._process(AuraScript.KICK_DECAY_S)
	assert_false(aura.set_state(1, false, Color.RED, "runes"), "an undo does not pop")
	assert_eq(aura.kick_amount(), 0.0, "and does not kick")
	assert_lt(float(AuraScript.params_for(aura.count, false)["radius"]), r_two, "and the aura shrinks with it")
	aura.clear()
	assert_false(aura.is_active(), "clear leaves nothing on screen")


func _frames() -> SpriteFrames:
	var f := SpriteFrames.new()
	var img := Image.create(8, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	f.add_frame("default", ImageTexture.create_from_image(img))
	f.add_frame("default", ImageTexture.create_from_image(img))
	return f


func test_the_outline_mirrors_the_body_and_grows_with_the_count() -> void:
	## The half the bubble cannot cover: a silhouette of the body's own frame, so it reads beside a
	## turn_start bubble clamped onto the upper body — on any sheet, without knowing where the art sits.
	var body := AnimatedSprite2D.new()
	body.sprite_frames = _frames()
	body.scale = Vector2(0.8, 0.8)
	body.flip_h = true
	body.frame = 1
	add_child_autofree(body)
	var aura = AuraScript.new()
	body.add_child(aura)
	aura.bind_body(body)
	var line = aura.outline()
	assert_not_null(line, "binding a body creates the outline")
	assert_false(line.visible, "CONTROL: an empty queue shows no outline")
	aura.set_state(2, false, Color.RED, "runes")
	assert_true(line.visible, "a queued action shows it")
	assert_eq(line.sprite_frames, body.sprite_frames, "drawn from the body's own frames")
	assert_eq(line.frame, 1, "on the body's current frame")
	assert_true(line.flip_h, "facing the same way")
	var two: float = line.scale.x / body.scale.x
	aura.set_state(5, true, Color.RED, "runes")
	var five: float = line.scale.x / body.scale.x
	assert_gt(five, two, "the outline stands further out at 5 than at 2")
	assert_gt(two, 1.0, "and is always larger than the body, or it is hidden behind it")
	aura.clear()
	assert_false(line.visible, "clear hides it")


# ─── the scene drives it from the queue ───

func _scene_with_pc(job: String) -> Array:
	var scene = autofree(SceneScript.new())
	var pc := Combatant.new()
	autofree(pc)
	pc.combatant_name = "Mira"
	pc.job = {"id": job}
	var sprite := AnimatedSprite2D.new()
	sprite.scale = Vector2(0.8, 0.8)
	sprite.sprite_frames = _frames()
	add_child_autofree(sprite)
	scene.party_members.append(pc)
	scene.party_sprite_nodes.append(sprite)
	BattleManager.player_party.clear()
	BattleManager.player_party.append(pc)
	BattleManager.current_combatant = pc
	Engine.time_scale = 0.25
	return [scene, pc, sprite]


func _aura_on(sprite: Node) -> Node:
	for child in sprite.get_children():
		if child.get_script() == AuraScript:
			return child
	return null


func test_the_queue_count_drives_an_aura_on_the_acting_pc() -> void:
	var s := _scene_with_pc("mage")
	var scene = s[0]; var sprite: AnimatedSprite2D = s[2]
	scene._on_advance_queue_changed(3, 4)
	var aura = _aura_on(sprite)
	assert_not_null(aura, "a queue of 3 puts an aura on the acting PC's sprite")
	assert_eq(aura.count, 3, "carrying the count")
	assert_eq(aura.shape, "runes", "in the Mage's glyph, from ADVANCE_FLOURISH_SHAPES")
	assert_almost_eq(aura.scale.x, 1.25, 0.01, "counter-scaled against the sheet's 0.8x draw scale")
	assert_true(aura.outline() != null and aura.outline().visible, "and the scene bound the body outline to that sprite")
	scene._on_advance_queue_changed(4, 4)
	assert_eq(aura.count, 4, "it follows the next press")
	scene._on_advance_queue_changed(3, 4)
	assert_eq(aura.count, 3, "and shrinks on undo")
	scene._on_advance_queue_changed(0, 4)
	assert_false(aura.is_active(), "and is gone when the queue empties")


func test_five_of_five_enters_the_full_bank_state() -> void:
	var s := _scene_with_pc("cleric")
	var scene = s[0]; var sprite: AnimatedSprite2D = s[2]
	scene._on_advance_queue_changed(4, 5)
	assert_false(_aura_on(sprite).full_bank, "CONTROL: four of five is not the full bank")
	scene._on_advance_queue_changed(5, 5)
	assert_true(_aura_on(sprite).full_bank, "5/5 is")
	## The discriminator for deriving it from max_size: a full queue BELOW a full bank is not one.
	## `count >= max_size` alone passes both lines above and gets this one wrong.
	scene._on_advance_queue_changed(4, 4)
	assert_false(_aura_on(sprite).full_bank, "a full 4/4 queue below +4 AP is not the full bank")


func test_the_player_can_turn_it_off_and_fast_battles_never_see_it() -> void:
	var s := _scene_with_pc("rogue")
	var scene = s[0]; var sprite: AnimatedSprite2D = s[2]
	scene._on_advance_queue_changed(2, 4)
	assert_true(_aura_on(sprite).is_active(), "CONTROL: it shows at full render with the flag unset")
	GameState.battle_fx_flags["advance_aura"] = false
	scene._on_advance_queue_changed(3, 4)
	assert_false(_aura_on(sprite).is_active(), "the Advance Aura toggle turns it off")
	GameState.battle_fx_flags.erase("advance_aura")
	Engine.time_scale = 2.0
	scene._on_advance_queue_changed(3, 4)
	assert_false(_aura_on(sprite).is_active(), "and 2x (MINIMAL) never draws it")


func test_an_enemy_turn_never_gets_the_aura() -> void:
	var s := _scene_with_pc("fighter")
	var scene = s[0]; var sprite: AnimatedSprite2D = s[2]
	var monster := Combatant.new()
	autofree(monster)
	BattleManager.current_combatant = monster
	scene._on_advance_queue_changed(3, 4)
	assert_null(_aura_on(sprite), "a combatant outside the party gets no aura")


# ─── it clears on every way out of the menu ───

func _menu_for(scene) -> Object:
	var menu = CommandMenuScript.new(scene)
	return menu


func test_commit_defer_go_back_and_close_each_clear_it() -> void:
	## queue_changed(0) clears on submit and close, but defer and go-back are not queue mutations —
	## so each exit is driven on its own, starting from a live aura every time.
	assert_ne(BattleManager.current_state, BattleManager.BattleState.PLAYER_SELECTING,
		"CONTROL: the autoload is idle, so go-back returns without touching a real battle")
	var exits := {
		"commit": func(m): m._on_win98_actions_submitted([]),
		"defer": func(m): m._on_win98_defer_requested(),
		"go_back": func(m): m._on_win98_go_back_requested(),
		"close": func(m): m._on_win98_menu_closed(null),
	}
	var survived: Array = []
	for exit_name in exits.keys():
		var s := _scene_with_pc("bard")
		var scene = s[0]; var sprite: AnimatedSprite2D = s[2]
		scene._on_advance_queue_changed(3, 4)
		assert_true(_aura_on(sprite).is_active(), "CONTROL: live before %s" % exit_name)
		BattleManager.current_combatant = null
		(exits[exit_name] as Callable).call(_menu_for(scene))
		if _aura_on(sprite).is_active():
			survived.append(exit_name)
	assert_eq(survived.size(), 0, "the aura outlived a way out of the menu: " + str(survived))


func test_battle_end_clears_it() -> void:
	var s := _scene_with_pc("guardian")
	var scene = s[0]; var sprite: AnimatedSprite2D = s[2]
	scene._on_advance_queue_changed(2, 4)
	scene._clear_advance_aura()
	assert_false(_aura_on(sprite).is_active(), "the clear the battle-end handler calls leaves nothing")
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var at: int = src.find("func _on_battle_ended(")
	assert_gt(at, -1, "CONTROL: the battle-end handler exists")
	assert_true(src.substr(at, 200).contains("_clear_advance_aura()"),
		"and _on_battle_ended calls it first — a win mid-queue must not leave a glowing PC on the results screen")


func test_each_press_bursts_the_jobs_own_glyph_ring() -> void:
	## The first pass popped particles only, and cowir-main could not see a press in the frames. The pop
	## now bursts the job's glyph ring — the resolution flourish in miniature. It runs inside a live
	## scene, so this reads the stripped code of the pop itself.
	var code: String = GdSource.code_of("res://src/battle/BattleScene.gd")
	var at: int = code.find("func _spawn_advance_queue_pop(")
	assert_gt(at, -1, "CONTROL: the per-press pop survives stripping")
	var end: int = code.find("\nfunc ", at + 10)
	var body: String = code.substr(at, (end - at) if end > at else 2000)
	assert_true(body.contains("BattleJuice.spawn_burst("), "CONTROL: a known code line in the pop survives the strip")
	assert_true(body.contains("_spawn_advance_shape(shape"), "each rising press bursts the job's own glyph ring")


func test_the_full_bank_cue_is_written_where_the_audit_can_read_it() -> void:
	## full_bank_charged is manifest-guarded and fails SILENT. test_sfx_key_orphan_audit catches a typo
	## only when the key sits literally at a play_advance_state call — measured: a typo in that form reds
	## it, the identical typo through `SoundManager.call("play_advance_state", key)` stays green. And the
	## audit is one-directional (a key written in code must resolve; nothing requires a manifest key to
	## be consumed), so it cannot notice the call being re-wrapped. This arm is what notices.
	var code: String = GdSource.code_of("res://src/battle/BattleScene.gd")
	var at: int = code.find("func _on_advance_queue_changed(")
	assert_gt(at, -1, "CONTROL: the queue handler survives stripping")
	var end: int = code.find("\nfunc ", at + 10)
	var body: String = code.substr(at, (end - at) if end > at else 3000)
	assert_true(body.contains("_attach_advance_aura(sprite)"), "CONTROL: a known code line in the handler survives the strip")
	assert_true(body.contains('SoundManager.play_advance_state("full_bank_charged")'),
		"the full-bank cue must be a literal play_advance_state call, or a typo in its key plays silence unaudited")


func test_the_settings_menu_offers_the_toggle() -> void:
	var keys: Array = []
	for row in SettingsScript.BATTLE_FX_FLAGS:
		keys.append(str(row[0]))
	assert_gt(keys.size(), 10, "CONTROL: the battle FX table read non-empty (%d)" % keys.size())
	assert_true(keys.has("advance_aura"), "Settings lists an Advance Aura toggle")


# ─── the resolution flourish reads before the first lunge ───

## Two instruments failed here before this one, and both are worth keeping in view:
##   · wall clock — a 0.2s hold measured 91 ms on a correct tree; a headless loop does not pace
##     frames to real time.
##   · process frames — could not see the await's GATE: removing `presentation_hold > 0.0` made every
##     Advance await a zero-second timer, which resolved inside the same frame, and the arm stayed green.
## What separates all three states exactly is WHETHER THE FIRST SUB-ACTION RUNS BEFORE THE CALL YIELDS.
## Called without `await`, _execute_advance returns at its first await. No await before the loop, and
## the first sub-action has already fired by then; an await there, and it has not.
func _run_advance(hold_on_beat: float) -> Dictionary:
	var bm = add_child_autofree(BattleManagerScript.new())
	var pc := Combatant.new()
	autofree(pc)
	pc.combatant_name = "Mira"; pc.max_hp = 900; pc.current_hp = 900; pc.attack = 50; pc.current_ap = 2
	pc.job = {"id": "fighter"}
	var dummy := Combatant.new()
	autofree(dummy)
	dummy.combatant_name = "Dummy"; dummy.max_hp = 999999; dummy.current_hp = 999999
	bm.player_party.append(pc)
	bm.enemy_party.append(dummy)
	var seen := {"advance": false, "first": false, "pending": -1.0, "executed": 0}
	bm.action_executing.connect(func(_who, act):
		if str(act.get("type", "")) == "advance":
			seen["advance"] = true
			bm.presentation_hold = hold_on_beat
		elif not bool(seen["first"]):
			seen["first"] = true
			seen["pending"] = bm.presentation_hold)
	bm.action_executed.connect(func(_who, _act, _targets): seen["executed"] = int(seen["executed"]) + 1)
	var actions: Array = [{"type": "attack", "target": dummy}, {"type": "attack", "target": dummy}, {"type": "attack", "target": dummy}]
	bm._execute_advance(pc, {"type": "advance", "combatant": pc, "actions": actions, "full_bank": false})
	var first_before_yield: bool = bool(seen["first"])
	## Let the coroutine finish before autofree takes the manager. BOUNDED — an arm that waits on the
	## subject advancing without a limit does not fail when it breaks, it hangs and gets killed.
	var deadline: int = Time.get_ticks_msec() + 5000
	while int(seen["executed"]) < actions.size() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert_eq(int(seen["executed"]), actions.size(), "CONTROL: all three sub-actions ran within the bound")
	assert_true(bool(seen["advance"]), "CONTROL: the advance beat reached the presentation layer")
	return {"first_before_yield": first_before_yield, "pending": float(seen["pending"])}


func test_the_advance_beat_holds_the_stage_before_the_first_lunge() -> void:
	var r: Dictionary = await _run_advance(0.2)
	assert_false(bool(r["first_before_yield"]),
		"the first sub-action ran before the advance yielded — its lunge starts the same frame as the flourish")
	assert_eq(float(r["pending"]), 0.0,
		"the hold was still unconsumed (%.2f) when the first sub-action fired, so nothing waited on it" % float(r["pending"]))


func test_with_no_hold_the_first_action_is_not_delayed() -> void:
	## CONTROL for the arm above, and the proof the await is GATED: with no hold set the first
	## sub-action runs synchronously, exactly as before — turbo, the console, 2x+ and headless keep
	## their pacing with no yield added.
	var r: Dictionary = await _run_advance(0.0)
	assert_true(bool(r["first_before_yield"]),
		"with no hold the first sub-action must run before the advance yields — an ungated await added one")


func test_the_scene_sets_that_hold_on_the_advance_beat() -> void:
	## The ordering arms above set the hold BY HAND, so they prove BattleManager honours one and say
	## nothing about whether the scene ever sets it. _on_action_executing returns before its hold
	## match without an animator, so this reads the code — stripped, because BattleScene carries
	## docstrings and a presence assert over raw source is satisfied by prose naming the call.
	var code: String = GdSource.code_of("res://src/battle/BattleScene.gd")
	var at: int = code.find("func _on_action_executing(")
	assert_gt(at, -1, "CONTROL: the action handler survives stripping")
	var end: int = code.find("\nfunc ", at + 10)
	var body: String = code.substr(at, (end - at) if end > at else 4000)
	assert_true(body.contains("BattleManager.presentation_hold = 0.45"),
		"CONTROL: a known code line in that handler survives the strip (the item arm's hold)")
	var arm: int = body.find('"advance":')
	assert_gt(arm, -1, "the handler has an advance arm")
	assert_true(body.substr(arm, 400).contains("presentation_hold = advance_presentation_hold("),
		"and the advance arm sets the hold — without it the flourish is masked by the first lunge again")


func test_the_scene_sizes_the_hold_to_the_flourish() -> void:
	var prev: float = 0.0
	for n in range(2, 6):
		var h: float = SceneScript.advance_presentation_hold(n)
		assert_gte(h, prev, "a bigger Advance never holds the stage for less (%d: %.2f)" % [n, h])
		prev = h
	assert_gt(SceneScript.advance_presentation_hold(2), 0.0, "every Advance gets a hold at full render")
	assert_lt(SceneScript.advance_presentation_hold(5), 0.62, "and none outlasts a basic attack's own hold")
