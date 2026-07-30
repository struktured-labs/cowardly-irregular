#!/bin/bash
# Train SDXL LoRA for generic JRPG pixel art style (jrpg_pixel_style)
# Covers shared visual language across all Cowardly Irregular jobs.
# Uses kohya_ss/sd-scripts sdxl_train_network.py
set -euo pipefail

# Paths
KOHYA_DIR="/home/struktured/projects/kohya_ss"
SDSCRIPTS="${KOHYA_DIR}/sd-scripts"
VENV="${KOHYA_DIR}/.venv/bin/python"
TRAIN_DIR="/home/struktured/projects/cowardly-irregular-sprite-gen/tools/lora_training"
DATASET_DIR="${TRAIN_DIR}/style_dataset"
CHECKPOINT_DIR="${TRAIN_DIR}/checkpoints"
SAMPLE_DIR="${TRAIN_DIR}/samples"
LOG_DIR="${TRAIN_DIR}/logs"
LORA_FINAL="/home/struktured/projects/ComfyUI/models/loras/jrpg_pixel_style.safetensors"
MODEL_PATH="/home/struktured/projects/ComfyUI/models/checkpoints/sd_xl_base_1.0.safetensors"
SAMPLE_PROMPTS="${TRAIN_DIR}/sample_prompts.txt"

# Allow overriding max_train_steps via first argument
MAX_TRAIN_STEPS="${1:-3000}"

mkdir -p "${CHECKPOINT_DIR}" "${SAMPLE_DIR}" "${LOG_DIR}"

echo "=== Starting SDXL style LoRA training ==="
echo "LoRA name : jrpg_pixel_style"
echo "Max steps : ${MAX_TRAIN_STEPS}"
echo "Dataset   : ${DATASET_DIR}"
echo "Model     : ${MODEL_PATH}"
echo "Checkpts  : ${CHECKPOINT_DIR}"
echo "Final out : ${LORA_FINAL}"
echo ""

"${VENV}" "${SDSCRIPTS}/sdxl_train_network.py" \
  --pretrained_model_name_or_path="${MODEL_PATH}" \
  --train_data_dir="${DATASET_DIR}" \
  --output_dir="${CHECKPOINT_DIR}" \
  --output_name="jrpg_pixel_style" \
  --save_model_as="safetensors" \
  --resolution="512,512" \
  --train_batch_size=4 \
  --gradient_accumulation_steps=1 \
  --max_train_steps="${MAX_TRAIN_STEPS}" \
  --learning_rate=0.00008 \
  --unet_lr=0.00008 \
  --text_encoder_lr=4e-05 \
  --lr_scheduler="cosine_with_restarts" \
  --lr_warmup_steps=150 \
  --lr_scheduler_num_cycles=3 \
  --optimizer_type="AdamW8bit" \
  --mixed_precision="bf16" \
  --save_precision="bf16" \
  --xformers \
  --enable_bucket \
  --bucket_no_upscale \
  --min_bucket_reso=128 \
  --max_bucket_reso=512 \
  --caption_extension=".txt" \
  --caption_prefix="jrpg_pixel_style, " \
  --keep_tokens=1 \
  --shuffle_caption \
  --caption_dropout_rate=0.1 \
  --noise_offset=0.05 \
  --cache_latents \
  --cache_latents_to_disk \
  --network_module="networks.lora" \
  --network_dim=64 \
  --network_alpha=32 \
  --save_every_n_steps=500 \
  --sample_every_n_steps=250 \
  --sample_prompts="${SAMPLE_PROMPTS}" \
  --sample_sampler="euler_a" \
  --seed=42 \
  --logging_dir="${LOG_DIR}" \
  --log_prefix="style_lora_" \
  --full_bf16 \
  --max_data_loader_n_workers=4 \
  --persistent_data_loader_workers \
  2>&1 | tee "${LOG_DIR}/style_training_$(date +%Y%m%d_%H%M%S).log"

# Copy final checkpoint to ComfyUI loras directory
echo ""
echo "=== Copying final LoRA to ComfyUI ==="
cp "${CHECKPOINT_DIR}/jrpg_pixel_style.safetensors" "${LORA_FINAL}"
echo "Saved to: ${LORA_FINAL}"
echo "Checkpoints saved in: ${CHECKPOINT_DIR}"
ls -lh "${CHECKPOINT_DIR}"/jrpg_pixel_style*.safetensors
echo "=== Training complete ==="
