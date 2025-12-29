kat#!/bin/bash
# Auteur : Bruno DELNOZ (adapté pour ffmpeg par NoXoZ)
# Email : bruno.delnoz@protonmail.com
# Nom du script : record_cam.sh
# Target usage : Enregistrer l'écran en segments personnalisables avec ffmpeg, capturer le son système (Monitor),
# amplification optionnelle post-traitement, gestion propre de CTRL-C et --delete.
# Version : v1.9 - Date : 2025-09-02
#
# Changelog :
# v1.9 - 2025-09-02 : Détection dynamique de la résolution d'écran, ajout option --mute-output pour muter la sortie audio pendant l'enregistrement (sans affecter la capture), correction de la gestion de la durée totale limitée.
# v1.8 - 2025-08-17 : Remplacement de recordmydesktop par ffmpeg, durée illimitée par défaut, options adaptées pour Whisper
# v1.7 - 2025-08-12 : Amélioration de la gestion de l'arrêt via Ctrl+C
# v1.6 - 2025-08-12 : Ajout --target_dir pour spécifier le répertoire de sortie
# v1.5 - 2025-08-11 : Ajout --segment-duration pour personnaliser la durée des segments
# v1.4 - 2025-08-09 : Corrections multiples - logique de boucle, gestion des processus
# v1.3 - 2025-08-09 : Ajout --volume, segmentation 10min, horodatage automatique
# v1.2 - 2025-08-09 : Capture son système (Monitor)
# v1.1 - 2025-08-09 : Mode durée illimitée (0) + exemples HELP
# v1.0 - 2025-08-09 : Version initiale
set -u
set -o pipefail
SCRIPT_NAME="$(basename "$0")"
LOGFILE="$(dirname "$0")/${SCRIPT_NAME%.sh}.log"
# --- Paramètres par défaut ---
SEGMENT_SECONDS=2100 # 2100s = 35 minutes par défaut
RESOLUTION="$(xdpyinfo | grep dimensions | awk '{print $2}')" # Résolution dynamique
FPS=30 # Images par seconde
AUDIO_DEVICE="alsa_output.pci-0000_00_1f.3.analog-stereo.monitor" # Périphérique audio par défaut
V_CODEC="libx264" # Codec vidéo
V_PRESET="medium" # Préréglage qualité/vitesse
V_CRF=28 # Qualité vidéo (0-51, plus bas = meilleure qualité)
A_CODEC="aac" # Codec audio
A_BITRATE="192k" # Bitrate audio
A_CHANNELS=2 # Canaux audio
A_SAMPLERATE=44100 # Fréquence d'échantillonnage
VOLUME_FILTER="highpass=300,lowpass=3000,compand=0|0:1|1:-90/-60|-60/-40|-40/-30|-20/-20:6" # Amplification audio (vide = désactivé)
ACTIONS=() # Liste des actions effectuées
GENERATED_FILES=() # Fichiers créés pendant l'exécution
STOP_AFTER_CURRENT=0 # Flag pour arrêt propre
TOTAL_DURATION=0 # 0 = illimité (par défaut)
BASE_NAME="" # Base du nom de fichier
DO_DELETE=0 # Suppression des fichiers
DO_EXEC=0 # Mode exécution
TARGET_DIR="./" # Répertoire de sortie
CURRENT_FFMPEG_PID=0 # PID du processus ffmpeg en cours
MICROPHONE_DEVICE="" # Micro désactivé par défaut
RECORD_MIC=0 # 0 = pas de micro
MUTE_OUTPUT=0 # 0 = sortie audio non mutée
ORIGINAL_VOLUME=0 # Volume original pour restauration
# --- Helpers ---
log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" | tee -a "$LOGFILE"
}
discover_audio_devices() {
    echo "=== PÉRIPHÉRIQUES AUDIO DISPONIBLES ==="
    echo ""
    if command -v pactl >/dev/null 2>&1; then
        echo "📢 SORTIES AUDIO (son système à capturer) :"
        pactl list sources short | grep -E "(monitor|output)" | while read -r line; do
            device_name=$(echo "$line" | awk '{print $2}')
            echo " --device \"$device_name\""
        done
        echo ""
        echo "🎤 ENTRÉES AUDIO (microphones) :"
        pactl list sources short | grep -vE "(monitor|output)" | while read -r line; do
            device_name=$(echo "$line" | awk '{print $2}')
            device_desc=$(echo "$line" | cut -d$'\t' -f2- | tr '\t' ' ')
            echo " --mic \"$device_name\" # $device_desc"
        done
        echo ""
        echo "💡 SUGGESTIONS :"
        echo " • Pour capture système seule : $0 Demo"
        echo " • Pour capture + micro : $0 Tutorial --mic"
        echo " • Pour une durée limitée : $0 3600 Demo"
    else
        echo "⚠️ pactl non disponible. Installation : sudo apt install pulseaudio-utils"
    fi
    echo ""
}
usage_and_exit() {
    cat << 'EOF'
USAGE:
  ./record_cam.sh [base_nom] [OPTIONS]
  ./record_cam.sh [duree_total_en_sec] [base_nom] [OPTIONS]
  - base_nom : base du nom des fichiers (ex: nest_agression).
  - duree_total_en_sec : durée totale en secondes (optionnel, 0 = illimité par défaut).
OPTIONS:
  --segment-duration SEC : durée de chaque segment en secondes (par défaut: 2100).
  --volume FLOAT : amplification audio (crée un fichier *_boost.mp4).
  --device DEVICE : périphérique audio système (par défaut: alsa_output.pci-0000_00_1f.3.analog-stereo.monitor).
  --mic [DEVICE] : active le microphone (par défaut: micro par défaut).
  --no-mic : désactive le microphone (par défaut).
  --mute-output : mute la sortie audio pendant l'enregistrement (sans affecter la capture).
  --target_dir DIR : répertoire de sortie (par défaut: ./).
  --help : affiche cette aide.
  --discover-devices : liste les périphériques audio disponibles.
  --delete : supprime les fichiers générés pour la base donnée (backup avant suppression).
EXEMPLES:
  # Enregistrement illimité (par défaut), segments de 35 min, son système :
  ./record_cam.sh nest_agression
  # Avec micro et amplification x2 :
  ./record_cam.sh Tutorial --mic --volume 2.0
  # Durée limitée à 1 heure (3600s) :
  ./record_cam.sh 3600 Demo
  # Segments de 10 min, répertoire personnalisé :
  ./record_cam.sh Test --segment-duration 600 --target_dir ~/Vidéos
  # Mute sortie audio pendant enregistrement :
  ./record_cam.sh Demo --mute-output
  # Lister les périphériques audio :
  ./record_cam.sh --discover-devices
  # Supprimer les fichiers pour une base :
  ./record_cam.sh --delete nest_agression
PRÉREQUIS: ffmpeg, PulseAudio, xdpyinfo (pour résolution dynamique).
EOF
    exit "$1"
}
stop_ffmpeg() {
    if [[ "$CURRENT_FFMPEG_PID" -ne 0 ]]; then
        log "Arrêt de ffmpeg (PID: $CURRENT_FFMPEG_PID)"
        kill -TERM "$CURRENT_FFMPEG_PID" 2>/dev/null
        wait "$CURRENT_FFMPEG_PID" 2>/dev/null
        CURRENT_FFMPEG_PID=0
    fi
}
restore_volume() {
    if [[ "$MUTE_OUTPUT" -eq 1 ]]; then
        log "Restauration du volume original à $ORIGINAL_VOLUME%"
        pactl set-sink-volume @DEFAULT_SINK@ "$ORIGINAL_VOLUME"%
    fi
}
cleanup() {
    stop_ffmpeg
    restore_volume
}
mute_output() {
    if [[ "$MUTE_OUTPUT" -eq 1 ]]; then
        ORIGINAL_VOLUME=$(pactl get-sink-volume @DEFAULT_SINK@ | grep -oP '\d+%' | head -1 | tr -d '%')
        log "Muting sortie audio (volume original: $ORIGINAL_VOLUME%)"
        pactl set-sink-volume @DEFAULT_SINK@ 0%
    fi
}
record_segment() {
    local seg_index=$1
    local duration=$2
    local ts=$(date '+%Y%m%d_%H%M%S')
    local outfile="${TARGET_DIR}/${BASE_NAME}_${ts}_part${seg_index}.mp4"
    log "Démarrage segment #${seg_index} -> ${outfile} (durée: ${duration}s)"
    local ffmpeg_cmd=(
        ffmpeg
        -f x11grab -s "$RESOLUTION" -r "$FPS" -i :0.0
        -f pulse -i "$AUDIO_DEVICE"
        -t "$duration"
        -c:v "$V_CODEC" -preset "$V_PRESET" -crf "$V_CRF"
        -c:a "$A_CODEC" -b:a "$A_BITRATE" -ac "$A_CHANNELS" -ar "$A_SAMPLERATE"
        -movflags +faststart
        -y "$outfile"
    )
    if [[ "$RECORD_MIC" -eq 1 ]]; then
        ffmpeg_cmd=(
            ffmpeg
            -f x11grab -s "$RESOLUTION" -r "$FPS" -i :0.0
            -f pulse -i "$AUDIO_DEVICE"
            -f pulse -i "$MICROPHONE_DEVICE"
            -filter_complex "[1:a][2:a]amix=inputs=2[aout]"
            -map 0:v -map "[aout]"
            -t "$duration"
            -c:v "$V_CODEC" -preset "$V_PRESET" -crf "$V_CRF"
            -c:a "$A_CODEC" -b:a "$A_BITRATE" -ac "$A_CHANNELS" -ar "$A_SAMPLERATE"
            -movflags +faststart
            -y "$outfile"
        )
    fi
    "${ffmpeg_cmd[@]}" >/dev/null 2>&1 &
    CURRENT_FFMPEG_PID=$!
    ACTIONS+=("Record segment ${seg_index} -> ${outfile} (${duration}s)")
}
boost_audio() {
    local infile=$1
    local boost_dir="${TARGET_DIR}/BOOST"
    mkdir -p "$boost_dir"
    local boost_file="${boost_dir}/$(basename "$infile" .mp4)_boost.mp4"
    log "Amplification audio: $infile -> $boost_file (volume: ${VOLUME_FILTER})"
    if ffmpeg -i "$infile" -filter:a "volume=${VOLUME_FILTER}" -c:v copy "$boost_file" >/dev/null 2>&1; then
        GENERATED_FILES+=("$boost_file")
        log "Amplification terminée: $boost_file"
        # Supprimer le fichier original
        if rm "$infile"; then
            log "Fichier original supprimé: $infile"
            # Retirer le fichier original de GENERATED_FILES
            local new_files=()
            for file in "${GENERATED_FILES[@]}"; do
                if [[ "$file" != "$infile" ]]; then
                    new_files+=("$file")
                fi
            done
            GENERATED_FILES=("${new_files[@]}")
            log "Fichier original retiré de la liste des fichiers générés: $infile"
        else
            log "ERREUR: Échec de la suppression du fichier original: $infile"
        fi
    else
        log "ERREUR: Échec de l'amplification audio pour $infile"
    fi
}
# --- Parse args ---
if [[ $# -eq 0 ]]; then
    usage_and_exit 0
fi
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|--discover-devices)
            if [[ "$1" == "--discover-devices" ]]; then
                discover_audio_devices
                exit 0
            else
                usage_and_exit 0
            fi
            ;;
        --segment-duration)
            shift
            SEGMENT_SECONDS="$1"
            shift
            ;;
        --volume)
            shift
            VOLUME_FILTER="$1"
            shift
            ;;
        --device)
            shift
            AUDIO_DEVICE="$1"
            shift
            ;;
        --mic)
            RECORD_MIC=1
            if [[ $# -gt 0 && "${2:0:1}" != "-" ]]; then
                shift
                MICROPHONE_DEVICE="$1"
            else
                MICROPHONE_DEVICE="default"
            fi
            shift
            ;;
        --no-mic)
            RECORD_MIC=0
            MICROPHONE_DEVICE=""
            shift
            ;;
        --mute-output)
            MUTE_OUTPUT=1
            shift
            ;;
        --target_dir)
            shift
            TARGET_DIR="$1"
            shift
            ;;
        --delete)
            DO_DELETE=1
            shift
            ;;
        --exec)
            DO_EXEC=1
            shift
            ;;
        -*)
            echo "[ERREUR] Option inconnue: $1"
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done
set -- "${POSITIONAL[@]}"
# --- Gestion de --delete ---
if [[ "$DO_DELETE" -eq 1 ]]; then
    if [[ $# -lt 1 ]]; then
        echo "[ERREUR] --delete nécessite la base de nom."
        exit 1
    fi
    TARGET_BASE="$1"
    BACKUP_DIR="$(dirname "$0")/backup_${TARGET_BASE}_$(date '+%Y%m%d_%H%M%S')"
    mkdir -p "$BACKUP_DIR"
    found_files=0
    for f in "${TARGET_DIR}/${TARGET_BASE}"*.mp4 "${TARGET_DIR}/BOOST/${TARGET_BASE}"*.mp4; do
        if [[ -e "$f" ]]; then
            mv "$f" "$BACKUP_DIR/"
            echo "Déplacé: $f -> $BACKUP_DIR/"
            found_files=1
        fi
    done
    if [[ $found_files -eq 0 ]]; then
        echo "Aucun fichier trouvé pour '$TARGET_BASE'."
        rmdir "$BACKUP_DIR" 2>/dev/null
    else
        echo "Backup dans $BACKUP_DIR"
    fi
    exit 0
fi
# --- Vérification des arguments ---
if [[ $# -lt 1 ]]; then
    echo "[ERREUR] Usage: $0 [base_nom] [OPTIONS] ou $0 [duree] [base_nom] [OPTIONS]"
    exit 1
fi
# Gestion de la durée (optionnelle)
if [[ "${1}" =~ ^[0-9]+$ ]]; then
    TOTAL_DURATION="$1"
    BASE_NAME="$2"
    shift 2
else
    TOTAL_DURATION=0 # Illimité par défaut
    BASE_NAME="$1"
    shift
fi
# --- Vérification des prérequis ---
if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "[ERREUR] ffmpeg n'est pas installé."
    exit 1
fi
if ! command -v xdpyinfo >/dev/null 2>&1; then
    echo "[ERREUR] xdpyinfo n'est pas installé (paquet x11-utils)."
    exit 1
fi
if [[ "$MUTE_OUTPUT" -eq 1 ]] && ! command -v pactl >/dev/null 2>&1; then
    echo "[ERREUR] pactl n'est pas installé pour --mute-output."
    exit 1
fi
# --- Configuration des traps ---
trap 'log "SIGINT reçu: arrêt en cours..."; STOP_AFTER_CURRENT=1; cleanup; exit 130' SIGINT
trap 'cleanup' EXIT
# --- Boucle principale ---
log "Démarrage: base=$BASE_NAME, durée_totale=${TOTAL_DURATION} (0=illimitée), segment_duration=${SEGMENT_SECONDS}s, device=$AUDIO_DEVICE, mic=$RECORD_MIC, mic_device=$MICROPHONE_DEVICE, volume=$VOLUME_FILTER, mute_output=$MUTE_OUTPUT, target_dir=$TARGET_DIR"
mute_output
seg_index=0
remaining_duration=$TOTAL_DURATION
while true; do
    if [[ "$STOP_AFTER_CURRENT" -eq 1 ]]; then
        log "Arrêt demandé, sortie de la boucle."
        break
    fi
    if [[ "$TOTAL_DURATION" -gt 0 ]]; then
        if [[ "$remaining_duration" -le 0 ]]; then
            log "Durée totale atteinte, arrêt."
            break
        fi
        current_duration=$(( remaining_duration < SEGMENT_SECONDS ? remaining_duration : SEGMENT_SECONDS ))
        remaining_duration=$(( remaining_duration - current_duration ))
    else
        current_duration="$SEGMENT_SECONDS"
    fi
    record_segment "$seg_index" "$current_duration"
    sleep "$current_duration"
    stop_ffmpeg
    # Vérifier le fichier généré
    latest_file=$(ls -t "${TARGET_DIR}/${BASE_NAME}"_*_part${seg_index}.mp4 2>/dev/null | head -n1)
    if [[ -n "$latest_file" ]]; then
        GENERATED_FILES+=("$latest_file")
        log "Segment enregistré: $latest_file (taille: $(stat -c%s "$latest_file" 2>/dev/null || echo "N/A") octets)"
        if [[ -n "$VOLUME_FILTER" ]]; then
            boost_audio "$latest_file"
        fi
    else
        log "ERREUR: Aucun fichier généré pour le segment $seg_index"
    fi
    seg_index=$((seg_index + 1))
done
# --- Résumé ---
log "=== Résumé des actions ==="
for action in "${ACTIONS[@]}"; do
    log "- $action"
done
log "=== Fichiers générés ==="
for f in "${GENERATED_FILES[@]}"; do
    log "- $f"
done
log "Fin du script."
exit 0
