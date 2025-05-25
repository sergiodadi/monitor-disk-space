#
#!/bin/bash
#
# monitor-disk-space.sh - Surveillance de l'espace disque sur plusieurs serveurs via SSH avec alertes par email

#--------------------------------------------------------------
# [OBJECTIF PRINCIPAL]
#--------------------------------------------------------------
# Ce script surveille l'espace disque sur plusieurs serveurs via SSH.
# Il génère des rapports HTML et envoie des alertes par email selon les seuils d'utilisation.
# Il peut également identifier les plus grands répertoires et fichiers pour faciliter le nettoyage.
# Une rotation des fichiers logs est également disponible avec compression automatique.
# Il permet désormais de trier les serveurs par pourcentage d'utilisation (croissant ou décroissant).
# Il valide les noms de serveurs pour éviter les erreurs liées à des configurations incorrectes.
#
#--------------------------------------------------------------
# [ORGANIGRAMME DES FONCTIONS PRINCIPALES]
#--------------------------------------------------------------
# 1. Initialisation et traitement des arguments
# 2. Analyse et validation du fichier de serveurs (server-disk-space.conf)
#    - Les serveurs aux noms invalides sont signalés ou exclus selon le mode de validation
# 3. Pour chaque serveur valide:
#    a. Vérification de l'accessibilité (check_server_reachable)
#    b. Vérification de l'espace disque (check_disk_space)
#    c. Recherche des plus grands répertoires et fichiers (si activé)
#       - Les serveurs dans EXCLUDED_SERVERS sont exclus de cette étape
#    d. Vérification des seuils d'alerte (check_for_alerts)
# 4. Si demandé, création d'un rapport trié par pourcentage d'utilisation (show_sorted_usage)
# 5. Génération du rapport HTML standard avec avertissements sur les serveurs invalides
# 6. Envoi des emails selon le niveau d'alerte
# 7. Envoi des rapports consolidés (si demandé)
# 8. Rotation des logs (si activée)
# 9. Nettoyage
#
#--------------------------------------------------------------
# [EXPLICATIONS COMPLÉMENTAIRES]
#--------------------------------------------------------------
# - Le script utilise flock pour éviter les exécutions simultanées
# - La configuration est séparée en fichiers distincts:
#   * disk-monitor.conf: paramètres globaux et adresses email
#   * server-disk-space.conf: liste des serveurs à surveiller
# - Format du fichier server-disk-space.conf:
#   serveur:partitions:seuil_warning:seuil_critical
#   Exemples:
#     serveur1:/                   # Vérifie / avec seuils par défaut
#     serveur2:/var,/home          # Vérifie / et les partitions spécifiées
#     serveur3:/var:60:85          # Vérifie / et /var avec seuils personnalisés
# - Les résultats des analyses de grands répertoires/fichiers sont mis en cache
#   et recalculés périodiquement pour réduire la charge
# - Certains serveurs peuvent être exclus des calculs intensifs (grands fichiers
#   et répertoires) via la variable EXCLUDED_SERVERS dans disk-monitor.conf
# - Une rotation des logs est disponible pour gérer automatiquement les anciens
#   fichiers logs, avec compression optionnelle
# - Les options -u et -U permettent d'obtenir un rapport trié des serveurs par
#   pourcentage d'utilisation (croissant ou décroissant respectivement)
# - La validation des noms de serveurs permet d'éviter les erreurs liées à des
#   configurations incorrectes (trois modes disponibles: strict, warn, off)
#
#--------------------------------------------------------------
# [LISTE DES FONCTIONS] (par ordre alphabétique)
#--------------------------------------------------------------
# check_big_dirs_calculation: Vérifie si les grands répertoires doivent être recalculés
# check_big_files_calculation: Vérifie si les grands fichiers doivent être recalculés
# check_disk_space      : Vérifie l'espace disque d'un serveur
# check_for_alerts      : Vérifie si les seuils d'alerte sont atteints pour un serveur
# check_server_reachable: Vérifie si un serveur est accessible via ping
# create_css            : Génère le CSS pour le rapport HTML
# extract_big_data      : Extrait les données des grands répertoires/fichiers
# is_server_excluded    : Vérifie si un serveur est dans la liste des exclusions
# list_servers          : Affiche la liste des serveurs configurés
# log                   : Écrit un message dans le fichier de log
# rotate_logs           : Gère la rotation des fichiers de logs avec compression optionnelle
# rotate_specific_file  : Effectue la rotation d'un fichier spécifique
# send_consolidated_reports: Génère et envoie les rapports consolidés
# show_help             : Affiche l'aide du script
# show_sorted_usage     : Affiche l'utilisation du disque triée par pourcentage
# show_version          : Affiche la version du script
# validate_server_name  : Valide le format et la syntaxe d'un nom de serveur
#
#--------------------------------------------------------------
# [VARIABLES] (par ordre alphabétique)
#--------------------------------------------------------------
# BIG_DIRS_EMAIL       : Destinataire des rapports sur les grands répertoires
# BIG_DIRS_FILE        : Fichier de cache des grands répertoires
# BIG_FILES_EMAIL      : Destinataire des rapports sur les grands fichiers
# BIG_FILES_FILE       : Fichier de cache des grands fichiers
# CALC_BIG_DIRS        : Active/désactive le calcul des grands répertoires
# CALC_BIG_FILES       : Active/désactive le calcul des grands fichiers
# CALC_DAYS            : Nombre de jours avant recalcul des grands répertoires/fichiers
# CONFIG_FILE          : Fichier de configuration principal
# CRITICAL_EMAIL       : Destinataire des alertes de niveau critique
# CRITICAL_THRESHOLD   : Seuil d'utilisation critique (%)
# DATE                 : Date d'exécution (format YYYY-MM-DD)
# EMAIL_SENDER         : Adresse d'expéditeur pour les emails
# EXCLUDED_SERVERS     : Liste des serveurs exclus des calculs intensifs (séparés par des virgules)
# HOSTNAME             : Nom de l'hôte exécutant le script
# INFO_EMAIL           : Destinataire des rapports normaux
# INVALID_SERVERS      : Tableau des serveurs avec noms invalides
# LOCK_FILE            : Fichier de verrouillage pour éviter les exécutions simultanées
# LOG_DIR              : Répertoire des fichiers de log
# LOG_FILE             : Fichier de log
# LOG_ROTATION_COMPRESS: Active/désactive la compression des logs lors de la rotation
# LOG_ROTATION_ENABLED : Active/désactive la rotation des logs
# LOG_ROTATION_MAX_FILES: Nombre maximal de fichiers logs à conserver lors de la rotation
# MAIL_BIG_DIRS        : Active/désactive l'envoi des rapports sur les grands répertoires
# MAIL_BIG_FILES       : Active/désactive l'envoi des rapports sur les grands fichiers
# NUM_BIG_DIRS         : Nombre de grands répertoires à afficher
# NUM_BIG_FILES        : Nombre de grands fichiers à afficher
# SERVER_LIST          : Fichier contenant la liste des serveurs à surveiller
# SERVER_LIST_TEST     : Fichier de liste de serveurs pour le mode test
# SERVER_VALIDATION_MODE: Mode de validation des noms de serveurs (strict/warn/off)
# SHOW_SERVER_TIMING   : Active/désactive l'affichage du temps de traitement par serveur
# SHOW_USAGE_SORTED    : Détermine si le tri de l'utilisation est activé ("asc" ou "desc")
# SIMULATION_MODE      : Mode simulation (pour tests)
# SKIP_NORMAL_MAIL     : Si activé, n'envoie pas d'email quand tout est normal
# SKIP_STANDARD_REPORT : Si activé, n'envoie pas le rapport standard
# TEMP_DIR             : Répertoire temporaire
# TEST_MODE            : Active/désactive le mode test
# TIME                 : Heure d'exécution (format HH:MM:SS)
# VERBOSE              : Active/désactive le mode verbeux
# VERSION              : Version du script
# WARNING_EMAIL        : Destinataire des alertes de niveau avertissement
# WARNING_THRESHOLD    : Seuil d'utilisation pour les avertissements (%)
#
#--------------------------------------------------------------
# [OPTIONS] (par ordre alphabétique)
#--------------------------------------------------------------
# -c, --critical [NOMBRE]       : Seuil critique en % (défaut: 90)
# -C, --critical-email [EMAIL]  : Email pour les alertes de niveau critique
# -d, --days [NOMBRE]           : Jours avant recalcul des grands répertoires/fichiers (défaut: 7)
# -D, --no-dirs                 : Désactive le calcul des grands répertoires
# -E, --exclude-servers "LISTE" : Liste de serveurs à exclure des calculs intensifs (format: "serveur1,serveur2,...")
# -f, --num-big-files [NOMBRE]  : Nombre de grands fichiers à afficher (défaut: 3)
# -F, --no-files                : Désactive le calcul des grands fichiers
# -h, --help                    : Affiche ce message d'aide
# -I, --info-email [EMAIL]      : Email pour les rapports sans alerte
# -l, --list-server             : Liste les serveurs configurés
# -m, --max-logs [NOMBRE]       : Nombre maximal de fichiers logs à conserver (défaut: 30)
# -M, --mail-big-files [EMAIL]  : Envoie une liste consolidée des plus gros fichiers
# -n, --num-big-dirs [NOMBRE]   : Nombre de grands répertoires à afficher (défaut: 3)
# -N, --validate-names [MODE]   : Validation des noms de serveurs (strict/warn/off, défaut: strict)
# -P, --mail-big-dirs [EMAIL]   : Envoie une liste consolidée des plus gros répertoires
# -r, --rotate-logs             : Active la rotation des fichiers logs
# -R, --no-rotate-logs          : Désactive la rotation des fichiers logs
# -S, --skip-normal             : Ne pas envoyer d'email si aucun seuil n'est atteint
# -t, --test                    : Mode test avec fichier de configuration alternatif
# -T, --timing                  : Affiche le temps de traitement pour chaque serveur
# -u, --usage-sort-asc          : Affiche l'utilisation du disque triée par ordre croissant
# -U, --usage-sort-desc         : Affiche l'utilisation du disque triée par ordre décroissant
# -v, --verbose                 : Mode verbeux (log détaillé)
# -V, --version                 : Affiche la version du script
# -w, --warning [NOMBRE]        : Seuil d'avertissement en % (défaut: 75)
# -W, --warning-email [EMAIL]   : Email pour les alertes de niveau avertissement
# -x, --compress-logs           : Active la compression des anciens fichiers logs
# -X, --no-compress-logs        : Désactive la compression des anciens fichiers logs
# -z, --zero-calc               : Réinitialise le calcul des grands répertoires et fichiers
#
# [7 mai 2025] v 1.0
# - première mise en exploitation sur le site de nice
#
# [8 mai 2025] v 1.1
# - correction du bug d'affichage des grands répertoires et fichiers (gestion par serveur)
#
# [8 mai 2025] v 1.2
# - ajout d'une option pour choisir le nombre de jours entre les calculs des grands répertoires et fichiers
#
# [10 mai 2025] v 1.3
# - renommage du script de check_disk_space.sh à monitor-disk-space.sh
# - ajout d'une variable SCRIPT_NAME pour le nom du script
#
# [11 mai 2025] v 1.4
# - ajout du verrouillage d'exécution avec flock pour éviter les exécutions simultanées
# - modification du titre et format d'envoi des emails (sans date, avec charset UTF-8)
# - ajout d'envoi à différentes adresses email selon le niveau d'alerte
# - ajout des options pour configurer les adresses email
# - ajout d'un mode simulation (-s/--simulate) pour tester les alertes
# - ajout des options pour configurer les seuils d'alerte (-w/--warning et -c/--critical)
# - ajout de la mesure de durée d'exécution dans le rapport
#
# [12 mai 2025] v 1.5
# - amélioration de l'affichage des points de montage avec LANG=C
# - nettoyage du code et suppression des variables dupliquées
#
# [13 mai 2025] v 1.6
# - ajout d'un saut de ligne en mode verbose avant le traitement de chaque serveur
#
# [13 mai 2025] v 2.0
# - ajout des options -M/--mail-big-files et -P/--mail-big-dirs pour l'envoi d'emails
#   contenant les listes consolidées des plus gros fichiers et répertoires
# - ajout des versions courtes -I/-W/-C pour les options --info-email, --warning-email et --critical-email
# - amélioration du formatage des rapports consolidés avec tableaux HTML et élimination des doublons
# - ajout de l'option -t/--test pour utiliser un fichier de serveurs de test
# - possibilité de ne recevoir que les rapports spécifiques avec -M/-P sans le rapport standard
# - mise à jour de l'aide et de la documentation
#
# [14 mai 2025] v 2.1
# - centralisation de l'adresse d'expéditeur dans une variable EMAIL_SENDER
# - amélioration de la présentation des emails avec un nom d'affichage pour l'expéditeur
# - utilisation d'un domaine fixe pour l'adresse d'expéditeur au lieu du hostname dynamique
#
# [14 mai 2025] v 2.2
# - ajout de la possibilité de définir des seuils d'alerte personnalisés par serveur
# - modification du format du fichier de configuration des serveurs pour inclure les seuils personnalisés
# - mise à jour de la fonction check_disk_space pour utiliser les seuils personnalisés
# - mise à jour de la fonction list_servers pour afficher les seuils personnalisés
# - amélioration de la documentation et de l'aide pour refléter le nouveau format de configuration
#
# [14 mai 2025] v 2.3
# - ajout de la possibilité de désactiver l'envoi des mails quand aucun seuil n'est atteint (-S/--skip-normal)
# - correction des problèmes avec les seuils personnalisés par serveur
#
# [15 mai 2025] v 2.4
# - ajout de l'option -T/--timing pour mesurer et afficher le temps de traitement de chaque serveur
# - ajout d'un tableau récapitulatif des temps de traitement à la fin du rapport HTML
# - optimisation de l'affichage des temps dans les logs (uniquement en mode verbose)
# - tri des serveurs par temps de traitement dans le rapport récapitulatif
#
# [16 mai 2025] v 2.5
# - Externalisation des données sensibles dans un fichier de configuration
# - Modification des extensions des fichiers de configuration (.lis -> .conf)
# - Remplacement des domaines email réels par des domaines d'exemple
#
# [16 mai 2025] v 2.5.1
# - Correction d'un bug critique qui empêchait l'exclusion de serveurs des calculs intensifs
# - Suppression des définitions en double de variables qui causaient des problèmes
# - Amélioration des logs pour mieux tracer l'exclusion des serveurs
# - Ajout de logs supplémentaires pour déboguer la fonction d'exclusion des serveurs
#
# [16 mai 2025] v 2.6
# - Ajout d'une fonctionnalité de rotation des fichiers logs avec compression
# - Ajout des options -r/--rotate-logs et -R/--no-rotate-logs pour activer/désactiver la rotation
# - Ajout des options -m/--max-logs pour définir le nombre max de fichiers logs à conserver
# - Ajout des options -x/--compress-logs et -X/--no-compress-logs pour activer/désactiver la compression
# - Ajout des fonctions rotate_logs et rotate_specific_file pour gérer la rotation des logs
# - Mise à jour de la documentation et de l'aide pour les nouvelles options
#
# [17 mai 2025] v 2.6.1
# - Ajout des options -u/--usage-sort-asc et -U/--usage-sort-desc pour trier les serveurs par utilisation
# - Ajout de la fonction show_sorted_usage pour générer et envoyer un rapport d'utilisation trié
# - Amélioration de la fonction check_disk_space pour standardiser le format de sortie avec LC_ALL=C
# - Correction des problèmes d'affichage des données dans les rapports
# - Meilleure gestion des en-têtes et des formats de sortie spécifiques à chaque serveur
# - Mise à jour de la documentation et de l'aide pour les nouvelles options
#
# [17 mai 2025] v 2.6.2
# - Ajout de la validation des noms de serveurs pour éviter les erreurs de configuration
# - Ajout de la fonction validate_server_name pour vérifier la syntaxe et le format des noms
# - Ajout de l'option -N/--validate-names pour configurer le mode de validation (strict/warn/off)
# - Ajout d'un avertissement dans le rapport HTML pour les serveurs avec noms invalides
# - Mode strict par défaut: les serveurs avec noms invalides sont exclus du traitement
# - Les serveurs mal configurés sont clairement identifiés dans le rapport
# - Mise à jour de la documentation et de l'aide pour la nouvelle fonctionnalité
#
# [18 mai 2025] v 2.6.3
# - Correction du bug dans show_sorted_usage qui tentait de ping des serveurs avec leurs partitions
# - Extraction correcte du nom du serveur avant de faire un ping pour les serveurs avec configuration complexe
# - Amélioration des logs avec séparation visuelle entre les serveurs dans la fonction show_sorted_usage
# - Traitement correct des serveurs avec configuration de partitions personnalisées pour le tri d'utilisation
# - Meilleure gestion de la fonction log pour traiter les lignes vides dans les logs et sur le terminal
#
# [18 mai 2025] v 2.6.4
# - Ajout d'un mode de validation de configuration (-Z, --validate-config)
# - Vérification complète des serveurs, de leur accessibilité et de leurs configurations sans exécution complète
# - Test de connectivité (DNS, ping, SSH) pour tous les serveurs
# - Vérification des partitions configurées sur chaque serveur
# - Envoi d'un rapport de validation par email avec code couleur et statistiques précises
# - Détection précoce des problèmes de configuration et de connectivité
# - Amélioration de la fiabilité globale du script
#
#[20 mai 2025] v 2.6.5
# - Correction critique du comportement de l'option -U/--usage-sort-desc qui n'exécutait pas correctement le tri
# - Ajout d'une désactivation automatique du mode validation lorsque l'option de tri est activée
# - Implémentation d'une exécution autonome de show_sorted_usage sans les autres parties du script
# - Priorité donnée aux options de tri sur les autres fonctionnalités pour une meilleure expérience utilisateur
# - Initialisation explicite de la variable VALIDATION_MODE à false par défaut
# - Optimisation du flux d'exécution pour éviter les traitements inutiles en mode tri d'utilisation
#
# [21 mai 2025] v 2.6.6
# - Amélioration de la compatibilité avec macOS (Darwin) pour la surveillance des serveurs Apple
# - Détection automatique du système d'exploitation via la commande uname
# - Adaptation des commandes df et du traitement des sorties selon le système d'exploitation détecté
# - Correction de l'affichage des points de montage sur macOS avec gestion appropriée des colonnes
# - Ajout de fonctions spécifiques (detect_os, get_disk_info) pour gérer les différences entre OS
#
# [22 mai 2025] v 2.6.7
# - Correction du problème d'affichage des noms de serveurs incluant un utilisateur SSH
# - Modification de la fonction build_display_name pour n'afficher que le nom du serveur sans l'utilisateur
# - Conservation des informations d'utilisateur pour la connexion SSH tout en améliorant l'affichage
# - Meilleure documentation pour la gestion des serveurs avec authentification user@serveur
# - Mise à jour de l'aide pour clarifier le format de configuration et l'affichage des rapports
# - Correction de bugs mineurs dans la génération des rapports HTML
# - Amélioration de la détection des systèmes macOS (prise en charge des volumes APFS)
# - Optimisation des commandes SSH pour réduire la charge réseau
# - Ajout de la version du script dans les en-têtes de rapport
# - Correction des calculs d'espace pour les systèmes avec des unités en TiB/GiB
# - Standardisation du formatage des tailles de disque dans les rapports
#
# [22 mai 2025] v 2.6.8
# - Ajout de l'affichage de la commande complète utilisée pour lancer le script dans tous les rapports
# - Modification de tous les rapports HTML (principal, validation, tri d'utilisation, consolidés) 
#   pour inclure la commande avec ses options dans la ligne "Généré par..."
# - Ajout de la variable FULL_COMMAND pour capturer automatiquement "$0 $*"
# - Amélioration de la traçabilité : possibilité de savoir exactement quelle commande a généré quel rapport
# - Mise à jour des fonctions show_sorted_usage, generate_validation_report et send_consolidated_reports
# - Correction de la fonction list_servers dupliquée (suppression de la version simplifiée)
#
# [24 mai 2025] v 2.6.9 
# - CORRECTION CRITIQUE: Bug de duplication des partitions dans check_disk_space() et show_sorted_usage()
# - Suppression de la logique défaillante "partitions="/ $additional_partitions""
# - Les partitions spécifiées dans le fichier de config ne sont plus ajoutées à "/" par défaut
# - Utilisation d'un tableau pour traiter les partitions multiples (IFS=',' read -ra PARTITION_ARRAY)
# - Nettoyage automatique des espaces dans les noms de partitions
# - Vérification et omission des partitions vides
# - AMÉLIORATION: Cohérence entre check_disk_space() et show_sorted_usage()
# - Application de la même logique de traitement des partitions dans les deux fonctions
# - Les options -U et -u n'affichent plus de doublons
# - AMÉLIORATION: Simplification du format de fichier de configuration
# - Plus de filesystem par défaut ajouté automatiquement
# - Le fichier de config spécifie exactement les partitions à vérifier
# - Format plus prévisible : une partition listée = une vérification
#

