extends GutTest

## `status_cured.ogg` was composed and NOTHING played it, which @cowir-story found while measuring
## @cowir-music's orphan-cue pair. The cause is a NAME MISMATCH, not a missing arm: the cue is keyed
## `cured` while the ability effect is named `cleanse`, so no `status_<effect>` lookup can reach it —
## and BattleScene's arm listed `cleanse` among the buffs, so a cure sounded like a stat buff.
## The item path was already covered (`_ITEM_EFFECT_SFX` maps `cure_status`/`cure_all_status` ->
## `status_cured`, and BattleScene calls play_item for an item action), so ABILITIES were the gap.
##
## Three properties, and each is a thing a naive wiring gets wrong:
##   ONCE PER ACTION    four ailments off two allies is ONE cure. A per-status cue fires four times,
##                      the 80 ms cooldown swallows three, and an archived log reads "1" either way —
##                      only `_sfx_suppressed_by_cooldown` can tell them apart, which is why that
##                      flag is the oracle here rather than a play count.
##   ONLY WHEN IT CURES a cast on an ally with no ailments must not sound like a cure. The executor
##                      is the only place that knows, which is why the cue lives there and not in
##                      BattleScene's effect dispatch.
##   NOT ON EXPIRY      a status timing out, or a buff ending, is not a cure and must stay silent.
##
## ⚠️ The publish trace is BLIND to all of this: @cowir-deploy measured three traced publishes and
## the render smoke never removes a status at all (0 events in .662/.663/.664), so a zero there would
## report that the smoke never went here. That is why the proof is in this file.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const CUE := "status_cured"
const SOUND_MANAGER_PATH := "res://src/audio/SoundManager.gd"

var _bm = null


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)
	_reset_audio()


func after_each() -> void:
	_reset_audio()


func _reset_audio() -> void:
	SoundManager._sfx_cooldowns.erase(CUE)
	SoundManager._sfx_cooldowns.erase("buff")
	SoundManager._sfx_suppressed_by_cooldown = false
	SoundManager._cue_log_counts.clear()


func _ally(name_: String) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = name_
	c.max_hp = 100
	c.current_hp = 100
	c.max_mp = 50
	c.current_mp = 50
	c.speed = 10
	c.is_alive = true
	return c


## The real executor, through the real ability dictionary — not a hand-made {effect: "cleanse"},
## so a rename of the effect string reds this instead of passing against a fiction.
func _cleanse(targets: Array) -> void:
	var ability: Dictionary = JobSystem.get_ability("esuna")
	assert_false(ability.is_empty(), "VOID: the esuna ability is gone, so nothing below drives a cure")
	assert_eq(str(ability.get("effect", "")), "cleanse",
		"VOID: esuna's effect is no longer 'cleanse' — re-point this guard rather than deleting it")
	_bm._execute_support_ability(_ally("Healer"), ability, targets)


func test_a_cure_that_removes_two_ailments_sounds_exactly_once() -> void:
	var t := _ally("Patient")
	t.add_status("poison", 3)
	t.add_status("blind", 3)
	assert_eq(t.status_effects.size(), 2, "VOID: the fixture did not land two ailments")
	_cleanse([t])
	assert_eq(t.status_effects.size(), 0, "the cure must actually remove both ailments")
	## PLAYED: the cooldown map records the key only when a cue reaches the player.
	assert_true(SoundManager._sfx_cooldowns.has(CUE),
		"a cure that removed two ailments played no %s at all — the cue is authored and the event is live" % CUE)
	## ONCE: read immediately, because any later cue overwrites this flag. A second play inside the
	## 80 ms window would be suppressed and set it.
	assert_false(SoundManager._sfx_suppressed_by_cooldown,
		"%s was played more than once for ONE cure action — four ailments off two allies is one cure, and the per-key cooldown would hide the repeats from the log" % CUE)


