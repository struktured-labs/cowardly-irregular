extends GutTest

## A CURATIVE ITEM THAT CURES A STATUS NOTHING CAN INFLICT IS A 200-GOLD NO-OP, AND THE GAME SELLS ONE.
##
## `gold_needle` costs 200, is stocked by `VillageShop` (`:42`, the standard shelf) and is the reward
## in a Castle Harmonia chest (`castle_harmonia_f2_c4`). Its only effect is `cure_status: ["petrify"]`
## — and `petrify` appears in NO data file but `items.json`, and nowhere in `src/` except an icon
## list and a label map. Nothing in the game can petrify anybody, so the item cannot ever do
## anything. A player can buy it, carry it, use it, and get the animation with no effect.
##
## 🔑 This is the silent-failure class CLAUDE.md names: no error, no warning, a resolvable id and a
## clean suite. The three sibling curatives are the controls that make the finding mean something —
## antidote/poison, echo_herbs/silence and eye_drops/blind all resolve, so the derivation is not
## simply failing to find things.
##
## ⚠️ THE DERIVATION READS `src/` AS TEXT, so it goes through `GdSource` rather than a raw read. A
## commented-out `add_status("petrify")` would otherwise WIDEN the inflictable set and make this dead
## item read as live — the acceptance-widening direction, which is silent. Same hazard as
## test_a_window_status_brings_its_own_cue, and the reason that file pins its own strip.
##
## 📌 WHAT TO DO ABOUT `gold_needle` IS A DESIGN CALL, NOT THIS FILE'S: give something a petrify
## attack, drop it from the shelf and the chest, or leave it as authored-ahead content. Until that is
## ruled on, the exemption below carries the reason so it is visible instead of silent — and it reds
## from BOTH sides: a NEW uninflictable curative fails, and an exemption that has become live fails
## too, so wiring petrify forces the entry out rather than leaving a stale excuse behind.

## ⚠️ WHAT A GREEN HERE MEANS, because the inflictable set is a DELIBERATE OVER-APPROXIMATION: it
## counts every authored ability effect/secondary_effect name as a status that can land. Measured
## 2026-10-12 — 66 effect names, 23 of which are treated as a status anywhere in src and 43 of which
## are not. The set is ~43 names wider than reality, so this guard fails toward "no offender found",
## the direction that costs a defect. gold_needle cleared even the generous bar, which is what makes
## that finding strong rather than marginal.
##
## ⛔ THE TIGHTER RULE WAS MEASURED AND REJECTED, not overlooked. Requiring (effect AND status-ish)
## clears all three live curatives and still flags petrify — but `cure_status: ["attack_down"]` is a
## legitimate debuff cure, and attack_down sits in no status const and no has_status literal, so the
## tighter rule calls it DEAD. It trades a hypothetical false-clean for a plausible false alarm on a
## CORRECT change, which is the wrong side of that asymmetry.

const GdSource := preload("res://test/unit/helpers/gd_source.gd")

## id -> why it is allowed to cure something unreachable. A REASON, never a bare flag: this cannot be
## silenced green, only explained green.
const AUTHORED_AHEAD := {
	"gold_needle": "petrify has no source in the game: absent from every data file but items.json, and from src except AbilityIcons' icon list and ItemSystem's label map. Sold at 200g by VillageShop and chested at castle_harmonia_f2_c4, so it is a live purchase with no possible effect. Design call open (add a petrify source / unstock it / keep as authored-ahead).",
}


func _items() -> Dictionary:
	var text: String = FileAccess.get_file_as_string("res://data/items.json")
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var i: Variant = (parsed as Dictionary).get("items", parsed)
	return i if i is Dictionary else {}


## The statuses a given block of CODE can put on a combatant: an add_status string literal, or either
## side of a STATUS_ALIASES map. Takes the code as text so an arm can feed it a synthetic block —
## the live files carry no status named in a comment today, so the under-strip direction is NOT
## exercisable against them, and a stripper that stopped stripping would change nothing any arm could
## see. @cowir-autogrind measured that half on their own file within the hour.
func _literals_in(code: String) -> Dictionary:
	var out: Dictionary = {}
	var lit := RegEx.new()
	lit.compile("add_status\\(\\s*\"([a-z_]+)\"")
	for m in lit.search_all(code):
		out[m.get_string(1)] = true
	return out


## The src files that can apply a status, read through GdSource so prose is not input.
func _applier_code() -> String:
	var code: String = ""
	for f in ["res://src/battle/Combatant.gd", "res://src/battle/BattleManager.gd",
			"res://src/battle/EffectSystem.gd", "res://src/autogrind/HeadlessBattleResolver.gd",
			"res://src/items/ItemSystem.gd", "res://src/jobs/PassiveSystem.gd"]:
		code += "\n" + GdSource.code_of(f)
	return code


