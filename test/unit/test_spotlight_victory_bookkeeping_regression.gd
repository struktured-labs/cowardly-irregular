extends GutTest

## Cycle 13 (msg 2754 → task #2 = spotlight victory bookkeeping audit).
##
## Spotlight duels are 1v1 solo battles wrapping each W1 starter unlock.
## The victory teardown splits across TWO code paths that must agree:
##
##   1) BattleManager.end_battle(true) — runs to completion BEFORE the
##      battle_ended signal fires. Handles: bestiary, prev-bosses, boss
##      splits, PartyChat one_hp_victory, EXP, drops, C3 telemetry.
##
##   2) GameLoop._on_battle_ended — short-circuits on
##      _spotlight_duel_active, sets the unlock flag + clears the loss
##      counter + calls _reconcile_spotlight_locks + emits
##      spotlight_battle_ended, and RETURNS before the normal victory
##      flow (party heal, exploration return, battles_won increment).
##
## This ratchet pins the split so a well-intentioned refactor doesn't:
##   - Move bestiary/prev-bosses AFTER the signal (skipping them for duels)
##   - Delete the short-circuit return (double-teardown, cutscene collides)
##   - Remove data-side markers (spotlight monsters need boss=true so the
##     BM.end_battle boss-tagging path fires them)
##   - Silently start incrementing battles_won for spotlight victories
##     (see FLAG below — this is currently intentional design, deliberate
##     pin; if struktured rules "yes, count them", flip this test to
##     assert the increment instead of the skip)
##
## FLAG for struktured (not this cycle's fix — audit deliverable):
##   `battles_won` (both the GameLoop session-local and GameState
##   persistent counter) is NOT incremented on spotlight victory. The
##   short-circuit returns before reaching line 2797. Downstream
##   consumers under-count by up to 5 (one per W1 duel):
##     - RecordsMenu "Battles Won" player stat
##     - IronhavenStrikeRegistryInterior._storms_survived
##     - CutsceneDirector._detect_playstyle autobattle_ratio denominator
##     - SaveSystem to_dict total_battles
##     - miniboss-every-3 cadence: (battles_won + 1) % 3 == 0 gate
##   Case for including: spotlight IS a battle the player fought+won.
##   Case for excluding: spotlight IS a cutscene-forced encounter that
##   is already itself a miniboss experience; counting would double-tap
##   the miniboss cadence, undercount vs playstyle-detected "autobattler"
##   for a player who only fought duels + autobattled trash.

const GL_PATH: String = "res://src/GameLoop.gd"
const BM_PATH: String = "res://src/battle/BattleManager.gd"
const BES_PATH: String = "res://src/battle/BattleEnemySpawner.gd"


## ── (1) BM.end_battle path: bestiary + prev-bosses + splits still fire ──

func test_bm_end_battle_marks_bestiary_before_signal_emit() -> void:
	## The bestiary loop is inside the VICTORY block ABOVE
	## battle_ended.emit — so it fires for spotlight victories too. If a
	## refactor moves this AFTER emit, spotlight bosses stop crediting.
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var loop_idx: int = src.find("BestiarySystem.mark_defeated(mtype, defeat_loc)")
	assert_gt(loop_idx, -1, "bestiary mark_defeated must exist in BM.end_battle")
	var emit_idx: int = src.find("battle_ended.emit(", loop_idx)
	assert_gt(emit_idx, loop_idx,
		"bestiary loop must run BEFORE battle_ended.emit — spotlight short-circuit runs on the signal, so anything after emit gets skipped for duels")


func test_bm_end_battle_appends_prev_bosses_before_signal_emit() -> void:
	## Same discipline for previously_fought_bosses + record_boss_split
	## (used by pattern_recognition passive + speedrun splits).
	var src: String = FileAccess.get_file_as_string(BM_PATH)
	var prev_idx: int = src.find("previously_fought_bosses")
	assert_gt(prev_idx, -1)
	var emit_idx: int = src.find("battle_ended.emit(", prev_idx)
	assert_gt(emit_idx, prev_idx,
		"prev_bosses append must run BEFORE battle_ended.emit for the spotlight bosses to credit")


## ── (2) GameLoop._on_battle_ended short-circuit shape ──

func test_spotlight_short_circuit_sets_unlock_flag_on_victory() -> void:
	var src: String = FileAccess.get_file_as_string(GL_PATH)
	var idx: int = src.find("if _spotlight_duel_active:")
	assert_gt(idx, -1, "spotlight short-circuit must exist")
	var window: String = _short_circuit_block(src, idx)
	assert_string_contains(window, "cutscene_flag_spotlight_unlocked_",
		"victory branch must set the unlock cutscene flag")
	assert_string_contains(window, "_pending_spotlight_unlock",
		"unlock flag names must include the pending job id")


