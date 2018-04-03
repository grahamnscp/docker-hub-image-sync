#!/bin/bash

################################################################################
# Batch script to poll Docker Hub repos and sync images for all tags in each repo
# Designed to only pull changes compared to local docker daemon image store
# Pulled images extracted to local file system for moving and importing into DTR
#
# dependancies:
#   docker-ls utility: see: https://github.com/mayflower/docker-ls/releases
# https://github.com/mayflower/docker-ls/releases/download/v0.3.1/docker-ls-linux-amd64.zip
#
# example crontab entry:
#10 01 * * *  /usr/local/bin/get-repos.bash > /dev/null 2>&1
#
#
# grahamnscp	April 2018	Initial version
#
################################################################################

trap control_c SIGINT

##############################################
# Variables
##############################################
REPO_LIST_FILE=/usr/local/etc/repo-list.txt
#REPO_LIST_FILE=./repo-list.txt
LOGDIR=/var/log/get-repos-batch
#LOGDIR=./get-repos-batch
DOCKER_IMAGE_SAVE_DIR=/var/tmp/saved_images
#DOCKER_IMAGE_SAVE_DIR=./saved_images
#
DOCKER_LS_BIN=/usr/local/bin/docker-ls
#
REPO_TAGS=""
IMAGES_DOWNLOADED=0
declare -a PULLED_IMAGES
#
DATE=`/bin/date +'%Y%m%d'`
TIME=`/bin/date +'%H%M'`
LOGFILE=$LOGDIR/get-repos-batch-log-${DATE}-${TIME}.log
ERRORLOGFILE=$LOGDIR/get-repos-batch-log-${DATE}-${TIME}.errorlog
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
    /usr/bin/mkdir -p $DOCKER_IMAGE_SAVE_DIR
  fi
}


logmsg () {
  /usr//bin/echo `date +'%Y%m%d-%H:%M:%S'` "[get-repo-batch] $1" | tee -a $LOGFILE
}


