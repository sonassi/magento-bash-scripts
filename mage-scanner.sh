#!/bin/bash

[ ! -f "app/Mage.php" ] && echo "Error: This does not appear to be a Magento installation" && exit 1

# Identify current Magento version
MAGE_VERSION=$(php -r "require 'app/Mage.php'; echo Mage::getVersion();")

# Download clean Magento source
wget -q sys.sonassi.com/mage-install.sh -O mage-install.sh >/dev/null 2>&1
bash mage-install.sh -d -r $MAGE_VERSION
tar zxf latest-magento.tar.gz

# Disable the compiler
[ -f "includes/config.php" ] && mv includes/config{.php,.disabled.php}

# Look for common methods used to comprimise a Magento installation
COMPRIMISE_METHODS="eval|ord|chr|gzflate|gzinflate|base64_encode|base64_decode"
COMPRIMISE_METHODS_REV=$(echo "$COMPRIMISE_METHODS" | rev)
SCAN_PATH="app lib"

CORE_MODIFICATIONS=()
MISSING_FROM_CORE=()

while read FILE; do
  if [ ! -f  "magento-ce-$MAGE_VERSION/$FILE" ]; then
    MISSING_FROM_CORE+=( "$FILE" )
  else
    diff --brief -bB "$FILE" "magento-ce-$MAGE_VERSION/$FILE" >/dev/null 2>&1 || CORE_MODIFICATIONS+=( "$FILE" )
  fi
done < <(grep -lirE "($COMPRIMISE_METHODS|$COMPRIMISE_METHODS_REV|strrev)([\t\n\r ]+)?\(" $SCAN_PATH)

if [ ${#MISSING_FROM_CORE[@]} -gt 0 ]; then
cat <<EOF

###########################
#    MISSING FROM CORE    #
###########################

The following files are not present in the Magento core, they could
form part of your custom theme or modules. However, there is no clean
version to compare these files to, so manual verification is recommended

EOF
  for WARNING in "${MISSING_FROM_CORE[@]}"; do
    echo "  $WARNING"
  done
fi

if [ ${#CORE_MODIFICATIONS[@]} -gt 0 ]; then
cat <<EOF

#############################
#    MODIFIED CORE FILES    #
#############################

The following core files have been modified. These edits could be from
part of your regular store development (although editing the core is
not a recommended practice), or they could be comprimised files.

EOF
  for WARNING in "${CORE_MODIFICATIONS[@]}"; do
    echo "  $WARNING"
  done
fi