func test_a_cure_with_nothing_to_cure_does_not_sound_like_one() -> void:
	## The log already says "has no ailments to cleanse"; the audio must agree. This is the arm that
	## makes the cue live in the executor rather than in BattleScene's dispatch, which cannot know.
	var t := _ally("Healthy")
	assert_eq(t.status_effects.size(), 0, "VOID: fixture should start clean")
	_cleanse([t])
	assert_false(SoundManager._sfx_cooldowns.has(CUE),
		"%s played for a cure that cured nothing, so the cue stops meaning 'an ailment came off'" % CUE)
	## And the cast is still audible — silence for a spent turn is a regression in feel, and the
	## generic buff cue is what shipped before this change.
	assert_true(SoundManager._sfx_cooldowns.has("buff"),
		"a no-op cure now plays nothing at all; the player spent a turn and heard silence")


func test_a_status_expiring_is_not_a_cure() -> void:
	## The loud direction of the whole feature: `remove_status` fires on natural expiry several times
	## a round, so cueing IT rather than the cure action would make this the noisiest sound in the
	## game. Driving expiry directly proves the cue is not attached to the removal event.
	var t := _ally("Poisoned")
	t.add_status("poison", 1)
	_reset_audio()
	t.remove_status("poison")
	assert_eq(t.status_effects.size(), 0, "VOID: the status did not come off, so this arm proves nothing")
	assert_false(SoundManager._sfx_cooldowns.has(CUE),
		"%s played on a bare remove_status — it is cued by the CURE ACTION, not by the removal event, or every expiring poison tick sounds like a cure" % CUE)


func test_a_buff_ending_is_not_a_cure() -> void:
	## ESUNA_AILMENTS is an inclusion list on purpose; a cure must not strip regen and must not
	## announce one. Both halves measured here because the cue and the removal share a code path.
	var t := _ally("Blessed")
	t.add_status("regen", 3)
	t.add_status("poison", 3)
	_cleanse([t])
	assert_true(t.has_status("regen"), "a cure stripped a BUFF — ESUNA_AILMENTS is an inclusion list")
	assert_true(SoundManager._sfx_cooldowns.has(CUE), "CONTROL: the poison did come off, so the cue should have played")


func test_the_cue_is_authored_and_on_disk() -> void:
	## Without this the arms above pass if someone deletes the asset instead of fixing the wiring:
	## play_status falls back to the generic descending blip, which is struktured's ruling-15
	## "not even close to good", and every assertion here still holds.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	assert_true(parsed is Dictionary, "VOID: manifest did not parse")
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {})
	assert_true(sfx.has(CUE), "%s is no longer authored; it was the point of this wiring" % CUE)
	var f: String = str((sfx.get(CUE, {}) as Dictionary).get("file", ""))
	var res: String = f if f.begins_with("res://") else "res://" + f
	assert_true(FileAccess.file_exists(res), "%s is authored as %s but the file is not there" % [CUE, f])


