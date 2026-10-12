extends RefCounted
class_name W4Landmarks

## THE W4 landmark table: where each one stands, what it draws as, and what it says when pressed.
##
## Same contract as W1/W2/W3Landmarks, and for the same reason — the Combine drew four pieces of
## plant and answered with none of them. A player who presses the first two and gets silence has
## been taught that overworld scenery is scenery, and every readable placed afterwards inherits it.
##
## W1's landmarks are tradespeople half-noticing that distance does not agree with itself. W2's are
## municipal paperwork half-noticing that the suburb does not advance. W3's are engineers
## half-noticing that nothing wears out. W4's are PRODUCTION CLERKS half-noticing that the works
## makes more than it is given: a stack that smokes with nothing burning, a yield board that beats
## the input ledger every quarter, a shift roster signed for labour nobody performed, and a surplus
## nobody ordered, stacked in the yard because stopping would require a person to decide to stop.
## They are not frightened by it. They are behind on the paperwork it generates.
##
## Providers are METHODS, not statics, so the Callable holds this object alive and a caller does not
## have to. Every one re-reads GameState on open — the pages are a live read.

## cell is in MAP CELLS (x * MAP_SCALE * TILE_SIZE), the unit IndustrialOverworld authors in. All
## four are in `tools/gen_w4_industrial.py`'s ENTITY_SPOTS, which reserves a clearing per cell —
## moving one regenerates the whole W4 map, so the cells are fixed here by construction.
func table() -> Array:
	return [
		{"cell": Vector2(20, 10), "type": Landmark.Type.SMOKESTACK, "name": "The Emission Log", "fn": "emission_log"},
		{"cell": Vector2(45, 30), "type": Landmark.Type.BARREL_STACK, "name": "The Yield Board", "fn": "yield_board"},
		{"cell": Vector2(10, 35), "type": Landmark.Type.SMOKESTACK, "name": "The Shift Roster", "fn": "shift_roster"},
		{"cell": Vector2(30, 20), "type": Landmark.Type.BARREL_STACK, "name": "The Overrun", "fn": "overrun"},
	]


func _gs() -> Node:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("GameState")


