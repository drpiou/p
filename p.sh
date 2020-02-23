#!/usr/bin/env bash

# https://github.com/drpiou/p
# 0.0.1 - 2020-02-22
#
# This script allows you the switch php versions in specific folders.

#
# Constants.
#

VERSION=0.0.1

DEBUG=0
SILENT=0
DOWNLOAD=0
FORCE_PATH=0
FORCE_HOMEBREW=0

SGR_RESET="\033[0m"
SGR_FAINT="\033[2m"
SGR_RED="\033[31m"
SGR_YELLOW="\033[33m"
SGR_CYAN="\033[36m"

CONFIG_FILE=.php-version
CONFIG_BASE="$HOME/$CONFIG_FILE"

SEMVER_URL="https://raw.githubusercontent.com/drpiou/p/$VERSION/semver.sh"

P_PREFIX="${P_PREFIX:=$HOME/.p}"
P_PATH=$P_PREFIX/bin
P_BIN=$P_PATH/php
P_DATA=$P_PREFIX/p
P_SCRIPTS=$P_DATA/bin
P_SEMVER=$P_SCRIPTS/semver.sh
P_SELECT=select.sh
P_RUBY=/usr/bin/ruby
P_BREW=brew
P_BREW_INSTALL=https://raw.githubusercontent.com/Homebrew/install/master/install
P_BREW_OPENLDAP=openldap
P_BREW_LIBICONV=libiconv
P_BREW_TAP=exolnet/deprecated
P_BREW_TAP_INSTALL=exolnet/homebrew-deprecated
P_BREW_CELLAR=$(brew --cellar)

#
# Variables.
#

bin_path=
bin_folder=/bin
bin_file=php
bin_version=
bin_brew=1

php_version=
php_bin=
php_candidate=
php_selected=
php_satisfiable_version=
php_satisfiable_package=
php_satisfiable_bin=
php_found=

#
# Output usage.
#

__usage() {
  cat <<-EOF
Usage: p [options] [COMMAND] [args]
Commands:
  p <version>                   Link php <version>
  p update <version>            Update installed php <version>
  p run <version> [args ...]    Execute php <version> with [args ...]
  p which <version>             Output path for php <version>
  p rm <version ...>            Remove the given downloaded version(s)
  p prune                       Remove all downloaded versions except the installed version
  p ls                          Output versions
  p ls-remote [version]         Output matching versions available for download
  p uninstall                   Remove the installed p
Options:
  -V, --version                 Output version of p
  -h, --help                    Display help information
  -d, --download                Download <version>
  -P, --path                    Force installation from path
  -H, --homebrew                Force installation from Homebrew
  -S, --silent                  Silent output
  -T, --trace                   Trace output
Aliases:
  update: u
  which: bin
  run: use, as
  ls: list
  lsr: ls-remote
  rm: -
EOF
}

#
# Output debug message.
#

__echo_debug() {
  [ 1 == "$DEBUG" ] && __echo "trace: $*"
}

#
# Output color message.
#

__echo_color() {
  printf 1>&2 "${SGR_CYAN}%s${SGR_RESET}\n" "$*"
}

#
# Output gray message.
#

__echo_gray() {
  [ 0 == "$SILENT" ] && printf 1>&2 "${SGR_FAINT}%s${SGR_RESET}\n" "$*"
}

#
# Output yellow message.
#

__echo_yellow() {
  [ 0 == "$SILENT" ] && printf 1>&2 "${SGR_YELLOW}%s${SGR_RESET}\n" "$*"
}

#
# Output red message.
#

__echo_red() {
  printf 1>&2 "${SGR_RED}%s${SGR_RESET}\n" "$*"
}

#
# Output message.
#

__echo() {
  printf 1>&2 "%s\n" "$*"
}

#
# Exit with the given <msg ...>
#

__abort() {
  printf 1>&2 "\n  Aborting: %s${SGR_RESET}\n\n" "$*"
  exit 1
}

#
# Exit error with the given <msg ...>
#

__abort_err() {
  printf 1>&2 "\n  ${SGR_RED}Error: %s${SGR_RESET}\n\n" "$*"
  exit 1
}

#
# Ask question.
#

__ask_yes_no() {
  local choice
  read -rep "$1" choice
  choice=$(__tolower "$choice")

  if [[ $choice =~ ^(yes|y| ) ]] || [[ -z $choice ]]; then
    echo "1"
  elif [[ $choice =~ ^(no|n) ]]; then
    echo "0"
  else
    __abort_err "Invalid choice."
  fi
}

