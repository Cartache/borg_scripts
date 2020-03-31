#!/bin/bash

LOG="/var/log/borg/backup.log"

# check if we are the only local instance
if [[ "`pidof -x $(basename $0) -o %PPID`" ]]; then
        echo "This script is already running with PID `pidof -x $(basename $0) -o %PPID`" >> "${LOG}"
        exit
fi

## Backup ratio
## Value between 1 and 22 
## Highest but lowest = 22

# some helpers and error handling:
info() { printf "\n%s %s\n\n" "$( date )" "$*" >&2; }
trap 'echo $( date ) Backup interrupted >&2; exit 2' INT TERM

export BORG_PASSPHRASE="Cannon_Underwire_Tactical_Pending_Bonanza_Constant_Glove_Dreadlock_Resigned_Jiffy" 	#Std Variable
export BORG_RSH='ssh -i /opt/borgbackup/.ssh/id_rsa'														#Std Variable
export BORG_REPO="ssh://u225102@u225102.your-storagebox.de:23/./backup/containers"							#Std Variable
export BORG_EXCLUDE="/opt/borgbackup/exclude_containers.lst"												#My Variable


##
## Output to a logfile
##

exec > >(tee -i $LOG)
exec 2>&1

# get all running docker container names
#SRCNAMES=$(sudo docker ps | awk '{if(NR>1) print $NF}')
SRCNAMES="filezilla"
HOST=$(hostname)

echo "###### Backup started: ######"
echo $( date )
echo "Backuping up ${HOST} containers" 

# loop through all running containers
for SRCNAME in $SRCNAMES
do
	docker stop $SRCNAME
	echo "Backuping up ${SRCNAME}"
	sleep 5
	borg create 									\
				--compression zstd,15 				\
				--verbose 							\
				--filter AME 						\
				--list 								\
				--stats 							\
				--show-rc 							\
				--exclude-caches 					\
				--exclude-from $BORG_EXCLUDE 		\
				$BORG_REPO::"$HOST-$SRCNAME-{now}" 	\
				/opt/appdata/$SRCNAME
	docker start $SRCNAME
done

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

