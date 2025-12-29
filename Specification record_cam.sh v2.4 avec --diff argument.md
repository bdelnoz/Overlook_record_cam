**Spécifications Complètes pour Record Cam Script Version 2.x**

---

## 1. Pré-requis

* `ffmpeg` : capture audio/vidéo
* `xdpyinfo` : obtenir la résolution de l'écran (installable via `sudo apt-get install xdpyinfo`)
* `ImageMagick` (`compare`) : détection des différences d'images (installable via `sudo apt-get install imagemagick`)
* `bash` : interpréteur du script

> L'option `--prerequis` permet de vérifier tous ces prérequis avant exécution.

---

## 2. Nouveaux Arguments pour Diff/Mouvement

| Argument            | Description                                                         | Valeur par défaut                                                    |
| ------------------- | ------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `--diff`            | Active la détection de mouvement sur la capture d'écran             | Inactif                                                              |
| `--diff-target-dir` | Répertoire où seront stockées les images de diff                    | `./diff_output`                                                      |
| `--diff-duration`   | Durée d'activité de la détection (indépendante de la capture vidéo) | 0 (ad vitam aeternam)                                                |
| `--diff-interval`   | Intervalle entre captures d'images pour diff                        | 3 (secondes)                                                         |
| `--diff-threshold`  | Seuil de différence (%) pour considérer un mouvement                | 5                                                                    |
| `--diff-record-all` | Enregistre toutes les images de diff générées                       | Faux (conserver seulement les images finales avec carré fluorescent) |

---

## 3. Fonctionnement

1. Vérification des prérequis si `--prerequis` est actif.
2. Capture vidéo normale inchangée.
3. Si `--diff` est actif :

   * Capture d'images à l'intervalle défini.
   * Comparaison des images consécutives avec `compare` d'ImageMagick.
   * Détection des mouvements selon le seuil (`--diff-threshold`).
   * Création d'image JPEG avec carré fluorescent sur mouvement détecté.
   * Stockage automatique dans le répertoire défini par `--diff-target-dir`.
   * Durée limitée par `--diff-duration`, 0 pour illimité.

> Les fonctions existantes de capture vidéo, son, segments, boosting restent inchangées.

---

## 4. Changelog

* **v1.0 - v2.0** : Fonctionnalités de capture vidéo et son.
* **v2.1** : Ajout segmentation vidéo.
* **v2.2** : Ajout options de log et boost du son.
* **v2.3** : Ajout `--diff` initial, capture d'images et carré fluorescent.
* **v2.4** : Ajout `--diff-target-dir`, `--diff-delay`, et `--diff-record-all`.
* **v2.5 / 2.x actuel** : Ajout `--diff-duration`, `--diff-interval`, `--diff-threshold`, vérification prérequis intégrée.

---

## 5. Exemples

### 5.1 Exemples existants (capture seule)

```bash
./record_cam.sh -duration 7200 -segment 300 -muteoutput
```

### 5.2 Exemples nouveaux (diff seule)

```bash
./record_cam.sh --diff --diff-duration 3600 --diff-interval 3 --diff-target-dir ./diff_output
```

### 5.3 Exemples combinés (capture vidéo + diff)

```bash
./record_cam.sh -duration 7200 -segment 300 --diff --diff-duration 3600 --diff-interval 3 --diff-target-dir ./diff_output
```

### 5.4 Exemples avec options supplémentaires

```bash
./record_cam.sh -duration 7200 -segment 300 -boost 5 --diff --diff-duration 7200 --diff-interval 5 --diff-threshold 10 --diff-target-dir ./diff_output
```

---

## 6. Notes importantes

* `--diff-duration` est indépendant de la durée principale de capture.
* `--diff-interval` définit la fréquence de capture pour la détection de mouvement.
* `--diff-record-all` permet de conserver toutes les images intermédiaires ou seulement les images finales avec carré fluorescent.
* Les logs sont toujours actifs et stockés dans le répertoire d'exécution du script.
* Les arguments existants pour capture vidéo restent inchangés.
* `--prerequis` vérifie automatiquement l'installation des outils nécessaires.

---




Changelog

v1.0 à v1.9 : historique complet inchangé.

v2.0 à v2.2 : ajout progressif de --diff et ses fonctionnalités.

v2.3 :

Intégration finale des arguments --diff, --diff_delay, --diff_target_dir, --diff_interval, --diff_threshold, --diff_record_all_images.

Détection en parallèle avec l’enregistrement vidéo.

Capture et marquage des mouvements avec carré fluorescent.

Logging permanent dans le répertoire d’exécution ou de détection.

Pré-requis clairement listés et vérifiés.

--help mis à jour avec tous les exemples.


**Fin des Spécifications Version 2.x**
