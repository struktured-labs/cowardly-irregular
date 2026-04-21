extends Node
class_name TutorialHints

## TutorialHints — static catalog of all game tutorial hints.
## Call these from GameLoop, BattleScene, OverworldScene etc. at the right moments.
##
## Usage:
##   TutorialHints.show(parent_node, "movement")

## All available hints
const HINTS = {
	"movement": {
		"title": "Movement",
		"body": "Use D-pad or left stick to move. The overworld is large — follow signposts and check your Quest Log (Menu → Quest Log) for direction.",
	},
	"autobattle_intro": {
		"title": "Autobattle System",
		"body": "Press F5 or L+R together to open the Autobattle Editor. Design rules — if HP is low, heal. If enemy is weak to fire, cast fire. Let the system fight for you. Not laziness. Enlightenment.",
	},
	"autobattle_toggle": {
		"title": "Toggle Autobattle",
		"body": "Press F6 or Select to toggle autobattle ON/OFF for all party members. When active, your rules execute automatically each turn.",
	},
	"save_crystal": {
		"title": "Save Crystal",
		"body": "Approach a glowing crystal and press A to save your progress. Save often — the game has real consequences.",
	},
	"first_battle": {
		"title": "Your First Battle",
		"body": "Combat is turn-based. Watch the Action Gauge (top-right) to see turn order — the icon at the top acts next. On your turn, pick Attack for a basic strike, or open Skills, Magic, or Items from the command menu. A/Z confirms, B/X backs out — the enemy's HP bar tells you how close the fight is to ending.",
	},
	"understanding_ap": {
		"title": "Understanding AP",
		"body": "Each character has Action Points (AP) from -4 to +4, shown under their name. You gain +1 AP every turn automatically, and you spend AP to take extra actions in a single turn. At 0 AP you act normally; above 0 you can do more at once; below 0 you owe the system. The system always collects.",
	},
	"advance_defer": {
		"title": "Advance and Defer",
		"body": "Press R to Advance: queue up to 4 actions in one turn, each costing 1 AP. Burn AP for burst damage when you need the fight to end now. Press L to Defer — skip the turn, gain +1 AP, and take less damage. Alternate them: Defer to bank AP, Advance to spend it all at once.",
	},
	"group_attacks": {
		"title": "Group Attacks",
		"body": "When every party member has enough AP, you can pool it for a Group Attack. All-Out Attack hits the full enemy row; Combo Magic fuses two elements (Fire + Ice = Steam) for elemental combos; Formation Specials unlock with specific party compositions. Group Attacks hit harder than anything else — but every member drops into AP debt afterward. Be ready to Defer.",
	},
	"first_boss": {
		"title": "Boss Fight",
		"body": "Bosses have multiple phases. Watch for pattern changes and adapt your strategy. Masterites each have a unique fighting style — learn it.",
	},
	"quest_log": {
		"title": "Quest Log",
		"body": "Lost? Open the menu and check Quest Log for your current objective. The minimap also shows a pulsing gold dot at your destination.",
	},
	"autogrind": {
		"title": "Autogrind",
		"body": "Open the Autogrind panel to let the game fight battles automatically. Set interrupt rules to stop when HP is low. Higher speed = more risk. The system rewards patience... and punishes perfection.",
	},
	"world_transition": {
		"title": "New World",
		"body": "Each world transforms your party — new costumes, new abilities, same skills underneath. The Masterites here follow the same four archetypes: Warden, Arbiter, Tempo, Curator.",
	},
	"first_formation": {
		"title": "Party Formations",
		"body": "Press F to cycle formations. Front Line boosts ATK, Back Row boosts DEF, Diamond protects with a tank, Spread resists AoE. Formations pair with Formation Specials for devastating combos.",
	},
	"ludicrous_speed": {
		"title": "Ludicrous Speed",
		"body": "Battles now resolve instantly via pure math — no animations, no rendering. Your autobattle scripts and formation specials still execute faithfully. Watch the dashboard for throughput stats.",
	},
	"autogrind_menu": {
		"title": "Autogrind Setup",
		"body": "Configure interrupt rules: IF party HP drops below 30% THEN use potions. IF a member dies THEN stop. Press 1/2/3 for quick presets (Casual/Standard/Hardcore). Press Start to begin grinding.",
	},
	"autogrind_presets": {
		"title": "Quick Presets",
		"body": "Casual: safe, stops on death. Standard: balanced with auto-advance. Hardcore: ludicrous speed, minimal stops. Presets configure rules + toggles in one keypress.",
	},
	"autogrind_export": {
		"title": "Script Sharing",
		"body": "Your autobattle scripts and autogrind rules are saved to script_exports/. Share JSON files with other players or back them up. Press I to import shared scripts.",
	},
	"autogrind_resume": {
		"title": "Resume Session",
		"body": "Your grind progress was saved automatically. Press Resume to continue where you left off — all battles, EXP, and items are preserved.",
	},
}


static func show(parent: Node, hint_id: String) -> void:
	"""Show a tutorial hint by ID, if it hasn't been shown before."""
	if not HINTS.has(hint_id):
		push_warning("TutorialHints: Unknown hint '%s'" % hint_id)
		return

	var hint_data = HINTS[hint_id]
	var hint = TutorialHint.new()
	parent.add_child(hint)
	hint.show_hint(hint_id, hint_data["title"], hint_data["body"])
	# Auto-cleanup after dismissal
	hint.hint_dismissed.connect(func(_id): hint.queue_free())