## Every status the game can actually inflict. Derived, never hand-listed.
func _inflictable() -> Dictionary:
	var out: Dictionary = _literals_in(_applier_code())
	## ALIASES COME FROM THE PARSED CONST, NOT FROM TEXT. @cowir-autogrind's prior step: a guard that
	## wants a const's MEMBERS does not need the source, and reading them as text buys a whole bug
	## class for nothing — an extraction anchored on a delimiter after the const NAME lands inside a
	## TYPE (`Array[String]`, `Dictionary[String, int]`). My own ad-hoc version of that read 0 names
	## and scored `poison` a non-status. Through the class the engine has already parsed it, so no
	## delimiter is searched and a commented alias pair cannot widen this either. Verified equivalent
	## to the text read it replaces: 5 pairs, 10 distinct names, same names.
	for k in Combatant.STATUS_ALIASES.keys():
		out[str(k)] = true
		out[str(Combatant.STATUS_ALIASES[k])] = true
	var text: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var abil: Variant = (parsed as Dictionary).get("abilities", parsed)
		if abil is Dictionary:
			for k in (abil as Dictionary).keys():
				var a: Variant = (abil as Dictionary)[k]
				if not (a is Dictionary):
					continue
				for key in ["effect", "secondary_effect"]:
					var e: String = str((a as Dictionary).get(key, ""))
					if e != "":
						out[e] = true
	return out


## BOTH DIRECTIONS OF THE STRIP, as standing arms rather than a plant. Either assertion alone is
## satisfied by a defect in the other direction: "a comment is not a source" survives a strip that ate
## everything, and "real code survives" survives a strip that never ran.
func test_the_strip_is_load_bearing_in_both_directions() -> void:
	## BOTH PROSE SHAPES, because they need different machinery: the `#` line pass handles one and only
	## the `"""` region parity handles the other. @cowir-autogrind measured that a guard asserting only
	## the `#` form stays green when the REGION split is dropped — GdSource's own documented `.325`
	## defect. Latent here rather than live (the applier corpus carries 360 `"""` fences and ZERO
	## docstrings naming add_status, measured), so this closes a surface rather than a bug.
	var prose: String = "func _x():\n\t## add_status(\"petrify\", 3)\n\tc.add_status(\"poison\", 2)\n"
	var doc: String = "func _y():\n\t\"\"\"\n\tadd_status(\"stoned\", 3)\n\t\"\"\"\n\tc.add_status(\"poison\", 2)\n"
	assert_true(_literals_in(prose).has("petrify"),
		"CONTROL: on RAW text the # -commented application IS counted — the hazard must be reproducible, or the arm below proves nothing")
	assert_true(_literals_in(doc).has("stoned"),
		"CONTROL: and the DOCSTRING one too, else the region half of this arm proves nothing")
	var stripped: Dictionary = _literals_in(str(GdSource.split(prose)["code"]))
	assert_false(stripped.has("petrify"),
		"UNDER-STRIP (# form): a status named only in a comment must not count as a source — else a dead curative reads as live")
	var stripped_doc: Dictionary = _literals_in(str(GdSource.split(doc)["code"]))
	assert_false(stripped_doc.has("stoned"),
		"UNDER-STRIP (\"\"\" form): a status named only in a DOCSTRING must not count either — a # -only pass leaves this standing")
	assert_true(stripped.has("poison"),
		"OVER-STRIP: the real add_status beside it must SURVIVE — a stripper that ate everything would satisfy the lines above")
	assert_true(stripped_doc.has("poison"),
		"OVER-STRIP (region form): and the code below a docstring must survive the region split")
	## AND THROUGH THE PRODUCTION ACCESSOR, not only the helper. The three asserts above feed
	## GdSource directly, so they certify the HELPER and stay green if _applier_code stops using it —
	## the helper-vs-caller gap three lanes hit tonight, reproduced here before it was noticed.
	var live: String = _applier_code()
	assert_false(live.is_empty(),
		"VACUITY FLOOR: the live accessor must return code at all — an empty read empties the inflictable set silently")
	var raw: String = FileAccess.get_file_as_string("res://src/battle/Combatant.gd")
	var raw_comments: int = 0
	for ln in raw.split("\n"):
		if ln.strip_edges().begins_with("#"):
			raw_comments += 1
	assert_gt(raw_comments, 0,
		"CONTROL: the raw applier source must carry comment lines, else a clean live strip proves nothing")
	var live_comments: int = 0
	for ln in live.split("\n"):
		if ln.strip_edges().begins_with("#"):
			live_comments += 1
	assert_eq(live_comments, 0,
		"the LIVE accessor must strip prose — %d comment lines survived, so a commented add_status would widen the inflictable set" % live_comments)
	## AND A FLOOR ON THE SRC HALF SPECIFICALLY. _inflictable() merges this with abilities.json's 66
	## effect names, so a TOTAL failure of the src extraction still clears any floor on the MERGED set.
	## Measured: an accessor returning one single line left the merged size above 40 and every arm
	## green — the clever over-strip @cowir-deploy reasoned about and @cowir-overworld measured. A floor
	## is only load-bearing on the half it sits on.
	var from_src: int = _literals_in(live).size()
	assert_gt(from_src, 10,
		"the src half must contribute real add_status literals (%d) — abilities.json alone masks its total failure" % from_src)


