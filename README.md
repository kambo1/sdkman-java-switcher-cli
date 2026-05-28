# SDKMAN Java Picker

`sj` is a small zsh helper for picking Java versions managed by SDKMAN.

## Prerequisites

- zsh
- SDKMAN installed and initialized at `~/.sdkman/bin/sdkman-init.sh`
- Java managed through SDKMAN: `sdk install java <version>`
- Network access for `sj install` / `sj add` when fetching the SDKMAN catalog
- An interactive terminal for the picker UI

## Commands

```sh
./sj          # same as ./sj use
./sj use      # pick an installed Java for this shell
./sj default  # pick an installed Java as the SDKMAN default
./sj list     # list installed Java versions
./sj install  # pick Java major version, then distribution/version to install
./sj add      # same as install
./sj uninstall # pick an installed Java and uninstall it
./sj rm       # same as uninstall
./sj current  # show the current SDKMAN Java version
```

The picker supports arrow keys, `j`/`k`, `h`/`l`, Enter, and `q`.
Installed versions are marked with `*`; the current version is marked with `>`.

`./sj install` groups the large SDKMAN catalog by major version first, for example
`Java 21`, then shows the matching distributions and patch versions. Press `l`
or Enter to move into a major version, and press `h` in the distribution list
to return to the major-version list.

## Current Shell Switching

A normal script cannot change the environment of the shell that launched it.
Use `sj default` to persist a Java version as SDKMAN's default.

To switch only the current shell session, source the script instead:

```sh
source ./sj
```

For convenience, add an alias to your shell config:

```sh
alias sj='source /path/to/sj'
```
