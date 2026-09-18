extends GutTest

const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const UI_PATH := "res://src/ui/autogrind/AutogrindUI.gd"

## The console's `member_status` ring offered `slow`, and a rule naming it could never fire.
## `member_status` is evaluated with `has_status`, which reads `status_effects`. The slowdown in this
## game is `masterite_slow` — authored `effect: debuff, stat: speed` — so it lands in
## `active_debuffs` instead. A player cycling the ring to that position wrote a dead rule, saved it,
## shared it as a COWIR1: code, and nothing said a word. Found by @cowir-ai.
##
## ⛔ THE GUARD THAT SHOULD HAVE CAUGHT IT NAMED ITS OWN WRONG CORPUS: the ring was validated against
## BattleScene's STATUS_ICON_CONFIG, which HAS a `slow` key — so the entry passed a check on whether
## the game can DISPLAY the status while failing whether anything can APPLY it. @cowir-battle's "the
## predicate is a corpus", in a comment that states the predicate out loud.
##
## ⚠️ THE INSTRUMENT MATTERS HERE AND MY FIRST ONE WAS USELESS: counting `add_status("poison")`
## literals returns ZERO for poison, which demonstrably works — statuses are applied through a
## VARIABLE (`add_status(status_to_add, …)`). A literal census over a composed writer is the shape
## this fleet has been retracting all night. This arm derives from the AUTHORED effect set instead.

## The rule side's own table, not a copy: this was a 2-entry snapshot and the applier had four.
## test_autogrind_a_rule_names_the_word_the_ability_uses_regression asserts it equals the
## applier's, so a stale copy here can no longer disagree with what actually lands.
const _ALIASES := Combatant.STATUS_ALIASES


func _authored_effects() -> Dictionary:
	var ab: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var out: Dictionary = {}
	for d in ab.values():
		for key in ["effect", "secondary_effect"]:
			var v: Variant = (d as Dictionary).get(key, "")
			if typeof(v) == TYPE_STRING and str(v) != "":
				out[str(v)] = true
	return out


func _ring() -> Array:
	var code: String = GdSource.code_of(UI_PATH)
	var at: int = code.find("const MEMBER_STATUS_RING")
	assert_gt(at, 0, "CONTROL: the ring must be locatable in AutogrindUI")
	var close: int = code.find("]", at)
	var out: Array = []
	for m in RegEx.create_from_string('"([a-z_]+)"').search_all(code.substr(at, close - at)):
		out.append(m.get_string(1))
	return out


func test_every_status_the_ring_offers_can_actually_be_applied() -> void:
	## THE RATCHET. A ring entry no ability authors is a rule a player can write and never fire.
	var effects: Dictionary = _authored_effects()
	assert_gt(effects.size(), 30, "CONTROL: abilities.json must yield a real effect set, or every hit below is vacuous")
	var ring: Array = _ring()
	assert_gt(ring.size(), 5, "CONTROL: the ring was actually parsed")
	var unreachable: Array = []
	for st in ring:
		if effects.has(st):
			continue
		## an alias counts: the resolver maps freeze -> stun and burn -> burning at apply time
		var aliased: bool = false
		for a in _ALIASES:
			if str(_ALIASES[a]) == str(st) and effects.has(a):
				aliased = true
		if not aliased:
			unreachable.append(st)
	gut.p("    ring: %d entries · authored effects: %d · unreachable: %s" % [ring.size(), effects.size(), str(unreachable)])
	assert_eq(unreachable, [],
		"the status ring offers a status no ability authors, so a player selecting it writes a rule that can never fire: %s" % str(unreachable))


func test_slow_is_a_debuff_not_a_status_and_stays_out() -> void:
	## Pins the specific fact rather than only the class, so a well-meaning re-add has to argue with
	## the reason instead of with an empty list.
	var ab: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var ms: Dictionary = ab.get("masterite_slow", {})
	assert_false(ms.is_empty(), "CONTROL: masterite_slow must still exist — it is the slowdown this arm is about")
	assert_eq(str(ms.get("effect", "")), "debuff",
		"masterite_slow is no longer authored as a debuff — if it now applies a STATUS, `slow` can go back in the ring")
	assert_eq(str(ms.get("stat", "")), "speed",
		"masterite_slow no longer targets the speed stat")
	assert_false(_ring().has("slow"),
		"`slow` is back in the status ring — it lands in active_debuffs via add_debuff(\"Slow\", …), and member_status reads status_effects through has_status")


func test_the_ring_is_not_validated_against_the_icon_table() -> void:
	## ⛔ THE CORPUS ARM. The previous guard checked BattleScene's STATUS_ICON_CONFIG, which contains
	## `slow`, so it certified displayability and called it applicability. Pinning the distinction so
	## the next reader does not re-adopt the wrong corpus — it is the cheaper of the two to reach for.
	var icons: String = GdSource.code_of("res://src/battle/BattleScene.gd")
	assert_gt(icons.length(), 10000, "CONTROL: BattleScene was actually read")
	assert_true(icons.contains('"slow": {"label": "SLOW"'),
		"STATUS_ICON_CONFIG no longer carries the dead `slow` icon — if it was removed, say so here; while it exists it is the corpus that certified a status nothing applies")
	var ui: String = GdSource.code_of(UI_PATH)
	assert_false(ui.contains("STATUS_ICON_CONFIG"),
		"AutogrindUI is validating its ring against the ICON table again — that corpus answers whether a status can be DRAWN, not whether anything can apply it")