## CONTROL, must pass on BOTH trees: the derivation finds a real set AND the three living curatives
## resolve through it. Without this the offender arm below could pass for a broken derivation.
func test_control_the_derivation_sees_the_statuses_that_do_land() -> void:
	var inf: Dictionary = _inflictable()
	assert_gt(inf.size(), 40,
		"the inflictable set must be substantial (%d) — a near-empty one would call every curative dead" % inf.size())
	for pair in [["antidote", "poison"], ["echo_herbs", "silence"], ["eye_drops", "blind"]]:
		assert_true(inf.has(str(pair[1])),
			"%s cures %s and %s DOES land in game — if this fails the derivation is broken, not the item" % [pair[0], pair[1], pair[1]])


## THE GUARD. Every named cure target must be something the game can inflict, or carry a reason.
func test_every_curative_cures_a_status_that_can_happen() -> void:
	var inf: Dictionary = _inflictable()
	var items: Dictionary = _items()
	assert_false(items.is_empty(), "CONTROL: items.json must parse, else this arm checks nothing")
	var offenders: Array[String] = []
	var checked: int = 0
	for id in items.keys():
		var v: Variant = items[id]
		if not (v is Dictionary):
			continue
		var e: Variant = (v as Dictionary).get("effects", {})
		if not (e is Dictionary):
			continue
		for s in (e as Dictionary).get("cure_status", []):
			checked += 1
			if inf.has(str(s)):
				continue
			if AUTHORED_AHEAD.has(str(id)):
				continue
			offenders.append("%s cures '%s'" % [id, s])
	assert_gt(checked, 0, "CONTROL: at least one cure_status target must have been examined")
	assert_eq(offenders, [] as Array[String],
		"these items cure a status nothing in the game can inflict, so they are no-ops a player can buy: %s — either give the status a source or add it to AUTHORED_AHEAD with the reason" % str(offenders))


## The exemption cannot go stale. The moment something CAN inflict the status, the entry is a lie and
## must come out — so wiring petrify reds here instead of leaving a permanent excuse.
func test_no_authored_ahead_entry_has_quietly_come_alive() -> void:
	var inf: Dictionary = _inflictable()
	var items: Dictionary = _items()
	var alive: Array[String] = []
	for id in AUTHORED_AHEAD.keys():
		assert_true(items.has(str(id)),
			"AUTHORED_AHEAD names '%s', which is not an item any more — drop the entry" % id)
		assert_gt(str(AUTHORED_AHEAD[id]).length(), 40,
			"'%s' must carry a REASON, not a flag — an exemption you can tick is not an exemption" % id)
		var v: Variant = items.get(str(id), {})
		if not (v is Dictionary):
			continue
		var e: Variant = (v as Dictionary).get("effects", {})
		if not (e is Dictionary):
			continue
		for s in (e as Dictionary).get("cure_status", []):
			if inf.has(str(s)):
				alive.append("%s cures '%s', which now LANDS" % [id, s])
	assert_eq(alive, [] as Array[String],
		"an exemption has come alive and is now misleading: %s — remove the AUTHORED_AHEAD entry, the item is real content now" % str(alive))


## An exempted curative is still SOLD: the shelf must say it does nothing while the buyer is choosing.
func test_an_authored_ahead_curative_discloses_it_on_the_shelf() -> void:
	var items: Dictionary = _items()
	assert_false(AUTHORED_AHEAD.is_empty(), "no exemptions left — delete this arm with the table")
	for id in AUTHORED_AHEAD.keys():
		var v: Variant = items.get(str(id), {})
		var desc: String = str((v as Dictionary).get("description", "")) if v is Dictionary else ""
		assert_string_contains(desc, "(Currently no effect)",
			"'%s' is sold but cures nothing that can happen — its description must disclose that" % id)


## FLOOR: the symbols this file reaches on a runtime receiver. GdSource is a class_name const reached
## at parse time (a missing member exits 3, nothing ran), so it is deliberately not floored here.
func test_floor_the_symbols_this_file_drives_exist() -> void:
	assert_true(FileAccess.file_exists("res://data/items.json"), "items.json is this file's subject")
	assert_true(FileAccess.file_exists("res://data/abilities.json"), "abilities.json feeds the derivation")
	assert_false(_items().is_empty(), "the item table must be readable through this file's own accessor")
	assert_false(GdSource.code_of("res://src/battle/Combatant.gd").is_empty(),
		"the src accessor must return code — an empty read would empty the inflictable set silently")
