#!/bin/bash

if [[ $2 == "debug" ]]; 
then
	BORG_DEBUG="true"
fi

LOGDIR="/var/log/borgbackup"
CONFIGDIR="/opt/borgbackup/"
LOG="$LOGDIR/backup.log"
HOST=$(hostname)
ARCHITECTURE=$(lscpu | grep Architecture)
#RSYNC_REMOVE_SOURCE="--remove-source-files"
RSYNC_REMOVE_SOURCE=""
RSYNC_SOURCE="/mnt/storagebox/backup/"
RSYNC_DESTINATION="/mnt/gdrive/Backup/Storagebox/"
RSYNC_LOG="/var/log/rsync/rsync_generic.log"
## Backup compression ratio. Value between 1 and 22 ## Highest but lowest speed = 22
BORG_COMPRESSION=15
BORG_TEMPMOUNT="/tmp/borgmount"

export HOME=/root
export BORG_PASSCOMMAND="cat $HOME/.borg-passphrase" 	
export BORG_RSH='ssh -i /opt/borgbackup/.ssh/id_rsa'	
export BORG_EXPORT_PATH="/mnt/gdrive/Backup/borgbackup/borg.key"
export BORG_EXCLUDE="/opt/borgbackup/borg_exclude_${1}_$HOST.lst"
echo $BORG_EXCLUDE
echo "This is the architecture $ARCHITECTURE"

BORG_PARAMS="--verbose 							 	\
		--filter AME 						 	\
		--list									\
		--stats 							 	\
		--show-rc 							 	\
		--exclude-caches						\
		--one-file-system						"

#Disable compression in case of Raspberry PI
#if [[ $ARCHITECTURE =~ "arm" ]]; 
#then
#	export BORG_REPO="ssh://u225102@u225102.your-storagebox.de:23/./backup/desbreit_ARM"
#else
	export BORG_REPO="ssh://u225102@u225102.your-storagebox.de:23/./backup/desbreit"
	BORG_PARAMS="$BORG_PARAMS --compression zstd,$BORG_COMPRESSION"
#fi

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
	sudo mkdir -p $LOGDIR
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

echo "###### Borg started: ######"
echo $( date )
echo "Borging $1 from ${HOST}" 

case "$1" in
	containers)
		# get all running docker container names
		SRCNAMES=$(sudo docker ps | awk '{if(NR>1) print $NF}')
		#SRCNAMES="filezilla"
#		export BORG_EXCLUDE="/opt/borgbackup/borg_exclude_containers.lst"
		# loop through all running containers
		for SRCNAME in $SRCNAMES
		do
			docker stop $SRCNAME
			echo "Backuping up ${SRCNAME}"
			sleep 5
			borg create $BORG_PARAMS						\
						--exclude-from $BORG_EXCLUDE 		\
						$BORG_REPO::"$HOST-Containers-$SRCNAME-{now}" 	\
						/opt/appdata/$SRCNAME
			docker start $SRCNAME
		done
		;;
	system)
		while read -r line; do BORG_INCLUDE="$BORG_INCLUDE $line"; done < "/opt/borgbackup/borg_include_system.lst"
		echo "This is $BORG_INCLUDE"
		export BORG_EXCLUDE="/opt/borgbackup/borg_exclude_system.lst"
		if $BORG_DEBUG=="true";
		then
		echo "borg create								\
					$BORG_PARAMS						\
					--exclude-from $BORG_EXCLUDE 		\
					$BORG_REPO::"$HOST-System-{now} " 	\
					$BORG_INCLUDE"
		else
		borg create										\
					$BORG_PARAMS						\
					--exclude-from $BORG_EXCLUDE 		\
					$BORG_REPO::"$HOST-System-{now} " 	\
					$BORG_INCLUDE
		fi
		;;
	data)
		# reads the include file into BORG_INCLUDE variable
		while read -r line; do BORG_INCLUDE="$BORG_INCLUDE $line"; done < "/opt/borgbackup/borg_include_data.lst"
		borg create									\
					$BORG_PARAMS					\
					--exclude-from $BORG_EXCLUDE 	\
					$BORG_REPO::"$HOST-Data-{now}" 		\
					$BORG_INCLUDE
		;;
	mount)
		borg mount	$BORG_REPO $BORG_TEMPMOUNT*
		;;
	umount)
		borg umount	$BORG_TEMPMOUNT
		;;
	list)
		borg list $BORG_REPO -P $HOST
		;;
	list_all)
		borg list $BORG_REPO
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

if [ $1 == 'containers' ] || [ $1 == 'system' ]  || [ $1 == 'data' ]
then
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
fi


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

