# WIPER

Shell script to securely wipe specific files or folders, or cover your tracks on UNIX systems.
Designed for private people. This script is intended for testing and educational purposes.

**It might break your system if misused, so use it at your own risk.**

## Installation

`wiper.sh` works on UNIX-like systems (Linux distros, macOS). Install it as follows:

```bash
wget --quiet -O /usr/local/bin/wiper "https://raw.githubusercontent.com/hyp3rd/wiper/main/wiper.sh"
chmod +x /usr/local/bin/wiper
# or
curl -o /usr/local/bin/wiper "https://raw.githubusercontent.com/hyp3rd/wiper/main/wiper.sh"
chmod +x /usr/local/bin/wiper
```

## Requirements

- `bash` 3.2 or newer (works with the macOS system bash)
- Core POSIX utilities: `dd`, `find`, `awk`, `grep`, `tr`, `head`, `stat`, `mktemp`
- Optional: `shred` (Linux) — preferred over the `dd` loop when present
- Optional: `lsof` — used by `private` to list open log files

`private` mode is **Linux only** — it enumerates accounts from `/etc/passwd`, which is not the source of truth on macOS.

System paths (`/var/log/*`, `/etc/passwd`, etc.) require root. Run with `sudo` for `private` and for `disable-logging` against system directories.

## Usage

```text
wiper [command] [flags] /path/to/wipe
```

### Commands

| Command           | Description                                                              |
| ----------------- | ------------------------------------------------------------------------ |
| `wipe`            | Securely overwrite the content of a file or folder                       |
| `erase`           | Truncate the content of a file or folder (does not unlink)               |
| `remove`          | Delete a file or folder (`rm -rf`)                                       |
| `disable-logging` | Symlink every `*.log` under `<path>` to `/dev/null`                      |
| `private`         | Cover your tracks on the system (Linux only)                             |
| `help`            | Top-level help — also `wiper <command> --help` for command-specific help |
| `version`         | Print the version number of wiper                                        |

### Flags

| Flag                  | Description                                                                                |
| --------------------- | ------------------------------------------------------------------------------------------ |
| `-h`, `--help`        | Help for `wiper` or for a specific command                                                 |
| `-i`, `--iterations`  | Number of overwrite iterations for `wipe` (default `8`); e.g., `wiper wipe -i 64 <path>`   |
| `-t`, `--timespan`    | Minutes to consider a log file recently modified (default `120`); used by `private`        |
| `-s`, `--silent`      | No confirmation prompts                                                                    |
| `-r`, `--recursive`   | For `wipe`, `erase`, `remove`, recurse into descendant directories                         |

### Examples

```bash
wiper wipe ~/secrets.txt                  # 8 random-byte passes
wiper wipe -i 64 -s ~/secrets.txt         # 64 passes, no prompt
wiper erase -r ~/scratch/                 # truncate every file under scratch/
wiper remove -s ~/scratch/                # rm -rf, no prompt
wiper disable-logging /var/log            # symlink every *.log under /var/log → /dev/null
sudo wiper private                        # cover tracks (Linux)
wiper wipe --help                         # per-command help
```

Use `wiper <command> --help` for command-specific details.

## Breaking changes (v0.10.0)

- **`disable-logging` now requires an explicit `<root>` path argument.** The previous behavior walked `/` and symlinked every match — a footgun that could brick application logs, dependency caches (`node_modules`, browser caches), and unrelated `*.log` files. To get the old scope, pass `/` explicitly: `wiper disable-logging /` (not recommended).
- **`private` mode now exits with an error on macOS** instead of silently doing nothing useful. macOS does not ship with `/etc/passwd` populated.

## Security caveats

Secure overwrite is only meaningful on a small subset of modern storage:

- **SSDs**: wear leveling means logical-block writes do not reliably overwrite the physical cells holding old data. Use full-disk encryption + a TRIM-aware secure erase from the drive's controller (ATA Secure Erase, NVMe Sanitize) instead.
- **Copy-on-write filesystems** (APFS, Btrfs, ZFS): old blocks may persist as snapshots, redirected writes, or in past-version metadata. Overwriting the logical file does nothing to these.
- **Journaled filesystems** (ext3/4, NTFS, HFS+): the journal may retain copies of recently-written data.

`wiper` is best-effort on modern storage. If your threat model requires forensic-grade data destruction, encrypt the disk before writing sensitive data and destroy the keys (or the drive).

## Disclaimer

This software is provided as-is, without warranty of any kind. Use at your own risk. The author is not responsible for any damage caused by this software.

## License

MIT — see [LICENSE](LICENSE) for details.

[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fhyp3rd%2Fwiper.svg?type=large)](https://app.fossa.com/projects/git%2Bgithub.com%2Fhyp3rd%2Fwiper?ref=badge_large)

## Author

Software architect with 15+ years building distributed systems and cloud-native platforms across banking,
defense, and product startups. I work with challenges and research. Heavy on Go, Python, TypeScript and
microservices. Comfortable across distributed infrastructure, complexity, security, and product.
Feel free to hook me up on [LinkedIn](https://www.linkedin.com/in/francesco-cosentino/).
