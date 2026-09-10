extends GutTest

## The F1 controls reference is the ONLY place a player learns the global keys, and it is the
## screen struktured asked for by name ("it should be really easy to know all the buttons").
##
## Found by the reverse legend sweep: GameLoop binds KEY_F8 -> _write_feedback_bundle(), a
## screenshot + log + save + game state written as ONE FILE a tester can send back. It was named
## NOWHERE a player can see — not the overlay, not ControlsMenu, not a tutorial hint. His artist
## reports bugs in prose ("I tried a lot of keys"); the one feature built to replace that with an
## artifact was undiscoverable.
##
## ⚠️ SCOPE, STATED TO MATCH THE INSTRUMENT: this checks GLOBAL **F-KEYS ONLY** — the regex is
## `keycode == KEY_F<digits>`. GameLoop also binds ESCAPE, P, T, X and Y globally and this sees
## NONE of them. The filename says "every global key" and that is broader than what runs.
##
## This class is `feedback_label_broader_than_predicate` (2026-08-05), and its first line is why
## none of my controls caught it: A CONTROL TESTS THE EXPRESSION, AND THE EXPRESSION IS FINE. The
## regex correctly finds every F-key; the fabricated-key control correctly reports absence. Both
## true, and neither touches the gap between "every global key" and "every F-key".
##
## Recorded because cowir-main demonstrated the cost again on 2026-09-10: a predicate phrased more
## broadly than its implementation ("unreachable by ANY path", over a scanner that followed two of
## three link kinds) CONCEALS the gap, because broad-sounding language deters anyone from reading
## the code beneath it. An honest narrow claim gets interrogated; a confident wide one does not.
##
## So: next global NON-F key added is NOT caught by this. That is a gap to fill, not a covered case.

const GL := "res://src/GameLoop.gd"
const OVERLAY := "res://src/ui/HowToPlayOverlay.gd"

## NO SUPPRESSION LIST. There was one, holding "F5", and its stated reason — "printed on that
## editor's own legend" — was NEVER TRUE: F5 appears in zero on-screen strings in
## AutobattleGridEditor. @cowir-sfx named this shape FALSE (never true; the mechanism was simply
## unmodelled), distinct from EXPIRED, and it is the dangerous one because no rot check can catch
## it — there is no transition to detect. The entry was also UNNECESSARY: F5 is listed on the F1
## overlay, so the assertion passes without it. An exemption that is both false and unneeded reads
## as a considered decision and hides that nobody checked.


func _global_fkeys() -> Array:
	var src := FileAccess.get_file_as_string(GL)
	var re := RegEx.new()
	re.compile("keycode\\s*==\\s*KEY_(F\\d+)\\b")
	var out := []
	for m in re.search_all(src):
		var k := m.get_string(1)
		if not out.has(k):
			out.append(k)
	out.sort()
	return out


## THE RATCHET: every global F-key must appear in the reference the player is told to open.
func test_the_reference_lists_every_global_fkey() -> void:
	var keys := _global_fkeys()
	assert_gt(keys.size(), 3,
		"CONTROL: GameLoop must really bind several F-keys, else this sweep proves nothing (got %s)" % str(keys))
	var overlay := FileAccess.get_file_as_string(OVERLAY)
	assert_gt(overlay.length(), 0, "CONTROL: the overlay must be readable")
	for k in keys:
		assert_true(overlay.contains(k),
			"%s is bound globally and the controls reference never names it — the only screen that tells a player the keys" % k)


## The one that prompted this. Named explicitly so deleting the row is unambiguous, not just a
## count changing.
func test_the_bug_report_key_is_advertised() -> void:
	var overlay := FileAccess.get_file_as_string(OVERLAY)
	assert_true(overlay.contains("F8"),
		"F8 writes a screenshot + log + save bundle a tester can send back; it must be discoverable")
	assert_true(overlay.to_lower().contains("bug report"),
		"and the row must say what it DOES — 'F8' alone teaches nobody why to press it")


## The advertised key must be real. A reference that lies is the defect this lane spent the day
## removing; matching the COMPARISON, not the token, because a comment naming it cannot fail.
func test_the_advertised_key_is_actually_bound() -> void:
	var src := FileAccess.get_file_as_string(GL)
	var re := RegEx.new()
	re.compile("keycode\\s*==\\s*KEY_F8\\b")
	assert_not_null(re.search(src),
		"the overlay advertises F8, so something must COMPARE a keycode to KEY_F8")
	assert_true(src.contains("_write_feedback_bundle"),
		"and it must reach the bundle writer")
	var ctl := RegEx.new()
	ctl.compile("keycode\\s*==\\s*KEY_F97\\b")
	assert_null(ctl.search(src), "CONTROL: this binding check can report absence")
