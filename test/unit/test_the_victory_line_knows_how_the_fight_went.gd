extends GutTest

## THE VICTORY MOMENT CARRIED NO INFORMATION ABOUT THE FIGHT. `_dispatch_victory_party_line` passed a
## literal `{}` as event_data, so every victory line was chosen from party/enemy state ALONE — which at
## victory is the FINAL frame. end_battle has already built `char_results` (levels gained, abilities
## learned, per character) by the time it dispatches the line, and none of it reached the speaker.
##
## struktured's ask (2026-10-28): quips that differ on how close a fight was, on a level-up, on learning
## an ability. Three of those were already computed for the victory screen and thrown away here.
##
## 🔑 WHAT IS GENUINELY NEW, versus what the existing tags already say. End-state closeness is ALREADY
## expressible: `ally_down` / `ally_low` / `last_standing` / `all_full` all read live party HP, and HP is
## not restored before the line fires. So this adds only the four facts no context could hold:
##   self_leveled · self_learned_ability · long_fight · one_shot_win
## A fifth tag for "nobody fell" would have duplicated `none_down`, and was not added.
##
## ⚠️ one_shot_win is only truthful from .738. Before that fold, a pooled group attack recorded no first
## damage, so `_one_shot_achieved` was false for the most canonical one-shot in the game.

const TAGS := preload("res://src/llm/VoiceLineTags.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")
const BM_PATH := "res://src/battle/BattleManager.gd"
const BM := preload("res://src/battle/BattleManager.gd")


func _ctx(data: Dictionary) -> PartyCombatLineContext:
	var c := PartyCombatLineContext.new()
	c.speaker_name = "Brom"
	c.event_kind = PartyCombatLineContext.EVENT_VICTORY
	c.party = [{"name": "Brom", "job_id": "fighter", "hp_pct": 100.0, "is_alive": true}]
	c.enemies = []
	c.event_data = data
	return c


func _row(who: String, leveled: bool, learned: Array) -> Dictionary:
	return {"name": who, "leveled_up": leveled, "learned_abilities": learned}


func test_the_low_water_mark_is_actually_recorded_by_the_engine() -> void:
	## ⛔ EVERY ARM ABOVE HANDS THE TAG A PAYLOAD I WROTE. None of them proves the engine ever FILLS
	## that payload — the tag could be perfect and `_battle_low_water_pct` never move. Driven on the
	## real autoload through the real signal, which is the only thing that answers it.
	var guard = BattleStateGuard.new()
	guard.snapshot()
	var pc := Combatant.new()
	autofree(pc)
	pc.combatant_name = "Brom"
	pc.is_alive = true
	pc.max_hp = 100
	pc.current_hp = 100
	BattleManager.player_party.assign([pc])
	BattleManager._battle_low_water_pct = 100.0
	## The dip and the recovery, exactly the history a final-frame read cannot see.
	BattleManager._on_hp_changed_for_low_water(100, 7, pc)
	BattleManager._on_hp_changed_for_low_water(7, 92, pc)
	var low: float = BattleManager._battle_low_water_pct
	guard.restore()
	assert_almost_eq(low, 7.0, 0.01,
		"the engine must keep the WORST value reached (7%%), not the latest one (92%%)")


func test_the_low_water_sampler_is_wired_and_unwired() -> void:
	## ⛔ THE ARM ABOVE CALLS THE HANDLER DIRECTLY, so it passes whether or not anything ever invokes it.
	## Both halves are needed: without the connect the feature is dead with every other arm green, and
	## without the disconnect each battle leaves a listener on a combatant it no longer owns — the leak
	## _died_callbacks exists to prevent, which is why it is cached as a bound Callable the same way.
	var code: String = GdSource.code_of(BM_PATH)
	assert_gt(code.length(), 10000, "CONTROL: BattleManager was actually read")
	assert_true(code.contains("combatant.hp_changed.connect(hcb)"),
		"nothing connects the low-water sampler, so _battle_low_water_pct never moves and won_barely can never hold")
	assert_true(code.contains("combatant.hp_changed.disconnect(hcb)"),
		"the sampler is connected and never disconnected — every battle leaks a listener onto its combatants")
	assert_true(code.contains("_hp_callbacks.clear()"),
		"the bound-Callable cache must be cleared with the others, or it holds freed combatants")
	assert_true(code.contains("_battle_low_water_pct = 100.0"),
		"the mark must reset per battle, or one close call makes every later victory read as a close call")


