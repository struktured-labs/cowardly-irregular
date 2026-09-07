extends GutTest

## Backstop for the tools/deploy_web.sh size gate (2026-07-03 incident:
## 226 MB pck broke the itch.io HTML5 embed). The script is the primary
## wall; this test makes the standing GUT gate itself refuse whenever
## the last-exported pck on disk is over the limit — so even an ad-hoc
## deploy chain that skipped the script gets stopped at the next suite
## run, before the next push.

const LIMIT_BYTES: int = 199_000_000


func test_last_exported_web_pck_under_itch_embed_limit() -> void:
	# res:// maps to the project root in editor/headless runs.
	var f := FileAccess.open("res://builds/web/index.pck", FileAccess.READ)
	if f == null:
		# NOT pass_test(). The sample this backstop measures is absent exactly when
		# the backstop matters least-visibly: builds/ is gitignored (.gitignore:28),
		# so CI and every fresh checkout take this branch on every run. pass_test()
		# scored that as a GREEN TICK, indistinguishable from "the pck was measured
		# and is under the limit" — and no existing instrument could tell them apart
		# (pass_test is a real assert, so GUT never scores it Risky, and Tests is 1
		# not 0). Verified 2026-08-22 with tools/mutation_check.sh: LIMIT_BYTES
		# 199_000_000 -> 1 with no pck on disk stays GREEN; the identical mutation
		# with an 11-byte pck present goes RED. Same file, same mutation, opposite
		# verdicts — the only variable is whether the sample exists.
		# pending() does not make this test live; it makes its INERTNESS visible,
		# which is what gate.sh's "check the CONDITION" pending banner is for.
		pending("no web export at builds/web/index.pck — pck size backstop NOT exercised (builds/ is gitignored, so this is the CI and fresh-checkout default)")
		return
	var size := f.get_length()
	f.close()
	assert_lt(int(size), LIMIT_BYTES,
		"builds/web/index.pck is %d MB — itch.io refuses HTML5 embeds >= 200 MB; fix export_presets exclude_filter BEFORE pushing" % (size / 1048576))
