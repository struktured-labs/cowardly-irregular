extends RefCounted
class_name CharacterCustomization

## CharacterCustomization - Data class for character appearance and personality

## Eye shape options (like FF1-5)
enum EyeShape {
	NORMAL,
	NARROW,
	WIDE,
	CLOSED
}

## Eyebrow style options
enum EyebrowStyle {
	NORMAL,
	THICK,
	THIN,
	ARCHED
}

## Nose shape options
enum NoseShape {
	NORMAL,
	SMALL,
	POINTED,
	BROAD
}

## Mouth/Expression options
enum MouthStyle {
	NEUTRAL,
	SMILE,
	FROWN,
	SMIRK
}

## Hair style options
enum HairStyle {
	SHORT,
	LONG,
	SPIKY,
	BRAIDED,
	PONYTAIL,
	MOHAWK
}

## Personality options (affects starting stats and item)
enum Personality {
	BRAVE,       # +2 ATK, starts with power_drink
	CAUTIOUS,    # +2 DEF, starts with extra potions
	SCHOLARLY,   # +2 MAG, starts with ether
	QUICK,       # +2 SPD, starts with speed_tonic
	CHARISMATIC  # +2 MAG +1 SPD, starts with party_bell
}

## Skin tone presets
const SKIN_TONES: Array[Color] = [
	Color(0.96, 0.87, 0.78),  # Light
	Color(0.91, 0.78, 0.65),  # Fair
	Color(0.78, 0.60, 0.45),  # Medium
	Color(0.62, 0.45, 0.35),  # Tan
	Color(0.45, 0.32, 0.25),  # Dark
]

## Hair color presets
const HAIR_COLORS: Array[Color] = [
	Color(0.15, 0.12, 0.10),  # Black
	Color(0.45, 0.30, 0.18),  # Brown
	Color(0.85, 0.65, 0.35),  # Blonde
	Color(0.65, 0.25, 0.15),  # Red
	Color(0.55, 0.55, 0.60),  # Gray/Silver
	Color(0.30, 0.45, 0.80),  # Blue (fantasy)
	Color(0.45, 0.75, 0.35),  # Green (fantasy)
	Color(0.80, 0.40, 0.70),  # Pink (fantasy)
]

## Character data
var name: String = ""
var eye_shape: EyeShape = EyeShape.NORMAL
var eyebrow_style: EyebrowStyle = EyebrowStyle.NORMAL
var nose_shape: NoseShape = NoseShape.NORMAL
var mouth_style: MouthStyle = MouthStyle.NEUTRAL
var hair_style: HairStyle = HairStyle.SHORT
var hair_color: Color = HAIR_COLORS[1]  # Brown
var skin_tone: Color = SKIN_TONES[1]    # Fair
var personality: Personality = Personality.BRAVE
var starting_jobs: Array = ["fighter", "cleric"]  # Array of job IDs


func _init(char_name: String = "Hero") -> void:
	name = char_name


## Getters for display labels
static func get_eye_shape_name(shape: EyeShape) -> String:
	match shape:
		EyeShape.NORMAL: return "Normal"
		EyeShape.NARROW: return "Narrow"
		EyeShape.WIDE: return "Wide"
		EyeShape.CLOSED: return "Closed"
	return "Unknown"


static func get_eyebrow_style_name(style: EyebrowStyle) -> String:
	match style:
		EyebrowStyle.NORMAL: return "Normal"
		EyebrowStyle.THICK: return "Thick"
		EyebrowStyle.THIN: return "Thin"
		EyebrowStyle.ARCHED: return "Arched"
	return "Unknown"


static func get_nose_shape_name(shape: NoseShape) -> String:
	match shape:
		NoseShape.NORMAL: return "Normal"
		NoseShape.SMALL: return "Small"
		NoseShape.POINTED: return "Pointed"
		NoseShape.BROAD: return "Broad"
	return "Unknown"


static func get_mouth_style_name(style: MouthStyle) -> String:
	match style:
		MouthStyle.NEUTRAL: return "Neutral"
		MouthStyle.SMILE: return "Smile"
		MouthStyle.FROWN: return "Frown"
		MouthStyle.SMIRK: return "Smirk"
	return "Unknown"


static func get_hair_style_name(style: HairStyle) -> String:
	match style:
		HairStyle.SHORT: return "Short"
		HairStyle.LONG: return "Long"
		HairStyle.SPIKY: return "Spiky"
		HairStyle.BRAIDED: return "Braided"
		HairStyle.PONYTAIL: return "Ponytail"
		HairStyle.MOHAWK: return "Mohawk"
	return "Unknown"


