#!/bin/bash
PATH=/usr/local/sbin:/usr/sbin:/sbin:/usr/local/bin:/usr/bin:/bin

## Usage (after configuration):
## 1. Insert camera's memory card into a USB port on your unRAID system
## 2. The system will automatically move (or copy) any images/videos from the memory card to the array
##    If jhead was installed, it will automatically rotate images according to the exif data
## 3. Wait for the imperial theme to play, then remove the memory card

## Preparation:
## 1. Install jhead (to automatically rotate photos) using the Nerd Pack plugin
## 2. Install the "Unassigned Devices" plugin
## 3. Use that plugin to set this script to run *in the background* when a memory card is inserted
## 4. Configure variables in this script as described below

## Warning:
## The newperms script has a bug in unRAID 6.1.3 - 6.1.7
## see https://lime-technology.com/forum/index.php?topic=43388.0

## --- BEGIN CONFIGURATION ---

## SET THIS FOR YOUR CAMERAS: 
## array of directories under /DCIM/ that contain files you want to move (or copy)
## can contain regex
VALIDDIRS=("/DCIM/[0-9][0-9][0-9]___[0-9][0-9]" "/DCIM/[0-9][0-9][0-9]CANON" "/DCIM/[0-9][0-9][0-9]_FUJI" "/DCIM/[0-9][0-9][0-9]NIKON" \
"/DCIM/[0-9][0-9][0-9]MSDCF" "/DCIM/[0-9][0-9][0-9]OLYMP" "/DCIM/[0-9][0-9][0-9]MEDIA" "/DCIM/[0-9][0-9][0-9]GOPRO" "/DCIM/[0-9][0-9][0-9]_PANA")

## SET THIS FOR YOUR SYSTEM:
## location to move files to. use date command to ensure unique dir
DESTINATION_ROOT="/mnt/user/priority/video"

## SET THIS FOR YOUR SYSTEM:
## location to move files to. use date command to ensure unique dir
DESTINATION="${DESTINATION_ROOT}/photo_import/$(date +"%Y-%m-%d-%H-%M-%S-%N")/"

## location of mmt config yaml
MMT_CONFIG="/boot/config/plugins/unassigned.devices/mmt-auto-import.yaml"

## SET THIS FOR YOUR SYSTEM:
## change to "move" when you are confident everything is working. Default value "copy"
MOVE_OR_COPY="move"

## set this to 1 and check the syslog for additional debugging info
DEBUG="1"

## Available variables: 
# AVAIL      : available space
# USED       : used space
# SIZE       : partition size
# SERIAL     : disk serial number
# ACTION     : if mounting, ADD; if unmounting, REMOVE
# MOUNTPOINT : where the partition is mounted
# FSTYPE     : partition filesystem
# LABEL      : partition label
# DEVICE     : partition device, e.g /dev/sda1
# OWNER      : "udev" if executed by UDEV, otherwise "user"
# PROG_NAME  : program name of this script
# LOGFILE    : log file for this script

log_all() {
  log_local "$1"
  logger "$PROG_NAME-$1"
}

log_local() {
  echo "`date` $PROG_NAME-$1"
  echo "`date` $PROG_NAME-$1" >> $LOGFILE
}

log_debug() {
  if [ ${DEBUG} ]
  then
    log_local "$1"
  fi
}

beep_imperial() {
  for i in $(seq 1 ${1}); do
    beep -f 392 -l 450 -r 3 -D 150 -n -f 311.13 -l 400 -D 50 \
    -n -f 466.16 -l 100 -D 50 -n -f 392 -l 500 -D 100 \
    -n -f 311.13 -l 400 -D 50 -n -f 466.16 -l 100 -D 50 \
    -n -f 392 -l 600 -D 600 -n -f 587.33 -l 450 -r 3 -D 150 \
    -n -f 622.25 -l 400 -D 50 -n -f 466.16 -l 100 -D 50 \
    -n -f 369.99 -l 500 -D 100 -n -f 311.13 -l 400 -D 50 \
    -n -f 466.16 -l 100 -D 50 -n -f 392 -l 500 -D 100
    sleep 2
  done
}

