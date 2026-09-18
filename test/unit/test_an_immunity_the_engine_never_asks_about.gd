extends GutTest

## A monster's `immunities` array is authored data, and the engine asks about exactly ONE category.
##
## `_monster_immune_to_category(target, category)` takes the category as a PARAMETER, which reads as
## general — and every call site in src/ passes the literal `"physical"`:
##
##     BattleManager:4438  _execute_attack           -> "physical"
##     BattleManager:4896  _execute_physical_ability -> "physical"
##
## There is no magic call site. `_execute_magic_ability` checks `_monster_phase_out_check` and the
## elemental table and never asks about immunities at all.
##
## ⚠️ NOT A LIVE DEFECT TODAY, AND THIS FILE IS NOT BILLED AS ONE: `null_entity` is the only monster
## authoring an immunity and it authors "physical", which IS consumed. The gap is that authoring
## `"magic"` — an ordinary content act, in the file where immunities live, next to an entry that
## works — would do nothing, silently, and the monster would take full magic damage while its data
## says otherwise. A parameterised function whose every caller passes one literal is the shape that
## invites exactly that.
##
## ✅ SO THIS GUARD IS AN AUTHORING BACKSTOP, NOT A BUG REPORT. It reds the day someone authors a
## category nothing asks about — which is the moment the information is useful and cheap to act on,
## rather than after a playtest where a boss "ignores" its own resistance.
##
## Both sides are DERIVED: authored categories from monsters.json, consumed categories from the
## literals at the call sites. A hand-list on either side would go stale the first time someone adds
## a category, which is the event this exists to catch.

const MONSTERS := "res://data/monsters.json"
const SRC_ROOT := "res://src"
const FN := "_monster_immune_to_category"


func _monsters() -> Dictionary:
	var raw: String = FileAccess.get_file_as_string(MONSTERS)
	assert_ne(raw, "", "CONTROL: monsters.json must be readable, or every arm below is vacuous")
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return {}
	var inner: Variant = parsed.get("monsters", parsed)
	return inner if inner is Dictionary else {}


## Every distinct category named in any monster's `immunities`.
func _authored_categories() -> Array[String]:
	var out: Array[String] = []
	for mid in _monsters():
		var m: Variant = _monsters()[mid]
		if not (m is Dictionary):
			continue
		var im: Variant = m.get("immunities", [])
		if not (im is Array):
			continue
		for cat in im:
			var c: String = str(cat)
			if c != "" and not (c in out):
				out.append(c)
	out.sort()
	return out


func _src_files() -> Array[String]:
	var out: Array[String] = []
	var stack: Array = [SRC_ROOT]
	while not stack.is_empty():
		var d: String = str(stack.pop_back())
		for sub in DirAccess.get_directories_at(d):
			stack.append("%s/%s" % [d, sub])
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				out.append("%s/%s" % [d, f])
	return out


## Every category literal the engine actually passes. Derived from the CALL SITES, so a new consumer
## is picked up the day it lands without editing this file.
func _consumed_categories() -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.create_from_string(FN + "\\s*\\([^,)]+,\\s*\"([a-z_]+)\"")
	for path in _src_files():
		var src: String = FileAccess.get_file_as_string(path)
		if not src.contains(FN):
			continue
		for m in re.search_all(src):
			var c: String = m.get_string(1)
			if not (c in out):
				out.append(c)
	out.sort()
	return out


func test_the_derived_sets_are_real() -> void:
	# Control. `authored - consumed == []` is the success value AND what two empty derivations give.
	var authored: Array[String] = _authored_categories()
	var consumed: Array[String] = _consumed_categories()
	assert_gt(authored.size(), 0,
		"derived ZERO authored immunity categories — monsters.json parsed empty, so the check below is vacuous")
	assert_gt(consumed.size(), 0,
		"derived ZERO consumed categories — the call-site scan is broken, which would make EVERY authored category read as unconsumed")
	assert_true("physical" in consumed,
		"CONTROL: \"physical\" is passed at BattleManager:4438 and :4896; if the scan cannot see those two it cannot see any")


func test_every_authored_immunity_has_a_consumer() -> void:
	var authored: Array[String] = _authored_categories()
	var consumed: Array[String] = _consumed_categories()
	var orphans: Array[String] = []
	for c in authored:
		if not (c in consumed):
			orphans.append(c)
	assert_eq(orphans, [],
		"a monster authors an immunity the engine never asks about, so it does nothing and the monster takes full damage while its data says otherwise. "
		+ "`%s` takes the category as a PARAMETER but every call site passes a literal — add a call site for the new category, or drop it from monsters.json: %s" % [FN, str(orphans)])


func test_the_scan_can_actually_fire() -> void:
	# Without this, "no orphans" is equally true of a regex that never matched anything.
	var re := RegEx.create_from_string(FN + "\\s*\\([^,)]+,\\s*\"([a-z_]+)\"")
	var fabricated: String = "\tif %s(target, \"zz_not_a_real_category\"):" % FN
	var hits: Array = re.search_all(fabricated)
	assert_eq(hits.size(), 1,
		"CONTROL: the call-site pattern must match a fabricated call, else it cannot detect a real one")
	assert_eq((hits[0] as RegExMatch).get_string(1), "zz_not_a_real_category",
		"CONTROL: and it must capture the CATEGORY, not the receiver — capturing the wrong group would make every category read as consumed")