# Vérifier qu'une seule instance du script s'exécute à la fois
LOCK_FILE="/var/lock/monitor-disk-space.lock"

# Utiliser flock pour gérer le verrouillage
(
# Tentative d'acquérir un verrou exclusif, sortir immédiatement si impossible (-n)
flock -n 200 || {
    echo "Une autre instance du script est déjà en cours d'exécution."
    exit 1
}

# Fichier de configuration principal
CONFIG_FILE="/usr/local/etc/disk-monitor.conf"

# Variables de configuration par défaut (seront écrasées si définies dans le fichier de config)
VERSION="2.6.8"
SCRIPT_NAME=$(basename "$0")
SERVER_LIST="/usr/local/etc/server-disk-space.conf"
SERVER_LIST_TEST="/usr/local/etc/server-disk-space-test.conf"
TEST_MODE=false
SKIP_NORMAL_MAIL=false  # Par défaut, envoyer les mails même quand tout est normal
SHOW_SERVER_TIMING=false  # Par défaut, ne pas afficher le temps de traitement par serveur

# Configuration pour la rotation des logs
LOG_ROTATION_ENABLED=true       # Activer/désactiver la rotation des logs
LOG_ROTATION_MAX_FILES=30       # Nombre maximal de fichiers de logs à conserver
LOG_ROTATION_COMPRESS=true      # Compresser les anciens logs

# Adresse d'expéditeur pour les emails (valeur par défaut)
EMAIL_SENDER="Disk Monitor <disk-monitor@exemple.com>"

# Adresses email par défaut pour chaque niveau d'alerte
INFO_EMAIL="infos@exemple.com"
WARNING_EMAIL="warning@exemple.com"
CRITICAL_EMAIL="critique@exemple.com"

# Options pour l'envoi des listes consolidées
MAIL_BIG_FILES=false
MAIL_BIG_DIRS=false
BIG_FILES_EMAIL="$INFO_EMAIL" # Par défaut, même adresse que les rapports info
BIG_DIRS_EMAIL="$INFO_EMAIL"  # Par défaut, même adresse que les rapports info
SKIP_STANDARD_REPORT=false

# Autres variables par défaut
WARNING_THRESHOLD=75
CRITICAL_THRESHOLD=90
SIMULATION_MODE=false
SHOW_USAGE_SORTED=""  # Vide par défaut, "asc" pour croissant, "desc" pour décroissant
SERVER_VALIDATION_MODE="strict"  # Peut être "strict" ou "warn"
VALIDATION_MODE=false  # Par défaut, ne pas activer le mode validation

# Charger la configuration depuis le fichier externe si existant
if [ -f "$CONFIG_FILE" ]; then
    . "$CONFIG_FILE"  # Le point est une commande shell pour "sourcer" un fichier
    echo "Configuration chargée depuis $CONFIG_FILE"
    echo "Serveurs exclus: $EXCLUDED_SERVERS"
fi

LOG_DIR="/var/log/monitor-disk-space"
TEMP_DIR="/tmp/disk-space-monitor"
BIG_DIRS_FILE="$LOG_DIR/big_directories.log"
BIG_FILES_FILE="$LOG_DIR/big_files.log"
DATE=$(date +"%Y-%m-%d")
TIME=$(date +"%H:%M:%S")
HOSTNAME=$(hostname)
VERBOSE=false
LOG_FILE="$LOG_DIR/disk-space-check-$DATE.log"

# Nombre de grands répertoires à afficher (par défaut: 3)
NUM_BIG_DIRS=3
# Nombre de grands fichiers à afficher (par défaut: 3)
NUM_BIG_FILES=3
# Activation du calcul des grands répertoires (par défaut: activé)
CALC_BIG_DIRS=false
# Activation du calcul des grands fichiers (par défaut: activé)
CALC_BIG_FILES=false
# Nombre de jours avant recalcul des grands répertoires/fichiers (par défaut: 7)
CALC_DAYS=7

# Capturer la commande complète utilisée pour lancer le script
FULL_COMMAND="$0 $*"

# Enregistrer l'heure de début
START_TIME=$(date +%s)

#
# debut des fonctions
#

# Fonction de validation complète
validate_configuration() {
    local critical_errors=0
    local warnings=0
    
    echo "Mode validation : vérification de la configuration..."
    
    # 1. Vérification des fichiers de configuration
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "ERREUR CRITIQUE: Fichier de configuration principal introuvable: $CONFIG_FILE"
        critical_errors=$((critical_errors + 1))
    else
        echo "OK: Fichier de configuration principal trouvé: $CONFIG_FILE"
        
        # Vérifier la syntaxe du fichier
        if ! bash -n "$CONFIG_FILE" 2>/dev/null; then
            echo "ERREUR: Le fichier de configuration contient des erreurs de syntaxe"
            critical_errors=$((critical_errors + 1))
        else
            echo "OK: Syntaxe du fichier de configuration correcte"
        fi
    fi
    
    if [ ! -f "$SERVER_LIST" ]; then
        echo "ERREUR CRITIQUE: Fichier de liste de serveurs introuvable: $SERVER_LIST"
        critical_errors=$((critical_errors + 1))
    else
        echo "OK: Fichier de liste de serveurs trouvé: $SERVER_LIST"
    fi
    
    # 2. Vérification des droits d'accès
    if [ ! -r "$CONFIG_FILE" ]; then
        echo "ERREUR: Pas de droits de lecture sur $CONFIG_FILE"
        critical_errors=$((critical_errors + 1))
    fi
    
    if [ ! -r "$SERVER_LIST" ]; then
        echo "ERREUR: Pas de droits de lecture sur $SERVER_LIST"
        critical_errors=$((critical_errors + 1))
    fi
    
    # 3. Vérification des répertoires
    if [ ! -d "$LOG_DIR" ]; then
        echo "AVERTISSEMENT: Répertoire de logs inexistant: $LOG_DIR (sera créé)"
        warnings=$((warnings + 1))
    else
        if [ ! -w "$LOG_DIR" ]; then
            echo "ERREUR: Pas de droits d'écriture sur $LOG_DIR"
            critical_errors=$((critical_errors + 1))
        else
            echo "OK: Répertoire de logs accessible en écriture"
        fi
    fi
    
    # 5. Vérification des serveurs
    echo -e "\nVérification des serveurs..."
    
    local server_count=0
    local reachable_count=0
    local ssh_ok_count=0
    
    # Tableau pour stocker les résultats des tests
    declare -A server_status  # Tableau associatif pour le statut des serveurs
    
    # Créer un tableau temporaire pour stocker la liste des serveurs valides
    servers=()
    
    # Parcourir le fichier de configuration des serveurs
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Ignorer les lignes vides et les commentaires
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Extraire le nom du serveur (avant le premier ':' s'il existe)
        server=$(echo "$line" | cut -d':' -f1 | tr -d '[:space:]')
        
        # Ignorer les lignes vides
        if [[ -z "$server" ]]; then
            continue
        fi
        
        # Ajouter le serveur à la liste
        servers+=("$server")
    done < "$SERVER_LIST"
    
    # Afficher le nombre de serveurs trouvés
    server_count=${#servers[@]}
    echo "Nombre de serveurs à vérifier: $server_count"
    
    # Maintenant parcourir chaque serveur dans la liste pour les tester
    for server in "${servers[@]}"; do
        echo -e "\nTest du serveur: $server"
        
        # Vérification de la syntaxe du nom
        if ! validate_server_name "$server" "warn"; then
            echo "  AVERTISSEMENT: Nom de serveur potentiellement invalide: $server"
            warnings=$((warnings + 1))
            server_status["$server"]="warning"
        else
            echo "  OK: Syntaxe du nom de serveur valide"
            server_status["$server"]="ok"
        fi
        
        # Test de résolution DNS
        if ! host "$server" >/dev/null 2>&1; then
            echo "  ERREUR: Impossible de résoudre le nom d'hôte: $server"
            server_status["$server"]="error"
            continue
        else
            echo "  OK: Résolution DNS réussie"
        fi
        
        # Test de ping
        if ping -c 1 -W 2 "$server" >/dev/null 2>&1; then
            echo "  OK: Serveur accessible par ping"
            reachable_count=$((reachable_count + 1))
        else
            echo "  AVERTISSEMENT: Serveur non accessible par ping: $server"
            warnings=$((warnings + 1))
            server_status["$server"]="warning"
        fi
        
        # Test de connexion SSH basique
        if ssh -o BatchMode=yes -o ConnectTimeout=5 "$server" "echo test" >/dev/null 2>&1; then
            echo "  OK: Connexion SSH réussie"
            ssh_ok_count=$((ssh_ok_count + 1))
        else
            echo "  ERREUR: Impossible de se connecter en SSH à $server"
            critical_errors=$((critical_errors + 1))
            server_status["$server"]="error"
            continue
        fi
        
        # Vérification des partitions définies pour ce serveur
        server_line=$(grep "^${server}:" "$SERVER_LIST" || echo "")
        if [[ -n "$server_line" && "$server_line" =~ : ]]; then
            # Extraire les partitions (après le premier ':' et avant le deuxième ':' s'il existe)
            partitions=$(echo "$server_line" | cut -d':' -f2 | tr -d '[:space:]')
            
            if [[ ! -z "$partitions" ]]; then
                # Si les partitions contiennent des virgules, les traiter séparément
                if [[ "$partitions" =~ , ]]; then
                    IFS=',' read -ra PART_ARRAY <<< "$partitions"
                    for part in "${PART_ARRAY[@]}"; do
                        echo "  Test de la partition: $part"
                        
                        # Vérifier si la partition existe
                        if ssh -o BatchMode=yes -o ConnectTimeout=5 "$server" "df -h $part" >/dev/null 2>&1; then
                            echo "    OK: Partition $part accessible"
                        else
                            echo "    ERREUR: Partition $part introuvable ou inaccessible sur $server"
                            critical_errors=$((critical_errors + 1))
                            server_status["$server"]="error"
                        fi
                    done
                else
                    # Si c'est une seule partition
                    echo "  Test de la partition: $partitions"
                    
                    # Vérifier si la partition existe
                    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$server" "df -h $partitions" >/dev/null 2>&1; then
                        echo "    OK: Partition $partitions accessible"
                    else
                        echo "    ERREUR: Partition $partitions introuvable ou inaccessible sur $server"
                        critical_errors=$((critical_errors + 1))
                        server_status["$server"]="error"
                    fi
                fi
            fi
        fi
    done
    
    # Modifier la fonction generate_validation_report pour envoyer par email
    generate_validation_report server_status servers "$INFO_EMAIL"
    
    # Afficher le résumé des tests
    echo -e "\n==== RÉSUMÉ DES TESTS ===="
    echo "Serveurs testés: $server_count"
    echo "Serveurs accessibles par ping: $reachable_count"
    echo "Serveurs accessibles par SSH: $ssh_ok_count"
    echo "Erreurs critiques: $critical_errors"
    echo "Avertissements: $warnings"
    
    # Afficher le statut global
    if [ $critical_errors -gt 0 ]; then
        echo -e "\nSTATUT: ÉCHEC - Des erreurs critiques doivent être corrigées avant l'exécution du script"
        return 1
    elif [ $warnings -gt 0 ]; then
        echo -e "\nSTATUT: AVERTISSEMENT - Le script peut s'exécuter mais des problèmes ont été détectés"
        return 0
    else
        echo -e "\nSTATUT: SUCCÈS - Aucun problème détecté dans la configuration"
        return 0
    fi
}

# Fonction pour construire un nom d'affichage à partir d'un serveur et d'un utilisateur
build_display_name() {
    local server_name="$1"
    local ssh_user="$2"
    echo "${server_name}"
}

# Fonction pour extraire le nom d'utilisateur, le nom du serveur et ses attributs
extract_server_info() {
    local server_config="$1"
    local server_name=""
    local ssh_user=""
    
    # Vérifier si un nom d'utilisateur est spécifié (format user@server)
    if [[ "$server_config" =~ @ ]]; then
        ssh_user=$(echo "$server_config" | cut -d'@' -f1)
        server_name=$(echo "$server_config" | cut -d'@' -f2 | cut -d':' -f1)
    else
        server_name=$(echo "$server_config" | cut -d':' -f1)
        ssh_user="" # Utilisateur SSH par défaut (celui qui exécute le script)
    fi
    
    echo "$server_name $ssh_user"
}

# Fonction pour construire la commande SSH avec l'utilisateur approprié
build_ssh_command() {
    local server_name="$1"
    local ssh_user="$2"
    
    if [[ -n "$ssh_user" ]]; then
        echo "ssh ${ssh_user}@${server_name}"
    else
        echo "ssh ${server_name}"
    fi
}

# Fonction pour détecter le système d'exploitation d'un serveur
detect_os() {
    local server_name="$1"
    local ssh_user="$2"
    local ssh_cmd=""
    
    ssh_cmd=$(build_ssh_command "$server_name" "$ssh_user")
    
    # Exécuter uname pour déterminer l'OS
    local os_type=$($ssh_cmd "uname" 2>/dev/null)
    
    # Retourner "Darwin" pour macOS, sinon "Linux" ou autre
    echo "$os_type"
}

# Fonction pour obtenir les informations de disque adaptées à l'OS
get_disk_info() {
    local server_name="$1"
    local ssh_user="$2"
    local os_type="$3"
    local partition="$4"
    local ssh_cmd=""
    
    ssh_cmd=$(build_ssh_command "$server_name" "$ssh_user")
    
    if [[ "$os_type" == "Darwin" ]]; then
        # Format macOS - extraction adaptée
        $ssh_cmd "df -h '$partition' 2>/dev/null | awk 'NR>1 {print \$1\"|\"\$2\"|\"\$3\"|\"\$4\"|\"\$5\"|\"\$9}'" | head -1
    else
        # Format Linux standard
        $ssh_cmd "LC_ALL=C df -h '$partition' 2>/dev/null | grep -v '^Filesystem' | grep -v '^Sys.' | awk '{print \$1\"|\"\$2\"|\"\$3\"|\"\$4\"|\"\$5\"|\$6}'" | head -1
    fi
}

# Fonction pour générer un rapport HTML détaillé des résultats de validation et l'envoyer par email
generate_validation_report() {
    local -n status_ref=$1   # Référence au tableau associatif des statuts
    local -n servers_ref=$2  # Référence au tableau des serveurs
    local email_recipient=$3 # Destinataire de l'email
    
    # Variables pour le comptage des statistiques
    local total_servers=${#servers_ref[@]}
    local ping_ok_count=0
    local ssh_ok_count=0
    local error_count=0
    local warning_count=0
    
    local report_file="$TEMP_DIR/validation_report.html"
    
    # Créer le répertoire temporaire si nécessaire
    mkdir -p "$TEMP_DIR"
    
    # Créer l'en-tête du rapport HTML
    cat > "$report_file" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Rapport de validation de configuration - $DATE</title>
    <style>
        body { font-family: Arial, sans-serif; padding: 20px; }
        h1 { color: #333366; }
        h2 { color: #666699; margin-top: 20px; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .success { background-color: #e6ffe6; }
        .warning { background-color: #ffffcc; }
        .error { background-color: #ffcccc; }
        .summary { font-weight: bold; margin: 20px 0; padding: 10px; border-radius: 5px; }
    </style>
</head>
<body>
    <h1>Rapport de validation de configuration - $DATE</h1>
    <p>Généré par $SCRIPT_NAME version $VERSION sur le serveur $HOSTNAME avec la commande $FULL_COMMAND</p>
    <h2>Résultats des tests de serveurs</h2>
    <table>
        <tr>
            <th>Serveur</th>
            <th>Statut</th>
            <th>DNS</th>
            <th>Ping</th>
            <th>SSH</th>
            <th>Partitions</th>
        </tr>
EOF

    # Ajouter les détails des serveurs
    for server in "${servers_ref[@]}"; do
        # Déterminer le statut du serveur
        status_class="success"
        status_text="OK"
        if [[ "${status_ref[$server]}" == "warning" ]]; then
            status_class="warning"
            status_text="ATTENTION"
            warning_count=$((warning_count + 1))
        elif [[ "${status_ref[$server]}" == "error" ]]; then
            status_class="error"
            status_text="ERREUR"
            error_count=$((error_count + 1))
        fi
        
        # Tester pour DNS, ping, et SSH
        dns_status="Non testé"
        if host "$server" >/dev/null 2>&1; then
            dns_status="<span style='color:green'>✓</span>"
        else
            dns_status="<span style='color:red'>✗</span>"
        fi
        
        ping_status="Non testé"
        ping_ok=false
        if ping -c 1 -W 2 "$server" >/dev/null 2>&1; then
            ping_status="<span style='color:green'>✓</span>"
            ping_ok=true
            ping_ok_count=$((ping_ok_count + 1))
        else
            ping_status="<span style='color:red'>✗</span>"
        fi
        
        ssh_status="Non testé"
        if ssh -o BatchMode=yes -o ConnectTimeout=5 "$server" "echo test" >/dev/null 2>&1; then
            ssh_status="<span style='color:green'>✓</span>"
            ssh_ok_count=$((ssh_ok_count + 1))
        else
            ssh_status="<span style='color:red'>✗</span>"
        fi
        
        # Vérifier les partitions définies
        parts_status="/"
        server_line=$(grep "^${server}:" "$SERVER_LIST" || echo "")
        if [[ -n "$server_line" && "$server_line" =~ : ]]; then
            partitions=$(echo "$server_line" | cut -d':' -f2 | tr -d '[:space:]')
            
            if [[ ! -z "$partitions" ]]; then
                parts_status=""
                if [[ "$partitions" =~ , ]]; then
                    IFS=',' read -ra PART_ARRAY <<< "$partitions"
                    for part in "${PART_ARRAY[@]}"; do
                        if ssh -o BatchMode=yes -o ConnectTimeout=5 "$server" "df -h $part" >/dev/null 2>&1; then
                            parts_status+="$part <span style='color:green'>✓</span>, "
                        else
                            parts_status+="$part <span style='color:red'>✗</span>, "
                        fi
                    done
                    # Supprimer la virgule finale
                    parts_status=${parts_status%, }
                else
                    # Si c'est une seule partition
                    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$server" "df -h $partitions" >/dev/null 2>&1; then
                        parts_status="$partitions <span style='color:green'>✓</span>"
                    else
                        parts_status="$partitions <span style='color:red'>✗</span>"
                    fi
                fi
            fi
        fi
        
        # Ajouter la ligne du serveur au tableau
        cat >> "$report_file" <<EOF
        <tr class="$status_class">
            <td>$server</td>
            <td>$status_text</td>
            <td>$dns_status</td>
            <td>$ping_status</td>
            <td>$ssh_status</td>
            <td>$parts_status</td>
        </tr>
EOF
    done
    
    # Ajouter le résumé et fermer le rapport HTML
    cat >> "$report_file" <<EOF
    </table>
    
    <h2>Résumé</h2>
    <div class="summary">
        <p>Serveurs testés: $total_servers</p>
        <p>Serveurs accessibles par ping: $ping_ok_count</p>
        <p>Serveurs accessibles par SSH: $ssh_ok_count</p>
        <p>Erreurs critiques: $error_count</p>
        <p>Avertissements: $warning_count</p>
    </div>
    
    <h2>Configuration globale</h2>
    <table>
        <tr>
            <th>Paramètre</th>
            <th>Valeur</th>
            <th>Statut</th>
        </tr>
        <tr>
            <td>Fichier de configuration</td>
            <td>$CONFIG_FILE</td>
            <td>$([ -f "$CONFIG_FILE" ] && echo "<span style='color:green'>✓</span>" || echo "<span style='color:red'>✗</span>")</td>
        </tr>
        <tr>
            <td>Fichier de liste de serveurs</td>
            <td>$SERVER_LIST</td>
            <td>$([ -f "$SERVER_LIST" ] && echo "<span style='color:green'>✓</span>" || echo "<span style='color:red'>✗</span>")</td>
        </tr>
        <tr>
            <td>Répertoire de logs</td>
            <td>$LOG_DIR</td>
            <td>$([ -d "$LOG_DIR" ] && [ -w "$LOG_DIR" ] && echo "<span style='color:green'>✓</span>" || echo "<span style='color:red'>✗</span>")</td>
        </tr>
        <tr>
            <td>Seuil d'avertissement</td>
            <td>$WARNING_THRESHOLD%</td>
            <td>$([ "$WARNING_THRESHOLD" -lt "$CRITICAL_THRESHOLD" ] && echo "<span style='color:green'>✓</span>" || echo "<span style='color:red'>✗</span>")</td>
        </tr>
        <tr>
            <td>Seuil critique</td>
            <td>$CRITICAL_THRESHOLD%</td>
            <td>$([ "$WARNING_THRESHOLD" -lt "$CRITICAL_THRESHOLD" ] && echo "<span style='color:green'>✓</span>" || echo "<span style='color:red'>✗</span>")</td>
        </tr>
    </table>
    
    <hr>
    <p><em>Ce rapport a été généré automatiquement en mode validation.</em></p>
</body>
</html>
EOF

    echo "Rapport de validation détaillé généré: $report_file"
    
    # Envoyer le rapport par email
    if [[ -n "$email_recipient" ]]; then
        local subject="Rapport de validation de configuration - $HOSTNAME - $DATE"
        if $TEST_MODE; then
            subject="[TEST] $subject"
        fi
        
        echo "Envoi du rapport par email à $email_recipient..."
        cat "$report_file" | mail -a "Content-Type: text/html; charset=UTF-8" -s "$subject" -r "$EMAIL_SENDER" "$email_recipient"
        echo "Rapport envoyé par email."
    else
        echo "Aucun destinataire spécifié, le rapport n'a pas été envoyé par email."
    fi
}

# Fonction pour valider le format d'un nom de serveur
validate_server_name() {
    local server_config="$1"
    local validation_mode="$2"  # "strict" ou "warn"
    
    # Extraire le nom du serveur (après @ s'il existe)
    local server=""
    if [[ "$server_config" =~ @ ]]; then
        server=$(echo "$server_config" | cut -d'@' -f2)
    else
        server="$server_config"
    fi
    
    # Vérification de base (pas vide, pas de caractères spéciaux interdits)
    if [[ -z "$server" || ! "$server" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        if [ "$validation_mode" = "strict" ]; then
            log "ERREUR: Nom de serveur invalide ignoré: '$server' (contient des caractères non autorisés)"
            return 1
        else
            log "AVERTISSEMENT: Nom de serveur suspect: '$server' (contient des caractères non autorisés)"
        fi
    fi
    
    # Vérification de la syntaxe DNS correcte (nom + domaine)
    if [[ ! "$server" =~ ^[a-zA-Z0-9._-]+\.[a-zA-Z0-9._-]+$ ]]; then
        if [ "$validation_mode" = "strict" ]; then
            log "ERREUR: Nom de serveur invalide ignoré: '$server' (format de domaine incorrect)"
            return 1
        else
            log "AVERTISSEMENT: Nom de serveur suspect: '$server' (format de domaine incorrect)"
        fi
    fi
    
    # Vérification de la longueur
    if [ ${#server} -gt 253 ]; then
        if [ "$validation_mode" = "strict" ]; then
            log "ERREUR: Nom de serveur invalide ignoré: '$server' (nom trop long)"
            return 1
        else
            log "AVERTISSEMENT: Nom de serveur suspect: '$server' (nom trop long)"
        fi
    fi
    
    # Option supplémentaire: vérification DNS (résolution du nom)
    if [ "$validation_mode" = "strict" ]; then
        if ! host "$server" > /dev/null 2>&1; then
            log "ERREUR: Nom de serveur non résolu: '$server' (vérifiez DNS)"
            return 1
        fi
    fi
    
    return 0  # Validation réussie
}

# Fonction pour afficher l'utilisation du disque triée
show_sorted_usage() {
    local sort_order=$1  # "asc" pour croissant, "desc" pour décroissant
    local output_file="$TEMP_DIR/sorted_usage.txt"
    local html_file="$TEMP_DIR/sorted_usage.html"
    
    log "Démarrage de la fonction show_sorted_usage avec ordre: $sort_order"
    
    # Entête du fichier HTML
    cat > "$html_file" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Utilisation des disques triee - $DATE</title>
    $(create_css)
    <style>
        table {
            width: 100%;
            border-collapse: collapse;
        }
        th, td {
            padding: 8px;
            text-align: left;
            border: 1px solid #ddd;
        }
        th {
            background-color: #f2f2f2;
        }
        .normal {
            background-color: #e6ffe6;
        }
        .warning {
            background-color: #ffffcc;
        }
        .critical {
            background-color: #ffcccc;
        }
    </style>
</head>
<body>
    <h1>Utilisation des disques triee - $DATE</h1>
    <p>Genere par $SCRIPT_NAME version $VERSION sur le serveur $HOSTNAME avec la commande $FULL_COMMAND</p>
EOF
    
    # Ajouter une note en mode test
    if $TEST_MODE; then
        echo "<p><strong>Mode TEST active</strong> - Fichier de serveurs: $SERVER_LIST</p>" >> "$html_file"
    fi
    
    echo "<table>" >> "$html_file"
    echo "<tr><th>Serveur</th><th>Point de montage</th><th>Partition</th><th>Taille</th><th>Utilise</th><th>Disponible</th><th>Utilisation</th></tr>" >> "$html_file"
    
    # Créer un fichier temporaire pour le tri
    > "$output_file"
    servers=()
    invalid_servers=()

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Ignorer les lignes vides et les commentaires
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
    
        # Extraire le nom du serveur (avant le premier ':' s'il existe)
        server=$(echo "$line" | cut -d':' -f1 | tr -d '[:space:]')
    
        # Valider le nom du serveur
        if validate_server_name "$server" "$SERVER_VALIDATION_MODE"; then
            servers+=("$line")
            log "Serveur valide ajouté: $server"
        else
            invalid_servers+=("$server")
            if [ "$SERVER_VALIDATION_MODE" = "strict" ]; then
                log "Serveur ignoré (mode strict): $server"
            else
                servers+=("$line")
                log "Serveur ajouté avec avertissement: $server"
            fi
        fi
    done < "$SERVER_LIST"

    # Ajouter au rapport un avertissement concernant les serveurs invalides
    if [ ${#invalid_servers[@]} -gt 0 ]; then
        echo "<div class=\"warning\" style=\"padding: 10px; margin: 10px 0; border-radius: 5px;\">" >> "$TEMP_DIR/report.html"
        echo "<h3>Avertissement: Serveurs potentiellement mal configurés</h3>" >> "$TEMP_DIR/report.html"
        echo "<p>Les serveurs suivants ont des noms qui ne respectent pas les conventions de nommage ou n'ont pas pu être résolus:</p>" >> "$TEMP_DIR/report.html"
        echo "<ul>" >> "$TEMP_DIR/report.html"
        for invalid_server in "${invalid_servers[@]}"; do
            echo "<li>$invalid_server</li>" >> "$TEMP_DIR/report.html"
        done
        echo "</ul>" >> "$TEMP_DIR/report.html"
        echo "<p>Veuillez vérifier la configuration de ces serveurs.</p>" >> "$TEMP_DIR/report.html"
        echo "</div>" >> "$TEMP_DIR/report.html"
    fi 
    log "Nombre de serveurs à traiter pour le tri: ${#servers[@]}"
    
    # Pour chaque serveur dans la liste
    for server_line in "${servers[@]}"; do
        # Ajouter un saut de ligne avant le traitement de chaque serveur
        log "" # Ajoute une ligne vide dans les logs

        # Extraire le nom du serveur et l'utilisateur SSH
        server_info=$(extract_server_info "$server_line")
        server_name=$(echo "$server_info" | cut -d' ' -f1)
        ssh_user=$(echo "$server_info" | cut -d' ' -f2)
        
        # Utiliser uniquement le nom du serveur pour l'affichage
        display_name="$server_name"
        
        log "Collecte des données pour $display_name"
        
        # Vérifier si le serveur est accessible (utiliser seulement le nom de serveur pour le ping)
        if ! check_server_reachable "$server_name"; then
            log "Le serveur $display_name n'est pas accessible, ignoré"
            continue
        fi
        
        # Déterminer les partitions à vérifier et les seuils - CORRECTION DU BUG
        local partitions=""
        local server_warning=$WARNING_THRESHOLD
        local server_critical=$CRITICAL_THRESHOLD
        
        # Chercher la configuration du serveur
        local server_config_line=""
        if [[ -n "$ssh_user" ]]; then
            server_config_line=$(grep "^${ssh_user}@${server_name}:" "$SERVER_LIST" || echo "")
        else
            server_config_line=$(grep "^${server_name}:" "$SERVER_LIST" || echo "")
        fi
        
        if [[ -n "$server_config_line" ]]; then
            # Extraire les partitions (champ 2)
            local field2=$(echo "$server_config_line" | cut -d':' -f2)
            if [ ! -z "$field2" ]; then
                partitions="$field2"
            else
                partitions="/"
            fi
            
            # Extraire les seuils personnalisés
            local custom_warning=$(echo "$server_config_line" | cut -d':' -f3)
            local custom_critical=$(echo "$server_config_line" | cut -d':' -f4)
            
            if [[ ! -z "$custom_warning" && "$custom_warning" =~ ^[0-9]+$ ]]; then
                server_warning=$custom_warning
            fi
            
            if [[ ! -z "$custom_critical" && "$custom_critical" =~ ^[0-9]+$ ]]; then
                server_critical=$custom_critical
            fi
        else
            partitions="/"
        fi
        
        log "Partitions pour $display_name: $partitions, Seuils: $server_warning% / $server_critical%"
        
        # Construire la commande SSH avec l'utilisateur approprié
        local ssh_cmd=""
        if [[ -n "$ssh_user" ]]; then
            ssh_cmd="ssh ${ssh_user}@${server_name}"
        else
            ssh_cmd="ssh ${server_name}"
        fi
        
        # Détecter le système d'exploitation
        local os_type=$($ssh_cmd "uname" 2>/dev/null)
        log "Système d'exploitation détecté pour $display_name: $os_type"
        
        # Traiter les partitions séparées par des virgules
        IFS=',' read -ra PARTITION_ARRAY <<< "$partitions"
        for partition in "${PARTITION_ARRAY[@]}"; do
            # Supprimer les espaces éventuels
            partition=$(echo "$partition" | tr -d '[:space:]')
            
            # Ignorer les partitions vides
            if [[ -z "$partition" ]]; then
                continue
            fi
            
            log "Vérification de la partition $partition sur $display_name"
            
            local df_output=""
            local filesystem=""
            local size=""
            local used=""
            local avail=""
            local usage_str=""
            local usage_percent=""
            local mount_point=""
            
            # Adapter la commande en fonction du système d'exploitation
            if [[ "$os_type" == "Darwin" ]]; then
                # Version macOS de la commande df
                df_output=$($ssh_cmd "df -h '$partition'" 2>/dev/null | grep -v "Filesystem" | head -1)
                
                if [ ! -z "$df_output" ]; then
                    # Extraction adaptée pour macOS
                    filesystem=$(echo "$df_output" | awk '{print $1}')
                    size=$(echo "$df_output" | awk '{print $2}')
                    used=$(echo "$df_output" | awk '{print $3}')
                    avail=$(echo "$df_output" | awk '{print $4}')
                    usage_str=$(echo "$df_output" | awk '{print $5}')
                    
                    # Sur macOS, le point de montage est en dernière position (peut être après colonne 9)
                    mount_point=$(echo "$df_output" | awk '{for(i=9;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')
                    
                    # Si le point de montage est vide, essayer d'autres méthodes
                    if [ -z "$mount_point" ]; then
                        mount_point=$(echo "$df_output" | awk '{print $9}')
                    fi
                    
                    # Si toujours vide, utiliser la partition spécifiée
                    if [ -z "$mount_point" ]; then
                        mount_point="$partition"
                    fi
                else
                    log "ERREUR: Aucune donnée reçue pour $display_name:$partition"
                    continue
                fi
            else
                # Version Linux standard avec LC_ALL=C pour standardiser le format de sortie
                df_output=$($ssh_cmd "LC_ALL=C df -h '$partition'" 2>/dev/null | grep -v '^Filesystem' | grep -v '^Sys.' | head -1)
                
                if [ ! -z "$df_output" ]; then
                    # Extraire proprement les informations avec awk
                    filesystem=$(echo "$df_output" | awk '{print $1}')
                    size=$(echo "$df_output" | awk '{print $2}')
                    used=$(echo "$df_output" | awk '{print $3}')
                    avail=$(echo "$df_output" | awk '{print $4}')
                    usage_str=$(echo "$df_output" | awk '{print $5}')
                    
                    # Récupérer le point de montage (qui peut contenir des espaces)
                    mount_point=$(echo "$df_output" | awk '{for(i=6;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')
                    
                    # Si le point de montage est vide, utiliser la partition
                    if [ -z "$mount_point" ]; then
                        mount_point="$partition"
                    fi
                else
                    log "ERREUR: Aucune donnée reçue pour $display_name:$partition"
                    continue
                fi
            fi
            
            log "Données reçues: $df_output"
            
            # Enlever le % du pourcentage d'utilisation
            usage_percent=${usage_str%\%}
            
            # Vérifier que les données sont valides
            if [[ -n "$filesystem" && -n "$size" && -n "$used" && -n "$avail" && "$usage_percent" =~ ^[0-9]+$ ]]; then
                # Déterminer la classe CSS
                status_class="normal"
                if [ "$usage_percent" -ge "$server_critical" ]; then
                    status_class="critical"
                elif [ "$usage_percent" -ge "$server_warning" ]; then
                    status_class="warning"
                fi
                
                # Ajouter au fichier de tri avec le nom d'affichage corrigé
                echo "$usage_percent|$display_name|$mount_point|$filesystem|$size|$used|$avail|$status_class" >> "$output_file"
                
                log "Ajouté pour tri: $display_name:$mount_point = $usage_percent% ($status_class)"
            else
                log "Données invalides pour $display_name:$partition - $df_output"
            fi
        done
    done
    
    # Vérifier si des données ont été collectées
    if [ ! -s "$output_file" ]; then
        log "Aucune donnée collectée pour le tri"
        echo "<tr><td colspan=\"7\">Aucune donnée d'utilisation disponible</td></tr>" >> "$html_file"
    else
        # Trier les données
        if [ "$sort_order" = "asc" ]; then
            sort -t'|' -k1 -n "$output_file" > "$output_file.sorted"
            log "Tri effectué par ordre croissant"
        else
            sort -t'|' -k1 -nr "$output_file" > "$output_file.sorted"
            log "Tri effectué par ordre décroissant"
        fi
        
        # Ajouter les données triées au rapport HTML
        while IFS='|' read -r percent server mount_point filesystem size used avail status_class; do
            echo "<tr class=\"$status_class\">" >> "$html_file"
            echo "<td>$server</td>" >> "$html_file"
            echo "<td>$mount_point</td>" >> "$html_file"
            echo "<td>$filesystem</td>" >> "$html_file"
            echo "<td>$size</td>" >> "$html_file"
            echo "<td>$used</td>" >> "$html_file"
            echo "<td>$avail</td>" >> "$html_file"
            echo "<td>$percent%</td>" >> "$html_file"
            echo "</tr>" >> "$html_file"
        done < "$output_file.sorted"
    fi
    
    # Terminer le rapport HTML
    echo "</table>" >> "$html_file"
    echo "</body></html>" >> "$html_file"
    
    # Définir le sujet du mail
    local subject="Utilisation des disques triee"
    if [ "$sort_order" = "asc" ]; then
        subject="$subject (croissant) - $DATE"
    else
        subject="$subject (decroissant) - $DATE"
    fi
    
    if $TEST_MODE; then
        subject="[TEST] $subject"
    fi
    
    # Envoyer l'email
    log "Envoi de l'email contenant l'utilisation triee"
    cat "$html_file" | mail -a "Content-Type: text/html; charset=UTF-8" -s "$subject" -r "$EMAIL_SENDER" "$INFO_EMAIL"
    
    # Sauvegarder le rapport
    local suffix=""
    if [ "$sort_order" = "asc" ]; then
        suffix="usage-asc"
    else
        suffix="usage-desc"
    fi
    
    log "Sauvegarde du rapport dans $LOG_DIR/report-$DATE-$suffix.html"
    cp "$html_file" "$LOG_DIR/report-$DATE-$suffix.html"
    
    log "Fonction show_sorted_usage terminée"
}

# Fonction pour faire la rotation des fichiers de logs
rotate_logs() {
    local log_dir="$1"
    local max_logs="$2"      # Nombre maximal de fichiers de logs à conserver
    local compress="$3"      # true/false pour activer la compression
    
    log "Démarrage de la rotation des logs dans $log_dir"
    
    # Vérifier que le répertoire de logs existe
    if [ ! -d "$log_dir" ]; then
        log "ERREUR: Le répertoire de logs $log_dir n'existe pas"
        return 1
    fi
    
    # Compresser les anciens logs qui ne sont pas encore compressés
    if $compress; then
        find "$log_dir" -type f -name "*.log" -not -name "*.gz" -mtime +1 | while read -r file; do
            if [ -f "$file" ]; then
                log "Compression du fichier $file"
                gzip -9f "$file"
            fi
        done
    fi
    
    # Supprimer les logs les plus anciens si on dépasse max_logs
    if [ $max_logs -gt 0 ]; then
        # Compter les fichiers de logs (normaux et compressés)
        local log_count=$(find "$log_dir" -type f \( -name "*.log" -o -name "*.log.gz" \) | wc -l)
        
        if [ $log_count -gt $max_logs ]; then
            local files_to_delete=$((log_count - max_logs))
            log "Suppression des $files_to_delete fichiers de logs les plus anciens"
            
            # Lister les fichiers par date (du plus ancien au plus récent) et supprimer les plus anciens
            find "$log_dir" -type f \( -name "*.log" -o -name "*.log.gz" \) -printf "%T@ %p\n" | \
                sort -n | head -n $files_to_delete | cut -d' ' -f2- | while read -r file; do
                log "Suppression du fichier de log ancien: $file"
                rm -f "$file"
            done
        else
            log "Nombre de fichiers de logs ($log_count) inférieur à la limite ($max_logs), pas de suppression"
        fi
    fi
    
    # Rotation des fichiers spécifiques
    rotate_specific_file "$BIG_DIRS_FILE" $compress
    rotate_specific_file "$BIG_FILES_FILE" $compress
    
    log "Rotation des logs terminée"
}

# Fonction auxiliaire pour faire la rotation d'un fichier spécifique
rotate_specific_file() {
    local file="$1"
    local compress="$2"
    
    if [ -f "$file" ]; then
        local backup_file="${file}.$(date +%Y%m%d)"
        
        # Vérifier si le fichier de sauvegarde existe déjà
        if [ -f "$backup_file" ]; then
            log "Le fichier $backup_file existe déjà, remplacement"
            rm -f "$backup_file"  # Supprimer l'ancien fichier
        fi
        
        # Créer une copie datée du fichier
        log "Création d'une copie de $file vers $backup_file"
        cp "$file" "$backup_file"
        
        # Compresser si demandé
        if $compress; then
            # Vérifier si le fichier compressé existe déjà
            if [ -f "$backup_file.gz" ]; then
                log "Le fichier $backup_file.gz existe déjà, remplacement"
                rm -f "$backup_file.gz"  # Supprimer l'ancien fichier compressé
            fi
            
            log "Compression de $backup_file"
            gzip -9f "$backup_file"  # Ajout de l'option -f pour forcer l'écrasement
        fi
    else
        log "Le fichier $file n'existe pas, rotation ignorée"
    fi
}

# Fonction pour vérifier si un serveur est exclu des calculs intensifs
is_server_excluded() {
    local server=$1
    
    # Si la liste d'exclusion est vide, aucun serveur n'est exclu
    if [ -z "$EXCLUDED_SERVERS" ]; then
        if $VERBOSE; then
            log "Aucun serveur exclu configuré"
        fi
        return 1 # false, le serveur n'est pas exclu
    fi
    
    if $VERBOSE; then
        log "Vérification si '$server' est dans la liste d'exclusion: '$EXCLUDED_SERVERS'"
    fi
    
    # Convertir la liste d'exclusion en tableau (avec traitement des espaces)
    IFS=',' read -ra excluded_array <<< "$EXCLUDED_SERVERS"
    
    # Vérifier si le serveur est dans la liste
    for excluded in "${excluded_array[@]}"; do
        # Supprimer les espaces éventuels
        excluded=$(echo "$excluded" | tr -d '[:space:]')
        if [ "$server" = "$excluded" ]; then
            if $VERBOSE; then
                log "Le serveur '$server' est exclu des calculs intensifs"
            fi
            return 0 # true, le serveur est exclu
        fi
    done
    
    if $VERBOSE; then
        log "Le serveur '$server' n'est pas exclu des calculs intensifs"
    fi
    return 1 # false, le serveur n'est pas exclu
}

# Fonction pour vérifier s'il y a des alertes
check_for_alerts() {
    local server_config="$1"
    
    # Extraire le nom du serveur et l'utilisateur SSH
    local server_info=$(extract_server_info "$server_config")
    local server_name=$(echo "$server_info" | cut -d' ' -f1)
    local ssh_user=$(echo "$server_info" | cut -d' ' -f2)
    
    # Construire la commande SSH
    local ssh_cmd=$(build_ssh_command "$server_name" "$ssh_user")
    
    # Détecter le système d'exploitation
    local os_type=$(detect_os "$server_name" "$ssh_user")
    
    # Adapter la commande en fonction de l'OS
    local ssh_output=""
    if [[ "$os_type" == "Darwin" ]]; then
        # Commande adaptée pour macOS
        ssh_output=$($ssh_cmd "df -h / | awk 'NR>1{print \$5}'" 2>&1)
    else
        # Commande standard pour Linux
        ssh_output=$($ssh_cmd "df -h / | grep -v Filesystem" 2>&1)
    fi
    
    if [ $? -eq 0 ]; then
        local usage_str=""
        local usage_percent=""
        
        if [[ "$os_type" == "Darwin" ]]; then
            # Extraction directe pour macOS
            usage_str="$ssh_output"
            usage_percent=$(echo "$usage_str" | sed 's/%//')
        else
            # Extraction standard pour Linux
            usage_str=$(echo "$ssh_output" | awk '{print $5}')
            usage_percent=$(echo "$usage_str" | grep -o '[0-9]*')
        fi

        # Récupérer les seuils personnalisés
        local server_warning_threshold=$WARNING_THRESHOLD
        local server_critical_threshold=$CRITICAL_THRESHOLD
        
        # Chercher la configuration du serveur avec l'utilisateur si spécifié
        local server_line=""
        if [[ -n "$ssh_user" ]]; then
            server_line=$(grep "^${ssh_user}@${server_name}:" "$SERVER_LIST")
        else
            server_line=$(grep "^${server_name}:" "$SERVER_LIST")
        fi
        
        if [[ -n "$server_line" ]]; then
            local field3=$(echo "$server_line" | cut -d':' -f3)
            local field4=$(echo "$server_line" | cut -d':' -f4)
            
            if [[ ! -z "$field3" && "$field3" =~ ^[0-9]+$ ]]; then
                server_warning_threshold="$field3"
            fi
            
            if [[ ! -z "$field4" && "$field4" =~ ^[0-9]+$ ]]; then
                server_critical_threshold="$field4"
            fi
        fi
        
        # Vérifier les seuils
        if [[ "$usage_percent" =~ ^[0-9]+$ ]]; then
            if [ "$usage_percent" -ge "$server_critical_threshold" ]; then
                has_critical=true
                log "[CRITIQUE] Détecté sur $server_name: $usage_percent% (seuil: $server_critical_threshold%)"
            elif [ "$usage_percent" -ge "$server_warning_threshold" ]; then
                has_warning=true
                log "[WARNING] Détecté sur $server_name: $usage_percent% (seuil: $server_warning_threshold%)"
            fi
        else
            log "AVERTISSEMENT: Impossible d'extraire le pourcentage d'utilisation pour $server_name (valeur: $usage_str)"
        fi
    else
        log "ERREUR: Impossible d'obtenir l'utilisation du disque pour $server_name, sortie SSH: $ssh_output"
    fi
}

# Fonction pour lister les serveurs
list_servers() {
    local current_server_list="$SERVER_LIST"
    
    if [ ! -f "$current_server_list" ]; then
        echo "Erreur: Fichier de liste de serveurs $current_server_list introuvable."
        exit 1
    fi

    if $TEST_MODE; then
        echo "Mode TEST: Liste des serveurs configurés dans $current_server_list:"
    else
        echo "Liste des serveurs configurés:"
    fi
    echo "-----------------------------"

    while read -r line; do
        # Ignorer les lignes vides et les commentaires
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        # Vérifier si la ligne contient un nom de serveur valide
        if [[ "$line" =~ ^[[:alnum:]._-]+ ]]; then
            # Extraire le nom du serveur
            server=$(echo "$line" | cut -d':' -f1 | tr -d '[:space:]')
            
            # Extraire le reste de la configuration
            config=$(echo "$line" | cut -d':' -f2-)
            
            # Partitions
            partitions=$(echo "$config" | cut -d':' -f1)
            if [[ -z "$partitions" || "$partitions" =~ ^[[:space:]]*$ ]]; then
                partitions="/"
            fi
            
            # Seuils 
            warning_threshold=$WARNING_THRESHOLD
            critical_threshold=$CRITICAL_THRESHOLD
            
            if [[ "$config" =~ : ]]; then
                # Extraire les seuils personnalisés
                thresholds=$(echo "$config" | cut -d':' -f2-)
                
                custom_warning=$(echo "$thresholds" | cut -d':' -f1)
                if [[ ! -z "$custom_warning" && "$custom_warning" =~ ^[0-9]+$ ]]; then
                    warning_threshold=$custom_warning
                fi
                
                custom_critical=$(echo "$thresholds" | cut -d':' -f2)
                if [[ ! -z "$custom_critical" && "$custom_critical" =~ ^[0-9]+$ ]]; then
                    critical_threshold=$custom_critical
                fi
            fi
            
            echo "Serveur: $server   FS: $partitions   Seuils: $warning_threshold% / $critical_threshold%"
        fi
    done <"$current_server_list"

    exit 0
}
    
# Fonction pour générer et envoyer les emails contenant les listes consolidées
send_consolidated_reports() {
    # Créer un répertoire temporaire pour le traitement si nécessaire
    mkdir -p "$TEMP_DIR"

    # Créer un tableau temporaire pour stocker les noms des serveurs du fichier actuel
    declare -a current_servers

    # Charger les serveurs dans un tableau pour pouvoir vérifier si un serveur fait partie de la liste actuelle
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Ignorer les lignes vides et les commentaires
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        # Extraire le nom du serveur (avant le premier ':' s'il existe)
        server=$(echo "$line" | cut -d':' -f1 | tr -d '[:space:]')

        # Ajouter uniquement les noms de serveur non vides
        if [[ ! -z "$server" ]]; then
            current_servers+=("$server")
            if $VERBOSE; then
                log "Serveur ajoute a la liste des serveurs actuels: $server"
            fi
        fi
    done <"$SERVER_LIST"

    # Fonction pour vérifier si un serveur est dans la liste actuelle
    is_current_server() {
        local srv="$1"
        for cs in "${current_servers[@]}"; do
            if [[ "$srv" == "$cs" ]]; then
                return 0
            fi
        done
        return 1
    }

    if $MAIL_BIG_FILES; then
        log "Preparation de l'email consolide des plus gros fichiers"
        # Créer un fichier temporaire pour le rapport
        local temp_file_report="$TEMP_DIR/consolidated_files.html"

        # Générer l'en-tête HTML
        cat >"$temp_file_report" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Liste consolidee des plus gros fichiers - $DATE</title>
    $(create_css)
    <style>
        table.consolidated {
            width: 100%;
            border-collapse: collapse;
        }
        table.consolidated th {
            background-color: #e0e0e0;
            padding: 8px;
            text-align: left;
            border: 1px solid #ccc;
        }
        table.consolidated td {
            padding: 8px;
            border: 1px solid #ccc;
        }
        .file-size {
            font-weight: bold;
            text-align: right;
            white-space: nowrap;
        }
        .file-path {
            font-family: monospace;
        }
        .server-name {
            font-weight: bold;
            color: #333366;
        }
        tr:nth-child(even) {
            background-color: #f9f9f9;
        }
    </style>
</head>
<body>
    <h1>Liste consolidee des plus gros fichiers - $DATE</h1>
    <p>Genere par $SCRIPT_NAME version $VERSION sur le serveur $HOSTNAME avec la commande $FULL_COMMAND</p>
EOF

        # Ajouter une note en mode test
        if $TEST_MODE; then
            echo "<p><strong>Mode TEST active</strong> - Fichier de serveurs: $SERVER_LIST</p>" >>"$temp_file_report"
        fi

        # Si la liste des serveurs exclus n'est pas vide, l'ajouter au rapport
        if [ ! -z "$EXCLUDED_SERVERS" ]; then
            echo "<p><strong>Note:</strong> Les serveurs suivants sont exclus des calculs intensifs: <em>$EXCLUDED_SERVERS</em></p>" >>"$temp_file_report"
        fi

        echo "<table class=\"consolidated\">" >>"$temp_file_report"
        echo "<tr>" >>"$temp_file_report"
        echo "    <th>Taille</th>" >>"$temp_file_report"
        echo "    <th>Fichier</th>" >>"$temp_file_report"
        echo "    <th>Serveur</th>" >>"$temp_file_report"
        echo "</tr>" >>"$temp_file_report"

        # Créer un fichier temporaire pour le traitement
        local temp_processing="$TEMP_DIR/files_processing.tmp"
        >"$temp_processing"

        # Créer un fichier pour stocker les chemins uniques afin d'éviter les doublons
        local unique_paths_file="$TEMP_DIR/unique_paths.tmp"
        >"$unique_paths_file"

        # Vérifier si le fichier existe et n'est pas vide
        if [ -f "$BIG_FILES_FILE" ] && [ -s "$BIG_FILES_FILE" ]; then
            log "Extraction des donnees des plus gros fichiers depuis $BIG_FILES_FILE..."

            # Déboguer le contenu du fichier
            if $VERBOSE; then
                log "Contenu du fichier de grands fichiers:"
                head -n 20 "$BIG_FILES_FILE" | while IFS= read -r line; do
                    log "  $line"
                done

                log "Liste des serveurs actuels:"
                for srv in "${current_servers[@]}"; do
                    log "  $srv"
                done
            fi

            # Méthode alternative : extraire directement par bloc de serveur
            for current_server in "${current_servers[@]}"; do
                # Vérifier si le serveur est exclu des calculs intensifs
                if is_server_excluded "$current_server"; then
                    if $VERBOSE; then
                        log "Le serveur $current_server est exclu des calculs intensifs, données ignorées"
                    fi
                    continue  # Passer au serveur suivant
                fi

                if $VERBOSE; then
                    log "Recherche des donnees pour le serveur $current_server"
                fi

                # Utiliser awk pour extraire le bloc de données du serveur actuel
                awk -v server="$current_server" '
                BEGIN { found=0; }
                $0 ~ "^Serveur: " server ", " { found=1; next; }
                found && $0 ~ "^-{5,}$" { found=0; next; }
                found && $0 ~ "^Serveur:" { found=0; next; }
                found && $1 ~ /^[0-9,.]+[KMGTP]?$/ { print $0; }
            ' "$BIG_FILES_FILE" >"$TEMP_DIR/server_files_${current_server}.tmp"

                # Vérifier si des données ont été extraites
                if [ -s "$TEMP_DIR/server_files_${current_server}.tmp" ]; then
                    if $VERBOSE; then
                        log "Donnees trouvees pour $current_server:"
                        cat "$TEMP_DIR/server_files_${current_server}.tmp" | while IFS= read -r line; do
                            log "  $line"
                        done
                    fi

                    # Traiter chaque ligne de données et éliminer les doublons
                    while IFS= read -r line; do
                        # Extraire la taille et le chemin
                        local size=$(echo "$line" | awk '{print $1}')
                        local path=$(echo "$line" | cut -d' ' -f2-)

                        # Nettoyer le chemin pour enlever la taille au début (si elle existe)
                        path=$(echo "$path" | sed 's/^[0-9,.]*[KMGTP]\?\s*//')

                        # Créer une clé unique pour ce fichier (serveur:chemin)
                        local unique_key="${current_server}:${path}"

                        # Vérifier si nous avons déjà traité ce fichier pour ce serveur
                        if ! grep -q "^$unique_key$" "$unique_paths_file"; then
                            # Ajouter la clé unique au fichier pour éviter les doublons
                            echo "$unique_key" >>"$unique_paths_file"

                            # Normaliser les tailles pour le tri
                            local sort_size=$(echo "$size" | tr ',' '.')
                            case "$sort_size" in
                            *K) sort_size=$(echo "${sort_size%K} * 1" | bc) ;;
                            *M) sort_size=$(echo "${sort_size%M} * 1024" | bc) ;;
                            *G) sort_size=$(echo "${sort_size%G} * 1024 * 1024" | bc) ;;
                            *T) sort_size=$(echo "${sort_size%T} * 1024 * 1024 * 1024" | bc) ;;
                            *P) sort_size=$(echo "${sort_size%P} * 1024 * 1024 * 1024 * 1024" | bc) ;;
                            esac

                            # Ajouter au fichier de traitement
                            echo "$sort_size|$size|$path|$current_server" >>"$temp_processing"

                            if $VERBOSE; then
                                log "  Ajoute: $size $path (Serveur: $current_server)"
                            fi
                        else
                            if $VERBOSE; then
                                log "  Ignore doublon: $size $path (Serveur: $current_server)"
                            fi
                        fi
                    done <"$TEMP_DIR/server_files_${current_server}.tmp"
                else
                    log "Aucune donnee trouvee pour le serveur $current_server"
                fi
            done

            # Vérifier si des données ont été extraites
            if [ -s "$temp_processing" ]; then
                log "Tri des donnees extraites..."
                # Trier par taille et prendre les 20 premiers
                sort -t'|' -k1 -nr "$temp_processing" | head -20 | while IFS='|' read -r sort_size size path server; do
                    echo "<tr>" >>"$temp_file_report"
                    echo "  <td class=\"file-size\">$size</td>" >>"$temp_file_report"
                    echo "  <td class=\"file-path\">$path</td>" >>"$temp_file_report"
                    echo "  <td class=\"server-name\">$server</td>" >>"$temp_file_report"
                    echo "</tr>" >>"$temp_file_report"
                done
            else
                log "AVERTISSEMENT: Aucune donnee n'a pu etre extraite pour les serveurs actuels"
                echo "<tr><td colspan=\"3\">Aucune donnee n'a pu etre extraite pour les fichiers des serveurs actuels.</td></tr>" >>"$temp_file_report"
            fi
        else
            log "Fichier $BIG_FILES_FILE introuvable ou vide"
            echo "<tr><td colspan=\"3\">Aucune donnee disponible sur les plus gros fichiers.</td></tr>" >>"$temp_file_report"
        fi

        # Fermer le HTML
        cat >>"$temp_file_report" <<EOF
    </table>
    <hr>
    <p><em>Pour plus de details, consultez le rapport complet.</em></p>
</body>
</html>
EOF

        # Définir le sujet avec préfixe [TEST] si nécessaire
        local files_subject="Liste consolidee des plus gros fichiers - $DATE"
        if $TEST_MODE; then
            files_subject="[TEST] $files_subject"
        fi

        # Envoyer l'email
        log "Envoi de l'email contenant la liste des plus gros fichiers a $BIG_FILES_EMAIL"
        cat "$temp_file_report" | mail -a "Content-Type: text/html; charset=UTF-8" -s "$files_subject" -r "$EMAIL_SENDER" "$BIG_FILES_EMAIL"
    fi

    if $MAIL_BIG_DIRS; then
        log "Preparation de l'email consolide des plus gros repertoires"
        # Créer un fichier temporaire pour le rapport
        local temp_dir_report="$TEMP_DIR/consolidated_dirs.html"

        # Générer l'en-tête HTML
        cat >"$temp_dir_report" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Liste consolidee des plus gros repertoires - $DATE</title>
    $(create_css)
    <style>
        table.consolidated {
            width: 100%;
            border-collapse: collapse;
        }
        table.consolidated th {
            background-color: #e0e0e0;
            padding: 8px;
            text-align: left;
            border: 1px solid #ccc;
        }
        table.consolidated td {
            padding: 8px;
            border: 1px solid #ccc;
        }
        .dir-size {
            font-weight: bold;
            text-align: right;
            white-space: nowrap;
        }
        .dir-path {
            font-family: monospace;
        }
        .server-name {
            font-weight: bold;
            color: #333366;
        }
        tr:nth-child(even) {
            background-color: #f9f9f9;
        }
    </style>
</head>
<body>
    <h1>Liste consolidee des plus gros repertoires - $DATE</h1>
    <p>Genere par $SCRIPT_NAME version $VERSION sur le serveur $HOSTNAME avec la commande $FULL_COMMAND</p>
EOF

        # Ajouter une note en mode test
        if $TEST_MODE; then
            echo "<p><strong>Mode TEST active</strong> - Fichier de serveurs: $SERVER_LIST</p>" >>"$temp_dir_report"
        fi
        
        # Si la liste des serveurs exclus n'est pas vide, l'ajouter au rapport
        if [ ! -z "$EXCLUDED_SERVERS" ]; then
            echo "<p><strong>Note:</strong> Les serveurs suivants sont exclus des calculs intensifs: <em>$EXCLUDED_SERVERS</em></p>" >>"$temp_dir_report"
        fi

        echo "<table class=\"consolidated\">" >>"$temp_dir_report"
        echo "<tr>" >>"$temp_dir_report"
        echo "    <th>Taille</th>" >>"$temp_dir_report"
        echo "    <th>Repertoire</th>" >>"$temp_dir_report"
        echo "    <th>Serveur</th>" >>"$temp_dir_report"
        echo "</tr>" >>"$temp_dir_report"

        # Créer un fichier temporaire pour le traitement
        local temp_processing="$TEMP_DIR/dirs_processing.tmp"
        >"$temp_processing"

        # Créer un fichier pour stocker les chemins uniques afin d'éviter les doublons
        local unique_paths_file="$TEMP_DIR/unique_dir_paths.tmp"
        >"$unique_paths_file"

        # Vérifier si le fichier existe et n'est pas vide
        if [ -f "$BIG_DIRS_FILE" ] && [ -s "$BIG_DIRS_FILE" ]; then
            log "Extraction des donnees des plus gros repertoires depuis $BIG_DIRS_FILE..."

            # Déboguer le contenu du fichier
            if $VERBOSE; then
                log "Contenu du fichier de grands repertoires:"
                head -n 20 "$BIG_DIRS_FILE" | while IFS= read -r line; do
                    log "  $line"
                done
            fi

            # Méthode alternative : extraire directement par bloc de serveur
            for current_server in "${current_servers[@]}"; do
                # Vérifier si le serveur est exclu des calculs intensifs
                if is_server_excluded "$current_server"; then
                    if $VERBOSE; then
                        log "Le serveur $current_server est exclu des calculs intensifs, données ignorées"
                    fi
                    continue  # Passer au serveur suivant
                fi

                if $VERBOSE; then
                    log "Recherche des donnees pour le serveur $current_server"
                fi

                # Utiliser awk pour extraire le bloc de données du serveur actuel
                awk -v server="$current_server" '
                BEGIN { found=0; }
                $0 ~ "^Serveur: " server ", " { found=1; next; }
                found && $0 ~ "^-{5,}$" { found=0; next; }
                found && $0 ~ "^Serveur:" { found=0; next; }
                found && $1 ~ /^[0-9,.]+[KMGTP]?$/ { print $0; }
            ' "$BIG_DIRS_FILE" >"$TEMP_DIR/server_dirs_${current_server}.tmp"

                # Vérifier si des données ont été extraites
                if [ -s "$TEMP_DIR/server_dirs_${current_server}.tmp" ]; then
                    if $VERBOSE; then
                        log "Donnees trouvees pour $current_server:"
                        cat "$TEMP_DIR/server_dirs_${current_server}.tmp" | while IFS= read -r line; do
                            log "  $line"
                        done
                    fi

                    # Traiter chaque ligne de données et éliminer les doublons
                    while IFS= read -r line; do
                        # Extraire la taille et le chemin
                        local size=$(echo "$line" | awk '{print $1}')
                        local path=$(echo "$line" | cut -d' ' -f2-)

                        # Nettoyer le chemin pour enlever la taille au début (si elle existe)
                        path=$(echo "$path" | sed 's/^[0-9,.]*[KMGTP]\?\s*//')

                        # Créer une clé unique pour ce répertoire (serveur:chemin)
                        local unique_key="${current_server}:${path}"

                        # Vérifier si nous avons déjà traité ce répertoire pour ce serveur
                        if ! grep -q "^$unique_key$" "$unique_paths_file"; then
                            # Ajouter la clé unique au fichier pour éviter les doublons
                            echo "$unique_key" >>"$unique_paths_file"

                            # Normaliser les tailles pour le tri
                            local sort_size=$(echo "$size" | tr ',' '.')
                            case "$sort_size" in
                            *K) sort_size=$(echo "${sort_size%K} * 1" | bc) ;;
                            *M) sort_size=$(echo "${sort_size%M} * 1024" | bc) ;;
                            *G) sort_size=$(echo "${sort_size%G} * 1024 * 1024" | bc) ;;
                            *T) sort_size=$(echo "${sort_size%T} * 1024 * 1024 * 1024" | bc) ;;
                            *P) sort_size=$(echo "${sort_size%P} * 1024 * 1024 * 1024 * 1024" | bc) ;;
                            esac

                            # Ajouter au fichier de traitement
                            echo "$sort_size|$size|$path|$current_server" >>"$temp_processing"

                            if $VERBOSE; then
                                log "  Ajoute: $size $path (Serveur: $current_server)"
                            fi
                        else
                            if $VERBOSE; then
                                log "  Ignore doublon: $size $path (Serveur: $current_server)"
                            fi
                        fi
                    done <"$TEMP_DIR/server_dirs_${current_server}.tmp"
                else
                    log "Aucune donnee trouvee pour le serveur $current_server"
                fi
            done

            # Vérifier si des données ont été extraites
            if [ -s "$temp_processing" ]; then
                log "Tri des donnees extraites..."
                # Trier par taille et prendre les 20 premiers
                sort -t'|' -k1 -nr "$temp_processing" | head -20 | while IFS='|' read -r sort_size size path server; do
                    echo "<tr>" >>"$temp_dir_report"
                    echo "  <td class=\"dir-size\">$size</td>" >>"$temp_dir_report"
                    echo "  <td class=\"dir-path\">$path</td>" >>"$temp_dir_report"
                    echo "  <td class=\"server-name\">$server</td>" >>"$temp_dir_report"
                    echo "</tr>" >>"$temp_dir_report"
                done
            else
                log "AVERTISSEMENT: Aucune donnee n'a pu etre extraite pour les serveurs actuels"
                echo "<tr><td colspan=\"3\">Aucune donnee n'a pu etre extraite pour les repertoires des serveurs actuels.</td></tr>" >>"$temp_dir_report"
            fi
        else
            log "Fichier $BIG_DIRS_FILE introuvable ou vide"
            echo "<tr><td colspan=\"3\">Aucune donnee disponible sur les plus gros repertoires.</td></tr>" >>"$temp_dir_report"
        fi

        # Fermer le HTML
        cat >>"$temp_dir_report" <<EOF
    </table>
    <hr>
    <p><em>Pour plus de details, consultez le rapport complet.</em></p>
</body>
</html>
EOF

        # Définir le sujet avec préfixe [TEST] si nécessaire
        local dirs_subject="Liste consolidee des plus gros repertoires - $DATE"
        if $TEST_MODE; then
            dirs_subject="[TEST] $dirs_subject"
        fi

        # Envoyer l'email
        log "Envoi de l'email contenant la liste des plus gros repertoires a $BIG_DIRS_EMAIL"
        cat "$temp_dir_report" | mail -a "Content-Type: text/html; charset=UTF-8" -s "$dirs_subject" -r "$EMAIL_SENDER" "$BIG_DIRS_EMAIL"
    fi
}

# Fonction pour afficher l'aide
show_help() {
    echo "Usage: $SCRIPT_NAME [OPTIONS]"
    echo
    echo "Options:"
    echo "  -c, --critical [NOMBRE]        Seuil critique en pourcentage (par défaut: 90)"
    echo "  -C, --critical-email [EMAIL]   Email pour les alertes de niveau critique (par défaut: critique@exemple.com)"
    echo "  -d, --dirs                     Active le calcul des grands répertoires (désactivé par défaut)"
    echo "  --days [NOMBRE]                Nombre de jours avant recalcul des grands répertoires/fichiers (par défaut: 7)"
    echo "  -E, --exclude-servers \"LISTE\"  Liste de serveurs à exclure des calculs intensifs (format: \"serveur1,serveur2,...\")"
    echo "  -f, --files                    Active le calcul des grands fichiers (désactivé par défaut)"
    echo "  -F, --num-big-files [NOMBRE]   Nombre de grands fichiers à afficher (par défaut: 3)"
    echo "  -h, --help                     Affiche ce message d'aide"
    echo "  -I, --info-email [EMAIL]       Email pour les rapports sans alerte (par défaut: infos@exemple.com)"
    echo "  -l, --list-server              Liste les serveurs configurés"
    echo "  -m, --max-logs [NOMBRE]        Nombre maximal de fichiers logs à conserver (par défaut: 30)"
    echo "  -M, --mail-big-files [EMAIL]   Envoie une liste consolidée des plus gros fichiers par email"
    echo "  -N, --validate-names [MODE]    Validation des noms de serveurs (strict/warn/off, défaut: warn)"
    echo "  -n, --num-big-dirs [NOMBRE]    Nombre de grands répertoires à afficher (par défaut: 3)"
    echo "  -P, --mail-big-dirs [EMAIL]    Envoie une liste consolidée des plus gros répertoires par email"
    echo "  -r, --rotate-logs              Active la rotation des fichiers logs"
    echo "  -R, --no-rotate-logs           Désactive la rotation des fichiers logs"
    echo "  -S, --skip-normal              Ne pas envoyer de mail si aucun seuil n'est atteint"
    echo "  -t, --test                     Mode test: utilise le fichier /usr/local/etc/server-disk-space-test.conf"
    echo "  -T, --timing                   Afficher le temps de traitement pour chaque serveur"
    echo "  -u, --usage-sort-asc           Affiche l'utilisation du disque triée par ordre croissant"
    echo "  -U, --usage-sort-desc          Affiche l'utilisation du disque triée par ordre décroissant"
    echo "  -v, --verbose                  Mode verbeux (log détaillé)"
    echo "  -V, --version                  Affiche la version du script"
    echo "  -w, --warning [NOMBRE]         Seuil d'avertissement en pourcentage (par défaut: 75)"
    echo "  -W, --warning-email [EMAIL]    Email pour les alertes de niveau avertissement (par défaut: warning@exemple.com)"
    echo "  -x, --compress-logs            Active la compression des anciens fichiers logs"
    echo "  -X, --no-compress-logs         Désactive la compression des anciens fichiers logs"
    echo "  -z, --zero-calc                Réinitialise le calcul des plus grands répertoires et fichiers"
    echo "  -Z, --validate-config          Vérifie la configuration et les connexions"
    echo " "
    echo "Description:"
    echo "  Ce script vérifie l'espace disque de plusieurs serveurs via SSH"
    echo "  et envoie un rapport par email selon le niveau d'alerte détecté."
    echo
    echo "  Note: Par défaut, les calculs intensifs (grands répertoires/fichiers) sont désactivés."
    echo "  Utilisez les options -d et -f pour les activer explicitement."
    echo
    echo "Format du fichier de configuration des serveurs:"
    echo "  serveur:partitions:seuil_warning:seuil_critical"
    echo "  Exemples:"
    echo "    serveur1                     # Vérifie seulement la partition / avec les seuils par défaut"
    echo "    serveur2:/var,/home          # Vérifie / et les partitions spécifiées avec les seuils par défaut"
    echo "    serveur3:/var:60:85          # Vérifie / et /var avec des seuils personnalisés (60% et 85%)"
    echo "    user@serveur4:/data:70:90    # Connexion avec l'utilisateur spécifié et seuils personnalisés"
    echo "    serge@mini.nojo.fr:/Volumes/Data  # Exemple pour un serveur macOS avec un utilisateur spécifique"
    exit 0
}

# Fonction pour afficher la version
show_version() {
    echo "$SCRIPT_NAME version $VERSION"
    exit 0
}

# Fonction pour écrire dans le log en mode verbeux
log() {
    if $VERBOSE; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" >>"$LOG_FILE"
        # Afficher également sur le terminal en mode verbeux
        echo "$(date +"%Y-%m-%d %H:%M:%S") - $1"
    fi
}

# Fonction pour vérifier si un serveur est accessible par ping
check_server_reachable() {
    local server_config="$1"
    local ping_count=2
    local timeout=3
    
    # Extraire le nom du serveur et l'utilisateur
    local server_info=$(extract_server_info "$server_config")
    local server_name=$(echo "$server_info" | cut -d' ' -f1)
    
    log "Vérification de l'accessibilité du serveur $server_name par ping"
    ping -c $ping_count -W $timeout $server_name >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        log "Le serveur $server_name est accessible"
        return 0 # Serveur accessible
    else
        log "ATTENTION: Le serveur $server_name n'est pas accessible par ping"
        return 1 # Serveur inaccessible
    fi
}
    
# Fonction pour vérifier si les grands répertoires doivent être calculés pour un serveur spécifique
check_big_dirs_calculation() {
    local server=$1
    # Vérification si les données pour ce serveur sont absentes ou trop anciennes
    if ! grep -q "^Serveur: $server.*Répertoires" "$BIG_DIRS_FILE" 2>/dev/null || [ $(find "$BIG_DIRS_FILE" -mtime +$CALC_DAYS -print | wc -l) -gt 0 ]; then
        log "Calcul des plus grands répertoires nécessaire pour $server (données manquantes ou plus vieilles de $CALC_DAYS jours)"
        return 0 # Calculer les grands répertoires
    else
        log "Réutilisation des données existantes sur les plus grands répertoires pour $server"
        return 1 # Ne pas calculer les grands répertoires
    fi
}

# Fonction pour vérifier si les grands fichiers doivent être calculés pour un serveur spécifique
check_big_files_calculation() {
    local server=$1
    # Vérification si les données pour ce serveur sont absentes ou trop anciennes
    if ! grep -q "^Serveur: $server.*Fichiers" "$BIG_FILES_FILE" 2>/dev/null || [ $(find "$BIG_FILES_FILE" -mtime +$CALC_DAYS -print | wc -l) -gt 0 ]; then
        log "Calcul des plus grands fichiers nécessaire pour $server (données manquantes ou plus vieilles de $CALC_DAYS jours)"
        return 0 # Calculer les grands fichiers
    else
        log "Réutilisation des données existantes sur les plus grands fichiers pour $server"
        return 1 # Ne pas calculer les grands fichiers
    fi
}

# Fonction pour créer un CSS pour l'email HTML
create_css() {
    cat <<EOF
<style>
    body {
        font-family: Arial, sans-serif;
        padding: 20px;
    }
    h1 {
        color: #333366;
    }
    h2 {
        color: #666699;
        margin-top: 20px;
    }
    table {
        border-collapse: collapse;
        width: 100%;
        margin-bottom: 20px;
    }
    th, td {
        border: 1px solid #ddd;
        padding: 8px;
        text-align: left;
    }
    th {
        background-color: #f2f2f2;
    }
    .normal {
        background-color: #e6ffe6;
    }
    .warning {
        background-color: #ffffcc;
    }
    .critical {
        background-color: #ffcccc;
    }
    .inode-normal {
        background-color: #e6f3ff;
    }
    .inode-warning {
        background-color: #ccebff;
    }
    .inode-critical {
        background-color: #b3e0ff;
    }
    .big-dirs {
        background-color: #f2f2f2;
        padding: 10px;
        margin-top: 10px;
        border-radius: 5px;
    }
</style>
EOF
}

# Fonction pour extraire proprement les informations des grands répertoires/fichiers pour un serveur spécifique
extract_big_data() {
    local server=$1
    local type=$2 # "Répertoires" ou "Fichiers"
    local file=$3 # Fichier source

    # Créer un fichier temporaire pour les résultats
    local temp_file="$TEMP_DIR/${server}_${type}.tmp"
    >"$temp_file"

    # On cherche uniquement les lignes concernant ce serveur
    grep -A20 "^Serveur: $server.*$type" "$file" | while read -r line; do
        # Si on trouve une ligne indiquant un autre serveur, on s'arrête
        if [[ "$line" =~ ^Serveur:.*$type && ! "$line" =~ ^Serveur:\ $server ]]; then
            break
        fi
        # Si on trouve une ligne de délimitation, on s'arrête
        if [[ "$line" =~ ^-{40,} ]]; then
            break
        fi
        # Sinon, on ajoute la ligne au fichier temporaire
        echo "$line" >>"$temp_file"
    done

    # Retourner le contenu filtré
    cat "$temp_file"
    rm -f "$temp_file"
}

# Fonction pour vérifier l'espace disque d'un serveur
check_disk_space() {
    local server_config=$1
    local partitions=""
    local additional_partitions=""
    local show_inodes=false
    local server_warning_threshold=$WARNING_THRESHOLD  # Valeur par défaut
    local server_critical_threshold=$CRITICAL_THRESHOLD  # Valeur par défaut

    # Extraire le nom du serveur et l'utilisateur SSH
    local server_info=$(extract_server_info "$server_config")
    local server_name=$(echo "$server_info" | cut -d' ' -f1)
    local ssh_user=$(echo "$server_info" | cut -d' ' -f2)

    local display_name=$(build_display_name "$server_name" "$ssh_user")

    log "Vérification de l'espace disque pour le serveur $display_name"
    
    # Construire la commande SSH
    local ssh_cmd=""
    if [[ -n "$ssh_user" ]]; then
        ssh_cmd="ssh ${ssh_user}@${server_name}"
    else
        ssh_cmd="ssh ${server_name}"
    fi
    
    # Détecter le système d'exploitation
    local os_type=$($ssh_cmd "uname" 2>/dev/null)
    log "Système d'exploitation détecté pour $display_name: $os_type"
    
    # Chercher la configuration du serveur dans le fichier
    local server_line=""
    if [[ -n "$ssh_user" ]]; then
        server_line=$(grep "^${ssh_user}@${server_name}:" "$SERVER_LIST" || echo "")
    else
        server_line=$(grep "^${server_name}:" "$SERVER_LIST" || echo "")
    fi
    
    if [[ -n "$server_line" ]]; then
        log "Configuration trouvée: $server_line"
        
        # Extraire directement les champs par position
        local field2=$(echo "$server_line" | cut -d':' -f2)
        local field3=$(echo "$server_line" | cut -d':' -f3)
        local field4=$(echo "$server_line" | cut -d':' -f4)
        
        # Vérification des partitions (champ 2) - CORRECTION DU BUG
        if [ ! -z "$field2" ]; then
            partitions="$field2"
            log "Partitions spécifiées pour $display_name: $partitions"
        else
            partitions="/"
            log "Aucune partition spécifiée pour $display_name, utilisation de la partition racine"
        fi
        
        # Vérification du seuil d'avertissement (champ 3)
        if [[ ! -z "$field3" && "$field3" =~ ^[0-9]+$ ]]; then
            server_warning_threshold="$field3"
            log "Seuil d'avertissement personnalisé pour $display_name: $server_warning_threshold%"
        fi
        
        # Vérification du seuil critique (champ 4)
        if [[ ! -z "$field4" && "$field4" =~ ^[0-9]+$ ]]; then
            server_critical_threshold="$field4"
            log "Seuil critique personnalisé pour $display_name: $server_critical_threshold%"
        fi
    else
        # Aucune configuration spécifique trouvée
        partitions="/"
        log "Aucune configuration spécifique pour $display_name, utilisation de la partition racine uniquement"
    fi

    # Ajouter un titre pour le serveur dans le rapport
    echo "<h2>Serveur: $display_name</h2>" >>"$TEMP_DIR/report.html"
    echo "<table>" >>"$TEMP_DIR/report.html"
    echo "<tr><th>Point de montage</th><th>Partition</th><th>Taille</th><th>Utilisé</th><th>Disponible</th><th>Utilisation</th></tr>" >>"$TEMP_DIR/report.html"

    # Traiter les partitions séparées par des virgules
    IFS=',' read -ra PARTITION_ARRAY <<< "$partitions"
    for partition in "${PARTITION_ARRAY[@]}"; do
        # Supprimer les espaces éventuels
        partition=$(echo "$partition" | tr -d '[:space:]')
        
        # Ignorer les partitions vides
        if [[ -z "$partition" ]]; then
            continue
        fi
        
        log "Vérification de la partition $partition sur $display_name"

        # Variables pour stocker les informations extraites
        local filesystem=""
        local size=""
        local used=""
        local avail=""
        local usage_str=""
        local usage_percent=""
        local mount_point=""

        # Adapter la commande en fonction du système d'exploitation
        if [[ "$os_type" == "Darwin" ]]; then
            # Version macOS de la commande df
            local df_output=$($ssh_cmd "df -h '$partition'" 2>/dev/null | grep -v "Filesystem" | head -1)
            
            if [ ! -z "$df_output" ]; then
                # Extraction adaptée pour macOS
                filesystem=$(echo "$df_output" | awk '{print $1}')
                size=$(echo "$df_output" | awk '{print $2}')
                used=$(echo "$df_output" | awk '{print $3}')
                avail=$(echo "$df_output" | awk '{print $4}')
                usage_str=$(echo "$df_output" | awk '{print $5}')
                # Sur macOS, le point de montage est en dernière position (peut être après colonne 9)
                mount_point=$(echo "$df_output" | awk '{for(i=9;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')
                
                # Si le point de montage est vide, essayer des colonnes alternatives
                if [ -z "$mount_point" ]; then
                    mount_point=$(echo "$df_output" | awk '{print $9}')
                fi
                
                # Si toujours vide, utiliser la partition spécifiée
                if [ -z "$mount_point" ]; then
                    mount_point="$partition"
                fi
            else
                log "ERREUR: Aucune donnée reçue pour $display_name:$partition"
            fi
        else
            # Version Linux standard avec LC_ALL=C pour standardiser le format de sortie
            local df_output=$($ssh_cmd "LC_ALL=C df -h '$partition'" 2>/dev/null | grep -v '^Filesystem' | grep -v '^Sys.' | head -1)
            
            if [ ! -z "$df_output" ]; then
                # Extraire proprement les informations avec awk
                filesystem=$(echo "$df_output" | awk '{print $1}')
                size=$(echo "$df_output" | awk '{print $2}')
                used=$(echo "$df_output" | awk '{print $3}')
                avail=$(echo "$df_output" | awk '{print $4}')
                usage_str=$(echo "$df_output" | awk '{print $5}')
                
                # Récupérer le point de montage (qui peut contenir des espaces)
                mount_point=$(echo "$df_output" | awk '{for(i=6;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')
                
                # Si le point de montage est vide, utiliser la partition
                if [ -z "$mount_point" ]; then
                    mount_point="$partition"
                fi
            else
                log "ERREUR: Aucune donnée reçue pour $display_name:$partition"
            fi
        fi

        # Si des données ont été récupérées, les traiter
        if [ ! -z "$df_output" ]; then
            # Enlever le % du pourcentage d'utilisation
            usage_percent=${usage_str%\%}

            local status_class="normal"
            # Vérifier que usage_percent est un nombre valide
            if [[ "$usage_percent" =~ ^[0-9]+$ ]]; then
                if $SIMULATION_MODE; then
                    log "SIMULATION : $display_name:$partition considéré comme étant à 95% d'utilisation (valeur réelle: $usage_percent%)"
                    usage_percent=95
                fi
                if [ "$usage_percent" -ge "$server_critical_threshold" ]; then
                    status_class="critical"
                    log "[CRITIQUE] $display_name:$partition est à $usage_percent% d'utilisation (seuil: $server_critical_threshold%)"
                elif [ "$usage_percent" -ge "$server_warning_threshold" ]; then
                    status_class="warning"
                    log "[WARNING] $display_name:$partition est à $usage_percent% d'utilisation (seuil: $server_warning_threshold%)"
                else
                    log "Normal: $display_name:$partition est à $usage_percent% d'utilisation"
                fi
            else
                log "AVERTISSEMENT: Impossible d'extraire le pourcentage d'utilisation pour $display_name:$partition (valeur: $usage_str)"
                usage_percent="N/A"
            fi

            # Ajouter la ligne au rapport pour ce serveur
            echo "<tr class=\"$status_class\"><td>$mount_point</td><td>$filesystem</td><td>$size</td><td>$used</td><td>$avail</td><td>$usage_percent%</td></tr>" >>"$TEMP_DIR/report.html"
        else
            log "ERREUR: Impossible de vérifier la partition $partition sur $display_name"
            echo "<tr class=\"critical\"><td>$partition</td><td colspan=\"5\">Erreur lors de la vérification</td></tr>" >>"$TEMP_DIR/report.html"
        fi
    done

    # Fermer la table pour ce serveur
    echo "</table>" >>"$TEMP_DIR/report.html"

    # Vérifier l'utilisation des inodes et décider si on doit l'afficher
    # (Cette partie varie selon l'OS)
    local display_inodes=false
    local inodes_html=""

    if [[ "$os_type" != "Darwin" ]]; then
        # Linux - gestion standard des inodes
        # Préparer le début du HTML pour les inodes dans une variable
        inodes_html+="<h3>Utilisation des inodes</h3>\n"
        inodes_html+="<table>\n"
        inodes_html+="<tr><th>Point de montage</th><th>Partition</th><th>Inodes</th><th>IUtilisés</th><th>ILibres</th><th>IUtil%</th></tr>\n"

        # Traiter les partitions pour les inodes aussi
        IFS=',' read -ra PARTITION_ARRAY <<< "$partitions"
        for partition in "${PARTITION_ARRAY[@]}"; do
            # Supprimer les espaces éventuels
            partition=$(echo "$partition" | tr -d '[:space:]')
            
            # Ignorer les partitions vides
            if [[ -z "$partition" ]]; then
                continue
            fi
            
            # Utiliser LC_ALL=C pour standardiser la sortie de df -i
            local inode_info=$($ssh_cmd "LC_ALL=C df -i $partition" 2>/dev/null | grep -v 'Filesystem' | grep -v '^Sys.' | head -1)

            if [ $? -eq 0 ] && [ ! -z "$inode_info" ]; then
                local filesystem=$(echo "$inode_info" | awk '{print $1}')
                local inodes=$(echo "$inode_info" | awk '{print $2}')
                local iused=$(echo "$inode_info" | awk '{print $3}')
                local ifree=$(echo "$inode_info" | awk '{print $4}')
                local iusage_str=$(echo "$inode_info" | awk '{print $5}')
                
                # Récupérer le point de montage (qui peut contenir des espaces)
                local mount_point=$(echo "$inode_info" | awk '{for(i=6;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')
                
                # Si le point de montage est vide, utiliser la partition
                if [ -z "$mount_point" ]; then
                    mount_point="$partition"
                fi
                
                # Extraire uniquement les chiffres du pourcentage
                local iusage_percent=$(echo "$iusage_str" | sed 's/%//')

                # Vérifier que iusage_percent est un nombre valide
                if [[ "$iusage_percent" =~ ^[0-9]+$ ]]; then
                    # Vérifier si le taux d'utilisation des inodes atteint 50%
                    if [ "$iusage_percent" -ge 50 ]; then
                        display_inodes=true
                        log "Utilisation des inodes élevée sur $display_name:$partition: $iusage_percent% (seuil: 50%)"
                    fi

                    local istatus_class="inode-normal"
                    if [ "$iusage_percent" -ge "$server_critical_threshold" ]; then
                        istatus_class="inode-critical"
                    elif [ "$iusage_percent" -ge "$server_warning_threshold" ]; then
                        istatus_class="inode-warning"
                    fi
                else
                    log "AVERTISSEMENT: Impossible d'extraire le pourcentage d'utilisation des inodes pour $display_name:$partition (valeur: $iusage_str)"
                    iusage_percent="N/A"
                    istatus_class="inode-normal"
                fi

                inodes_html+="<tr class=\"$istatus_class\"><td>$mount_point</td><td>$filesystem</td><td>$inodes</td><td>$iused</td><td>$ifree</td><td>$iusage_percent%</td></tr>\n"
            else
                inodes_html+="<tr class=\"inode-critical\"><td colspan=\"6\">Erreur lors de la vérification des inodes de $partition sur $display_name</td></tr>\n"
            fi
        done

        inodes_html+="</table>\n"

        # Ajouter les informations sur les inodes au rapport seulement si nécessaire
        if $display_inodes; then
            log "Affichage des informations sur les inodes pour $display_name (utilisation ≥ 50%)"
            echo -e "$inodes_html" >>"$TEMP_DIR/report.html"
        else
            log "Omission des informations sur les inodes pour $display_name (utilisation < 50%)"
        fi
    else
        # macOS - les inodes sont traités différemment
        log "Inodes sur macOS: gestion différente - affichage omis"
    fi

    # Vérifier si le serveur est exclu des calculs intensifs
    if is_server_excluded "$server_name"; then
        log "Le serveur $display_name est exclu des calculs des grands répertoires et fichiers"
        echo "<h3>Calculs intensifs: Le serveur $display_name est exclu des calculs des grands répertoires et fichiers</h3>" >>"$TEMP_DIR/report.html"
    else
        # Gestion des grands répertoires
        if $CALC_BIG_DIRS && check_big_dirs_calculation "$server_name"; then
            echo "<h3>Les plus grands répertoires de $display_name (calculés le $DATE)</h3>" >>"$TEMP_DIR/report.html"
            echo "<div class=\"big-dirs\">" >>"$TEMP_DIR/report.html"
            echo "<pre>" >>"$TEMP_DIR/report.html"

            # Calculer les N plus grands répertoires pour chaque partition
            IFS=',' read -ra PARTITION_ARRAY <<< "$partitions"
            for partition in "${PARTITION_ARRAY[@]}"; do
                # Supprimer les espaces éventuels
                partition=$(echo "$partition" | tr -d '[:space:]')
                
                # Ignorer les partitions vides
                if [[ -z "$partition" ]]; then
                    continue
                fi
                
                echo "Partition: $partition" >>"$TEMP_DIR/report.html"
                
                # Commande adaptée selon l'OS
                local big_dirs=""
                if [[ "$os_type" == "Darwin" ]]; then
                    # Version macOS
                    big_dirs=$($ssh_cmd "find $partition -type d -not -path '*/\.*' -exec du -sh {} \; 2>/dev/null | sort -hr | head -$NUM_BIG_DIRS")
                else
                    # Version Linux
                    big_dirs=$($ssh_cmd "find $partition -type d -exec du -sh {} \; 2>/dev/null | sort -rh | head -$NUM_BIG_DIRS")
                fi

                if [ $? -eq 0 ] && [ ! -z "$big_dirs" ]; then
                    echo "$big_dirs" >>"$TEMP_DIR/report.html"

                    # Sauvegarder les résultats pour les utiliser plus tard
                    echo "Serveur: $display_name, Partition: $partition, Date: $DATE (Répertoires)" >>"$BIG_DIRS_FILE.new"
                    echo "$big_dirs" >>"$BIG_DIRS_FILE.new"
                    echo "----------------------------------------" >>"$BIG_DIRS_FILE.new"
                else
                    echo "Erreur lors du calcul des grands répertoires pour $partition sur $display_name" >>"$TEMP_DIR/report.html"
                fi
                echo "" >>"$TEMP_DIR/report.html"
            done

            echo "</pre>" >>"$TEMP_DIR/report.html"
            echo "</div>" >>"$TEMP_DIR/report.html"
        elif $CALC_BIG_DIRS; then
            # Utiliser les données sauvegardées
            if [ -f "$BIG_DIRS_FILE" ]; then
                echo "<h3>Les plus grands répertoires de $display_name (dernière mise à jour: $(stat -c %y "$BIG_DIRS_FILE" | cut -d' ' -f1))</h3>" >>"$TEMP_DIR/report.html"
                echo "<div class=\"big-dirs\">" >>"$TEMP_DIR/report.html"
                echo "<pre>" >>"$TEMP_DIR/report.html"

                # Extraire uniquement les données pour ce serveur
                extract_big_data "$server_name" "Répertoires" "$BIG_DIRS_FILE" >>"$TEMP_DIR/report.html"

                echo "</pre>" >>"$TEMP_DIR/report.html"
                echo "</div>" >>"$TEMP_DIR/report.html"
            else
                log "Fichier de cache des grands répertoires non trouvé, il sera créé au prochain calcul"
            fi
        else
            log "Calcul des grands répertoires désactivé par l'option -D"
        fi

        # Vérifier les plus grands fichiers pour ce serveur
        if $CALC_BIG_FILES && check_big_files_calculation "$server_name"; then
            echo "<h3>Les plus grands fichiers de $display_name (calculés le $DATE)</h3>" >>"$TEMP_DIR/report.html"
            echo "<div class=\"big-dirs\">" >>"$TEMP_DIR/report.html"
            echo "<pre>" >>"$TEMP_DIR/report.html"

            # Calculer les N plus grands fichiers pour chaque partition
            IFS=',' read -ra PARTITION_ARRAY <<< "$partitions"
            for partition in "${PARTITION_ARRAY[@]}"; do
                # Supprimer les espaces éventuels
                partition=$(echo "$partition" | tr -d '[:space:]')
                
                # Ignorer les partitions vides
                if [[ -z "$partition" ]]; then
                    continue
                fi
                
                echo "Partition: $partition" >>"$TEMP_DIR/report.html"
                
                # Commande adaptée selon l'OS
                local big_files=""
                if [[ "$os_type" == "Darwin" ]]; then
                    # Version macOS
                    big_files=$($ssh_cmd "find $partition -type f -not -path '*/\.*' -exec du -sh {} \; 2>/dev/null | sort -hr | head -$NUM_BIG_FILES")
                else
                    # Version Linux
                    big_files=$($ssh_cmd "find $partition -type f -exec du -sh {} \; 2>/dev/null | sort -rh | head -$NUM_BIG_FILES")
                fi

                if [ $? -eq 0 ] && [ ! -z "$big_files" ]; then
                    echo "$big_files" >>"$TEMP_DIR/report.html"

                    # Sauvegarder les résultats pour les utiliser plus tard
                    echo "Serveur: $display_name, Partition: $partition, Date: $DATE (Fichiers)" >>"$BIG_FILES_FILE.new"
                    echo "$big_files" >>"$BIG_FILES_FILE.new"
                    echo "----------------------------------------" >>"$BIG_FILES_FILE.new"
                else
                    echo "Erreur lors du calcul des grands fichiers pour $partition sur $display_name" >>"$TEMP_DIR/report.html"
                fi
                echo "" >>"$TEMP_DIR/report.html"
            done

            echo "</pre>" >>"$TEMP_DIR/report.html"
            echo "</div>" >>"$TEMP_DIR/report.html"
        elif $CALC_BIG_FILES; then
            # Utiliser les données sauvegardées
            if [ -f "$BIG_FILES_FILE" ]; then
                echo "<h3>Les plus grands fichiers de $display_name (dernière mise à jour: $(stat -c %y "$BIG_FILES_FILE" | cut -d' ' -f1))</h3>" >>"$TEMP_DIR/report.html"
                echo "<div class=\"big-dirs\">" >>"$TEMP_DIR/report.html"
                echo "<pre>" >>"$TEMP_DIR/report.html"

                # Extraire uniquement les données pour ce serveur
                extract_big_data "$server_name" "Fichiers" "$BIG_FILES_FILE" >>"$TEMP_DIR/report.html"

                echo "</pre>" >>"$TEMP_DIR/report.html"
                echo "</div>" >>"$TEMP_DIR/report.html"
            else
                log "Fichier de cache des grands fichiers non trouvé, il sera créé au prochain calcul"
            fi
        else
            log "Calcul des grands fichiers désactivé par l'option -F"
        fi
    fi
}

#
# =======================  debut de la partie principale ===========
# Traiter d'abord l'option -t (mode test)
for arg in "$@"; do
    if [[ "$arg" == "-t" ]] || [[ "$arg" == "--test" ]]; then
        TEST_MODE=true
        SERVER_LIST="$SERVER_LIST_TEST"
        log "Mode test activé: utilisation du fichier $SERVER_LIST_TEST"
        break
    fi
done

# Traiter les options
while [[ $# -gt 0 ]]; do
    case $1 in
    -c | --critical)
        if [[ $2 =~ ^[0-9]+$ ]] && [ $2 -ge 0 ] && [ $2 -le 100 ]; then
            CRITICAL_THRESHOLD=$2
            log "Seuil critique défini à $CRITICAL_THRESHOLD%"
            shift # passe à l'argument suivant
        else
            echo "Erreur: l'option -c nécessite un nombre entier entre 0 et 100."
            exit 1
        fi
        ;;
    -C | --critical-email)
        if [[ $2 =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            CRITICAL_EMAIL=$2
            log "Email pour les alertes de niveau critique défini à $CRITICAL_EMAIL"
            shift # passe à l'argument suivant
        else
            echo "Erreur: l'option -C/--critical-email nécessite une adresse email valide."
            exit 1
        fi
        ;;
    -d | --dirs)
        CALC_BIG_DIRS=true
        log "Calcul des grands répertoires activé"
        ;;
    --days)
        if [[ $2 =~ ^[0-9]+$ ]]; then
            CALC_DAYS=$2
            log "Nombre de jours avant recalcul défini à $CALC_DAYS"
            shift # passe à l'argument suivant
        else
            echo "Erreur: l'option --days nécessite un nombre entier."
            exit 1
        fi
        ;;
    -E | --exclude-servers)
        EXCLUDED_SERVERS="$2"
        log "Serveurs exclus des calculs intensifs: $EXCLUDED_SERVERS"
        shift # passe à l'argument suivant
        ;;
    -f | --files)
        CALC_BIG_FILES=true
        log "Calcul des grands fichiers activé"
        ;;
    -F | --num-big-files)
        if [[ $2 =~ ^[0-9]+$ ]]; then
            NUM_BIG_FILES=$2
            log "Nombre de grands fichiers à afficher défini à $NUM_BIG_FILES"
            shift # passe à l'argument suivant
        else
            echo "Erreur: l'option -F nécessite un nombre entier."
            exit 1
        fi
        ;;
    -h | --help)
        show_help
        ;;
    -I | --info-email)
        if [[ $2 =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            INFO_EMAIL=$2
            log "Email pour les rapports sans alerte défini à $INFO_EMAIL"
            shift # passe à l'argument suivant
        else
            echo "Erreur: l'option -I/--info-email nécessite une adresse email valide."
            exit 1
        fi
        ;;
    -l | --list-server)
        list_servers
        ;;
    -m | --max-logs)
        if [[ $2 =~ ^[0-9]+$ ]]; then
            LOG_ROTATION_MAX_FILES=$2
            log "Nombre maximal de fichiers de logs défini à $LOG_ROTATION_MAX_FILES"
            shift # passe à l'argument suivant
        else
            echo "Erreur: l'option --max-logs nécessite un nombre entier."
            exit 1
        fi
        ;;
    -M | --mail-big-files)
        MAIL_BIG_FILES=true
        SKIP_STANDARD_REPORT=true
        if [[ $2 =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            BIG_FILES_EMAIL=$2
            log "Email pour l'envoi des plus gros fichiers défini à $BIG_FILES_EMAIL"
            shift # passe à l'argument suivant
        fi
        ;;
    -n | --num-big-dirs)
        if [[ $2 =~ ^[0-9]+$ ]]; then
            NUM_BIG_DIRS=$2
            log "Nombre de grands répertoires à afficher défini à $NUM_BIG_DIRS"
            shift # passe à l'argument suivant
        else
            echo "Erreur: l'option -n nécessite un nombre entier."
            exit 1
        fi
        ;;
    -N | --validate-names)
        case "$2" in
            strict|warn|off)
                SERVER_VALIDATION_MODE="$2"
                log "Mode de validation des noms de serveurs: $SERVER_VALIDATION_MODE"
                shift
                ;;
            *)
                echo "Erreur: Mode de validation invalide. Utilisez 'strict', 'warn' ou 'off'."
                exit 1
                ;;
        esac
        ;;
    -P | --mail-big-dirs)
        MAIL_BIG_DIRS=true
        SKIP_STANDARD_REPORT=true
        if [[ $2 =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            BIG_DIRS_EMAIL=$2
            log "Email pour l'envoi des plus gros répertoires défini à $BIG_DIRS_EMAIL"
            shift # passe à l'argument suivant
        fi
        ;;
    -r | --rotate-logs)
        LOG_ROTATION_ENABLED=true
        log "Rotation des logs activée"
        ;;
    -R | --no-rotate-logs)
        LOG_ROTATION_ENABLED=false
        log "Rotation des logs désactivée"
        ;;
    -s | --simulate)
        SIMULATION_MODE=true
        log "Mode simulation activé : toutes les partitions seront considérées comme ayant 95% d'utilisation"
        ;;
    -S | --skip-normal)
        SKIP_NORMAL_MAIL=true
        log "Mode sans mail pour rapports normaux activé"
        ;;
    -t | --test)
        # Déjà traité au début, ne rien faire ici
        ;;
    -T | --timing)
        SHOW_SERVER_TIMING=true
        log "Affichage du temps de traitement par serveur activé"
        ;;
    -u | --usage-sort-asc)
        SHOW_USAGE_SORTED="asc"
        log "Affichage de l'utilisation triée par ordre croissant activé"
        ;;
    -U | --usage-sort-desc)
        SHOW_USAGE_SORTED="desc"
        log "Affichage de l'utilisation triée par ordre décroissant activé"
        ;;
    -v | --verbose)
        VERBOSE=true
        ;;
    -V | --version)
        show_version
        ;;
    -w | --warning)
        if [[ $2 =~ ^[0-9]+$ ]] && [ $2 -ge 0 ] && [ $2 -le 100 ]; then
            WARNING_THRESHOLD=$2
            log "Seuil d'avertissement défini à $WARNING_THRESHOLD%"
            shift # passe à l'argument suivant
        else
            echo "Erreur: l'option -w nécessite un nombre entier entre 0 et 100."
            exit 1
        fi
        ;;
    -W | --warning-email)
        if [[ $2 =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            WARNING_EMAIL=$2
            log "Email pour les alertes de niveau avertissement défini à $WARNING_EMAIL"
            shift # passe à l'argument suivant
        else
            echo "Erreur: l'option -W/--warning-email nécessite une adresse email valide."
            exit 1
        fi
        ;;
    -x | --compress-logs)
        LOG_ROTATION_COMPRESS=true
        log "Compression des logs activée"
        ;;
    -X | --no-compress-logs)
        LOG_ROTATION_COMPRESS=false
        log "Compression des logs désactivée"
        ;;
    -z | --zero-calc)
        # Réinitialiser le calcul des plus grands répertoires et fichiers et quitter
        echo "Réinitialisation du calcul des plus grands répertoires et fichiers..."
        if [ -f "$BIG_DIRS_FILE" ]; then
            echo "Suppression du fichier de cache des répertoires: $BIG_DIRS_FILE"
            rm -f "$BIG_DIRS_FILE"
        fi
        if [ -f "$BIG_FILES_FILE" ]; then
            echo "Suppression du fichier de cache des fichiers: $BIG_FILES_FILE"
            rm -f "$BIG_FILES_FILE"
        fi
        echo "Réinitialisation terminée. Le recalcul sera effectué lors de la prochaine exécution du script."
        exit 0
        ;;
    -Z | --validate-config)
        VALIDATION_MODE=true
        log "Mode validation: vérification de la configuration activée"
        ;;
    # Gestion des anciennes options obsolètes pour faciliter la migration
    -D | --no-dirs)
        echo "AVERTISSEMENT: L'option -D/--no-dirs est obsolète. Les calculs des grands répertoires sont maintenant désactivés par défaut."
        echo "Utilisez -d/--dirs pour les activer si nécessaire."
        ;;
    -F | --no-files)
        echo "AVERTISSEMENT: L'option -F/--no-files est obsolète. Les calculs des grands fichiers sont maintenant désactivés par défaut."
        echo "Utilisez -f/--files pour les activer si nécessaire."
        ;;
    *)
        echo "Option inconnue: $1"
        echo "Utilisez '$SCRIPT_NAME --help' pour voir les options disponibles."
        exit 1
        ;;
    esac
    shift
