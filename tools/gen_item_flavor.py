#!/usr/bin/env python3
"""Adds flavor text to data/items.json and data/equipment.json.

Preserves the existing functional `description` field (used by battle/inventory
UI for mechanical tooltips) and adds a new `flavor` field for atmospheric
one-liners. BestiaryMenu-style UIs can show both.

Idempotent: re-running just overwrites the flavor field.
"""
import json
import re
from pathlib import Path


def compact_primitive_arrays(text: str) -> str:
    """Re-collapse arrays of numbers/strings/booleans onto a single line.

    Matches multi-line [ … ] blocks where every element is a primitive
    literal and rewrites them as a single-line array. Preserves the
    surrounding indentation and trailing comma/newline.
    """
    pattern = re.compile(
        r"\[\n(?:[ \t]+[-+]?(?:\d+(?:\.\d+)?|\"[^\"\n]*\"|true|false|null),?\n)+[ \t]+\]",
    )

    def replace(match: re.Match) -> str:
        body = match.group(0)
        items = [line.strip().rstrip(",") for line in body.splitlines()[1:-1]]
        return "[" + ", ".join(items) + "]"

    prev = None
    while prev != text:
        prev = text
        text = pattern.sub(replace, text)
    return text

ROOT = Path(__file__).resolve().parent.parent
ITEMS = ROOT / "data" / "items.json"
EQUIPMENT = ROOT / "data" / "equipment.json"

# ── Consumables ────────────────────────────────────────────────────────────
ITEM_FLAVOR: dict[str, str] = {
    "potion": "A dusty bottle that smells faintly of mint. Every adventurer's first purchase, last resort, and half their inventory weight.",
    "hi_potion": "A larger bottle with a wax seal bearing a tower insignia. The apothecary's note says: use sparingly. Everyone uses it often.",
    "mega_potion": "Looks like regular potion, shares like a miracle. The label claims it was blessed. The label is printed. The blessing is questionable.",
    "elixir": "A rare vial of silver liquid, cold to the touch and faintly humming. Wasted on common fights. Exactly correct for the one you barely survive.",
    "ether": "A pale blue tincture distilled from focused concentration and regrets. Tastes like remembering why you left home.",
    "hi_ether": "A refined ether in a glass vial with gilt etching. The etching reads, in tiny script: drink now, balance the ledger later.",
    "mega_ether": "A bulk-order ether with a sloshing echo. Restores a little to everyone. Nobody is grateful enough for how many there used to be.",
    "antidote": "Bitter herbs in cloudy water. It will cure the poison. It will not make you happy about having been poisoned.",
    "echo_herbs": "A small pouch of crushed leaves. Sprinkled on the tongue, the words come back. Sprinkled in the wind, so does the wind.",
    "remedy": "A cure-all tonic from a village apothecary who has seen it all and is, frankly, tired. Cures every status effect. Does not cure despair.",
    "phoenix_down": "A single feather, perpetually warm. It feels impatient to its holder, as if it has somewhere else to be.",
    "power_drink": "A vile, muscle-brown concoction that tastes like a grudge. Increases attack. Does not increase judgment.",
    "speed_tonic": "A carbonated tonic that fizzes louder than it should. Drink it fast, which is the point.",
    "defense_tonic": "A thick, pond-colored syrup that coats the throat. Slows nothing. Hardens everything else.",
    "magic_tonic": "A cobalt potion with a single swirl of silver that refuses to mix. Sharpens the edge of spellwork for a short while.",
    "bomb_fragment": "A volatile chunk of compressed heat, wrapped in oiled cloth. Warning: the cloth is decorative, not protective.",
    "arctic_wind": "A sealed glass sphere containing a single indignant gust of north wind. Breaks open loud. Ends louder.",
    "x_potion": "A potion so concentrated the apothecary charges by the drop. Fully restores one ally. Also fully depletes one coin purse.",
    "smoke_bomb": "A rice-paper ball packed with alchemist's smoke. Throws badly, works perfectly. Will not fool any boss who has read the manual.",
    "tent": "Oiled canvas folded to the size of a brick. Rest inside and your body remembers it was alive. Unreasonably heavy considering.",
    "eye_drops": "A small vial with a dropper made of twisted silver. Clears blindness. Does not clear whatever you were blinded looking at.",
    "gold_needle": "A thin needle of gold alloy. Applied to petrified flesh, it reminds the flesh it was flesh. Reusable, though no one tries.",
    "lightning_bolt": "A slim metal rod that hums if you hold it wrong. Legal in all but three kingdoms. Hurled, not thrown.",
    "holy_water": "Spring water blessed at dawn by someone sincere. The water has opinions about the undead. Living things are fine by it.",
    "repel": "A small paper charm with a faint garlic smell. Keeps monsters incurious for fifty steps. Walk briskly.",
}

