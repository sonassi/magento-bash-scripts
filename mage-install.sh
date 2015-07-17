#!/bin/bash

# magento_assets_url="http://www.magentocommerce.com/downloads/assets"
# $magento_assets_url/$sample_data_version/magento-sample-data-$sample_data_version.tar.gz
# $magento_assets_url/$VERS/magento-$VERS.tar.gz
# http://www.magentocommerce.com/downloads/assets/tools/magento-db-repair-tool-1.1.zip

function usage()
{
  cat <<EOF
$(basename $0) Usage:

$(basename $0) -r [magento release] -l [hostname] -u [username] -p [password] -n [database name] ((-s) -e [email] -w [url])

  Required

    -r [0-9.]+      Magento release (eg. 1.9.0.1)          
    -l hostname     Database server hostname (eg. db1.i)
    -u username     Database username
    -p password     Database password
    -n db name      Database name               

  Optional

    -s              With sample data

    Auto install - To complete installer and create admin user

    -w url          Store URL (eg. www.example.com)           
    -e email        Admin email (eg. info@example.com)

EOF
exit 0
}

function check_existence()
{
  wget --no-check-certificate -S --spider "$1" 2>&1 | grep -q "Remote file exists" && return 0
  return 1
}

function download_magento()
{
  URL="${MAGENTO_REPO}/archive/${RELEASE}.tar.gz"
  if ! check_existence $URL ; then
    echo "Error: Magento version ${RELEASE} could not be found"
    exit 1
  fi
  wget --no-check-certificate -qO latest-magento.tar.gz "${URL}"
}

function download_sample_data()
{
  URL="${SAMPLE_DATA_REPO}/archive/${SAMPLE_DATA_VERSION}.tar.gz"
  if ! check_existence $URL ; then
    echo "Error: Magento sample data ${SAMPLE_DATA_VERSION} could not be found"
    exit 1
  fi
  wget --no-check-certificate -qO latest-sample-data.tar.gz "${URL}"
}

DOWNLOAD_ONLY=0
SAMPLE_DATA=0
FORCE=0
MAGENTO_REPO="https://github.com/sonassi/magento-ce"
SAMPLE_DATA_REPO="https://github.com/sonassi/magento-sample-data"
RELEASE=
DBHOST=
DBUSER=
DBNAME=
DBPASS=
STORE_URL=
ADMIN_EMAIL=

while getopts "r:e:w:l:n:p:u:dshf" OPTION; do
  case $OPTION in
    d)
      DOWNLOAD_ONLY=1
      ;;
    r)
      RELEASE="$OPTARG"
      ;;
    l)
      DBHOST="$OPTARG"
      ;;
    u)
      DBUSER="$OPTARG"
      ;;    
    n)
      DBNAME="$OPTARG"
      ;;      
    p)
      DBPASS="$OPTARG"
      ;;  
    w)
      STORE_URL="$OPTARG"
      ;;     
    e)
      ADMIN_EMAIL="$OPTARG"
      ;;     
    s)
      SAMPLE_DATA=1
      ;;
    f)
      FORCE=1
      ;;
    h)
      usage
  esac
done

MYSQL_CONNECT="-h$DBHOST -u$DBUSER -p$DBPASS"

if [ $DOWNLOAD_ONLY -eq 1 ] && [[ ! "$RELEASE" == "" ]]; then
  echo "Downloading Magento ${RELEASE} ..."
  download_magento
  exit 0
fi

if [[ "$RELEASE" == "" ]] ||
   [[ "$DBHOST" == "" ]]
   [[ "$DBUSER" == "" ]]
   [[ "$DBPASS" == "" ]]
   [[ "$DBNAME" == "" ]]; then
   echo "Error: Insufficient arguments provided"
   exit 1
fi

# Work out what version of sample data we need
if [[ $RELEASE > 1.9.0.0 ]] || [[ "$RELEASE" == "1.9.0.0" ]]; then
  SAMPLE_DATA_VERSION="1.9.0.0-lite"
elif [[ $RELEASE > 1.6.1.0 ]] || [[ "$RELEASE" == "1.6.1.0" ]]; then
 SAMPLE_DATA_VERSION="1.6.1.0"
else
  SAMPLE_DATA_VERSION="1.2.0"
fi

# Sanity check MySQL works
MYSQL_VERSION=$(mysql $MYSQL_CONNECT -Nsre "SHOW VARIABLES LIKE 'version';" 2>&1 | grep -Eohm1 '([0-9.]+|ERROR)')
if [[ "$MYSQL_VERSION" == "ERROR"* ]]; then
  echo "Error: Could not establish a database connection"
  exit 1
fi

# If MySQL is <5.1 then use a modified version of the sample data
if [[ $MYSQL_VERSION < 5.1 ]] && [[ $SAMPLE_DATA_VERSION == "1.6.1.0" ]] && [ $SAMPLE_DATA -eq 1 ]; then
  SAMPLE_DATA_VERSION="${SAMPLE_DATA_VERSION}-fix"
