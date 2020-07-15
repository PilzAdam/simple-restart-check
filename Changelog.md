# Changelog

This project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!-- this changelog is based on https://keepachangelog.com/en/1.0.0/ -->

<!-- ## [Unreleased] -->

## [1.0.0] - 2020-07-15

The first release and initial version of `simple-restart-check.sh`.

### Added

* Basic functionality: listing of processes that use outdated libraries
* Initial set of ignore patterns
* Routine to find a nice human-readable name for processes using outdated libraries
* Option `-v` to always list all outdated libraries in output
* Option `-f` to show full library path in output instead of just the filename
* Option `-p` to only scan the specified process(es)
* Colored output (controllable by `-c` option)
* Option `-h` to show a help message

<!-- Links to releases -->
[Unreleased]: https://github.com/PilzAdam/simple-restart-check/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/PilzAdam/simple-restart-check/releases/v1.0.0
