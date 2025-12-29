# Spécifications – Option `--delete-ori` pour `record_cam.sh`

## Objectif
Ajouter une option `--delete-ori` permettant la suppression automatique du fichier MP4 original après qu’un boost audio ait été appliqué et que le fichier résultant ait été correctement sauvegardé.

## Description
- L’option `--delete-ori` est un argument en ligne de commande.  
- Si spécifiée, le script supprime le fichier MP4 original uniquement après que le boost audio ait produit un fichier de sortie valide.  
- Si non spécifiée, le comportement actuel est conservé : le fichier original est préservé.

## Fonctionnement attendu
1. Le boost audio s’exécute normalement (création du fichier `*_boost.mp4`).  
2. Vérification que le fichier boosté existe et est lisible.  
3. Si `--delete-ori` est activé, le script supprime le fichier MP4 original.  
4. Si l’option n’est pas activée, le fichier original reste inchangé.  

## Exemple d’utilisation
\`\`\`bash
./record_cam.sh --volume --delete-ori
\`\`\`
→ Boost audio du fichier généré et suppression automatique du MP4 original après validation.

## Mise à jour de l’aide
Dans `--help`, ajouter :
\`\`\`
  --delete-ori       Supprime le fichier MP4 original après boost audio
\`\`\`

## Changelog
- **v3.2** : Ajout de l’option `--delete-ori` permettant la suppression du fichier original après boost audio.
