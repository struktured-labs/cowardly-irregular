extends RefCounted
class_name W5Landmarks

## THE W5 landmark table: where each one stands, what it draws as, and what it says when pressed.
##
## Same contract as W1-W4Landmarks. Fifth world, same anti-feature: four terminals and racks drawn
## and none of them answered.
##
## The arc so far is people half-noticing one impossible thing about their own trade — W1's
## tradespeople that distance does not agree with itself, W2's municipal clerks that the suburb does
## not advance, W3's engineers that nothing wears out, W4's production clerks that the works makes
## more than it is given. **W5 is the first world where the DOCUMENTS ARE ABOUT THE PLAYER.** The
## Vigil's records system has been logging this run, and every page is a live read presented as its
## own telemetry: the intake record with one blank field, a retention shelf nobody can authorise a
## deletion from, a reconciliation whose two counts of you disagree, and a column of records with no
## subject. Nobody here is unsettled by the sprawl; they are unsettled by the gaps in the file.
##
## Providers are METHODS, not statics, so the Callable holds this object alive and a caller does not
## have to. Every one re-reads GameState on open — and here that is diegetic rather than decorative,
## because the thing doing the reading is a records system.

## cell is in MAP CELLS (x * MAP_SCALE * TILE_SIZE), the unit FuturisticOverworld authors in. All
## four are in `tools/gen_w5_futuristic.py`'s ENTITY_SPOTS, which reserves a clearing per cell —
## moving one regenerates the whole W5 map, so the cells are fixed here by construction.
func table() -> Array:
	return [
		{"cell": Vector2(15, 10), "type": Landmark.Type.DATA_TERMINAL, "name": "The Intake Record", "fn": "intake_record"},
		## ⛔ DRAWS, DOES NOT ANSWER, and the reason is measured rather than preferred. A readable here
		## steals TWO of `RootProcessEntrance`'s approach cells — (-1,1) and (1,1) — because a Mode 7
		## readable zone (128 x 1.67) covers the facing probe point where the entrance's own box does
		## not, so the press goes to the shelf at 170px over the entrance at 136. A WORLD TRANSITION
		## losing a press outranks a lore page, and the cell cannot move: it is reserved in
		## `tools/gen_w5_futuristic.py`'s ENTITY_SPOTS, so relocating it regenerates the W5 map.
		## Keeping the row keeps the drawn SERVER_RACK; `mute_reason` is what stops the readable.
		{"cell": Vector2(40, 35), "type": Landmark.Type.SERVER_RACK, "name": "The Retention Shelf", "fn": "",
			"mute_reason": "a readable here takes RootProcessEntrance's (-1,1) and (1,1) presses; a world transition outranks a page"},
		{"cell": Vector2(30, 20), "type": Landmark.Type.DATA_TERMINAL, "name": "The Reconciliation", "fn": "reconciliation"},
		{"cell": Vector2(25, 40), "type": Landmark.Type.SERVER_RACK, "name": "The Unclaimed Column", "fn": "unclaimed_column"},
	]


func _gs() -> Node:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("GameState")


