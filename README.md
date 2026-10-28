# ZCode Puffin TUI — preview releases

Preview builds of the ZCode Puffin terminal UI (`zcode`). This repository holds the installer, the
version pointer, the checksums and the release notes; the binaries are attached to its
[releases](https://github.com/Linyxus/z-code-puffin-releases/releases).

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/Linyxus/z-code-puffin-releases/main/install.sh | sh
```

Installs `~/.local/bin/zcode` for macOS (Apple Silicon, Intel) and Linux (arm64, x64). Options via
environment variables:

| Variable             | Meaning                                    | Default        |
| -------------------- | ------------------------------------------ | -------------- |
| `PUFFIN_VERSION`     | install this version instead of the latest | `latest`       |
| `PUFFIN_INSTALL_DIR` | where `zcode` goes                         | `~/.local/bin` |
| `PUFFIN_TARGET`      | override platform detection                | from `uname`   |

Windows: download `zcode-windows-<arch>.exe` from a release's assets by hand (only when the release
built it).

## Use

```sh
zcode                      # open the TUI
zcode "fix the footer"     # open it and send a first message
zcode continue             # reopen the latest session in this folder
zcode resume [id]          # reopen a session (no id: pick from a list)
zcode exec "list the TODOs" # run one turn without the TUI and print the reply
zcode update               # replace zcode with the latest release (--check only looks)
zcode help                 # options (-m model, -e effort, --mode) and the rest
```

## Layout

```
install.sh                       the installer (source of truth: packages/tui/release/install.sh in z-code)
latest                           the version the installer picks by default
releases/<version>/SHA256SUMS    checksums of that version's binaries
releases/<version>/build.json    commit, app and CLI versions, targets, build time
NOTES                            what's new in each version, newest first
```

Binaries: `https://github.com/Linyxus/z-code-puffin-releases/releases/download/v<version>/zcode-<target>`,
and a gzip-compressed `zcode-<target>.gz` beside each.

The welcome block of the TUI and `zcode version` show `<puffin version> · cli <cli version> · <commit>`;
quote it in bug reports. Releases are cut from the z-code repository with `pnpm --dir packages/tui release`.
