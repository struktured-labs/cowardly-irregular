extends GutTest

## tick 207: PartyStatusScreen._job_label has a proper fallback
## cascade — name → prettified id → "(no job)".
##
## Pre-fix the fallback was just the literal string "Job" which
## looked like a UI label (the kind that introduces a value),
## not a value itself. A briefly-unassigned combatant or one with
## data drift (job dict missing "name" field) rendered as the
## word "Job" on their card — confusing.
##
## Fix:
##   1. job["name"] (data file canonical name)
##   2. _format_id(job["id"]) (proper title-cased fallback per tick 204)
##   3. "(no job)" (clear "unset" indicator with parens — reads as
##      a state, not a value)
##
## Same cascade applies to Object-shaped jobs (for non-Dictionary
## job storage in tests or future job representations).

const PARTY_STATUS_SCREEN := "res://src/ui/PartyStatusScreen.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _new_screen() -> Object:
	var scene = load(PARTY_STATUS_SCREEN)
	return scene.new()


# Minimal mock — Object with arbitrary "job" property.
class FakeMember:
	var job
	var combatant_name: String = "Test"

	func _init(j = null):
		job = j


# ── Happy path: name field present ────────────────────────────────────

func test_dict_job_with_name_returns_name() -> void:
	var s = _new_screen()
	var member = FakeMember.new({"id": "fighter", "name": "Fighter"})
	assert_eq(s._job_label(member), "Fighter",
		"job dict with 'name' → name")
	s.queue_free()


func test_dict_job_with_multi_word_name_preserved() -> void:
	# Pin: the data-file name is used verbatim. No prettifier applied.
	var s = _new_screen()
	var member = FakeMember.new({"id": "time_mage", "name": "Time Mage"})
	assert_eq(s._job_label(member), "Time Mage",
		"data-file name returned verbatim")
	s.queue_free()


# ── Fallback 1: id only (name missing) ─────────────────────────────────

func test_dict_job_with_id_only_prettifies() -> void:
	# Real failure mode: data drift, name field missing.
	# Now uses tick 204's _format_id for proper title-case.
	var s = _new_screen()
	var member = FakeMember.new({"id": "time_mage"})
	assert_eq(s._job_label(member), "Time Mage",
		"id-only fallback uses _format_id (proper title case)")
	s.queue_free()


func test_dict_job_with_empty_name_falls_back_to_id() -> void:
	# Pin: empty name string still triggers the id fallback (data
	# author had a name field but left it blank).
	var s = _new_screen()
	var member = FakeMember.new({"id": "scriptweaver", "name": ""})
	assert_eq(s._job_label(member), "Scriptweaver",
		"empty name → fall through to id prettifier")
	s.queue_free()


func test_dict_job_three_word_id_prettifies() -> void:
	var s = _new_screen()
	var member = FakeMember.new({"id": "shadow_dragon_slayer"})
	assert_eq(s._job_label(member), "Shadow Dragon Slayer",
		"3-word snake_case id → 'Shadow Dragon Slayer'")
	s.queue_free()


# ── Fallback 2: "(no job)" terminal state ──────────────────────────────

func test_null_job_returns_no_job_label() -> void:
	# Briefly during job-swap, member.job can be null.
	var s = _new_screen()
	var member = FakeMember.new(null)
	assert_eq(s._job_label(member), "(no job)",
		"null job → '(no job)' (state indicator, not 'Job')")
	s.queue_free()


func test_empty_dict_returns_no_job_label() -> void:
	# Defensive: a job dict with no id and no name → terminal fallback.
	var s = _new_screen()
	var member = FakeMember.new({})
	assert_eq(s._job_label(member), "(no job)",
		"empty dict → '(no job)'")
	s.queue_free()


func test_dict_with_only_other_keys_returns_no_job_label() -> void:
	# Dict has random keys but neither name nor id.
	var s = _new_screen()
	var member = FakeMember.new({"foo": "bar", "level": 5})
	assert_eq(s._job_label(member), "(no job)",
		"dict missing both name and id → '(no job)'")
	s.queue_free()


# ── Negative pin: the pre-fix "Job" literal is gone ────────────────────

func test_old_job_literal_fallback_gone() -> void:
	# Pre-fix had `return "Job"` as the terminal fallback. The new
	# fallback is `(no job)` — explicit unset state.
	var src := _read(PARTY_STATUS_SCREEN)
	var fn_idx: int = src.find("func _job_label")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_false(body.contains("return \"Job\""),
		"pre-fix bare 'Job' fallback must be gone")
	assert_true(body.contains("return \"(no job)\""),
		"new '(no job)' terminal fallback must be present")


# ── Source-level pins: cascade structure ──────────────────────────────

func test_cascade_calls_format_id_on_id_fallback() -> void:
	# Pin: an id the game does NOT know still goes through _format_id (tick 204's title-case helper), never capitalize().
	var src := _read(PARTY_STATUS_SCREEN)
	var fn_idx: int = src.find("func _job_label")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("return _format_id(jid)"),
		"the unknown-id fallback must use _format_id, for both job shapes")


func test_cascade_puts_the_world_name_before_the_stored_name() -> void:
	# RE-PINNED 2026-11-05. This arm read "the data-file name wins" (name before id). cowir-story's canon reversed that
	# for a job the game knows: it reads as THIS world names it (a stored "Cleric" must not show in W2). The stored
	# name still wins over the id's words, which is what the arm protected.
	var src := _read(PARTY_STATUS_SCREEN)
	var fn_idx: int = src.find("func _job_label")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	var world: int = body.find("job_display_name_for_id(jid)")
	var stored: int = body.find("return stored")
	var words: int = body.find("return _format_id(jid)")
	assert_gt(world, -1)
	assert_gt(stored, -1)
	assert_gt(words, -1)
	assert_lt(world, stored, "a known job's world name comes before its stored name")
	assert_lt(stored, words, "the stored name still wins over the id's words")


# ── Cross-pin: tick 204 _format_id preserved ──────────────────────────

func test_tick_204_format_id_helper_preserved() -> void:
	var src := _read(PARTY_STATUS_SCREEN)
	assert_true(src.contains("func _format_id(id: String) -> String:"),
		"tick 204 _format_id helper preserved")
	# AND it still does proper title case (the per-word loop).
	assert_true(src.contains("id.split(\"_\")"),
		"_format_id still splits on underscore")