__ask_no_yes() {
  local choice
  read -rep "$1" choice
  choice=$(__tolower "$choice")

  if [[ $choice =~ ^(no|n| ) ]] || [[ -z $choice ]]; then
    echo "0"
  elif [[ $choice =~ ^(yes|y) ]]; then
    echo "1"
  else
    __abort_err "Invalid choice."
  fi
}

#
# Select options
#

__select_option() {
  _select() {
    # little helpers for terminal print control and key input
    ESC=$(printf "\033")
    # shellcheck disable=SC1087
    # shellcheck disable=SC2059
    cursor_blink_on() { printf "$ESC[?25h"; }
    # shellcheck disable=SC1087
    # shellcheck disable=SC2059
    cursor_blink_off() { printf "$ESC[?25l"; }
    # shellcheck disable=SC1087
    # shellcheck disable=SC2059
    cursor_to() { printf "$ESC[$1;${2:-1}H"; }
    # shellcheck disable=SC2059
    print_option() { printf "   $1 "; }
    # shellcheck disable=SC1087
    # shellcheck disable=SC2059
    print_selected() { printf "  $ESC[7m $1 $ESC[27m"; }
    get_cursor_row() {
      # shellcheck disable=SC2034
      IFS=';' read -r -sdR -p $'\E[6n' ROW COL
      echo "${ROW#*[}"
    }
    key_input() {
      read -r -s -n3 key 2>/dev/null >&2
      # shellcheck disable=SC1087
      if [[ $key == "$ESC[A" ]]; then
        echo up
      elif [[ $key == "$ESC[B" ]]; then
        echo down
      else
        echo enter
      fi
    }

    # initially print empty new lines (scroll down if at bottom of screen)
    for opt; do printf "\n"; done

    # determine current screen position for overwriting the options
    local lastrow
    local startrow

    lastrow=$(get_cursor_row)
    startrow=$((lastrow - $#))

    # ensure cursor and input echoing back on upon a ctrl+c during read -s
    trap "cursor_blink_on; stty echo; printf '\n'; exit" 2
    cursor_blink_off

    local selected=0
    while true; do
      # print options by overwriting the last lines
      local idx=0
      for opt; do
        cursor_to $((startrow + idx))
        if [ $idx -eq $selected ]; then
          print_selected "$opt"
        else
          print_option "$opt"
        fi
        ((idx++))
      done

      # user key control
      case $(key_input) in
      up)
        ((selected--))
        if [ $selected -lt 0 ]; then selected=$(($# - 1)); fi
        ;;
      down)
        ((selected++))
        if [ $selected -ge $# ]; then selected=0; fi
        ;;
      enter) break ;;
      *) break ;;
      esac
    done

    # cursor position back to normal
    cursor_to "$lastrow"
    printf "\n"
    cursor_blink_on

    return $selected
  }

  _select "$@" 1>&2

  result=$?

  echo $result

  return $result
}

#
# Check if semvers match.
#

__is_satisfiable() {
  "$P_SEMVER" -r "$1" "$2 " | tail -1
}

__is_satisfiable_latest() {
  "$P_SEMVER" -r "<=$1" "$2" | tail -1
}

__is_satisfiable_version() {
  __parse "$1" '([0-9x]+)'
}

#
# Parse in string.
#

__parse() {
  [[ $1 =~ $2 ]]

  echo "${BASH_REMATCH[1]}"
}

#
# Parse "-NotWorking" in string.
#

__parse_error() {
  __parse "$1" '(-NotWorking$)'
}

#
# Parse "-Current" in string.
#

__parse_current() {
  __parse "$1" '(-Current$)'
}

#
# Parse php "<version>" in string.
#

__parse_version() {
  __parse "$1" '([0-9]+[\.][0-9]+[\.][0-9]+)'
}

#
# Test bin version.
#

__test_version() {
  __parse_version "$("$1" -v 2>/dev/null | grep 'built')"
}

#
# Parse php "<version>" in found string.
#

__found_version() {
  echo "$1" | awk -F '=' '{print $1}'
}

#
# Parse php "<package>" in found string.
#

__found_package() {
  echo "$1" | awk -F '=' '{print $3}'
}

#
# Parse php "<bin>" in found string.
#

__found_bin() {
  echo "$1" | awk -F '=' '{print $2}'
}

#
# String to lower.
#

__tolower() {
  echo "$1" | awk '{print tolower($0)}'
}

#
# Format path.
#

__format_path() {
  echo "${1//[\/]+/'/'}"
}

#
# String to lower.
#

__get_key() {
  echo "${1%%=*}"
}

#
# String to lower.
#

__get_value() {
  echo "${1##*=}"
}

#
# Append string to another.
#

__append() {
  if [ -n "$1" ]; then
    if [ -z "$2" ]; then
      echo "$1"
    else
      echo "$2 $1"
    fi
  else
    echo "$2"
  fi
}

#
# Uninstall p.
#

__uninstall() {
  __echo_debug "...uninstall"

  rm -rf "$P_PREFIX"

  __echo_color "Successfully uninstalled."
}

#
# Init p.
#

__init() {
  [ -z "$P_PREFIX" ] && __abort_err "P_PREFIX is undefined. Please export 'P_PREFIX'."
  [ ! -d "$P_PATH" ] && mkdir -p "$P_PATH"
  [ ! -d "$P_SCRIPTS" ] && mkdir -p "$P_SCRIPTS"
  [ 1 == "$DEBUG" ] && clear

  __init_semver
  __load_config

  [ 1 == "$bin_brew" ] && __init_brew
}

#
# Init semver.
#

__init_semver() {
  if [[ ! -f "$P_SEMVER" ]]; then
    curl "$SEMVER_URL" >"$P_SEMVER" 2>/dev/null
    chmod u+x "$P_SEMVER" 2>/dev/null
  fi
}

#
# Init homebrew.
#

__init_brew() {
  __echo_debug "...init homebrew"

  local brew_exists
  local choice

  brew_exists=$(command -v $P_BREW)

  if [ -z "$brew_exists" ]; then
    choice=$(__ask_yes_no $'Homebrew is not installed.\nDo you wish to install it? [Y/n]\n> ')

    if [ "$choice" == "0" ]; then
      __abort "Canceled."
    else
      if [ -f "$P_RUBY" ]; then
        __echo_color "Installing Homebrew..."

        /usr/bin/ruby -e "$(curl -fsSL "$P_BREW_INSTALL")"
      else
        __abort_err "Cannot install Homebrew; $P_RUBY not found."
      fi
    fi
  fi
}

#
# Check homebrew installation.
#

__check_brew() {
  __echo_debug "...check homebrew"

  local xcode_select_exists
  local openldap_exists
  local libiconv_exists
  local tap_exists
  local choice

  xcode_select_exists=$(xcode-select --version | grep 'xcode-select version')

  if [ -z "$xcode_select_exists" ]; then
    choice=$(__ask_yes_no $'XCode Command Line Tools tap is not installed.\nDo you wish to install it? [Y/n]\n> ')

    [ "$choice" == "0" ] && __abort "Canceled."

    __echo_color "Installing XCode Command Line Tools..."

    xcode-select --install
  fi

  openldap_exists=$(brew list | grep "$P_BREW_OPENLDAP")

  if [ -z "$openldap_exists" ]; then
    choice=$(__ask_yes_no "Homebrew $P_BREW_OPENLDAP"$' package is not installed.\nDo you wish to install it? [Y/n]\n> ')

    [ "$choice" == "0" ] && __abort "Canceled."

    __echo_color "Installing Homebrew $P_BREW_OPENLDAP package..."

    brew install "$P_BREW_OPENLDAP"
  fi

  libiconv_exists=$(brew list | grep "$P_BREW_LIBICONV")

  if [ -z "$libiconv_exists" ]; then
    choice=$(__ask_yes_no "Homebrew $P_BREW_LIBICONV"$' package is not installed.\nDo you wish to install it? [Y/n]\n> ')

    [ "$choice" == "0" ] && __abort "Canceled."

    __echo_color "Installing Homebrew $P_BREW_LIBICONV package..."

    brew install "$P_BREW_LIBICONV"
  fi

  tap_exists=$(brew tap | grep "$P_BREW_TAP")

  if [ -z "$tap_exists" ]; then
    choice=$(__ask_yes_no "Homebrew $P_BREW_TAP"$' tap is not installed.\nDo you wish to install it? [Y/n]\n> ')

    [ "$choice" == "0" ] && __abort "Canceled."

    __echo_color "Installing Homebrew $P_BREW_TAP_P_BREW_TAP_INSTALL tap..."

    brew tap "$P_BREW_TAP_INSTALL"
  fi
}

#
# Load config.
#

__load_config() {
  __echo_debug "...load config"

  __load_config_file "$CONFIG_BASE"
  __load_config_file "$CONFIG_FILE"

  if [ -n "$bin_path" ] || [ 1 == "$FORCE_PATH" ]; then
    bin_brew=0
  fi

  if [ 1 == "$FORCE_HOMEBREW" ]; then
    bin_brew=1
  fi

  __echo_debug "bin_path: $bin_path"
  __echo_debug "bin_folder: $bin_folder"
  __echo_debug "bin_file: $bin_file"
  __echo_debug "bin_version: $bin_version"
  __echo_debug "bin_brew: $bin_brew"
  __echo_debug "DEBUG: $DEBUG"
  __echo_debug "SILENT: $SILENT"
  __echo_debug "DOWNLOAD: $DOWNLOAD"
  __echo_debug "FORCE_PATH: $FORCE_PATH"
  __echo_debug "FORCE_HOMEBREW: $FORCE_HOMEBREW"
  __echo_debug "CONFIG_FILE: $CONFIG_FILE"
  __echo_debug "CONFIG_BASE: $CONFIG_BASE"
  __echo_debug "P_PREFIX: $P_PREFIX"
  __echo_debug "P_PATH: $P_PATH"
  __echo_debug "P_BIN: $P_BIN"
  __echo_debug "P_DATA: $P_DATA"
  __echo_debug "P_SCRIPTS: $P_SCRIPTS"
  __echo_debug "P_SEMVER: $P_SEMVER"
  __echo_debug "P_RUBY: $P_RUBY"
  __echo_debug "P_BREW: $P_BREW"
  __echo_debug "P_BREW_INSTALL: $P_BREW_INSTALL"
  __echo_debug "P_BREW_OPENLDAP: $P_BREW_OPENLDAP"
  __echo_debug "P_BREW_LIBICONV: $P_BREW_LIBICONV"
  __echo_debug "P_BREW_TAP: $P_BREW_TAP"
  __echo_debug "P_BREW_TAP_INSTALL: $P_BREW_TAP_INSTALL"
  __echo_debug "P_BREW_CELLAR: $P_BREW_CELLAR"
}

#
# Load config file.
#

__load_config_file() {
  if [ -e "$1" ]; then
    __echo_debug "config_file: $1"

    local value

    while read -r line || [ -n "$line" ]; do
      if [ -n "$line" ]; then
        value=$(__get_value "$line")

        if [ -n "$value" ]; then
          case "$(__get_key "$line")" in
          path)
            if [ 0 == "$FORCE_PATH" ] || { [ 1 == "$FORCE_PATH" ] && [ -n "$value" ]; }; then
              bin_path="$value"
            fi
            ;;
          folder) bin_folder="$value" ;;
          bin) bin_file="$value" ;;
          version) bin_version="$value" ;;
          ?) ;;
          esac
        fi
      fi
    done <"$1"
  fi
}

