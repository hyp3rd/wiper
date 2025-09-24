#!/bin/bash
# Shell script to securely wipe specific files or folders, or cover your tracks on UNIX systems.
#

set -euo pipefail

RED='\033[0;31m'
ORANGE='\033[1;33m'
GREEN='\033[1;32m'
NC='\033[0m' # No Color

#######################################
# Display an error message and redirects output to stderr.
# Globals:
#   None
# Arguments:
#   Error message
#######################################
err() {
  echo -e "${RED}[ERR]${NC} [$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

#######################################
# Displays a warning and redirects the output to stderr.
# Globals:
#   None
# Arguments:
#   Warn message
#######################################
warn() {
  echo -e "${ORANGE}[WARN]${NC} [$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

#######################################
# Displays an info message.
# Globals:
#   None
# Arguments:
#   Info message
#######################################
info() {
  echo -e "${GREEN}[INFO]${NC} [$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&1
}

#######################################
# Displays log message.
# Globals:
#   None
# Arguments:
#   Log message
#######################################
log() {
  echo -e "${GREEN}[+]${NC} $*" >&1
}

#######################################
# Displays exit message, and exits the program.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   non-zero.
#######################################
abort() {
  echo -e "${ORANGE}You cowardly aborted${NC}" && exit 1
}

#######################################
# Displays the usage
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   non-zero.
#######################################
usage() {
  echo -e "
${GREEN}WIPER${NC}
${ORANGE}/dev/null before dishonour${NC}

Shell script to securely wipe specific files or folders, or cover your tracks on UNIX systems.
Designed for private people...


Usage:
  wiper [command] [flag] /path|file/to/wipe

Available Commands:
  wipe              Wipe securely the content of a file or a folder
  erase             Erase the content of a file or a folder
  remove            Remove the content of a file or a folder
  disable-logging   Disable logging on the system
  private           Clear up your traces on the system
  help              Help about any command
  version           Print the version number of wiper

Flags:
  -h, --help        help for wiper
  -i, --iterations  number of iterations for the wipe command (default 8)
  -t, --timespan    timespan in minutes to consider a log file recently modified (default 120)
  -s, --silent      dry run, no questions asked
  -r, --recursive   enable the main commands {wipe, erase, remove} to run recursive against any decendant directory

Use 'wiper [command] --help' for more information about a command.
"
  exit 0
}

#######################################
# Globals:
#   LOGS_FILES
#   LOGS_FILES
#   VERSION
#   OS
#   LOCAL_USERS
#   DETECTED_LOGS_FILES
#######################################
LOGS_FILES=(
  /tmp/logs                                # General message and system related
  /var/logs                                # General message and system related
  /tmp/log                                 # General message and system related
  /var/log                                 # General message and system related
  /var/adm                                 # General message and system related
  "${HOME}/.bash_history"                  # Bash History
  "${HOME}/.bash_logout"                   # Bash logout history
  "${HOME}/.ksh_history"                   # Ksh history
  /var/log/messages                        # General message and system related
  /var/log/auth.log                        # Authenication logs
  /var/log/kern.log                        # Kernel logs
  /var/log/cron.log                        # Crond logs
  /var/log/lastlog                         # Last logins log
  /var/log/faillog                         # Failure log from
  /var/log/maillog                         # Mail server logs
  /var/log/boot.log                        # System boot log
  /var/log/mysqld.log                      # MySQL database server log file
  /var/log/qmail                           # Qmail log directory
  /var/log/httpd                           # Apache access and error logs directory
  /usr/local/apache/logs                   # Apache access and error logs directory
  /var/apache/logs                         # Apache access and error logs directory
  /var/log/lighttpd                        # Lighttpd access and error logs directory
  /var/log/nginx                           # nginx access and error logs directory
  /var/log/secure                          # Authentication log
  /var/run/utmp                            # Login records file
  /etc/utmp                                # Login records file
  /var/log/utmp                            # Login records file
  /var/log/wtmp                            # Login records file
  /etc/wtmp                                # Login records file
  /var/log/yum.log                         # Yum command log file
  /var/log/system.log                      # System Log
  /var/log/DiagnosticMessages              # Mac Analytics Data
  /Library/Logs                            # System Application Logs
  /Library/Logs/DiagnosticReports          # System Reports
  "${HOME}/Library/Logs"                   # User Application Logs
  "${HOME}/Library/Logs/DiagnosticReports" # User Reports
)

VERSION="v1.0"
OS=""
LOCAL_USERS=()
DETECTED_LOGS_FILES=()
SKIPPED_FILES=()
ITERATIONS=8
TIMESPAN=120

### Internal Helpers

#######################################
# Determine if the current user is root
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   non-zero on error.
#######################################
__is_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "You aren't ${GREEN}root${NC}"
    return 1
  fi
}

#######################################
# Determine if a file or a dir is writable by the current user
# Globals:
#   None
# Arguments:
#   A directory or a file
# Returns:
#   non-zero on error.
#######################################
__can_write() {
  if [[ -w "$1" ]]; then
    return 0
  fi
  err "You don't have write permissions on $(pwd)/$1"
  return 1
}

#######################################
# Check if a file is zero bytes and should be skipped
# Globals:
#   SKIPPED_FILES
# Arguments:
#   A file path
# Returns:
#   0 if file should be skipped (is zero bytes), 1 otherwise
#######################################
__is_zero_bytes() {
  if [[ -f "$1" ]] && [[ ! -s "$1" ]]; then
    SKIPPED_FILES+=("$(pwd)/$1")
    return 0
  fi
  return 1
}

#######################################
# Detect the OS
# Globals:
#   None
# Arguments:
#   A directory or a file
# Returns:
#   non-zero on error.
#######################################
__detect_os() {
  UNAME=$(command -v uname)

  case $("${UNAME}" | tr '[:upper:]' '[:lower:]') in
    linux*)
      OS="linux"
      ;;
    darwin*)
      OS="darwin"
      ;;
    msys* | cygwin* | mingw* | nt | win*)
      # or possible 'bash on windows'
      err "You are running windows, cannot compute"
      exit 1
      ;;
    *)
      err "Unsupported OS"
      exit 1
      ;;
  esac
}

