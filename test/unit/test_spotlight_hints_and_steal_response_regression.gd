extends GutTest

## Two Rogue-duel playtest fixes bundled (cowir-main msg 2472 + msg 2474):
##
## 1. Progressive death-tiered hints: each defeat against a spotlight boss
##    increments GameState.game_constants["spotlight_losses_<job>"]. On next
##    duel attempt, a threshold table maps loss-count to a hint tier that
##    fires spotlight_hint_<job>_<tier> via TutorialHints. Victory resets
##    the counter. Content owner: cowir-story.
##
## 2. Steal-triggers-weakness (Lockward's vault-crack): a successful Rogue
##    Steal against a target with monsters.json steal_response applies its
##    mechanical effect once per fight. Lockward's shape: defense_break /
##    modifier=0.5 → permanent Vault-Cracked debuff. Design: rewards Rogue's
##    signature-ability read, tunes the fight from impossible to fair.

const GameLoopScript = preload("res://src/GameLoop.gd")


## ── Progressive hint threshold table ───────────────────────────────────

func test_hint_thresholds_declared_as_array() -> void:
	# Explicit thresholds over a formula so per-boss tuning is one edit.
	# cowir-main's suggestion: 2, 4, 6 (breathing room before hints start).
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_string_contains(src, "const SPOTLIGHT_HINT_THRESHOLDS",
		"threshold array must be a named const — greppable + tunable")
	assert_string_contains(src, "[2, 4, 6]",
		"cowir-main msg 2472 default: tier 1 after 2 losses, tier 2 after 4, tier 3 after 6")


func test_hint_tier_zero_below_first_threshold() -> void:
	# Player gets breathing room to figure it out themselves before hints
	# start — 0 losses = no hint, 1 loss = still no hint.
	assert_eq(GameLoopScript._spotlight_hint_tier(0), 0,
		"0 losses must return tier 0 (no hint)")
	assert_eq(GameLoopScript._spotlight_hint_tier(1), 0,
		"1 loss is still below threshold — no hint (morale-friendly cadence)")


func test_hint_tier_advances_with_thresholds() -> void:
	# 2 losses = tier 1; 4 losses = tier 2; 6 losses = tier 3.
	# Between-threshold values stay on the lower tier (3 losses = still tier 1).
	assert_eq(GameLoopScript._spotlight_hint_tier(2), 1, "2 losses → tier 1")
	assert_eq(GameLoopScript._spotlight_hint_tier(3), 1, "3 losses stays on tier 1")
	assert_eq(GameLoopScript._spotlight_hint_tier(4), 2, "4 losses → tier 2")
	assert_eq(GameLoopScript._spotlight_hint_tier(5), 2, "5 losses stays on tier 2")
	assert_eq(GameLoopScript._spotlight_hint_tier(6), 3, "6 losses → tier 3")


func test_hint_tier_caps_at_array_length() -> void:
	# A player who loses 20+ times still gets tier 3 (the last authored tier),
	# never a bogus tier 4 that would push_warning on every duel start.
	assert_eq(GameLoopScript._spotlight_hint_tier(99), 3,
		"unbounded losses cap at the last threshold count")


## ── Loss counter wired on defeat / cleared on victory ──────────────────

func test_on_battle_ended_increments_loss_counter_on_defeat() -> void:
	# Anchor on the distinctive defeat-branch marker so we can't be
	# fooled by prior duplicate occurrences of "if _spotlight_duel_active:".
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var idx: int = src.find("elif not victory and _pending_spotlight_unlock")
	assert_gt(idx, -1, "defeat branch must exist in the short-circuit — parallel to the victory unlock flag")
	var window: String = src.substr(idx, 800)
	assert_string_contains(window, "\"spotlight_losses_\" + _pending_spotlight_unlock",
		"loss_key must be namespaced per-job")
	assert_string_contains(window, "GameState.game_constants[loss_key] = current + 1",
		"the counter must actually increment (missing this = silent failure, no tier ever fires)")


func test_on_battle_ended_clears_loss_counter_on_victory() -> void:
	# Anchor on my new "[SPOTLIGHT] battle won → set" print (introduced by
	# this fix) so we're guaranteed to land in the victory branch of the
	# short-circuit, not any generic reference to the unlock flag.
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var idx: int = src.find("[SPOTLIGHT] battle won")
	assert_gt(idx, -1, "the updated victory-branch print must exist")
	var window: String = src.substr(maxi(0, idx - 500), 700)
	assert_string_contains(window, "GameState.game_constants.erase(loss_key)",
		"victory branch must clear the loss counter — otherwise a replay inherits tier from the prior run")