func test_an_enemys_hp_does_not_count_as_the_partys_low_water() -> void:
	var guard = BattleStateGuard.new()
	guard.snapshot()
	var foe := Combatant.new()
	autofree(foe)
	foe.combatant_name = "Slime"
	foe.is_alive = true
	foe.max_hp = 100
	BattleManager.player_party.assign([])
	BattleManager._battle_low_water_pct = 100.0
	BattleManager._on_hp_changed_for_low_water(100, 1, foe)
	var low: float = BattleManager._battle_low_water_pct
	guard.restore()
	assert_almost_eq(low, 100.0, 0.01,
		"a monster at 1%% is the party WINNING; counting it would make every victory a close call")


func test_the_payload_reads_the_speakers_own_row() -> void:
	## A line says "I levelled", so the flags must be the SPEAKER's. Reading the first row instead — the
	## easy mistake — puts Mira's level-up in Brom's mouth, and the party screen would still look right.
	var rows: Array = [_row("Mira", true, ["cure"]), _row("Brom", false, [])]
	var p: Dictionary = BM.victory_line_payload("Brom", rows, 3, false)
	assert_false(bool(p[PartyCombatLineContext.VICTORY_SELF_LEVELED]),
		"Brom did not level; Mira did, and she is the first row")
	assert_false(bool(p[PartyCombatLineContext.VICTORY_SELF_LEARNED]),
		"Brom learned nothing; the ability belongs to Mira's row")
	var q: Dictionary = BM.victory_line_payload("Mira", rows, 3, false)
	assert_true(bool(q[PartyCombatLineContext.VICTORY_SELF_LEVELED]),
		"CONTROL: Mira's own row must still report her level-up, or the arm above passes for the wrong reason")
	assert_true(bool(q[PartyCombatLineContext.VICTORY_SELF_LEARNED]), "CONTROL: Mira learned cure")


func test_a_speaker_with_no_row_claims_nothing() -> void:
	## The deferred-payout and solo-duel paths can dispatch a line for someone absent from char_results.
	## A default that claimed a level-up would have the speaker celebrate one they never got.
	var p: Dictionary = BM.victory_line_payload("Nobody", [_row("Brom", true, ["cleave"])], 2, false)
	assert_false(bool(p[PartyCombatLineContext.VICTORY_SELF_LEVELED]), "an absent speaker levelled nothing")
	assert_false(bool(p[PartyCombatLineContext.VICTORY_SELF_LEARNED]), "an absent speaker learned nothing")
	assert_eq(int(p[PartyCombatLineContext.VICTORY_ROUNDS]), 2, "the fight's own facts still travel")


func test_a_malformed_row_cannot_abort_the_payload() -> void:
	## char_results is built in a loop over live combatants; a null or non-Dictionary entry must not take
	## the victory line down with it, because an abort here loses the whole line rather than one flag.
	var p: Dictionary = BM.victory_line_payload("Brom", [null, 7, _row("Brom", true, [])], 4, true)
	assert_true(bool(p[PartyCombatLineContext.VICTORY_SELF_LEVELED]),
		"the real row sits behind two malformed ones and must still be found")
	assert_true(bool(p[PartyCombatLineContext.VICTORY_ONE_SHOT]), "the one-shot flag is passed, not derived")


func test_each_outcome_tag_holds_only_on_its_own_payload() -> void:
	var cases: Dictionary = {
		"self_leveled": {PartyCombatLineContext.VICTORY_SELF_LEVELED: true},
		"self_learned_ability": {PartyCombatLineContext.VICTORY_SELF_LEARNED: true},
		"long_fight": {PartyCombatLineContext.VICTORY_ROUNDS: TAGS.LONG_FIGHT_ROUNDS},
		"one_shot_win": {PartyCombatLineContext.VICTORY_ONE_SHOT: true},
	}
	for tag in cases:
		assert_true(TAGS.tag_holds(str(tag), _ctx(cases[tag])),
			"%s must hold on the payload written for it" % tag)
		for other in cases:
			if str(other) == str(tag):
				continue
			assert_false(TAGS.tag_holds(str(tag), _ctx(cases[other])),
				"%s held on %s's payload — the arms are reading the wrong key" % [tag, other])