#
# Load current php variables.
#

__load_current() {
  __echo_debug "...load current"

  local path
  local version

  path="$(readlink "$P_BIN")"
  version=$(__get_version_from_path "$path")

  if [ -n "$version" ]; then
    php_version=$version
    php_bin=$path
  fi

  __echo_debug "php_version: $php_version"
  __echo_debug "php_bin: $php_bin"
}

#
# Load local php versions.
#

__load_local() {
  __echo_debug "...load local"

  if [ 0 == "$bin_brew" ]; then
    __load_from_path
  else
    __load_installed
  fi
}

#
# Load php version from path.
#

__load_from_path() {
  __echo_debug "...load from path"

  __echo_gray "Loading from path..."

  php_found=

  if [ ! -d "$bin_path" ]; then
    __echo_yellow "Path '$bin_path' not found."
  fi

  for d in "$bin_path"/*; do
    if [[ -d $d ]]; then
      __add_version_from_path "$(__format_path "$d/$bin_folder/$bin_file")"
    fi
  done

  __echo_debug "php_found: $php_found"
}

#
# Load installed php version.
#

__load_installed() {
  __echo_debug "...load installed"

  __echo_gray "Loading installed..."

  php_found=

  while read -r i; do
    __add_version_from_path "$(__get_installed_bin_path "$i")" "$i"
  done < <(__get_installed_candidates)

  __echo_debug "php_found: $php_found"
}

#
# Load remote php version.
#

__load_remote() {
  __echo_debug "...load remote"

  __echo_gray "Loading remote..."

  php_found=

  while read -r i; do
    __add_version_from_path "$(__get_downloadable_bin_path "$i")" "$i" "1"
  done < <(__get_downloadables_candidates)

  __echo_debug "php_found: $php_found"
}

#
# Load satisfiable php variables.
#

__load_satisfiable() {
  __echo_debug "...load satisfiable $1"

  local versions
  local version
  local satisfiable
  local best_version

  __load_candidate "$1" "1"

  if [ -n "$php_found" ]; then
    read -r -a versions <<<"$php_found"

    for i in "${versions[@]}"; do
      version="$(__found_version "$i")"
      satisfiable=$(__is_satisfiable "$php_candidate" "$version")

      if [ -n "$satisfiable" ]; then
        [ -z "$php_selected" ] && __echo_gray "Found satisfiable PHP version: PHP $satisfiable..."

        if [ -z "$best_version" ]; then
          best_version=$satisfiable
        fi

        if [ -n "$(__is_satisfiable_latest "$satisfiable" "$best_version")" ]; then
          php_satisfiable_version=$version
          php_satisfiable_package=$(__found_package "$i")
          php_satisfiable_bin=$(__found_bin "$i")
        fi
      fi
    done
  fi

  if [ -z "$php_satisfiable_version" ]; then
    __abort_err "No satisfiable PHP version was found."
  fi

  __echo_debug "php_satisfiable_version: $php_satisfiable_version"
  __echo_debug "php_satisfiable_package: $php_satisfiable_package"
  __echo_debug "php_satisfiable_bin: $php_satisfiable_bin"
}

#
# Load php candidate.
#

__load_candidate() {
  php_selected=
  php_candidate="$1"

  if [ -z "$php_candidate" ] && [ -n "$2" ]; then
    php_selected=1
    php_candidate=$(__select_version)
  fi

  __echo_debug "php_candidate: $php_candidate"
}

#
# Add php version to found.
#

__add_version_from_path() {
  local version
  local path

  version=$(__get_version_from_path "$1" "$3")
  path=$1

  if [ -n "$2" ]; then
    path="$path=$2"
  fi

  if [ -n "$version" ]; then
    php_found=$(__append "$version=$path" "$php_found")
  fi
}

#
# Get php version from path.
#

__get_version_from_path() {
  local version

  if [ -n "$2" ] || [ -f "$1" ]; then
    version=$(__parse_version "$1")

    if [ -n "$version" ] && { [ -n "$2" ] || [ -n "$(__test_version "$1")" ]; }; then
      echo "$version"
    fi
  fi
}

#
# Get installed version candidates.
#

__get_installed_candidates() {
  brew list | grep 'php'
}

#
# Get path for installed php <version>.
#

__get_installed_bin_path() {
  brew list "$1" | grep '/bin/php$'
}

#
# Get downloadable version candidates.
#

__get_downloadables_candidates() {
  brew search '/^php|php@[0-9\.]+$/' | grep 'php'
}

#
# Get path for downloadable php <version>.
#

__get_downloadable_bin_path() {
  path=$(brew info "$1" | grep "$P_BREW_CELLAR")
  echo "${path%% *}"
}

#
# Select local php version.
#

__select_version() {
  local versions

  versions=$(__list_versions)

  if [ -z "$versions" ]; then
    __echo_yellow "No selectable versions found."
  else
    read -r -a versions <<<"$versions"

    case $(__select_option "${versions[@]}") in
    *) echo "${versions[$?]}" ;;
    esac
  fi
}

#
# List local php versions.
#

__list_versions() {
  local found
  local versions

  read -r -a found <<<"$php_found"

  for i in "${found[@]}"; do
    versions="$(__append "$(__found_version "$i")" "$versions")"
  done

  versions=$(echo "$versions" | tr " " "\n" | sort -r -t. -n -k1,1 -k2,2 -k3,3 -k4,4 | tr "\n" " ")

  if [ ! " " == "$versions" ]; then
    echo "$versions"
  fi
}

#
# Install php <version>.
#

__install() {
  __echo_debug "...install $1"

  if [ 1 == "$DOWNLOAD" ]; then
    __load_remote
    __download "$1"
  else
    __load_local
    __load_satisfiable "$1"
    __link "$php_satisfiable_version" "$php_satisfiable_bin"
  fi
}

#
# Update php <version>.
#

__update() {
  __echo_debug "...update $1"

  __load_installed
  __download "$1"
}

#
# Download php <version>.
#

__download() {
  __echo_debug "...download $1"

  __load_satisfiable "$1"

  if [ -n "$php_satisfiable_package" ]; then
    __echo_color "Installing Homebrew $php_satisfiable_package package..."

    __check_brew

    brew install "$php_satisfiable_package"
  fi
}

#
# Link php <version> from <path>.
#

__link() {
  if [ 0 == "$DOWNLOAD" ]; then
    __echo_debug "...link version $1"

    __echo_color "Linking PHP $1..."
    __echo_gray "From $2..."

    unlink "$P_BIN"
    ln -s "$2" "$P_BIN"
  fi
}

#
# Remove the given downloaded version(s).
#
# TODO

__remove() {
  __echo_debug "...remove"

  if [ 0 == "$bin_brew" ]; then
    __abort_err "Cannot uninstall bin version. This only works with Homebrew (without 'path' config)."
  fi
}

#
# Remove all downloaded versions except the installed version.
#
# TODO

__prune() {
  __echo_debug "...prune"

  if [ 0 == "$bin_brew" ]; then
    __abort_err "Cannot uninstall bin version. This only works with Homebrew (without 'path' config)."
  fi
}

#
# Output path for php <version:-current>.
#

__which() {
  __echo_debug "...which"

  __load_current

  local path_bin
  local version

  path_bin=$php_bin

  if [ -n "$1" ]; then
    version=$1

    if [ -z "$(__is_satisfiable_version "$1")" ]; then
      version=
    fi

    __load_local
    __load_satisfiable "$version"

    path_bin=$php_satisfiable_bin
  fi

  __echo_color "$($path_bin -v | head -n 1)"

  if [ "php" == "$path_bin" ]; then
    __echo_gray "Loaded Bin => $(readlink "$P_BIN")"
  else
    __echo_gray "Loaded Bin => $(command -v "$path_bin")"
  fi

  __echo_gray "$($path_bin -i | grep 'Loaded Configuration File')"
}

#
# Execute downloaded php <version> with [args ...].
#

__run() {
  __echo_debug "...run"

  __load_local

  if [ -n "$(__is_satisfiable_version "$1")" ]; then
    __load_satisfiable "$1"
    shift
  else
    __load_satisfiable ""
  fi

  __echo_color "$($php_satisfiable_bin -v | head -n 1)"

  exec "$php_satisfiable_bin" "$@"
}

#
# List local php versions.
#

__list_local() {
  __echo_debug "...list local"

  __load_local

  local versions

  versions=$(__list_versions)

  if [ -n "$versions" ]; then
    __echo_color "PHP versions: $versions"
  else
    __abort_err "Cannot find PHP version."
  fi
}

#
# List remote php versions.
#

__list_remote() {
  __echo_debug "...list remote"

  __load_remote

  local versions

  versions=$(__list_versions)

  if [ -n "$versions" ]; then
    __echo_color "Downloadable PHP versions: $versions"
  else
    __abort_err "Cannot find downloadable PHP version."
  fi
}

#
# Process...
#

unprocessed_args=()

while [[ $# -ne 0 ]]; do
  case "$1" in
  -V | --version)
    __echo "Version $VERSION"
    exit
    ;;
  -h | --help | help)
    __usage
    exit
    ;;
  -T | --trace) DEBUG=1 ;;
  -S | --silent) SILENT=1 ;;
  -d | --download) DOWNLOAD=1 ;;
  -P | --path) FORCE_PATH=1 ;;
  -H | --homebrew) FORCE_HOMEBREW=1 ;;
  run | as | use)
    unprocessed_args=("$@")
    break
    ;;
  *) unprocessed_args+=("$1") ;;
  esac
  shift
done

set -- "${unprocessed_args[@]}"

__init

if test $# -eq 0; then
  __install ""
else
  while test $# -ne 0; do
    case "$1" in
    bin | which)
      __which "$2"
      exit
      ;;
    run | as | use)
      shift
      __run "$@"
      exit
      ;;
    rm | -)
      shift
      __remove "$@"
      exit
      ;;
    prune)
      __prune
      exit
      ;;
    ls | list)
      __list_local
      exit
      ;;
    lsr | ls-remote)
      __list_remote
      exit
      ;;
    uninstall)
      __uninstall
      exit
      ;;
    u | update)
      shift
      __update "$1"
      exit
      ;;
    i | install)
      shift
      __install "$1"
      exit
      ;;
    *)
      __install "$1"
      exit
      ;;
    esac
    shift
  done
fi
