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
		pass_test("no web export on disk — nothing to check")
		return
	var size := f.get_length()
	f.close()
	assert_lt(int(size), LIMIT_BYTES,
		"builds/web/index.pck is %d MB — itch.io refuses HTML5 embeds >= 200 MB; fix export_presets exclude_filter BEFORE pushing" % (size / 1048576))
