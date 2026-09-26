extends GutTest

## The pause menu's Jobs screen can switch a starter onto any other starter job.
## Closing it rewrote the card's job name and the combatant the next battle
## uses, and left two faces on the old job: the portrait baked when the menu
## opened, and the figure on the map. That figure is restamped only when the
## leader changes or a new map loads, so a fighter who just became a mage
## keeps walking as a fighter until one of those happens.
##
## What the player sees: open the menu, change the leader to Mage, close Jobs.
## The card says Mage beside a fighter's face. Close the menu and the person
## on the map is still the fighter.

const MENU := preload("res://src/ui/OverworldMenu.gd")
const PLAYER := preload("res://src/exploration/OverworldPlayer.gd")

var _saved_leader: int = 0


func before_each() -> void:
	_saved_leader = int(GameState.party_leader_index)
	GameState.party_leader_index = 0


func after_each() -> void:
	GameState.party_leader_index = _saved_leader


func _member(who: String, job_id: String) -> Combatant:
	var member := Combatant.new()
	member.combatant_name = who
	member.job = {"id": job_id, "name": job_id.capitalize()}
	member.max_hp = 100
	member.current_hp = 100
	member.max_mp = 20
	member.current_mp = 20
	member.is_alive = true
	add_child_autofree(member)
	return member


func _open(party: Array) -> OverworldMenu:
	var menu: OverworldMenu = MENU.new()
	add_child_autofree(menu)
	menu.setup(party)
	await get_tree().process_frame
	await get_tree().process_frame
	return menu


## The card's face is a CharacterPortrait child. It has no stable name on the
## unfixed menu, so a get_node("Portrait") would abort the test before the
## stale-face assert and the file would pass.
func _face(card: Control) -> CharacterPortrait:
	for child in card.get_children():
		if child is CharacterPortrait:
			return child
	return null


## Same handoff GameLoop._on_party_leader_changed uses: the signal carries an index, the scene stamps that member.
func _wire_map(menu: OverworldMenu) -> OverworldPlayer:
	var avatar: OverworldPlayer = PLAYER.new()
	add_child_autofree(avatar)
	menu.party_leader_changed.connect(func(idx: int) -> void:
		avatar.set_appearance_from_leader(menu.party[idx])
	)
	return avatar


func test_the_leaders_new_job_replaces_the_map_figure_and_the_card_face() -> void:
	var hero := _member("Bram", "fighter")
	var mira := _member("Mira", "cleric")
	var menu := await _open([hero, mira])
	assert_eq(menu._party_panels.size(), 2, "the pause menu built a card per member")
	assert_true(menu._ui_built, "the cards are the in-place ones a job change closes back onto")
	var avatar := _wire_map(menu)
	var card: Control = menu._party_panels[0]
	var face := _face(card)
	assert_not_null(face, "the leader's card has a face")
	assert_eq(str(face.job_id), "fighter", "the card opens showing the job they have")
	assert_eq(str(avatar.current_job), "fighter", "the map still shows the fighter they walked in as")

	hero.job = {"id": "mage", "name": "Mage"}
	menu._on_job_changed(hero, "mage", false)
	menu._on_submenu_closed()

	assert_false(card.is_queued_for_deletion(),
		"Jobs closes onto the existing cards — a full rebuild is not what the player gets")
	assert_eq(str(card.get_node("JobLabel").text), "Mage",
		"the job name already updates; the face has to agree with it")
	face = _face(card)
	assert_not_null(face, "the leader's card still has a face after Jobs closes")
	assert_eq(str(face.job_id), "mage",
		"the pause-menu card still shows the fighter's face after the leader becomes a mage")
	assert_eq(str(avatar.current_job), "mage",
		"the figure on the map is still the fighter until the leader is cycled or the map reloads")


func test_another_members_job_change_updates_their_card_only() -> void:
	var hero := _member("Bram", "fighter")
	var mira := _member("Mira", "cleric")
	var menu := await _open([hero, mira])
	var avatar := _wire_map(menu)
	var hero_card: Control = menu._party_panels[0]
	var mira_card: Control = menu._party_panels[1]

	mira.job = {"id": "bard", "name": "Bard"}
	menu._on_job_changed(mira, "bard", false)
	menu._on_submenu_closed()

	assert_eq(str(avatar.current_job), "fighter",
		"changing someone who is not leading must not restamp the map figure")
	var hero_face := _face(hero_card)
	var mira_face := _face(mira_card)
	assert_not_null(hero_face, "the leader's card still has a face")
	assert_not_null(mira_face, "her card still has a face")
	assert_eq(str(hero_face.job_id), "fighter",
		"the leader's card keeps the leader's face")
	assert_eq(str(mira_card.get_node("JobLabel").text), "Bard",
		"her card's job name follows the change")
	assert_eq(str(mira_face.job_id), "bard",
		"her card still shows the cleric's face after she becomes a bard")
