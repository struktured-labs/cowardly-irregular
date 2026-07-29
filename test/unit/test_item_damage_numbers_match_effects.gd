extends GutTest

## Item descriptions quote raw damage/heal numbers. The x10 stat re-denomination
## (ba9c06f5) scaled `effects` and left four descriptions behind, each stating
## exactly one tenth of the real value:
##
##   bomb_fragment   "Deals 100 fire damage"       damage 1000
##   arctic_wind     "Deals 80 ice damage"         damage  800
##   lightning_bolt  "Deals 120 lightning damage"  damage 1200
##   holy_water      "Deals 150 holy damage"       damage 1500
##
## Unlike setup_hint, this surface is LIVE: ItemsMenu.gd:332 assigns description
## straight to a label (control: 4 `name` reads in the same file). A player pricing
## a 150g Bomb Fragment against a 500 HP Potion was reading a tenfold understatement.
##
## ═══ WHY THIS RULE IS NARROW, ON PURPOSE ═══
##
## The obvious rule — "every number in a description must appear in the item's data"
## — was written, measured, and REJECTED at 20 false positives:
##
##   lore numbers      "Expired June 1987", "one(1) soul", "An 8-bit value"
##   decimals split    the integer regex reads "2.0" as 2 and 0
##   percent vs mult   "boosts attack by 25%" is stored as power: 1.25, not 25
##
## So this matches only SEMANTIC PAIRS, where the prose and the field are in the
## same denomination and no conversion is implied. It answers "does the quoted
## damage equal the dealt damage" and nothing else. The broad instrument was right
## for finding the x10 drift and wrong as a general honesty rule — an instrument's
## reach is scoped to the question it answered. (cowir-sfx msg 3365.)
##
## SCOPE, measured 2026-07-29: abilities.json yields ZERO pairs under this rule —
## ability prose says "deals heavy fire damage", not "deals 1200". It is deliberately
## not covered rather than covered vacuously; the floor control below is what keeps
## that honest for items.json.

const ITEMS := "res://data/items.json"

## desc pattern -> the effects key it must agree with.
const PAIRS := [
	["(?i)deals?\\s+(\\d+)\\s+\\w*\\s*damage", "damage"],
	["(?i)restores?\\s+(\\d+)\\s+hp", "heal_hp"],
	["(?i)restores?\\s+(\\d+)\\s+mp", "heal_mp"],
]


func _items() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(ITEMS))
	return d.get("items", d) if d is Dictionary else {}


## (quoted, actual, label) for every description that names a value the data also holds.
func _pairs() -> Array:
	var out: Array = []
	var items := _items()
	for k in items:
		var v = items[k]
		if not (v is Dictionary):
			continue
		var desc: String = str(v.get("description", ""))
		var eff = v.get("effects", {})
		if not (eff is Dictionary):
			continue
		for p in PAIRS:
			if not eff.has(p[1]):
				continue
			var re := RegEx.new()
			if re.compile(p[0]) != OK:
				continue
			var m := re.search(desc)
			if m == null:
				continue
			out.append([int(m.get_string(1)), int(eff[p[1]]), "%s (%s)" % [k, p[1]]])
	return out


## FLOOR. A broken regex or a failed parse finds zero pairs, and zero pairs agree
## perfectly — the guard would go green having compared nothing.
func test_control_pairs_are_found() -> void:
	assert_gt(_items().size(), 40, "items.json must parse with a real corpus")
	assert_gt(_pairs().size(), 7, "must find description/effect pairs to compare — 0 makes the "
		+ "check below vacuous rather than passing")


## THE GUARD.
func test_quoted_damage_equals_dealt_damage() -> void:
	var wrong: Array = []
	for p in _pairs():
		if p[0] != p[1]:
			wrong.append("%s: description says %d, data says %d" % [p[2], p[0], p[1]])
	assert_eq(wrong, [], "these item descriptions quote a number the item does not deliver, and "
		+ "ItemsMenu renders them verbatim while the player is deciding what to buy. The x10 "
		+ "re-denomination caused this once by scaling `effects` without the prose — if that is "
		+ "what happened again, fix the prose: %s" % [wrong])
