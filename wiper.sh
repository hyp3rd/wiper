#!/bin/bash
#
# wiper - securely wipe files or directories, or cover your tracks on UNIX.
#
# This script is intended for testing and educational purposes. Secure overwrite
# is best-effort on modern storage: SSDs (wear leveling), copy-on-write
# filesystems (APFS, Btrfs, ZFS), and journaled filesystems may retain data
# regardless of how many overwrite passes are made.
#
# Compatible with bash 3.2+ (macOS default) and bash 4+. POSIX-leaning where
# possible; bash-only constructs are kept to [[ ]] tests, ((  )) arithmetic,
# arrays, and process substitution. Avoids ${var,,} (bash 4) and mapfile.
#

set -euo pipefail

### Output / colors

if [[ -t 1 ]]; then
  RED=$'\033[0;31m'
  ORANGE=$'\033[1;33m'
  GREEN=$'\033[1;32m'
  NC=$'\033[0m'
else
  RED=""
  ORANGE=""
  GREEN=""
  NC=""
fi

#######################################
# Display an error message on stderr.
# Globals:
#   RED, NC
# Arguments:
#   Error message
#######################################
err() {
  printf '%b\n' "${RED}[ERR]${NC} [$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

#######################################
# Display a warning on stderr.
# Globals:
#   ORANGE, NC
# Arguments:
#   Warning message
#######################################
warn() {
  printf '%b\n' "${ORANGE}[WARN]${NC} [$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

#######################################
# Display an info message on stdout.
# Globals:
#   GREEN, NC
# Arguments:
#   Info message
#######################################
info() {
  printf '%b\n' "${GREEN}[INFO]${NC} [$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
}

#######################################
# Display a log message on stdout.
# Globals:
#   GREEN, NC
# Arguments:
#   Log message
#######################################
log() {
  printf '%b\n' "${GREEN}[+]${NC} $*"
}

#######################################
# Display the abort message and exit non-zero.
# Globals:
#   ORANGE, NC
# Arguments:
#   None
# Returns:
#   Exits 1.
#######################################
abort() {
  printf '%b\n' "${ORANGE}You cowardly aborted${NC}"
  exit 1
}

### Globals

VERSION="v0.10.0"
OS=""
LOCAL_USERS=()
DETECTED_LOGS_FILES=()
SKIPPED_FILES=()
ITERATIONS=8
TIMESPAN=120

WIPE=false
ERASE=false
REMOVE=false
DISABLE_LOGGING=false
PRIVATE=false
SILENT=false
RECURSIVE=false
CONFIRMED=false

#######################################
# Top-level usage. Exits 0.
#######################################
usage() {
  printf '%b' "
${GREEN}WIPER${NC} ${ORANGE}${VERSION}${NC}
${ORANGE}/dev/null before dishonour${NC}

Securely wipe files or directories, or cover your tracks on UNIX systems.
Designed for private people. Use at your own risk.

Usage:
  wiper [command] [flags] /path/to/wipe

Commands:
  wipe              Securely overwrite the content of a file or directory
  erase             Truncate the content of a file or directory
  remove            Delete a file or directory from the system
  disable-logging   Symlink every *.log under <path> to /dev/null
  private           Cover your tracks on the system (Linux only)
  help              Show this help, or 'wiper <command> --help' for details
  version           Print the version number of wiper

Flags:
  -h, --help        help for wiper or for a specific command
  -i, --iterations  number of overwrite iterations for wipe (default ${ITERATIONS})
  -t, --timespan    minutes to consider a log file recently modified (default ${TIMESPAN})
  -s, --silent      no confirmation prompts
  -r, --recursive   for {wipe, erase, remove}, recurse into descendant directories

Use 'wiper <command> --help' for command-specific help.
"
  exit 0
}

#######################################
# Per-command usage blocks. Each exits 0.
#######################################
usage_wipe() {
  printf '%b' "
${GREEN}wiper wipe${NC} - securely overwrite content with random data

Usage:
  wiper wipe [flags] /path/to/file_or_dir

Flags:
  -i, --iterations N    number of overwrite passes (default ${ITERATIONS})
  -s, --silent          no confirmation prompts
  -r, --recursive       recurse into descendant directories
  -h, --help            this help

Notes:
  - Prefers GNU shred(1) when available (Linux). Falls back to dd loop.
  - Best-effort on SSDs and copy-on-write filesystems (APFS, Btrfs, ZFS).
  - Zero-byte files are reported and skipped.
"
  exit 0
}

usage_erase() {
  printf '%b' "
${GREEN}wiper erase${NC} - truncate content (does not unlink)

Usage:
  wiper erase [flags] /path/to/file_or_dir

Flags:
  -s, --silent       no confirmation prompts
  -r, --recursive    recurse into descendant directories
  -h, --help         this help
"
  exit 0
}

usage_remove() {
  printf '%b' "
${GREEN}wiper remove${NC} - delete a file or directory (rm -rf)

Usage:
  wiper remove [flags] /path/to/file_or_dir

Flags:
  -s, --silent       no confirmation prompts
  -r, --recursive    recurse into descendant directories
  -h, --help         this help
"
  exit 0
}

usage_disable_logging() {
  printf '%b' "
${GREEN}wiper disable-logging${NC} - symlink *.log files under <root> to /dev/null

Usage:
  wiper disable-logging /path/to/root

Notes:
  - The <root> argument is required (the previous behavior of walking / has
    been removed; it was a footgun that could brick app logs and caches).
  - Typical use: 'wiper disable-logging /var/log' as root.
"
  exit 0
}

usage_private() {
  printf '%b' "
${GREEN}wiper private${NC} - cover your tracks on the system (Linux only)

Usage:
  wiper private [flags]

Flags:
  -t, --timespan N   minutes to consider a log recently modified (default ${TIMESPAN})
  -h, --help         this help

What it does:
  - Symlinks /var/log/auth.log to /dev/null
  - Wipes per-user shell history files for accounts in /etc/passwd
  - Wipes well-known log files and any *.log modified in the last <timespan>
  - Lists currently open *.log files via lsof (if available)

macOS:
  Not supported. /etc/passwd does not reflect macOS user accounts.
"
  exit 0
}

#######################################
# Curated log file/dir paths. Used by 'private' mode.
# Globals (set by helpers):
#   LOGS_FILES, DETECTED_LOGS_FILES, LOCAL_USERS, SKIPPED_FILES, OS
#######################################
LOGS_FILES=(
  /tmp/logs                                # General message and system related
  /var/logs                                # General message and system related
  /tmp/log                                 # General message and system related
  /var/log                                 # General message and system related
  /var/adm                                 # General message and system related
  "${HOME}/.bash_history"                  # Bash history
  "${HOME}/.bash_logout"                   # Bash logout history
  "${HOME}/.ksh_history"                   # Ksh history
  /var/log/messages                        # General message and system related
  /var/log/auth.log                        # Authentication logs
  /var/log/kern.log                        # Kernel logs
  /var/log/cron.log                        # Crond logs
  /var/log/lastlog                         # Last logins log
  /var/log/faillog                         # Failure log
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
  /var/log/utmp                            # Login records file
  /var/log/wtmp                            # Login records file
  /var/log/yum.log                         # Yum command log file
  /var/log/system.log                      # System Log
  /var/log/DiagnosticMessages              # Mac Analytics Data
  /Library/Logs                            # System Application Logs
  /Library/Logs/DiagnosticReports          # System Reports
  "${HOME}/Library/Logs"                   # User Application Logs
  "${HOME}/Library/Logs/DiagnosticReports" # User Reports
)

### Internal helpers

#######################################
# Determine if the current user is root.
# Returns:
#   0 if root, 1 otherwise.
#######################################
__is_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "You aren't ${GREEN}root${NC}"
    return 1
  fi
}

#######################################
# Convert a path to its absolute form.
# Arguments:
#   A path
# Outputs:
#   The absolute path on stdout (no trailing newline).
#######################################
__abs_path() {
  case "$1" in
    /*) printf '%s' "$1" ;;
    *) printf '%s/%s' "$(pwd)" "$1" ;;
  esac
}

#######################################
# Determine if a file or dir is writable by the current user.
# Arguments:
#   A path
# Returns:
#   0 if writable, 1 otherwise.
#######################################
__can_write() {
  if [[ -w "$1" ]]; then
    return 0
  fi
  err "You don't have write permissions on $(__abs_path "$1")"
  return 1
}

#######################################
# Check if a regular file is zero bytes; if so, record it for the summary.
# Globals:
#   SKIPPED_FILES (appended to)
# Arguments:
#   A path
# Returns:
#   0 if file is zero bytes (and was recorded), 1 otherwise.
#######################################
__is_zero_bytes() {
  if [[ -f "$1" && ! -s "$1" ]]; then
    SKIPPED_FILES+=("$(__abs_path "$1")")
    return 0
  fi
  return 1
}

#######################################
# Detect the OS once and cache the result in OS.
# Globals:
#   OS (set: linux | darwin)
# Returns:
#   Exits 1 on unsupported OS.
#######################################
__detect_os() {
  [[ -n "$OS" ]] && return 0
  local uname_bin
  uname_bin=$(command -v uname)
  case $("$uname_bin" | tr '[:upper:]' '[:lower:]') in
    linux*) OS="linux" ;;
    darwin*) OS="darwin" ;;
    msys* | cygwin* | mingw* | nt | win*)
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
# Append a trailing slash to a path/string if absent.
# Arguments:
#   A path or string
# Outputs:
#   The argument with a trailing slash on stdout.
#######################################
__add_trailing_slash() {
  local output="$1"
  [[ ${output} != */ ]] && output="${output}/"
  printf '%s\n' "${output}"
}

