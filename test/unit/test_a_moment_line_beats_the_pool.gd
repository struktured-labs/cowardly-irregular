extends GutTest

## Spec 2a.1 step 2 — "a line written for THIS MOMENT outranks everything, including a ready pooled
## line" — was shipped and FED BY NOTHING: 630 lines, 0 carrying a moment tag, so has_moment_line
## could not return true in a player's game. cowir-ai pinned that at 0 and asked for an end-to-end
## arm the day content landed rather than a raised number; 30 moment lines landed 2026-10-12 and the
## arms below are that hand-off, fired through BattleManager against the SHIPPED corpus with no
## planted line. The moment vocabulary is DERIVED from the evaluator, so a new tag joins it here
## without an edit. Content is cowir-story's; the picker and the evaluators are cowir-ai's.

const JOBS: Array[String] = ["fighter", "cleric", "mage", "rogue", "bard"]
const TRIGGERS: Array[String] = ["turn_start", "big_hit_taken", "low_hp", "used_signature_ability", "victory"]
const POOL_DIR := "user://test_moment_beats_pool"
const POOLED := "Pooled line, ready and waiting."
const SETTLE_FRAMES := 5

var _saved: Dictionary = {}
var _heard: Array = []
var _keys: Array = []


func _wipe() -> void:
	var d := DirAccess.open(POOL_DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


func before_each() -> void:
	PartyPersonas._recent_spoken.clear()  # the pick window leaks across FILES; see test_a_voice_store_is_left_as_it_was_found
	PartyPersonas._last_variant.clear()
	_wipe()
	_saved = {
		"rogue": (PartyPersonas._data.get("rogue", {}) as Dictionary).duplicate(true),
		"cast": VoiceService._cast.duplicate(true), "cache": VoiceService.cache, "store": VoicePool.store,
		"tts": GameState.tts_live_enabled, "pld": GameState.party_llm_dialogue_enabled,
		"vel": GameState.game_constants.get("dev_voice_every_line", null),
		"party": BattleManager.player_party.duplicate(), "foes": BattleManager.enemy_party.duplicate(),
		"state": BattleManager.current_state, "turbo": BattleManager.turbo_mode,
		"llm_on": LLMService.llm_enabled, "scale": Engine.time_scale,
	}
	VoicePool.set_process(false)
	VoiceService.cache = VoiceCache.new(POOL_DIR, 10_000_000)
	VoiceService._cast = {"fighter": {"voice": "fighter.wav", "rev": 1}}
	VoicePool.store = VoicePoolStore.new(POOL_DIR + "/pool.json")
	VoicePool.store.put("fighter", "turn_start", POOLED, "fighter.wav", 1)
	VoiceService.cache.write(VoiceCache.key_for("fighter.wav", 1, POOLED), WavFixture.tone(0.3, 8000))
	GameState.tts_live_enabled = true
	GameState.party_llm_dialogue_enabled = true
	GameState.game_constants.erase("dev_voice_every_line")
	## The pool/moment decision is made BEFORE the model is consulted, so an unavailable LLM isolates
	## exactly the comparison under test: pooled line vs. authored moment line.
	LLMService.llm_enabled = false
	BattleManager.turbo_mode = false
	Engine.time_scale = BattleSpeechBubble.SUPPRESS_TIME_SCALE * 0.5
	## A line left awaiting a model by an EARLIER file resumes and emits into this capture; production
	## drops it via _line_moment_passed, so trip that same guard rather than filtering the signal.
	BattleManager.battle_serial += 1
	_heard.clear()
	_keys.clear()
	BattleManager.party_combat_line.connect(_on_line)


func after_each() -> void:
	BattleManager.party_combat_line.disconnect(_on_line)
	PartyPersonas._recent_spoken.clear()
	PartyPersonas._last_variant.clear()
	PartyPersonas._data["rogue"] = _saved["rogue"]
	BattleManager.current_state = _saved["state"]
	BattleManager.player_party.assign((_saved["party"] as Array).filter(func(c): return is_instance_valid(c)))
	BattleManager.enemy_party.assign((_saved["foes"] as Array).filter(func(c): return is_instance_valid(c)))
	BattleManager.turbo_mode = _saved["turbo"]
	LLMService.llm_enabled = _saved["llm_on"]
	if _saved["vel"] != null:
		GameState.game_constants["dev_voice_every_line"] = _saved["vel"]
	GameState.tts_live_enabled = _saved["tts"]
	GameState.party_llm_dialogue_enabled = _saved["pld"]
	VoiceService._cast = _saved["cast"]
	VoiceService.cache = _saved["cache"]
	VoicePool.store = _saved["store"]
	VoicePool.set_process(true)
	Engine.time_scale = _saved["scale"]
	_wipe()


func _on_line(_who, line, key) -> void:
	_heard.append(str(line))
	_keys.append(str(key))


## Pooled emissions in this window; an unrelated dispatch carries a trigger key, never a token.
func _pool_keys() -> int:
	return _keys.filter(func(k): return str(k).begins_with("pool:")).size()


## Derived from the evaluator, so a tag added there joins this vocabulary without an edit here.
func _moment_vocabulary() -> Array[String]:
	var out: Array[String] = []
	for t in VoiceLineTags.SIMPLE_TAGS:
		if VoiceLineTags.is_moment_tag(str(t)):
			out.append(str(t))
	return out


func _authored_moment_lines() -> Array[String]:
	var found: Array[String] = []
	for job in JOBS:
		for trig in TRIGGERS:
			for e in PartyPersonas.get_trigger_entries(job, trig):
				for t in (e.get("tags", []) as Array):
					if VoiceLineTags.is_moment_tag(str(t)):
						found.append("%s/%s [%s]" % [job, trig, t])
						break
	return found


## The shipped lines a Fighter's turn can speak only because this tag holds.
func _fighter_lines_tagged(tag: String) -> Array:
	var out: Array = []
	for e in PartyPersonas.get_trigger_entries("fighter", "turn_start"):
		if (e.get("tags", []) as Array).has(tag):
			out.append(str(e.get("line", "")))
	return out


func _fighter_moment_lines() -> Array:
	var out: Array = []
	for e in PartyPersonas.get_trigger_entries("fighter", "turn_start"):
		for t in (e.get("tags", []) as Array):
			if VoiceLineTags.is_moment_tag(str(t)):
				out.append(str(e.get("line", "")))
				break
	return out


func _member(who: String, job: String, alive: bool) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = who
	c.job = {"id": job}
	c.is_alive = alive
	c.max_hp = 100
	c.current_hp = 100 if alive else 0
	return c


## Two foes at full health, so no ENEMY-side moment can hold and the party side is the only variable.
func _foe(who: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = who
	c.max_hp = 100
	c.current_hp = 100
	c.is_alive = true
	return c


## A Fighter's turn with three in the party, so an ally being down never also means last_standing.
func _ask(fallen_ally: bool) -> void:
	var brom := _member("Brom", "fighter", true)
	BattleManager.player_party.assign([brom, _member("Mira", "cleric", not fallen_ally), _member("Zeph", "mage", true)])
	BattleManager.enemy_party.assign([_foe("Slime"), _foe("Rat")])
	BattleManager.current_state = BattleManager.BattleState.PLAYER_SELECTING
	BattleManager._run_party_line_async(brom, "turn_start", {})
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame


func test_the_moment_vocabulary_is_not_empty() -> void:
	## CONTROL on the derivation: if this ever reads empty, every arm below is vacuous rather than clean.
	var vocab: Array[String] = _moment_vocabulary()
	assert_gte(vocab.size(), 6, "the evaluator offers %d moment tags, too few to derive anything from" % vocab.size())
	for expected in ["ally_down", "last_standing", "enemy_last"]:
		assert_true(vocab.has(expected), "'%s' must still be a moment tag" % expected)


func test_the_mechanism_works_when_a_moment_line_exists() -> void:
	## CONTROL retained from the gap this file opened: with one line planted the picker sees the
	## moment, so a zero elsewhere means "nothing authored", never "mechanism broken".
	var entry: Dictionary = (_saved["rogue"] as Dictionary).duplicate(true)
	var tv: Dictionary = entry.get("trigger_voices", {})
	tv["low_hp"] = ["Generic.", {"line": "Get UP!", "when": "ally_down"}]
	entry["trigger_voices"] = tv
	PartyPersonas._data["rogue"] = entry
	var ctx := PartyCombatLineContext.new()
	ctx.speaker_name = "Vex"
	ctx.party = [{"name": "Vex", "job_id": "rogue", "hp_pct": 20.0, "is_alive": true},
		{"name": "Mira", "job_id": "cleric", "hp_pct": 0.0, "is_alive": false}]
	ctx.enemies = [{"name": "Slime", "hp_pct": 100.0}]
	assert_true(PartyPersonas.has_moment_line("rogue", "low_hp", ctx),
		"the moment mechanism does not fire even for a planted moment line — a real defect, not an authoring gap")


func test_every_starter_authors_a_moment_line() -> void:
	## The gap itself: the mechanism had no content at all. Derived rather than counted, so a job
	## losing its last moment line reds here instead of going quietly unreachable.
	var found: Array[String] = _authored_moment_lines()
	assert_gt(found.size(), 0, "no moment line is authored — has_moment_line cannot return true in a player's game")
	for job in JOBS:
		var mine: Array = found.filter(func(f): return str(f).begins_with("%s/" % job))
		assert_gt(mine.size(), 0, "%s authors no moment line, so the mechanism never fires for that character" % job)


func test_a_moment_that_holds_speaks_a_line_written_for_it() -> void:
	## SHIPPED corpus, no plant: with an ally down, every pick the Fighter makes is an ally_down line.
	var ctx := PartyCombatLineContext.new()
	ctx.speaker_name = "Brom"
	ctx.party = [{"name": "Brom", "job_id": "fighter", "hp_pct": 80.0, "is_alive": true},
		{"name": "Mira", "job_id": "cleric", "hp_pct": 0.0, "is_alive": false},
		{"name": "Zeph", "job_id": "mage", "hp_pct": 90.0, "is_alive": true}]
	ctx.enemies = [{"name": "Slime", "hp_pct": 100.0}, {"name": "Rat", "hp_pct": 100.0}]
	assert_true(PartyPersonas.has_moment_line("fighter", "turn_start", ctx),
		"an ally is down and the Fighter authors ally_down lines, so the moment must be live")
	var ally_down: Array = _fighter_lines_tagged("ally_down")
	assert_gt(ally_down.size(), 2, "under three ally_down lines means the same one repeats every turn the moment holds")
	for _i in 12:
		var picked: Dictionary = PartyPersonas.pick_trigger_voice("fighter", "turn_start", ctx)
		assert_true(str(picked.get("line", "")) in ally_down,
			"with an ally down the pick must be an ally_down line, got: %s" % [picked.get("line", "")])


func test_a_moment_line_stays_out_of_an_ordinary_turn() -> void:
	## The other half: a moment line must not leak into a turn where its moment is false, or the
	## Fighter mourns an ally standing beside him.
	var ctx := PartyCombatLineContext.new()
	ctx.speaker_name = "Brom"
	ctx.party = [{"name": "Brom", "job_id": "fighter", "hp_pct": 100.0, "is_alive": true},
		{"name": "Mira", "job_id": "cleric", "hp_pct": 100.0, "is_alive": true},
		{"name": "Zeph", "job_id": "mage", "hp_pct": 100.0, "is_alive": true}]
	ctx.enemies = [{"name": "Slime", "hp_pct": 100.0}, {"name": "Rat", "hp_pct": 100.0}]
	assert_false(PartyPersonas.has_moment_line("fighter", "turn_start", ctx),
		"nobody is down, nobody is alone and both foes are whole, so no moment may be live")
	var moments: Array = _fighter_moment_lines()
	assert_gt(moments.size(), 0, "CONTROL: the Fighter must author moment lines for this arm to mean anything")
	for _i in 20:
		var picked: Dictionary = PartyPersonas.pick_trigger_voice("fighter", "turn_start", ctx)
		assert_false(str(picked.get("line", "")) in moments,
			"a moment line played on an ordinary turn: %s" % [picked.get("line", "")])


# ── END TO END: the shipped line against a ready pooled one, through BattleManager ───────────────

func test_an_authored_moment_line_beats_a_ready_pooled_line() -> void:
	if SoundManager.wav_commit_refused():
		pending("mixer latched: the pooled line cannot be made ready, so there is nothing to outrank")
		return
	assert_false(LLMService.is_available(), "CONTROL: the model must stay out of this comparison")
	assert_true(VoicePool.store.has_line("fighter", "turn_start"), "CONTROL: the pool holds a ready line to lose")
	var ally_down: Array = _fighter_lines_tagged("ally_down")
	assert_gt(ally_down.size(), 0, "CONTROL: the Fighter must author an ally_down line")
	await _ask(true)
	assert_eq(_pool_keys(), 0, "the pool spoke over a line written for this moment; keys were %s" % [_keys])
	assert_true(_heard.any(func(l): return str(l) in ally_down),
		"an ally fell and the Fighter said none of his authored ally_down lines: %s" % [_heard])
	assert_true(VoicePool.store.has_line("fighter", "turn_start"), "the pooled line was spent though a moment line won")


func test_control_an_ordinary_turn_still_spends_the_pooled_line() -> void:
	## Without this the arm above would pass on a pool that was never ready — and the shipped moment
	## lines would be beating nothing at all.
	if SoundManager.wav_commit_refused():
		pending("mixer latched: the pooled line cannot be made ready")
		return
	await _ask(false)
	assert_eq(_pool_keys(), 1, "the ready pooled line did not speak on an ordinary turn; keys were %s" % [_keys])
	assert_true(_heard.has(POOLED), "CONTROL: the pooled line is what an ordinary turn speaks: %s" % [_heard])
	assert_false(VoicePool.store.has_line("fighter", "turn_start"), "the spoken line stayed in the pool")
	var moments: Array = _fighter_moment_lines()
	assert_false(_heard.any(func(l): return str(l) in moments), "a moment line reached an ordinary turn: %s" % [_heard])
