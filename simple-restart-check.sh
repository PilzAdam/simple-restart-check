#!/bin/bash

# A utility script that checks if processes use outdated libraries.
# This is useful to run after an upgrade, to check which processes need to be restarted.
# The main idea to is to check in /proc/$pid/maps for entries marked as executable and "(deleted)".
# See below for a list of 'ignore patterns', for which we don't care if they are marked as "(deleted)"

IGNORE_PATTERNS=(
	"/dev/*"         # device files
	"/run/*"         # temporary run-time files
	"/var/run/*"
	"/memfd:*"       # temporary memory files, e.g. from a JIT compiler
	"/tmp/.gl*"      # temporary OpenGL (?) files, e.g. /tmp/.glWSsluM
)

pids=() # PIDs to check
verbose="" # whether to print outdated library names if there are more than 1 for a process
fullpath="" # whether to print the full path of libraries or just the filename

function usage {
	echo "Usage: $(basename "$0") [-p PID]... [-v] [-f] [-h]" 1>&2
}

while getopts ":p:vfh" opt
do
	case "$opt" in
		p) pids+=("$OPTARG") ;;
		v) verbose="1" ;;
		f) fullpath="1" ;;
		h)
			usage
			echo "Checks which currently running processes use outdated libraries." 1>&2
			echo "" 1>&2
			echo "Options:" 1>&2
			echo "  -p PID   Only check the process with the given PID. Can be given multiple" 1>&2
			echo "           times, in which case all explicitly given processes are checked." 1>&2
			echo "  -v       List all outdated libraries for each process." 1>&2
			echo "  -f       Show full library path instead of just the filename." 1>&2
			echo "  -h       Print this help message and exit." 1>&2
			echo "" 1>&2
			echo "Exit status:" 1>&2
			echo "  0  success" 1>&2
			echo "  1  invalid command line option" 1>&2
			exit 0
			;;
		:)
			echo "Error: -${OPTARG} requires an argument" 1>&2
			exit 1
			;;
		*)
			echo "Error: Invalid option -${OPTARG}"
			usage
			exit 1
			;;
	esac
done
shift $((OPTIND-1))

# check that there are no trailing arguments
if [[ $# -gt 0 ]]
then
	usage
	exit 1
fi

# if $pids is empty, fill it with all running PIDs
if [[ ${#pids[@]} == 0 ]]
then
	for pid in $(ps -Ao pid --no-headers)
	do
		pids+=("$pid")
	done
fi


# Some helper functions for logging progress
function progress {
	echo -n "[$1/$2]" >&2
}
function clearLine {
	echo -en "\r             \r" >&2
}

# Helper function to print a nice name for a process
function printProcessName {
	local pid="$1"

	local exeName
	if [[ -f "/proc/$pid/exe" ]]
	then
		exeName="$(basename "$(realpath "/proc/$pid/exe")")"
		exeName="${exeName% (deleted)}" # exe may be deleted, remove the suffix
	fi

	local commName
	commName="$(cat "/proc/$pid/comm")"

	if [[ -z "$exeName" ]]
	then
		# we only have a comm name
		echo -ne "\033[0;35m$commName\033[0m (\033[1m$pid\033[0m)"

	elif [[ "$exeName" == "$commName"* ]]
	then
		# comm name is just a truncated version of exe name
		echo -ne "\033[0;35m$exeName\033[0m (\033[1m$pid\033[0m)"

	else
		# comm and exe name differ
		echo -ne "\033[0;35m$commName\033[0m (\033[0;33m$exeName\033[0m, \033[1m$pid\033[0m)"
	fi
}

# Main part: check all PIDs in $pid
for (( i=0; i<${#pids[@]}; i++ ))
do
	progress $((i+1)) ${#pids[@]}
	pid="${pids[i]}"

	if [[ ! -d "/proc/$pid" ]]
	then
		# process already terminated
		clearLine
		continue
	fi

	outdated=() # list of all outdated libraries we find

	while read -r line
	do
		file="${line% (deleted)}"

		ignore=""
		for pattern in "${IGNORE_PATTERNS[@]}"
		do
			# shellcheck disable=SC2053
			if [[ "$file" == $pattern ]]
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
		clearLine
		printProcessName "$pid"
		echo -en " uses "

		if [[ ${#outdated[@]} == 1 ]]
		then
			echo "outdated ${outdated[0]}"

		elif [[ -z "$verbose" ]]
		then
			echo "multiple outdated libraries"

		else
			echo "multiple outdated libraries:"
			for lib in "${outdated[@]}"
			do
				echo "    $lib"
			done
		fi
	fi

	clearLine
done
