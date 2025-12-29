#!/bin/bash

# Auteur : Bruno DELNOZ
# Email : bruno.delnoz@protonmail.com
# Nom du script : record_cam.sh
# Target usage : Enregistrer l'écran en segments personnalisables avec ffmpeg, capturer le son système (Monitor),
# amplification optionnelle post-traitement, gestion propre de CTRL-C, --delete, et détection de mouvement avec diff
# Version : v3.0.1 - Date : 2025-10-22
#
# Changelog :
# v3.0.1 - 2025-10-22 : Correction erreur arithmétique notation scientifique (lignes 416-420)
# v3.0 - 2025-09-15 : Ajout complet de la détection de mouvement avec ImageMagick (--diff), arguments --diff-target-dir, --diff-duration, --diff-interval, --diff-threshold, --diff-record-all, intégration prérequis ImageMagick, fonctionnement en parallèle avec capture vidéo
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

# --- Variables du script ---
SCRIPT_NAME="$(basename "$0")"
LOGFILE="$(dirname "$0")/${SCRIPT_NAME%.sh}.v3.0.log"

# --- Paramètres par défaut (existants) ---
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
VOLUME_FILTER="" # Amplification audio (vide = désactivé)
DEFAULT_AUDIO_FILTER="highpass=300,lowpass=3000,compand=0|0:1|1:-90/-60|-60/-40|-40/-30|-20/-20:6" # Filtre par défaut
ACTIONS=() # Liste des actions effectuées
GENERATED_FILES=() # Fichiers créés pendant l'exécution
STOP_AFTER_CURRENT=0 # Flag pour arrêt propre
TOTAL_DURATION=0 # 0 = illimité (par défaut)
BASE_NAME="" # Base du nom de fichier
DO_DELETE=0 # Suppression des fichiers
DO_UNDELETE=0 # Restauration des fichiers
DO_EXEC=1 # Mode exécution (par défaut true)
DO_SIMULATE=0 # Mode simulation (par défaut false)
DO_PREREQUIS=0 # Vérification des prérequis
DO_INSTALL=0 # Installation des prérequis
DO_CHANGELOG=0 # Afficher le changelog
TARGET_DIR="./" # Répertoire de sortie
CURRENT_FFMPEG_PID=0 # PID du processus ffmpeg en cours
MICROPHONE_DEVICE="" # Micro désactivé par défaut
RECORD_MIC=0 # 0 = pas de micro
MUTE_OUTPUT=0 # 0 = sortie audio non mutée
ORIGINAL_VOLUME=0 # Volume original pour restauration

# --- Nouveaux paramètres pour la détection de mouvement ---
DO_DIFF=0 # Active la détection de mouvement
DIFF_TARGET_DIR="./diff_output" # Répertoire pour les images de diff
DIFF_DURATION=0 # Durée de détection (0 = illimitée)
DIFF_INTERVAL=3 # Intervalle entre captures (secondes)
DIFF_THRESHOLD=5 # Seuil de différence en pourcentage
DIFF_RECORD_ALL=0 # Enregistrer toutes les images (0 = seulement avec mouvement)
DIFF_PID=0 # PID du processus de détection
DIFF_STOP_FLAG=0 # Flag d'arrêt pour la détection

# --- Helpers existants ---
log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" | tee -a "$LOGFILE"
}

