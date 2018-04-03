#!/bin/bash

################################################################################
# Batch script to move the saved Docker Hub image files
#
# grahamnscp	April 2018	Initial version
#
################################################################################

trap control_c SIGINT

##############################################
# Variables
##############################################
LOGDIR=/var/log/get-repos-batch
DOCKER_IMAGE_SAVE_DIR=/var/tmp/saved_images
DOCKER_IMAGE_MOVE_DIR=/var/tmp/moved_images
#
DATE=`/bin/date +'%Y%m%d'`
TIME=`/bin/date +'%H%M'`
LOGFILE=$LOGDIR/move-image-files-batch-log-${DATE}-${TIME}.log
ERRORLOGFILE=$LOGDIR/move-image-files-batch-log-${DATE}-${TIME}.errorlog
MAXLOGS=4


##############################################
# Functions 
##############################################
control_c()
{
  /usr/bin/echo -en "\n!Control-C Interrupt, exiting..\n"
  /usr/bin/rm -rf $EXPORT_WORK_DIR
  exit 1
}


checkmk_logdir () {
  if [ ! -d "$LOGDIR" ]; then
    /usr/bin/mkdir -p $LOGDIR
  fi
}


checkmk_dockerimagesavedir () {
  if [ ! -d "$DOCKER_IMAGE_SAVE_DIR" ]; then
    logmsg "ERROR: Image files directory does not exist; '$DOCKER_IMAGE_SAVE_DIR', exiting.."
    errorlogmsg "ERROR: Image files directory does not exist; '$DOCKER_IMAGE_SAVE_DIR', exiting.."
    exit 1
  fi
}


checkmk_dockerimagemovedir () {
  if [ ! -d "$DOCKER_IMAGE_MOVE_DIR" ]; then
    /usr/bin/mkdir -p $DOCKER_IMAGE_MOVE_DIR
  fi
}

logmsg () {
  /usr//bin/echo `date +'%Y%m%d-%H:%M:%S'` "[move-image-files-batch] $1" | tee -a $LOGFILE
}


errorlogmsg () {
  /usr/bin/echo `date +'%Y%m%d-%H:%M:%S'` "[move-image-files-batch] $1" >> $ERRORLOGFILE
}

purge_log_files () {
  # don't purge out the .errorlog files
  SYNCLOGS=`/usr/bin/ls -l $LOGDIR | /usr//bin/grep $1 | /usr/bin/grep -v ".errorlog" | /usr/bin/wc -l`
  if [ $SYNCLOGS -gt $MAXLOGS ]
  then
    while [ $SYNCLOGS -gt $MAXLOGS ]; do
      OLDESTLOG=`/usr/bin/ls -cltrh $LOGDIR | /usr/bin/grep $1 | /usr/bin/grep -v ".errorlog" | /usr/bin/head -1 | /usr/bin/awk '{print $9}'`
      logmsg "MAXLOGS=$MAXLOGS, purging $LOGDIR/$OLDESTLOG"
      /usr/bin/rm -rf $LOGDIR/$OLDESTLOG
      SYNCLOGS=`/usr/bin/ls -l $LOGDIR | /usr/bin/grep $1 | /usr/bin/grep -v ".errorlog" | /usr/bin/wc -l`
    done
  fi
}


##############################################
# Main
##############################################
logmsg "Started.."
logmsg "Logfile is '$LOGFILE'"

TIME_START=`date +"%s"`

checkmk_logdir
checkmk_dockerimagesavedir
checkmk_dockerimagemovedir

# Check for flag file before processing, only exists if new images pulled and saved
# maybe the image pulls have not completed yet?, or get-repos batch failed?, so exit
if [ ! -f $DOCKER_IMAGE_SAVE_DIR/last_exported_images_list ]
then
  logmsg "WARNING: Flag file not present; '$DOCKER_IMAGE_SAVE_DIR/last_exported_images_list', no work to do, exiting"
  exit 0
fi

# Move images to moved_images folder for onward processing
TAR_FILES_PRESENT=0
for i in $DOCKER_IMAGE_SAVE_DIR/*.tar; do test -f "$i" && TAR_FILES_PRESENT=1  && break; done
if [ ! $TAR_FILES_PRESENT -eq 0 ]
then
  logmsg "Moving image files from '$DOCKER_IMAGE_SAVE_DIR/' to '$DOCKER_IMAGE_MOVE_DIR/'.."
  /usr/bin/mv $DOCKER_IMAGE_SAVE_DIR/*.tar $DOCKER_IMAGE_MOVE_DIR/
  /usr/bin/mv $DOCKER_IMAGE_SAVE_DIR/last_exported_images_list $DOCKER_IMAGE_MOVE_DIR/

  # ------->>>>> Further file processing here as required <<<<<-------
  #


else
  logmsg "WARNING: No image tar files found in; '$DOCKER_IMAGE_SAVE_DIR'"
  errorlogmsg "WARNING: No image tar files found in; '$DOCKER_IMAGE_SAVE_DIR' but there is a flag file; '$DOCKER_IMAGE_SAVE_DIR/last_exported_images_list'"
fi

#
TIME_COMPLETE=`date +"%s"`
DURATION_BATCH=`date -u -d "0 $TIME_COMPLETE seconds - $TIME_START seconds" +"%H:%M:%S"`
logmsg "Duration for nightly batch cycle: $DURATION_BATCH"


# Tidy up sync log directory, keep MAXLOGS log files for each type
purge_log_files "move-image-files-batch-"

logmsg "All done, exiting 0.."
exit 0

