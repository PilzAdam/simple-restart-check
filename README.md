# simple-restart-check

A simple Bash script that checks if processes use outdated libraries. This is useful to run after an upgrade, to check which processes need to be restarted.

## How do I use it?

Simply run `simple-restart-check.sh`. By default, it checks all processes that are currently running. Note that it requires root priviliges to check processes not owned by the user who runs the script.

Command-line options:
| Option                   | Description                                                                                                                       |
|:------------------------:|-----------------------------------------------------------------------------------------------------------------------------------|
| <code>-p&nbsp;PID</code> | Only check the process with the given PID. Can be given multiple times, in which case all explicitly given processes are checked. |
| `-v`                     | List all outdated libraries for each process, instead of omitting the list if there is more than 1 outdated library.              |
| `-f`                     | Show full library path instead of just the filename.                                                                              |
| <code>-c&nbsp;0|1</code> | Whether to use colors in output. If not supplied, colored output is enabled if stdout goes to a terminal.                         |
| `-h`                     | Print a help message and exit.                                                                                                    |

## How does it work?

The file `/proc/$pid/maps` contains all memory-mapped files of a process, including all libraries. For example, my Bash process looks like this (many lines ommited for brevity):
```
55f6b7e24000-55f6b7eb3000 r-xp 0001f000 08:11 6560573            /usr/bin/bash
55f6b8b72000-55f6b905b000 rw-p 00000000 00:00 0                  [heap]
7ff5ee0e3000-7ff5ee0ea000 r-xp 00003000 08:11 6557176            /usr/lib/libnss_files-2.31.so
7ff5ee0f4000-7ff5ee57e000 r--p 00000000 08:11 6598737            /usr/lib/locale/locale-archive
7ff5ee597000-7ff5ee5d3000 r-xp 00017000 08:11 6557839            /usr/lib/libncursesw.so.6.2
7ff5ee616000-7ff5ee763000 r-xp 00025000 08:11 6557086            /usr/lib/libc-2.31.so
7ff5ee7b9000-7ff5ee7bb000 r-xp 00001000 08:11 6557120            /usr/lib/libdl-2.31.so
7ff5ee7d4000-7ff5ee7fc000 r-xp 00016000 08:11 6560542            /usr/lib/libreadline.so.8.0
7ff5ee80f000-7ff5ee812000 rw-p 00000000 00:00 0
7ff5ee845000-7ff5ee865000 r-xp 00002000 08:11 6557015            /usr/lib/ld-2.31.so
7ff5ee870000-7ff5ee871000 rw-p 00000000 00:00 0
7fff98e84000-7fff98ea5000 rw-p 00000000 00:00 0                  [stack]
7fff98f70000-7fff98f74000 r--p 00000000 00:00 0                  [vvar]
7fff98f74000-7fff98f76000 r-xp 00000000 00:00 0                  [vdso]
ffffffffff600000-ffffffffff601000 --xp 00000000 00:00 0          [vsyscall]
```

The rightmost column contains the filename (if any) that is mapped to the specified region in the processes memory. Note that there is a bunch of junk that we don't care about, like `[heap]` or device files (not shown here).

The main idea to is to check for entries in `/proc/$pid/maps` that are marked as `(deleted)`. This occurs if the file that was mapped (i.e. the library that was loaded when the process started) does not exist anymore - either because it was deleted or because it was overwritten (e.g. during an upgrade).

In practice, this may look like this:
```
7ff5ee616000-7ff5ee763000 r-xp 00025000 08:11 6557086            /usr/lib/libc-2.31.so (deleted)
```
Here, the process uses a version of `libc` that does no longer exist. `simple-restart-check.sh` reports:
```
bash (1234) uses outdated libc-2.31.so
```
To filter out the unwanted junk mentioned above, `simple-restart-check.sh` only considers files that are marked as executable (`x` in the second column). Additionally, it has a list of patterns to ignore (see `IGNORE_PATTERNS` close to the top of the script).
