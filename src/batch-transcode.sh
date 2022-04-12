#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

#*******************************************************************************
#*******************************************************************************
#
#  Batch Video Transcode Script
#
#*******************************************************************************
#*******************************************************************************
#
#  Pre-requisites:
#    See `transcode.sh`
#
#*******************************************************************************

#*******************************************************************************
#  Usage
#*******************************************************************************

usage()
{
  cat << USAGE_TEXT
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-f] [-v] directory

Batch video transcode script.

Available options:

-d, --delete-original  Delete original video once encoding is complete.
-h, --help             Print this help and exit
-l, --lower            Override default settings with a lower quality encode
USAGE_TEXT
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
    exit 0
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
  echo "Must provide a directory to transcode."
  exit 1
fi

# Ensure directory exists
if [ ! -d "$DIRECTORY" ]
then
  echo "$DIRECTORY does not exist."
  exit 1
fi

readonly LOG_FILE="$SCRIPT_DIR/../logs/$(date +"%Y%m%d-%H%M%S").$TRANSCODED_FILE_EXTENSION.log"

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
clean_up() {
  trap - ERR EXIT SIGINT SIGTERM
  log "Interupted, cleaning up\n" "error"
  log "Done\n"
  exit 1
}
trap clean_up ERR EXIT SIGINT SIGTERM

#*******************************************************************************
# Scan directory for all video files
#*******************************************************************************

# Create a regex of the extensions for the find command
FILE_TYPES_REGEX="\\("${FILE_TYPES[0]}
for t in "${FILE_TYPES[@]:1:${#FILE_TYPES[*]}}"
do
  FILE_TYPES_REGEX="${FILE_TYPES_REGEX}\\|${t}"
done
FILE_TYPES_REGEX="${FILE_TYPES_REGEX}\\)"

# Set the field seperator to newline instead of space
readonly IFS_ORIGINAL=$IFS
IFS=$(echo -en "\n\b")

log "Scanning directory: $DIRECTORY\n"

# Loop over all matched files and run transcoder
for FILENAME in `find "${DIRECTORY}" -type f -regex "^.*\\(\\(?!\.$TRANSCODED_FILE_EXTENSION\\).\\)*\.$FILE_TYPES_REGEX$"`
do
  log "Start transcoding video: $FILENAME\n"

  # Pass-through arguments to transcoder
  ARG_LIST=""
  [[ "$LOWER_QUALITY" = true ]] && ARG_LIST="-l $ARG_LIST"
  [[ "$DELETE_ORIGINAL" = true ]] && ARG_LIST="-d $ARG_LIST"

  # Transcode file
  "$SCRIPT_DIR/transcoder.sh" $ARG_LIST\""$FILENAME"\"

  log "Done encoding video: $FILENAME\n"
done

log "Done\n"

# Reset IFS
IFS=$IFS_ORIGINAL

exit 0