## The system's record of your arrival. Complete, except for the field it cannot fill.
func intake_record() -> Array:
	var pages: Array = [
		"THE VIGIL — INTAKE TERMINAL\nRecord open. Subject present.\n\nThe screen is already showing your record when you reach it. Nothing was typed.",
		{"heading": "Fields", "body": "ARRIVED: yes\nROUTE: the portal, as expected\nPARTY: counted\nEQUIPMENT: itemised\nINTENT: —\n\nFour of five fields were filled before you stopped walking. The fifth has been blank on every record the Vigil holds."},
		{"heading": "On the blank field", "body": "The Vigil does not guess. A guessed field is worse than an empty one, because a later reader cannot tell them apart — that rule is older than this terminal and it is the only rule here anybody quotes.\n\nSo the column stands empty, in one hundred and six thousand records, and the Vigil considers this the honest outcome rather than a failure."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var secs: int = int(gs.playtime_seconds)
	var h: int = secs / 3600
	var m: int = (secs % 3600) / 60
	if secs < 3600:
		pages.append({"heading": "Elapsed, this record", "body": "%d minutes under observation.\n\nThe INTENT field remains blank. The terminal notes, in the margin where it keeps things it cannot file, that you have not done anything that would fill it, and that this is not the same as doing nothing." % m})
	else:
		pages.append({"heading": "Elapsed, this record", "body": "%d hours %d minutes under observation.\n\nThe INTENT field remains blank. The margin observes that longer records do not fill it — the field is not waiting for evidence, and the Vigil has stopped expecting the wait to end." % [h, m]})
	return pages


## Racks kept past any retention policy, because nobody can authorise a deletion.
func retention_shelf() -> Array:
	var pages: Array = [
		"RETENTION SHELF 9\nRecords held beyond schedule. Do not power down.\n\nRacks to the horizon, every indicator steady, and a laminated card at eye level with the policy on it.",
		{"heading": "The policy", "body": "Records are retained for the period of their usefulness, and are then DESTROYED on the authority of the officer who determined that period.\n\nNo officer is named on any record on this shelf. The field for it exists."},
		{"heading": "What follows from that", "body": "Nothing can be deleted, because deletion needs an authority that was never recorded, and the authority cannot be recorded retroactively without a record of who authorised THAT.\n\nThe shelf is not a hoard. It is a procedure with one missing signature, running correctly, for a very long time."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var keeps: int = gs.save_history.size() if gs.save_history is Array else 0
	if keeps <= 0:
		pages.append({"heading": "Your file", "body": "You have decided no moment was worth keeping.\n\nThe shelf has no opinion on that and files it anyway. The absence of a kept moment is itself a record, and it is retained under the same policy as every other."})
	else:
		pages.append({"heading": "Your file", "body": "You have decided %d moments were worth keeping.\n\nEach is retained. So is each one you decided was not. The shelf does not distinguish between what you chose to keep and what you chose to overwrite — both are events, and the policy is about events." % keeps})
	return pages


## Two counts of the same subject, from one system, that do not agree.
func reconciliation() -> Array:
	var pages: Array = [
		"RECONCILIATION TERMINAL\nComparing: SUBJECT LEDGER against EVENT LOG.\n\nThe screen is split. Both halves are the Vigil's own.",
		{"heading": "The discrepancy", "body": "The ledger counts what was done to the world. The log counts what the world recorded happening.\n\nThey have never matched. Not once, for any subject, in either direction consistently — the ledger runs high in some records and low in others, which rules out the one explanation anybody liked."},
		{"heading": "What has been ruled out", "body": "A miscount (both halves recount on demand, and agree with themselves). A clock (the drift is not time-ordered). A lost write (the gap closes and reopens).\n\nWhat is left is that the two halves are counting different worlds, and the terminal is not permitted to print that sentence, so it prints the numbers instead."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var won: int = int(gs.battles_won)
	var seen: Dictionary = gs.game_constants.get("seen_monsters", {}) if gs.game_constants.get("seen_monsters", {}) is Dictionary else {}
	pages.append({"heading": "This subject, now", "body": "LEDGER: %d resolved engagements\nLOG: %d kinds of thing catalogued\n\nThe terminal offers no relation between these two figures. It has been asked for one and has declined, on the grounds that inventing a relation is the only error it is actually able to make." % [won, seen.size()]})
	return pages


## A column of records with no subject, which the system keeps correctly.
func unclaimed_column() -> Array:
	var pages: Array = [
		"RACK 14 — UNCLAIMED\nRecords without a subject. Complete in every other field.\n\nThe indicators here are the same steady colour as everywhere else, which is the detail the shelf-keeper wanted written down.",
		{"heading": "What is in them", "body": "Arrival times. Routes. Party counts. Equipment. Outcomes.\n\nEvery field populated, to the standard the Vigil requires, and the SUBJECT field empty — not blank-because-unknown, which has its own marker, but empty in the way a field is empty before anything has ever been written in it."},
		{"heading": "The shelf-keeper's note", "body": "I have been asked whether these are errors. They are not: an error fails validation and these pass it. I have been asked whether they are tests. There is no test harness on this shelf.\n\nMy own reading, which is not a finding: somebody did all of this, correctly, and the column that says who is the one thing the Vigil never managed to keep."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var corruption: float = gs.corruption_level
	if corruption >= 0.35:
		pages.append({"heading": "Addendum, today", "body": "Four of the unclaimed records now carry a subject.\n\nIt is yours. The arrival times are not.\n\nI am writing this down and I am not raising it, because the form for raising it asks who observed the change."})
	elif corruption >= 0.15:
		pages.append({"heading": "Addendum, today", "body": "One of the unclaimed records has acquired a partial subject — three characters, then the field ends.\n\nThey match yours. I have checked twice and will not check a third time, because checking is an event and events are recorded."})
	else:
		pages.append({"heading": "Addendum, today", "body": "The column is unchanged. Every subject field still empty, every other field still complete.\n\nA quiet shelf is a correct shelf. I write that at the top of every shift and I have begun to notice I write it before I look."})
	return pages