func test_spotlight_short_circuit_clears_loss_counter_on_victory() -> void:
	## Clearing (not resetting to 0) matches msg 2472 ruling: a hypothetical
	## replay starts fresh, and .get(key, 0) sees the same 0 either way.
	var src: String = FileAccess.get_file_as_string(GL_PATH)
	var idx: int = src.find("if _spotlight_duel_active:")
	assert_gt(idx, -1)
	var window: String = _short_circuit_block(src, idx)
	assert_string_contains(window, "spotlight_losses_",
		"loss counter key must be per-job")
	assert_string_contains(window, "GameState.game_constants.erase(loss_key)",
		"loss counter must be erased (not set-to-0) on victory")


func test_spotlight_short_circuit_increments_loss_counter_on_defeat() -> void:
	## Death-tier hint counter (msg 2472). Persistence via game_constants
	## survives a save+quit mid-attempt; start_solo_battle reads it on
	## the next entry to fire spotlight_hint_<job>_<tier>.
	var src: String = FileAccess.get_file_as_string(GL_PATH)
	var idx: int = src.find("elif not victory and _pending_spotlight_unlock")
	assert_gt(idx, -1, "defeat branch of the short-circuit must exist")
	var window: String = _short_circuit_block(src, idx)
	assert_string_contains(window, "GameState.game_constants[loss_key] = current + 1",
		"defeat branch must increment loss counter")


func test_spotlight_short_circuit_calls_reconcile_locks_on_victory() -> void:
	## _reconcile_spotlight_locks walks the party and flips
	## autobattle_locked→false for any PC whose spotlight flag is set.
	## Must fire IN the short-circuit so the mid-battle unlock takes
	## immediate effect (post-cutscene party menu shows unlocked kit).
	var src: String = FileAccess.get_file_as_string(GL_PATH)
	var idx: int = src.find("if _spotlight_duel_active:")
	assert_gt(idx, -1)
	var window: String = _short_circuit_block(src, idx)
	var flag_idx: int = window.find("cutscene_flag_spotlight_unlocked_")
	var reconcile_idx: int = window.find("_reconcile_spotlight_locks()")
	assert_gt(reconcile_idx, flag_idx,
		"_reconcile_spotlight_locks must be called AFTER the flag is set — pre-set call finds the flag still false and doesn't flip anything")


func test_spotlight_short_circuit_emits_signal_and_returns() -> void:
	## start_solo_battle awaits spotlight_battle_ended — without this
	## emit the coroutine deadlocks; without the return, the normal
	## victory flow runs a second teardown under the cutscene.
	var src: String = FileAccess.get_file_as_string(GL_PATH)
	var idx: int = src.find("if _spotlight_duel_active:")
	assert_gt(idx, -1)
	var window: String = _short_circuit_block(src, idx)
	assert_string_contains(window, "spotlight_battle_ended.emit(victory)",
		"signal must fire so start_solo_battle can resume")
	# The return must land BETWEEN the emit and the normal victory block.
	# Text-check: `return` on the same line as or immediately after the emit.
	var emit_idx: int = window.find("spotlight_battle_ended.emit(victory)")
	var post_emit: String = window.substr(emit_idx, 200)
	assert_string_contains(post_emit, "\n\t\treturn",
		"short-circuit must return immediately after emit — falling through re-runs the normal victory flow (double teardown, cutscene collision)")


## ── (3) battles_won: duels COUNT, but are removed from the ratio ──

func test_spotlight_victory_counts_as_a_battle_won() -> void:
	## struktured ruled 2026-07-29: "the fights which unlock each of the 5 party members —
	## remove from the ratio." So the duel IS a battle won (Records must say so; it previously
	## under-counted by five) and it is excluded from the AUTOMATION RATIO instead.
	##
	## This test previously PINNED the skip as design-ambiguous, with a comment instructing
	## exactly this flip once he ruled. Flipped rather than deleted — the pin did its job.
	var src: String = FileAccess.get_file_as_string(GL_PATH)
	var sc: int = src.find("if _spotlight_duel_active:")
	assert_gt(sc, -1)
	var emit_idx: int = src.find("spotlight_battle_ended.emit(victory)", sc)
	var inside: String = src.substr(sc, emit_idx - sc)
	assert_string_contains(inside, "GameState.battles_won += 1",
		"a won duel must increment battles_won INSIDE the short-circuit — the early return "
		+ "previously skipped it, under-counting Records by the five unlock fights")
	assert_string_contains(inside, "GameState.spotlight_duels_won += 1",
		"and must record it as a DUEL, so the automation ratio can subtract it")


func test_the_ratio_excludes_duels() -> void:
	## The ruling's actual subject. battles_won is both a display number and the ratio's
	## denominator, and those want different answers: five forced-manual tutorial fights are
	## battles the player won, but say nothing about their automation habits. Leaving them in
	## the denominator of an automation ratio biases toward "automator" — backwards, since they
	## are the most manual battles in the game.
	var cd: String = FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	assert_string_contains(cd, "organic_battles_won()",
		"the playstyle ratio must use the organic count, not raw battles_won")


