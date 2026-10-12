extends RefCounted
class_name W2Landmarks

## THE W2 landmark table: where each one stands, what it draws as, and what it says when pressed.
##
## Same contract as W1Landmarks and for the same reason — the Mundane Sprawl drew four pieces of
## street furniture and answered with none of them, which is the anti-feature W1 closed in .343: a
## player who presses the first two and gets nothing stops pressing, and every readable placed
## afterwards inherits that.
##
## W1's landmarks are tradespeople half-noticing that distance out there does not agree with itself.
## W2's are municipal paperwork half-noticing that the suburb does not advance. The hydrant tags are
## inspected on a schedule that never comes due, the bus is always four minutes away, and the route
## map's next stop is the stop you are standing at. Nobody files a complaint about any of it; they
## file complaints about parking.
##
## Providers are METHODS, not statics, so the Callable holds this object alive and a caller does not
## have to. Every one re-reads GameState on open — the pages are a live read.

## cell is in MAP CELLS (x * MAP_SCALE * TILE_SIZE), the unit SuburbanOverworld authors in.
func table() -> Array:
	return [
		{"cell": Vector2(25, 5), "type": Landmark.Type.FIRE_HYDRANT, "name": "The Inspection Tag", "fn": "inspection_tag"},
		{"cell": Vector2(40, 30), "type": Landmark.Type.BUS_STOP, "name": "The Timetable", "fn": "timetable"},
		{"cell": Vector2(10, 35), "type": Landmark.Type.FIRE_HYDRANT, "name": "The Taped Notice", "fn": "taped_notice"},
		{"cell": Vector2(35, 15), "type": Landmark.Type.BUS_STOP, "name": "The Route Map", "fn": "route_map"},
	]


func _gs() -> Node:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("GameState")


## A municipal inspection record whose schedule has never once come due.
func inspection_tag() -> Array:
	var pages: Array = [
		"MUNICIPAL WATER — HYDRANT 0041\nInspection tag. Do not remove.\nRemoval is a municipal offence. So is the condition of this tag.",
		{"heading": "Inspection record", "body": "PASSED — insp. R. Ott\nPASSED — insp. R. Ott\nPASSED — insp. R. Ott\nPASSED — insp. R. Ott\n\nFour inspections. Four passes. The dates column has been left blank on all four, in the same pen."},
		{"heading": "Reverse of the tag", "body": "NEXT INSPECTION DUE: 30 DAYS\n\nThe card is sun-bleached to the colour of the sidewalk. Whatever thirty days this is counting, it is not counting down."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var secs: int = int(gs.playtime_seconds)
	var m: int = secs / 60
	if m < 1:
		pages.append({"heading": "Checked, by you", "body": "You have been in this sprawl under a minute and the tag already says thirty days.\n\nIt will still say thirty days. That is not a prediction; it is the only thing it has ever said."})
	else:
		pages.append({"heading": "Checked, by you", "body": "You have been in this sprawl %d minutes.\n\nNEXT INSPECTION DUE: 30 DAYS.\n\nThe number on the card has not moved, and R. Ott has not been by." % m})
	return pages


## The bus is four minutes away. It has always been four minutes away.
func timetable() -> Array:
	var pages: Array = [
		"ROUTE 4 — SERVICE BOARD\nA laminated timetable behind scratched plastic, and beneath it a small amber display that is still working.",
		{"heading": "The board", "body": "NEXT SERVICE: 4 MIN\n\nThe laminate lists departures every eleven minutes from 06:04. It does not list a last service. The column where a last service would go has been trimmed off square, with scissors."},
		{"heading": "Taped beneath, laminated separately", "body": "TO PASSENGERS: the board is accurate.\n\nWe have received your enquiries. We have checked the board. The board is accurate. We are aware that this is not the same as the bus arriving, and we thank you for your patience, which we have also received."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var secs: int = int(gs.playtime_seconds)
	var h: int = secs / 3600
	var m: int = (secs % 3600) / 60
	if h > 0:
		pages.append({"heading": "The amber display, now", "body": "NEXT SERVICE: 4 MIN\n\nYou have been in this world %d hours and %d minutes. The display has said four the whole time.\n\nThe bench is worn in the middle, so somebody believed it for a long while." % [h, m]})
	else:
		pages.append({"heading": "The amber display, now", "body": "NEXT SERVICE: 4 MIN\n\nYou have been here %d minutes and it has said four for all of them. Four is not a countdown. Four is the display's opinion." % m})
	return pages


## The notice is municipal. Everything taped over it is not.
func taped_notice() -> Array:
	return [
		"HYDRANT 0058. A laminated municipal notice, and over it a geology of tape — four layers, each one a neighbour answering the layer beneath.",
		{"heading": "Layer one, municipal", "body": "NO PARKING WITHIN 15 FEET OF THIS HYDRANT.\nVehicles will be removed at the owner's expense."},
		{"heading": "Layer two, biro on lined paper", "body": "The silver estate car parks here EVERY evening. I have measured it. NINE FEET. I have the measurements. I have had the measurements for some time and nobody has asked me for them."},
		{"heading": "Layer three, marker on card", "body": "It is fifteen feet from the NEAR side. Measure from the near side. You are measuring from the wrong side and you have been for two years, Brian."},
		{"heading": "Layer four, printed, laminated, drilled and bolted through the other three", "body": "THE HYDRANT HAS NEVER BEEN USED.\n\nThere has not been a fire on this street. There is no record of a fire on this street. I have requested the record. There is no record because there is no fire, and I would like someone to sit with that before they measure anything else."},
		{"heading": "Layer five would go here", "body": "There is no layer five. The bolts through layer four are the good kind, and everybody seems to have accepted that as the end of it.\n\nThe silver estate car is parked nine feet away."},
	]


## The route is a loop with one stop on it, and the pen correction makes that worse.
func route_map() -> Array:
	var pages: Array = [
		"ROUTE 4 — SYSTEM MAP\nA diagram of the whole network, behind glass, at the shelter on the rise.",
		{"heading": "The map", "body": "The line is drawn as a closed loop. Around it, one stop is marked, and the marker is a small white circle with a dot in it.\n\nYou are at that stop. There are no others on the loop."},
		{"heading": "Legend", "body": "● you are here\n○ all other stops\n\nThe legend defines a symbol the map does not use."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var battles: int = int(gs.battles_won)
	if battles >= 1:
		pages.append({"heading": "In pen, lower right", "body": "Somebody has drawn a second stop on the loop, in biro, with an arrow to it reading HERE TOO.\n\nIt is drawn on the same point as the first. They have not made a mistake — there is only one point on this loop, and they have found a way to say so twice."})
	else:
		pages.append({"heading": "Lower right", "body": "The glass is clean and unmarked. Nobody has corrected this map.\n\nIt has been up long enough for the frame to rust, and nobody has corrected this map."})
	return pages
