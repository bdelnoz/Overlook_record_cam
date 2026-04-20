<!--
Document : README_Overlook.md
Auteur : Bruno DELNOZ
Email : bruno.delnoz@protonmail.com
Version : v1.1.0
Date : 2026-04-20 00:00
-->
# Overlook - Operator Guide

## Purpose

Overlook provides continuous screen-and-audio capture workflows for incident review and retrospective analysis.

In this repository, the operational script is `record_cam.sh`, with historical variants (`record_cam.v3.0.sh`, `record_cam.LAST.sh`, `record_cam_v3.2.sh`) kept for comparison or fallback.

## What is recorded

- Desktop video stream from X11 display (`:0.0`).
- System audio monitor source.
- Optional microphone source mixed with system audio.
- Optional motion snapshots (diff loop) in parallel.

## Main operational features

- Timed segmentation of MP4 output.
- Optional total-duration stop.
- Optional output mute during recording (`--mute-output`) without impacting capture.
- Automatic post-processing of segments into `BOOST/` output files.
- Optional movement evidence images with highlighted bounding area.
- Safe delete/restore workflow with automatic backup foldering.

## Typical usage patterns

```bash
# 35-minute segments, unlimited duration
./record_cam.sh Patrol

# 2-hour run with 15-minute segments
./record_cam.sh 7200 Patrol --segment-duration 900

# Motion analysis only
./record_cam.sh --diff --diff-target-dir ./diff_output --diff-duration 1800

# Combined recording + motion detection
./record_cam.sh 3600 Patrol --diff --diff-interval 3 --diff-threshold 8
```

## Output conventions

- Video segments: `<base>_<timestamp>_part<index>.mp4`
- Post-processed audio/video: `TARGET_DIR/BOOST/*_boost.mp4`
- Motion captures: `capture_<timestamp>_<index>.png`
- Motion alerts: `MOVEMENT_<timestamp>_<counter>.jpg`
- Log file: `<script_basename>.v3.0.log` for current `record_cam.sh`

## Operational recommendations

- Run `./record_cam.sh --prerequis` before first production execution.
- Validate the PulseAudio monitor source with `--discover-devices` when audio capture is missing.
- Use dedicated `--target_dir` for long sessions to prevent mixed outputs.
- Prefer explicit `--diff-target-dir` when running multiple detection sessions.
