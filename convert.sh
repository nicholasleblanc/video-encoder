#!/bin/bash

#*******************************************************************************
#*******************************************************************************
#
#  Video Conversion Script
#
#*******************************************************************************
#*******************************************************************************
#
#  Pre-requisites:
#    ffmpeg with libx265
#      If using on WSL we use the native Windows ffmpeg libraries. Can be
#      downaloded here: https://github.com/BtbN/FFmpeg-Builds/releases
#
#*******************************************************************************

#*******************************************************************************
#  Configuration
#*******************************************************************************

AUDIO_CODEC="aac"
VIDEO_CODEC="libx265" # Will need Ubuntu 18.04 LTS or later. On average libx265 should produce files half in size of libx264  without losing quality. It is more compute intensive, so transcoding will take longer.

#*******************************************************************************
#  Usage
#*******************************************************************************

usage()
{
  cat << EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-f] [-v] filename

Video conversion script.

Available options:

-h, --help   Print this help and exit
-f, --force  Force a file to convert even if a lock file exists
-l, --lower  Override default settings with a lower quality encode
EOF
  exit
}

#*******************************************************************************
#  Main Program
#*******************************************************************************

. ./common.config

FILENAME=$1
FORCE=false
LOWER_QUALITY=false

# Handle options
# https://pretzelhands.com/posts/command-line-flags/
for arg in "$@"
do
  case $arg in
    -h|--help)
    usage
    exit
    ;;
    -f|--force)
    FORCE=true
    shift # Remove --force from processing
    ;;
    -l|--lower)
    LOWER_QUALITY=true
    shift # Remove --lower from processing
    ;;
    *)
    FILENAME=("$1")
    shift # Remove generic argument from processing
    ;;
  esac
done

# Ensure a file name was provided
if [ -z "$FILENAME" ]
then
  echo "Must provide a file to convert."
  exit 1
fi

# Ensure file is a valid video file
EXTENSION="${FILENAME##*.}"
if [[ ! " ${FILE_TYPES[*]} " =~ " ${EXTENSION} " ]]
then
  echo "$FILENAME is not a valid video file."
  exit 1
fi

# Ensure file exists
if [ ! -f "$FILENAME" ]
then
  echo "$FILENAME does not exist."
  exit 1
fi

# Ensure ffmpeg is installed
if ! command -v ffmpeg &> /dev/null
then
    echo "ffmpeg could not be found."
    exit 1
fi

NEW_FILENAME="${FILENAME%.*}.$CONVERTED_FILE_EXTENSION.mkv"
TEMP_FILENAME="$NEW_FILENAME.tmp"
LOCK_FILE="${FILENAME%.*}.$CONVERTED_FILE_EXTENSION.lock"
LOG_FILE="${FILENAME%.*}.$CONVERTED_FILE_EXTENSION.log"

# If we're forcing this through, remove any existing lock or temp files
if [ "$FORCE" = true ]
then
  rm -f "$LOCK_FILE"
  rm -f "$TEMP_FILENAME"
fi

# Create the log file
touch "$LOG_FILE"

# Define log function
log()
{
  TYPE=${2:-"info"}
  TYPE=${TYPE^^}
  LOG_STRING="$TYPE $(date +"%Y%m%d-%H%M%S"): $1"
  printf "$LOG_STRING" | tee -a "$LOG_FILE"
}

# Handle cancelling process
cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  log "Interupted, cleaning up\n" "error"
  rm -f "$LOCK_FILE"
  rm -f "$TEMP_FILENAME"
  log "Done\n"
  exit 1
}
trap cleanup SIGINT SIGTERM ERR EXIT

# In order to avoid duplicate processes, if another transcode process is active, exit
if ls "$LOCK_FILE" 1> /dev/null 2>&1; then
  log "LOCK_FILE:$LOCK_FILE already exists\n" "error"
  exit 1
fi

# If the new file already exists, exit
if ls "$NEW_FILENAME" 1> /dev/null 2>&1; then
  echo "NEW_FILENAME:$NEW_FILENAME already exists\n" "error"
  exit 1
fi

# If the temp file already exists, exit
if ls "$TEMP_FILENAME" 1> /dev/null 2>&1; then
  echo "TEMP_FILENAME:$TEMP_FILENAME already exists\n" "error"
  exit 1
fi

# Define check_errors function
check_errs()
{
  # Function. Parameter 1 is the return code
  # Para. 2 is text to display on failure
  if [ "${1}" -ne "0" ]; then
    log "# ${1} : ${2}" "error"
    exit ${1}
  fi
}

