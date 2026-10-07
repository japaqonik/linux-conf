# linux-conf

Personal Linux configuration (bash, tmux, starship, neovim).

## Install

```sh
./install.sh            # symlink dotfiles into place (default)
./install.sh --copy     # copy files instead of symlinking
./install.sh --no-starship   # skip installing starship
./install.sh --no-neovim     # skip installing neovim
./install.sh --bashrc PATH   # write the managed block to PATH instead of ~/.bashrc
./install.sh --dry-run  # preview changes without applying them
```

### Choosing where the shell config goes

By default the managed block is written to `~/.bashrc`. On machines where
`~/.bashrc` is not writable but is set up to source another file you *can*
edit, point the installer at that file:

```sh
./install.sh --bashrc ~/.bashrc.local
# or via environment variable:
LINUX_CONF_BASHRC=~/.bashrc.local ./install.sh
```

Precedence: `--bashrc` > `LINUX_CONF_BASHRC` > `~/.bashrc`. The installer
checks that the target is writable (or creatable) and fails early with a
clear message otherwise.

### What it does

1. Places config files into their proper locations:

   | Repo path                | Destination               |
   |--------------------------|---------------------------|
   | `.bashrc.tmux`           | `~/.bashrc.tmux`          |
   | `.tmux.conf`             | `~/.tmux.conf`            |
   | `.config/starship.toml`  | `~/.config/starship.toml` |
   | `.config/nvim/`          | `~/.config/nvim/`         |
   | `bin/`                   | `~/bin/`                  |

2. Installs [starship](https://starship.rs/) if not already present
   (via the official installer; uses its default location, which may
   prompt for sudo). Skip with `--no-starship`.

3. Installs [neovim](https://github.com/neovim/neovim/blob/master/INSTALL.md)
   if not already present, from the official release tarball into
   `/opt/nvim-linux-<arch>` (may prompt for sudo). Arch is auto-detected
   (`x86_64` / `arm64`). Skip with `--no-neovim`.

4. Injects a managed block into `~/.bashrc` that:
   - initializes starship (reads `~/.config/starship.toml` by default)
   - adds the neovim bin dir to `PATH` if `/opt/nvim-linux-<arch>/bin` exists
     (per the neovim install docs — nothing else puts this on `PATH`)
   - sources the tmux auto-attach snippet (`[ -f ~/.bashrc.tmux ] && . ~/.bashrc.tmux`)

### Notes

- Existing files are backed up to `~/.linux-conf-backup/<timestamp>/`
  before being replaced.
- The managed block is delimited by
  `# >>> linux-conf managed block >>>` / `# <<< ... <<<` and is safe to
  re-run — it strips and regenerates itself each time (idempotent).
- The installer removes the old standalone `eval "$(starship init bash)"`
  line, since the managed block now owns starship init.
- The tmux snippet is sourced from `~/.bashrc.tmux` rather than inlined. If
  your `~/.bashrc.user` already has this source line, you can remove it there
  to avoid duplication (sourcing twice is harmless — the auto-attach is
  guarded by `[[ -z "$TMUX" ]]`).
