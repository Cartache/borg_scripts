#!/bin/bash

LOGDIR="/var/log/borgbackup"
CONFIGDIR="/opt/borgbackup/"
LOG="$LOGDIR/backup.log"
HOST=$(hostname)
ARCHITECTURE=lscpu | grep Architecture
#RSYNC_REMOVE_SOURCE="--remove-source-files"
RSYNC_REMOVE_SOURCE=""
RSYNC_SOURCE="/mnt/storagebox/backup/"
RSYNC_DESTINATION="/mnt/gdrive/Backup/Storagebox/"
RSYNC_LOG="/var/log/rsync/rsync_generic.log"
## Backup compression ratio. Value between 1 and 22 ## Highest but lowest speed = 22
BORG_COMPRESSION=15

export HOME=/root
#export BORG_PASSPHRASE="Cannon_Underwire_Tactical_Pending_Bonanza_Constant_Glove_Dreadlock_Resigned_Jiffy"
export BORG_PASSCOMMAND="cat $HOME/.borg-passphrase" 	
export BORG_RSH='ssh -i /opt/borgbackup/.ssh/id_rsa'														#Std Variable
export BORG_REPO="ssh://u225102@u225102.your-storagebox.de:23/./backup/desbreit"							#Std Variable
export BORG_EXPORT_PATH="/mnt/gdrive/Backup/borgbackup/borg.key"

case "$HOST" in
	osmc)
	BORG_PARAMS="--verbose 							 	\
			--filter AME 						 	\
			--list									\
			--stats 							 	\
			--show-rc 							 	\
			--exclude-caches						\
			--one-file-system						"
		;;
	*)
	BORG_PARAMS="--verbose 							 	\
				--filter AME 						 	\
				--list									\
				--stats 							 	\
				--show-rc 							 	\
				--exclude-caches						\
				--one-file-system						\
				--compression zstd,$BORG_COMPRESSION    "
		;;
esac


# check if we are the only local instance
if [[ "`pidof -x $(basename $0) -o %PPID`" ]]; then
        echo "This script is already running with PID `pidof -x $(basename $0) -o %PPID`" >> "${LOG}"
        exit
fi

# Check for root permissions
if [[ $EUID -ne 0 ]]; then
  echo -e "${SCRIPT_NAME} requires root privledges.\n"
  echo -e "sudo $0 $*\n"
  exit 1
fi

#create log folder if not present
if [ ! -d "$LOGDIR" ]; then
	mkdir -p $LOGDIR
fi

#create include and exclude files if missing
touch "$CONFIGDIR/borg_include_system.lst"
touch "$CONFIGDIR/borg_include_containers.lst"
touch "$CONFIGDIR/borg_include_data.lst"
touch "$CONFIGDIR/borg_exclude_system.lst"
touch "$CONFIGDIR/borg_exclude_containers.lst"
touch "$CONFIGDIR/borg_exclude_data.lst"



# some helpers and error handling:
info() { printf "\n%s %s\n\n" "$( date )" "$*" >&2; }
trap 'echo $( date ) Backup interrupted >&2; exit 2' INT TERM

##
## Output to a logfile
##
exec > >(tee -i $LOG)
exec 2>&1

echo "###### Backup started: ######"
echo $( date )
echo "Backuping up $1 from ${HOST}" 

case "$1" in
	containers)
		# get all running docker container names
		#SRCNAMES=$(sudo docker ps | awk '{if(NR>1) print $NF}')
		SRCNAMES="filezilla"
		BORG_EXCLUDE="/opt/borgbackup/borg_exclude_containers.lst"
		# loop through all running containers
		for SRCNAME in $SRCNAMES
		do
			docker stop $SRCNAME
			echo "Backuping up ${SRCNAME}"
			sleep 5
			borg create $BORG_PARAMS						\
						--exclude-from $BORG_EXCLUDE 		\
						$BORG_REPO::"$HOST-$SRCNAME-{now}" 	\
						/opt/appdata/$SRCNAME
			docker start $SRCNAME
		done
		;;
	system)
		export BORG_INCLUDE="/opt/borgbackup/borg_include_system.lst"
		BORG_EXCLUDE="/opt/borgbackup/borg_exclude_system.lst"
		borg create									\
					$BORG_PARAMS					\
					--exclude-from $BORG_EXCLUDE 	\
					$BORG_REPO::"$HOST-{now}" 		\
					$BORG_INCLUDE
		;;
	data)
		export BORG_INCLUDE="/opt/borgbackup/borg_include_data.lst"
		BORG_EXCLUDE="/opt/borgbackup/borg_exclude_data.lst"
		borg create									\
					$BORG_PARAMS					\
					--exclude-from $BORG_EXCLUDE 	\
					$BORG_REPO::"$HOST-{now}" 		\
					$BORG_INCLUDE
		;;
	list)
		borg list $BORG_REPO -P $HOST
		;;
	rsync)
		rsync -arvzh --progress --stats $RSYNC_REMOVE_SOURCE $RSYNC_SOURCE $RSYNC_DESTINATION > $RSYNC_LOG
		;;
	keys_export)
		borg key export --paper $BORG_REPO $BORG_EXPORT_PATH
		;;
	*)
		echo $"Usage: $0 {containers|system|data|rsync|key_export}"
		exit 1
		;;
esac

backup_exit=$?

info "Pruning repository"

# Use the `prune` subcommand to maintain 7 daily, 4 weekly and 6 monthly
# archives of THIS machine. The '{hostname}-' prefix is very important to
# limit prune's operation to this machine's archives and not apply to
# other machines' archives also:

borg prune                          \
    --list                          \
    --prefix '$HOST-'          \
    --show-rc                       \
    --keep-daily    7               \
    --keep-weekly   4               \
    --keep-monthly  6               \
	$BORG_REPO

prune_exit=$?

# use highest exit code as global exit code
global_exit=$(( backup_exit > prune_exit ? backup_exit : prune_exit ))

if [ ${global_exit} -eq 0 ]; then
    info "Backup and Prune finished successfully"
elif [ ${global_exit} -eq 1 ]; then
    info "Backup and/or Prune finished with warnings"
else
    info "Backup and/or Prune finished with errors"
fi

exit ${global_exit}

echo "###### Backup ended: {now} ######"

