<!--
Document : spec_delete_ori.md
Auteur : Bruno DELNOZ
Email : bruno.delnoz@protonmail.com
Version : v1.1.0
Date : 2026-04-20 00:00
-->
# Specification Note - `--delete-ori` Option

## Objective

This document preserves the design intent of adding `--delete-ori` to remove the original MP4 only after a valid boosted output is confirmed.

## Repository status

- The lightweight script `record_cam_v3.2.sh` includes `--delete-ori`.
- The main operational script `record_cam.sh` does **not** expose `--delete-ori` as a CLI argument.
- In `record_cam.sh`, original segment deletion is already embedded in `boost_audio()` after successful boost output generation.

## Behavior in `record_cam_v3.2.sh`

1. `--volume` triggers audio boost for `output.mp4`.
2. Boosted file is written under `./boost/`.
3. `ffprobe` verifies output stream validity.
4. If `--delete-ori` is enabled and verification succeeds, original MP4 is deleted.
5. If verification fails, original file is retained.

## Usage example (`record_cam_v3.2.sh`)

```bash
./record_cam_v3.2.sh --volume --delete-ori
```

## Consistency note

For users operating `record_cam.sh`, deletion semantics are tied to successful boost processing without a dedicated `--delete-ori` flag.
