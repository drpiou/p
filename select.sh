#!/usr/bin/env bash

# Renders a text based list of options that can be selected by the
# user using up, down and enter keys and returns the chosen option.
#
# https://unix.stackexchange.com/a/415155
#
#   Arguments   : list of options, maximum of 256
#                 "opt1" "opt2" ...
#   Return value: selected index (0 for opt1, 1 for opt2 ...)#

__select_option() {
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

__select_option "$@" 1>&2

result=$?

echo $result
