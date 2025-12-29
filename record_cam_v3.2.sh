#!/bin/bash
#
# record_cam.sh - Script d'enregistrement caméra avec options avancées
#
# Version 3.2
#

VERSION="3.2"

show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --volume            Booste le volume audio du fichier enregistré"
    echo "  --delete-ori        Supprime le fichier MP4 original après boost audio (si valide)"
    echo "  --help              Affiche cette aide"
    echo "  --version           Affiche la version du script"
}

show_version() {
    echo "record_cam.sh version $VERSION"
}

# Variables par défaut
DO_VOLUME=0
DO_DELETE_ORI=0

# Parsing arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --volume)
            DO_VOLUME=1
            shift
            ;;
        --delete-ori)
            DO_DELETE_ORI=1
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        --version)
            show_version
            exit 0
            ;;
        *)
            echo "Option inconnue: $1"
            show_help
            exit 1
            ;;
    esac
done

# Exemple de fichier généré (dans un vrai script, ce fichier est produit par la capture caméra)
OUTPUT_FILE="output.mp4"

# Fonction boost audio
boost_audio() {
    local infile="$1"
    local outfile="./boost/$(basename "$infile" .mp4)_boost.mp4"

    mkdir -p ./boost

    echo ">> Boost audio : $infile -> $outfile"
    ffmpeg -i "$infile" -vcodec copy -af "volume=2.0" "$outfile" -y

    # Vérification avec ffprobe
    if ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "$outfile" | grep -q "audio"; then
        echo ">> Vérification OK : fichier boosté valide."
        if [[ $DO_DELETE_ORI -eq 1 ]]; then
            echo ">> Suppression du fichier original : $infile"
            rm -f "$infile"
        fi
    else
        echo "!! Erreur : fichier boosté invalide, conservation de l’original."
    fi
}

# Execution principale
if [[ $DO_VOLUME -eq 1 ]]; then
    boost_audio "$OUTPUT_FILE"
fi

# --- Changelog ---
# v3.2 : Ajout de l’option --delete-ori avec vérification ffprobe avant suppression du fichier original.
# v3.1 : Version précédente avec boost audio et améliorations diverses.
