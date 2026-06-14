extends GutTest

## Wave G — BEHAVIORAL regression test for end-of-fight boss gloat lines.
##
## Contract under test (LLM OFF — deterministic scripted floor only):
##   1. Defeating a boss (party victory) emits boss_gloat_line(text, true) with a
##      NON-EMPTY line drawn from that boss section's "victory_lines" pool.
##   2. A party wipe BY a boss emits boss_gloat_line(text, false) with a NON-EMPTY
##      line drawn from the "defeat_lines" pool.
##   3. The path NEVER blocks and NEVER errors when boss_dialogue has no section
##      for a given monster (ordinary trash mobs stay silent — no signal).
##   4. BossDialogue.get_victory_line / get_defeat_line return "" gracefully for
##      a missing section or a missing/empty pool — never crash.
##
## DETERMINISM: we inject a known boss section directly into BossDialogue._data
## (and remove it in after_each) so the test does NOT depend on the concurrently
## authored data/boss_dialogue.json pools landing first. LLMService.llm_enabled
## is forced false so the synchronous fallback path is exercised — no network,
## no await, no flakiness. The signal is emitted SYNCHRONOUSLY from
## _dispatch_boss_gloat in that path, so we can watch it inline.
##
## Regression intent: guards the "every boss kill / wipe gets a personality line,
## gracefully degrading to a scripted pool when the LLM is off" feature so a
## future change can't silently drop the gloat or block the battle-end flow.

const TEST_BOSS_ID: String = "test_gloat_boss_g"

var _bm: Node = null
var _dlg: Node = null
var _llm: Node = null

# Saved LLM enable flag so we can restore it for sibling tests.
var _saved_llm_enabled: bool = true
# Whether we injected the test section (so after_each only erases what we added).
var _injected: bool = false


func before_each() -> void:
	_bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	_dlg = Engine.get_main_loop().root.get_node_or_null("BossDialogue")
	_llm = Engine.get_main_loop().root.get_node_or_null("LLMService")

	# Force the deterministic floor: LLM disabled → complete() returns fallback
	# immediately and _dispatch_boss_gloat emits synchronously.
	if _llm:
		_saved_llm_enabled = _llm.llm_enabled
		_llm.llm_enabled = false

	# Inject a known boss section with both pools so the test is independent of
	# the concurrently authored real data.
	if _dlg and "_data" in _dlg:
		_dlg._data[TEST_BOSS_ID] = {
			"display_name": "The Test Gloat Boss",
			"victory_lines": [
				"You automated your way past me... how very modern of you.",
				"Defeated by a script. I almost respect it.",
			],
			"defeat_lines": [
				"Your party falls. Predictable.",
				"And so the irregulars are regularised — into corpses.",
			],
		}
		_injected = true


func after_each() -> void:
	if _llm:
		_llm.llm_enabled = _saved_llm_enabled
	if _dlg and _injected and "_data" in _dlg and _dlg._data.has(TEST_BOSS_ID):
		_dlg._data.erase(TEST_BOSS_ID)
	_injected = false
	# Leave BattleManager INACTIVE + clear for sibling tests.
	if _bm:
		_bm.enemy_party.clear()
		_bm.player_party.clear()
		_bm.all_combatants.clear()
		if "current_state" in _bm:
			_bm.current_state = _bm.BattleState.INACTIVE


# ── Builders ──────────────────────────────────────────────────────────────────

func _make_boss(persona: String) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "The Test Gloat Boss"
	c.max_hp = 300
	c.current_hp = 0          # already defeated for the victory case
	c.is_alive = false
	c.set_meta("is_boss", true)
	c.set_meta("is_miniboss", true)
	c.set_meta("llm_persona_id", persona)
	return c


func _make_trash_mob() -> Combatant:
	# No boss meta, no persona, no boss_dialogue section → must stay silent.
	var c := Combatant.new()
	c.combatant_name = "Slime"
	c.max_hp = 20
	c.current_hp = 0
	c.is_alive = false
	c.set_meta("monster_type", "slime")
	return c


# Stage a battle with a single boss in enemy_party so _dispatch_boss_gloat can
# resolve the persona. enemy_party is the only thing _dispatch_boss_gloat reads.
func _stage(boss: Combatant) -> void:
	_bm.enemy_party.clear()
	_bm.enemy_party.append(boss)


# Capture helper: connect to boss_gloat_line, run the dispatch, return the
# captured payload as { fired:bool, text:String, is_victory:bool }.
func _capture_gloat(victory: bool) -> Dictionary:
	var box := {"fired": false, "text": "", "is_victory": victory}
	var cb := func(text: String, is_victory: bool) -> void:
		box["fired"] = true
		box["text"] = text
		box["is_victory"] = is_victory
	_bm.boss_gloat_line.connect(cb)
	# LLM is off → _dispatch_boss_gloat emits synchronously.
	_bm._dispatch_boss_gloat(victory)
	if _bm.boss_gloat_line.is_connected(cb):
		_bm.boss_gloat_line.disconnect(cb)
	return box


# ── Accessor-level graceful contract ─────────────────────────────────────────

func test_accessors_missing_section_return_empty() -> void:
	assert_not_null(_dlg, "BossDialogue autoload required")
	if _dlg == null:
		return
	assert_eq(_dlg.get_victory_line("no_such_boss_xyz"), "",
		"missing section → victory line is empty string, never a crash")
	assert_eq(_dlg.get_defeat_line("no_such_boss_xyz"), "",
		"missing section → defeat line is empty string, never a crash")


