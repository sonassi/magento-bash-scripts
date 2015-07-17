#!/bin/bash

IGNORE_TABLES=( dataflow_batch_export dataflow_batch_import log_customer log_quote log_summary log_summary_type log_url log_url_info log_visitor log_visitor_info log_visitor_online report_event index_event enterprise_logging_event_changes core_cache core_cache_tag core_session core_cache_tag )
IGNORE_TABLES_AGGRESSIVE=( report_compared_product_index report_viewed_product_index sales_flat_quote_address sales_flat_quote_shipping_rate enterprise_customer_sales_flat_quote enterprise_customer_sales_flat_quote_address sales_flat_quote )
TRUNCATE_TABLES=( dataflow_batch_export dataflow_batch_import log_customer log_quote log_summary log_summary_type log_url log_url_info log_visitor log_visitor_info log_visitor_online report_viewed_product_index report_compared_product_index report_event index_event index_process_event )
CONFIG_FILE="./app/etc/local.xml"
DUMP_FILE="./var/db.sql"

function usage()
{
cat <<EOF
Usage:     $0 [OPTIONS]
Version:   1.03
Author:    www.sonassihosting.com
Download:  sys.sonassi.com/mage-dbdump.sh

This script is used to dump or restore Magento databases by reading
the local.xml file and parsing the DB credentials. It strips out
superfluous data (logs etc.) for smaller and quicker dumps. It also
optimises the dump by avoiding locks where possible.

Dumps to $DUMP_FILE(.gz)

If you have pigz installed, it will use that over gzip for parallel
compression/de-compression.

OPTIONS:
      -a             Advertise awesome hosting
      -d             Dump the database
      -r             Restore the databse
      -z             Use gzip compression (use with -d or -r)
      -e             Use extended inserts
      -h             Show help/usage
      -f             Full dump, do not exclude any tables
      -A             Aggressive dump, exclude (${IGNORE_TABLES_AGGRESSIVE[@]})
      -B             Exclude additional custom tables (space separated, within "double quotes")
      -F             Do not ask questions and force all actions
      -i             Interactive, enter a mysql> prompt
      -c             Clean log and index tables

EOF
}

function error()
{
  echo -e "Error: $1"
  [[ ! "$2" == "noexit" ]] && exit 1
}

function getParam()
{
  RETVAL=$(grep -Eoh "<$1>(<!\[CDATA\[)?(.*)(\]\]>)?<\/$1>" $TMP_FILE | sed "s#<$1><!\[CDATA\[##g;s#\]\]><\/$1>##g")
  if [[ "$2" == "sanitise" ]]; then
    RETVAL=$(echo "$RETVAL" | sed 's/"/\\\"/g')
  fi
  echo -e "$RETVAL"
}

function compress()
{
  while read DATA; do
    [[ ! "$OPT_z" == "" ]] && (echo "$DATA" | $GZIP_CMD -) || echo "$DATA"
  done
}

function mysqldumpit()
{

  if [[ "$OPT_f" == "" ]]; then
    [[ ! "$OPT_A" == "" ]] && IGNORE_TABLES=( ${IGNORE_TABLES[@]} ${IGNORE_TABLES_AGGRESSIVE[@]} )
    [[ ! "$OPT_B" == "" ]] && IGNORE_TABLES=( ${IGNORE_TABLES[@]} $OPT_B )
    for TABLE in "${IGNORE_TABLES[@]}"; do
      IGNORE_STRING="$IGNORE_STRING --ignore-table=$DBNAME.$TABLE_PREFIX$TABLE"
    done
  fi

  # We use --single-transaction in favour of --lock-tables=false , its slower, but less potential for unreliable dumps
  echo "SET SESSION sql_mode='NO_AUTO_VALUE_ON_ZERO';"
  ( mysqldump -p"$DBPASS" $MYSQL_ARGS --no-data --routines --triggers --single-transaction; \
      mysqldump -p"$DBPASS" $MYSQL_ARGS $IGNORE_STRING --no-create-db --single-transaction ) | sed 's/DEFINER=[^*]*\*/\*/g'
}

