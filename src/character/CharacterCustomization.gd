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
	BRAVE,     # +2 ATK, starts with power_drink
	CAUTIOUS,  # +2 DEF, starts with extra potions
	SCHOLARLY, # +2 MAG, starts with ether
	QUICK      # +2 SPD, starts with speed_tonic
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
var starting_jobs: Array = ["fighter", "white_mage"]  # Array of job IDs


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
	return "Unknown"


static func get_personality_description(p: Personality) -> String:
	match p:
		Personality.BRAVE: return "+2 ATK, Power Drink"
		Personality.CAUTIOUS: return "+2 DEF, Extra Potions"
		Personality.SCHOLARLY: return "+2 MAG, Ether"
		Personality.QUICK: return "+2 SPD, Speed Tonic"
	return ""


## Apply personality stat bonus to a combatant
func apply_stat_bonus(combatant: Combatant) -> void:
	match personality:
		Personality.BRAVE:
			combatant.base_stats["attack"] = combatant.base_stats.get("attack", 10) + 2
		Personality.CAUTIOUS:
			combatant.base_stats["defense"] = combatant.base_stats.get("defense", 10) + 2
		Personality.SCHOLARLY:
			combatant.base_stats["magic"] = combatant.base_stats.get("magic", 10) + 2
		Personality.QUICK:
			combatant.base_stats["speed"] = combatant.base_stats.get("speed", 10) + 2
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


## Deserialize from dictionary - requires passing the script as parameter
static func from_dict_with_script(data: Dictionary, script: GDScript):
	var custom = script.new(data.get("name", "Hero"))
	custom.eye_shape = data.get("eye_shape", EyeShape.NORMAL)
	custom.eyebrow_style = data.get("eyebrow_style", EyebrowStyle.NORMAL)
	custom.nose_shape = data.get("nose_shape", NoseShape.NORMAL)
	custom.mouth_style = data.get("mouth_style", MouthStyle.NEUTRAL)
	custom.hair_style = data.get("hair_style", HairStyle.SHORT)
	var hair_arr = data.get("hair_color", [0.45, 0.30, 0.18])
	custom.hair_color = Color(hair_arr[0], hair_arr[1], hair_arr[2])
	var skin_arr = data.get("skin_tone", [0.91, 0.78, 0.65])
	custom.skin_tone = Color(skin_arr[0], skin_arr[1], skin_arr[2])
	custom.personality = data.get("personality", Personality.BRAVE)
	custom.starting_jobs = data.get("starting_jobs", ["fighter", "white_mage"])
	return custom


## Create default party customizations - requires passing the script as parameter
static func create_default_party_with_script(script: GDScript) -> Array:
	var party: Array = []

	# Hero - Fighter/Brave (determined look)
	var hero = script.new("Hero")
	hero.eye_shape = EyeShape.NORMAL
	hero.eyebrow_style = EyebrowStyle.THICK
	hero.nose_shape = NoseShape.NORMAL
	hero.mouth_style = MouthStyle.NEUTRAL
	hero.hair_style = HairStyle.SHORT
	hero.hair_color = HAIR_COLORS[1]  # Brown
	hero.skin_tone = SKIN_TONES[1]
	hero.personality = Personality.BRAVE
	hero.starting_jobs = ["fighter", "thief"]
	party.append(hero)

	# Mira - White Mage/Cautious (cheerful look)
	var mira = script.new("Mira")
	mira.eye_shape = EyeShape.WIDE
	mira.eyebrow_style = EyebrowStyle.ARCHED
	mira.nose_shape = NoseShape.SMALL
	mira.mouth_style = MouthStyle.SMILE
	mira.hair_style = HairStyle.LONG
	mira.hair_color = HAIR_COLORS[3]  # Red
	mira.skin_tone = SKIN_TONES[0]
	mira.personality = Personality.CAUTIOUS
	mira.starting_jobs = ["white_mage", "black_mage"]
	party.append(mira)

	# Zack - Thief/Quick (mysterious look)
	var zack = script.new("Zack")
	zack.eye_shape = EyeShape.NARROW
	zack.eyebrow_style = EyebrowStyle.THIN
	zack.nose_shape = NoseShape.POINTED
	zack.mouth_style = MouthStyle.SMIRK
	zack.hair_style = HairStyle.SPIKY
	zack.hair_color = HAIR_COLORS[0]  # Black
	zack.skin_tone = SKIN_TONES[2]
	zack.personality = Personality.QUICK
	zack.starting_jobs = ["thief", "fighter"]
	party.append(zack)

	# Vex - Black Mage/Scholarly (serious look)
	var vex = script.new("Vex")
	vex.eye_shape = EyeShape.CLOSED
	vex.eyebrow_style = EyebrowStyle.NORMAL
	vex.nose_shape = NoseShape.BROAD
	vex.mouth_style = MouthStyle.FROWN
	vex.hair_style = HairStyle.PONYTAIL
	vex.hair_color = HAIR_COLORS[4]  # Silver
	vex.skin_tone = SKIN_TONES[3]
	vex.personality = Personality.SCHOLARLY
	vex.starting_jobs = ["black_mage", "white_mage"]
	party.append(vex)

	return party
