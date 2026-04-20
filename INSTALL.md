<!--
Document : INSTALL.md
Auteur : Bruno DELNOZ
Email : bruno.delnoz@protonmail.com
Version : v1.0.0
Date : 2026-04-20 00:00
-->
# Installation Guide

## 1) System packages (Debian/Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y ffmpeg x11-utils imagemagick pulseaudio-utils bc
```

## 2) Script permissions

```bash
chmod +x ./record_cam.sh
chmod +x ./record_cam.v3.0.sh
chmod +x ./record_cam_v3.2.sh
chmod +x ./record_cam.LAST.sh
```

## 3) Validate dependencies with script checks

```bash
./record_cam.sh --prerequis
```

## 4) First smoke test (non-destructive)

```bash
./record_cam.sh --simulate true Demo --segment-duration 10
```

## 5) Audio device discovery (optional)

```bash
./record_cam.sh --discover-devices
```
