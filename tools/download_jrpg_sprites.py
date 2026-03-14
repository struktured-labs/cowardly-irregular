#!/usr/bin/env python3
"""
Download JRPG battle sprite sheets from spriters-resource.com for LoRA training.

Fetches each asset page to resolve the real /media/assets/<folder>/<id>.png URL,
then downloads the image. Folder numbers are not predictable from the asset ID alone.
"""

import re
import time
import sys
from pathlib import Path
import urllib.request
import urllib.error

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_BASE = REPO_ROOT / "tools" / "lora_training" / "raw_jrpg_sprites"

BASE_SITE = "https://www.spriters-resource.com"

PAGE_HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0",
    "Referer": "https://www.spriters-resource.com/",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
}

IMG_HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0",
    "Referer": "https://www.spriters-resource.com/",
    "Accept": "image/avif,image/webp,*/*",
}

# Cache resolved media URLs to avoid re-fetching asset pages
_media_url_cache: dict[int, str] = {}

# Battle/character sprite sheets only — no backgrounds, no enemies, no UI
# Format: (asset_id, name, asset_page_path)
SPRITE_SHEETS: dict[str, list[tuple[int, str, str]]] = {
    "final_fantasy_iv": [
        (5207, "cecil_dark_knight",  "/snes/ff4/asset/5207/"),
        (5204, "cecil_paladin",      "/snes/ff4/asset/5204/"),
        (5212, "kain",               "/snes/ff4/asset/5212/"),
        (5226, "rydia_child",        "/snes/ff4/asset/5226/"),
        (5222, "rydia_adult",        "/snes/ff4/asset/5222/"),
        (5221, "rosa",               "/snes/ff4/asset/5221/"),
        (5223, "tellah",             "/snes/ff4/asset/5223/"),
        (5225, "yang",               "/snes/ff4/asset/5225/"),
        (5219, "palom",              "/snes/ff4/asset/5219/"),
        (5220, "porom",              "/snes/ff4/asset/5220/"),
        (5209, "edward",             "/snes/ff4/asset/5209/"),
        (5205, "cid",                "/snes/ff4/asset/5205/"),
        (5208, "edge",               "/snes/ff4/asset/5208/"),
        (5211, "fusoya",             "/snes/ff4/asset/5211/"),
    ],
    "final_fantasy_v": [
        (31541, "bartz",  "/snes/ff5/asset/31541/"),
        (31543, "faris",  "/snes/ff5/asset/31543/"),
        (31544, "galuf",  "/snes/ff5/asset/31544/"),
        (31542, "krile",  "/snes/ff5/asset/31542/"),
        (31545, "lenna",  "/snes/ff5/asset/31545/"),
    ],
    "final_fantasy_vi": [
        (5830, "celes",       "/snes/ff6/asset/5830/"),
        (5836, "cyan",        "/snes/ff6/asset/5836/"),
        (5844, "edgar",       "/snes/ff6/asset/5844/"),
        (6646, "gau",         "/snes/ff6/asset/6646/"),
        (6649, "gogo",        "/snes/ff6/asset/6649/"),
        (6666, "locke",       "/snes/ff6/asset/6666/"),
        (6680, "mog",         "/snes/ff6/asset/6680/"),
        (6692, "relm",        "/snes/ff6/asset/6692/"),
        (6699, "sabin",       "/snes/ff6/asset/6699/"),
        (6700, "setzer",      "/snes/ff6/asset/6700/"),
        (6702, "shadow",      "/snes/ff6/asset/6702/"),
        (6706, "strago",      "/snes/ff6/asset/6706/"),
        (6707, "terra",       "/snes/ff6/asset/6707/"),
        (5847, "terra_esper", "/snes/ff6/asset/5847/"),
        (6795, "umaro",       "/snes/ff6/asset/6795/"),
    ],
    "chrono_trigger": [
        (2514, "crono",          "/snes/chronotrigger/asset/2514/"),
        (3617, "marle",          "/snes/chronotrigger/asset/3617/"),
        (3614, "lucca",          "/snes/chronotrigger/asset/3614/"),
        (3570, "frog",           "/snes/chronotrigger/asset/3570/"),
        (3651, "robo",           "/snes/chronotrigger/asset/3651/"),
        (2511, "ayla",           "/snes/chronotrigger/asset/2511/"),
        (3615, "magus",          "/snes/chronotrigger/asset/3615/"),
        (3642, "characters_all", "/snes/chronotrigger/asset/3642/"),
    ],
    "breath_of_fire": [
        (268180, "protagonists_battle", "/snes/breathfire/asset/268180/"),
    ],
    "breath_of_fire_ii": [
        (263551, "protagonists_battle",          "/snes/breathfire2/asset/263551/"),
        (264145, "fused_protagonists_battle",    "/snes/breathfire2/asset/264145/"),
        (20123,  "ryu_dragon_transformations",   "/snes/breathfire2/asset/20123/"),
        (261953, "ryu_jean_valerie_transformed", "/snes/breathfire2/asset/261953/"),
    ],
    "secret_of_mana": [
        (129980, "randi", "/snes/secretofmana/asset/129980/"),
        (129981, "primm", "/snes/secretofmana/asset/129981/"),
        (129982, "popoi", "/snes/secretofmana/asset/129982/"),
    ],
    "earthbound": [
        (104953, "ness",  "/snes/earthbound/asset/104953/"),
        (104954, "paula", "/snes/earthbound/asset/104954/"),
        (104955, "jeff",  "/snes/earthbound/asset/104955/"),
        (104956, "poo",   "/snes/earthbound/asset/104956/"),
    ],
    "final_fantasy_dawn_of_souls": [
        (19338, "ff1_battle_sprites", "/game_boy_advance/finalfantasy1dawnofsouls/asset/19338/"),
        (25036, "ff2_firion",         "/game_boy_advance/finalfantasy2dawnofsouls/asset/25036/"),
        (25037, "ff2_gordon",         "/game_boy_advance/finalfantasy2dawnofsouls/asset/25037/"),
        (25038, "ff2_guy",            "/game_boy_advance/finalfantasy2dawnofsouls/asset/25038/"),
        (25040, "ff2_josef",          "/game_boy_advance/finalfantasy2dawnofsouls/asset/25040/"),
        (25041, "ff2_leila",          "/game_boy_advance/finalfantasy2dawnofsouls/asset/25041/"),
        (25042, "ff2_leon",           "/game_boy_advance/finalfantasy2dawnofsouls/asset/25042/"),
        (25043, "ff2_maria",          "/game_boy_advance/finalfantasy2dawnofsouls/asset/25043/"),
        (25022, "ff2_minwu",          "/game_boy_advance/finalfantasy2dawnofsouls/asset/25022/"),
        (25024, "ff2_ricard",         "/game_boy_advance/finalfantasy2dawnofsouls/asset/25024/"),
        (25045, "ff2_scott",          "/game_boy_advance/finalfantasy2dawnofsouls/asset/25045/"),
    ],
    "final_fantasy_tactics": [
        (1313, "squire_male",        "/playstation/fft/asset/1313/"),
        (1314, "squire_female",      "/playstation/fft/asset/1314/"),
        (1288, "chemist_male",       "/playstation/fft/asset/1288/"),
        (1289, "chemist_female",     "/playstation/fft/asset/1289/"),
        (1294, "knight_male",        "/playstation/fft/asset/1294/"),
        (1295, "knight_female",      "/playstation/fft/asset/1295/"),
        (1262, "archer_male",        "/playstation/fft/asset/1262/"),
        (1280, "archer_female",      "/playstation/fft/asset/1280/"),
        (1322, "white_mage_male",    "/playstation/fft/asset/1322/"),
        (1323, "white_mage_female",  "/playstation/fft/asset/1323/"),
        (1284, "black_mage_male",    "/playstation/fft/asset/1284/"),
        (1285, "black_mage_female",  "/playstation/fft/asset/1285/"),
        (1292, "geomancer_male",     "/playstation/fft/asset/1292/"),
        (1293, "geomancer_female",   "/playstation/fft/asset/1293/"),
        (1318, "thief_male",         "/playstation/fft/asset/1318/"),
        (1319, "thief_female",       "/playstation/fft/asset/1319/"),
        (1290, "dragoon_male",       "/playstation/fft/asset/1290/"),
        (1291, "dragoon_female",     "/playstation/fft/asset/1291/"),
        (1301, "monk_male",          "/playstation/fft/asset/1301/"),
        (1303, "monk_female",        "/playstation/fft/asset/1303/"),
        (1320, "time_mage_male",     "/playstation/fft/asset/1320/"),
        (1321, "time_mage_female",   "/playstation/fft/asset/1321/"),
        (1315, "summoner_male",      "/playstation/fft/asset/1315/"),
        (1317, "summoner_female",    "/playstation/fft/asset/1317/"),
        (1311, "samurai_male",       "/playstation/fft/asset/1311/"),
        (1312, "samurai_female",     "/playstation/fft/asset/1312/"),
        (1305, "ninja_male",         "/playstation/fft/asset/1305/"),
        (1308, "ninja_female",       "/playstation/fft/asset/1308/"),
        (1296, "mediator_male",      "/playstation/fft/asset/1296/"),
        (1297, "mediator_female",    "/playstation/fft/asset/1297/"),
        (1299, "mime_male",          "/playstation/fft/asset/1299/"),
        (1300, "mime_female",        "/playstation/fft/asset/1300/"),
        (1309, "oracle_male",        "/playstation/fft/asset/1309/"),
        (1310, "oracle_female",      "/playstation/fft/asset/1310/"),
        (1282, "bard",               "/playstation/fft/asset/1282/"),
        (1286, "calculator_male",    "/playstation/fft/asset/1286/"),
        (1287, "calculator_female",  "/playstation/fft/asset/1287/"),
        (1345, "dancer",             "/playstation/fft/asset/1345/"),
        (1266, "agrias",             "/playstation/fft/asset/1266/"),
        (1388, "rafa",               "/playstation/fft/asset/1388/"),
    ],
    "octopath_traveler": [
        (113913, "ophilia_cleric",    "/nintendo_switch/octopathtraveler/asset/113913/"),
        (116005, "cyrus_scholar",     "/nintendo_switch/octopathtraveler/asset/116005/"),
        (116031, "tressa_merchant",   "/nintendo_switch/octopathtraveler/asset/116031/"),
        (116030, "olberic_warrior",   "/nintendo_switch/octopathtraveler/asset/116030/"),
        (116033, "primrose_dancer",   "/nintendo_switch/octopathtraveler/asset/116033/"),
        (113459, "alfyn_apothecary",  "/nintendo_switch/octopathtraveler/asset/113459/"),
        (116032, "therion_thief",     "/nintendo_switch/octopathtraveler/asset/116032/"),
        (116029, "haanit_hunter",     "/nintendo_switch/octopathtraveler/asset/116029/"),
    ],
}