func test_an_outcome_tag_cannot_hold_without_a_payload() -> void:
	## ⛔ THE ISOLATION ARM. Every non-victory event sends `{}`, so a line tagged for a level-up must be
	## unspeakable on turn_start. Without this, an outcome tag would be a moment tag that holds ALWAYS and
	## outranks every generic line in the pool — the loudest possible regression, and silent in the data.
	for tag in ["self_leveled", "self_learned_ability", "long_fight", "one_shot_win", "won_barely", "someone_fell"]:
		assert_false(TAGS.tag_holds(str(tag), _ctx({})),
			"%s holds with no event_data, so it would fire on every ambient line" % tag)


func test_long_fight_is_a_boundary_not_a_coincidence() -> void:
	## Assert the RELATIONSHIP to the threshold, not the number: raising LONG_FIGHT_ROUNDS is a correct
	## change and must not red, while an off-by-one in the comparison must.
	var n: int = TAGS.LONG_FIGHT_ROUNDS
	assert_gt(n, 1, "CONTROL: a threshold of 1 or less would make the arm below vacuous")
	assert_false(TAGS.tag_holds("long_fight", _ctx({PartyCombatLineContext.VICTORY_ROUNDS: n - 1})),
		"one round short of the threshold is not a long fight")
	assert_true(TAGS.tag_holds("long_fight", _ctx({PartyCombatLineContext.VICTORY_ROUNDS: n})),
		"the threshold itself counts as a long fight")


func test_a_dip_that_was_healed_back_is_invisible_to_every_final_frame_tag() -> void:
	## ⛔ THE ARM THAT JUSTIFIES TRACKING AT ALL. A party that fell to 4% and was healed to 90% had the
	## closest fight of the night, and ally_low / ally_down / last_standing / all_full ALL read false,
	## because every one of them reads the party as it stands when the line fires. Without the recorded
	## low-water mark the game has no way to know it happened, so "that was close" could never be said
	## at the only moment it is true.
	var healthy_now: Array = [
		{"name": "Brom", "job_id": "fighter", "hp_pct": 90.0, "is_alive": true},
		{"name": "Mira", "job_id": "cleric", "hp_pct": 95.0, "is_alive": true},
	]
	var c := PartyCombatLineContext.new()
	c.speaker_name = "Brom"
	c.event_kind = PartyCombatLineContext.EVENT_VICTORY
	c.party = healthy_now
	c.enemies = []
	c.event_data = {PartyCombatLineContext.VICTORY_LOW_WATER: 4.0}
	for blind in ["ally_low", "ally_down", "last_standing", "all_full"]:
		assert_false(TAGS.tag_holds(blind, c),
			"CONTROL: %s reads the final frame and must be false here — if it holds, this fixture does not demonstrate the gap" % blind)
	assert_true(TAGS.tag_holds("won_barely", c),
		"the party reached 4%% and nothing else in the system can say so")


func test_a_full_health_finish_is_not_a_close_call() -> void:
	assert_false(TAGS.tag_holds("won_barely", _ctx({PartyCombatLineContext.VICTORY_LOW_WATER: 100.0})),
		"an untouched party did not barely win")
	assert_false(TAGS.tag_holds("won_barely", _ctx({})),
		"a payload with no low-water key must default safe, not claim a close call")


func test_won_barely_is_a_boundary_not_a_pinned_number() -> void:
	var t: float = TAGS.CLOSE_CALL_PCT
	assert_gt(t, 1.0, "CONTROL: a threshold at or below 1%% would make the arm below vacuous")
	assert_true(TAGS.tag_holds("won_barely", _ctx({PartyCombatLineContext.VICTORY_LOW_WATER: t - 1.0})),
		"below the threshold is a close call")
	assert_false(TAGS.tag_holds("won_barely", _ctx({PartyCombatLineContext.VICTORY_LOW_WATER: t})),
		"the threshold itself is not yet a close call, and raising CLOSE_CALL_PCT must not red this")


