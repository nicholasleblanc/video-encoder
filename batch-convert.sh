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
EOF
  exit
}

#*******************************************************************************
#  Main Program
#*******************************************************************************

. ./common.config

DIRECTORY=$1
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
    -l|--lower)
    LOWER_QUALITY=true
    shift # Remove --lower from processing
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

LOG_FILE="$(date +"%Y%m%d-%H%M%S").$CONVERTED_FILE_EXTENSION.log"
touch $LOG_FILE # Create the log file

log()
{
  TYPE=${2:-"info"}
  TYPE=${TYPE^^}
  LOG_STRING="$TYPE $(date +"%Y%m%d-%H%M%S"): $1"
  printf "$LOG_STRING" | tee -a "$LOG_FILE"
}

# Create a regex of the extensions for the find command
FILE_TYPES_REGEX="\\("${FILE_TYPES[0]}
for t in "${FILE_TYPES[@]:1:${#FILE_TYPES[*]}}"; do
  FILE_TYPES_REGEX="${FILE_TYPES_REGEX}\\|${t}"
done
FILE_TYPES_REGEX="${FILE_TYPES_REGEX}\\)"

# # Set the field seperator to newline instead of space
IFS_ORIGINAL=$IFS
IFS=$(echo -en "\n\b")

log "Scanning $DIRECTORY\n"

# Loop over all matched files and run converter
for FILENAME in `find "${DIRECTORY}" -type f -regex "^.*\\(\\(?!\.$CONVERTED_FILE_EXTENSION\\).\\)*\.$FILE_TYPES_REGEX$"`; do
  log "Start encoding $FILENAME\n"

  # Transdode file
  ./convert.sh -p "$FILENAME"

  log "Done encoding $FILENAME\n"
done

log "Done converting $DIRECTORY\n"

# Reset IFS
IFS=$IFS_ORIGINAL