def resolve_media_url(asset_id: int, asset_page_path: str) -> str | None:
    """Fetch the asset page and extract the /media/assets/... URL."""
    if asset_id in _media_url_cache:
        return _media_url_cache[asset_id]

    page_url = f"{BASE_SITE}{asset_page_path}"
    req = urllib.request.Request(page_url, headers=PAGE_HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            html = resp.read().decode("utf-8", errors="replace")
    except Exception as exc:
        print(f"  [err]  could not fetch asset page {page_url}: {exc}")
        return None

    # Match /media/assets/<folder>/<id>.png or .gif (with optional ?updated=...)
    match = re.search(r'(/media/assets/\d+/\d+\.(?:png|gif))(?:\?[^"\']*)?', html)
    if not match:
        return None

    media_path = match.group(1)
    full_url = f"{BASE_SITE}{media_path}"
    _media_url_cache[asset_id] = full_url
    return full_url


def download_sheet(asset_id: int, asset_page_path: str, dest: Path) -> bool:
    for ext in (".png", ".gif"):
        if dest.with_suffix(ext).exists():
            print(f"  [skip] {dest.with_suffix(ext).name} already exists")
            return True

    media_url = resolve_media_url(asset_id, asset_page_path)
    if not media_url:
        print(f"  [err]  {dest.stem} — could not resolve media URL (asset {asset_id})")
        return False

    ext = ".gif" if media_url.endswith(".gif") else ".png"
    actual_dest = dest.with_suffix(ext)

    req = urllib.request.Request(media_url, headers=IMG_HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = resp.read()
        actual_dest.write_bytes(data)
        size_kb = len(data) / 1024
        print(f"  [ok]   {actual_dest.name}  ({size_kb:.1f} KB)")
        return True
    except urllib.error.HTTPError as e:
        print(f"  [err]  {actual_dest.name} — HTTP {e.code}: {media_url}")
        return False
    except Exception as exc:
        print(f"  [err]  {actual_dest.name} — {exc}: {media_url}")
        return False


def main() -> int:
    total = sum(len(v) for v in SPRITE_SHEETS.values())
    done = 0
    failed = []

    for game, sheets in SPRITE_SHEETS.items():
        game_dir = OUT_BASE / game
        game_dir.mkdir(parents=True, exist_ok=True)
        print(f"\n{game} ({len(sheets)} sheets)")
        for asset_id, name, page_path in sheets:
            dest = game_dir / f"{name}_{asset_id}.png"
            ok = download_sheet(asset_id, page_path, dest)
            if not ok:
                failed.append((game, name, asset_id))
            else:
                done += 1
            time.sleep(0.5)

    print(f"\n--- Summary ---")
    print(f"Downloaded: {done}/{total}")
    if failed:
        print(f"Failed ({len(failed)}):")
        for game, name, aid in failed:
            print(f"  {game}/{name} (id={aid})")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
