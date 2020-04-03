#!/bin/bash

#force the use of root home folder for configuration files
export HOME=/root
WGET_CREDENTIALS="/root/.wgetrc"

# check if we are the only local instance
if [[ "`pidof -x $(basename $0) -o %PPID`" ]]; then
        echo "This script is already running with PID `pidof -x $(basename $0) -o %PPID`" >> "${LOG}"
        exit
fi

# Check for root permissions
if [[ $EUID -ne 0 ]]; then
  echo -e "$0 requires root privledges.\n"
  echo -e "sudo $0 $*\n"
  exit 1
fi

#create log folder if not present
if [ ! -f $WGET_CREDENTIALS ]; then
	echo "Credentials file /root/.wgetrc missing"
fi

case "$1" in
	containers | system | data | list | rsync | keys_export)
		SCRIPTNAME="borg_backup.sh"
		#uses credentials in file $HOME/.wgetrc
		#-nv not verbose
		#-N only if new download
		wget -Nnv https://u225102.your-storagebox.de/appdata/borgbackup/$SCRIPTNAME && bash $SCRIPTNAME $1; rm -f $SCRIPTNAME
		;;
	*)
		echo $"Usage: $0 {containers|system|data|rsync|key_export}"
		exit 1
		;;
esac