#######################################
# Add a trailing slash to a given string
# Globals:
#   None
# Arguments:
#   A directory, a file, a url, or whatever you need to add a trailing slash
# Returns:
#   The given argument with appended a trailing slash.
#######################################
__add_trailing_slash() {
  output=$1
  [[ ${1} != */ ]] && output="${output}/"
  echo "${output}"
}

#######################################
# Determine if a command exists on the system
# Globals:
#   None
# Arguments:
#   A directory or a file
# Returns:
#   0 if the command exists, non-zero on error.
#######################################
__command_exists() {
  command -v "$@" >/dev/null 2>&1
}

#######################################
# Display summary of skipped zero-byte files
# Globals:
#   SKIPPED_FILES
# Arguments:
#   None
# Outputs:
#   Writes the summary to stdout
#######################################
__report_skipped_files() {
  if [[ ${#SKIPPED_FILES[@]} -gt 0 ]]; then
    echo
    info "Summary: Skipped ${#SKIPPED_FILES[@]} zero-byte file(s)"
    for skipped_file in "${SKIPPED_FILES[@]}"; do
      echo -e "  ${ORANGE}[-]${NC} ${skipped_file}"
    done
    echo
  fi
}

### Internal Helpers: END

### Secure Wipe

#######################################
# Overwrites a file or a directory with random characters
# Globals:
#   OS
#   ITERATIONS
# Arguments:
#   A directory or a file
# Outputs:
#   Writes the progress and the results to stdout
#######################################
__secure_wipe() {
  : <<'END_DOC'
dd - It is short for data definition and sometimes called data destroyer because it is infamous for accidental data destruction.

if=/dev/urandom - "if" stands for In File, AKA the source. It is the file, blocks, or device that dd will read from.
In this case /dev/urandom, a particular device comes with Linux and BSD that will produce an endless supply of random characters (we need the exact Out File size).

of={file} - "of" stands for Out File. We are writing over a file, so we type our file name here.

count=1 - The count tells dd how many times to repeat.
Suppose set count to "2", it would produce 42 bytes of data. We only want it to write over the current data, not create more than what we need to set this to "1".

conv=notrunc - dd by default will stop writing and truncate (delete the rest) the file if you specify a byte size that is less than the file.
You don't need to have this part of the command to get the job done, but it will help being accurate and minimizing errors.
END_DOC

  local fileSize
  [[ $OS == "darwin" ]] && fileSize=$(stat -f%z "$1")
  [[ $OS == "linux" ]] && fileSize=$(stat --format=%s "$1")

  if [[ -s $1 ]]; then
    for ((n = 1; n <= "${ITERATIONS}"; n++)); do
      echo -ne "${GREEN}[√]${NC} Wiping: ${GREEN}iteration(s)${NC} ...${ORANGE}$n${NC} of ${ITERATIONS} for ...[+] ${ORANGE}$(pwd)/$1${NC}\r"
      dd if=/dev/urandom of="$1" bs="${fileSize}" count=1 conv=notrunc 2>/dev/null # status=none: status is not known operand in some distributions of dd
    done
    printf "\n"
  else
    # File is zero bytes, already handled by __is_zero_bytes
    return 0
  fi
}

#######################################
# Determine if a file or a directory can be wiped
# Globals:
#   SILENT
#   ITERATIONS
# Arguments:
#   A directory or a file
# Outputs:
#   Writes the results to stdout
#######################################
secure_wipe() {
  local re='^[0-9]+$'
  if ! [[ ${ITERATIONS} =~ $re ]]; then
    err "The number of iterations is supposedly an integer"
    exit 1
  fi

  info "Wiping the content of ...${ORANGE}$1${NC}"

  if [[ ${SILENT} == false ]]; then
    echo -n "Go ahead? [Y/n]: "
    read -r wipeFiles
    echo

    [[ $(echo "${wipeFiles}" | tr '[:upper:]' '[:lower:]') == "y" ]] || abort
  fi

  if [[ -f "$1" ]] && __can_write "$1" && ! __is_zero_bytes "$1"; then
    __secure_wipe "$1"
  elif [[ -d "$1" ]] && __can_write "$1" && [[ -n $(ls -A "$1") ]]; then
    local directories=()
    pushd "$1" > /dev/null
    for i in *; do
      if [[ -d $i ]]; then
        directories+=("$i")
      else
        __can_write "$i" && ! __is_zero_bytes "$i" && __secure_wipe "$i"
      fi
    done
    __recursive_action "WIPE" directories

    popd > /dev/null
    info "Successfully wiped the content of the files held under ${GREEN}[+]${NC}...${GREEN}$(__add_trailing_slash "$1")${NC}"
  else
    printf "\n"
    err "The directory is empty, or the file is not readable ${RED}[-]${NC}...${RED}$(__add_trailing_slash "$1")${NC}"
  fi
  __report_skipped_files
  echo
}

### Secure Wipe: END

### Erase

#######################################
# Erases the content of a file or a directory
# Globals:
#   None
# Arguments:
#   A directory or a file
# Outputs:
#   Writes the progress and the results to stdout
#######################################
__erase() {
  : <<'END_DOC'
dd - data definition

if=/dev/null - "if" stands for In File, in this case /dev/null, a special file called the null device in Unix systems.
Colloquially it is also called the bit-bucket or the blackhole because it immediately discards anything written to it and only returns an end-of-file EOF when read.

of={file} - "of" stands for Out File. We are writing over a file, so we type our file name here.
END_DOC
  if __is_zero_bytes "$1"; then
    return 0
  fi
  dd if="/dev/null" of="$1"
  log "Successfully erased the content of ...${GREEN}$(pwd)/$1${NC}"
}

#######################################
# Determine if the content of a file or a directory can be erased
# Globals:
#   SILENT
# Arguments:
#   A directory or a file
# Outputs:
#   Writes the progress and the results to stdout
#######################################
erase() {
  info "Erasing the content of ...${ORANGE}$1${NC}"

  if [[ ${SILENT} == false ]]; then
    echo -n "Should I? [Y/n]: "
    read -r eraseFiles
    echo

    [[ ${eraseFiles,,} == "y" ]] || abort
  fi

  if [[ -f $1 ]]; then
    __can_write "$1" && ! __is_zero_bytes "$1" && __erase "$1"
  elif [[ -d "$1" ]] && __can_write "$1" && [[ -n $(ls -A "$1") ]]; then
    local directories=()
    pushd "$1" > /dev/null
    for i in *; do
      if [[ -d $i ]]; then
        directories+=("$i")
      else
        __can_write "$i" && ! __is_zero_bytes "$i" && __erase "$i"
      fi
    done
    __recursive_action "ERASE" directories
    popd > /dev/null
    info "Successfully erased the content of the files held under ${GREEN}[+]${NC}...${GREEN}$(__add_trailing_slash "$1")${NC}"
  else
    err "The directory is empty, or the file is not readable ${RED}[-]${NC}...$(__add_trailing_slash "$1")"
  fi
  __report_skipped_files
  echo
}

### Erase: END

### Remove

#######################################
# Remove a file from the system
# Globals:
#   None
# Arguments:
#   A file
# Outputs:
#   Writes the results to stdout
#######################################
__remove() {
  if __is_zero_bytes "$1"; then
    return 0
  fi
  rm -rf "$1"
  log "Successfully removed ...${GREEN}$(pwd)/$1${NC}"
}

#######################################
# Determine if a file or the content of a directory can be removed from the system
# Globals:
#   SILENT
# Arguments:
#   A file or a directory
# Outputs:
#   Writes the results to stdout
#######################################
remove() {
  if [[ ${SILENT} == false ]]; then
    echo -n "Should I delete the file(s) from  the disk? [Y/n]: "
    read -r removeFiles
    [[ ${removeFiles,,} == "y" ]] || exit 0
    echo
  fi

  if [[ -f "$1" ]]; then
    __can_write "$1" && __remove "$1"
  elif [[ -d "$1" ]] && __can_write "$1" && [[ -n $(ls -A "$1") ]]; then
    local directories=()
    pushd "$1" > /dev/null
    for i in *; do
      if [[ -d $i ]]; then
        directories+=("$i")
      else
        __can_write "$i" && __remove "$i"
      fi
    done
    __recursive_action "REMOVE" directories
  
    info "Successfully deleted the content of ${GREEN}[+]${NC}...${GREEN}$(__add_trailing_slash "$1")${NC}"
    popd > /dev/null
  else
    warn "Directory empty or file not readable ${ORANGE}[-]${NC}...$(__add_trailing_slash "$1")"
  fi
  __report_skipped_files
  echo
}

### Remove: END

### Recursive Mode

#######################################
# Make recursive the selected action for any descendant directory
# Globals:
#   None
# Arguments:
#   The action name
#   An array of directories passed by reference
# Outputs:
#   Writes the results to stdout
#######################################
__recursive_action() {
  action="$1"

  if [ ${#directories[@]} -gt 0 ]; then
    for dir in "${directories[@]}"; do
      echo
      if [[ "${RECURSIVE}" == true ]]; then
        case $action in
          "WIPE")
            secure_wipe "$dir"
            ;;
          "ERASE")
            erase "$dir"
            ;;
          "REMOVE")
            remove "$dir"
            ;;
          *)
            err "Action not available"
            exit 1
            ;;
        esac
      else
        warn "Recursive mode {--recursive} is off. ${ORANGE}I did not $(echo "${action}" | tr '[:upper:]' '[:lower:]')${NC} $(__add_trailing_slash "${dir}")"
      fi
    done
  fi
  echo
}

### Recursive: END

### Logging

#######################################
# Disable logs
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Writes the results to stdout
#######################################
disable_logging() {
  info "Disabling logs"

  while IFS= read -r -d $'\0'; do
    ln -sf /dev/null "${REPLY}" &&
      echo -e "${GREEN}[√]${NC} Disabled ${GREEN}[+]${NC}...${REPLY}."
  done < <(find / -type f -name "*.log" -print0)
  info "Successfully disabled all the logs on the system"
}

### Logging: END

### Private

#######################################
# Enumerate the users on the local system and save em to LOCAL_USERS
# Globals:
#   LOCAL_USERS
# Arguments:
#   None
# Outputs:
#   Task's information
#######################################
__enumerate_users() {
  info "Enumerating users on the local system"
  while read -r line; do
    LOCAL_USERS+=("$line")
  done < <(grep -Ev "#|/bin/sync|nologin" /etc/passwd | awk -F ":" '{print $1}')
}

#######################################
# Return the homedir of a given username
# Globals:
#   None
# Arguments:
#   A username
# Outputs:
#   The homedir of a given user
#######################################
__get_home_dir() {
  if [[ $# -gt 0 ]]; then
   grep "$1" /etc/passwd | cut -d: -f6
  fi
}

#######################################
# Sends the auth log stream to /dev/null
# Globals:
#   None
# Arguments:
#   A file
# Outputs:
#   Writes the results to stdout
#######################################
__disable_auth() {
  local authLog="/var/log/auth.log"

  if [[ -w ${authLog} ]]; then
    ln -sf /dev/null ${authLog}
    log "Permanently sending ${authLog} to /dev/null"
  else
    warn "${authLog} is not writable"
  fi
  echo
}

#######################################
# Disable the history for the main shells
# Globals:
#   None
# Arguments:
#   A file
# Outputs:
#   Writes the results to stdout
#######################################
__disable_history() {
  erase_history

  unset HISTFILE
  HISTFILE=/dev/null

  export HISTFILE=/dev/null
  export HISTFILESIZE=0
  export HISTSIZE=0
  log "Set HISTFILESIZE & HISTSIZE to 0"

  history -c
  shopt -ou history

  log "Disabled history library"

  info "Permenently disabled bash log"
  warn "You need to reload the session to see effects"
  echo
}

#######################################
# Erase the most common history files stored under a given home dir, and prevents the system from collecting history
# Globals:
#   None
# Arguments:
#   A user's home dir
#######################################
__erase_history() {
  local history_files=(
    "${1}/.bash_history"
    "${1}/.zsh_history"
    "${1}/.ksh_history"
    "${1}/.local/share/fish/fish_history"
  )

  for hfile in "${history_files[@]}"; do
    if [[ -f ${hfile} ]]; then
      secure_wipe "${hfile}"
      erase "${hfile}"

      log "Sending ${ORANGE}$hfile${NC} to /dev/null"
      ln -sf /dev/null "${hfile}" && echo -e "${GREEN}[√]${NC} Success"
      echo
    else
      warn "History file does not exist: ${ORANGE}${hfile}${NC}"
    fi
  done
}

#######################################
# Erase the most common history files and prevents the system from collecting history
# Globals:
#   LOCAL_USERS
# Arguments:
#   None
#######################################
erase_history() {
  __enumerate_users
  echo
  info "Erasing history files and disabling history's collection"
  for usr in "${LOCAL_USERS[@]}"; do
    __erase_history "$(__get_home_dir "${usr}")"
  done
}

#######################################
# Detect the directories and files stored in LOGS_FILES are available on the system
# Globals:
#   LOGS_FILES
#   DETECTED_LOGS_FILES
# Arguments:
#   None
#######################################
__detect_log_files() {
  for i in "${LOGS_FILES[@]}"; do
    if [[ -f "$i" ]] || [[ -d "$i" ]]; then
      DETECTED_LOGS_FILES+=("$i")
    fi
  done
}

#######################################
# Wipe and empty the log files on the system
# Globals:
#   DETECTED_LOGS_FILES
#   TIMESPAN
# Arguments:
#   None
#######################################
__clear_logs() {
  __detect_log_files
  for i in "${DETECTED_LOGS_FILES[@]}"; do
    secure_wipe "$i"
    erase "$i"
  done

  info "Wiping any log file modified in the last ${TIMESPAN} minutes"

  # might break with older versions of bash
  # mapfile -d $'\0' recently_modified_logs < <(find -L -s /var/log -type f -name "*.log" -newerct '45 minutes ago' -print)

  while IFS= read -r -d $'\0'; do
    echo -ne "${GREEN}[!]${NC} Wiping ${ORANGE}[-]${NC}...${REPLY}\r"
    if __can_write "$REPLY" && ! __is_zero_bytes "$REPLY"; then
      secure_wipe "$REPLY" && erase "$REPLY"
      echo -e "${GREEN}[√]${NC} Wiped ${GREEN}[+]${NC}...${REPLY}."
    fi
  done < <(find / -type f -name "*.log" -newerct "${TIMESPAN} minutes ago" -print0)

  # backwords compatible
  # while IFS= read -r -d $'\0' log_file; do
  #   echo -ne "${GREEN}[!]${NC} Wiping ${ORANGE}[-]${NC}...${log_file}\r"
  #   __can_write "$log_file" && secure_wipe "$log_file" && erase "$log_file"
  #   echo -e "${GREEN}[√]${NC} Wiped ${GREEN}[+]${NC}...${log_file}."
  # done < <(find / -type f -name "*.log" -cmin "-${TIMESPAN}" -print0)

}

#######################################
# Detect the log files currently open on the system
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Writes the results to stdout and stores em to /tmp/open_logs.txt
#######################################
__detect_open_logs() {
  if __command_exists lsof; then
    echo
    info "Checking if any log file is currently open"
    lsof | grep .log | tee -a /tmp/open_logs.txt
    echo
    log "The list of open log files is stored in ${ORANGE}/tmp/open_logs.txt${NC}"
  else
    echo
    warn "lsof is not installed on the system, I cannot determine if any log file is currently open"
  fi
}

#######################################
# Wrapper for __disable_auth, __disable_history, __clear_logs, __detect_open_logs, __disable_logging
# Globals:
#   None
# Arguments:
#   None
#######################################
private() {
  SILENT=true
  __disable_auth
  __disable_history
  __clear_logs
  __detect_open_logs
}

### Private: END

#######################################
# Displays the script's version
# Globals:
#   None
# Arguments:
#   None
#######################################
show_version() {
  echo -e "${GREEN}wiper${NC}, ${ORANGE}${VERSION}${NC}"
}

#######################################
# Determine the command and execute it
# Globals:
#   WIPE
#   ERASE
#   REMOVE
#   DISABLE_LOGGING
#   PRIVATE
# Arguments:
#   File or path to parse
#######################################
wiper() {
  __detect_os
  [[ "${WIPE}" == true ]] && secure_wipe "$1"
  [[ "${ERASE}" == true ]] && erase "$1"
  [[ "${REMOVE}" == true ]] && remove "$1"
  [[ "${DISABLE_LOGGING}" == true ]] && disable_logging
  [[ "${PRIVATE}" == true ]] && private
}

[ $# -lt 1 ] && usage

POSITIONAL=()

WIPE=false
ERASE=false
REMOVE=false
DISABLE_LOGGING=false
PRIVATE=false
SILENT=false
RECURSIVE=false

while [[ $# -gt 0 ]]; do

  key="$1"

  case $key in
    wipe)
      WIPE=true   # past argument
      shift
      ;;
    erase)
      ERASE=true
      shift   # past argument
      ;;
    remove)
      REMOVE=true
      shift   # past argument
      ;;
    disable-logging)
      DISABLE_LOGGING=true
      shift
      ;;
    private)
      PRIVATE=true
      shift   # past argument
      ;;
    version)
      show_version
      exit 0
      ;;
    -s | --silent)
      SILENT=true
      shift   # past argument
      ;;
    -i | --iterations)
      ITERATIONS="$2"
      shift   # past argument
      shift   # past value
      ;;
    -t | --timespan)
      TIMESPAN="$2"
      shift   # past argument
      shift   # past value
      ;;
    -r | --recursive)
      RECURSIVE=true
      shift   # past argument
      ;;
    -h | help)
      usage
      ;;
    *)                   # unamed option
      POSITIONAL+=("$1") # save it in an array for later
      shift              # past argument
      ;;
  esac
done

set -- "${POSITIONAL[@]-}" # restore positional parameters

if [[ -z ${1-} ]] && [[ ${PRIVATE} == false ]] && [[ ${DISABLE_LOGGING} == false ]]; then
  err "Feed me with file or path to wipe, or go private {wiper private}"
  usage
elif [[ ${PRIVATE} == true ]] || [[ ${DISABLE_LOGGING} == true ]]; then
  wiper "$@"
else
  wiper "$1"
fi