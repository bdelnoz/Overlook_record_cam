<!--
Document : Specification record_cam.sh v2.4 avec --diff argument.md
Auteur : Bruno DELNOZ
Email : bruno.delnoz@protonmail.com
Version : v1.1.0
Date : 2026-04-20 00:00
-->
# Specification Alignment Note - `record_cam.sh` Diff Features

## Scope

This document updates the historical v2.4 specification to align with the currently present implementation in `record_cam.sh` (script header version `v3.0.1`).

## Effective prerequisites

- `ffmpeg`
- `xdpyinfo` (`x11-utils`)
- `ImageMagick` commands (`compare`, `identify`, `convert`, `import`) when `--diff` is used
- `pulseaudio-utils` (`pactl`) when `--mute-output` is used
- `bc` optional for floating-point threshold checks

`--prerequis` runs prerequisite checks and can be combined with `--install` for automatic package installation.

## Effective diff/motion arguments

| Argument | Current behavior | Default |
| --- | --- | --- |
| `--diff` | Enables motion detection loop in parallel (or standalone if no base name is provided). | Off |
| `--diff-target-dir DIR` | Directory for screenshots and movement-marked images. | `./diff_output` |
| `--diff-duration SEC` | Detection activity duration (`0` means unlimited). | `0` |
| `--diff-interval SEC` | Delay between screenshot captures. | `3` |
| `--diff-threshold PCT` | Movement detection threshold percentage. | `5` |
| `--diff-record-all` | Keeps all captures, not only movement-positive ones. | Off |

## Runtime behavior summary

1. Optional prerequisite check is executed (`--prerequis`) and is always re-checked before operational run.
2. Screen is captured periodically for diff analysis.
3. Consecutive screenshots are compared with ImageMagick metrics.
4. When threshold is met, a marked JPEG (`MOVEMENT_*.jpg`) is generated.
5. Depending on `--diff-record-all`, non-event captures may be removed.
6. Detection can run with video capture or as standalone mode (`./record_cam.sh --diff ...`).

## Additional system options active in current script

- `--help`
- `--changelog`
- `--discover-devices`
- `--exec`
- `--simulate` (expects a following value; `true` enables simulation in current parser)
- `--delete` / `--remove`
- `--undelete`
- `--target_dir`

## Version context

- Historical v2.x document intent: diff feature introduction and progression.
- Current repository implementation: advanced v3.x branch with refined arithmetic handling for diff calculations and expanded system options.