func test_organic_count_subtracts_duels_and_never_goes_negative() -> void:
	var saved_b: int = GameState.battles_won
	var saved_d: int = GameState.spotlight_duels_won
	GameState.battles_won = 25
	GameState.spotlight_duels_won = 5
	assert_eq(GameState.organic_battles_won(), 20,
		"25 fights won, 5 of them duels -> 20 battles that are evidence about automation")
	# A corrupted or hand-edited save must not produce a negative denominator.
	GameState.battles_won = 2
	GameState.spotlight_duels_won = 9
	assert_eq(GameState.organic_battles_won(), 0, "clamped, never negative")
	GameState.battles_won = saved_b
	GameState.spotlight_duels_won = saved_d



## ── (4) Data-side pin: spotlight monsters must remain boss-tagged ──

func test_spotlight_monsters_still_have_boss_true_in_data() -> void:
	## Spotlight monsters need boss=true (or miniboss=true) in
	## monsters.json so BattleEnemySpawner sets the is_boss meta at
	## spawn — which the BM.end_battle prev_bosses loop keys off. A
	## data refactor that flips these to trash-type would silently
	## stop crediting them in prev_bosses/splits/persona-memory.
	var f: FileAccess = FileAccess.open("res://data/monsters.json", FileAccess.READ)
	assert_not_null(f, "monsters.json must exist")
	var ms: Dictionary = JSON.parse_string(f.get_as_text())
	assert_typeof(ms, TYPE_DICTIONARY)
	var spotlight_ids: Array = [
		"fighter_skeleton_knight",
		"cleric_survive_target",
		"rogue_lockward",
		"mage_prismatic_construct",
		"bard_hostile_courtier",
	]
	for id in spotlight_ids:
		assert_true(ms.has(id), "spotlight monster '%s' must exist in monsters.json" % id)
		var m: Dictionary = ms[id]
		var is_boss_like: bool = bool(m.get("boss", false)) or bool(m.get("miniboss", false))
		assert_true(is_boss_like,
			"spotlight monster '%s' must have boss=true or miniboss=true — bestiary/prev-bosses/splits need is_boss meta at spawn" % id)


## ── (5) BattleEnemySpawner sets the boss meta from data ──

func test_spawner_sets_is_boss_meta_from_data() -> void:
	## BM.end_battle only credits prev_bosses / boss splits when
	## enemy.get_meta("is_boss") returns true. That meta gets set by
	## BattleEnemySpawner reading monster_data.boss / .miniboss. If a
	## refactor drops the set_meta calls, spotlight bosses silently
	## stop crediting — same silent-failure class the CLAUDE.md pattern
	## principle guards against.
	var src: String = FileAccess.get_file_as_string(BES_PATH)
	var idx: int = src.find("monster_data.get(\"boss\", false) or monster_data.get(\"miniboss\", false)")
	assert_gt(idx, -1, "spawner must key is_boss meta off monster_data.boss || .miniboss")
	var window: String = src.substr(idx, 300)
	assert_string_contains(window, "set_meta(\"is_boss\", true)",
		"is_boss meta must be set — bestiary/prev-bosses check this")


## ── (6) _reconcile_spotlight_locks call sites (post-load survival) ──

func test_reconcile_spotlight_locks_called_on_party_rehydrate() -> void:
	## Save+quit after a spotlight victory reloads Combatants with
	## autobattle_locked defaulting to true — the reconcile call flips
	## them false again based on the persisted cutscene_flag. Without
	## this call, the player would find their previously-unlocked
	## duelist locked out after loading.
	var src: String = FileAccess.get_file_as_string(GL_PATH)
	# Locate the rehydrate block — the comment above the call is
	# stable ("flags persist in game_constants").
	var comment_idx: int = src.find("Spotlight reconcile after load")
	assert_gt(comment_idx, -1, "post-load reconcile comment must exist")
	var window: String = src.substr(comment_idx, 300)
	assert_string_contains(window, "_reconcile_spotlight_locks()",
		"post-load must call _reconcile_spotlight_locks — otherwise unlocked duelists come back locked")


## The spotlight short-circuit block, bounded at its own `return` rather than a byte count.
## A fixed window silently truncates when anyone adds a line inside the block — which is exactly
## what happened when the battles_won ruling landed: the emit fell outside a 1500-char window and
## three assertions started searching a region that no longer contained their subject.
func _short_circuit_block(src: String, idx: int) -> String:
	var end: int = src.find("\n\t\treturn", idx)
	if end == -1:
		return src.substr(idx, 2000)
	return src.substr(idx, end - idx + 12)
