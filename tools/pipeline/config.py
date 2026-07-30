from pathlib import Path

# ── Directory Paths ──────────────────────────────────────────────────────────
COMFYUI_DIR = Path("/home/struktured/projects/ComfyUI")
PROJECT_DIR = Path("/home/struktured/projects/cowardly-irregular-sprite-gen")
MODELS_DIR = COMFYUI_DIR / "models"
OUTPUT_DIR = PROJECT_DIR / "tmp" / "generated"
REFERENCE_DIR = PROJECT_DIR / "assets" / "sprites" / "jobs" / "fighter"

# ── Model Paths ──────────────────────────────────────────────────────────────
SDXL_CHECKPOINT = MODELS_DIR / "checkpoints" / "sd_xl_base_1.0.safetensors"
PIXEL_ART_LORA = MODELS_DIR / "loras" / "fighter_ci_pixel_500.safetensors"
STYLE_LORA = MODELS_DIR / "loras" / "jrpg_pixel_style.safetensors"

IPADAPTER_DIR = COMFYUI_DIR / "models" / "ipadapter"
IPADAPTER_WEIGHTS = IPADAPTER_DIR / "sdxl_models" / "ip-adapter-plus_sdxl_vit-h.safetensors"
CLIP_ENCODER_DIR = IPADAPTER_DIR / "models" / "image_encoder"

CONTROLNET_OPENPOSE_ID = "xinsir/controlnet-openpose-sdxl-1.0"

# ── Generation Constants ─────────────────────────────────────────────────────
FRAME_W = 256
FRAME_H = 256

ANIMATIONS = ["idle", "walk", "attack", "hit", "dead", "cast", "defend", "item", "victory"]

FRAME_COUNTS = {
    "idle": 2,
    "walk": 6,
    "attack": 6,
    "hit": 4,
    "dead": 4,
    "cast": 4,
    "defend": 4,
    "item": 4,
    "victory": 4,
}
