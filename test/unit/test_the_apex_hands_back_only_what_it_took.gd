extends GutTest

## `VertexApex` disables random encounters on entry — "Nothing random happens in this room." Its
## `_exit_tree` restored them by writing the literal `true`.
##
## ⛔ A RESTORE THAT WRITES A CONSTANT ANSWERS FOR A CALLER IT NEVER ASKED. The render smoke disables
## encounters at startup; walking out of the Apex handed them back mid-run, and from that point the
## run had live 5%-per-step encounters (cowir-deploy/cowir-main, 2026-09-18). `_exit_tree` has no
## knowledge of who disabled them, so it must not decide what they wanted.
##
## 📌 LATENT TODAY AND THE ARMS SAY SO RATHER THAN THE COMMIT ALONE. The smoke is currently the only
## other writer of `encounters_enabled`, so nothing in normal play disables them for this room to
## re-enable — and in the failing run the Apex was entered AFTER the bail it was blamed for. The
## third arm drives exactly the configuration that makes it live, so the day a cutscene or another
## smoke leg disables encounters, this file already describes what happens.
##
## ⚠️ THE FIX'S OTHER HALF POINTS THE OPPOSITE WAY TO THE BUG, which is why arm four exists: an
## ungated `_prev = encounters_enabled` capture would, on a second `_ready` with no intervening
## `_exit_tree`, store the ALREADY-FALSE value and disable encounters PERMANENTLY. Silent, and worse
## than the defect being fixed.

const APEX := preload("res://src/maps/dungeons/VertexApex.gd")

var _saved_encounters: bool = true


## ⛔ `encounters_enabled` IS A FIELD ON A SHARED AUTOLOAD AND EVERY ARM HERE WRITES IT. Restored in
## `after_each` rather than inline, so an abort mid-arm cannot strand the flag for the rest of the
## process — this lane's own banked rule, and the failure it prevents is the one this file is about.
func before_each() -> void:
	_saved_encounters = EncounterSystem.encounters_enabled


func after_each() -> void:
	EncounterSystem.encounters_enabled = _saved_encounters


func _enter_apex() -> Node:
	var sv := SubViewport.new()
	sv.size = Vector2i(640, 480)
	add_child_autofree(sv)
	var apex = APEX.new()
	sv.add_child(apex)
	await get_tree().process_frame
	return apex


func _leave(apex: Node) -> void:
	var parent := apex.get_parent()
	if parent:
		parent.remove_child(apex)
	apex.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## ⛔ THE CONTROL, and it comes first: if entering does not suppress encounters, every arm below is
## about a room that does nothing and the restore has nothing to answer for.
func test_entering_the_apex_suppresses_encounters() -> void:
	EncounterSystem.encounters_enabled = true
	var apex = await _enter_apex()
	assert_false(EncounterSystem.encounters_enabled,
		"CONTROL: the Apex must disable random encounters on entry — 'nothing random happens in this room'")
	assert_true(apex._suppressed_encounters, "CONTROL: …and it must record that it took them")


## Leaving a room that genuinely took them must hand them back, or the fix trades one bug for the
## opposite one and the player walks the rest of the game without encounters.
func test_leaving_hands_them_back_when_the_apex_took_them() -> void:
	EncounterSystem.encounters_enabled = true
	var apex = await _enter_apex()
	assert_false(EncounterSystem.encounters_enabled, "CONTROL: taken on entry")

	await _leave(apex)

	assert_true(EncounterSystem.encounters_enabled,
		"the Apex disabled encounters, so leaving must re-enable them — otherwise the player "
		+ "walks out of the last room of the game into a world with no random battles")


## ⛔ THE DEFECT. Enter with encounters ALREADY disabled by somebody else, leave, and they must
## still be disabled. This is the configuration the render smoke runs in, and the one the old
## `_exit_tree` broke by writing a literal.
func test_leaving_does_not_hand_back_what_it_never_took() -> void:
	EncounterSystem.encounters_enabled = false
	var apex = await _enter_apex()
	assert_false(apex._suppressed_encounters,
		"CONTROL: with encounters already off the Apex must NOT claim them")

	await _leave(apex)

	assert_false(EncounterSystem.encounters_enabled,
		"somebody else had disabled encounters and leaving the Apex switched them back on — "
		+ "`_exit_tree` wrote the literal `true` and answered for a caller it never asked. This is "
		+ "the render smoke's configuration exactly.")


## ⛔ THE OPPOSITE-DIRECTION HAZARD, AND NOTHING ELSE HERE CATCHES IT. A second `_ready` with no
## intervening `_exit_tree` — a re-enter, a rebuild — must not let the room lose track of what it
## took. An ungated capture would store the already-false value and disable encounters for good.
func test_a_second_entry_does_not_corrupt_what_is_owed() -> void:
	EncounterSystem.encounters_enabled = true
	var apex = await _enter_apex()
	assert_true(apex._suppressed_encounters, "CONTROL: claimed on the first entry")

	apex._ready()
	await get_tree().process_frame
	assert_false(EncounterSystem.encounters_enabled, "CONTROL: still suppressed after a second _ready")

	await _leave(apex)

	assert_true(EncounterSystem.encounters_enabled,
		"a second _ready ran with encounters already false; the room must still know it owes them "
		+ "back. A capture taken on every entry would have stored `false` and disabled encounters "
		+ "permanently — the same class of bug, pointing the other way.")


## ⚠️ THERE IS NO "DOES NOT STOMP A RE-ENABLE THAT HAPPENED INSIDE" ARM, AND THAT IS A MEASUREMENT.
## I wrote one, and the source clause it guarded — `and not EncounterSystem.encounters_enabled` —
## turned out to be unobservable: if somebody re-enabled them while the player was inside, they are
## already `true`, so the restore is a no-op either way. Mutating the clause away red NOTHING (5/5
## green). Clause deleted, arm deleted. An arm that cannot fail reads as cover.
##
## 📌 The four that remain are each reached by a mutation no other one reaches — including the
## second-entry arm, which ONLY fires when `_ready` clears the claim before re-checking.