FILE_SIZE="$(ls -lh "$FILENAME" | awk '{ print $5 }')"

rm -f "$LOCK_FILE" #Clean up mktemp artifact
touch "$LOCK_FILE" # Create the lock file
check_errs $? "Failed to create temporary LOCK_FILE: $LOCK_FILE"

# ********************************************************
# Detect original resolution
# ********************************************************

ORIGINAL_RESOLUTION=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$FILENAME")

# Default target is 1080p
TARGET_RESOLUTION="hd1080"
VIDEO_QUALITY=22
AUDIO_BITRATE=640

if [ "$LOWER_QUALITY" = true ]
then
  VIDEO_QUALITY=26
  AUDIO_BITRATE=192
fi

if [ "$ORIGINAL_RESOLUTION" -gt 2000 ]
then
  TARGET_RESOLUTION="uhd2160"
  VIDEO_QUALITY=25
  AUDIO_BITRATE=640

  if [ "$LOWER_QUALITY" = true ]
  then
    VIDEO_QUALITY=30
    AUDIO_BITRATE=192
  fi
elif [ "$ORIGINAL_RESOLUTION" -lt 1000 ] && [ "$ORIGINAL_RESOLUTION" -ge 700 ]
then
  TARGET_RESOLUTION="hd720"
  VIDEO_QUALITY=21
  AUDIO_BITRATE=192

  if [ "$LOWER_QUALITY" = true ]
  then
    VIDEO_QUALITY=26
    AUDIO_BITRATE=128
  fi
elif [ "$ORIGINAL_RESOLUTION" -lt 700 ]
then
  TARGET_RESOLUTION="hd480"
  VIDEO_QUALITY=22
  AUDIO_BITRATE=128

  if [ "$LOWER_QUALITY" = true ]
  then
    VIDEO_QUALITY=27
  fi
fi

# ********************************************************
# Start transcoding
# ********************************************************

log "Transcoding $FILENAME to $TEMP_FILENAME\n"

log "Using FFMPEG\n"
log "[$FILE_SIZE -> \n"

START_TIME=$(date +%s)

if grep -q microsoft /proc/version
then
  WINDOWS_FILENAME=$(wslpath -w "$FILENAME")
  WINDOWS_NEW_FILENAME="${WINDOWS_FILENAME%.*}.$CONVERTED_FILE_EXTENSION.mkv"
  WINDOWS_TEMP_FILENAME="$WINDOWS_NEW_FILENAME.tmp"

  ./ffmpeg.exe -probesize 1500M -analyzeduration 1000M -i "$WINDOWS_FILENAME" -f matroska -s $TARGET_RESOLUTION -c:v "$VIDEO_CODEC"  -preset veryfast -crf "$VIDEO_QUALITY" -vf yadif -codec:a "$AUDIO_CODEC" -b:a "$AUDIO_BITRATE"k -async 1 "$WINDOWS_TEMP_FILENAME"
else
  ffmpeg -probesize 1500M -analyzeduration 1000M -i "$FILENAME" -f matroska -s $TARGET_RESOLUTION -c:v "$VIDEO_CODEC"  -preset veryfast -crf "$VIDEO_QUALITY" -vf yadif -codec:a "$AUDIO_CODEC" -b:a "$AUDIO_BITRATE"k -async 1 "$TEMP_FILENAME"
fi


END_TIME=$(date +%s)
SECONDS="$(( END_TIME - START_TIME ))"
MINUTES_TAKEN="$(( SECONDS / 60 ))"
SECONDS_TAKEN="$(( $SECONDS - (MINUTES_TAKEN * 60) ))"
LOG_STRING_4="$(ls -lh "$TEMP_FILENAME" | awk ' { print $5 }')] - [$MINUTES_TAKEN min $SECONDS_TAKEN sec]\n"
check_errs $? "Failed to convert."

# ********************************************************"
# Done transcoding, perform cleanup
# ********************************************************"

LOG_STRING_5="Finished transcode\n"
log "$LOG_STRING_4$LOG_STRING_5"

# Delete original file
# rm -f "$FILENAME"
# check_errs $? "Failed to remove original file: $FILENAME"

# Move completed tempfile to final location
mv -f "$TEMP_FILENAME" "$NEW_FILENAME"
check_errs $? "Failed to move converted file: $TEMP_FILENAME"

# Delete the LOCK_FILE
rm -f "$LOCK_FILE"
check_errs $? "Failed to remove LOCK_FILE."

log "Done\n"
