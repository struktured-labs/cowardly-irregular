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
	var window: String = src.substr(idx, 1500)
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
	var window: String = src.substr(idx, 1500)
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
	var window: String = src.substr(idx, 800)
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
	var window: String = src.substr(idx, 1500)
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
	var window: String = src.substr(idx, 1500)
	assert_string_contains(window, "spotlight_battle_ended.emit(victory)",
		"signal must fire so start_solo_battle can resume")
	# The return must land BETWEEN the emit and the normal victory block.
	# Text-check: `return` on the same line as or immediately after the emit.
	var emit_idx: int = window.find("spotlight_battle_ended.emit(victory)")
	var post_emit: String = window.substr(emit_idx, 200)
	assert_string_contains(post_emit, "\n\t\treturn",
		"short-circuit must return immediately after emit — falling through re-runs the normal victory flow (double teardown, cutscene collision)")


## ── (3) battles_won: currently SKIPPED for spotlight (design flag) ──

func test_battles_won_currently_skipped_for_spotlight_victory() -> void:
	## PIN CURRENT BEHAVIOR: the short-circuit returns BEFORE the
	## `battles_won += 1` line. This is DESIGN-AMBIGUOUS — if struktured
	## rules "spotlights should count as battles_won," flip the return
	## into `if victory: battles_won += 1; if GameState: GameState
	## .battles_won += 1` inside the short-circuit BEFORE the return,
	## and change this test's assertions to check the counters
	## increment rather than the structural skip.
	var src: String = FileAccess.get_file_as_string(GL_PATH)
	var short_circuit_idx: int = src.find("if _spotlight_duel_active:")
	assert_gt(short_circuit_idx, -1)
	var battles_won_incr_idx: int = src.find("battles_won += 1")
	assert_gt(battles_won_incr_idx, short_circuit_idx,
		"battles_won += 1 must be BELOW the short-circuit — pinning current 'skip for spotlight' behavior")
	# The window between the short-circuit's `return` and the increment
	# must not contain another `battles_won += 1` (which would mean the
	# short-circuit *does* count spotlights, contradicting the pin).
	var post_short_circuit: String = src.substr(short_circuit_idx, battles_won_incr_idx - short_circuit_idx)
	var second_incr: int = post_short_circuit.find("battles_won += 1")
	assert_eq(second_incr, -1,
		"no battles_won increment inside the short-circuit — if intent changed, delete this pin and add the increment")


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
