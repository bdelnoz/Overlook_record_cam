<!--
Document : README.md
Auteur : Bruno DELNOZ
Email : bruno.delnoz@protonmail.com
Version : v1.1.0
Date : 2026-04-20 00:00
-->
# Overlook_record_cam

## Overview

This repository contains shell scripts to record the Linux desktop and system audio with `ffmpeg`, including segmentation, optional microphone mixing, audio post-processing, and motion-detection snapshots using ImageMagick.

The scripts currently present are:

- `record_cam.sh` → main script (header version `v3.0.1`, dated `2025-10-22`).
- `record_cam.v3.0.sh` → archived/stable v3.0 snapshot.
- `record_cam_v3.2.sh` → lightweight experimental script focused on `--delete-ori` behavior.
- `record_cam.LAST.sh` → legacy script variant.

## Main script behavior (`record_cam.sh`)

### Core recording

- Captures X11 screen using `ffmpeg` (`x11grab`).
- Captures system audio from PulseAudio monitor source (`--device`).
- Supports optional microphone mix (`--mic [DEVICE]`, `--no-mic`).
- Splits recording into segments (`--segment-duration`, default 2100s).
- Supports unlimited session by default (`TOTAL_DURATION=0`) or bounded duration via first positional numeric argument.

### Audio processing

- Applies a default post-processing filter chain (`highpass`, `lowpass`, `compand`) after each segment.
- If `--volume FLOAT` is provided, appends `volume=FLOAT` to the default chain.
- Writes processed files into `TARGET_DIR/BOOST/` and removes original segment file after successful processing.

### Motion detection (`--diff`)

- Optional parallel screenshot-based motion detection loop.
- Uses `import`, `compare`, `identify`, and `convert` from ImageMagick.
- Configurable with:
  - `--diff-target-dir DIR`
  - `--diff-duration SEC`
  - `--diff-interval SEC`
  - `--diff-threshold PCT`
  - `--diff-record-all`
- Generates `MOVEMENT_*.jpg` files with highlighted changed area when movement threshold is reached.

### File management and maintenance

- `--delete` / `--remove <base>`: moves matching files to timestamped backup directory.
- `--undelete <base>`: restores files from latest matching backup directory.
- `--prerequis`: checks dependencies.
- `--install`: installs missing packages (`apt-get`) when used with prerequisites flow.
- `--discover-devices`: lists audio capture devices.
- `--changelog`: prints embedded script changelog.

## CLI syntax summary

```bash
# Help
./record_cam.sh --help

# Unlimited recording with base name
./record_cam.sh MySession

# 1 hour recording in 10-minute segments
./record_cam.sh 3600 MySession --segment-duration 600

# Recording with microphone and extra volume
./record_cam.sh MySession --mic --volume 2.0

# Motion detection only
./record_cam.sh --diff --diff-duration 3600 --diff-interval 3 --diff-threshold 5

# Prerequisites check
./record_cam.sh --prerequis
```

## Current dependency set

- `bash`
- `ffmpeg`
- `xdpyinfo` (`x11-utils`)
- `ImageMagick` (`compare`, `identify`, `convert`, `import`) for `--diff`
- `pactl` (`pulseaudio-utils`) for `--mute-output` and device discovery
- `bc` optional (used for floating-point threshold comparison)

## Notes and constraints

- Scripts target X11-based Linux desktop capture flows.
- `record_cam.sh` parses `--simulate` as a flag requiring a following value (`true` expected to enable simulation).
- The repository currently contains multiple script generations; `record_cam.sh` should be considered the primary operational entrypoint.
