#!/bin/bash

#*******************************************************************************
#*******************************************************************************
#
#  Batch Video Conversion Script
#
#*******************************************************************************
#*******************************************************************************
#
#  Pre-requisites:
#    ffmpeg with libx265
#
#*******************************************************************************

#*******************************************************************************
#  Usage
#*******************************************************************************

usage()
{
  cat << EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-f] [-v] directory

Video conversion script.

Available options:

-h, --help   Print this help and exit
-l, --lower  Override default settings with a lower quality encode
-d, --delete-original  Delete original video once encoding is complete.
EOF
  exit
}

#*******************************************************************************
#  Main Program
#*******************************************************************************

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

. "$SCRIPT_DIR/../.env"

DIRECTORY=$1
LOWER_QUALITY=false
DELETE_ORIGINAL=false

# Handle options
# https://pretzelhands.com/posts/command-line-flags/
for arg in "$@"
do
  case $arg in
    -h|--help)
    usage
    exit
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
    DIRECTORY=("$1")
    shift # Remove generic argument from processing
    ;;
  esac
done

# Ensure a directory was provided
if [ -z "$DIRECTORY" ]
then
  echo "Must provide a directory to convert."
  exit 1
fi

# Ensure directory exists
if [ ! -d "$DIRECTORY" ]
then
  echo "$DIRECTORY does not exist."
  exit 1
fi

LOG_FILE="$SCRIPT_DIR/../logs/$(date +"%Y%m%d-%H%M%S").$CONVERTED_FILE_EXTENSION.log"

# Create the log file
touch $LOG_FILE

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
  trap - SIGINT ERR
  log "Interupted, cleaning up\n" "error"
  log "Done\n"
  exit 1
}
trap cleanup SIGINT ERR

# ********************************************************
# Scan directory for all video files via Regex
# ********************************************************

# Create a regex of the extensions for the find command
FILE_TYPES_REGEX="\\("${FILE_TYPES[0]}
for t in "${FILE_TYPES[@]:1:${#FILE_TYPES[*]}}"; do
  FILE_TYPES_REGEX="${FILE_TYPES_REGEX}\\|${t}"
done
FILE_TYPES_REGEX="${FILE_TYPES_REGEX}\\)"

# Set the field seperator to newline instead of space
IFS_ORIGINAL=$IFS
IFS=$(echo -en "\n\b")

log "Scanning directory: $DIRECTORY\n"

# Loop over all matched files and run converter
for FILENAME in `find "${DIRECTORY}" -type f -regex "^.*\\(\\(?!\.$CONVERTED_FILE_EXTENSION\\).\\)*\.$FILE_TYPES_REGEX$"`; do
  log "Start encoding video: $FILENAME\n"

  # Pass-through arguments to converter
  ARG_LIST=""
  [[ "$LOWER_QUALITY" = true ]] && ARG_LIST="-l $ARG_LIST"
  [[ "$DELETE_ORIGINAL" = true ]] && ARG_LIST="-d $ARG_LIST"

  # Transcode file
  ./convert.sh $ARG_LIST"$FILENAME"

  log "Done encoding video: $FILENAME\n"
done

log "Done\n"

# Reset IFS
IFS=$IFS_ORIGINAL
