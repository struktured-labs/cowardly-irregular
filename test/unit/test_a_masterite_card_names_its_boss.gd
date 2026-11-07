extends GutTest

## A Masterite's boss card is the first thing the fight says. Three of them named someone else: the industrial
## Warden's card read "Warden of the Mainspring · Steampunk", the futuristic Arbiter's said "Industrial", and the
## abstract Curator's carried the digital Curator's name. Each card is derived here from the boss its scene triggers
## on: its name is the monster's own data name, its subtitle is that boss's world.

const CUTSCENES := "res://data/cutscenes/"
## monster theme suffix -> the subtitle's world word (masterites.md's phase table)
const THEME := {"medieval": "Medieval", "suburban": "Suburban", "steampunk": "Steampunk",
		"industrial": "Industrial", "futuristic": "Digital", "abstract": "Abstract"}


## [scene id, card name, card title, monster id] for every Masterite boss card on disk.
func _cards() -> Array:
	var monsters = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var out := []
	var re := RegEx.create_from_string("^boss_(warden|arbiter|tempo|curator)_([a-z]+)$")
	for f in DirAccess.get_files_at(CUTSCENES):
		if not f.ends_with(".json"):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(CUTSCENES + f))
		if not d is Dictionary:
			continue
		var trigger := str(d.get("trigger", ""))
		for step in d.get("steps", []):
			if not (step is Dictionary and str(step.get("type", "")) == "boss_intro" and str(step.get("title", "")).begins_with("Masterite")):
				continue
			var mid := ""
			if trigger == "boss_warden_encounter":
				mid = "masterite_warden_medieval"  # W1's Warden scene is named for its trigger point, not its theme
			else:
				var m := re.search(trigger)
				if m != null:
					mid = "masterite_%s_%s" % [m.get_string(1), m.get_string(2)]
			out.append([f.get_basename(), str(step.get("name", "")), str(step.get("title", "")), mid,
					str((monsters as Dictionary).get(mid, {}).get("name", "")) if monsters is Dictionary else ""])
	return out


func test_every_card_resolves_to_a_masterite() -> void:
	var cards := _cards()
	assert_gt(cards.size(), 23, "CONTROL: all 24 Masterite cards found (4 archetypes over 6 worlds)")
	var unresolved := []
	for c in cards:
		if c[4] == "":
			unresolved.append("%s (trigger resolves to '%s')" % [c[0], c[3]])
	assert_eq(unresolved, [], "every Masterite card's scene triggers on a Masterite in monsters.json")


func test_a_card_names_its_own_boss() -> void:
	var wrong := []
	for c in _cards():
		if c[4] != "" and c[1] != c[4]:
			wrong.append("%s: card says '%s', the boss is '%s'" % [c[0], c[1], c[4]])
	assert_eq(wrong, [], "a boss card names the boss its scene introduces")


func test_a_card_names_its_bosss_world() -> void:
	var wrong := []
	for c in _cards():
		var theme := str(c[3]).get_slice("_", 2)
		if THEME.has(theme) and c[2] != "Masterite — %s" % THEME[theme]:
			wrong.append("%s: card says '%s', the boss is %s" % [c[0], c[2], THEME[theme]])
	assert_eq(wrong, [], "a boss card's subtitle names the world its boss belongs to")
