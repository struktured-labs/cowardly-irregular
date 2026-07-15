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
	"spotlight_unlock": {
		"title": "Spotlight Unlocked",
		"body": "This party member just stepped out from autopilot — you now have direct control of their turn. Locked members still follow their autobattle rules until their spotlight scene plays.",
		"min_dismiss": 2.0,  # Load-bearing unlock — playtest 2026-07-15 msg 2555, mid-battle button-mashers were skipping it
	},
	"spotlight_locked_intro": {
		"title": "Why the auto-turns?",
		"body": "Only the Fighter starts with manual control. Cleric, Mage, Rogue, and Bard follow their autobattle rules until you unlock them by winning their Spotlight Duel — a 1v1 miniboss that showcases what THAT character does best. Look for their spotlight beat in the villages and cave.",
	},

	# Spotlight-duel tiered death hints. Convention: tier 1 = the DOOR (what to
	# notice), tier 2 = the RULE (what wins), tier 3 = the RECIPE (exact loop).
	# cowir-battle wires the loss-counter → show hook by tier.

	"spotlight_hint_fighter_1": {
		"title": "The Skeleton Knight — I",
		"body": "Not every strike deserves an answer. Watch how it moves before you commit.",
	},
	"spotlight_hint_fighter_2": {
		"title": "The Skeleton Knight — II",
		"body": "It braces before it swings. Braced turns are yours to prepare. Unbraced turns are yours to spend.",
	},
	"spotlight_hint_fighter_3": {
		"title": "The Skeleton Knight — III",
		"body": "Power Strike on clean turns. Defend when it braces. The opening comes every third round — bank Advance for it. Rhythm beats reflex.",
	},

	"spotlight_hint_cleric_1": {
		"title": "The Grinding Wound — I",
		"body": "Nothing you swing lands. The Wound doesn't take damage. It isn't asking you to hit it.",
	},
	"spotlight_hint_cleric_2": {
		"title": "The Grinding Wound — II",
		"body": "You aren't fighting it — you're outlasting it. Keep the party alive to turn eight. Attacks waste the turn you could have healed.",
	},
	"spotlight_hint_cleric_3": {
		"title": "The Grinding Wound — III",
		"body": "Cure at half HP. Pray refills MP. Protect the exposed. Defer the safe turns. Faith isn't loud — it's on time.",
	},

	"spotlight_hint_rogue_1": {
		"title": "The Lockward — I",
		"body": "The vault is what he shows you. The key is what he hides.",
	},
	"spotlight_hint_rogue_2": {
		"title": "The Lockward — II",
		"body": "The fight isn't the fight. Fingers first — take what he thinks he's guarding. Then the vault opens on its own.",
	},
	"spotlight_hint_rogue_3": {
		"title": "The Lockward — III",
		"body": "Steal turn one — the key, not the coin. His guard breaks with the vault. Backstab the unguarded turns; Defer the sigil turns. He kept every rule but the one you wrote.",
	},

	"spotlight_hint_mage_1": {
		"title": "The Prismatic Construct — I",
		"body": "It changes color for a reason. Watch first, cast second.",
	},
	"spotlight_hint_mage_2": {
		"title": "The Prismatic Construct — II",
		"body": "Fire when it burns. Ice when it frosts. Thunder when it sparks. The wrong element is worse than doing nothing — it wastes the turn.",
	},
	"spotlight_hint_mage_3": {
		"title": "The Prismatic Construct — III",
		"body": "Read the color. Cast to match. Save MP for the cycle you can't skip. The color is a sentence — finish it with the matching element.",
	},

	"spotlight_hint_bard_1": {
		"title": "The Hostile Courtier — I",
		"body": "Not every fight is a fight. Listen for what he's actually saying.",
	},
	"spotlight_hint_bard_2": {
		"title": "The Hostile Courtier — II",
		"body": "HP doesn't win this. Swayed does. Sing until the pile reaches the threshold.",
	},
	"spotlight_hint_bard_3": {
		"title": "The Hostile Courtier — III",
		"body": "Lullaby stacks Swayed. Discord stacks Swayed. Ignore his HP; watch the count. He listens when the pile fills — not one turn earlier, not one turn late.",
	},
}


static func show(parent: Node, hint_id: String) -> void:
	"""Show a tutorial hint by ID, if it hasn't been shown before."""
	if not HINTS.has(hint_id):
		push_warning("TutorialHints: Unknown hint '%s'" % hint_id)
		return

	# Guard BEFORE instancing/add_child — prior code leaked a node every call
	# for an already-seen hint (TutorialHint.show_hint short-circuited but the
	# CanvasLayer had already been parented and nothing freed it).
	if TutorialHint._shown_hints.get(hint_id, false):
		return
	var ml := Engine.get_main_loop()
	if ml and ml is SceneTree:
		var gs := (ml as SceneTree).root.get_node_or_null("GameState")
		if gs and gs.game_constants.get("tutorial_" + hint_id, false):
			return

	var hint_data = HINTS[hint_id]
	var hint = TutorialHint.new()
	parent.add_child(hint)
	hint.show_hint(hint_id, hint_data["title"], hint_data["body"], float(hint_data.get("min_dismiss", 0.0)))
	# Auto-cleanup after dismissal
	hint.hint_dismissed.connect(func(_id): hint.queue_free())
