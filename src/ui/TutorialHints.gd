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
	"advance_defer": {
		"title": "Advance & Defer",
		"body": "Press R to Advance — queue up to 4 actions in one turn (costs AP). Press L to Defer — skip your turn, gain +1 AP, take less damage. Manage your AP for powerful combos.",
	},
	"group_attacks": {
		"title": "Group Attacks",
		"body": "When all party members have AP, you can pool it for devastating group attacks: All-Out Attack, Combo Magic, or Formation Specials. Powerful but leaves everyone exposed next turn.",
	},
	"first_battle": {
		"title": "Battle Controls",
		"body": "Navigate menus with D-pad. Confirm with A/Z. Cancel with B/X. Use R to queue multiple actions (Advance mode). Use L to skip your turn and build AP (Defer).",
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
