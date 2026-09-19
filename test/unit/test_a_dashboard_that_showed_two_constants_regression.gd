extends GutTest

## The autogrind dashboard rendered CSI as a flat 0% and Yield as a flat 100% for an entire
## session. `AutogrindSystem.get_grind_stats()` computes both on every refresh; the controller's
## `get_grind_stats()` is a 28-key LITERAL built beside `sys_stats` rather than from it, and it
## cherry-picked four keys — so csi, yield_multiplier and automation_affinity were discarded one hop
## before the UI that reads them.
##
##   AutogrindSystem:558-560        "csi" · "yield_multiplier" · "automation_affinity"   computed
##   AutogrindController:686        sys_stats, then a literal taking total_gold + 3 others
##   GameLoop:5999 · 6227 · 6508    refresh(stats, region) — all three pass the CONTROLLER's dict
##   AutogrindDashboard:742/744     stats.get("csi", 0.0) · stats.get("yield_multiplier", 1.0)
##                                  -> 0.0 and 1.0, always
##
## ⚠️ AND THE STRIP HID HALF OF IT, WHICH IS WHY IT SURVIVED: AutogrindStatsStrip:151 falls back to
## `AutogrindSystem.get_csi(region_id)` and was therefore CORRECT, while :164 fell back to
## `stats["efficiency"]` — a DIFFERENT QUANTITY under the Yield label, so an absent key rendered a
## plausible wrong number rather than a default. Two surfaces, one missing key, three behaviours.
##
## Reported by cowir-controller, who traced it in source and declined to claim it.

const ControllerScript = preload("res://src/autogrind/AutogrindController.gd")

const DASHBOARD := "res://src/ui/autogrind/AutogrindDashboard.gd"
const STRIP := "res://src/ui/autogrind/AutogrindStatsStrip.gd"
const CONTROLLER := "res://src/autogrind/AutogrindController.gd"


func before_each() -> void:
	for n in ["AutogrindSystem", "AutobattleSystem"]:
		var sys: Node = get_node_or_null("/root/" + n)
		if sys != null and "_test_disable_persistence" in sys:
			sys._test_disable_persistence = true


func _keys_the_ui_reads() -> Array:
	## Derived from both UI files, so a new stats key the UI starts reading is covered without
	## anyone remembering to add it here.
	var out: Dictionary = {}
	var re := RegEx.create_from_string("stats\\.get\\(\"([a-z_]+)\"")
	for path in [DASHBOARD, STRIP]:
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			out[m.get_string(1)] = true
	var keys: Array = out.keys()
	keys.sort()
	return keys


func test_the_scan_finds_the_ui_reads() -> void:
	## CONTROL: every arm below is vacuous if the regex finds nothing.
	var keys: Array = _keys_the_ui_reads()
	gut.p("    UI reads %d stats keys" % keys.size())
	assert_gt(keys.size(), 8, "the UI's stats reads must be findable")
	assert_true(keys.has("csi"), "CONTROL: the key this bug was about is in the scan")
	assert_true(keys.has("yield_multiplier"), "CONTROL: and its sibling")


func test_the_controller_supplies_every_key_the_ui_reads() -> void:
	## THE RATCHET, and it is the shape of the defect: the producer is a literal and the consumer is
	## a set of independent `get`s, so nothing but this arm connects them.
	var src: String = FileAccess.get_file_as_string(CONTROLLER)
	var i: int = src.find("func get_grind_stats")
	assert_gt(i, -1, "CONTROL: the controller's get_grind_stats must be locatable")
	var body: String = src.substr(i, src.find("\nfunc ", i + 10) - i)
	var missing: Array[String] = []
	for key in _keys_the_ui_reads():
		if not body.contains("\"%s\"" % key):
			missing.append(key)
	for m in missing:
		gut.p("    MISSING: the UI reads '%s' and the controller never sends it" % m)
	assert_eq(missing.size(), 0,
		"the dashboard reads keys this dict does not carry, so they render as their defaults forever: " + str(missing))


func test_csi_and_yield_reach_the_ui_with_real_values() -> void:
	## The consequence, driven rather than pinned. A controller dict whose csi is absent is
	## indistinguishable from one whose csi is genuinely 0.0 — this arm asks for a NON-default.
	var sys: Node = get_node_or_null("/root/AutogrindSystem")
	if sys == null or not sys.has_method("get_grind_stats"):
		pass_test("AutogrindSystem autoload unavailable")
		return
	var ctrl = ControllerScript.new()
	add_child_autofree(ctrl)
	if not ctrl.has_method("get_grind_stats"):
		pass_test("controller has no get_grind_stats")
		return
	var stats: Dictionary = ctrl.get_grind_stats()
	assert_true(stats.has("csi"), "the controller must carry csi")
	assert_true(stats.has("yield_multiplier"), "and yield_multiplier")
	assert_true(stats.has("automation_affinity"), "and automation_affinity")


func test_the_controller_agrees_with_the_system_on_those_keys() -> void:
	## Carried, not recomputed: a second computation here is the twin-drift shape that put three
	## effects out of sync between the two battle engines earlier today.
	var sys: Node = get_node_or_null("/root/AutogrindSystem")
	if sys == null or not sys.has_method("get_grind_stats"):
		pass_test("AutogrindSystem autoload unavailable")
		return
	var ctrl = ControllerScript.new()
	add_child_autofree(ctrl)
	var sys_stats: Dictionary = sys.get_grind_stats()
	var stats: Dictionary = ctrl.get_grind_stats()
	for key in ["csi", "yield_multiplier", "automation_affinity"]:
		assert_eq(float(stats.get(key, -999.0)), float(sys_stats.get(key, -998.0)),
			"the controller must pass the system's %s through, not compute its own" % key)


func test_no_fallback_substitutes_a_different_quantity() -> void:
	## :164 fell back to `efficiency` under the Yield label — not a default, a different metric, so
	## an absent key rendered a plausible wrong number. A fallback may name its own subject or ask
	## the system; it may not name a sibling stat.
	var strip: String = FileAccess.get_file_as_string(STRIP)
	assert_eq(strip.count("stats.get(\"yield_multiplier\", stats.get(\"efficiency\""), 0,
		"the Yield label must not fall back to the efficiency stat — it is a different quantity")
	var re := RegEx.create_from_string("stats\\.get\\(\"([a-z_]+)\",\\s*stats\\.get\\(\"([a-z_]+)\"")
	var crossed: Array[String] = []
	for path in [DASHBOARD, STRIP]:
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			if m.get_string(1) != m.get_string(2):
				crossed.append("%s -> %s" % [m.get_string(1), m.get_string(2)])
	for c in crossed:
		gut.p("    CROSSED FALLBACK: " + c)
	assert_eq(crossed.size(), 0,
		"a stats read falls back to a DIFFERENT stat, which renders a wrong number rather than a default: " + str(crossed))