errorlogmsg () {
  /usr/bin/echo `date +'%Y%m%d-%H:%M:%S'` "[get-repo-batch] $1" >> $ERRORLOGFILE
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


function check_repo_access()
{
  REPO_NAME=$1

  logmsg "Checking access to repo: '$REPO_NAME'"
  REPO_CHECK_OUT=`$DOCKER_LS_BIN tags $REPO_NAME 2>&1 | /usr/bin/egrep -v "$REPO_NAME"`

  HAS_TAGS=`/usr/bin/echo $REPO_CHECK_OUT | /usr/bin/grep -c "tags:"` 
  AUTH_FAILED=`/usr/bin/echo $REPO_CHECK_OUT | /usr/bin/grep -c "authorization rejected"` 
 
  if [ $AUTH_FAILED -eq 1 ]
  then
    # authorization rejected by registry
    logmsg "WARNING: Failed to access repo, raw output: '$REPO_CHECK_OUT'"
    errorlogmsg "WARNING: Failed to access repo '$REPO_NAME', output: '$REPO_CHECK_OUT'"
    return 1
  fi
  if [ ! $HAS_TAGS -eq 1 ]
  then
    logmsg "WARNING: Failed to find tags in repo, raw output: '$REPO_CHECK_OUT'"
    errorlogmsg "WARNING: Failed to find tags in repo '$REPO_NAME', raw output: '$REPO_CHECK_OUT'"
    return 1
  fi

  return 0
}


function fetch_tags_for_repo()
{
  REPO_NAME=$1

  logmsg "Fetching tags from repo: '$REPO_NAME'"
  REPO_TAGS=`$DOCKER_LS_BIN tags $REPO_NAME 2>/dev/null |/usr/bin/egrep -v "tags:|$REPO_NAME" | /usr/bin/awk '{print $2}' | /usr/bin/sed 's/\"//g'`
}


function pull_image()
{
  REPO_NAME=$1
  IMAGE_TAG=$2

  logmsg "Checking image: '$REPO_NAME:$IMAGE_TAG'"

  # check if it already exists in local daemon
  IMAGE_EXISTS=`docker images | /usr/bin/awk '{print $1":"$2}' | /usr/bin/grep -c "$REPO_NAME:$IMAGE_TAG"`

  if [ $IMAGE_EXISTS -eq 0 ]
  then
    # need to pull image
    logmsg "Pulling image '$REPO_NAME:$IMAGE_TAG' from Docker hub.."

    IMAGE_PULL_OUTPUT=`docker pull $REPO_NAME:$IMAGE_TAG 2>&1`

    # store list of images pulled down, can save just the new ones later
    IMAGES_DOWNLOADED=$(($IMAGES_DOWNLOADED+1))
    PULLED_IMAGES[$IMAGES_DOWNLOADED]="$REPO_NAME:$IMAGE_TAG"
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

# tidy previous flag file
[ ! -f $DOCKER_IMAGE_SAVE_DIR/last_exported_images_list ] || /usr/bin/rm $DOCKER_IMAGE_SAVE_DIR/last_exported_images_list

logmsg "Reading repo list from file: '$REPO_LIST_FILE'"

if [ ! -f $REPO_LIST_FILE ]
then
  logmsg "ERROR: Failed to access repo list file: '$REPO_LIST_FILE'"
  errorlogmsg "ERROR: Failed to access repo list file: '$REPO_LIST_FILE', exiting.."
  exit 1
fi

# Loop through each repo in the repo file and download the images for each tag if not already stored locally
while read repo
do
  logmsg "Processing repo: '$repo'"

  check_repo_access "$repo"
  if [ $? -eq 0 ]
  then
    fetch_tags_for_repo "$repo"
    TAGS_LIST=`echo $REPO_TAGS | /usr/bin/sed 's/\\n/\ /g'`
    logmsg "TAGS: '$TAGS_LIST'"
    for tag in $REPO_TAGS
    do
      pull_image "$repo" "$tag"
    done
  else
    logmsg "WARNING: Failed to process repo: '$repo'i, continuing.."
  fi
done < $REPO_LIST_FILE

#
TIME_SYNC_COMPLETE=`date +"%s"`
DURATION_SYNC=`date -u -d "0 $TIME_SYNC_COMPLETE seconds - $TIME_START seconds" +"%H:%M:%S"`
logmsg "Duration for repo synchronisation: $DURATION_SYNC"


# review which images where pulled this run
logmsg "Images pulled: '$IMAGES_DOWNLOADED'"

if [ ! $IMAGES_DOWNLOADED -eq 0 ]
then
  logmsg "Saving new images to flat files in; '$DOCKER_IMAGE_SAVE_DIR'"

  # save images..
  # each pulled image details was stored in an array called PULLED_IMAGES
  for (( i=1; i<=$IMAGES_DOWNLOADED; i++ ))
  do
    THIS_REPO=`/usr/bin/echo ${PULLED_IMAGES[i]} | /usr/bin/sed 's/\//:/'`
    THIS_REPO_USER=`/usr/bin/echo ${THIS_REPO} | /usr/bin/awk -F: '{print $1}'`
    THIS_REPO_REPO=`/usr/bin/echo ${THIS_REPO} | /usr/bin/awk -F: '{print $2}'`
    THIS_REPO_TAG=`/usr/bin/echo ${THIS_REPO} | /usr/bin/awk -F: '{print $3}'`

    docker save ${PULLED_IMAGES[i]} -o $DOCKER_IMAGE_SAVE_DIR/${THIS_REPO_USER}_${THIS_REPO_REPO}_${THIS_REPO_TAG}.tar
  done

  # Create new flag file, always the same name
  logmsg "Creating flag file; '$DOCKER_IMAGE_SAVE_DIR/last_exported_images_list'"
  /usr/bin/touch $DOCKER_IMAGE_SAVE_DIR/last_exported_images_list 

  for (( i=1; i<=$IMAGES_DOWNLOADED; i++ ))
  do
    /usr/bin/echo $(printf "%s" "${PULLED_IMAGES[i]}") >> $DOCKER_IMAGE_SAVE_DIR/last_exported_images_list
  done
fi

#
TIME_EXTRACT_COMPLETE=`date +"%s"`
DURATION_EXTRACT=`date -u -d "0 $TIME_EXTRACT_COMPLETE seconds - $TIME_SYNC_COMPLETE seconds" +"%H:%M:%S"`
DURATION_BATCH=`date -u -d "0 $TIME_EXTRACT_COMPLETE seconds - $TIME_START seconds" +"%H:%M:%S"`
logmsg "Duration for image save: $DURATION_EXTRACT"
logmsg "Duration for total nightly batch cycle: $DURATION_BATCH"


# Tidy up sync log directory, keep MAXLOGS log files for each type
purge_log_files "get-repos-batch-"

logmsg "All done, exiting 0.."
exit 0