## A stack that smokes, and a fuel ledger recording deliveries that were never made.
func emission_log() -> Array:
	var pages: Array = [
		"COMBINE WORKS — STACK 2\nEmission log. Readings hourly, in ink, no erasures.\n\nA clerk's hut at the base, the hut's window facing the stack so you can take the reading sitting down.",
		{"heading": "The readings", "body": "Grey, light. Grey, light. Grey, light.\n\nNine thousand entries in that column and four distinct words used across all of them. I have read back three years and the stack has never once been clear and never once been black."},
		{"heading": "The fuel side of the ledger", "body": "Coal in, by the ton, signed for at the gate.\n\nI am the one who signs. Nothing has come through the gate in my time here. The column is not blank, because a blank column is a question somebody answers, and the figure I enter is the figure that makes the stack's output balance."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var won: int = int(gs.battles_won)
	if won <= 0:
		pages.append({"heading": "Note for my relief", "body": "Nothing has happened on my shift.\n\nThat is the whole report. It is also every report in the drawer, and the drawer is full, and the stack is still smoking."})
	else:
		pages.append({"heading": "Note for my relief", "body": "%d incidents out on the floor this period, which is %d more than the stack has had.\n\nI record the stack. The floor has its own clerk. We have never been asked to reconcile, and I have stopped offering." % [won, won]})
	return pages


## Output exceeds input, every quarter, and the reconciliation is the job.
func yield_board() -> Array:
	var pages: Array = [
		"YARD BOARD — QUARTERLY YIELD\nA painted board, the figures chalked over so many times the slate beneath is grey-white and soft.",
		{"heading": "This quarter", "body": "IN:   nine hundred\nOUT: one thousand one hundred and forty\n\nThe board does not have a column for the difference. The difference is two hundred and forty and it has been positive every quarter the board has existed."},
		{"heading": "From the reconciliation file", "body": "I am required to account for the surplus. I have accounted for it eleven times, in writing, and every account is a different story told to the same figure.\n\nSpillage recovered. Reclassified stock. A counting error at the gate, then a counting error at the gate again, then a counting error at the gate a third time. The file is a record of my imagination, not of the works."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var gold: int = int(gs.get_gold())
	if gold >= 600:
		pages.append({"heading": "Appended, in a different hand", "body": "The bearer is carrying %d.\n\nThe board notes, with no column for it, that the works has never paid anyone that. The surplus does not leave the yard as money. It does not leave the yard at all." % gold})
	else:
		pages.append({"heading": "Appended, in a different hand", "body": "The bearer is carrying %d.\n\nLess than one quarter's difference. The surplus has never been anybody's wage, and it is stacked forty feet from this board where anyone could take it, and the stack only grows." % gold})
	return pages


## A roster signed for shifts nobody worked, kept because the form requires a signature.
func shift_roster() -> Array:
	var pages: Array = [
		"CHEMICAL ROW — SHIFT ROSTER\nA steel frame under glass, a card for each name, and a pencil chained to the frame that has not been sharpened in a long time.",
		{"heading": "The cards", "body": "Forty-one names. Every card signed in and signed out, every shift, three shifts a day.\n\nI have worked this row eighteen months. I have met nine of the forty-one. The other thirty-two sign in before me and out after me and I have come in early twice to see it happen, and both times the cards were already signed."},
		{"heading": "Why the roster is kept", "body": "Because the plant will not release product without a signed shift. That is the whole mechanism. The row runs itself and the product will not leave until a person has written a name beside it.\n\nSo someone writes forty-one names. I think it is one of us. I think it has been one of us for a long time and that whoever it is believes they are the only one doing it, and I have not asked, because I sign nine of them myself."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var who: String = ""
	var standing: int = 0
	var leader = gs.get_party_leader()
	if leader is Dictionary:
		who = str(leader.get("name", ""))
	for m in gs.party_for_queries():
		if m is Dictionary and int(m.get("current_hp", 1)) > 0:
			standing += 1
	if who == "":
		pages.append({"heading": "Blank cards at the bottom of the frame", "body": "There are always blank cards. The frame was built with room, which tells you what the works expected of itself."})
	else:
		pages.append({"heading": "Blank cards at the bottom of the frame", "body": "There are blank cards, and a pencil on a chain, and nobody here would stop you.\n\n\"%s\" would fit. So would the %d of you still on your feet. The roster has never checked whether a name belongs to anyone — that is not what it is for." % [who, standing]})
	return pages


## Surplus with nowhere to go, stacked because stopping needs a decision nobody is assigned.
func overrun() -> Array:
	var pages: Array = [
		"OVERRUN YARD — NO ORDER AGAINST THIS STOCK\nBarrels stacked five high in rows, with lanes between them wide enough for a cart that never comes.",
		{"heading": "The tag on the nearest row", "body": "PRODUCED: to schedule.\nORDERED: —\nDESTINATION: —\n\nThe schedule is met. There is no order. Both of those are true at once and the yard is the shape of them being true at once."},
		{"heading": "The shift supervisor's standing note", "body": "I have asked who can stop a line. The answer is that a line is stopped by the authority that started it, and the authority that started these lines is a schedule, and a schedule is not an office you can walk to.\n\nI can slow a line. I have slowed this one. The yard grew anyway, more slowly, which everyone treated as a success and which I would like to record was not one."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var secs: int = int(gs.playtime_seconds)
	var h: int = secs / 3600
	var m: int = (secs % 3600) / 60
	if secs < 3600:
		pages.append({"heading": "Rate, for whoever reads this next", "body": "You have been in these works %d minutes.\n\nThe yard has grown in that time. Not by much. It does not need to be by much; it only needs to be every minute, and it is." % m})
	else:
		pages.append({"heading": "Rate, for whoever reads this next", "body": "You have been in these works %d hours and %d minutes.\n\nThe yard has grown for every one of them, and will have grown by the time you reach the gate. I am not telling you this to alarm you. I am telling you because I am the only person who writes it down." % [h, m]})
	return pages
