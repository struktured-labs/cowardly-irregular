from pathlib import Path

import torch
from PIL import Image


def compute_identity_embeddings(pipe, reference_image: Image.Image):
    """Pre-compute IP-Adapter embeddings from a reference image.

    These embeddings encode the character's visual identity and can be
    reused across all frame generations for consistency.
    """
    print("Computing identity embeddings from reference...")
    embeds = pipe.prepare_ip_adapter_image_embeds(
        ip_adapter_image=reference_image,
        ip_adapter_image_embeds=None,
        device="cuda",
        num_images_per_prompt=1,
        do_classifier_free_guidance=True,
    )
    print(f"  Embedding shape: {[e.shape for e in embeds]}")
    return embeds


def load_cached_embeddings(embeds_path: Path):
    """Load previously saved identity embeddings from disk, or return None."""
    if embeds_path.exists():
        print(f"Loading cached identity embeddings from {embeds_path}...")
        return torch.load(embeds_path)
    return None


def save_embeddings(embeds, embeds_path: Path):
    """Save identity embeddings to disk for reuse."""
    torch.save(embeds, embeds_path)
    print(f"  Identity embeddings saved: {embeds_path}")
