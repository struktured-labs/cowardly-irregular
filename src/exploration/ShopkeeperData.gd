extends RefCounted
class_name ShopkeeperData

## Static shopkeeper appearance definitions for the 4 shop types


static func get_item_shopkeeper() -> CharacterCustomization:
	"""Willow - Item Shop keeper. Friendly herbalist."""
	var custom = CharacterCustomization.new("Willow")
	custom.eye_shape = CharacterCustomization.EyeShape.WIDE
	custom.eyebrow_style = CharacterCustomization.EyebrowStyle.ARCHED
	custom.nose_shape = CharacterCustomization.NoseShape.SMALL
	custom.mouth_style = CharacterCustomization.MouthStyle.SMILE
	custom.hair_style = CharacterCustomization.HairStyle.BRAIDED
	custom.hair_color = CharacterCustomization.HAIR_COLORS[6]  # Green
	custom.skin_tone = CharacterCustomization.SKIN_TONES[1]    # Fair
	return custom


static func get_black_magic_shopkeeper() -> CharacterCustomization:
	"""Mortimer - Black Magic dealer. Mysterious and dark."""
	var custom = CharacterCustomization.new("Mortimer")
	custom.eye_shape = CharacterCustomization.EyeShape.NARROW
	custom.eyebrow_style = CharacterCustomization.EyebrowStyle.THIN
	custom.nose_shape = CharacterCustomization.NoseShape.POINTED
	custom.mouth_style = CharacterCustomization.MouthStyle.SMIRK
	custom.hair_style = CharacterCustomization.HairStyle.LONG
	custom.hair_color = CharacterCustomization.HAIR_COLORS[5]  # Blue
	custom.skin_tone = CharacterCustomization.SKIN_TONES[4]    # Dark
	return custom


static func get_white_magic_shopkeeper() -> CharacterCustomization:
	"""Sister Lenora - White Magic seller. Serene and gentle."""
	var custom = CharacterCustomization.new("Sister Lenora")
	custom.eye_shape = CharacterCustomization.EyeShape.NORMAL
	custom.eyebrow_style = CharacterCustomization.EyebrowStyle.NORMAL
	custom.nose_shape = CharacterCustomization.NoseShape.NORMAL
	custom.mouth_style = CharacterCustomization.MouthStyle.NEUTRAL
	custom.hair_style = CharacterCustomization.HairStyle.PONYTAIL
	custom.hair_color = CharacterCustomization.HAIR_COLORS[3]  # Red
	custom.skin_tone = CharacterCustomization.SKIN_TONES[0]    # Light
	return custom


static func get_blacksmith_shopkeeper() -> CharacterCustomization:
	"""Brutus - Blacksmith. Burly and gruff."""
	var custom = CharacterCustomization.new("Brutus")
	custom.eye_shape = CharacterCustomization.EyeShape.NORMAL
	custom.eyebrow_style = CharacterCustomization.EyebrowStyle.THICK
	custom.nose_shape = CharacterCustomization.NoseShape.BROAD
	custom.mouth_style = CharacterCustomization.MouthStyle.FROWN
	custom.hair_style = CharacterCustomization.HairStyle.SHORT
	custom.hair_color = CharacterCustomization.HAIR_COLORS[0]  # Black
	custom.skin_tone = CharacterCustomization.SKIN_TONES[3]    # Tan
	return custom


static func get_shopkeeper_for_type(shop_type: int) -> CharacterCustomization:
	"""Get shopkeeper by shop type enum value (0=ITEM, 1=BLACK_MAGIC, 2=WHITE_MAGIC, 3=BLACKSMITH)"""
	match shop_type:
		0: return get_item_shopkeeper()
		1: return get_black_magic_shopkeeper()
		2: return get_white_magic_shopkeeper()
		3: return get_blacksmith_shopkeeper()
	return get_item_shopkeeper()
