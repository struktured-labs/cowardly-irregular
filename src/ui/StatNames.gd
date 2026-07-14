extends RefCounted
class_name StatNames

## Shared stat-name display helpers — tick 211.
##
## Extracted from EquipmentMenu (tick 210) so the same maps drive
## every stat display surface. Acronyms (HP/MP) preserved via
## explicit maps. Canonical JRPG abbreviations: ATK / DEF / MAG /
## SPD / HP / MP — disambiguates max_hp from max_mp (the bare
## `substr(0, 3).to_upper()` produces "MAX" for both, ambiguous).
##
## Unknown stat ids (Scriptweaver custom stats, future stats not
## yet mapped) fall back to .capitalize() / substr — readable
## degradation, not crash.

const DISPLAY := {
	"attack": "Attack",
	"defense": "Defense",
	"magic": "Magic",
	"speed": "Speed",
	"max_hp": "Max HP",
	"max_mp": "Max MP",
}

const SHORT := {
	"attack": "ATK",
	"defense": "DEF",
	"magic": "MAG",
	"speed": "SPD",
	"max_hp": "HP",
	"max_mp": "MP",
}


# Long-form display name. "max_hp" → "Max HP". Unknown ids fall back to .capitalize().
static func display_name(stat_name: String) -> String:
	if stat_name == "":
		return ""
	return DISPLAY.get(stat_name, stat_name.capitalize())


# Compact display code. "max_hp" → "HP" (NOT "MAX" — disambiguates from max_mp). Unknown ids fall back to substr(0, 3).to_upper().
static func short_code(stat_name: String) -> String:
	if stat_name == "":
		return ""
	return SHORT.get(stat_name, stat_name.substr(0, 3).to_upper())
