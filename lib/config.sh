#!/bin/bash
# config.sh — All configurable values in one place.
# Edit this file to customize your homekase setup.

# ── Paths ──
HOMELAB_DIR="/opt/homelab"
DATA_DIR="/data"
STORAGE_DIR="/storage"

# ── Repositories ──
HOMEKASE_REPO="https://github.com/FabriSilve/homekase.git"
ASSISTANT_REPO="https://github.com/FabriSilve/homekase-assistant.git"

# ── AI Assistant ──
# Model tiers: qwen2.5:14b (excellent), qwen2.5:7b (good), qwen2.5:3b (basic)
# Auto-selected based on available RAM, or override here:
# ASSISTANT_MODEL_OVERRIDE=""

# RAM thresholds for model recommendation (MB)
ASSISTANT_RAM_EXCELLENT=12288   # 12GB → 14B model
ASSISTANT_RAM_GOOD=7168         # 7GB  → 7B model
ASSISTANT_RAM_BASIC=4096        # 4GB  → 3B model