case $ACTION in
  'ADD' )
    #
    # Beep that the device is plugged in.
    #
    beep  -l 200 -f 600 -n -l 200 -f 800
    sleep 2

    if [ -d ${MOUNTPOINT} ]
    then
      # only process an automount. manual mount is messy, users may or may not expect it to unmount afterwards
      if [ "$OWNER" = "udev" ]; then
        log_all "Started"
        log_debug "Logging to $LOGFILE"

	log_debug "Using mmt to copying GoPro media file to organised structure under output path defined in ${MMT_CONFIG}"
	log_debug "mmt gopro config: ${MMT_CONFIG_GOPRO}"
	mmt import --config "${MMT_CONFIG_GOPRO}" --input "${MOUNTPOINT}" --date "yyyy-mm-dd" --camera "gopro" --prefix "GoPro_" | (head -n 10; tail -n 1000)

  log_debug "Using mmt to copying DJI media file to organised structure under output path defined in ${MMT_CONFIG}"
  log_debug "mmt gopro config: ${MMT_CONFIG_DJI}"
	mmt import --config "${MMT_CONFIG_DJI}" --input "${MOUNTPOINT}" --date "yyyy-mm-dd" --camera "dji" --prefix "DJI_"  | (head -n 10; tail -n 1000)
	log_debug "Finished copying media file to organised structure under output path defined in ${MMT_CONFIG}"

        RSYNCFLAG=""
        MOVEMSG="copying"
        if [ ${MOVE_OR_COPY} == "move" ]; then
          RSYNCFLAG=" --remove-source-files "
          MOVEMSG="moving"
        fi

        # only operate on USB disks that contain a /DCIM directory, everything else will simply be mounted
        if [ -d "${MOUNTPOINT}/DCIM" ]; then
          log_debug "DCIM exists ${MOUNTPOINT}/DCIM"

          # loop through all the subdirs in /DCIM looking for dirs defined in VALIDDIRS
          for DIR in ${MOUNTPOINT}/DCIM/*; do
            if [ -d "${DIR}" ]; then
              log_debug "checking ${DIR}"
              for element in "${VALIDDIRS[@]}"; do
                if [[ ${DIR} =~ ${element} ]]; then
                  # process this dir
                  log_local "${MOVEMSG} ${DIR}/ to ${DESTINATION}"
                  rsync -a ${RSYNCFLAG} "${DIR}/" "${DESTINATION}"
                  # remove empty directory from memory card
                  if [ ${MOVE_OR_COPY} == "move" ]; then
                    rmdir ${DIR}
                  fi
                fi
              done
            fi
          done

          # files were moved (or copied).  rotate images, fix permissions
          if [ -d "${DESTINATION}" ]; then

            if [ -e "/usr/bin/jhead" -a -e "/usr/bin/jpegtran" ] && [[ $(find "${DESTINATION}"  -name "*.[jJ][pP][gG]") ]]; then
              log_debug "running jhead on ${DESTINATION}"
              jhead -autorot -ft "${DESTINATION}"*.[jJ][pP][gG]
            fi

            log_debug "fixing permissions on ${DESTINATION}"
            newperms "${DESTINATION}"

          fi

          # sync and unmount USB drive
          sync -f ${DESTINATION}
          sync -f ${MOUNTPOINT}
          sleep 1
          /usr/local/sbin/rc.unassigned umount $DEVICE

          # send notification
          beep_imperial 1
          /usr/local/emhttp/webGui/scripts/notify -e "unRAID Server Notice" -s "Media Management Tool Import" -d "MMT Import completed for ${MOUNTPOINT}" -i "normal"

        fi  # end check for DCIM directory

      else
        log_all "Media Manager Import drive not processed, owner is $OWNER"
      fi  # end check for valid owner
    else
      log_all "Mount point doesn't exist ${MOUNTPOINT}"
    fi  # end check for valid mountpoint
  ;;

  'REMOVE' )
    #
    # Beep that the device is unmounted.
    #
    beep  -l 200 -f 800 -n -l 200 -f 600

    log_all "Media Manager Import drive unmounted, can safely be removed"
  ;;
esac
