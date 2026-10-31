extends RefCounted
class_name TrialRouting

## WHICH SUB-FINAL TRIAL A SAVE HAS EARNED. struktured, 2026-10-26: three sub-final bosses, "one for
## automated gamers, one for classic games, one for one shotters", routed by how the player actually
## played rather than chosen at a door.
##
## ⛔ THIS DOES NOT ADD A PLAYSTYLE. CutsceneDirector._detect_playstyle() returns automator / manual /
## grinder / exploiter / balanced and world6_chapter3 branches on those four canon keys to pick one of
## the game's four endings. A fifth return value would leave a player with an unhandled branch, so the
## trial decision lives here and CONSUMES that answer instead of extending it.
##
## The one-shot build has no playstyle label and needs none: SaveSystem.one_shot_records already
## persists {monster_id: {count, best_rank, best_setup}} on every one-shot victory, which is a better
## signal than a label because it records the RANK — a player who reached S ("Raw power overwhelm",
## one setup turn) committed to the build, where a handful of accidental one-shots is noise.

## The three trials. Mechanical ids: cowir-story owns the display names and the dialogue.
const TRIAL_AUTOMATION := "trial_automation"
const TRIAL_CLASSIC := "trial_classic"
const TRIAL_BURST := "trial_burst"

## WHICH MONSTER EACH TRIAL FIELDS. The arena asks for this rather than naming a monster, so a
## renamed or deleted id cannot leave the routing pointing at nothing —
## test_every_trial_fields_a_monster_that_exists reds instead, and it derives the three ids from
## this map rather than listing them.
##
## ⚠️ MECHANICAL IDS, AND THE DISPLAY NAMES ARE DATA. cowir-story owns what a player reads: the
## `name`, `description`, `dialogue` and intro cutscene on each monsters.json entry are theirs to
## rewrite without touching a line of this file. What is NOT theirs to change silently is the
## mechanic each trial tests, which is why the guard checks the MECHANIC and not the prose.
const TRIAL_MONSTERS := {
	TRIAL_AUTOMATION: "the_operator",
	TRIAL_CLASSIC: "the_examiner",
	TRIAL_BURST: "the_margin",
}


## The monster a trial fields. Falls back to the classic occupant for the same reason trial_for
## defaults to TRIAL_CLASSIC: an unrecognised trial should yield a real fight, not an empty arena.
static func monster_for(trial: String) -> String:
	return str(TRIAL_MONSTERS.get(trial, TRIAL_MONSTERS[TRIAL_CLASSIC]))


## Below this many one-shots nothing is a build — the formation clears the low-end roster by accident
## even after .727 (13 of 50 monsters are still one-shottable by design).
const BURST_MIN_ONE_SHOTS: int = 8

## …and they have to be GOOD ones. S is one setup turn, A is up to three; B and C are a party that
## happened to finish a fight in one phase.
const BURST_DELIBERATE_RANKS: Array[String] = ["S", "A"]

## A burst player's one-shots as a share of their won battles. Set beside
## CutsceneDirector.PLAYSTYLE_MANUAL_RATIO (0.3) deliberately: this is the same KIND of judgement
## about proportion, and a one-shot rate above a fifth of all wins is a habit rather than a knack.
const BURST_RATIO: float = 0.2


## The trial for an explicit set of counts. PURE: no autoloads, so every arm of its guard can state
## its own population instead of building a save.
##   playstyle         whatever CutsceneDirector._detect_playstyle() returned
##   one_shots         total one_shot victories across all monsters
##   deliberate        of those, how many reached rank S or A
##   battles_won       organic battles won (the duels are already excluded upstream)
static func trial_for(playstyle: String, one_shots: int, deliberate: int, battles_won: int) -> String:
	## THE BURST BUILD OUTRANKS THE DELIVERY METHOD, and the asymmetry is deliberate: automation is HOW
	## a player issues commands, a one-shot build is WHAT they built. A script that one-shots is still a
	## one-shot build, and that trial is the one such a player has never been tested by — they have
	## skipped the second half of every fight in the game.
	if _is_burst_build(one_shots, deliberate, battles_won):
		return TRIAL_BURST
	if playstyle == "automator":
		return TRIAL_AUTOMATION
	## manual, grinder, exploiter and balanced all land here. Classic is the DEFAULT on purpose: it is
	## the only one of the three that assumes nothing about the player, so an unrecognised playstyle
	## gets a real fight rather than no trial at all.
	return TRIAL_CLASSIC


## A build, not a knack: enough one-shots, enough of them deliberate, and a high enough share of wins.
static func _is_burst_build(one_shots: int, deliberate: int, battles_won: int) -> bool:
	if one_shots < BURST_MIN_ONE_SHOTS:
		return false
	if deliberate <= 0:
		return false
	if battles_won <= 0:
		## No denominator: trust the deliberate count alone rather than dividing by zero.
		return deliberate >= BURST_MIN_ONE_SHOTS
	return float(one_shots) / float(battles_won) >= BURST_RATIO


## The trial this save has earned, resolved from the live game. Guarded at every step because the
## arena is instantiable in a test with no GameLoop: a missing director yields "balanced", which
## trial_for documents as landing on TRIAL_CLASSIC — a real fight rather than no trial at all.
##
## ⚠️ IT ASKS THE DIRECTOR RATHER THAN RE-DERIVING THE PLAYSTYLE. CutsceneDirector._detect_playstyle
## is the only body; world6_chapter3's ending branch reads the same answer. A local copy here would
## be a second instrument that drifts, and the two would disagree about the same save.
static func trial_from_game(director, save_system, game_state) -> String:
	var playstyle: String = "balanced"
	if director != null and director.has_method("detect_playstyle"):
		playstyle = str(director.detect_playstyle())
	var counts: Dictionary = counts_from_save(save_system, game_state)
	return trial_for(playstyle, int(counts.get("one_shots", 0)), int(counts.get("deliberate", 0)), int(counts.get("battles_won", 0)))


## The counts this save actually carries. Thin on purpose — everything decidable lives in trial_for.
static func counts_from_save(save_system, game_state) -> Dictionary:
	var one_shots: int = 0
	var deliberate: int = 0
	if save_system != null and "one_shot_records" in save_system:
		var records: Variant = save_system.one_shot_records
		if records is Dictionary:
			for key in (records as Dictionary):
				var row: Variant = (records as Dictionary)[key]
				if not (row is Dictionary):
					continue
				var n: int = int((row as Dictionary).get("count", 0))
				one_shots += n
				if str((row as Dictionary).get("best_rank", "")) in BURST_DELIBERATE_RANKS:
					deliberate += n
	var battles: int = 0
	if game_state != null:
		## organic_battles_won() exists so the five forced-manual unlock duels stay out of a ratio they
		## say nothing about — the same reason _detect_playstyle uses it.
		if game_state.has_method("organic_battles_won"):
			battles = int(game_state.organic_battles_won())
		elif "battles_won" in game_state:
			battles = int(game_state.battles_won)
	return {"one_shots": one_shots, "deliberate": deliberate, "battles_won": battles}