function question()
{
  [[ ! "$OPT_F" == "" ]] && return 0
  echo -n "$1 [y/N]: "
  read CONFIRM
  [[ "$CONFIRM" == "y" ]] || [[ "$CONFIRM" == "Y" ]] && return 0
  return 1
}

function message()
{
  STRIP=$(for i in {1..38}; do echo -n "#"; done)
  echo -e "$STRIP\n$1\n$STRIP"
}

function banner()
{
cat <<EOT
######################################

                              (_)
 ___  ___  _ __   __ _ ___ ___ _
/ __|/ _ \| '_ \ / _' / __/ __| |
\__ \ (_) | | | | (_| \__ \__ \ |
|___/\___/|_| |_|\__'_|___/___/_|

For truly optimised Magento hosting
Use http://www.sonassihosting.com ...

#####################################

EOT
}

[ ! -f "$CONFIG_FILE" ] && error "$CONFIG_FILE does not exist"

while getopts "B:AdrzehfFaic" OPTION; do
  case $OPTION in
    a)
      banner
      exit 0
      ;;
    h)
      usage
      exit 0
      ;;
    :)
      error "Error: -$OPTION requires an argument" noexit
      exit 1
      ;;
    \?)
      error "Error: Unknown option -$OPTION" noexit
      exit 1
      ;;
    *)
      [[ "$OPTARG" == "" ]] && OPTARG='"-'$OPTION' 1"'
      OPTION="OPT_$OPTION"
      eval ${OPTION}=$OPTARG
      ;;
  esac
done

[[ "$OPT_c$OPT_i$OPT_d$OPT_r" == "" ]] && usage && exit 1

which mktemp >/dev/null 2>&1
[ $? -eq 0 ] && TMP_FILE=$(mktemp ./var/local.xml.XXXXX) || TMP_FILE="./var/.tmp.local.xml"
sed -ne '/default_setup/,/\/default_setup/p' $CONFIG_FILE > $TMP_FILE

which pigz >/dev/null 2>&1
[ $? -eq 0 ] && GZIP_CMD="pigz" || GZIP_CMD="gzip"

IGNORE_STRING=""
DBHOST=$(getParam "host")
DBUSER=$(getParam "username")
DBPASS=$(getParam "password" "sanitise" )
DBNAME=$(getParam "dbname")
TABLE_PREFIX=$(getParam "table_prefix")
[ -f $TMP_FILE ] && rm $TMP_FILE
[[ ! "$OPT_z" == "" ]] && DUMP_FILE="$DUMP_FILE"".gz"

MYSQL_ARGS="-f -h $DBHOST -u $DBUSER $DBNAME"
[[ ! "$OPT_e" == "" ]] && MYSQL_ARGS="$MYSQL_ARGS --extended-insert=FALSE --complete-insert=TRUE"

if [[ ! "$OPT_r" == "" ]]; then

  [ ! -f "$DUMP_FILE" ] && error "SQL file does not exist"
  question "Are you sure you want to restore $DUMP_FILE to $DBNAME?"
  if [ $? -eq 0 ]; then
    [[ ! "$OPT_z" == "" ]] && $GZIP_CMD -d <$DUMP_FILE | mysql $MYSQL_ARGS -p"$DBPASS" || mysql $MYSQL_ARGS -p"$DBPASS" <$DUMP_FILE
    message "MYSQL IMPORT COMPLETE"
    banner
  fi
  exit 0

elif [[ ! "$OPT_c" == "" ]]; then

  for TABLE in ${TRUNCATE_TABLES[@]}; do
    echo "Cleaning $TABLE ..."
    mysql $MYSQL_ARGS -p"$DBPASS" -e "TRUNCATE ${TABLE_PREFIX}$TABLE"
  done

elif [[ ! "$OPT_i" == "" ]]; then

  mysql $MYSQL_ARGS -p"$DBPASS"

elif [[ ! "$OPT_d" == "" ]]; then

  [[ ! "$OPT_z" == "" ]] && mysqldumpit | $GZIP_CMD > $DUMP_FILE || mysqldumpit > $DUMP_FILE
  message "MYSQL DUMP COMPLETE"
  exit 0

fi