## WHICH CURE PATHS ARE COVERED, as an arm rather than a claim in a commit message. The ITEM path
## was already wired before this change — `_ITEM_EFFECT_SFX` maps cure_status/cure_all_status to
## status_cured and BattleScene calls play_item for an item action — so @cowir-story's "nothing plays
## it" held only for abilities. If an item's cue mapping ever breaks, that is a different defect from
## the ability wiring above and this names it separately.
## ⛔ DERIVED, NOT LISTED. This drove a hand-written ["antidote","echo_herbs","remedy",
## "eye_drops","gold_needle"] until 2026-10-14. Measured then: items.json holds 172 items, exactly
## 5 carry a cure effect, and the five listed were exactly those — so it was the COMPLETE population
## and there was no live gap. That is the trap: a hardcoded list that happens to be complete goes
## stale SILENTLY the day a sixth curative item is authored, and nothing reds. SoundManager's own
## derivation says why it should not be a list: "so a new consumable is covered on the day it is
## authored rather than when someone notices it is silent."
##
## 🔑 AND IT MIRRORS THE CONSUMER'S PRIORITY, which a naive "has cure_status" predicate would get
## wrong. `_ITEM_EFFECT_SFX` is an ORDERED first-match-wins list and `revive`, `escape_battle` and
## `repel_steps` all outrank the cure pair, so an item with BOTH revive and cure_status maps to
## ability_revive and must NOT be expected here. No such item exists today (measured: 0 of the 5 are
## shadowed), which is exactly why the naive form would have looked correct forever and then accused
## a correctly-mapped item the day one was authored.
func _items_the_consumer_maps_to_the_cure() -> Array[String]:
	var out: Array[String] = []
	var sm: Variant = load(SOUND_MANAGER_PATH)
	if sm == null:
		return out
	var consts: Dictionary = (sm as Script).get_script_constant_map()
	var table: Array = consts.get("_ITEM_EFFECT_SFX", [])
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	if not (parsed is Dictionary) or table.is_empty():
		return out
	var items: Variant = (parsed as Dictionary).get("items", parsed)
	if not (items is Dictionary):
		return out
	for iid in (items as Dictionary).keys():
		var entry: Variant = (items as Dictionary)[iid]
		if not (entry is Dictionary):
			continue
		var effects: Variant = (entry as Dictionary).get("effects", {})
		if not (effects is Dictionary):
			continue
		## First match wins, exactly as _derive_item_sounds_from_data walks it.
		for pair in table:
			if not (effects as Dictionary).has(pair[0]):
				continue
			if str(pair[1]) == CUE:
				out.append(str(iid))
			break
	out.sort()
	return out


func test_the_item_cure_path_is_cued_too() -> void:
	var expected: Array[String] = _items_the_consumer_maps_to_the_cure()
	assert_gt(expected.size(), 3,
		"VOID: derived only %d items that should map to %s — the derivation broke, and a short list here would pass by measuring almost nothing: %s" % [expected.size(), CUE, [expected]])
	var missing: Array[String] = []
	for id in expected:
		if str(SoundManager._item_sounds.get(id, "")) != CUE:
			missing.append("%s -> %s" % [id, str(SoundManager._item_sounds.get(id, "<none>"))])
	assert_eq(missing, [],
		"these curing items no longer map to %s, so the item cure path went silent while the ability path above stayed green: %s" % [CUE, [missing]])
	## The derivation must not be vacuously wide either: an item that cures nothing must not map here.
	assert_ne(str(SoundManager._item_sounds.get("potion", "")), CUE,
		"a plain healing potion maps to %s, so the cue no longer means 'an ailment came off'" % CUE)


## THE SIBLING THE FIRST FIX LEFT BEHIND. The `cleanse` executor above was the ability path; the
## Limit Break cleanses too (`_limit_break_cleanse`, the hidden half of what 4x AP buys) and played
## nothing, so the one mechanic a player cannot see had no cue either. Two existing guards are NAMED
## for this emit — `test_limit_break_cleanse_emit_preserved` and
## `test_limit_break_cleanse_per_participant_log_preserved` — and both assert only that the literal
## string is present in the source, so the emit's POLARITY was never pinned by either: it fired for
## every alive participant, and a healthy party of five read five "is cleansed by the Limit Break!"
## lines on a Limit Break that cured nobody. Those two stay green; they pin spelling, not behaviour.
##
## `play_flourish("group_limit_break")` already covers the ACTION, so the cue added here is not
## about audibility of the attack — it means the same thing it means on the ability path: an ailment
## came off. Which is why it must not fire when none did.
func test_the_limit_break_cleanse_floor() -> void:
	## Own arm on purpose: the two arms below touch _limit_break_cleanse AFTER their fixture
	## preconditions, so a rename would abort them with an assert already passed — green, silent.
	## This arm names the symbol instead, and reds with it.
	assert_true(_bm.has_method("_limit_break_cleanse"),
		"BattleManager no longer has _limit_break_cleanse — re-point the two arms below rather than deleting them")
	assert_true(SoundManager.has_method("play_status"),
		"SoundManager.play_status is gone, so the cue the arms below assert cannot be played by anything")


