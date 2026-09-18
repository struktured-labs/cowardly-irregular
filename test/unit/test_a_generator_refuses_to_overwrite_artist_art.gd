extends GutTest

## CLAUDE.md requires that AI generation never overwrite artist-made assets without explicit
## approval. Until 2026-09-17 the protection was an AUDIT — `tools/audit_sprite_tiers.py:9` says
## so plainly: "regeneration will happily overwrite artist work." An audit reports after the
## pixels are gone. Exactly one tool refused, and a DIRECT run of the generator bypassed it.
##
## `tools/artist_guard.py` now owns the rule and `gen_sprite_sdxl.py` calls it at its one write
## site. This file asserts the WIRING, because the guard's own behaviour is covered by its
## `--selftest` (walked by test_every_tool_selftest_still_passes.gd) and behaviour that nothing
## calls protects nothing.
##
## Triggers: OWNER (the rule forked back into a private copy) · WIRING (the call went away) ·
## ORDER (the guard moved BELOW the write, where it cannot prevent anything) ·
## FAILOPEN (the unavailable-provenance branch stopped refusing).

const GUARD := "res://tools/artist_guard.py"
const GENERATOR := "res://tools/gen_sprite_sdxl.py"
const SWEEP := "res://tools/gen_full_sweep.py"
const REGEN := "res://tools/regen_monster_artist_style.py"


func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func test_the_guard_exists_and_exports_the_entry_point() -> void:
	var src := _src(GUARD)
	assert_gt(src.length(), 200, "SCOPE: %s is missing or empty — every arm below is vacuous without it" % GUARD)
	assert_true(src.contains("def assert_writable("),
		"OWNER: artist_guard.py no longer defines assert_writable() — the callers below import a name that does not exist")


func test_the_generator_calls_the_guard_BEFORE_it_writes() -> void:
	var src := _src(GENERATOR)
	assert_true(src.contains("from tools.artist_guard import assert_writable"),
		"WIRING: %s no longer imports the guard" % GENERATOR)
	var guard_at := src.find("assert_writable(out_path")
	var write_at := src.find("strip.save(out_path)")
	assert_gt(guard_at, -1, "WIRING: the generator's write site no longer calls assert_writable(out_path, ...)")
	assert_gt(write_at, -1, "SCOPE: strip.save(out_path) is gone — this arm no longer describes the write site it guards")
	assert_lt(guard_at, write_at,
		"ORDER: assert_writable appears AFTER strip.save — a refusal below the write cannot prevent the overwrite it exists to stop")


func test_the_sweep_derives_from_the_shared_owner_not_a_private_copy() -> void:
	var src := _src(SWEEP)
	assert_true(src.contains("from tools.artist_guard import protected_anims"),
		"OWNER: gen_full_sweep.py no longer sources its protection from artist_guard.py")
	assert_false(src.contains("_LEGACY_PROTECTED = {"),
		"OWNER: the legacy floor has forked back into gen_full_sweep.py. Two copies drift, and this one already went stale once — it predates the cleric and mage artist drops")


func test_unavailable_provenance_REFUSES_rather_than_returning_empty() -> void:
	var src := _src(GUARD)
	var at := src.find("except ImportError")
	assert_gt(at, -1, "FAILOPEN: the guard no longer handles an unimportable provenance oracle at all")
	# The FIRST STATEMENT of the handler, not merely the presence of the string: a mutation that
	# comments the raise out and returns an empty oracle leaves "raise SystemExit" in the file,
	# and a contains() check passes on it. Measured — that mutation survived the first version.
	var nl := src.find("\n", at)
	var line_end := src.find("\n", nl + 1)
	var first: String = src.substr(nl + 1, line_end - nl - 1).strip_edges()
	assert_true(first.begins_with("raise SystemExit"),
		"FAILOPEN: the first statement of the unavailable-provenance handler is `%s`, not a raise. Returning an empty protected set there reports 'nothing is artist work', which is the one answer that destroys everything while looking green" % first)


## A tier the guard cannot read is unknown provenance, and this generator used to treat it as
## permission: `tier in ("T2", "T3")` is exact-match, and everything else fell through to "".
## Measured against a synthetic manifest before the fix — lowercase "t2", the already-authored
## "T2_artist_draft" and a missing tier field all PROCEEDED over artist pixels.
func test_an_unreadable_tier_REFUSES_rather_than_falling_through() -> void:
	var guard := _src(GUARD)
	assert_true(guard.contains("def tier_refusal("),
		"OWNER: artist_guard.py no longer defines tier_refusal() — the generator below imports a name that does not exist")
	## Both membership tests, as STATEMENTS. Naming the two constants only proves they are
	## DEFINED — cowir-autogrind's shape — and the claim below is about the decision CONSULTING
	## them. Measured: leaving both defined while consulting one reds 5 selftest arms and left
	## this one green until it carried `if t in`.
	assert_true(guard.contains("if t in _WRITABLE_TIERS:") and guard.contains("if t in _PROTECTED_TIERS:"),
		"OWNER: the tier decision collapsed back to one set. Three answers are the fix: writable proceeds, artist refuses, UNRECOGNISED refuses")

	var regen := _src(REGEN)
	assert_true(regen.contains("from tools.artist_guard import tier_refusal"),
		"WIRING: %s no longer sources its tier decision from the shared owner" % REGEN)
	assert_true(regen.contains("tier_refusal(tier"),
		"WIRING: artist_write_refusal no longer calls tier_refusal — the import alone refuses nothing")
	assert_false(regen.contains('tier in ("T2", "T3")'),
		"OWNER: the two-way membership test has forked back into the generator. That test is the defect: it answers 'writable' for every tier it does not recognise")
