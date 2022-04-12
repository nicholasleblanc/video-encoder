#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

#*******************************************************************************
#*******************************************************************************
#
#  Video Transcode Script
#
#*******************************************************************************
#*******************************************************************************
#
#  Pre-requisites:
#    ffmpeg with libx265
#      If running on WSL we use the native Windows ffmpeg libraries. They can be
#      downloaded here: https://github.com/BtbN/FFmpeg-Builds/releases
#
#*******************************************************************************

#*******************************************************************************
#  Configuration
#*******************************************************************************

readonly AUDIO_CODEC="libfdk_aac" # From best to worst: libfdk_aac > libmp3lame/eac3/ac3 > aac
readonly VIDEO_CODEC="libx265" # On average libx265 should produce files half in size of libx264  without losing quality. It is more compute intensive, so transcoding will take longer.

#*******************************************************************************
#  Usage
#*******************************************************************************

usage()
{
  cat << USAGE_TEXT
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-f] [-v] filename

Video transcode script.

Available options:

-d, --delete-original  Delete original video once encoding is complete.
-f, --force            Force a file to transcode even if a lock file exists
-h, --help             Print this help and exit
-l, --lower            Override default settings with a lower quality encode
USAGE_TEXT
}

#*******************************************************************************
#  Main Program
#*******************************************************************************

readonly SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

. "$SCRIPT_DIR/../.env"

FILENAME=$1
FORCE=false
LOWER_QUALITY=false
DELETE_ORIGINAL=false

# Handle options
# https://pretzelhands.com/posts/command-line-flags/
for arg in "$@"
do
  case $arg in
    -h|--help)
    usage
    exit 0
    ;;
    -f|--force)
    FORCE=true
    shift # Remove --force from processing
    ;;
    -l|--lower)
    LOWER_QUALITY=true
    shift # Remove --lower from processing
    ;;
    -d|--delete-original)
    DELETE_ORIGINAL=true
    shift # Remove --delete-original from processing
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
  echo "Must provide a file to transcode."
  exit 1
fi

# Ensure file is a valid video file
readonly EXTENSION="${FILENAME##*.}"
if [[ ! " ${FILE_TYPES[*]} " =~ " ${EXTENSION} " ]]
then
  echo "$FILENAME is not a valid video type."
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

readonly NEW_FILENAME="${FILENAME%.*}.$TRANSCODED_FILE_EXTENSION.mkv"
readonly TEMP_FILENAME="$NEW_FILENAME.tmp"
readonly LOCK_FILE="${FILENAME%.*}.$TRANSCODED_FILE_EXTENSION.lock"
readonly LOG_FILE="${FILENAME%.*}.$TRANSCODED_FILE_EXTENSION.log"

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
clean_up() {
  trap - ERR EXIT SIGINT SIGTERM
  log "Interupted, cleaning up\n" "error"
  rm -f "$LOCK_FILE"
  rm -f "$TEMP_FILENAME"
  log "Done\n"
  exit 1
}
trap clean_up ERR EXIT SIGINT SIGTERM

# In order to avoid duplicate processes, if another transcode process is active, exit
if ls "$LOCK_FILE" 1> /dev/null 2>&1
then
  log "LOCK_FILE:$LOCK_FILE already exists\n" "error"
  exit 1
fi

# If the new file already exists, exit
if ls "$NEW_FILENAME" 1> /dev/null 2>&1
then
  echo "NEW_FILENAME:$NEW_FILENAME already exists\n" "error"
  exit 1
fi

# If the temp file already exists, exit
if ls "$TEMP_FILENAME" 1> /dev/null 2>&1
then
  echo "TEMP_FILENAME:$TEMP_FILENAME already exists\n" "error"
  exit 1
fi

# Define check_errors function
check_errs()
{
  # Function. Parameter 1 is the return code
  # Para. 2 is text to display on failure
  if [ "${1}" -ne "0" ]
  then
    log "# ${1} : ${2}\n" "error"
    exit 1
  fi
}

readonly FILE_SIZE="$(ls -lh "$FILENAME" | awk '{ print $5 }')"

rm -f "$LOCK_FILE" #Clean up mktemp artifact
touch "$LOCK_FILE" # Create the lock file
check_errs $? "Failed to create temporary LOCK_FILE: $LOCK_FILE"

#*******************************************************************************
# Windows Subsystem for Linux setup
#
# If using WSL, it's much more efficient to run the native Windows executables rather than through
# Ubuntu or WSL. Luckily, WSL provides everything we need to make this work (including the
# ability to run Windows .exe files).
#*******************************************************************************

grep -q microsoft /proc/version && IS_WSL=true ||  IS_WSL=true

WINDOWS_FILENAME=""
WINDOWS_NEW_FILENAME=""
WINDOWS_TEMP_FILENAME=""

if [ "$IS_WSL" = true ]
then
  WINDOWS_FILENAME=$(wslpath -w "$FILENAME")
  WINDOWS_NEW_FILENAME="${WINDOWS_FILENAME%.*}.$TRANSCODED_FILE_EXTENSION.mkv"
  WINDOWS_TEMP_FILENAME="$WINDOWS_NEW_FILENAME.tmp"
