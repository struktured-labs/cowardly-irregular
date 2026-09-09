extends GutTest

## struktured 2026-09-06: "just have a general guard on if u have the ability or not at all,
## provenance irrelevant." Combatant.knows_ability is THE predicate and its own comment says
## "never re-derive per source". AutobattleSystem carried a SECOND derivation covering only
## kit + free_move + abilities_at_level, so autobattle upgrade resolution denied anything you
## LEARNED, PURCHASED, or got from a SECONDARY JOB.

const AB := "res://src/autobattle/AutobattleSystem.gd"
const CB := "res://src/battle/Combatant.gd"

func _read(p: String) -> String:
	var s := FileAccess.get_file_as_string(p)
	assert_gt(s.length(), 1000, "CONTROL: read %s" % p)
	return s

func _has_learned_body() -> String:
	var s := _read(AB)
	var i := s.find("func _combatant_has_learned(")
	assert_gt(i, -1, "CONTROL: located the predicate")
	var j := s.find("\nfunc ", i + 10)
	return s.substr(i, j - i)

func test_the_canonical_predicate_covers_all_six_sources() -> void:
	## The premise. If knows_ability ever narrows, delegating to it stops being the right answer
	## and this should be revisited rather than silently satisfied.
	var s := _read(CB)
	var i := s.find("func knows_ability(")
	assert_gt(i, -1, "CONTROL: knows_ability exists")
	var j := s.find("\nfunc ", i + 10)
	var body := s.substr(i, j - i)
	for src in ["learned_abilities", "purchased_abilities", "free_move", "abilities_at_level", "secondary_job"]:
		assert_true(body.contains(src), "knows_ability must still cover %s" % src)

func test_autobattle_delegates_instead_of_re_deriving() -> void:
	assert_true(_has_learned_body().contains("combatant.knows_ability("),
		"upgrade resolution must use the one predicate, not a second copy")

func test_the_second_derivation_is_actually_gone() -> void:
	## Delegating while LEAVING the old ladder would read as fixed and still answer from the copy
	## on any path that reached it first.
	## Assert on CODE constructs, not words: the explanatory comment above the delegation names
	## the sources it replaced, so a prose-blind substring check fails on the fix's own docstring.
	var body := _has_learned_body()
	for leftover in ["JobSystem.get_job(", "at_level[", "job.get(\"abilities\""]:
		assert_false(body.contains(leftover),
			"the re-derived ladder must be deleted, not shadowed — found '%s' still in the body" % leftover)

func test_the_secondary_job_gap_is_closed() -> void:
	## The specific reported symptom: "2ndary job does nothing apparently". knows_ability covers
	## the secondary kit; the deleted copy did not, so an upgrade from a secondary job was denied.
	var cb := _read(CB)
	var i := cb.find("func knows_ability(")
	var j := cb.find("\nfunc ", i + 10)
	assert_true(cb.substr(i, j - i).contains("secondary_job"),
		"CONTROL: the canonical predicate is the one that knows about secondary jobs")
	assert_false(_has_learned_body().contains("secondary_job as Dictionary"),
		"autobattle must not re-implement the secondary lookup — it delegates")

func test_the_null_guards_survive() -> void:
	var body := _has_learned_body()
	assert_true(body.contains("combatant == null"), "a null combatant must still return false")
	assert_true(body.contains("ability_id == \"\""), "an empty id must still return false")
