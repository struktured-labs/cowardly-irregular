extends GutTest

## cowir-music, measured: `status_exposed` and `status_cannot_defer` are authored cues with files on
## disk that had NEVER played. `_apply_vulnerability_window` applies both statuses after every group
## attack and contained zero SoundManager calls, and it is reached only from `_execute_group_action`,
## whose action carries `"type": "group"` — while BattleScene's status-cue dispatch (:4916) is gated
## on `action_type == "ability"`. So the cue could not arrive by the normal route and none was made.
##
## ⛔ THE SAME GATE IS ALREADY WORKED AROUND ELSEWHERE IN THIS FILE. BattleManager:5228 carries a
## cowir-sfx comment naming it and a direct `SoundManager.play_status(...)` beside it. This window
## was the sibling that fix did not reach — the fourth instance of that shape found today.
##
## ⚠️ THIS HEADER USED TO SAY "once per window" WAS NOT OBSERVABLE. THAT WAS FALSE, and leaving it
## would have been the same defect as the overclaiming canary I fixed an hour ago — a test header
## asserting something about coverage that is not true. cowir-music measured the discriminator:
## `SoundManager._sfx_suppressed_by_cooldown` is cleared at the top of every
## `_try_play_sfx_from_manifest` (:953) and set true ONLY at the cooldown gate (:963). So after the
## window, false means exactly one call reached each key; a per-participant implementation leaves it
## true. The STREAMS are identical either way, which is what made it look untestable — the flag is
## not. Two different keys are separate cooldown entries, so a two-cue window still reads false.

const MANIFEST := "res://data/sfx_manifest.json"
const BattleState := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

var _guard: RefCounted = null


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()
	var sm := get_node_or_null("/root/SoundManager")
	if sm and "_sfx_cooldowns" in sm:
		sm._sfx_cooldowns.clear()


func after_each() -> void:
	if _guard != null:
		_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _combatant(nm: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": nm, "max_hp": 30, "max_mp": 0,
		"attack": 5, "defense": 5, "magic": 5, "speed": 5})
	add_child_autofree(c)
	return c


## CONTROL, must pass on BOTH trees: the cues are authored. `play_status_if_authored` returns false
## for an unauthored key, so without this the arm below could pass for the wrong reason or fail for
## a reason that is not the defect.
func test_control_both_window_cues_are_authored() -> void:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	assert_not_null(f, "the sfx manifest must be readable")
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_true(parsed is Dictionary, "manifest parses")
	if not (parsed is Dictionary):
		return
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {})
	assert_true(sfx.has("status_exposed"), "status_exposed is authored — else the cue arm is vacuous")
	assert_true(sfx.has("status_cannot_defer"), "status_cannot_defer is authored")


## The defect: the window must be audible. Observed through SoundManager's own cooldown ledger,
## which records a key only when a cue actually plays.
func test_the_vulnerability_window_plays_its_authored_cues() -> void:
	var sm := get_node_or_null("/root/SoundManager")
	assert_not_null(sm, "CONTROL: SoundManager must be present, or this arm measures nothing")
	if sm == null or not ("_sfx_cooldowns" in sm):
		return
	sm._sfx_cooldowns.clear()
	BattleManager._apply_vulnerability_window([_combatant("Hero"), _combatant("Mira")])
	assert_true(sm._sfx_cooldowns.has("status_exposed"),
		"a group attack's exposure must be heard, not only written to the battle log")
	assert_true(sm._sfx_cooldowns.has("status_cannot_defer"),
		"both authored cues belong to this window; firing one and not the other is half a fix")


## CONTROL, must pass on BOTH trees: the mechanic still happens. A change that adds cues while
## breaking the statuses or the AP penalty would otherwise look like a success.
func test_control_the_window_still_exposes_and_costs_ap() -> void:
	var c := _combatant("Zack")
	c.current_ap = 3
	BattleManager._apply_vulnerability_window([c])
	assert_true(c.has_status("exposed"), "the window still applies exposed")
	assert_true(c.has_status("cannot_defer"), "and cannot_defer")
	assert_eq(c.current_ap, 1, "and still subtracts 2 AP (3 -> 1), the 2026-04-30 fix")


## A window with nobody in it must stay silent — the cue belongs to a real exposure, not to the call.
func test_an_empty_window_is_silent() -> void:
	var sm := get_node_or_null("/root/SoundManager")
	if sm == null or not ("_sfx_cooldowns" in sm):
		return
	sm._sfx_cooldowns.clear()
	BattleManager._apply_vulnerability_window([])
	assert_false(sm._sfx_cooldowns.has("status_exposed"),
		"no participant was exposed, so nothing should be heard")


## The "once" claim, now that it has an instrument. Three participants, one call per key.
func test_the_window_fires_once_not_once_per_participant() -> void:
	var sm := get_node_or_null("/root/SoundManager")
	assert_not_null(sm, "CONTROL: SoundManager must be present")
	if sm == null or not ("_sfx_suppressed_by_cooldown" in sm):
		fail_test("the suppression flag is the instrument for this arm; without it there is no measurement")
		return
	sm._sfx_cooldowns.clear()
	BattleManager._apply_vulnerability_window([_combatant("A"), _combatant("B"), _combatant("C")])
	assert_false(sm._sfx_suppressed_by_cooldown,
		"three participants must not mean three calls per key — the cue belongs to the window, not to each member")


## CONTROL, and the arm above is free without it: prove the flag CAN say yes. An instrument that is
## always false would pass the "once" assertion no matter how many times the window fired.
func test_control_the_suppression_flag_can_say_yes() -> void:
	var sm := get_node_or_null("/root/SoundManager")
	if sm == null or not ("_sfx_suppressed_by_cooldown" in sm):
		fail_test("no flag to control")
		return
	sm._sfx_cooldowns.clear()
	sm.play_status_if_authored("status_exposed")
	assert_false(sm._sfx_suppressed_by_cooldown, "the first call into a key plays and leaves the flag down")
	sm.play_status_if_authored("status_exposed")
	assert_true(sm._sfx_suppressed_by_cooldown,
		"an immediate repeat of the SAME key is suppressed — so the flag can say yes, and a false above means something")
