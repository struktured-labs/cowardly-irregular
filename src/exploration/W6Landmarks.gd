extends RefCounted
class_name W6Landmarks

## THE W6 landmark table — the last three, and the ones with no author.
##
## Five worlds of documents, each written by somebody half-noticing one impossible thing about their
## own trade: W1's tradespeople that distance does not agree with itself, W2's municipal clerks that
## the suburb does not advance, W3's engineers that nothing wears out, W4's production clerks that
## the works makes more than it is given, W5's records system that its own two counts of you
## disagree. Every one of those has a voice, a hand, a post, a shift.
##
## 🔑 W6'S DO NOT. The void crystals carry text in the register the other five taught the player to
## read — fields, addenda, marginal notes — and nobody is writing it. There is no surveyor, no
## clerk, no shelf-keeper, no post for a successor to inherit. The last world is where the
## documents continue and the authors stop, which is the only thing left that the previous five
## were all, in their different trades, circling.
##
## ⚠️ So these three deliberately do NOT invent a narrator to be eerie with. The first five earned
## their unease by having someone competent notice something they could not file; a sixth voice
## saying "I am the void" would undo all of it. What is left is the FORM — a record with every field
## in place and no hand — and the player's own file read back without a reader.
##
## Providers are METHODS, not statics, so the Callable holds this object alive and a caller does not
## have to. Every one re-reads GameState on open.

## cell is in MAP CELLS (x * MAP_SCALE * TILE_SIZE), the unit AbstractOverworld authors in. All
## three are in `tools/gen_w6_abstract.py`'s ENTITY_SPOTS, which reserves a clearing per cell —
## moving one regenerates the whole W6 map, so the cells are fixed here by construction.
## THREE, not four: W6 draws three crystals and this table does not invent a fourth.
func table() -> Array:
	return [
		{"cell": Vector2(20, 10), "type": Landmark.Type.VOID_CRYSTAL, "name": "The Unsigned Page", "fn": "unsigned_page"},
		{"cell": Vector2(15, 25), "type": Landmark.Type.VOID_CRYSTAL, "name": "The Repeated Line", "fn": "repeated_line"},
		{"cell": Vector2(25, 18), "type": Landmark.Type.VOID_CRYSTAL, "name": "The Reader's Column", "fn": "readers_column"},
	]


func _gs() -> Node:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("GameState")


## The form of a record, complete, with the one field the other five worlds always filled.
func unsigned_page() -> Array:
	var pages: Array = [
		"A page, held in the crystal at reading height.\n\nThe layout is familiar by now: a header, fields, an addendum, a space at the foot for the hand that wrote it.",
		{"heading": "Fields", "body": "SUBJECT: present\nROUTE: five worlds, in order\nOUTSTANDING: nothing\n\nEvery field populated. The space at the foot is not empty the way the Vigil's unclaimed column was empty. It has no RULE for a signature. The line was never drawn."},
		{"heading": "Addendum", "body": "The Survey wrote that it would like a finding entered rather than a reassurance. The parish wrote that the well had never refused anyone. The guild wrote that forty-one fitters in a row made the same choice and none wrote it down.\n\nAll of that is here, verbatim, in a hand that is not any of theirs."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var won: int = int(gs.battles_won)
	if won <= 0:
		pages.append({"heading": "OUTSTANDING, reconsidered", "body": "Nothing behind you. The field still reads `nothing`, which it would also read if there were something.\n\nThat is the property the first five worlds kept failing to write down: a field that cannot be wrong is not a measurement."})
	else:
		pages.append({"heading": "OUTSTANDING, reconsidered", "body": "%d resolved behind you, and the field still reads `nothing`.\n\nIt read `nothing` before them too. The first five worlds each had one instrument like this and each had somebody who noticed; there is nobody here, and the instrument is the same." % won})
	return pages


## One line, repeated, in the register of a successor's post that does not exist.
func repeated_line() -> Array:
	var pages: Array = [
		"The second crystal holds a register. Ruled columns, a date column, and one line entered over and over down the length of it.",
		{"heading": "The line", "body": "COUNT HOLDS.\nCOUNT HOLDS.\nCOUNT HOLDS.\nCOUNT HOLDS.\n\nThe date column is ruled and empty, which the Third Warden of the Counting Stones would recognise: she wrote her count every morning because the Second Warden did not, and because the First Warden's notes end in the middle of a word."},
		{"heading": "What the register is for", "body": "A vigil is kept so that a successor inherits something better than a half-written word. That is the whole argument, and it is a good one.\n\nThis register has no successor column. Nothing here is being handed to anybody. The line is entered because the line is entered."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var corruption: float = gs.corruption_level
	if corruption >= 0.35:
		pages.append({"heading": "The current line", "body": "COUNT DOES NOT HOLD.\n\nIt is written in the same hand as the others, at the same spacing, with no marginal note and nothing after it.\n\nThe bog warden got nine and thought about very little else. There is no sentence here about having thought about it."})
	elif corruption >= 0.15:
		pages.append({"heading": "The current line", "body": "COUNT HOLDS.\n\nThe entry above it is fainter than the rest and the one above that is fainter still, which is either an old register or a record of something losing confidence."})
	else:
		pages.append({"heading": "The current line", "body": "COUNT HOLDS.\n\nA boring vigil is a successful one — the warden said that out loud at the ring, daily, and noticed she was saying it TO the ring rather than about it.\n\nThere is nothing here to say it to."})
	return pages


## The last one, and the only field the previous five never had.
func readers_column() -> Array:
	var pages: Array = [
		"The third crystal is ruled into two columns. The left is full. The right is headed and empty.",
		{"heading": "The left column", "body": "Everything above. The assessment with no quarry marks, the stone that keeps the crossroads log, the eight stones in a bog, the tag whose thirty days never came due, the board that has said four minutes for as long as the bench has been worn, the collar struck twenty-two times for repairs nobody made, the yard that grows every minute, the column of records with no subject.\n\nFiled, in order, complete."},
		{"heading": "The right column", "body": "READER.\n\nThe header is the only text in it. The rule lines run the full height, so the column was drawn to be filled."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var who: String = ""
	var leader = gs.get_party_leader()
	if leader is Dictionary:
		who = str(leader.get("name", ""))
	var secs: int = int(gs.playtime_seconds)
	var h: int = secs / 3600
	if who == "":
		pages.append({"heading": "The right column, now", "body": "Still only the header.\n\nEvery document in the left column was written by somebody who could be named, and each of them wanted their finding entered rather than their reassurance. None of them had this column."})
	else:
		pages.append({"heading": "The right column, now", "body": "\"%s\", and beneath it the figure %d.\n\nThat is hours. It is the only entry in the column and it was not there before you reached the crystal.\n\nThe plaque at the north bridge read a name today too, and the bridge-keeper's log records four others in nine years, each obviously correct at the time, and nobody thought to wonder until afterwards." % [who, h]})
	return pages
