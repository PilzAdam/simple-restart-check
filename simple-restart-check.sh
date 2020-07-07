#!/bin/bash

# A utility script that checks if processes use outdated libraries.
# This is useful to run after an upgrade, to check which processes need to be restarted.
# The main idea to is to check in /proc/$pid/maps for entries marked as "(deleted)".
# See below for a list of 'ignore patterns', for which we don't care if they are marked as "(deleted)"

IGNORE_PATTERNS=(
	"/dev/*"         # don't care about device files
	"/SYSV00000000"  # don't care about SysV shm segments
	"/run/*"         # don't care about temporary run-time files
	"/var/run/*"
	"/memfd:*"       # don't care about temporary memory files
	"/\[aio\]"       # don't care about aio (asynchronous IO) file descriptors

	"/tmp/.gl*"      # temporary OpenGL (?) files, e.g. /tmp/.glWSsluM
	"*/dconf/user"   # dconf file, $HOME/.config/dconf/user
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
shift $((OPTIND -1))

# check that there are no trailing arguments
if [[ $# > 0 ]]
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

# Main part: check all PIDs in $pid
for (( i=0; i<${#pids[@]}; i++ ))
do
	progress $((i+1)) ${#pids[@]}
	pid="${pids[i]}"

	outdated=() # list of all outdated library filenames

	while read -r line
	do
		if [[ "$line" == *" (deleted)" ]]
		then
			file="${line% (deleted)}"

			ignore=""
			for pattern in "${IGNORE_PATTERNS[@]}"
			do
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
		fi
	done < <(cat "/proc/$pid/maps" 2>/dev/null | sed -E 's|^[^ ]+ [^ ]+ [^ ]+ [^ ]+ [^ ]+ +||g' | sort | uniq)
	# /proc/$pid/maps has 6 columns, delimited by spaces; the sed above removes the first 5, leaving only the filename

	if [[ ${#outdated[@]} > 0 ]]
	then
		name="$(basename "$(realpath "/proc/$pid/exe")")"
		name="${name% (deleted)}"

		clearLine
		echo -en "\033[0;35m$name\033[0m (\033[1m$pid\033[0m) uses "

		if [[ ${#outdated[@]} == 1 ]]
		then
			echo "outdated ${outdated[0]}"

		elif [[ -z $verbose ]]
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
