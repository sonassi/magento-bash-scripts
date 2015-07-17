#!/bin/bash

# SASS/Compass/Image tool

function usage()
{
cat << EOF
Usage:   $0 [OPTIONS]
Author:  www.sonassihosting.com

This script is used to auto-compile Compass SCSS and losslessly compress images, and auto-resize images.

REQUIREMENTS:
        compass
        inotifywait
        convert
        bc
        imgopt        See https://github.com/kormoc/imgopt

OPTIONS:
        -i            Image directory
        -w            Wach image directory for resize and optmise
        -c            Compass project directory
        -o            Optimise image directory
        -q            Image Quality (0-100)

EXAMPLES:
        -i /path/to/images/dir -w       - This will watch the dir for changes and losslessly compress
                                          any images created. It will also perform the auto-resize
                                          action that is carried out based on the image filename.

                                          Eg. myimage@2x.png - serves as an image at twice the normal
                                          resolution, so the script will create a new image myimage.png
                                          that is (100/2)% the resolution (50%).

                                          You can use other multipliers to achieve the desired result,
                                          myimage@4x.png - will create a new image myimage.png at 25%
                                          the resolution.

                                          This also works inversely, to allow for image resolution 
                                          increase. Use "@-[0-5]x" in place of "@[0-5]x". If you use
                                          @-2x, it will create a new image (100*2)% the resolution of
                                          the original (200%).

                                          The optmise command uses a series of tools (which must be 
                                          installed) to losslessly compress the image. The equivalent of
                                          Yahoo Y-SmushIt.

                                          The principle is that you upload the "higher" resolution image
                                          so that it creates the "normal" resolution image with the 
                                          standard filename


        -i /path/to/images/dir -o       - This will run a non-interactive version of the script and 
                                          merely optimise all images within the directory recursively.

        -c /path/to/compass/project     - This will mimic the "compass watch" functionality. It is only
                                          in this script to allow you to combine the image and SASS tools
                                          within a single 'watcher'

                                          This can be used in conjunction with -i and -w

        -d /path/to/image               - This is a special option to be used in conjunction with Nginx
                                          lua to create images on the fly. This is especially useful to
                                          render downsized images specifically for mobile devices by 
                                          passing in the same arguments as before.

                                          If you wish to use it with Nginx, use it in conjunction with 
                                          the following location directive (example)

                                          location ~* "@([+-][0-5](\.[0-9])?x|[0-9]+x[0-9]+)(q=[0-9]+)?\.(gif|jpg|jpeg|png)" {
                                            if (!-f $request_filename) {
                                              rewrite_by_lua 'os.execute("/bin/mage-watch.sh -d " .. ngx.var.request_filename .. "")';
                                            }
                                          }

                                          Then use the following URL examples,

                                          http://www.example.com/images/images@+5x.jpg
                                            - render 5x larger than the original of images.jpg

                                          http://www.example.com/images/images@-5x.jpg
                                            - render 5x smaller than the original of images.jpg    

                                          Adding q=[0-100] passes in an optional quality.

                                          There is no security built into this, so use at your own risk.

---------------------------------------------------------------------------------------------------------

A script built by Sonassi Hosting - the Magento Hosting specialists. Find us at www.sonassihosting.com

EOF
  exit
}

which imgopt > /dev/null 2>&1; IMGOPT=$?
COMPASS_BIN='/var/lib/gems/1.9.1/bin/compass'
QUALITY=90
#SHARPEN="-unsharp 0x1"
RESIZE_METHOD="-resize"
HOLD=0

function download_resize_image()
{
  image_args "$1"
  [ -f "$NEW_FILE" ] && convert "$NEW_FILE" -quality $QUALITY $SHARPEN $RESIZE_METHOD "$SIZE" "$FILE"
  echo convert "$NEW_FILE" -quality $QUALITY $SHARPEN $RESIZE_METHOD "$SIZE" "$FILE"
  optimise_image "$FILE"
  exit 0
}

function upload_resize_image()
{
  echo "$1" | grep -E "@[+-][0-5-]+x" > /dev/null 2>&1
  [ $? -eq 0 ] && echo -e "\e[00;31musage error\e[00m you shouldn't upload a file with the +/- syntax, this is only for browsers" && exit 0

  echo "$1" | grep -E "@[0-5-]+x" > /dev/null 2>&1
  [ ! $? -eq 0 ] && return

  MV_FILE=$(echo "$1" | sed -E "s#@([0-5])#@+\1#g")
  track_image "$MV_FILE"
  mv "$1" "$MV_FILE"
  optimise_image "$MV_FILE"
  image_args "$MV_FILE" invert
  convert "$FILE" -quality $QUALITY $SHARPEN $RESIZE_METHOD "$SIZE" "$NEW_FILE"
  echo -e "\e[01;36mresizing\e[00m  " $(basename $NEW_FILE) "to $SIZE"
  track_image "$NEW_FILE"
}

