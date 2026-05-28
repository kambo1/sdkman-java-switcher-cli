#!/usr/bin/env zsh

SDKMAN_INIT="${SDKMAN_INIT:-$HOME/.sdkman/bin/sdkman-init.sh}"
JAVA_DIR="${SDKMAN_CANDIDATES_DIR:-$HOME/.sdkman/candidates}/java"

usage() {
  cat <<'EOF'
sj - small SDKMAN Java picker

Usage:
  sj                 Pick an installed Java and switch to it
  sj use             Pick an installed Java for this shell
  sj default         Pick an installed Java as the SDKMAN default
  sj list            List installed Java versions
  sj versions        List all SDKMAN Java versions
  sj install|add     Pick from all SDKMAN Java versions and install it
  sj uninstall|rm    Pick an installed Java version and uninstall it
  sj current         Show the current SDKMAN Java version
  sj help            Show this help

Use an alias that sources this script to let "sj use" update the current shell.
EOF
}

load_sdkman() {
  if [[ ! -f "$SDKMAN_INIT" ]]; then
    print -u2 "SDKMAN init file not found: $SDKMAN_INIT"
    return 1
  fi

  source "$SDKMAN_INIT"
}

strip_ansi() {
  sed -E $'s/\x1B\\[[0-9;]*[[:alpha:]]//g'
}

installed_versions() {
  if [[ ! -d "$JAVA_DIR" ]]; then
    return 0
  fi

  find "$JAVA_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; \
    | awk '$0 != "current"' \
    | sort -Vr
}

is_installed_version() {
  local version="$1"

  [[ -d "$JAVA_DIR/$version" ]]
}

marked_versions() {
  local version current

  current="$(current_version || true)"
  while IFS= read -r version; do
    [[ -n "$version" ]] || continue

    if [[ "$version" == "$current" ]]; then
      print "> * $version"
    elif is_installed_version "$version"; then
      print "  * $version"
    else
      print "    $version"
    fi
  done
}

available_versions() {
  sdk list java \
    | strip_ansi \
    | awk '
      /^[[:space:]]*[*> ]*[0-9][^[:space:]]*-[[:alnum:]_.-]+[[:space:]]*$/ {
        gsub(/^[[:space:]]*[*> ]*/, "", $0)
        gsub(/[[:space:]]+$/, "", $0)
        print
        next
      }
      /\|/ {
        n = split($0, parts, "|")
        for (i = n; i >= 1; i--) {
          id = parts[i]
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
          if (id ~ /^[0-9][[:alnum:]._-]*-[[:alnum:]_.-]+$/) {
            print id
            next
          }
        }
      }
    ' \
    | sort -uV
}

current_version() {
  if [[ -L "$JAVA_DIR/current" ]]; then
    basename "$(readlink "$JAVA_DIR/current")"
  else
    sdk current java 2>/dev/null | strip_ansi | awk '/Using java version/ { print $4 }'
  fi
}

is_sourced() {
  [[ "${ZSH_EVAL_CONTEXT:-}" == *:file:* || "${ZSH_EVAL_CONTEXT:-}" == file:* ]]
}

pick() {
  emulate -L zsh
  set +xv
  setopt typeset_silent

  local title="$1"
  shift
  local hint="${1:-Use arrows or j/k, Enter/l to select, q to quit.}"
  shift
  local items=("$@")
  local count=${#items[@]}
  local selected=1
  local key
  local current
  local tty_fd
  local i marker suffix
  local installed_marker
  local rows visible start end

  if (( count == 0 )); then
    print -u2 "Nothing to pick."
    return 1
  fi

  if ! { exec {tty_fd}<>/dev/tty } 2>/dev/null; then
    print -u2 "Interactive picker requires a TTY."
    return 1
  fi

  current="$(current_version || true)"
  print -n "\e[?25l" >&$tty_fd

  while true; do
    rows="$(stty size <&$tty_fd 2>/dev/null | awk '{ print $1 }')"
    [[ "$rows" == <-> ]] || rows=24
    visible=$(( rows - 5 ))
    (( visible < 3 )) && visible=3
    (( visible > count )) && visible=$count

    start=$(( selected - (visible / 2) ))
    (( start < 1 )) && start=1
    end=$(( start + visible - 1 ))
    if (( end > count )); then
      end=$count
      start=$(( end - visible + 1 ))
      (( start < 1 )) && start=1
    fi

    print -n "\e[H\e[2J" >&$tty_fd
    print "$title ($selected/$count)" >&$tty_fd
    print "$hint" >&$tty_fd
    print >&$tty_fd

    if (( start > 1 )); then
      print "   ..." >&$tty_fd
    fi

    for i in {$start..$end}; do
      marker=" "
      suffix=""
      installed_marker=" "
      [[ $i -eq $selected ]] && marker=">"
      is_installed_version "${items[$i]}" && installed_marker="*"
      [[ "${items[$i]}" == "$current" ]] && suffix="  (current)"
      print " $marker $installed_marker ${items[$i]}$suffix" >&$tty_fd
    done

    if (( end < count )); then
      print "   ..." >&$tty_fd
    fi

    IFS= read -rs -k 1 key <&$tty_fd
    case "$key" in
      $'\e')
        IFS= read -rs -k 2 key <&$tty_fd || true
        case "$key" in
          '[A') (( selected-- )) ;;
          '[B') (( selected++ )) ;;
        esac
        ;;
      k) (( selected-- )) ;;
      j) (( selected++ )) ;;
      q)
        print -n "\e[?25h" >&$tty_fd
        exec {tty_fd}>&-
        return 1
        ;;
      l|$'\n'|$'\r')
        print -n "\e[H\e[2J\e[?25h" >&$tty_fd
        exec {tty_fd}>&-
        REPLY="${items[$selected]}"
        PICK_KEY="$key"
        return 0
        ;;
      h)
        print -n "\e[H\e[2J\e[?25h" >&$tty_fd
        exec {tty_fd}>&-
        REPLY="${items[$selected]}"
        PICK_KEY="$key"
        return 0
        ;;
    esac

    (( selected < 1 )) && selected=$count
    (( selected > count )) && selected=1
  done
}