func test_maybe_fire_helper_iterates_all_tiers_monotonically() -> void:
	# cowir-story msg 2478 gate: fire tier N iff losses >= threshold_N AND not
	# already shown. Meaning: if a player's counter jumps past threshold_1
	# without ever seeing tier 1 (save-load edge, bug, etc.), tier 1 STILL
	# fires on the next duel start. Multiple unfired tiers can fire in one
	# call. Deduplication belongs to TutorialHints.show internally.
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var idx: int = src.find("func _maybe_fire_spotlight_hint(job_id: String)")
	assert_gt(idx, -1)
	var body: String = src.substr(idx, 900)
	assert_string_contains(body, "GameState.game_constants.get(loss_key, 0)",
		"helper must read from game_constants with a safe default")
	assert_string_contains(body, "for i in range(SPOTLIGHT_HINT_THRESHOLDS.size()):",
		"helper must iterate all tiers, not compute a single 'highest' one — a jumped counter must still surface earlier tiers the player hasn't seen")
	assert_string_contains(body, "if losses >= threshold:",
		"comparison must be >= not == (cowir-story msg 2478 requirement)")
	assert_string_contains(body, "\"spotlight_hint_%s_%d\" % [job_id, tier]",
		"hint id pattern is contract with cowir-story: spotlight_hint_<job>_<tier>")
	assert_string_contains(body, "TutorialHints.show(self, hint_id)",
		"delivery through TutorialHints so dedupe (per-session + per-save) is honored")


func test_start_solo_battle_calls_maybe_fire_after_state_setup() -> void:
	# The hint fires BEFORE _start_battle_async so it shows up-front, not
	# during battle. Position after _spotlight_duel_active = true so the
	# state is coherent if the hint queries GameLoop state.
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var idx: int = src.find("_maybe_fire_spotlight_hint(job_id)")
	assert_gt(idx, -1, "start_solo_battle must call the fire helper")
	var back: String = src.substr(maxi(0, idx - 600), 600)
	assert_string_contains(back, "_spotlight_duel_active = true",
		"hint call must come after _spotlight_duel_active is set — coherent state during the hint")


## ── Watchdog diag surfaces spotlight_losses ────────────────────────────

func test_menu_wd_diag_includes_spotlight_losses() -> void:
	# msg 2472 bonus: watchdog trip cap shows current loss count. Great
	# tuning data — cowir-main will see e.g. "spotlight_losses=3" at trip
	# time and correlate with tier gates.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var idx: int = src.find("func _menu_wd_diag(pc: Combatant) -> String:")
	assert_gt(idx, -1)
	var body: String = src.substr(idx, 1500)
	assert_string_contains(body, "\"spotlight_losses_\" + pc_job_id",
		"diag must key the loss counter on the CURRENT PC's job — not a random one")
	assert_string_contains(body, "spotlight_losses=%d",
		"diag output must include the counter in the printable format string")


## ── Steal-response mechanic (Option 2 — defense break) ─────────────────

const CombatantScript = preload("res://src/battle/Combatant.gd")


func _make_target(monster_type: String, max_hp: int = 260, def: int = 30) -> Combatant:
	var c: Combatant = CombatantScript.new()
	c.combatant_name = monster_type
	c.max_hp = max_hp
	c.current_hp = max_hp
	c.defense = def
	c.is_alive = true
	c.set_meta("monster_type", monster_type)
	add_child_autofree(c)
	return c


func test_lockward_data_has_steal_response() -> void:
	# Data-side contract: rogue_lockward carries the steal_response the
	# BM handler will read at cast time. Missing = silent no-op, mechanic
	# reverts to gold-only steal — playtest bounces off the fight again.
	var f := FileAccess.open("res://data/monsters.json", FileAccess.READ)
	assert_not_null(f)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	assert_true(data.has("rogue_lockward"))
	var lockward: Dictionary = data["rogue_lockward"]
	assert_true(lockward.has("steal_response"),
		"Lockward's data must define steal_response")
	var r: Dictionary = lockward["steal_response"]
	assert_eq(str(r.get("type", "")), "defense_break",
		"tier-1 shape (Option 2): defense_break")
	assert_almost_eq(float(r.get("modifier", 0.0)), 0.5, 0.001,
		"modifier 0.5 = defense halved — tuned so backstabs land ~60 vs prior ~30")
	assert_ne(str(r.get("message", "")), "",
		"message must be non-empty for player feedback (cowir-story owns final copy)")


