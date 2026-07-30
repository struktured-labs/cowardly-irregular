import numpy as np
from PIL import Image


def validate_single_character(img: Image.Image) -> tuple[bool, str]:
    """Check if the image contains a single character (not multiple or a sheet).

    Returns (is_valid, reason).
    """
    from scipy import ndimage

    arr = np.array(img)
    mask = arr[:, :, 3] > 10

    if not mask.any():
        return False, "empty frame"

    labeled, n_components = ndimage.label(mask, structure=ndimage.generate_binary_structure(2, 2))

    if n_components == 0:
        return False, "no character found"

    component_sizes = []
    for i in range(1, n_components + 1):
        component_sizes.append((labeled == i).sum())
    component_sizes.sort(reverse=True)

    total_pixels = mask.sum()
    largest = component_sizes[0]

    if largest < total_pixels * 0.5:
        return False, f"largest component is only {largest/total_pixels:.0%} of pixels — likely multiple characters"

    if len(component_sizes) > 1 and component_sizes[1] > largest * 0.2:
        return False, f"second component is {component_sizes[1]/largest:.0%} of main — likely multiple characters"

    return True, "single character"