func test_the_limit_break_cue_fires_once_and_names_only_who_was_cured() -> void:
	## TWO ailing allies on purpose: with one, a cue moved INSIDE the participant loop still plays
	## exactly once and this arm cannot tell the difference. Two make the second play land inside the
	## 80 ms window, where only the suppression flag sees it.
	var ailing := _ally("Poisoned")
	var also := _ally("Cursed")
	var healthy := _ally("Unafflicted")
	ailing.add_status("poison", 3)
	ailing.add_status("blind", 3)
	also.add_status("curse", 3)
	assert_eq(ailing.status_effects.size(), 2, "VOID: the fixture did not land two ailments")
	assert_eq(also.status_effects.size(), 1, "VOID: the second ally is not ailing, so the once-per-action claim is untested")
	var lines: Array[String] = []
	_bm.battle_log_message.connect(func(m: String) -> void: lines.append(m))
	_reset_audio()
	_bm._limit_break_cleanse([ailing, also, healthy])
	assert_eq(ailing.status_effects.size(), 0, "the Limit Break must actually remove the ailments")
	assert_eq(also.status_effects.size(), 0, "the Limit Break cleansed the first ally but not the second")
	assert_true(SoundManager._sfx_cooldowns.has(CUE),
		"a Limit Break that cleansed two ailments played no %s — the ability path cues this and the Limit Break is the same event" % CUE)
	assert_false(SoundManager._sfx_suppressed_by_cooldown,
		"%s played more than once for ONE Limit Break; two ailments off one ally is one cure, and the 80 ms cooldown would hide the repeat" % CUE)
	var cleanse_lines: Array[String] = []
	for l in lines:
		if l.contains("is cleansed by the Limit Break"):
			cleanse_lines.append(l)
	assert_eq(cleanse_lines.size(), 2,
		"the cleanse announced %d party members when TWO of three were ailing — a healthy member is told 'is cleansed' about nothing: %s" % [cleanse_lines.size(), cleanse_lines])
	var announced := ", ".join(cleanse_lines)
	## A distinctive fixture name on purpose: "Fine" was the original and it is a substring of
	## "Finer", which occurs in src. Zero live exposure, and a better discriminator for free.
	assert_false(announced.contains("Unafflicted"),
		"the healthy ally was announced as cleansed: %s" % announced)
	assert_true(announced.contains("Poisoned") and announced.contains("Cursed"),
		"the cleanse lines do not name both allies who were actually cured: %s" % announced)


func test_a_limit_break_that_cured_nobody_is_silent_and_says_nothing() -> void:
	## A buff is the right negative: it will never be added to the cleansable list, so this arm
	## cannot red on a correct widening of that list the way naming a specific ailment would.
	var p := _ally("Blessed")
	p.add_status("regen", 3)
	var lines: Array[String] = []
	_bm.battle_log_message.connect(func(m: String) -> void: lines.append(m))
	_reset_audio()
	_bm._limit_break_cleanse([p])
	assert_true(p.has_status("regen"), "the Limit Break stripped a BUFF — the cleansable list is an inclusion list")
	assert_false(SoundManager._sfx_cooldowns.has(CUE),
		"%s played for a Limit Break that cured nothing, so the cue stops meaning 'an ailment came off'" % CUE)
	var cleanse_lines: Array[String] = []
	for l in lines:
		if l.contains("is cleansed by the Limit Break"):
			cleanse_lines.append(l)
	assert_eq(cleanse_lines, [],
		"the log announced a cleanse for a party member who had nothing to cleanse: %s" % [cleanse_lines])