static func get_personality_name(p: Personality) -> String:
	match p:
		Personality.BRAVE: return "Brave"
		Personality.CAUTIOUS: return "Cautious"
		Personality.SCHOLARLY: return "Scholarly"
		Personality.QUICK: return "Quick"
		Personality.CHARISMATIC: return "Charismatic"
	return "Unknown"


static func get_personality_description(p: Personality) -> String:
	match p:
		Personality.BRAVE: return "+2 ATK, Power Drink"
		Personality.CAUTIOUS: return "+2 DEF, Extra Potions"
		Personality.SCHOLARLY: return "+2 MAG, Ether"
		Personality.QUICK: return "+2 SPD, Speed Tonic"
		Personality.CHARISMATIC: return "+2 MAG +1 SPD, Party Bell"
	return ""


## Apply personality stat bonus to a combatant.
##
## Pre-fix this mutated the DERIVED stat (combatant.attack += 2) then
## immediately called recalculate_stats(), which rebuilds derived stats
## from base_X — so the +2 was wiped the same frame it landed. Every
## personality bonus in the UI ("+2 ATK" / "+2 DEF" / "+2 MAG" / "+2 SPD"
## / "+2 MAG +1 SPD") was effectively dead at character creation.
##
## Fix: modify the BASE stat so recalculate_stats picks the bonus up
## like any other source (job mods, level multiplier, passives). The
## bonus persists across stat recalcs and is intrinsic to the character.
func apply_stat_bonus(combatant: Combatant) -> void:
	match personality:
		Personality.BRAVE:
			combatant.base_attack += 2
		Personality.CAUTIOUS:
			combatant.base_defense += 2
		Personality.SCHOLARLY:
			combatant.base_magic += 2
		Personality.QUICK:
			combatant.base_speed += 2
		Personality.CHARISMATIC:
			combatant.base_magic += 2
			combatant.base_speed += 1
	combatant.recalculate_stats()


## Get starting items based on personality
func get_starting_items() -> Dictionary:
	match personality:
		Personality.BRAVE:
			return {"power_drink": 1, "potion": 3}
		Personality.CAUTIOUS:
			return {"potion": 6, "hi_potion": 2}
		Personality.SCHOLARLY:
			return {"ether": 3, "potion": 3}
		Personality.QUICK:
			return {"speed_tonic": 2, "potion": 3}
		Personality.CHARISMATIC:
			return {"party_bell": 1, "potion": 3, "ether": 1}
	return {"potion": 3}


## Serialize to dictionary for saving
func to_dict() -> Dictionary:
	return {
		"name": name,
		"eye_shape": eye_shape,
		"eyebrow_style": eyebrow_style,
		"nose_shape": nose_shape,
		"mouth_style": mouth_style,
		"hair_style": hair_style,
		"hair_color": [hair_color.r, hair_color.g, hair_color.b],
		"skin_tone": [skin_tone.r, skin_tone.g, skin_tone.b],
		"personality": personality,
		"starting_jobs": starting_jobs.duplicate()
	}


## JSON.parse returns enum fields as float. Assigning that float to a typed enum aborts this function and the caller stores null.
static func from_dict_with_script(data: Dictionary, script: GDScript):
	var custom = script.new(str(data.get("name", "Hero")))
	custom.eye_shape = _enum_or(data.get("eye_shape", EyeShape.NORMAL), EyeShape.size())
	custom.eyebrow_style = _enum_or(data.get("eyebrow_style", EyebrowStyle.NORMAL), EyebrowStyle.size())
	custom.nose_shape = _enum_or(data.get("nose_shape", NoseShape.NORMAL), NoseShape.size())
	custom.mouth_style = _enum_or(data.get("mouth_style", MouthStyle.NEUTRAL), MouthStyle.size())
	custom.hair_style = _enum_or(data.get("hair_style", HairStyle.SHORT), HairStyle.size())
	var hair_arr = data.get("hair_color", [0.45, 0.30, 0.18])
	if hair_arr is Array and hair_arr.size() >= 3:
		custom.hair_color = Color(float(hair_arr[0]), float(hair_arr[1]), float(hair_arr[2]))
	var skin_arr = data.get("skin_tone", [0.91, 0.78, 0.65])
	if skin_arr is Array and skin_arr.size() >= 3:
		custom.skin_tone = Color(float(skin_arr[0]), float(skin_arr[1]), float(skin_arr[2]))
	custom.personality = _enum_or(data.get("personality", Personality.BRAVE), Personality.size())
	var jobs = data.get("starting_jobs", ["fighter", "cleric"])
	if jobs is Array:
		var typed_jobs: Array = []
		for job_id in jobs:
			typed_jobs.append(str(job_id))
		custom.starting_jobs = typed_jobs
	return custom