fi

CURRENT_DIR=$(pwd)
ADMIN_PASS=$(wget -qO- http://pwgen.sonassi.com)

[ $FORCE -eq 0 ] && read -p "Do you really want to install in $CURRENT_DIR [y/N]: " ANSWER
[[ ! "$ANSWER" == "y" ]] && [ $FORCE -eq 0 ] && exit 1

echo -e "\nStarting installation, please wait\n"

# Download Magento
echo -n "  >> Downloading Magento $RELEASE ..."
[ -f latest-magento.tar.gz ] || download_magento
(
  tar zxf latest-magento.tar.gz 
  rsync -a magento-ce-$RELEASE/ $CURRENT_DIR/ --exclude="magento-ce-$RELEASE"
) &

# Download sample data
if [ $SAMPLE_DATA -eq 1 ]; then
  [ -f latest-sample-data.tar.gz ] || download_sample_data
  ( 
    tar zxf latest-sample-data.tar.gz
    rsync -a magento-sample-data-$SAMPLE_DATA_VERSION/media/ $CURRENT_DIR/media/
    mv magento-sample-data-$SAMPLE_DATA_VERSION/*.sql $CURRENT_DIR/data.sql
  ) &
fi

wait
echo " Done"

chmod -R 775 $CURRENT_DIR

if [ $SAMPLE_DATA -eq 1 ]; then
  echo -n "  >> Importing sample data ..."
  mysql $MYSQL_CONNECT $DBNAME < data.sql
  echo "Done"
fi

echo -n "  >> Setting up Mage ..."
if [[ $RELEASE > 1.5 ]]; then
  ./mage mage-setup . >/dev/null 2>&1
else
  ./pear mage-setup . >/dev/null 2>&1
  ./pear install magento-core/Mage_All_Latest-stable >/dev/null 2>&1
fi
echo " Done"

echo -n "  >> Cleaning up ..."
rm -rf $CURRENT_DIR/magento-ce-$RELEASE \
       $CURRENT_DIR/latest-magento.tar.gz \
       $CURRENT_DIR/magento-sample-data-$SAMPLE_DATA_VERSION \
       $CURRENT_DIR/latest-sample-data.tar.gz \
       $CURRENT_DIR/data.sql \
       $CURRENT_DIR/downloader/pearlib/cache/* \
       $CURRENT_DIR/downloader/pearlib/download/* \
       $CURRENT_DIR/mage-install.sh
echo " Done"

if [[ ! "$STORE_URL" == "" ]] &&
   [[ ! "$ADMIN_EMAIL" == "" ]]; then

  echo -n "  >> Installing Magento ..."
  php -f install.php -- \
  --license_agreement_accepted "yes" \
  --locale "en_GB" \
  --timezone "Europe/London" \
  --default_currency "GBP" \
  --db_host "$DBHOST" \
  --db_name "$DBNAME" \
  --db_user "$DBUSER" \
  --db_pass "$DBPASS" \
  --url "$STORE_URL" \
  --skip_url_validation \
  --use_rewrites "yes" \
  --use_secure "no" \
  --secure_base_url "" \
  --use_secure_admin "no" \
  --admin_firstname "Admin" \
  --admin_lastname "User" \
  --admin_email "$ADMIN_EMAIL" \
  --admin_username "$ADMIN_EMAIL" \
  --admin_password "$ADMIN_PASS" 1>/dev/null
  echo " Done"

  echo -n "  >> Removing admin notifications ..."
  mysql $MYSQL_CONNECT -e "DELETE FROM $DBNAME.adminnotification_inbox;"  >/dev/null 2>&1
  echo " Done"

  if [ -f "/microcloud/scripts_ro/magerun_install.sh" ]; then
    echo -n "  >> Installing magerun ..."
    /microcloud/scripts_ro/magerun_install.sh >/dev/null 2>&1
    . ~/.bash_profile
    mr_examplecom index:reindex:all >/dev/null 2>&1
    mr_examplecom cache:flush >/dev/null 2>&1
    echo "Done"
  fi

cat > .credentials.cnf <<EOF

Installation complete

  Admin Url     : $STORE_URL/admin
  Admin Username: $ADMIN_EMAIL
  Admin Password: $ADMIN_PASS
EOF

cat .credentials.cnf

fi

cat <<EOF

########################################

                                (_)
   ___  ___  _ __   __ _ ___ ___ _
  / __|/ _ \| '_ \ / _' / __/ __| |
  \__ \ (_) | | | | (_| \__ \__ \ |
  |___/\___/|_| |_|\__'_|___/___/_|


  Want truly optimised Magento hosting?

  Try http://www.sonassihosting.com ...

EOF
