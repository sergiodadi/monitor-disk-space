# monitor-disk-space
monitor-disk-space.sh - Surveillance de l'espace disque sur plusieurs serveurs via SSH avec alertes par email
# Disk Space Monitor

Version: 2.6

## Description
Script de surveillance d'espace disque pour serveurs Linux. Vérifie l'espace disque sur plusieurs serveurs via SSH et envoie des alertes par email.

## Fonctionnalités
- Surveillance multi-serveurs via SSH
- Génération de rapports HTML
- Alertes par email selon les seuils d'utilisation
- Identification des plus grands répertoires et fichiers
- Rotation des logs avec compression

## Utilisation

./monitor-disk-space.sh [OPTIONS]

## Configuration
Modifier les fichiers :

- /usr/local/etc/disk-monitor.conf : Configuration principale
- /usr/local/etc/server-disk-space.conf : Liste des serveurs

## Options
Options:
-  -c, --critical [NOMBRE]       Seuil critique en % (défaut: 90)
-  -C, --critical-email [EMAIL]  Email pour les alertes de niveau critique
-  -d, --days [NOMBRE]           Jours avant recalcul des grands répertoires/fichiers (défaut: 7)
-  -D, --no-dirs                 Désactive le calcul des grands répertoires
-  -E, --exclude-servers "LISTE" Liste de serveurs à exclure des calculs intensifs (format: "serveur1,serveur2,...")
-  -f, --num-big-files [NOMBRE]  Nombre de grands fichiers à afficher (défaut: 3)
-  -F, --no-files                Désactive le calcul des grands fichiers
-  -h, --help                    Affiche ce message d'aide
-  -I, --info-email [EMAIL]      Email pour les rapports sans alerte
-  -l, --list-server             Liste les serveurs configurés
-  -m, --max-logs [NOMBRE]       Nombre maximal de fichiers logs à conserver (défaut: 30)
-  -M, --mail-big-files [EMAIL]  Envoie une liste consolidée des plus gros fichiers
-  -n, --num-big-dirs [NOMBRE]   Nombre de grands répertoires à afficher (défaut: 3)
-  -P, --mail-big-dirs [EMAIL]   Envoie une liste consolidée des plus gros répertoires
-  -r, --rotate-logs             Active la rotation des fichiers logs
-  -R, --no-rotate-logs          Désactive la rotation des fichiers logs
-  -S, --skip-normal             Ne pas envoyer d'email si aucun seuil n'est atteint
-  -t, --test                    Mode test avec fichier de configuration alternatif
-  -T, --timing                  Affiche le temps de traitement pour chaque serveur
-  -v, --verbose                 Mode verbeux (log détaillé)
-  -V, --version                 Affiche la version du script
-  -w, --warning [NOMBRE]        Seuil d'avertissement en % (défaut: 75)
-  -W, --warning-email [EMAIL]   Email pour les alertes de niveau avertissement
-  -x, --compress-logs           Active la compression des anciens fichiers logs
-  -X, --no-compress-logs        Désactive la compression des anciens fichiers logs
-  -z, --zero-calc               Réinitialise le calcul des grands répertoires et fichiers

## Format du fichier de configuration des serveurs
serveur:partitions:seuil_warning:seuil_critical
Exemples:

- serveur1 - Vérifie seulement la partition / avec les seuils par défaut
- serveur2:/var,/home - Vérifie / et les partitions spécifiées avec les seuils par défaut
- serveur3:/var:60:85 - Vérifie / et /var avec des seuils personnalisés (60% et 85%)

## Installation
- Copiez le script dans un répertoire approprié (ex: /usr/local/bin/)
- Rendez-le exécutable: chmod +x /usr/local/bin/monitor-disk-space.sh
- Créez les fichiers de configuration dans /usr/local/etc/
- Créez le répertoire pour les logs: mkdir -p /var/log/monitor-disk-space

## Sécurité
Ce script nécessite un accès SSH par clé aux serveurs surveillés. Assurez-vous de configurer correctement les clés SSH pour l'utilisateur qui exécutera le script.

## IA
l'IA Claude m'a beaucoup aidé...