func test_someone_fell_survives_a_revival_where_ally_down_does_not() -> void:
	## A member who fell and was raised leaves `ally_down` false at victory. _ko_this_battle already
	## recorded the KO, and routing it is what lets the quip acknowledge a death the party undid.
	var raised: Array = [
		{"name": "Brom", "job_id": "fighter", "hp_pct": 70.0, "is_alive": true},
		{"name": "Mira", "job_id": "cleric", "hp_pct": 30.0, "is_alive": true},
	]
	var c := PartyCombatLineContext.new()
	c.speaker_name = "Brom"
	c.event_kind = PartyCombatLineContext.EVENT_VICTORY
	c.party = raised
	c.enemies = []
	c.event_data = {PartyCombatLineContext.VICTORY_ANYONE_FELL: true}
	assert_false(TAGS.tag_holds("ally_down", c), "CONTROL: everyone is standing again, so ally_down is false")
	assert_true(TAGS.tag_holds("someone_fell", c), "the fight still cost somebody their feet")


func test_the_payload_carries_the_fights_shape_not_just_the_speakers() -> void:
	var p: Dictionary = BM.victory_line_payload("Brom", [_row("Brom", false, [])], 5, false, 11.5, true)
	assert_almost_eq(float(p[PartyCombatLineContext.VICTORY_LOW_WATER]), 11.5, 0.01, "the low-water mark travels")
	assert_true(bool(p[PartyCombatLineContext.VICTORY_ANYONE_FELL]), "the KO record travels")
	var q: Dictionary = BM.victory_line_payload("Brom", [_row("Brom", false, [])], 5, false)
	assert_almost_eq(float(q[PartyCombatLineContext.VICTORY_LOW_WATER]), 100.0, 0.01,
		"the default must be a clean fight, so an un-updated caller cannot invent a close call")
	assert_false(bool(q[PartyCombatLineContext.VICTORY_ANYONE_FELL]), "and cannot invent a casualty")


func test_the_outcome_tags_are_known_and_rank_as_moments() -> void:
	## is_moment_tag is what makes a written line WIN its moment instead of sitting in the generic pool.
	for tag in ["self_leveled", "self_learned_ability", "long_fight", "one_shot_win", "won_barely", "someone_fell"]:
		assert_true(TAGS.is_known_tag(str(tag)), "%s must be known or every line carrying it is mute" % tag)
		assert_true(TAGS.is_moment_tag(str(tag)),
			"%s must outrank generic victory lines, or a level-up quip loses to 'Clean. Next.'" % tag)


func test_the_producer_still_spells_the_keys_this_payload_reads() -> void:
	## ⚠️ THIS CERTIFIES SPELLING, WHICH IS EXACTLY WHAT THIS JOIN IS. victory_line_payload reads
	## char_results rows by string key; end_battle writes them as string literals. Nothing types the two
	## together, so renaming either side mutes every outcome line with no error anywhere. Hand-building
	## rows in the arms above cannot catch it — a fixture only ever agrees with the author.
	var code: String = GdSource.code_of(BM_PATH)
	assert_gt(code.length(), 10000, "CONTROL: BattleManager was actually read, so a 0 below means absent")
	var i: int = code.find("char_results.append(")
	assert_gt(i, -1, "CONTROL: the char_results producer must be found, or this arm proves nothing")
	var block: String = code.substr(i, 900)
	assert_true(block.contains("\"leveled_up\""),
		"end_battle no longer writes \"leveled_up\" into char_results — victory_line_payload reads that key and now always reports false")
	assert_true(block.contains("\"learned_abilities\""),
		"end_battle no longer writes \"learned_abilities\" into char_results — every self_learned_ability line just went mute")
	assert_true(block.contains("\"name\""),
		"the payload finds the speaker's row by \"name\"; without it no row can ever match")


func test_the_dispatch_actually_sends_a_payload() -> void:
	## The producer and the predicates can both be right while the call site still passes `{}` — which is
	## what shipped until now. Read the dispatch rather than the helper.
	var code: String = GdSource.code_of(BM_PATH)
	var i: int = code.find("func _dispatch_victory_party_line")
	assert_gt(i, -1, "CONTROL: the dispatch function must be found")
	var body: String = code.substr(i, 1200)
	assert_true(body.contains("victory_line_payload("),
		"_dispatch_victory_party_line is back to sending a literal {} — the four outcome tags can never hold")
