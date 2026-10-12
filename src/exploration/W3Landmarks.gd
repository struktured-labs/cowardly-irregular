extends RefCounted
class_name W3Landmarks

## THE W3 landmark table: where each one stands, what it draws as, and what it says when pressed.
##
## Same contract as W1Landmarks and W2Landmarks, and for the same reason — the Clockwork Dominion
## drew four pieces of machinery and answered with none of them. A player who presses the first two
## and gets silence has been taught that overworld scenery is scenery, and every readable placed
## afterwards inherits that.
##
## W1's landmarks are tradespeople half-noticing that distance out there does not agree with itself.
## W2's are municipal paperwork half-noticing that the suburb does not advance. W3's are the
## Dominion's engineers half-noticing that NOTHING HERE WEARS OUT. The gauges do not drift, the
## teeth do not round off, the requisitions are delivered and never installed, and an apprenticeship
## that ends when you repair something cannot be completed. The guild's entire profession is
## bookkeeping about work it does not do, and every one of them is scrupulous about it.
##
## Providers are METHODS, not statics, so the Callable holds this object alive and a caller does not
## have to. Every one re-reads GameState on open — the pages are a live read.

## cell is in MAP CELLS (x * MAP_SCALE * TILE_SIZE), the unit SteampunkOverworld authors in. All
## four are in `tools/gen_w3_steampunk.py`'s ENTITY_SPOTS, which reserves a clearing per cell —
## moving one regenerates the whole W3 map, so the cells are fixed here by construction.
func table() -> Array:
	return [
		{"cell": Vector2(45, 8), "type": Landmark.Type.GEAR_PILE, "name": "The Spoil Heap", "fn": "spoil_heap"},
		{"cell": Vector2(15, 35), "type": Landmark.Type.STEAM_PIPE, "name": "The Standing Gauge", "fn": "standing_gauge"},
		{"cell": Vector2(30, 25), "type": Landmark.Type.GEAR_PILE, "name": "The Requisition Pile", "fn": "requisition_pile"},
		{"cell": Vector2(50, 20), "type": Landmark.Type.STEAM_PIPE, "name": "The Service Collar", "fn": "service_collar"},
	]


func _gs() -> Node:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("GameState")