fi

#*******************************************************************************
# Detect original resolution
#*******************************************************************************

ORIGINAL_RESOLUTION=0
if [ "$IS_WSL" = true ]
then
  ORIGINAL_RESOLUTION=$("$SCRIPT_DIR/../bin/ffprobe.exe" -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$WINDOWS_FILENAME")
else
  ORIGINAL_RESOLUTION=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$FILENAME")
fi
ORIGINAL_RESOLUTION=$(echo $ORIGINAL_RESOLUTION | sed 's/[^0-9]*//g') # Cleanup

TARGET_RESOLUTION=""
VIDEO_QUALITY=0
AUDIO_BITRATE=0

if [ "$ORIGINAL_RESOLUTION" -ge 2000 ] # 2160p
then
  TARGET_RESOLUTION="uhd2160"
  VIDEO_QUALITY=25
  AUDIO_BITRATE=640

  if [ "$LOWER_QUALITY" = true ]
  then
    VIDEO_QUALITY=30
    AUDIO_BITRATE=192
  fi
elif [ "$ORIGINAL_RESOLUTION" -lt 2000 ] && [ "$ORIGINAL_RESOLUTION" -ge 1000 ] # 1080p
then
  TARGET_RESOLUTION="hd1080"
  VIDEO_QUALITY=22
  AUDIO_BITRATE=640

  if [ "$LOWER_QUALITY" = true ]
  then
    VIDEO_QUALITY=26
    AUDIO_BITRATE=192
  fi
elif [ "$ORIGINAL_RESOLUTION" -lt 1000 ] && [ "$ORIGINAL_RESOLUTION" -ge 700 ] # 720p
then
  TARGET_RESOLUTION="hd720"
  VIDEO_QUALITY=21
  AUDIO_BITRATE=192

  if [ "$LOWER_QUALITY" = true ]
  then
    VIDEO_QUALITY=26
    AUDIO_BITRATE=128
  fi
elif [ "$ORIGINAL_RESOLUTION" -lt 700 ] # 480p
then
  TARGET_RESOLUTION="hd480"
  VIDEO_QUALITY=22
  AUDIO_BITRATE=128

  if [ "$LOWER_QUALITY" = true ]
  then
    VIDEO_QUALITY=27
  fi
fi

#*******************************************************************************
# Start transcoding
#*******************************************************************************

log "Transcoding $FILENAME to $TEMP_FILENAME\n"

log "Using FFMPEG\n"

readonly START_TIME=$(date +%s)

if [ "$IS_WSL" = true ]
then
  "$SCRIPT_DIR/../bin/ffmpeg.exe" -probesize 1500M -analyzeduration 1000M -i "$WINDOWS_FILENAME" -f matroska -s $TARGET_RESOLUTION -c:v "$VIDEO_CODEC"  -preset veryfast -crf "$VIDEO_QUALITY" -vf yadif -codec:a "$AUDIO_CODEC" -b:a "$AUDIO_BITRATE"k -async 1 "$WINDOWS_TEMP_FILENAME"
else
  ffmpeg -probesize 1500M -analyzeduration 1000M -i "$FILENAME" -f matroska -s $TARGET_RESOLUTION -c:v "$VIDEO_CODEC"  -preset veryfast -crf "$VIDEO_QUALITY" -vf yadif -codec:a "$AUDIO_CODEC" -b:a "$AUDIO_BITRATE"k -async 1 "$TEMP_FILENAME"
fi

readonly END_TIME=$(date +%s)
readonly SECONDS="$(( END_TIME - START_TIME ))"
readonly MINUTES_TAKEN="$(( SECONDS / 60 ))"
readonly SECONDS_TAKEN="$(( $SECONDS - (MINUTES_TAKEN * 60) ))"
readonly LOG_STRING_4="[$FILE_SIZE -> $(ls -lh "$TEMP_FILENAME" | awk ' { print $5 }')] - [$MINUTES_TAKEN min $SECONDS_TAKEN sec]\n"
check_errs $? "Failed to transcode"

#*******************************************************************************"
# Done transcoding, perform cleanup
#*******************************************************************************"

readonly LOG_STRING_5="Finished transcode\n"
log "$LOG_STRING_4$LOG_STRING_5"

# Delete original file
if [ "$DELETE_ORIGINAL" = true ]
then
  log "Delete original file: $FILENAME\n"

  rm -f "$FILENAME"
  check_errs $? "Failed to remove original file: $FILENAME"
fi

# Move completed tempfile to final location
mv -f "$TEMP_FILENAME" "$NEW_FILENAME"
check_errs $? "Failed to move transcoded file: $TEMP_FILENAME"

# Delete the LOCK_FILE
rm -f "$LOCK_FILE"
check_errs $? "Failed to remove lock file: $LOCK_FILE"

log "Done\n"

exit 0
