extends GutTest

## ELEVEN TOOLS DECLARE `--selftest` AND NOTHING RAN ANY OF THEM.
##
## 2026-09-12. Three lanes moved their measurement scripts out of gitignored `tmp/` and into
## `tools/` this session, for the stated reason that a number reaching struktured must be
## re-derivable by someone else. `pck_budget.py` carries the web-size figures, `pck_drift.py`
## and `check_pck_complete.py` gate deploys, `cutscene_dispatch.py` produced the unrouted-scene
## count, `input_caption_audit.py` found four shipped caption defects. Each has a selftest.
##
## ⛔ THE FIRST VERSION OF THIS FILE SAID "NOTHING IN THE SUITE, THE GATE OR CI EXECUTES ONE."
## THAT WAS FALSE, and the error is worth more than the claim was. I searched `test/*`,
## `.github/*`, `tools/run_tests.sh` and `tools/*gate*` — four path patterns picked because they
## sounded like where a runner lives. `publish_all.sh` is in none of them, and it runs three on
## EVERY publish (cowir-deploy, 2026-09-11), each as `if ! _ST=$(… --selftest); then … exit 4`.
## **A negative over a corpus chosen by guessing is worth nothing.** Corrected, measured against
## the whole repo:
##
##      3 .py tools   selftest RUN on every publish       publish_all.sh
##      8 .py tools   run NOWHERE                         this file covers 6, exempts 2
##     15 .sh tools   declare --selftest, run NOWHERE     cowir-deploy's; deliberately not walked
##
## ⚠️ THE .sh ROW NEARLY SHIPPED AS "invoked by 1 file each." The single match is each tool's OWN
## usage comment — `#   tools/check_import_ok.sh --selftest`. Mention, not invocation.
## `publish_all.sh` invokes zero `.sh` selftests; it CALLS `check_import_ok.sh`, and its comment
## says the decision is "exercised by ITS OWN selftest as a subprocess" — the tool runs, its
## selftest does not. Three spot-checked green today. Their runner belongs in the publish chain
## rather than this suite, so they are not walked here.
##
## 🔑 WHY THIS IS NOT HYPOTHETICAL, and it is my own tool: `cutscene_dispatch.py` shipped in
## `.335` not knowing the `cutscene_id` dispatch form, and reported three scenes that shipped in
## the SAME TAG as unreachable. Its selftest was green throughout — the gap was a door nobody
## had written yet, so no control named it. What caught it was running the tool by hand against
## a peer's fix. **A tool that is never executed cannot even fail that way.**
##
## WHAT THIS ASSERTS, and it is deliberately weak: every tool that OFFERS a selftest passes it.
## Not that the selftests are good — `cutscene_dispatch`'s could not see its own missing door,
## and that limit is in its docstring. This is the floor below that: the instrument still runs,
## its controls still hold, and nobody has broken it since the last time anyone looked.
##
## ⚠️ TWO TOOLS ARE EXEMPT AND BOTH EXEMPTIONS ARE NARROW.
##   audit_whoop.py            needs `soundfile`, absent here. NOT a hardcoded skip: the arm
##                             below treats a MISSING MODULE as an environment gap and any
##                             other failure as a defect, so the day the dep lands it is
##                             checked like the rest, with no edit.
##   reachable_from_anchors.py 33.0 s measured — it walks every .gd and builds a class_name
##                             closure. Too slow for a per-run gate; named here with its cost
##                             so the exemption is a decision rather than an omission. Run it
##                             by hand when the closure matters.

const TOOLS_DIR := "res://tools"
## Exempt BY NAME with the measured reason. A count floor cannot express "and why".
const SLOW_TOOLS := {
	"reachable_from_anchors.py": "33.0 s measured 2026-09-12 — full class_name closure over src/",
}
## Named members that must be discovered, one per owning lane, so a broken walk is loud.
const MUST_DISCOVER := ["cutscene_dispatch.py", "pck_budget.py", "input_caption_audit.py"]


func _run(args: Array) -> Array:
	var out: Array = []
	var code := OS.execute("python3", args, out, true)
	return [code, "\n".join(out.map(func(x): return str(x)))]


## Tools that OFFER a selftest, discovered by reading them rather than by a hand list — a hand
## list goes stale the next time a lane adds a tool, which is exactly when this should notice.
func _selftest_tools() -> Array:
	var found: Array = []
	var d := DirAccess.open(TOOLS_DIR)
	if d == null:
		return found
	for f in d.get_files():
		if not f.ends_with(".py"):
			continue
		var src: String = FileAccess.get_file_as_string(TOOLS_DIR + "/" + f)
		if src.contains("--selftest"):
			found.append(f)
	found.sort()
	return found


## PREMISE. The walk must find a real corpus, by NAMED member — a floor of "some" passes on a
## walk that found three unrelated files.
func test_premise_the_tool_walk_finds_the_instruments() -> void:
	var tools := _selftest_tools()
	assert_gt(tools.size(), 7,
		"only %d tools with a --selftest found — the walk is short, and a short walk checks nothing while reporting success" % tools.size())
	var missing: Array[String] = []
	for name in MUST_DISCOVER:
		if not tools.has(name):
			missing.append(name)
	assert_eq(missing.size(), 0,
		"the walk lost a tool it must see: %s — these are cited in decisions, and a walk that cannot find them is not checking them" % ", ".join(missing))
	for k in SLOW_TOOLS.keys():
		assert_true(tools.has(str(k)),
			"%s is exempted for runtime but the walk no longer finds it — delete the exemption, or fix the walk. An exemption for an absent file asserts nothing." % str(k))


## THE FLOOR. Every instrument still runs and its own controls still hold.
func test_every_tool_that_offers_a_selftest_passes_it() -> void:
	var probe := _run(["-c", "print('alive')"])
	if int(probe[0]) != 0:
		pending("python3 unavailable — the instruments cannot be exercised here")
		return
	assert_true(str(probe[1]).contains("alive"), "python control produced no output")

	var broken: Array[String] = []
	var env_gaps: Array[String] = []
	var ran := 0
	for name in _selftest_tools():
		if SLOW_TOOLS.has(name):
			continue
		var res := _run(["tools/" + name, "--selftest"])
		var code := int(res[0])
		var text := str(res[1])
		if code == 0:
			ran += 1
			continue
		# A missing optional dependency is an environment gap, not a broken instrument. Any
		# other non-zero exit is the tool failing its own controls.
		if text.contains("ModuleNotFoundError") or text.contains("ImportError"):
			env_gaps.append("%s (%s)" % [name, text.split("\n")[-1].substr(0, 60)])
		else:
			broken.append("%s exit=%d: %s" % [name, code, text.split("\n")[-1].substr(0, 90)])

	broken.sort()
	env_gaps.sort()
	assert_gt(ran, 5,
		"only %d instruments actually ran — if everything is landing in the exempt or env-gap buckets this arm is reporting success for doing nothing" % ran)
	assert_eq(broken.size(), 0,
		"an instrument fails its OWN selftest — its controls no longer hold, and every number it has produced since is suspect: %s" % ", ".join(broken))
	assert_lte(env_gaps.size(), 1,
		"more instruments are unrunnable for missing dependencies than the 1 known (audit_whoop needs soundfile): %s — each is an instrument nobody is checking" % ", ".join(env_gaps))
