extends RefCounted
class_name W1Landmarks

## THE W1 landmark table: where each one stands, what it draws as, and what it says when pressed.
##
## All three in one place on purpose. Cell and art type used to live in OverworldScene._place_
## landmarks() while the pages lived here, which is two sources feeding one surface — move the
## landmark, and its readable silently stays behind on the old cell with the label still promising
## a press. _place_landmarks() now reads this table.
##
## RUINS, CAMPFIRE, STONE_CIRCLE, WELL, STATUE — nine landmarks, and until the Survey Stone
## exactly zero of them could be pressed. That is not a missing feature so much as an anti-feature:
## a player who presses the first three and gets nothing has been TAUGHT that overworld scenery is
## scenery, and will walk past everything after it. The Survey Stone inherits that training.
##
## Each entry below is a different trade's encounter with the same anomaly the Survey Stone files:
## distance out here does not agree with itself. A salvage assessor meets it in stone that was
## never cut, a courier in a road that is half a day long depending who is paid for it, an
## expedition in a way back that is a third shorter than the way in. Nobody in W1 knows they are
## standing on a Mode 7 floor. They all know their numbers are wrong.
##
## Providers are METHODS, not statics, so the Callable holds this object alive and a caller does
## not have to. Every one re-reads GameState on open — the pages are a live read, like the Stone's.

## cell is in MAP CELLS (x * MAP_SCALE * TILE_SIZE), the unit OverworldScene authors in — the
## 2026-09 chest that landed 1680 px outside the world came from mixing these with PNG tiles.
func table() -> Array:
	return [
		{"cell": Vector2(29, 11), "type": Landmark.Type.RUINS, "name": "The Toppled Court", "fn": "toppled_court"},
		{"cell": Vector2(38, 22), "type": Landmark.Type.CAMPFIRE, "name": "The Crossroads Fire", "fn": "crossroads_fire"},
		{"cell": Vector2(68, 10), "type": Landmark.Type.STONE_CIRCLE, "name": "The Counting Stones", "fn": "counting_stones"},
		{"cell": Vector2(15, 24), "type": Landmark.Type.WELL, "name": "The Well Register", "fn": "well_register"},
		{"cell": Vector2(18, 13), "type": Landmark.Type.STATUE, "name": "The Recarved Plaque", "fn": "recarved_plaque"},
		{"cell": Vector2(20, 45), "type": Landmark.Type.CAMPFIRE, "name": "The Courier's Fire", "fn": "couriers_fire"},
		{"cell": Vector2(66, 47), "type": Landmark.Type.RUINS, "name": "The Last Camp", "fn": "last_camp"},
		{"cell": Vector2(38, 50), "type": Landmark.Type.STONE_CIRCLE, "name": "The Second Ring", "fn": "second_ring"},
	]


func _gs() -> Node:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).root.get_node_or_null("GameState")


## Northern forest ruin. The stone has no quarry marks, because nothing quarried it.
func toppled_court() -> Array:
	var pages: Array = [
		"SALVAGE ASSESSMENT\nNorth forest ruin, second visit.\n\nCommissioned by the Harmonia stonemasons' hall, who would like their columns back.",
		{"heading": "On the stone", "body": "No quarry marks. No chisel scars. No seams.\n\nA stone that was cut remembers the cutting. These do not. They are shaped the way a riverbed is shaped, which is to say by nothing, over no time, and very evenly."},
		{"heading": "On the collapse", "body": "I was asked which wall fell first. I have walked the debris four times.\n\nNothing fell. The rubble is where rubble goes — arranged the way a mason would arrange it if you asked a mason to build a ruin and he had never seen one."},
	]
	var seen: int = _seen_count()
	if seen > 0:
		pages.append({"heading": "Addendum, on the tenants", "body": "Since I opened this assessment I have catalogued %d kinds of thing living in the ruin.\n\nThe hall would like their columns. I would like the hall to consider what the columns are holding up." % seen})
	else:
		pages.append({"heading": "Addendum, on the tenants", "body": "Nothing living catalogued here yet, which the hall will read as good news.\n\nThe hall reads most things as good news. It is how they came to own a ruin."})
	return pages


func _seen_count() -> int:
	var gs := _gs()
	if gs == null:
		return 0
	var seen = gs.game_constants.get("seen_monsters", {})
	return seen.size() if seen is Dictionary else 0