func test_apply_steal_response_defense_break_applies_vault_cracked_debuff() -> void:
	var t := _make_target("test_monster")
	# Fake the mdata by installing a stub monster_database entry the same
	# way EncounterSystem does at runtime. We can't easily construct a full
	# EncounterSystem here, so exercise the code path against the real one
	# by using rogue_lockward's live entry.
	t.set_meta("monster_type", "rogue_lockward")
	# Have to lookup BM instance to call the helper. Guard for headless.
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless — behavioral coverage skipped, source pin below still holds")
		return
	bm._apply_steal_response(t)
	assert_true(t.active_debuffs.size() > 0,
		"Vault-Cracked debuff must be applied")
	var found_debuff: bool = false
	for d in t.active_debuffs:
		if str(d.get("effect", "")) == "Vault-Cracked" and str(d.get("stat", "")) == "defense":
			found_debuff = true
			assert_almost_eq(float(d.get("modifier", 0.0)), 0.5, 0.001,
				"defense modifier matches monsters.json")
			break
	assert_true(found_debuff, "debuff must be named Vault-Cracked and target defense")
	assert_true(t.has_meta("_steal_response_consumed") and bool(t.get_meta("_steal_response_consumed")),
		"one-shot guard meta must be set")


func test_apply_steal_response_is_one_shot_per_fight() -> void:
	# Re-applying must be a no-op — second successful Steal against the
	# same Lockward can't stack down defense further. Gold still awarded
	# (that's in the caller, not this helper).
	var t := _make_target("rogue_lockward")
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	bm._apply_steal_response(t)
	var count_after_first: int = t.active_debuffs.size()
	bm._apply_steal_response(t)
	assert_eq(t.active_debuffs.size(), count_after_first,
		"second application must be a no-op — the meta guard blocks it")


func test_apply_steal_response_no_op_when_target_has_no_monster_type() -> void:
	# Attacking a player-side target via Steal shouldn't crash — the field
	# absence is a normal case (party members have no monster_type meta).
	var pc: Combatant = CombatantScript.new()
	pc.combatant_name = "Rogue"
	pc.is_alive = true
	add_child_autofree(pc)
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	bm._apply_steal_response(pc)
	assert_eq(pc.active_debuffs.size(), 0,
		"no monster_type meta → helper must be a no-op, not error")


func test_apply_steal_response_no_op_when_monster_has_no_response() -> void:
	# A generic monster (e.g. slime) should be unaffected — the helper only
	# fires for monsters that opted in via monsters.json steal_response.
	var t := _make_target("slime")  # slime has no steal_response in data
	var bm: Node = get_tree().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload not available in headless")
		return
	bm._apply_steal_response(t)
	assert_eq(t.active_debuffs.size(), 0,
		"target without steal_response definition = no-op")
	assert_false(t.has_meta("_steal_response_consumed"),
		"the guard meta must NOT be set for a no-op path — otherwise a boss that later adds steal_response wouldn't fire mid-run")


func test_steal_handler_calls_apply_steal_response_on_success() -> void:
	# Source pin: the "steal" handler in BM must call the response helper
	# on a successful steal. Anchor on the distinctive comment I added so
	# we can't be fooled by any earlier "steal": occurrence.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx: int = src.find("Boss-specific steal_response (msg 2474)")
	assert_gt(idx, -1, "the new steal-response comment must exist as an anchor")
	var window: String = src.substr(idx, 400)
	assert_string_contains(window, "_apply_steal_response(target)",
		"the response helper must be called on successful steal — dropping this reverts Lockward to gold-only")


func test_apply_steal_response_helper_declared() -> void:
	# Sanity: the helper exists so BM's steal handler doesn't reference a
	# nonexistent method.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_string_contains(src, "func _apply_steal_response(target: Combatant) -> void:",
		"helper must exist with the expected signature")


## ── Message wording (Warden's Key, cowir-story msg 2478) ───────────────

