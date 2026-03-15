import torch
from .config import (
    SDXL_CHECKPOINT,
    PIXEL_ART_LORA,
    STYLE_LORA,
    IPADAPTER_DIR,
    IPADAPTER_WEIGHTS,
    CLIP_ENCODER_DIR,
    CONTROLNET_OPENPOSE_ID,
)


def load_pipeline(
    use_ipadapter: bool = True,
    lora_mode: str = "fighter",
    use_controlnet: bool = False,
):
    """Load SDXL + optional LoRA + optional ControlNet + optional IP-Adapter pipeline.

    lora_mode:
        "fighter" - loads fighter_ci_pixel_500.safetensors
        "style"   - loads jrpg_pixel_style.safetensors
        "none"    - skips LoRA entirely

    use_controlnet:
        True  - uses StableDiffusionXLControlNetPipeline with xinsir openpose controlnet
        False - uses StableDiffusionXLPipeline (default)
    """
    from diffusers import StableDiffusionXLPipeline, DDIMScheduler

    # Load image encoder for IP-Adapter if needed
    if use_ipadapter and CLIP_ENCODER_DIR.exists():
        from transformers import CLIPVisionModelWithProjection
        print("Loading CLIP ViT-H image encoder...")
        image_encoder = CLIPVisionModelWithProjection.from_pretrained(
            str(CLIP_ENCODER_DIR),
            torch_dtype=torch.float16,
        )
    else:
        image_encoder = None

    # Load ControlNet if requested
    controlnet = None
    if use_controlnet:
        from diffusers import ControlNetModel
        print(f"Loading ControlNet from {CONTROLNET_OPENPOSE_ID}...")
        controlnet = ControlNetModel.from_pretrained(
            CONTROLNET_OPENPOSE_ID,
            torch_dtype=torch.float16,
        )

    # Select pipeline class based on controlnet usage
    if use_controlnet and controlnet is not None:
        from diffusers import StableDiffusionXLControlNetPipeline
        pipeline_cls = StableDiffusionXLControlNetPipeline
        print(f"Loading SDXL+ControlNet pipeline from {SDXL_CHECKPOINT}...")
        pipe = pipeline_cls.from_single_file(
            str(SDXL_CHECKPOINT),
            controlnet=controlnet,
            image_encoder=image_encoder,
            torch_dtype=torch.float16,
            use_safetensors=True,
        )
    else:
        print(f"Loading SDXL from {SDXL_CHECKPOINT}...")
        pipe = StableDiffusionXLPipeline.from_single_file(
            str(SDXL_CHECKPOINT),
            image_encoder=image_encoder,
            torch_dtype=torch.float16,
            use_safetensors=True,
        )

    # DDIM scheduler recommended for IP-Adapter face models
    if use_ipadapter:
        pipe.scheduler = DDIMScheduler.from_config(pipe.scheduler.config)

    # Load IP-Adapter BEFORE LoRA
    if use_ipadapter and IPADAPTER_WEIGHTS.exists():
        print("Loading IP-Adapter Plus Face...")
        pipe.load_ip_adapter(
            str(IPADAPTER_DIR),
            subfolder="sdxl_models",
            weight_name="ip-adapter-plus_sdxl_vit-h.safetensors",
        )
        pipe.set_ip_adapter_scale(0.45)
        print("  IP-Adapter scale: 0.45")
    else:
        if use_ipadapter:
            print("WARNING: IP-Adapter weights not found, generating without identity lock")

    # Load LoRA AFTER IP-Adapter
    if lora_mode == "fighter":
        if PIXEL_ART_LORA.exists():
            print("Loading custom fighter_ci_pixel LoRA...")
            pipe.load_lora_weights(str(PIXEL_ART_LORA.parent), weight_name=PIXEL_ART_LORA.name)
            pipe.fuse_lora(lora_scale=0.5)
        else:
            print("WARNING: fighter LoRA not found, skipping")
    elif lora_mode == "style":
        if STYLE_LORA.exists():
            print("Loading jrpg_pixel_style LoRA...")
            pipe.load_lora_weights(str(STYLE_LORA.parent), weight_name=STYLE_LORA.name)
            pipe.fuse_lora(lora_scale=0.7)
        else:
            print("WARNING: style LoRA not found, skipping")
    elif lora_mode == "none":
        print("Skipping LoRA (lora_mode=none)")
    else:
        print(f"WARNING: unknown lora_mode '{lora_mode}', skipping LoRA")

    # Memory optimization LAST (after all adapters loaded)
    pipe.enable_model_cpu_offload()
    pipe.enable_vae_slicing()

    return pipe
