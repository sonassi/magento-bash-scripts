#!/bin/bash

CONFIG_FILE="./app/etc/local.xml"
TMP_FILE="./var/.tmp.local.xml"
DUMP_STRING=""

if [ ! -f "$CONFIG_FILE" ]; then
  echo "$CONFIG_FILE does not exist"
  exit
fi

sed -ne '/default_setup/,/\/default_setup/p' $CONFIG_FILE > $TMP_FILE

function getParam()
{
  RETVAL=$(grep -Eoh "<$1>(<!\[CDATA\[)?(.*)(\]\]>)?<\/$1>" $TMP_FILE | sed "s#<$1><!\[CDATA\[##g;s#\]\]><\/$1>##g")
	if [[ "$2" == "sanitise" ]]; then
	  RETVAL=$(echo "$RETVAL" | sed 's/"/\\\"/g')
	fi
echo -e "$RETVAL"
}


DBHOST=$(getParam "host")
DBUSER=$(getParam "username")
DBPASS=$(getParam "password" "sanitise" )
DBNAME=$(getParam "dbname")
TABLE_PREFIX=$(getParam "table_prefix")

[ -f $TMP_FILE ] && rm $TMP_FILE

echo "The database selected is: $DBNAME"
echo -n "Are you sure you want to purge? [y/N]: "
read CONFIRM; if [[ ! "$CONFIRM" == "y" ]]; then echo "You dodged a bullet there!"; exit; fi

echo -n "Last chance, are you 110% sure you want to purge $DBNAME? [y/N]: "
read CONFIRM; if [[ ! "$CONFIRM" == "y" ]]; then echo "You dodged a bullet there!"; exit; fi

TABLES=( $(mysql -h$DBHOST -u$DBUSER -p"$DBPASS" $DBNAME -e 'show tables' | awk '{ print $1}' | grep -v '^Tables' ) )

for TABLE in ${TABLES[@]}; do
  DUMP_STRING="SET FOREIGN_KEY_CHECKS=0; DROP VIEW $TABLE; SET FOREIGN_KEY_CHECKS=1;"
  mysql --force -h"$DBHOST" -u"$DBUSER" -p"$DBPASS" $DBNAME -e "$DUMP_STRING"
  DUMP_STRING="SET FOREIGN_KEY_CHECKS=0; DROP TABLE $TABLE; SET FOREIGN_KEY_CHECKS=1;"
  mysql --force -h"$DBHOST" -u"$DBUSER" -p"$DBPASS" $DBNAME -e "$DUMP_STRING"
done

cat <<EOT
#######################################

 MYSQL DB PURGE COMPLETE

#######################################
EOT

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
