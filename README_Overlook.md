# Overlook

## 🎥 Présentation

**Overlook** est un outil d’enregistrement automatisé basé sur `FFmpeg`, conçu pour capturer en continu l’écran ou un flux vidéo.  
Il segmente les enregistrements, ajuste le volume, et assure un fonctionnement en boucle stable, avec journalisation intégrée.

## 🚀 Fonctionnalités principales

- Capture de l’écran avec `FFmpeg`
- Bouclage automatique des sessions d’enregistrement
- Augmentation configurable du volume (`+2dB`, `+4dB`, etc.)
- Sauvegarde automatique des fichiers `.mp4`
- Gestion des erreurs et logs détaillés
- Mode silencieux ou verbeux selon les besoins

## ⚙️ Installation

```bash
git clone https://github.com/votre-nom/Overlook.git
cd Overlook
chmod +x overlook.sh
```

## 🧩 Utilisation

```bash
./overlook.sh --duree 600 --volume +4 --output /chemin/de/sortie
```

| Argument | Description |
|-----------|--------------|
| `--duree` | Durée d’une capture en secondes |
| `--volume` | Gain audio appliqué (ex: +4 pour +4dB) |
| `--output` | Dossier de destination des vidéos |
| `--verbose` | Active le mode verbeux |

## 🧠 Exemple concret

```bash
./overlook.sh --duree 900 --volume +6 --output ~/Videos/overlook
```

Enregistre des sessions de 15 minutes avec un volume amplifié de +6dB.

## 🧾 Licence

Ce projet est distribué sous licence MIT.

---

**Auteur :** Bruno Delnoz  
**Version :** 3.0.1  
**Nom de code :** Overlook  
**Description :** Capture visuelle continue avec gestion du son et bouclage automatique.