done

# MODIFICATION 1: Si SHOW_USAGE_SORTED est défini, donner la priorité à cette option
# et ne pas exécuter la validation de configuration
if [ ! -z "$SHOW_USAGE_SORTED" ]; then
    log "Option de tri d'utilisation détectée ($SHOW_USAGE_SORTED), désactivation du mode validation"
    VALIDATION_MODE=false
fi

# Si en mode validation, exécuter la validation et sortir
if $VALIDATION_MODE; then
    log "Exécution de la validation de configuration..."
    validate_configuration
    exit $?
fi

if $TEST_MODE; then
    log "Exécution en mode TEST avec le fichier $SERVER_LIST"
else
    log "Exécution en mode normal avec le fichier $SERVER_LIST"
fi

# Créer les répertoires nécessaires s'ils n'existent pas
mkdir -p "$LOG_DIR"
mkdir -p "$TEMP_DIR"

log "Démarrage du script $SCRIPT_NAME version $VERSION"

# Vérifier si le fichier de liste de serveurs existe
if [ ! -f "$SERVER_LIST" ]; then
    echo "Erreur: Fichier de liste de serveurs $SERVER_LIST introuvable."
    exit 1
fi

# MODIFICATION 2: Si SHOW_USAGE_SORTED est défini, exécuter uniquement la fonction show_sorted_usage
# et ignorer le reste du traitement
if [ ! -z "$SHOW_USAGE_SORTED" ]; then
    log "Exécution uniquement du tri d'utilisation ($SHOW_USAGE_SORTED)"
    show_sorted_usage "$SHOW_USAGE_SORTED"
    
    # Rotation des logs si activée
    if $LOG_ROTATION_ENABLED; then
        rotate_logs "$LOG_DIR" $LOG_ROTATION_MAX_FILES $LOG_ROTATION_COMPRESS
    fi
    
    log "Fin du script $SCRIPT_NAME (mode tri d'utilisation uniquement)"
    exit 0