func test_lockward_message_uses_warden_key_naming() -> void:
	# cowir-story finalized "Warden's Key" as the item name — Lockward IS a
	# Warden-class Masterite, so this reads as taking his guardian identity
	# not just an object. If someone reverts to "vault key" the naming
	# clashes with the cowir-story dialogue pools that reference the Warden.
	var f := FileAccess.open("res://data/monsters.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var r: Dictionary = data["rogue_lockward"]["steal_response"]
	var msg: String = str(r.get("message", ""))
	assert_string_contains(msg, "Warden's Key",
		"message must reference the finalized 'Warden's Key' naming — not 'vault key' / 'key of the vault'")


## ── BossDialogue getters for the new pools (cowir-story msg 2478) ──────

func test_boss_dialogue_get_steal_success_line_declared() -> void:
	# BossDialogue getter for the steal_success_lines pool — used by
	# _apply_steal_response to emit a boss_taunt in the same beat as the
	# mechanic. If the getter goes missing the flavor doesn't land.
	var src: String = FileAccess.get_file_as_string("res://src/llm/BossDialogue.gd")
	assert_string_contains(src, "func get_steal_success_line(boss_id: String) -> String:",
		"getter for steal_success_lines must exist")
	assert_string_contains(src, "_random_pool_line(boss_id, \"steal_success_lines\")",
		"getter must key on 'steal_success_lines' — that's the pool cowir-story authored")


func test_boss_dialogue_get_victory_line_stolen_key_declared() -> void:
	# The differentiated win pool for the Steal-path victory. Falls back
	# to standard get_victory_line when this pool is empty.
	var src: String = FileAccess.get_file_as_string("res://src/llm/BossDialogue.gd")
	assert_string_contains(src, "func get_victory_line_stolen_key(boss_id: String) -> String:",
		"getter for victory_lines_stolen_key must exist")
	assert_string_contains(src, "_random_pool_line(boss_id, \"victory_lines_stolen_key\")",
		"getter must key on 'victory_lines_stolen_key'")


## ── boss_taunt emit in steal-response (cowir-story msg 2478) ───────────

func test_apply_steal_response_emits_boss_taunt_on_success() -> void:
	# Source pin: the defense_break branch of _apply_steal_response must
	# emit boss_taunt with the steal_success_line. Same channel as phase-
	# transition quips so BattleScene bubbles it as boss speech.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx: int = src.find("func _apply_steal_response(target: Combatant) -> void:")
	assert_gt(idx, -1)
	var body: String = src.substr(idx, 2000)
	assert_string_contains(body, "get_steal_success_line(mtype)",
		"defense_break branch must query the boss dialogue for the steal beat")
	assert_string_contains(body, "boss_taunt.emit(target, line)",
		"the resulting line must go out via boss_taunt so it renders as speech, not just a log line")


## ── Victory-line differentiation on the stolen-key path ────────────────

func test_dispatch_boss_gloat_routes_stolen_key_line_on_victory() -> void:
	# When the party wins AND the boss got its Warden's Key stolen this
	# fight, victory_lines_stolen_key is preferred. Standard victory_lines
	# is the fallback if the differentiated pool is unauthored.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx: int = src.find("func _dispatch_boss_gloat(victory: bool) -> void:")
	assert_gt(idx, -1)
	var body: String = src.substr(idx, 1800)
	assert_string_contains(body, "_resolved_boss_had_key_stolen(persona_id)",
		"the victory branch must consult whether the key was stolen this fight")
	assert_string_contains(body, "get_victory_line_stolen_key(persona_id)",
		"stolen-key path must query the differentiated pool")
	assert_string_contains(body, "if fallback == \"\":",
		"empty differentiated pool must fall back to standard victory_lines")


func test_resolved_boss_had_key_stolen_reads_meta() -> void:
	# The predicate must find the enemy party member matching persona_id
	# and read its _steal_response_consumed meta. Missing this check =
	# the differentiated pool never fires even when the mechanic did.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx: int = src.find("func _resolved_boss_had_key_stolen(persona_id: String) -> bool:")
	assert_gt(idx, -1)
	var body: String = src.substr(idx, 600)
	assert_string_contains(body, "e.get_meta(\"monster_type\", \"\")",
		"predicate must match on monster_type (persona_id) to find the right combatant")
	assert_string_contains(body, "_steal_response_consumed",
		"predicate must read the guard meta the steal-response helper sets")
