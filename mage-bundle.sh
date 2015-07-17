#!/bin/bash

PWD=$(pwd)
KEY=$(wget -qO - http://pwgen.sonassi.com)
FILENAME="http_$KEY.tgz"
EXCLUDES=( "./var/log/*" "./var/cache/*" "./var/session/*" "./var/*port/*" "./var/tmp/*" "./media" "./errors/*" "./export/*" "./.git" "*.tar" "*.tgz" "*.gz" "*.bz2" "*.zip" "*.sql" "*.pdf" "*.mp3" "*.mp4" "*.mov" "*.avi" "./app/etc/local.xml" "./$FILENAME" )

echo -n "Please confirm you want to bundle ($PWD)  [y/N]: "
read CONFIRM
[[ ! "$CONFIRM" == "y" ]] && exit 1

function build_excludes()
{
  EXCLUDES_ALL=""
  for EXCLUDE in "${EXCLUDES[@]}"; do
    EXCLUDES_ALL="--exclude=$EXCLUDE $EXCLUDES_ALL"
  done
  echo $EXCLUDES_ALL
}

wget sys.sonassi.com/mage-dbdump.sh
bash mage-dbdump.sh
tar chvfz $PWD/$FILENAME $(build_excludes) . var/db.sql

cat << EOF
#######################################

 MYSQL DUMP & TAR COMPLETE

 Backup Location: $FILENAME

########################################
EOF

cat <<EOT
########################################

                                (_)
   ___  ___  _ __   __ _ ___ ___ _
  / __|/ _ \| '_ \ / _' / __/ __| |
  \__ \ (_) | | | | (_| \__ \__ \ |
  |___/\___/|_| |_|\__'_|___/___/_|


  Want truly optimised Magento hosting?

  Try http://www.sonassihosting.com ...

#########################################
EOT