fi

# Créer le rapport HTML (en-tête)
cat >"$TEMP_DIR/report.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Rapport d'espace disque - $DATE $TIME</title>
    $(create_css)
</head>
<body>
    <h1>Rapport d'espace disque - $DATE $TIME</h1>
    <p>Généré par $SCRIPT_NAME version $VERSION sur le serveur $HOSTNAME avec la commande $FULL_COMMAND</p>
    <p><em>Note: Des seuils personnalisés peuvent être définis pour chaque serveur dans le fichier de configuration.</em></p>
EOF

# Variables pour suivre s'il y a des alertes
has_warning=false
has_critical=false

log "Lecture du fichier de serveurs $SERVER_LIST"

# Déboguer le contenu du fichier
if $VERBOSE; then
    log "Contenu du fichier de serveurs:"
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Ignorer les lignes vides et les commentaires
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        # Extraire le nom du serveur (avant le premier ':' s'il existe)
        server=$(echo "$line" | cut -d':' -f1 | tr -d '[:space:]')
        # Afficher uniquement les noms de serveur non vides
        if [[ ! -z "$server" ]]; then
            log "  Serveur: '$server'"
        fi
    done <"$SERVER_LIST"
fi

# Créer un tableau temporaire pour stocker les serveurs
servers=()
invalid_servers=()