#######################################
# Determine if a command exists on the system.
# Arguments:
#   Command name(s)
# Returns:
#   0 if found, non-zero otherwise.
#######################################
__command_exists() {
  command -v "$@" >/dev/null 2>&1
}

#######################################
# Prompt the user for yes/no. Returns 0 on y/yes (case-insensitive).
# Arguments:
#   Prompt text (without "[Y/n]:" suffix)
# Returns:
#   0 on yes, 1 otherwise.
#######################################
__yesno() {
  local prompt="${1:-Continue}"
  local reply=""
  printf '%s [Y/n]: ' "${prompt}"
  read -r reply || reply=""
  printf '\n'
  reply=$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')
  [[ "$reply" == "y" || "$reply" == "yes" ]]
}

#######################################
# Print and clear the skipped zero-byte files list.
# Globals:
#   SKIPPED_FILES (read and reset)
# Outputs:
#   Summary block on stdout when non-empty.
#######################################
__report_skipped_files() {
  if [[ ${#SKIPPED_FILES[@]} -gt 0 ]]; then
    printf '\n'
    info "Summary: Skipped ${#SKIPPED_FILES[@]} zero-byte file(s)"
    local f
    for f in "${SKIPPED_FILES[@]}"; do
      printf '%b\n' "  ${ORANGE}[-]${NC} ${f}"
    done
    printf '\n'
    SKIPPED_FILES=()
  fi
}

### Secure wipe

#######################################
# Overwrite a regular file with random bytes.
#
# Strategy:
#   - On Linux with shred(1), use 'shred -fz -n ITERATIONS' (canonical, fast).
#   - Otherwise, loop ITERATIONS times piping ITERATIONS * fileSize bytes from
#     /dev/urandom into dd with conv=notrunc. Block size is fixed (1 MiB) so
#     multi-GB files don't blow up dd with a single huge bs= value.
#
# Globals:
#   OS, ITERATIONS, GREEN, ORANGE, NC
# Arguments:
#   A regular file path
# Outputs:
#   Progress on stdout.
#######################################
__secure_wipe() {
  __detect_os
  # Use absolute path internally so leading-dash filenames don't get parsed as
  # flags by stat / dd / shred.
  local target
  target=$(__abs_path "$1")

  # Caller should have filtered zero-byte; double-check.
  [[ -s "$target" ]] || return 0

  local fileSize
  if [[ "$OS" == "darwin" ]]; then
    fileSize=$(stat -f%z "$target")
  else
    fileSize=$(stat --format=%s "$target")
  fi

  if [[ "$OS" == "linux" ]] && __command_exists shred; then
    printf '%b\n' "${GREEN}[√]${NC} Wiping (shred -n ${ITERATIONS}): ${ORANGE}${target}${NC}"
    shred -fz -n "${ITERATIONS}" "$target"
    return 0
  fi

  local n
  for ((n = 1; n <= ITERATIONS; n++)); do
    printf '%b\r' "${GREEN}[√]${NC} Wiping: ${GREEN}iteration${NC} ...${ORANGE}${n}${NC} of ${ITERATIONS} ...[+] ${ORANGE}${target}${NC}"
    head -c "$fileSize" /dev/urandom | dd of="$target" bs=1048576 conv=notrunc 2>/dev/null
  done
  printf '\n'
}

#######################################
# Validate input and dispatch to __secure_wipe for files or per-entry for dirs.
# Globals:
#   SILENT, CONFIRMED, ITERATIONS, RECURSIVE
# Arguments:
#   A file or directory path
# Outputs:
#   Progress and results on stdout.
#######################################
secure_wipe() {
  if ! [[ ${ITERATIONS} =~ ^[0-9]+$ ]]; then
    err "The number of iterations must be a positive integer"
    exit 1
  fi

  info "Wiping the content of ...${ORANGE}$1${NC}"

  if [[ $SILENT == false && $CONFIRMED == false ]]; then
    __yesno "Go ahead?" || abort
    CONFIRMED=true
  fi

  if [[ ! -e "$1" ]]; then
    err "Path does not exist: $1"
  elif [[ -f "$1" ]]; then
    if __can_write "$1" && ! __is_zero_bytes "$1"; then
      __secure_wipe "$1"
    fi
  elif [[ -d "$1" ]] && __can_write "$1" && [[ -n $(ls -A "$1") ]]; then
    local directories=()
    local entry
    pushd "$1" >/dev/null
    while IFS= read -r -d '' entry; do
      entry="${entry#./}"
      if [[ -d "$entry" ]]; then
        directories+=("$entry")
      elif [[ -f "$entry" ]]; then
        __can_write "$entry" && ! __is_zero_bytes "$entry" && __secure_wipe "$entry" || true
      fi
    done < <(find . -mindepth 1 -maxdepth 1 -print0)
    __recursive_action "WIPE" "${directories[@]+"${directories[@]}"}"
    popd >/dev/null
    info "Successfully wiped files under ${GREEN}[+]${NC}...${GREEN}$(__add_trailing_slash "$1")${NC}"
  else
    warn "Directory empty or not writable: $(__add_trailing_slash "$1")"
  fi
  __report_skipped_files
  printf '\n'
}

### Erase

#######################################
# Truncate a regular file to zero bytes (':' redirect — fast, obvious).
# Arguments:
#   A regular file path
# Outputs:
#   Result on stdout.
#######################################
__erase() {
  if __is_zero_bytes "$1"; then
    return 0
  fi
  local target
  target=$(__abs_path "$1")
  : >"$target"
  log "Successfully erased the content of ...${GREEN}${target}${NC}"
}

#######################################
# Validate input and dispatch to __erase for files or per-entry for dirs.
# Globals:
#   SILENT, CONFIRMED, RECURSIVE
# Arguments:
#   A file or directory path
# Outputs:
#   Progress and results on stdout.
#######################################
erase() {
  info "Erasing the content of ...${ORANGE}$1${NC}"

  if [[ $SILENT == false && $CONFIRMED == false ]]; then
    __yesno "Should I?" || abort
    CONFIRMED=true
  fi

  if [[ ! -e "$1" ]]; then
    err "Path does not exist: $1"
  elif [[ -f "$1" ]]; then
    if __can_write "$1" && ! __is_zero_bytes "$1"; then
      __erase "$1"
    fi
  elif [[ -d "$1" ]] && __can_write "$1" && [[ -n $(ls -A "$1") ]]; then
    local directories=()
    local entry
    pushd "$1" >/dev/null
    while IFS= read -r -d '' entry; do
      entry="${entry#./}"
      if [[ -d "$entry" ]]; then
        directories+=("$entry")
      elif [[ -f "$entry" ]]; then
        __can_write "$entry" && ! __is_zero_bytes "$entry" && __erase "$entry" || true
      fi
    done < <(find . -mindepth 1 -maxdepth 1 -print0)
    __recursive_action "ERASE" "${directories[@]+"${directories[@]}"}"
    popd >/dev/null
    info "Successfully erased files under ${GREEN}[+]${NC}...${GREEN}$(__add_trailing_slash "$1")${NC}"
  else
    warn "Directory empty or not writable: $(__add_trailing_slash "$1")"
  fi
  __report_skipped_files
  printf '\n'
}

### Remove

#######################################
# Remove a file or directory from disk (rm -rf).
# Arguments:
#   A path
# Outputs:
#   Result on stdout.
#######################################
__remove() {
  rm -rf -- "$1"
  log "Successfully removed ...${GREEN}$(__abs_path "$1")${NC}"
}

#######################################
# Validate input and dispatch to __remove. For dirs, removes per-entry then
# recurses into subdirectories via __recursive_action.
# Globals:
#   SILENT, CONFIRMED, RECURSIVE
# Arguments:
#   A file or directory path
# Outputs:
#   Result on stdout.
#######################################
remove() {
  if [[ $SILENT == false && $CONFIRMED == false ]]; then
    __yesno "Should I delete the file(s) from disk?" || abort
    CONFIRMED=true
  fi

  if [[ ! -e "$1" ]]; then
    err "Path does not exist: $1"
  elif [[ -f "$1" ]]; then
    __can_write "$1" && __remove "$1"
  elif [[ -d "$1" ]] && __can_write "$1" && [[ -n $(ls -A "$1") ]]; then
    local directories=()
    local entry
    pushd "$1" >/dev/null
    while IFS= read -r -d '' entry; do
      entry="${entry#./}"
      if [[ -d "$entry" ]]; then
        directories+=("$entry")
      else
        __can_write "$entry" && __remove "$entry" || true
      fi
    done < <(find . -mindepth 1 -maxdepth 1 -print0)
    __recursive_action "REMOVE" "${directories[@]+"${directories[@]}"}"
    popd >/dev/null
    info "Successfully deleted content of ${GREEN}[+]${NC}...${GREEN}$(__add_trailing_slash "$1")${NC}"
  else
    warn "Directory empty or file not readable ${ORANGE}[-]${NC}...$(__add_trailing_slash "$1")"
  fi
  __report_skipped_files
  printf '\n'
}

### Recursive dispatch

#######################################
# Apply ACTION to each provided directory, gated by RECURSIVE.
# Globals:
#   RECURSIVE
# Arguments:
#   ACTION (WIPE | ERASE | REMOVE)
#   Zero or more directory paths
# Outputs:
#   Per-directory progress on stdout.
#######################################
__recursive_action() {
  local action="$1"
  shift
  [[ $# -eq 0 ]] && return 0
  local dir
  for dir in "$@"; do
    printf '\n'
    if [[ "$RECURSIVE" == true ]]; then
      case "$action" in
        WIPE) secure_wipe "$dir" ;;
        ERASE) erase "$dir" ;;
        REMOVE) remove "$dir" ;;
        *)
          err "Action not available: $action"
          exit 1
          ;;
      esac
    else
      warn "Recursive mode {--recursive} is off. ${ORANGE}I did not $(printf '%s' "$action" | tr '[:upper:]' '[:lower:]')${NC} $(__add_trailing_slash "$dir")"
    fi
  done
  printf '\n'
}

### disable-logging

#######################################
# Symlink every regular *.log file under <root> to /dev/null.
# Arguments:
#   A directory root (required)
# Outputs:
#   Per-file results on stdout.
#######################################
disable_logging() {
  local root="${1:-}"
  if [[ -z "$root" ]]; then
    err "disable-logging requires a path: e.g., 'wiper disable-logging /var/log'"
    exit 1
  fi
  if [[ ! -d "$root" ]]; then
    err "Not a directory: $root"
    exit 1
  fi

  info "Disabling .log files under ${root}"
  while IFS= read -r -d '' f; do
    if ln -sf /dev/null "$f"; then
      printf '%b\n' "${GREEN}[√]${NC} Disabled ${GREEN}[+]${NC}...${f}."
    fi
  done < <(find "$root" -type f -name '*.log' -print0 2>/dev/null)
  info "Done"
}

### Private mode (Linux only)

#######################################
# Enumerate non-system users from /etc/passwd into LOCAL_USERS.
# Globals:
#   LOCAL_USERS (appended to)
# Outputs:
#   Status info on stdout.
#######################################
__enumerate_users() {
  info "Enumerating users on the local system"
  local line
  while IFS= read -r line; do
    LOCAL_USERS+=("$line")
  done < <(grep -Ev '^#|/bin/sync|nologin' /etc/passwd | awk -F: '{print $1}')
}

#######################################
# Return the home directory for a given username, or empty string if not found.
# Arguments:
#   A username
# Outputs:
#   Home directory on stdout.
#######################################
__get_home_dir() {
  if [[ $# -gt 0 ]]; then
    awk -F: -v u="$1" '$1==u {print $6; exit}' /etc/passwd
  fi
}

#######################################
# Symlink /var/log/auth.log to /dev/null.
# Outputs:
#   Result on stdout.
#######################################
__disable_auth() {
  local authLog="/var/log/auth.log"

  if [[ -w "$authLog" ]]; then
    ln -sf /dev/null "$authLog"
    log "Permanently sending ${authLog} to /dev/null"
  else
    warn "${authLog} is not writable"
  fi
  printf '\n'
}

#######################################
# Wipe history files for every enumerated user. The script cannot affect the
# parent shell's running history; new sessions will pick up the symlinks.
# Globals:
#   LOCAL_USERS
# Outputs:
#   Per-file results on stdout.
#######################################
__disable_history() {
  erase_history
  info "Wiped history files for enumerated users"
  warn "Already-running shells keep their current history files until they exit"
  printf '\n'
}

#######################################
# Wipe and symlink-to-/dev/null the well-known history files under <home>.
# Arguments:
#   A user home directory
# Outputs:
#   Per-file results on stdout.
#######################################
__erase_history() {
  local home="$1"
  local history_files=(
    "${home}/.bash_history"
    "${home}/.zsh_history"
    "${home}/.ksh_history"
    "${home}/.local/share/fish/fish_history"
  )

  local hfile
  for hfile in "${history_files[@]}"; do
    if [[ -f "$hfile" ]]; then
      secure_wipe "$hfile"
      erase "$hfile"

      log "Sending ${ORANGE}${hfile}${NC} to /dev/null"
      ln -sf /dev/null "$hfile" && printf '%b\n' "${GREEN}[√]${NC} Success"
      printf '\n'
    else
      warn "History file does not exist: ${ORANGE}${hfile}${NC}"
    fi
  done
}

#######################################
# Wipe history for every enumerated user.
# Globals:
#   LOCAL_USERS
#######################################
erase_history() {
  __enumerate_users
  printf '\n'
  info "Erasing history files for enumerated users"
  local usr home
  for usr in "${LOCAL_USERS[@]+"${LOCAL_USERS[@]}"}"; do
    home=$(__get_home_dir "$usr")
    if [[ -n "$home" ]]; then
      __erase_history "$home"
    fi
  done
}

#######################################
# Filter LOGS_FILES down to existing regular files.
# Globals:
#   LOGS_FILES, DETECTED_LOGS_FILES (appended to)
#######################################
__detect_log_files() {
  local f
  for f in "${LOGS_FILES[@]}"; do
    if [[ -f "$f" ]]; then
      DETECTED_LOGS_FILES+=("$f")
    fi
  done
}

#######################################
# Wipe and erase known log files plus any *.log modified within TIMESPAN.
# Globals:
#   DETECTED_LOGS_FILES, TIMESPAN
#######################################
__clear_logs() {
  __detect_log_files
  local f
  for f in "${DETECTED_LOGS_FILES[@]+"${DETECTED_LOGS_FILES[@]}"}"; do
    secure_wipe "$f"
    erase "$f"
  done

  info "Wiping any log file modified in the last ${TIMESPAN} minutes"

  while IFS= read -r -d '' f; do
    printf '%b\r' "${GREEN}[!]${NC} Wiping ${ORANGE}[-]${NC}...${f}"
    if __can_write "$f" && ! __is_zero_bytes "$f"; then
      secure_wipe "$f" && erase "$f"
      printf '%b\n' "${GREEN}[√]${NC} Wiped ${GREEN}[+]${NC}...${f}."
    fi
  done < <(find / -type f -name '*.log' -newerct "${TIMESPAN} minutes ago" -print0 2>/dev/null)
}

#######################################
# Detect log files currently held open and write the list to a temp file.
# Outputs:
#   Open-files report on stdout, full list path printed at the end.
#######################################
__detect_open_logs() {
  if __command_exists lsof; then
    local outfile
    outfile=$(mktemp -t open_logs.XXXXXX)
    printf '\n'
    info "Checking if any log file is currently open"
    lsof 2>/dev/null | grep '\.log' | tee "$outfile" || true
    printf '\n'
    log "List of open log files stored in ${ORANGE}${outfile}${NC}"
  else
    printf '\n'
    warn "lsof is not installed; cannot determine if any log file is currently open"
  fi
}

#######################################
# Wrapper for the private-mode workflow. Linux only.
# Globals:
#   OS, SILENT, CONFIRMED
#######################################
private() {
  __detect_os
  if [[ "$OS" == "darwin" ]]; then
    err "private mode requires Linux; macOS account data is not in /etc/passwd"
    exit 1
  fi
  SILENT=true
  CONFIRMED=true
  __disable_auth
  __disable_history
  __clear_logs
  __detect_open_logs
}

#######################################
# Print the wiper version.
#######################################
show_version() {
  printf '%b\n' "${GREEN}wiper${NC}, ${ORANGE}${VERSION}${NC}"
}

### Argument parsing

[[ $# -lt 1 ]] && usage

POSITIONAL=()

while [[ $# -gt 0 ]]; do
  key="$1"

  case "$key" in
    wipe)
      WIPE=true
      shift
      ;;
    erase)
      ERASE=true
      shift
      ;;
    remove)
      REMOVE=true
      shift
      ;;
    disable-logging)
      DISABLE_LOGGING=true
      shift
      ;;
    private)
      PRIVATE=true
      shift
      ;;
    version | --version)
      show_version
      exit 0
      ;;
    -s | --silent)
      SILENT=true
      shift
      ;;
    -i | --iterations)
      if [[ $# -lt 2 ]]; then
        err "$1 requires an integer value"
        exit 1
      fi
      ITERATIONS="$2"
      shift 2
      ;;
    -t | --timespan)
      if [[ $# -lt 2 ]]; then
        err "$1 requires an integer value"
        exit 1
      fi
      TIMESPAN="$2"
      shift 2
      ;;
    -r | --recursive)
      RECURSIVE=true
      shift
      ;;
    -h | --help | help)
      if $WIPE; then usage_wipe; fi
      if $ERASE; then usage_erase; fi
      if $REMOVE; then usage_remove; fi
      if $DISABLE_LOGGING; then usage_disable_logging; fi
      if $PRIVATE; then usage_private; fi
      usage
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        POSITIONAL+=("$1")
        shift
      done
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"

### Dispatch

__detect_os

if [[ $WIPE == true ]]; then
  [[ $# -ge 1 ]] || {
    err "wipe requires a path"
    usage_wipe
  }
  secure_wipe "$1"
elif [[ $ERASE == true ]]; then
  [[ $# -ge 1 ]] || {
    err "erase requires a path"
    usage_erase
  }
  erase "$1"
elif [[ $REMOVE == true ]]; then
  [[ $# -ge 1 ]] || {
    err "remove requires a path"
    usage_remove
  }
  remove "$1"
elif [[ $DISABLE_LOGGING == true ]]; then
  disable_logging "${1:-}"
elif [[ $PRIVATE == true ]]; then
  private
else
  err "No command specified"
  usage
fi