## The central rest fire, and the flat stone every party that stops here writes one line on.
func crossroads_fire() -> Array:
	var pages: Array = [
		"A flat stone set by the fire, and on it, in a dozen hands, the log the crossroads keeps.\n\nThe custom is one line. Almost nobody manages one line.",
		{"heading": "Earlier hands", "body": "— Four of us east. Four of us back. Good road.\n\n— Three of us east.\n\n— Fire was lit when we arrived. Fire was lit when we left. We did not light it and we did not put it out and we would like that on the stone."},
		{"heading": "A careful hand, lower down", "body": "Eleven years on this road. I have never found this fire out, I have never found anyone tending it, and I have stopped raising it at the hall because of how they look at me.\n\nIt is a GOOD fire. That is the trouble. A neglected fire is a mystery. A well-kept one is a person you have not met."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var won: int = int(gs.battles_won)
	var standing: int = 0
	for m in gs.player_party:
		if m is Dictionary and int(m.get("current_hp", 1)) > 0:
			standing += 1
	if won <= 0:
		pages.append({"heading": "The next line is yours", "body": "Nothing behind you yet.\n\nThe stone has room, and the road east is long enough to fill it."})
	else:
		pages.append({"heading": "The next line is yours", "body": "%d fights behind you. %d of you still upright.\n\nThe stone has room. It has always had room, which is the other thing about this fire nobody wants to say out loud." % [won, standing]})
	return pages


## Eight stones in a bog that will not hold a fence post. The count is the vigil.
func counting_stones() -> Array:
	var pages: Array = [
		"Eight stones, set in a ring, in a bog that will not hold a fence post upright for one winter.",
		{"heading": "The Third Warden's count", "body": "Eight. Eight. Eight. Eight. Eight.\n\nI write the count every morning because the Second Warden did not, and the First Warden's notes end in the middle of a word, and I would like my successor to inherit something better than a half-written word."},
	]
	var gs := _gs()
	var corruption: float = gs.corruption_level if gs != null else 0.0
	if corruption >= 0.35:
		pages.append({"heading": "This morning", "body": "Nine.\n\nI counted four times and it was nine four times, and then it was eight, and the eight did not arrive like a correction.\n\nIt arrived like being agreed with."})
	elif corruption >= 0.15:
		pages.append({"heading": "This morning", "body": "Eight.\n\nI counted nine once, in poor light, and did not write it down, and have thought about very little else since."})
	else:
		pages.append({"heading": "This morning", "body": "Eight, still.\n\nA boring vigil is a successful one. I remind myself of this at the ring, out loud, where the ring can hear it."})
	pages.append({"heading": "On what it is for", "body": "It is not a calendar and not a grave; I have checked both, thoroughly, and the village has not forgiven me for the second one.\n\nIt is a ring of stones in a bog. Nobody accepts that answer, because they have all counted it themselves, and they all got eight."})
	return pages


## The parish well: one coin, one wish, and a register that only audits one side of that.
func well_register() -> Array:
	var pages: Array = [
		"HARMONIA PARISH\nWell and Wish Register\n\nKept since the well was dug. Copied twice; the second copyist was in a hurry.",
		{"heading": "The rate", "body": "One coin, one wish. The parish sets the rate. The well has never been consulted about the rate.\n\nOf two thousand one hundred and forty wishes registered, the parish can confirm two thousand one hundred and forty coins. Confirmation of the other half of the transaction is ongoing."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var gold: int = int(gs.get_gold())
	if gold >= 1000:
		pages.append({"heading": "Note on the carrier", "body": "You are carrying %d.\n\nThe register observes, without comment and in a different ink, that in eleven generations it has not once recorded a wish from anyone carrying that much." % gold})
	else:
		pages.append({"heading": "Note on the carrier", "body": "You are carrying %d.\n\nThe register observes that the well has never refused anyone on the grounds of the amount, and that this is the only institution in the parish of which that is true." % gold})
	var keeps: int = gs.save_history.size() if gs.save_history is Array else 0
	if keeps <= 0:
		pages.append({"heading": "The well's second use", "body": "The parish does not advertise it, but this is also where people come to decide a moment is worth keeping.\n\nYou have not done that yet. The parish would gently raise the cave."})
	else:
		pages.append({"heading": "The well's second use", "body": "The parish does not advertise it, but this is also where people come to decide a moment is worth keeping.\n\nYou have decided that %d times. The register does not rank people by the number. The register is, however, the only thing here that isn't counting it." % keeps})
	return pages


## The plaque on the north-bridge statue. The stone is old. The letters never are.
func recarved_plaque() -> Array:
	var pages: Array = [
		"A figure in grey stone on a pedestal at the north bridge. Weathered on three sides.\n\nThe fourth side is the plaque, and the plaque is not weathered at all.",
		{"heading": "The plaque", "body": "The stone beneath the letters is exactly as old as the rest of the monument. The LETTERS are new.\n\nThey have been new every time anyone has thought to check, going back as far as anyone has thought to check, which the bridge-keeper points out is not very far, and is not nothing either."},
	]
	var gs := _gs()
	var who: String = ""
	if gs != null:
		var leader = gs.get_party_leader()
		if leader is Dictionary:
			who = str(leader.get("name", ""))
	if who == "":
		pages.append({"heading": "Currently reading", "body": "The letters are there. Reading them takes longer than it ought to, and afterwards nobody can say what they said."})
	else:
		pages.append({"heading": "Currently reading", "body": "\"%s\"\n\nThat is what it says today. The bridge-keeper's log records four other names in nine years, and is adamant that each one was, at the time, obviously correct — that it did not read as a stranger's name, and that nobody thought to wonder until afterwards." % who})
	pages.append({"heading": "The bridge-keeper's own note", "body": "I have stopped bringing visitors to it.\n\nThey read the plaque and they are pleased, every single one of them, and I have never once got any of them to tell me what they are pleased about."})
	return pages


## The desert road fire: wood for one night, counted, by someone paid for half a journey.
func couriers_fire() -> Array:
	var pages: Array = [
		"A fire ring on the desert road, swept clean, with wood stacked to one side in a quantity somebody has plainly calculated rather than guessed.",
		{"heading": "Courier's post, for the next courier", "body": "Wood for one night. Take it. Leave the same.\n\nIf you leave more I will know, because I count it. If you leave less I will know that too, and I will still leave you wood, and we will both know."},
		{"heading": "On the run", "body": "Harmonia to Sandrift is a day and a half if you are honest about it. The hall pays for one day.\n\nEvery courier on this road has made their peace with that in their own way. Mine is this fire, which is exactly half."},
	]
	var gs := _gs()
	if gs == null:
		return pages
	var secs: int = int(gs.playtime_seconds)
	var h: int = secs / 3600
	var m: int = (secs % 3600) / 60
	if secs < 3600:
		pages.append({"heading": "For whoever is reading", "body": "You have been out here %d minutes by my reckoning.\n\nThat is very good time, or you have not gone far. Out here those are the same sentence and I have given up trying to separate them." % m})
	else:
		pages.append({"heading": "For whoever is reading", "body": "You have been out here %d hours and %d minutes by my reckoning.\n\nI have never met a traveller who agreed with my reckoning. I have never met one who could produce a better one, either." % [h, m]})
	return pages


## The fourth party's notice, posted on the last wall before the grotto.
func last_camp() -> Array:
	var pages: Array = [
		"A stone wall, waist high, three sides of a square. The fourth side faces the grotto.\n\nSomeone has scratched a notice into the inside face, where the wind cannot reach it.",
		{"heading": "The notice", "body": "TO ANYONE FOLLOWING.\n\nWe are the fourth party. The first three left notices as well; you are standing on them.\n\nRead this one. Add yours underneath. Then go in, because you are going to go in."},
		{"heading": "Lower down, and smaller", "body": "The heat is not the problem. The heat is honest.\n\nThe problem is that the way back is shorter than the way in. Every time. By about a third. Nobody in the party will say it out loud, so I am writing it down, because I am the one who keeps the notes."},
	]
	var gs := _gs()
	var burned: bool = gs != null and (gs.get_story_flag("fire_dragon_defeated") or gs.is_story_flag_set("fire_dragon_defeated"))
	if burned:
		pages.append({"heading": "Added in a fresh hand", "body": "Fifth party. In, and out.\n\nThe way back was shorter. It is always going to be shorter.\n\nWe are writing it down so the sixth party does not have to find it out with their own legs."})
	else:
		pages.append({"heading": "Beneath the notice", "body": "There is room under the notice.\n\nThere has been room under the notice for a long time."})
	return pages


## The bridge ring — the same ring as the bog ring, and the Survey's least popular finding.
func second_ring() -> Array:
	return [
		"Eight stones, set in a ring, on good dry ground beside the bridge, where anyone can see them and very nearly everyone walks past.",
		{"heading": "Royal Survey, cross-reference", "body": "This ring and the ring in the northern bog are the same ring.\n\nNot alike. Not of a type. I have measured both: eight stones, heights matching to the inch, same lean, same chip out of the north-east stone.\n\nThirty chains apart, and no road between them."},
		{"heading": "The office's reply, in full", "body": "\"Noted. Please confirm you did not measure the same ring twice.\"\n\nI did not measure the same ring twice.\n\nI would like that entered as a finding rather than as a reassurance."},
		{"heading": "On the cheap answer", "body": "The cheap answer is that one was copied from the other.\n\nI invite the office to consider who would do that, and how, and at what hour, and then to consider the expensive answer: that nobody copied anything, that there was only ever one ring, and that we have been counting the world wrong."},
	]