while IFS= read -r line || [[ -n "$line" ]]; do
    # Ignorer les lignes vides et les commentaires
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    # Extraire le nom du serveur (avant le premier ':' s'il existe)
    server=$(echo "$line" | cut -d':' -f1 | tr -d '[:space:]')
    
    # Valider le nom du serveur
    if validate_server_name "$server" "$SERVER_VALIDATION_MODE"; then
        servers+=("$line")
        log "Serveur valide ajouté: $server"
    else
        invalid_servers+=("$server")
        if [ "$SERVER_VALIDATION_MODE" = "strict" ]; then
            log "Serveur ignoré (mode strict): $server"
        else
            servers+=("$line")
            log "Serveur ajouté avec avertissement: $server"
        fi
    fi
done < "$SERVER_LIST"

# Ajouter au rapport un avertissement concernant les serveurs invalides
if [ ${#invalid_servers[@]} -gt 0 ]; then
    echo "<div class=\"warning\" style=\"padding: 10px; margin: 10px 0; border-radius: 5px;\">" >> "$TEMP_DIR/report.html"
    echo "<h3>Avertissement: Serveurs potentiellement mal configurés</h3>" >> "$TEMP_DIR/report.html"
    echo "<p>Les serveurs suivants ont des noms qui ne respectent pas les conventions de nommage ou n'ont pas pu être résolus:</p>" >> "$TEMP_DIR/report.html"
    echo "<ul>" >> "$TEMP_DIR/report.html"
    for invalid_server in "${invalid_servers[@]}"; do
        echo "<li>$invalid_server</li>" >> "$TEMP_DIR/report.html"
    done
    echo "</ul>" >> "$TEMP_DIR/report.html"
    echo "<p>Veuillez vérifier la configuration de ces serveurs.</p>" >> "$TEMP_DIR/report.html"
    echo "</div>" >> "$TEMP_DIR/report.html"
fi

# Trier les serveurs par ordre alphabétique
IFS=$'\n' sorted_servers=($(sort <<<"${servers[*]}"))
unset IFS

# Afficher le nombre de serveurs trouvés
log "Nombre de serveurs à traiter: ${#sorted_servers[@]}"

# Déclarer le tableau associatif pour stocker les temps de traitement des serveurs
declare -A server_timings

# Parcourir le tableau des serveurs triés
for line in "${sorted_servers[@]}"; do
    # Extraire le nom du serveur et l'utilisateur SSH
    server_info=$(extract_server_info "$line")
    server_name=$(echo "$server_info" | cut -d' ' -f1)
    ssh_user=$(echo "$server_info" | cut -d' ' -f2)
    
    if [[ -z "$server_name" ]]; then
        log "AVERTISSEMENT: Nom de serveur vide ignoré"
        continue
    fi

    # Utiliser la fonction pour générer le nom d'affichage
    display_name=$(build_display_name "$server_name" "$ssh_user")
    
    # Ajouter un saut de ligne en mode verbose
    if $VERBOSE; then
        echo ""
    fi
    
    log "Traitement du serveur: '$display_name'"
    
    # Enregistrer l'heure de début pour ce serveur
    if $SHOW_SERVER_TIMING; then
        server_start_time=$(date +%s)
    fi
    
    # Vérifier si le serveur est accessible par ping
    if ! check_server_reachable "$line"; then
        log "ERREUR: Le serveur $display_name n'est pas accessible, vérification ignorée"
        echo "<h2>Serveur: $display_name</h2>" >>"$TEMP_DIR/report.html"
        echo "<p class=\"critical\">Le serveur n'est pas accessible par ping</p>" >>"$TEMP_DIR/report.html"
        continue
    fi
    
    # Vérifier l'espace disque du serveur (fonction adaptée)
    check_disk_space "$line"
    
    # Vérifier s'il y a des alertes (fonction adaptée)
    check_for_alerts "$line"
    
    # Calcul du temps de traitement
    if $SHOW_SERVER_TIMING; then
        server_end_time=$(date +%s)
        server_duration=$((server_end_time - server_start_time))
        server_timings["$display_name"]=$server_duration
        
        if $VERBOSE; then
            server_duration_min=$((server_duration / 60))
            server_duration_sec=$((server_duration % 60))
            
            if [ $server_duration_min -gt 0 ]; then
                log "Temps de traitement pour $display_name: $server_duration_min minute(s) et $server_duration_sec seconde(s)"
            else
                log "Temps de traitement pour $display_name: $server_duration_sec seconde(s)"
            fi
        fi
    fi
done

# Fusion des fichiers temporaires avec les fichiers existants
if [ -f "$BIG_DIRS_FILE.new" ]; then
    # Si le fichier principal existe, fusionner les données
    if [ -f "$BIG_DIRS_FILE" ]; then
        # On conserve les données qui ne sont pas dans le fichier temporaire
        grep -v -f "$BIG_DIRS_FILE.new" "$BIG_DIRS_FILE" >"$BIG_DIRS_FILE.merged" 2>/dev/null
        cat "$BIG_DIRS_FILE.new" >>"$BIG_DIRS_FILE.merged"
        mv "$BIG_DIRS_FILE.merged" "$BIG_DIRS_FILE"
    else
        # Si le fichier principal n'existe pas, utiliser directement le fichier temporaire
        mv "$BIG_DIRS_FILE.new" "$BIG_DIRS_FILE"
    fi
    rm -f "$BIG_DIRS_FILE.new" 2>/dev/null
fi

if [ -f "$BIG_FILES_FILE.new" ]; then
    # Si le fichier principal existe, fusionner les données
    if [ -f "$BIG_FILES_FILE" ]; then
        # On conserve les données qui ne sont pas dans le fichier temporaire
        grep -v -f "$BIG_FILES_FILE.new" "$BIG_FILES_FILE" >"$BIG_FILES_FILE.merged" 2>/dev/null
        cat "$BIG_FILES_FILE.new" >>"$BIG_FILES_FILE.merged"
        mv "$BIG_FILES_FILE.merged" "$BIG_FILES_FILE"
    else
        # Si le fichier principal n'existe pas, utiliser directement le fichier temporaire
        mv "$BIG_FILES_FILE.new" "$BIG_FILES_FILE"
    fi
    rm -f "$BIG_FILES_FILE.new" 2>/dev/null
fi

# Ajouter le tableau récapitulatif des temps de traitement des serveurs
if $SHOW_SERVER_TIMING && [ ${#server_timings[@]} -gt 0 ]; then
    echo "<hr>" >>"$TEMP_DIR/report.html"
    echo "<h2>Temps de traitement par serveur</h2>" >>"$TEMP_DIR/report.html"
    echo "<table>" >>"$TEMP_DIR/report.html"
    echo "<tr><th>Serveur</th><th>Temps</th></tr>" >>"$TEMP_DIR/report.html"
    
    # Trier les serveurs par ordre décroissant de temps de traitement
    for server in $(for k in "${!server_timings[@]}"; do echo "$k ${server_timings[$k]}"; done | sort -rn -k2 | cut -d' ' -f1); do
        duration=${server_timings["$server"]}
        duration_min=$((duration / 60))
        duration_sec=$((duration % 60))
        
        echo "<tr>" >>"$TEMP_DIR/report.html"
        echo "<td>$server</td>" >>"$TEMP_DIR/report.html"
        
        if [ $duration_min -gt 0 ]; then
            echo "<td>${duration_min}m ${duration_sec}s</td>" >>"$TEMP_DIR/report.html"
        else
            echo "<td>${duration_sec}s</td>" >>"$TEMP_DIR/report.html"
        fi
        
        echo "</tr>" >>"$TEMP_DIR/report.html"
    done
    
    echo "</table>" >>"$TEMP_DIR/report.html"
fi

# Calculer la durée d'exécution
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Convertir en minutes et secondes
DURATION_MIN=$((DURATION / 60))
DURATION_SEC=$((DURATION % 60))

# Ajouter la durée d'exécution à la fin du rapport
echo "<hr>" >>"$TEMP_DIR/report.html"
echo "<p><em>Durée d'exécution : $DURATION_MIN minute(s) et $DURATION_SEC seconde(s)</em></p>" >>"$TEMP_DIR/report.html"

# Terminer le rapport HTML
echo "</body></html>" >>"$TEMP_DIR/report.html"

# Générer le rapport d'utilisation trié si demandé
if [ ! -z "$SHOW_USAGE_SORTED" ]; then
    show_sorted_usage "$SHOW_USAGE_SORTED"
fi

# Initialisation du sujet de base (sans préfixe)
subject="Rapport disques, repertoires et fichiers"

# Initialiser la liste des destinataires (vide au départ)
recipients=""

# N'envoyer le rapport standard que si SKIP_STANDARD_REPORT est faux
if ! $SKIP_STANDARD_REPORT; then
    # Initialisation du sujet de base (sans préfixe)
    subject="Rapport disques, repertoires et fichiers"

    # Ajouter les destinataires en fonction des seuils atteints
    if $has_critical; then
        recipients="$CRITICAL_EMAIL"
        subject="[CRITIQUE] $subject" # Ajouter le préfixe une seule fois ici
    fi

    if $has_warning; then
        # Si on a déjà un destinataire critique, ajouter le warning avec une virgule
        if [ ! -z "$recipients" ]; then
            recipients="$recipients,$WARNING_EMAIL"
            # Ne pas modifier le sujet si déjà préfixé par [CRITIQUE]
        else
            recipients="$WARNING_EMAIL"
            subject="[WARNING] $subject" # Ajouter le préfixe une seule fois ici
        fi
    fi

    # Si aucun seuil n'est atteint, envoyer à l'adresse info seulement si SKIP_NORMAL_MAIL est faux
    if [ -z "$recipients" ]; then
        if ! $SKIP_NORMAL_MAIL; then
            recipients="$INFO_EMAIL"
        else
            log "Aucun seuil atteint et option -S activée, aucun email ne sera envoyé"
        fi
    fi

    # Ajouter un préfixe [TEST] en mode test
    if $TEST_MODE; then
        subject="[TEST] $subject"
    fi

    # Envoyer l'email seulement si nous avons des destinataires
    if [ ! -z "$recipients" ]; then
        log "Envoi de l'email à $recipients avec le sujet '$subject'"
        cat "$TEMP_DIR/report.html" | mail -a "Content-Type: text/html; charset=UTF-8" -s "$subject" -r "$EMAIL_SENDER" "$recipients"
    else
        log "Aucun email envoyé (pas de destinataires)"
    fi
else
    log "Envoi du rapport standard ignoré (options -M ou -P activées)"
fi

# Envoyer les rapports consolidés si demandé
send_consolidated_reports

# Sauvegarder le rapport
log "Sauvegarde du rapport dans $LOG_DIR/report-$DATE.html"
cp "$TEMP_DIR/report.html" "$LOG_DIR/report-$DATE.html"

# Juste avant la fin du script, après l'envoi des rapports
if $LOG_ROTATION_ENABLED; then
    rotate_logs "$LOG_DIR" $LOG_ROTATION_MAX_FILES $LOG_ROTATION_COMPRESS
fi

# Nettoyer
log "Nettoyage des fichiers temporaires"
rm -rf "$TEMP_DIR"

log "Fin du script $SCRIPT_NAME"
exit 0
) 200>"$LOCK_FILE"

    