pick_from_command() {
  local title="$1"
  local command_name="$2"
  local -a items
  local tty_fd

  if { exec {tty_fd}<>/dev/tty } 2>/dev/null; then
    print -n "\e[H\e[2J" >&$tty_fd
    print "Loading $title..." >&$tty_fd
    exec {tty_fd}>&-
  fi

  items=("${(@f)$($command_name | awk 'NF')}")
  pick "$title" "" "${items[@]}"
}

show_loading() {
  local title="$1"
  local tty_fd

  if { exec {tty_fd}<>/dev/tty } 2>/dev/null; then
    print -n "\e[H\e[2J" >&$tty_fd
    print "Loading $title..." >&$tty_fd
    exec {tty_fd}>&-
  fi
}

version_major() {
  local version="$1"

  print "${version%%[.-]*}"
}

pick_available_java() {
  local -a versions majors filtered choices
  local version major label

  show_loading "Available SDKMAN Java versions"
  versions=("${(@f)$(available_versions | awk 'NF')}")

  if (( ${#versions[@]} == 0 )); then
    print -u2 "No available Java versions found."
    return 1
  fi

  majors=("${(@f)$(
    print -l "${versions[@]}" \
      | awk -F'[.-]' '{ count[$1]++ } END { for (major in count) print major "\t" count[major] }' \
      | sort -nr \
      | awk -F'\t' '{ print "Java " $1 " (" $2 ")" }'
  )}")

  while true; do
    pick "Available Java major versions" "" "${majors[@]}" || return 1
    label="$REPLY"
    major="${label#Java }"
    major="${major%% *}"

    filtered=()
    for version in "${versions[@]}"; do
      if [[ "$(version_major "$version")" == "$major" ]]; then
        filtered+=("$version")
      fi
    done

    pick "Java $major distributions" "Use arrows or j/k, h to go back, Enter/l to install, q to quit." "${filtered[@]}" || return 1
    [[ "$PICK_KEY" == "h" ]] && continue

    return 0
  done
}

use_java() {
  local version="$1"

  sdk use java "$version"
}

default_java() {
  local version="$1"

  sdk default java "$version"
}

sj_main() {
  emulate -L zsh
  set +xv

  local cmd="${1:-use}"
  local version

  case "$cmd" in
    help|-h|--help)
      usage
      ;;
    list|ls)
      installed_versions | marked_versions
      ;;
    versions|available)
      load_sdkman || return 1
      available_versions | marked_versions
      ;;
    current)
      load_sdkman || return 1
      sdk current java
      ;;
    use|switch)
      load_sdkman || return 1
      pick_from_command "Installed Java versions" installed_versions || return 1
      version="$REPLY"
      use_java "$version"
      ;;
    default)
      load_sdkman || return 1
      pick_from_command "Installed Java versions" installed_versions || return 1
      version="$REPLY"
      default_java "$version"
      ;;
    install|add)
      load_sdkman || return 1
      pick_available_java || return 1
      version="$REPLY"
      sdk install java "$version"
      ;;
    uninstall|rm)
      load_sdkman || return 1
      pick_from_command "Installed Java versions" installed_versions || return 1
      version="$REPLY"
      sdk uninstall java "$version"
      ;;
    *)
      print -u2 "Unknown command: $cmd"
      print -u2
      usage >&2
      return 2
      ;;
  esac
}

sj_main "$@"
sj_status=$?

unfunction sj_main 2>/dev/null || true

if is_sourced; then
  return "$sj_status"
fi

exit "$sj_status"
