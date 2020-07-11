#!/bin/bash

# A utility script that checks if processes use outdated libraries.
# This is useful to run after an upgrade, to check which processes need to be restarted.
# The main idea to is to check in /proc/$pid/maps for entries marked as executable and "(deleted)".
# See below for a list of 'ignore patterns', for which we don't care if they are marked as "(deleted)"

readonly ignore_patterns=(
	"/dev/*"         # device files
	"/run/*"         # temporary run-time files
	"/var/run/*"
	"/memfd:*"       # temporary memory files, e.g. from a JIT compiler
	"/tmp/.gl*"      # temporary OpenGL (?) files, e.g. /tmp/.glWSsluM
)

readonly c_name="\e[0;35m"    # color used for process name output
readonly c_exe="\e[0;33m"     # color used for exe name when it differs from comm
readonly c_pid="\e[0;1m"      # color used for the PID
readonly c_library="\e[0;31m" # color used for library names
readonly c_error="\e[1;31m"   # color used for error messages
readonly c_warn="\e[1;33m"    # color used for warning messages
readonly c_reset="\e[0m"      # resets color to normal

set -o nounset
set -o errexit
set -o pipefail

pids=() # PIDs to check
verbose="" # whether to print outdated library names if there are more than 1 for a process
fullpath="" # whether to print the full path of libraries or just the filename
use_color="" # wether to use colored output
if [[ -t 1 ]] # if we output to a terminal, use color
then
	use_color="1"
fi

function usage {
	echo "Usage: $(basename "$0") [-p PID]... [-v] [-f] [-c 0|1] [-h]" 1>&2
}

# Helper function to print a colored string
# $1: string to print
# $2: color string in the format "\e[XXm"
function cstr {
	if [[ -z "$use_color" ]]
	then
		echo "${1}"
	else
		echo -e "${2}${1}${c_reset}"
	fi
}

function fail {
	echo "$(cstr "Error" "$c_error"): $*" 1>&2
	exit 2
}

function warn {
	echo "$(cstr "Warning" "$c_warn"): $*" 1>&2
}

while getopts ":p:vfc:h" opt
do
	case "$opt" in
		p) pids+=("$OPTARG") ;;
		v) verbose="1" ;;
		f) fullpath="1" ;;
		c)
			case "$OPTARG" in
				0) use_color="" ;;
				1) use_color="1" ;;
				*)
					echo "$(cstr "Error" "$c_error"): -$opt expects 0 or 1" 1>&2
					exit 1
					;;
			esac
			;;
		h)
			usage
			cat <<EOF 1>&2
Checks which currently running processes use outdated libraries.

Options:
  -p PID   Only check the process with the given PID. Can be given multiple
           times, in which case all explicitly given processes are checked.
  -v       List all outdated libraries for each process.
  -f       Show full library path instead of just the filename.
  -c 0|1   Whether to use colors in output. If not supplied, colored output is
           enabled if stdout goes to a terminal.
  -h       Print this help message and exit.

Exit status:
  0  success
  1  invalid command line option
  2  severe failure during execution
EOF
			exit 0
			;;
		:)
			echo "$(cstr "Error" "$c_error"): -$OPTARG requires an argument" 1>&2
			exit 1
			;;
		*)
			echo "$(cstr "Error" "$c_error"): Invalid option -$OPTARG" 1>&2
			usage
			exit 1
			;;
	esac
done
shift $((OPTIND-1))

# check that there are no trailing arguments
if [[ $# -gt 0 ]]
then
	echo "$(cstr "Error" "$c_error"): Too many arguments" 1>&2
	usage
	exit 1
fi

# if $pids is empty, fill it with all running PIDs
if [[ ${#pids[@]} -eq 0 ]]
then
	ps_output="$(ps -Ao pid --no-headers)" || fail "couldn't get PID list"
	for pid in $ps_output
	do
		pids+=("$pid")
	done
fi

# Helper function to print a nice name for a process
function print_process_name {
	local pid="$1"

	local exe_name=""
	if [[ -f "/proc/$pid/exe" ]]
	then
		if exe_name="$(realpath --physical "/proc/$pid/exe" 2>/dev/null)"
		then
			exe_name="$(basename "${exe_name% (deleted)}")" # exe may be deleted, remove the suffix
		else
			warn "couldn't resolve /proc/$pid/exe"
		fi
	fi

	local comm_name=""
	comm_name="$(cat "/proc/$pid/comm" 2>/dev/null)" || warn "couldn't read /proc/$pid/comm"

	if [[ -z "$exe_name" ]]
	then
		# we only have a comm name
		echo "$(cstr "$comm_name" "$c_name") ($(cstr "$pid" "$c_pid"))"

	elif [[ "$exe_name" = "$comm_name"* ]]
	then
		# comm name is just a truncated version of exe name
		echo "$(cstr "$exe_name" "$c_name") ($(cstr "$pid" "$c_pid"))"

	else
		# comm and exe name differ
		echo "$(cstr "$comm_name" "$c_name") ($(cstr "$exe_name" "$c_exe"), $(cstr "$pid" "$c_pid"))"
	fi
}

# Main part: check all PIDs in $pid
for (( i=0; i<${#pids[@]}; i++ ))
do
	echo -en "[$((i+1))/${#pids[@]}]\r" 1>&2
	pid="${pids[i]}"

	# skip this PID if process is already terminated
	[[ -d "/proc/$pid" ]] || continue

	# warn if maps file doesn't exist
	[[ -f "/proc/$pid/maps" ]] || warn "/proc/$pid/maps doesn't exist"

	outdated=() # list of all outdated libraries we find

	while read -r line
	do
		file="${line% (deleted)}"

		ignore=""
		for pattern in "${ignore_patterns[@]}"
		do
			# shellcheck disable=SC2053
			if [[ "$file" = $pattern ]]
			then
				ignore="1"
				break
			fi
		done

		if [[ -z "$ignore" ]]
		then
			if [[ -z "$fullpath" ]]
			then
				outdated+=("$(basename "$file")")
			else
				outdated+=("$file")
			fi
		fi
	done < <(
			# grep filters for files mapped as executable 'x' and ending with 'deleted'
			# /proc/$pid/maps has 6 columns, delimited by spaces
			# sed removes the first 5, leaving only the filename
			grep -E '^[^ ]+ ..x.*\(deleted\)$' "/proc/$pid/maps" 2>/dev/null \
			| sed -E 's|^[^ ]+ [^ ]+ [^ ]+ [^ ]+ [^ ]+ +||g'                 \
			| sort                                                           \
			| uniq
		)

	if [[ ${#outdated[@]} -gt 0 ]]
	then
		echo -n "$(print_process_name "$pid") uses "

		if [[ ${#outdated[@]} -eq 1 ]]
		then
			echo "outdated $(cstr "${outdated[0]}" "$c_library")"

		elif [[ -z "$verbose" ]]
		then
			echo "multiple outdated libraries"

		else
			echo "multiple outdated libraries:"
			for lib in "${outdated[@]}"
			do
				echo "    $(cstr "$lib" "$c_library")"
			done
		fi
	fi
done