function image_args()
{
  FILE="$1"
  FILENAME=$(basename $FILE)

  I_QUALITY=$(echo $FILENAME | grep -Eoh "q=[0-9]([0-9])?\." | sed "s#q=##g;s#\.##g")
  QUALITY=${I_QUALITY:-$QUALITY}

  MULTIPLIER=$(echo "$FILENAME" | grep -Eoh "@[-+][0-5](.[0-9])?x")
  DIMENSIONS=$(echo "$FILENAME" | grep -Eoh "@[0-9]+x[0-9]+")

  if [[ ! "$MULTIPLIER" == "" ]]; then
    RATIO=$(echo $MULTIPLIER | sed -e "s#^@##g;s#^-##g;s#^\+##g;s#x\$##g")
    SIZE=$(echo "100/$RATIO" | bc)
    NEW_FILE=$(echo "$FILE" | sed "s#$MULTIPLIER##g;s#q=$I_QUALITY.#.#g")
    echo "$FILENAME" | grep -Eoh "@[+][0-5]x" > /dev/null 2>&1
    [ $? -eq 0 ] && [[ ! "$2" == "invert" ]] && RESIZE_METHOD="-adaptive-resize" && SIZE=$((100*$RATIO))
    SIZE="$SIZE%"
    return
  elif [[ ! "DIMENSIONS" == "" ]]; then
    SIZE=$(echo "$FILE" | grep -Eoh "[0-9]+x[0-9]+")
    NEW_FILE=$(echo "$FILE" | sed "s#$DIMENSIONS##g;s#q=$I_QUALITY.#.#g")
    return
  fi
  exit 0
}

function watch_compass()
{
  COMPASS_DIR="$1"
  #$compass watch $COMPASS_DIR/../
  ( inotifywait -q -r -m -e modify "$COMPASS_DIR" --format "%w %f %e" ) | while read DIR FILENAME EVENT; do
    $COMPASS_BIN compile $COMPASS_DIR/../
  done
}

function image_key()
{
  KEY=$(echo "$1" | md5sum - | cut -f"1" -d" ")
  echo "K_$KEY"
}

function track_image()
{
  [[ "$TRACK_LOG" == "" ]] && return
  KEY=$(image_key "$1")
  OFFSET=${2:-7200}
  VAL=$(( $(date +%s) + $OFFSET ))
  sed -i "/$KEY*/d" $TRACK_LOG
  echo "$KEY $VAL" >> $TRACK_LOG
}

function optimise_image()
{
  [ ! $IMGOPT -eq 0 ] && return
  IMG=$( imgopt "$1" 2> /dev/null | sed -e "s#^$DIR##g" )
  echo -e "\e[01;35moptimising\e[00m $IMG"
  track_image "$1" 5
}

function loop_prevent()
{
  KEY=$(image_key "$1")
  VAL=$(sed -n "/$KEY/p" $TRACK_LOG | cut -f2 -d" ")
  VAL=${VAL:-0}
  CURRENT_TIME=$(date +%s)
  [ $CURRENT_TIME -gt $VAL ] && return 0
  return 1
}

function watch_images()
{
  IMAGE_DIR="$1"

  # Image actions
  if [ -d "$IMAGE_DIR" ]; then
    ( inotifywait -q -r -m -e close_write "$IMAGE_DIR" --format "%w %f %e" --exclude "tmp\." ) | while read DIR FILENAME EVENT; do
      local FILE="$DIR$FILENAME"
      loop_prevent "$FILE"
      [ ! $? -eq 0 ] && continue
      track_image "$FILE"
      upload_resize_image "$FILE" &

      echo "$FILE" | grep -E "@[0-5-]+x" > /dev/null 2>&1
      [ ! $? -eq 0 ] && optimise_image "$FILE" &
    done
  fi
}

while getopts "q:c:i:d:ow" OPTION; do
  case $OPTION in
    \?)
      usage
      exit
      ;;
    q)
      QUALITY=$OPTARG
      ;;
    d)
      download_resize_image "$OPTARG"
      exit 0
      ;;  
    o)
      [[ ! "$OPT_i" == "" ]] && [ $IMGOPT -eq 0 ] && imgopt $OPT_i
      exit 0
      ;;
    c)
      watch_compass "$OPTARG/sass" &
      HOLD=1
      ;;
    w)
      TRACK_LOG=`mktemp -t tmp.XXXXXX` || return 1
      [[ ! "$OPT_i" == "" ]] && watch_images "$OPT_i" & 
      HOLD=1
      ;;
    *)
      [[ "$OPTARG" == "" ]] && OPTARG='"-'$OPTION' 1"'
      OPTION="OPT_$OPTION"
      eval ${OPTION}=$OPTARG
      ;;
  esac
done

[ $# -lt 1 ] && usage

if [ $HOLD -eq 1 ]; then
  trap '{ echo "Closing monitor" ; rm $TRACK_LOG; kill 0; exit 0; }' INT
  echo "Running in foreground. Press ctrl+c key to exit ..."
  while read LINE; do
    [[ "$LINE" == "q" ]] && break
  done
fi
