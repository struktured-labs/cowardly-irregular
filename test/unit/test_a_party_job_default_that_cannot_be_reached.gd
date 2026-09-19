extends GutTest

## `"adventurer"` was unreachable, and the prompt rendered "Kai the , unhurt".
##
## The party row was built as:
##
##     entry.get("job_id", entry.get("job", "adventurer"))
##
## which reads as a three-level fallback and is a two-level one, because
## `Combatant.to_dict` writes `data["job"] = data.get("job_id", "")` UNCONDITIONALLY:
##
##     job assigned      -> {job_id: "fighter", job: "fighter"}   primary wins
##     job NEVER assigned -> {job: ""}  and NO job_id             ⬅ middle key PRESENT but EMPTY
##
## So the chain returns "" and the final default cannot fire. `DialoguePrompts.
## _format_party_state` then renders `"  - %s the %s, %s"` as `"  - Kai the , unhurt"` —
## a malformed line in the prompt the model reads.
##
## ⛔ HOW IT WAS FOUND, because the instrument error is the transferable part: I published
## "no era ever wrote `job`" off `git log -S '"job":'`. The writer is an INDEXED assignment
## (`data["job"] = …`), which no dict-literal pattern can match — cowir-adhoc read his actual
## saves and found 30 of 30 party members carrying `job`. My control had certified the test
## on `"job_id"`, a DICT LITERAL, so it proved the shape I planted and not the claim I
## attached it to.

const DC := preload("res://src/llm/DynamicConversation.gd")


func test_an_entry_with_no_job_id_does_not_yield_an_empty_job() -> void:
	## THE DEFECT. This is exactly what to_dict emits for a jobless Combatant.
	var entry: Dictionary = {"name": "Kai", "job": ""}
	assert_eq(DC._party_job(entry), "adventurer",
		("an entry carrying an EMPTY job and no job_id must fall through to the default. "
		+ "to_dict writes job unconditionally, so the middle key is always present and a "
		+ "plain nested get() can never reach it."))


func test_a_whitespace_job_is_also_absent() -> void:
	## Same class, one layer out — a value that is present, non-empty, and still not a job.
	assert_eq(DC._party_job({"name": "Kai", "job": "   "}), "adventurer",
		"a whitespace-only job rendered as a blank in the prompt row")


func test_job_id_still_wins_when_it_is_real() -> void:
	## FLOOR. The fix must not change the ordinary path: job_id is the stable key and the one
	## every current save carries.
	assert_eq(DC._party_job({"job_id": "fighter", "job": "fighter"}), "fighter",
		"job_id stopped being preferred")


func test_job_is_used_when_job_id_is_missing_but_real() -> void:
	## The fallback still EXISTS — this arm is why the fix is "empty means absent" rather than
	## "drop the second key". cowir-adhoc measured 30 of 30 real party members carrying `job`.
	assert_eq(DC._party_job({"job": "cleric"}), "cleric",
		"a real job value was discarded — the fallback must still work, just not when empty")


func test_an_empty_job_id_falls_through_to_a_real_job() -> void:
	## Both keys present, primary empty. The old chain returned "" here too, for the same
	## reason one layer up.
	assert_eq(DC._party_job({"job_id": "", "job": "rogue"}), "rogue",
		"an empty job_id shadowed a real job")


func test_an_entry_with_neither_key_gets_the_default() -> void:
	assert_eq(DC._party_job({"name": "Kai"}), "adventurer",
		"an entry with no job keys at all must still name something")


# ── control: the shape the defect actually came from ─────────────────────────

func test_to_dict_really_writes_job_unconditionally() -> void:
	## FLOOR on the PREMISE. Every arm above rests on `job` being present-but-empty rather
	## than absent. If to_dict ever stops writing it unconditionally, the defect changes shape
	## and this file's reasoning needs re-reading rather than trusting.
	var src: String = FileAccess.get_file_as_string("res://src/battle/Combatant.gd")
	assert_ne(src, "", "Combatant.gd unreadable — the premise is unverified")
	assert_true(src.contains('data["job"] = data.get("job_id"'),
		("Combatant.to_dict no longer writes `job` from `job_id` unconditionally. The empty-"
		+ "middle-key premise these arms are built on has changed."))