func test_accessors_return_pool_member() -> void:
	if _dlg == null:
		return
	var v: String = _dlg.get_victory_line(TEST_BOSS_ID)
	var d: String = _dlg.get_defeat_line(TEST_BOSS_ID)
	assert_ne(v, "", "victory line must come from the injected pool")
	assert_ne(d, "", "defeat line must come from the injected pool")
	var vpool: Array = _dlg._data[TEST_BOSS_ID]["victory_lines"]
	var dpool: Array = _dlg._data[TEST_BOSS_ID]["defeat_lines"]
	assert_true(vpool.has(v), "returned victory line must be a member of victory_lines")
	assert_true(dpool.has(d), "returned defeat line must be a member of defeat_lines")


func test_accessors_empty_pool_return_empty() -> void:
	# Section present but pools absent → "" (graceful), not a crash.
	if _dlg == null or not ("_data" in _dlg):
		return
	_dlg._data["empty_pool_boss_g"] = {"display_name": "Hollow"}
	assert_eq(_dlg.get_victory_line("empty_pool_boss_g"), "",
		"section with no victory_lines key → empty string")
	assert_eq(_dlg.get_defeat_line("empty_pool_boss_g"), "",
		"section with no defeat_lines key → empty string")
	_dlg._data.erase("empty_pool_boss_g")


# ── Behavioral: victory emits a victory-pool line (LLM off) ──────────────────

func test_boss_defeat_emits_victory_pool_line() -> void:
	assert_not_null(_bm, "BattleManager autoload required")
	if _bm == null or _dlg == null:
		return
	# Sanity: LLM really is off so the synchronous fallback path is taken.
	if _llm and _llm.has_method("is_available"):
		assert_false(_llm.is_available(), "LLM must be unavailable for the scripted-floor test")

	var boss := _make_boss(TEST_BOSS_ID)
	add_child_autofree(boss)
	_stage(boss)

	var box: Dictionary = _capture_gloat(true)

	assert_true(box["fired"], "party victory over a boss must emit boss_gloat_line")
	assert_true(box["is_victory"], "is_victory flag must be true on a party win")
	assert_ne(str(box["text"]).strip_edges(), "",
		"victory gloat line must be NON-EMPTY (scripted-pool fallback)")
	var vpool: Array = _dlg._data[TEST_BOSS_ID]["victory_lines"]
	assert_true(vpool.has(box["text"]),
		"with LLM off, the emitted victory line must be a verbatim victory_lines member")


# ── Behavioral: party wipe emits a defeat-pool line (LLM off) ────────────────

func test_party_wipe_emits_defeat_pool_line() -> void:
	if _bm == null or _dlg == null:
		return

	var boss := _make_boss(TEST_BOSS_ID)
	add_child_autofree(boss)
	_stage(boss)

	var box: Dictionary = _capture_gloat(false)

	assert_true(box["fired"], "a boss wiping the party must emit boss_gloat_line")
	assert_false(box["is_victory"], "is_victory flag must be false on a party wipe")
	assert_ne(str(box["text"]).strip_edges(), "",
		"defeat gloat line must be NON-EMPTY (scripted-pool fallback)")
	var dpool: Array = _dlg._data[TEST_BOSS_ID]["defeat_lines"]
	assert_true(dpool.has(box["text"]),
		"with LLM off, the emitted defeat line must be a verbatim defeat_lines member")


# ── Graceful: no section / trash mob → no gloat, no error ────────────────────

func test_trash_mob_emits_no_gloat() -> void:
	if _bm == null:
		return
	var mob := _make_trash_mob()
	add_child_autofree(mob)
	_stage(mob)

	# Must NOT fire (no boss meta, no persona, no boss_dialogue section) and must
	# NOT error / block.
	var box: Dictionary = _capture_gloat(true)
	assert_false(box["fired"],
		"an ordinary monster with no boss_dialogue section must emit no gloat line")


func test_boss_with_meta_but_no_section_stays_silent() -> void:
	# A flagged boss whose persona has NO boss_dialogue section: graceful silence
	# (the data agent may not have authored every boss's pools yet).
	if _bm == null:
		return
	var boss := _make_boss("unsectioned_boss_persona_g")
	add_child_autofree(boss)
	_stage(boss)

	var box: Dictionary = _capture_gloat(false)
	assert_false(box["fired"],
		"a boss whose persona lacks a boss_dialogue section must stay silent, not crash")


func test_empty_enemy_party_is_safe() -> void:
	# Defensive: dispatching with no enemies at all must be a clean no-op.
	if _bm == null:
		return
	_bm.enemy_party.clear()
	var box: Dictionary = _capture_gloat(true)
	assert_false(box["fired"], "no enemies → no gloat; must not crash")


# ── Signal / API surface guards ──────────────────────────────────────────────

func test_signal_and_api_surface_exists() -> void:
	if _bm == null or _dlg == null:
		return
	assert_true(_bm.has_signal("boss_gloat_line"),
		"BattleManager must expose the boss_gloat_line signal")
	assert_true(_dlg.has_method("get_victory_line"))
	assert_true(_dlg.has_method("get_defeat_line"))
	assert_true(_bm.has_method("_dispatch_boss_gloat"))