# ── Weapons ────────────────────────────────────────────────────────────────
WEAPON_FLAVOR: dict[str, str] = {
    "bronze_sword": "A starter sword. Dull at the tip, slightly bent in the middle, honestly did its best. Will be replaced within the hour.",
    "iron_sword": "A soldier's working blade. Balanced, unfancy, reliable — three virtues that, combined, have outlasted many heroes.",
    "steel_sword": "A smith's pride. The fuller is straight, the hilt is wrapped in real leather, and the edge will hold through the second act.",
    "flame_sword": "A sword whose blade is always a little too warm to sheath. The leather scabbard has been replaced twice.",
    "ice_blade": "Translucent at the edge, rimed with frost that never quite melts. Do not rest your hand against the blade to check.",
    "mythril_sword": "Forged from the silver ore that costs more than villages. Featherlight and mean. Most of its weight is in its reputation.",
    "war_axe": "Heavy enough to count as a workout. Lands once, lands hard, leaves you breathing. The wielder, and the target, both.",
    "wooden_staff": "A walking stick that insists it is a weapon. Occasionally, and with enough magic, correct.",
    "oak_staff": "Seasoned oak, oil-rubbed, carved with small marks from the hands of the previous owner. Conducts a little more than wind.",
    "crystal_staff": "A staff with a faceted crystal bound at the head. The crystal is always a few degrees colder than the room.",
    "holy_staff": "A staff with a relic embedded in its crown — officially blessed, unofficially thrice-blessed because the priest felt strongly.",
    "bone_staff": "A staff made from bones that have kept their opinion of being staves. It clatters when no one is looking.",
    "thunder_rod": "A metal rod that crackles faintly when humidity is high. Best used in dry weather. Best dropped in wet.",
    "shadow_rod": "A rod of black wood that seems to drink the light near it. Casters say it is cold. Casters also say it is patient.",
    "iron_dagger": "A plain blade for plain work. No embellishment. The pommel has a single scratch in it that the thief insists they didn't make.",
    "mythril_dagger": "Light enough to throw, balanced enough to not want to. Hides comfortably inside a sleeve, which is usually the point.",
    "poison_dagger": "A dagger with a channel in the blade that holds something unpleasant. Re-applied after every fight. Smell before storage.",
    "sleep_dagger": "A curved blade coated in soporific resin. Enemies hit by it sometimes simply lay down. It is polite, in its way.",
    "assassin_blade": "A wickedly curved obsidian dagger that is a lot of words to describe a deeply focused piece of volcanic glass.",
}

# ── Armors ─────────────────────────────────────────────────────────────────
ARMOR_FLAVOR: dict[str, str] = {
    "leather_armor": "Hardened calfskin over padded linen. Smells like barn. Fights like you spent your last coin on it, because you did.",
    "iron_armor": "A soldier's issue. Loud, inflexible, conclusive. The joints squeak. Tell your healer not to stand downwind.",
    "chain_mail": "Thousands of interlocking rings. Each is a compromise between protection and shoulder pain. Compromise is working.",
    "dragon_mail": "Scales layered over a plate substrate, still faintly warm. The scales remember. The wearer does not ask about what.",
    "cloth_robe": "A simple caster's robe, woven by someone's aunt. The hem has been taken up three times. The inner pocket has a sweet in it, from before.",
    "mage_robe": "Dyed wool robes with silver thread sewn along the lines of a minor ward. The ward is real. The thread is decorative.",
    "dark_robe": "A robe whose dye will not fade, whose stitches cannot be picked out, whose hem seems a little wetter than the weather accounts for.",
    "sage_robe": "A robe of fine wool, layered with silk, embroidered with a language older than all present. Augments magic. Insists on being folded.",
    "thief_garb": "Black cloth, soft-soled shoes, pockets that are not where you expect. Designed to be forgotten when seen.",
    "ninja_garb": "Lightweight, quiet, the color of shadows at 3am. Prioritizes speed over sense. Sense is overrated anyway.",
    "mythril_vest": "A woven vest with mythril strands running through it. Weighs nothing. Announces nothing. Saves the day more often than it should.",
    "bone_armor": "Plates carved from monster bones, bound with sinew, still faintly cold. The bones hold a grudge that is now yours.",
}