# --- Fonction de vérification des prérequis ---
check_prerequisites() {
    log "=== VÉRIFICATION DES PRÉREQUIS ==="
    local missing_deps=()

    # Vérification ffmpeg
    if ! command -v ffmpeg >/dev/null 2>&1; then
        missing_deps+=("ffmpeg")
        log "❌ ffmpeg manquant"
    else
        log "✅ ffmpeg trouvé"
    fi

    # Vérification xdpyinfo
    if ! command -v xdpyinfo >/dev/null 2>&1; then
        missing_deps+=("x11-utils")
        log "❌ xdpyinfo manquant (paquet x11-utils)"
    else
        log "✅ xdpyinfo trouvé"
    fi

    # Vérification ImageMagick (pour --diff)
    if [[ "$DO_DIFF" -eq 1 ]]; then
        if ! command -v compare >/dev/null 2>&1; then
            missing_deps+=("imagemagick")
            log "❌ ImageMagick compare manquant (requis pour --diff)"
        else
            log "✅ ImageMagick compare trouvé"
        fi
    fi

    # Vérification pactl (pour --mute-output)
    if [[ "$MUTE_OUTPUT" -eq 1 ]]; then
        if ! command -v pactl >/dev/null 2>&1; then
            missing_deps+=("pulseaudio-utils")
            log "❌ pactl manquant (requis pour --mute-output)"
        else
            log "✅ pactl trouvé"
        fi
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "⚠️ Prérequis manquants : ${missing_deps[*]}"
        if [[ "$DO_INSTALL" -eq 1 ]]; then
            log "Installation automatique des prérequis..."
            if [[ "$DO_SIMULATE" -eq 0 ]]; then
                sudo apt-get update && sudo apt-get install -y "${missing_deps[@]}"
                ACTIONS+=("Installation prérequis : ${missing_deps[*]}")
            else
                log "[SIMULATION] sudo apt-get install -y ${missing_deps[*]}"
            fi
        else
            echo "Pour installer : sudo apt-get install -y ${missing_deps[*]}"
            if [[ "$DO_SIMULATE" -eq 0 ]]; then
                exit 1
            fi
        fi
    else
        log "✅ Tous les prérequis sont satisfaits"
    fi
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

# --- Fonction d'aide mise à jour ---
usage_and_exit() {
    cat << 'EOF'
USAGE:
  ./record_cam.sh [base_nom] [OPTIONS]
  ./record_cam.sh [duree_total_en_sec] [base_nom] [OPTIONS]
  - base_nom : base du nom des fichiers (ex: nest_agression).
  - duree_total_en_sec : durée totale en secondes (optionnel, 0 = illimité par défaut).

OPTIONS DE CAPTURE VIDÉO/AUDIO:
  --segment-duration SEC : durée de chaque segment en secondes (par défaut: 2100).
  --volume FLOAT : amplification audio supplémentaire (ex: 2.0 = x2, s'ajoute aux filtres par défaut).
                   Note: Les filtres audio par défaut (highpass, lowpass, compand) sont TOUJOURS appliqués.
  --device DEVICE : périphérique audio système (par défaut: alsa_output.pci-0000_00_1f.3.analog-stereo.monitor).
  --mic [DEVICE] : active le microphone (par défaut: micro par défaut).
  --no-mic : désactive le microphone (par défaut).
  --mute-output : mute la sortie audio pendant l'enregistrement (sans affecter la capture).
  --target_dir DIR : répertoire de sortie (par défaut: ./).

OPTIONS DE DÉTECTION DE MOUVEMENT:
  --diff : active la détection de mouvement sur la capture d'écran.
  --diff-target-dir DIR : répertoire pour les images de diff (par défaut: ./diff_output).
  --diff-duration SEC : durée d'activité de détection en secondes (par défaut: 0 = illimitée).
  --diff-interval SEC : intervalle entre captures d'images (par défaut: 3 secondes).
  --diff-threshold PCT : seuil de différence en % pour détecter mouvement (par défaut: 5).
  --diff-record-all : enregistre toutes les images générées (par défaut: seulement avec mouvement).

OPTIONS SYSTÈME:
  --help : affiche cette aide.
  --exec : mode exécution (par défaut: true).
          --simulate=true : active le mode simulation pour actions sensibles (par défaut: false).
  --prerequis : vérifie les prérequis avant exécution.
  --install : installe automatiquement les prérequis manquants.
  --changelog : affiche le changelog complet.
  --discover-devices : liste les périphériques audio disponibles.
  --delete BASE : supprime les fichiers générés pour la base donnée (backup avant suppression).
  --undelete BASE : restaure les fichiers depuis le backup.
  --remove BASE : alias pour --delete.

EXEMPLES CAPTURE VIDÉO:
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

EXEMPLES DÉTECTION MOUVEMENT:
  # Détection seule pendant 1h, capture toutes les 3s, seuil 5% :
  ./record_cam.sh --diff --diff-duration 3600 --diff-interval 3 --diff-target-dir ./movements

  # Capture vidéo + détection parallèle :
  ./record_cam.sh 7200 Demo --diff --diff-duration 3600 --diff-interval 5 --diff-threshold 10

  # Enregistrer toutes les images de diff :
  ./record_cam.sh --diff --diff-record-all --diff-target-dir ./all_captures

EXEMPLES SYSTÈME:
  # Vérifier prérequis :
  ./record_cam.sh --prerequis

  # Installer prérequis automatiquement :
  ./record_cam.sh --prerequis --install

  # Lister périphériques audio :
  ./record_cam.sh --discover-devices

  # Supprimer fichiers pour une base :
  ./record_cam.sh --delete nest_agression

  # Restaurer fichiers :
  ./record_cam.sh --undelete nest_agression

PRÉREQUIS: ffmpeg, xdpyinfo (x11-utils), ImageMagick (pour --diff), PulseAudio (pour --mute-output).
EOF
    exit "$1"
}

# --- Fonction de gestion du changelog ---
show_changelog() {
    cat << 'EOF'
=== CHANGELOG COMPLET ===

v3.0.1 - 2025-10-22:
• Correction erreur arithmétique avec notation scientifique (3.136e+06)
• Amélioration conversion pixel count vers entier avec printf
• Gestion robuste des comparaisons arithmétiques

v3.0 - 2025-09-15:
• Ajout complet détection de mouvement avec ImageMagick
• Nouveaux arguments : --diff, --diff-target-dir, --diff-duration, --diff-interval, --diff-threshold, --diff-record-all
• Intégration prérequis ImageMagick dans --prerequis
• Fonctionnement parallèle capture vidéo + détection mouvement
• Marquage fluorescent des zones de mouvement détectées
• Arguments système obligatoires : --prerequis, --install, --simulate, --changelog

v1.9 - 2025-09-02:
• Détection dynamique résolution écran
• Option --mute-output pour muter sortie audio
• Correction gestion durée totale limitée

v1.8 - 2025-08-17:
• Remplacement recordmydesktop par ffmpeg
• Durée illimitée par défaut
• Options adaptées pour Whisper

v1.7 - 2025-08-12:
• Amélioration gestion arrêt via Ctrl+C

v1.6 - 2025-08-12:
• Ajout --target_dir pour répertoire sortie

v1.5 - 2025-08-11:
• Ajout --segment-duration personnalisable

v1.4 - 2025-08-09:
• Corrections logique boucle et gestion processus

v1.3 - 2025-08-09:
• Ajout --volume, segmentation 10min, horodatage

v1.2 - 2025-08-09:
• Capture son système (Monitor)

v1.1 - 2025-08-09:
• Mode durée illimitée (0) + exemples HELP

v1.0 - 2025-08-09:
• Version initiale
EOF
    exit 0
}

# --- Fonctions de nettoyage ---
stop_ffmpeg() {
    if [[ "$CURRENT_FFMPEG_PID" -ne 0 ]]; then
        log "Arrêt de ffmpeg (PID: $CURRENT_FFMPEG_PID)"
        if [[ "$DO_SIMULATE" -eq 0 ]]; then
            kill -TERM "$CURRENT_FFMPEG_PID" 2>/dev/null
            wait "$CURRENT_FFMPEG_PID" 2>/dev/null
        else
            log "[SIMULATION] kill -TERM $CURRENT_FFMPEG_PID"
        fi
        CURRENT_FFMPEG_PID=0
    fi
}

stop_diff_detection() {
    if [[ "$DIFF_PID" -ne 0 ]]; then
        log "Arrêt de la détection de mouvement (PID: $DIFF_PID)"
        DIFF_STOP_FLAG=1
        if [[ "$DO_SIMULATE" -eq 0 ]]; then
            kill -TERM "$DIFF_PID" 2>/dev/null
            wait "$DIFF_PID" 2>/dev/null
        else
            log "[SIMULATION] kill -TERM $DIFF_PID"
        fi
        DIFF_PID=0
    fi
}

restore_volume() {
    if [[ "$MUTE_OUTPUT" -eq 1 ]]; then
        log "Restauration du volume original à $ORIGINAL_VOLUME%"
        if [[ "$DO_SIMULATE" -eq 0 ]]; then
            pactl set-sink-volume @DEFAULT_SINK@ "$ORIGINAL_VOLUME"%
        else
            log "[SIMULATION] pactl set-sink-volume @DEFAULT_SINK@ $ORIGINAL_VOLUME%"
        fi
    fi
}

cleanup() {
    stop_ffmpeg
    stop_diff_detection
    restore_volume
    # Réactiver le beep système
    xset b on 2>/dev/null
}

mute_output() {
    if [[ "$MUTE_OUTPUT" -eq 1 ]]; then
        if [[ "$DO_SIMULATE" -eq 0 ]]; then
            ORIGINAL_VOLUME=$(pactl get-sink-volume @DEFAULT_SINK@ | grep -oP '\d+%' | head -1 | tr -d '%')
            log "Muting sortie audio (volume original: $ORIGINAL_VOLUME%)"
            pactl set-sink-volume @DEFAULT_SINK@ 0%
        else
            ORIGINAL_VOLUME=50
            log "[SIMULATION] Muting sortie audio (volume original: $ORIGINAL_VOLUME%)"
        fi
    fi
}

# --- Fonction de détection de mouvement CORRIGÉE ---
diff_detection_loop() {
    log "=== DÉMARRAGE DÉTECTION DE MOUVEMENT ==="
    log "Paramètres: interval=${DIFF_INTERVAL}s, threshold=${DIFF_THRESHOLD}%, target_dir=${DIFF_TARGET_DIR}"

    if [[ "$DO_SIMULATE" -eq 0 ]]; then
        mkdir -p "$DIFF_TARGET_DIR"
    else
        log "[SIMULATION] mkdir -p $DIFF_TARGET_DIR"
    fi

    local start_time=$(date +%s)
    local img_counter=0
    local prev_img=""
    local current_img=""
    local movements_detected=0

    while [[ "$DIFF_STOP_FLAG" -eq 0 ]]; do
        # Vérification de la durée limite
        if [[ "$DIFF_DURATION" -gt 0 ]]; then
            local elapsed=$(($(date +%s) - start_time))
            if [[ "$elapsed" -ge "$DIFF_DURATION" ]]; then
                log "Durée de détection atteinte ($DIFF_DURATION s), arrêt."
                break
            fi
        fi

        # Capture d'écran
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        current_img="${DIFF_TARGET_DIR}/capture_${timestamp}_${img_counter}.png"

        if [[ "$DO_SIMULATE" -eq 0 ]]; then
            # Désactiver temporairement le beep système
            xset b off 2>/dev/null
            import -window root -silent "$current_img" 2>/dev/null
            log "Capture écran : $current_img"
        else
            log "[SIMULATION] import -window root $current_img"
            # Simuler la création du fichier
            touch "$current_img" 2>/dev/null || true
        fi

        # Comparaison avec l'image précédente
        if [[ -n "$prev_img" && -f "$prev_img" ]]; then
            local diff_result=""
            local movement_detected=0

            if [[ "$DO_SIMULATE" -eq 0 ]]; then
                # Calcul de la différence avec ImageMagick
                diff_result=$(compare -metric AE "$prev_img" "$current_img" null: 2>&1 | head -1 | grep -o '[0-9.eE+-]*' | head -1)
                if [[ -z "$diff_result" ]]; then
                    diff_result=0
                fi

                # CORRECTION: Conversion notation scientifique vers entier
                # Utilisation de printf pour gérer la notation scientifique
                diff_result=$(printf "%.0f" "$diff_result" 2>/dev/null || echo "0")

                local total_pixels=$(identify -format "%[fx:w*h]" "$current_img" 2>/dev/null || echo "1920000")
                # Conversion aussi pour total_pixels si besoin
                total_pixels=$(printf "%.0f" "$total_pixels" 2>/dev/null || echo "1920000")

                local diff_percentage=""

                # Calcul du pourcentage - méthode sûre avec protection division par zéro
                if [[ "$total_pixels" -gt 0 ]]; then
                    if command -v bc >/dev/null 2>&1; then
                        diff_percentage=$(echo "scale=2; ($diff_result * 100) / $total_pixels" | bc 2>/dev/null || echo "0")
                    else
                        # Calcul alternatif sans bc
                        diff_percentage=$(( (diff_result * 100) / total_pixels ))
                    fi
                else
                    diff_percentage=0
                fi

                log "Différence détectée: $diff_result pixels ($diff_percentage%)"

                # Vérification du seuil - CORRECTION: Comparaison sûre
                local threshold_check=0
                if command -v bc >/dev/null 2>&1; then
                    # Avec bc, comparaison flottante
                    threshold_check=$(echo "$diff_percentage >= $DIFF_THRESHOLD" | bc -l 2>/dev/null || echo "0")
                else
                    # Sans bc, conversion en entier et comparaison
                    local diff_int=$(printf "%.0f" "$diff_percentage" 2>/dev/null || echo "0")
                    if [[ "$diff_int" -ge "$DIFF_THRESHOLD" ]]; then
                        threshold_check=1
                    fi
                fi

                if [[ "$threshold_check" -eq 1 ]]; then
                    movement_detected=1
                    movements_detected=$((movements_detected + 1))
                    log "🔴 MOUVEMENT DÉTECTÉ! Seuil: $DIFF_THRESHOLD%, Détecté: $diff_percentage%"

                    # Création d'image avec carré fluorescent sur les zones de différence
                    local marked_img="${DIFF_TARGET_DIR}/MOVEMENT_${timestamp}_${movements_detected}.jpg"

                    # Créer une image de différence pour identifier les zones
                    local diff_img="${DIFF_TARGET_DIR}/temp_diff_${timestamp}.png"
                    compare "$prev_img" "$current_img" "$diff_img" 2>/dev/null

                    # Trouver les coordonnées des zones de différence
                    local coords=$(convert "$diff_img" -trim -format "%[fx:page.x],%[fx:page.y],%[fx:page.width],%[fx:page.height]" info: 2>/dev/null)

                    if [[ -n "$coords" ]]; then
                        # Extraire x,y,width,height
                        IFS=',' read -r x y w h <<< "$coords"
                        log "Zone de mouvement détectée: x=$x, y=$y, width=$w, height=$h"

                        # Créer l'image marquée avec rectangle sur la zone réelle
                        local x2=$((x + w))
                        local y2=$((y + h))
                        convert "$current_img" -fill 'rgba(255,255,0,0.3)' -stroke 'rgb(255,255,0)' -strokewidth 4 -draw "rectangle $x,$y $x2,$y2" "$marked_img"

                        # Ajouter du texte avec les coordonnées
                        convert "$marked_img" -fill 'rgb(255,255,0)' -pointsize 16 -draw "text $((x+5)),$((y+20)) 'MOVE: ${w}x${h}'" "$marked_img"
                    else
                        # Fallback: carré au centre si détection des coordonnées échoue
                        log "Impossible de déterminer la zone exacte, marquage central"
                        convert "$current_img" -fill 'rgba(255,255,0,0.5)' -stroke 'rgb(255,255,0)' -strokewidth 3 -draw "rectangle 50,50 200,200" "$marked_img"
                    fi

                    # Nettoyer l'image temporaire
                    rm -f "$diff_img" 2>/dev/null

                    GENERATED_FILES+=("$marked_img")
                    ACTIONS+=("Mouvement détecté et marqué: $marked_img (zone: $coords)")
                    log "Image marquée créée: $marked_img"
                fi
            else
                # Simulation
                local random_diff=$((RANDOM % 20))
                log "[SIMULATION] Différence simulée: $random_diff%"
                if [[ "$random_diff" -ge "$DIFF_THRESHOLD" ]]; then
                    movement_detected=1
                    movements_detected=$((movements_detected + 1))
                    log "[SIMULATION] 🔴 MOUVEMENT DÉTECTÉ! Seuil: $DIFF_THRESHOLD%, Détecté: $random_diff%"
                    local marked_img="${DIFF_TARGET_DIR}/MOVEMENT_${timestamp}_${movements_detected}.jpg"
                    log "[SIMULATION] Image marquée: $marked_img"
                    GENERATED_FILES+=("$marked_img")
                fi
            fi

            # Gestion des fichiers selon --diff-record-all
            if [[ "$DIFF_RECORD_ALL" -eq 0 && "$movement_detected" -eq 0 ]]; then
                # Supprimer l'image actuelle si pas de mouvement et --diff-record-all inactif
                if [[ "$DO_SIMULATE" -eq 0 ]]; then
                    rm -f "$current_img" 2>/dev/null
                    log "Image supprimée (pas de mouvement): $current_img"
                else
                    log "[SIMULATION] rm -f $current_img"
                fi
            else
                if [[ "$DIFF_RECORD_ALL" -eq 1 || "$movement_detected" -eq 1 ]]; then
                    GENERATED_FILES+=("$current_img")
                fi
            fi

            # Ne pas supprimer l'image précédente, elle sert de référence continue
        else
            # Première image, toujours conserver
            GENERATED_FILES+=("$current_img")
            log "Première image de référence: $current_img"
        fi

        # L'image actuelle devient la référence pour la prochaine comparaison SEULEMENT si on l'a gardée
        if [[ "$DIFF_RECORD_ALL" -eq 1 ]] || [[ -z "$prev_img" ]] || [[ "$movement_detected" -eq 1 ]]; then
            prev_img="$current_img"
        fi
        img_counter=$((img_counter + 1))

        # Attente avant prochaine capture
        sleep "$DIFF_INTERVAL"
    done

    log "=== FIN DÉTECTION DE MOUVEMENT ==="
    log "Total mouvements détectés: $movements_detected"
    log "Images capturées: $img_counter"
    ACTIONS+=("Détection mouvement terminée: $movements_detected mouvements sur $img_counter captures")
}

# --- Fonctions de capture vidéo (inchangées) ---
record_segment() {
    local seg_index=$1
    local duration=$2
    local ts=$(date '+%Y%m%d_%H%M%S')
    local outfile="${TARGET_DIR}/${BASE_NAME}_${ts}_part${seg_index}.mp4"

    log "Démarrage segment #${seg_index} -> ${outfile} (durée: ${duration}s)"

    if [[ "$DO_SIMULATE" -eq 0 ]]; then
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
    else
        log "[SIMULATION] ffmpeg capture vers $outfile"
        CURRENT_FFMPEG_PID=12345
    fi

    ACTIONS+=("Record segment ${seg_index} -> ${outfile} (${duration}s)")
}

boost_audio() {
    local infile=$1
    local boost_dir="${TARGET_DIR}/BOOST"

    if [[ "$DO_SIMULATE" -eq 0 ]]; then
        mkdir -p "$boost_dir"
    else
        log "[SIMULATION] mkdir -p $boost_dir"
    fi

    local boost_file="${boost_dir}/$(basename "$infile" .mp4)_boost.mp4"

    # Construction du filtre audio
    local audio_filter=""
    if [[ -n "$VOLUME_FILTER" ]]; then
        # Si un volume est spécifié, combiner avec le filtre par défaut
        audio_filter="${DEFAULT_AUDIO_FILTER},volume=${VOLUME_FILTER}"
    else
        # Sinon utiliser juste le filtre par défaut
        audio_filter="${DEFAULT_AUDIO_FILTER}"
    fi

    log "Amplification audio: $infile -> $boost_file (filtre: ${audio_filter})"

    if [[ "$DO_SIMULATE" -eq 0 ]]; then
        if ffmpeg -i "$infile" -filter:a "${audio_filter}" -c:v copy "$boost_file" >/dev/null 2>&1; then
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
    else
        log "[SIMULATION] ffmpeg amplification $infile -> $boost_file"
        GENERATED_FILES+=("$boost_file")
    fi
}

# --- Fonctions de gestion des fichiers ---
do_delete_files() {
    if [[ $# -lt 1 ]]; then
        echo "[ERREUR] --delete nécessite la base de nom."
        exit 1
    fi

    local target_base="$1"
    local backup_dir="$(dirname "$0")/backup_${target_base}_$(date '+%Y%m%d_%H%M%S')"

    if [[ "$DO_SIMULATE" -eq 0 ]]; then
        mkdir -p "$backup_dir"
    else
        log "[SIMULATION] mkdir -p $backup_dir"
    fi

    local found_files=0

    # Recherche dans répertoire principal
    for f in "${TARGET_DIR}/${target_base}"*.mp4 "${TARGET_DIR}/BOOST/${target_base}"*.mp4; do
        if [[ -e "$f" ]]; then
            if [[ "$DO_SIMULATE" -eq 0 ]]; then
                mv "$f" "$backup_dir/"
                echo "Déplacé: $f -> $backup_dir/"
            else
                log "[SIMULATION] mv $f $backup_dir/"
            fi
            found_files=1
        fi
    done

    # Recherche dans répertoire diff
    for f in "${DIFF_TARGET_DIR}/${target_base}"* "${DIFF_TARGET_DIR}/MOVEMENT_"*; do
        if [[ -e "$f" ]]; then
            if [[ "$DO_SIMULATE" -eq 0 ]]; then
                mv "$f" "$backup_dir/"
                echo "Déplacé: $f -> $backup_dir/"
            else
                log "[SIMULATION] mv $f $backup_dir/"
            fi
            found_files=1
        fi
    done

    if [[ $found_files -eq 0 ]]; then
        echo "Aucun fichier trouvé pour '$target_base'."
        if [[ "$DO_SIMULATE" -eq 0 ]]; then
            rmdir "$backup_dir" 2>/dev/null
        else
            log "[SIMULATION] rmdir $backup_dir"
        fi
    else
        echo "Backup dans $backup_dir"
        ACTIONS+=("Suppression avec backup : $target_base -> $backup_dir")
    fi

    exit 0
}

do_undelete_files() {
    if [[ $# -lt 1 ]]; then
        echo "[ERREUR] --undelete nécessite la base de nom."
        exit 1
    fi

    local target_base="$1"
    local backup_pattern="$(dirname "$0")/backup_${target_base}_*"

    # Recherche du backup le plus récent
    local latest_backup=""
    for backup_dir in $backup_pattern; do
        if [[ -d "$backup_dir" ]]; then
            latest_backup="$backup_dir"
        fi
    done

    if [[ -z "$latest_backup" ]]; then
        echo "Aucun backup trouvé pour '$target_base'."
        exit 1
    fi

    echo "Restauration depuis: $latest_backup"
    local restored_files=0

    for f in "$latest_backup"/*; do
        if [[ -f "$f" ]]; then
            local filename=$(basename "$f")
            local target_path=""

            # Déterminer le répertoire de destination
            if [[ "$filename" == *"_boost.mp4" ]]; then
                target_path="${TARGET_DIR}/BOOST/$filename"
                if [[ "$DO_SIMULATE" -eq 0 ]]; then
                    mkdir -p "${TARGET_DIR}/BOOST"
                    mv "$f" "$target_path"
                else
                    log "[SIMULATION] mkdir -p ${TARGET_DIR}/BOOST && mv $f $target_path"
                fi
            elif [[ "$filename" == "MOVEMENT_"* || "$filename" == "capture_"* ]]; then
                target_path="${DIFF_TARGET_DIR}/$filename"
                if [[ "$DO_SIMULATE" -eq 0 ]]; then
                    mkdir -p "$DIFF_TARGET_DIR"
                    mv "$f" "$target_path"
                else
                    log "[SIMULATION] mkdir -p $DIFF_TARGET_DIR && mv $f $target_path"
                fi
            else
                target_path="${TARGET_DIR}/$filename"
                if [[ "$DO_SIMULATE" -eq 0 ]]; then
                    mv "$f" "$target_path"
                else
                    log "[SIMULATION] mv $f $target_path"
                fi
            fi

            echo "Restauré: $filename -> $target_path"
            restored_files=1
        fi
    done

    if [[ $restored_files -eq 1 ]]; then
        echo "Suppression du répertoire backup: $latest_backup"
        if [[ "$DO_SIMULATE" -eq 0 ]]; then
            rmdir "$latest_backup" 2>/dev/null
        else
            log "[SIMULATION] rmdir $latest_backup"
        fi
        ACTIONS+=("Restauration depuis backup : $latest_backup")
    fi

    exit 0
}

# --- Parse arguments ---
if [[ $# -eq 0 ]]; then
    usage_and_exit 0
fi

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            usage_and_exit 0
            ;;
        --changelog)
            show_changelog
            ;;
        --discover-devices)
            discover_audio_devices
            exit 0
            ;;
        --prerequis)
            DO_PREREQUIS=1
            shift
            ;;
        --install)
            DO_INSTALL=1
            shift
            ;;
        --simulate)
            shift
            if [[ "$1" == "true" ]]; then
                DO_SIMULATE=1
            else
                DO_SIMULATE=0
            fi
            shift
            ;;
        --exec)
            DO_EXEC=1
            shift
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
            if [[ $# -gt 1 && "${2:0:1}" != "-" ]]; then
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
        --diff)
            DO_DIFF=1
            shift
            ;;
        --diff-target-dir)
            shift
            DIFF_TARGET_DIR="$1"
            shift
            ;;
        --diff-duration)
            shift
            DIFF_DURATION="$1"
            shift
            ;;
        --diff-interval)
            shift
            DIFF_INTERVAL="$1"
            shift
            ;;
        --diff-threshold)
            shift
            DIFF_THRESHOLD="$1"
            shift
            ;;
        --diff-record-all)
            DIFF_RECORD_ALL=1
            shift
            ;;
        --delete|--remove)
            DO_DELETE=1
            shift
            ;;
        --undelete)
            DO_UNDELETE=1
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

# --- Traitement des actions spéciales ---
if [[ "$DO_DELETE" -eq 1 ]]; then
    do_delete_files "$@"
fi

if [[ "$DO_UNDELETE" -eq 1 ]]; then
    do_undelete_files "$@"
fi

if [[ "$DO_PREREQUIS" -eq 1 ]]; then
    check_prerequisites
    # Si --prerequis est utilisé sans autres arguments de fonctionnalité, on s'arrête
    if [[ "$DO_EXEC" -eq 0 ]] || [[ $# -eq 0 && "$DO_DIFF" -eq 0 ]]; then
        log "Vérification des prérequis terminée."
        exit 0
    fi
fi

# --- Vérification des arguments principaux ---
if [[ $# -lt 1 && "$DO_DIFF" -eq 0 ]]; then
    echo "[ERREUR] Usage: $0 [base_nom] [OPTIONS] ou $0 [duree] [base_nom] [OPTIONS]"
    echo "        Pour détection seule: $0 --diff [OPTIONS]"
    exit 1
fi

# --- Gestion de la durée et du nom de base ---
if [[ "$DO_DIFF" -eq 1 && $# -eq 0 ]]; then
    # Mode détection seule
    BASE_NAME="diff_detection"
    TOTAL_DURATION=0
elif [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    # Premier argument est une durée
    TOTAL_DURATION="$1"
    BASE_NAME="${2:-detection}"
    shift 2
else
    # Premier argument est le nom de base
    TOTAL_DURATION=0 # Illimité par défaut
    BASE_NAME="$1"
    shift
fi

# --- Vérification prérequis automatique ---
check_prerequisites

# --- Configuration des signaux ---
trap 'log "SIGINT reçu: arrêt en cours..."; STOP_AFTER_CURRENT=1; DIFF_STOP_FLAG=1; cleanup; exit 130' SIGINT
trap 'cleanup' EXIT

# --- Lancement des processus ---
log "=== DÉMARRAGE DU SCRIPT v3.0.1 ==="
log "Configuration: base=$BASE_NAME, durée_totale=${TOTAL_DURATION} (0=illimitée), segment_duration=${SEGMENT_SECONDS}s"
log "Audio: device=$AUDIO_DEVICE, mic=$RECORD_MIC, mic_device=$MICROPHONE_DEVICE, volume=$VOLUME_FILTER, mute_output=$MUTE_OUTPUT"
log "Diff: actif=$DO_DIFF, target_dir=$DIFF_TARGET_DIR, durée=$DIFF_DURATION, interval=$DIFF_INTERVAL, threshold=$DIFF_THRESHOLD, record_all=$DIFF_RECORD_ALL"
log "Système: exec=$DO_EXEC, simulate=$DO_SIMULATE, target_dir=$TARGET_DIR"

# Création du répertoire de sortie
if [[ "$DO_SIMULATE" -eq 0 ]]; then
    mkdir -p "$TARGET_DIR"
else
    log "[SIMULATION] mkdir -p $TARGET_DIR"
fi

# Mutage de la sortie si demandé
mute_output

# Lancement de la détection de mouvement en arrière-plan si demandée
if [[ "$DO_DIFF" -eq 1 ]]; then
    log "Lancement de la détection de mouvement en arrière-plan"
    # Désactiver le beep système pour éviter les sons répétitifs
    xset b off 2>/dev/null
    if [[ "$DO_SIMULATE" -eq 0 ]]; then
        diff_detection_loop &
        DIFF_PID=$!
        log "Détection de mouvement lancée (PID: $DIFF_PID)"
    else
        log "[SIMULATION] Détection de mouvement lancée"
        DIFF_PID=54321
    fi
    ACTIONS+=("Détection mouvement activée (PID: $DIFF_PID)")
fi

# Boucle principale de capture vidéo (si un nom de base est fourni et que ce n'est pas juste de la détection)
if [[ -n "$BASE_NAME" && "$BASE_NAME" != "diff_detection" ]]; then
    log "Démarrage capture vidéo"

    seg_index=0
    remaining_duration=$TOTAL_DURATION

    while true; do
        # Vérification des signaux d'arrêt
        if [[ "$STOP_AFTER_CURRENT" -eq 1 ]]; then
            log "Arrêt demandé, sortie de la boucle de capture."
            break
        fi

        # Calcul de la durée du segment actuel
        if [[ "$TOTAL_DURATION" -gt 0 ]]; then
            if [[ "$remaining_duration" -le 0 ]]; then
                log "Durée totale de capture atteinte, arrêt."
                break
            fi
            current_duration=$(( remaining_duration < SEGMENT_SECONDS ? remaining_duration : SEGMENT_SECONDS ))
            remaining_duration=$(( remaining_duration - current_duration ))
        else
            current_duration="$SEGMENT_SECONDS"
        fi

        # Enregistrement du segment
        record_segment "$seg_index" "$current_duration"

        # Attente de la fin du segment
        if [[ "$DO_SIMULATE" -eq 0 ]]; then
            sleep "$current_duration"
        else
            log "[SIMULATION] sleep $current_duration"
            sleep 2 # Simulation rapide
        fi

        # Arrêt du processus ffmpeg
        stop_ffmpeg

        # Vérification et traitement du fichier généré
        if [[ "$DO_SIMULATE" -eq 0 ]]; then
            latest_file=$(ls -t "${TARGET_DIR}/${BASE_NAME}"_*_part${seg_index}.mp4 2>/dev/null | head -n1)
            if [[ -n "$latest_file" ]]; then
                GENERATED_FILES+=("$latest_file")
                log "Segment enregistré: $latest_file (taille: $(stat -c%s "$latest_file" 2>/dev/null || echo "N/A") octets)"

                # Amplification audio si demandée ou utilisation du filtre par défaut
                if [[ -n "$VOLUME_FILTER" ]] || [[ -n "$DEFAULT_AUDIO_FILTER" ]]; then
                    boost_audio "$latest_file"
                fi
            else
                log "ERREUR: Aucun fichier généré pour le segment $seg_index"
            fi
        else
            # Simulation
            local simulated_file="${TARGET_DIR}/${BASE_NAME}_$(date '+%Y%m%d_%H%M%S')_part${seg_index}.mp4"
            GENERATED_FILES+=("$simulated_file")
            log "[SIMULATION] Segment enregistré: $simulated_file"

            if [[ -n "$VOLUME_FILTER" ]] || [[ -n "$DEFAULT_AUDIO_FILTER" ]]; then
                boost_audio "$simulated_file"
            fi
        fi

        seg_index=$((seg_index + 1))
    done
else
    log "Mode détection seule, pas de capture vidéo"

    # Attendre la fin de la détection si elle est active
    if [[ "$DO_DIFF" -eq 1 && "$DIFF_PID" -ne 0 ]]; then
        log "Attente de la fin de la détection de mouvement..."
        if [[ "$DO_SIMULATE" -eq 0 ]]; then
            wait "$DIFF_PID" 2>/dev/null
        else
            log "[SIMULATION] wait $DIFF_PID"
            sleep 5 # Simulation
        fi
        DIFF_PID=0
    fi
fi

# --- Résumé final ---
log "=== RÉSUMÉ DES ACTIONS EFFECTUÉES ==="
if [[ ${#ACTIONS[@]} -gt 0 ]]; then
    action_counter=1
    for action in "${ACTIONS[@]}"; do
        log "$action_counter. $action"
        action_counter=$((action_counter + 1))
    done
else
    log "Aucune action effectuée."
fi

log "=== FICHIERS GÉNÉRÉS ==="
if [[ ${#GENERATED_FILES[@]} -gt 0 ]]; then
    file_counter=1
    for f in "${GENERATED_FILES[@]}"; do
        if [[ "$DO_SIMULATE" -eq 0 ]]; then
            file_size=$(stat -c%s "$f" 2>/dev/null || echo "N/A")
            log "$file_counter. $f (taille: $file_size octets)"
        else
            log "$file_counter. [SIMULATION] $f"
        fi
        file_counter=$((file_counter + 1))
    done
else
    log "Aucun fichier généré."
fi

log "=== FIN DU SCRIPT v3.0.1 ==="
exit 0