## A discard heap of gears, every one of them unworn. Nothing was thrown out for being broken.
func spoil_heap() -> Array:
	var pages: Array = [
		"CLOCKWORK DOMINION\nSpoil heap, north works. Guild property.\n\nA waste pile the height of a man, and a slate hung on a post beside it for whoever is doing the counting.",
		{"heading": "On the contents", "body": "Four hundred and six gears. I have had every one in my hand.\n\nNot one is worn. No rounded teeth, no galling on the bores, no heat colour. These are not failed parts. They are parts that were taken out of machines that were running."},
		{"heading": "On why", "body": "The schedule says a gear comes out at ten thousand hours. The gear does not know about the schedule and will not cooperate with it.\n\nSo we pull a sound gear, we fit an identical sound gear, we sign the sheet, and the sheet is the only thing in the whole procedure that changed."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var gold: int = int(gs.get_gold())
	if gold >= 400:
		pages.append({"heading": "Valuation, appended", "body": "You are carrying %d.\n\nThe heap is worth rather more than that as metal, and the guild has never once sold it. A heap of good parts is an embarrassment you can stand next to; a sale is an admission with a price on it." % gold})
	else:
		pages.append({"heading": "Valuation, appended", "body": "You are carrying %d.\n\nTake some if you like. Everyone does. The slate has never been short, which I used to think meant nobody takes any, and now think means the count was never the point." % gold})
	return pages


## The one instrument in the Dominion that moves — and it does not move for pressure.
func standing_gauge() -> Array:
	var pages: Array = [
		"STANDPIPE 11 — PRESSURE\nA brass gauge at eye height, and bolted beneath it a reading book with a pencil on a string.",
		{"heading": "The book", "body": "Six readings a day, every day, in four hands.\n\nThe needle has stood at the same mark through all of them. The book is not a record of the pressure. The book is a record of six people a day looking at a needle that does not move and writing down that it did not move."},
		{"heading": "A later hand, pressing hard enough to score the page", "body": "I asked what we would do if it DID move.\n\nThe foreman said we would report it. I asked who to. He went and found out, and came back, and the answer is that the reporting line terminates at the office that sets the mark the needle is standing on."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var corruption: float = gs.corruption_level
	if corruption >= 0.35:
		pages.append({"heading": "Today's reading", "body": "The needle is off the mark.\n\nIt is not high and it is not low. It is off to one side of a dial that has only one axis, and I have stood here long enough to be sure of it.\n\nI am writing it in the book. The book has a column for the value and no column for this."})
	elif corruption >= 0.15:
		pages.append({"heading": "Today's reading", "body": "On the mark. The needle is on the mark.\n\nIt shivered once, very slightly, in no direction, and I have put the pencil down twice and picked it up twice and the column still only wants a number."})
	else:
		pages.append({"heading": "Today's reading", "body": "On the mark, as ever.\n\nA still needle is a working standpipe. I say that out loud at the gauge, daily, and I have begun to notice that I say it to the gauge rather than about it."})
	return pages


## Parts ordered, delivered, signed for, and never fitted, because nothing broke.
func requisition_pile() -> Array:
	return [
		"CENTRAL PLAZA — DELIVERY POINT\nCrated gearing under a tarpaulin, stacked three deep, with the manifests still nailed to the crates.",
		{"heading": "Manifest, topmost crate", "body": "ORDERED: 1 set, main drive, plaza orrery.\nDELIVERED: 1 set.\nFITTED: —\n\nThe FITTED line is blank on every manifest in the stack. I have checked forty-one of them. The forty-first is eleven years old and the tarpaulin over it is newer than my apprenticeship."},
		{"heading": "Why they were ordered", "body": "Because the schedule said so. Why they were not fitted: because the fitter opened the housing, looked at a drive in perfect order, and could not bring himself to do it.\n\nI want it on the record that forty-one fitters in a row made the same choice and not one of them wrote it down. Each of them left the line blank instead, which is the same decision, taken privately, forty-one times."},
		{"heading": "What the blank line costs", "body": "Nothing, is the answer, and that is the part worth sitting with.\n\nThe orrery has run the whole time. If the parts were needed, eleven years of blank lines would have shown as a stopped orrery, and the plaza would have noticed before the guild did. So the guild is not wrong about the machine. The guild is wrong about what it is FOR, and the crates are the shape of the difference."},
	]


## An apprenticeship that ends when you repair something, in a city where nothing breaks.
func service_collar() -> Array:
	var pages: Array = [
		"STANDPIPE 4 — SERVICE COLLAR\nA brass band riveted round the pipe, stamped in a ring with the marks of everyone who has serviced it.",
		{"heading": "The marks", "body": "Twenty-two marks, and room for more.\n\nThe guild's rule is that an apprentice strikes the collar when they complete their first repair. The collar is the certificate. There is no paper."},
		{"heading": "Scratched inside the collar, where it meets the pipe", "body": "None of us repaired anything.\n\nWe serviced it. We opened it, found it sound, closed it, and struck the collar, because the alternative was to tell the guild there is nothing wrong with Standpipe 4 and there never has been.\n\nTwenty-two of us. We each thought we were the first to do it. The inside of the collar is how we found out we were not."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var keeps: int = gs.save_history.size() if gs.save_history is Array else 0
	var won: int = int(gs.battles_won)
	if won <= 0 and keeps <= 0:
		pages.append({"heading": "Room for one more mark", "body": "Nothing behind you here yet.\n\nThe collar does not ask what you repaired. Twenty-two marks are the proof of that."})
	elif keeps <= 0:
		pages.append({"heading": "Room for one more mark", "body": "%d fights behind you and not one moment you decided was worth keeping.\n\nThe collar would have a view on that, if a collar could. Twenty-two people struck it to certify work they had not done; you have done the work and certified none of it." % won})
	else:
		pages.append({"heading": "Room for one more mark", "body": "%d fights behind you, and %d moments you decided were worth keeping.\n\nThat is a better ratio of work to record than anyone on this collar managed, and the collar is the city's instrument of record." % [won, keeps]})
	return pages