# ── Accessories ────────────────────────────────────────────────────────────
ACCESSORY_FLAVOR: dict[str, str] = {
    "power_ring": "A heavy iron band, larger than it looks. Fingers that wear it often form opinions about door frames.",
    "magic_ring": "A thin silver ring etched with a single sigil. The sigil is for focus. The wearer notices the focus but cannot name it.",
    "speed_boots": "Boots soled with something that grips more than it should. The laces tie themselves. Nobody has asked why.",
    "hp_amulet": "An amulet that is always slightly warm. Increases maximum HP by the sheer force of insisting you'll be fine.",
    "mp_amulet": "A crystal pendant on a silver chain. It is said the crystal holds a thought. When you cast, the thought leaves. It comes back.",
    "lucky_charm": "A four-leaf clover pressed under glass, bound to a leather cord. The fourth leaf was, frankly, squint-worthy. It still counts.",
    "glass_amulet": "Brittle, beautiful, impossibly sharp when struck. Boosts damage dramatically. Will crack at the worst moment. This is part of its charm.",
    "barrier_ring": "A plain silver band with a faint hum. The hum is the ring holding back the air in front of you. Do not stop wearing it suddenly.",
    "resist_ring": "A ring of dark iron, cold to the touch. Small comfort against status effects, except on the one day you need it most, when it is large.",
    "thiefs_glove": "A single glove of supple leather, stitched with invisible thread. Whatever you touch leaves a faint impression of being taken.",
    "warriors_belt": "Thick tooled leather, worn shiny in the center. The belt holds you upright. The belt, frankly, is the only one in the outfit working.",
    "elven_cloak": "A cloak that shifts color in the light. Spoken of in the villages; never seen when in use. The wearer is harder to hit and harder to remember.",
}


def main() -> None:
    # items.json — inject flavor into top-level dict
    with ITEMS.open() as f:
        items = json.load(f)

    missing_items = [k for k in items if k not in ITEM_FLAVOR]
    extra_items = [k for k in ITEM_FLAVOR if k not in items]
    assert not missing_items, f"items missing flavor: {missing_items}"
    assert not extra_items, f"flavor for unknown items: {extra_items}"

    for k, v in items.items():
        v["flavor"] = ITEM_FLAVOR[k]

    serialized = json.dumps(items, indent="\t", ensure_ascii=False)
    ITEMS.write_text(compact_primitive_arrays(serialized) + "\n")
    print(f"Wrote {ITEMS} with flavor on {len(items)} consumables.")

    # equipment.json — inject flavor into weapons / armors / accessories
    with EQUIPMENT.open() as f:
        equipment = json.load(f)

    for section, table in (
        ("weapons", WEAPON_FLAVOR),
        ("armors", ARMOR_FLAVOR),
        ("accessories", ACCESSORY_FLAVOR),
    ):
        bucket = equipment.get(section, {})
        missing = [k for k in bucket if k not in table]
        extra = [k for k in table if k not in bucket]
        assert not missing, f"{section} missing flavor: {missing}"
        assert not extra, f"flavor for unknown {section}: {extra}"
        for k, v in bucket.items():
            v["flavor"] = table[k]

    serialized = json.dumps(equipment, indent="\t", ensure_ascii=False)
    EQUIPMENT.write_text(compact_primitive_arrays(serialized) + "\n")
    total = sum(len(equipment.get(s, {})) for s in ("weapons", "armors", "accessories"))
    print(f"Wrote {EQUIPMENT} with flavor on {total} equipment pieces.")


if __name__ == "__main__":
    main()