static func _enum_or(raw, count: int) -> int:
	return clampi(int(raw), 0, maxi(0, count - 1))


## Saves written before natures were stored omit the key. New Game's five starters still have one.
static func for_roster_name(roster_name: String):
	var index: int = {"Fighter": 0, "Cleric": 1, "Rogue": 2, "Mage": 3, "Bard": 4}.get(roster_name, -1)
	if index < 0:
		return null
	var defaults: Array = create_default_party_with_script(CharacterCustomization)
	if index >= defaults.size():
		return null
	return defaults[index]


## Create default party customizations - requires passing the script as parameter
static func create_default_party_with_script(script: GDScript) -> Array:
	var party: Array = []

	# Hero - Fighter/Rogue/Brave (determined look)
	var hero = script.new("Hero")
	hero.eye_shape = EyeShape.NORMAL
	hero.eyebrow_style = EyebrowStyle.THICK
	hero.nose_shape = NoseShape.NORMAL
	hero.mouth_style = MouthStyle.NEUTRAL
	hero.hair_style = HairStyle.SHORT
	hero.hair_color = HAIR_COLORS[1]  # Brown
	hero.skin_tone = SKIN_TONES[1]
	hero.personality = Personality.BRAVE
	hero.starting_jobs = ["fighter", "rogue"]
	party.append(hero)

	# Mira - Cleric/Bard/Cautious (cheerful look)
	var mira = script.new("Mira")
	mira.eye_shape = EyeShape.WIDE
	mira.eyebrow_style = EyebrowStyle.ARCHED
	mira.nose_shape = NoseShape.SMALL
	mira.mouth_style = MouthStyle.SMILE
	mira.hair_style = HairStyle.LONG
	mira.hair_color = HAIR_COLORS[3]  # Red
	mira.skin_tone = SKIN_TONES[0]
	mira.personality = Personality.CAUTIOUS
	mira.starting_jobs = ["cleric", "bard"]
	party.append(mira)

	# Zack - Rogue/Fighter/Quick (mysterious look)
	var zack = script.new("Zack")
	zack.eye_shape = EyeShape.NARROW
	zack.eyebrow_style = EyebrowStyle.THIN
	zack.nose_shape = NoseShape.POINTED
	zack.mouth_style = MouthStyle.SMIRK
	zack.hair_style = HairStyle.SPIKY
	zack.hair_color = HAIR_COLORS[0]  # Black
	zack.skin_tone = SKIN_TONES[2]
	zack.personality = Personality.QUICK
	zack.starting_jobs = ["rogue", "fighter"]
	party.append(zack)

	# Vex - Mage/Cleric/Scholarly (serious look)
	var vex = script.new("Vex")
	vex.eye_shape = EyeShape.CLOSED
	vex.eyebrow_style = EyebrowStyle.NORMAL
	vex.nose_shape = NoseShape.BROAD
	vex.mouth_style = MouthStyle.FROWN
	vex.hair_style = HairStyle.PONYTAIL
	vex.hair_color = HAIR_COLORS[4]  # Silver
	vex.skin_tone = SKIN_TONES[3]
	vex.personality = Personality.SCHOLARLY
	vex.starting_jobs = ["mage", "cleric"]
	party.append(vex)

	# Bard - Bard/Rogue/Cheerful (performer look)
	# Internal ID "bard" matches the job_id; see GameLoop._create_party.
	var bard = script.new("Bard")
	bard.eye_shape = EyeShape.WIDE
	bard.eyebrow_style = EyebrowStyle.ARCHED
	bard.nose_shape = NoseShape.SMALL
	bard.mouth_style = MouthStyle.SMILE
	bard.hair_style = HairStyle.LONG
	bard.hair_color = HAIR_COLORS[5] if HAIR_COLORS.size() > 5 else HAIR_COLORS[2]
	bard.skin_tone = SKIN_TONES[1]
	bard.personality = Personality.CHARISMATIC
	bard.starting_jobs = ["bard", "rogue"]
	party.append(bard)

	return party
