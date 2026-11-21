# Research: can dotfiles' tests run inside a workspace

Resolves #104 (Research: can dotfiles' tests run inside a workspace). Researched 2026-11-21.

**Question.** Can the `dotfiles` test suite run in a Coder workspace on the bakery image (Linux arm64, no Docker daemon, non-root), so OpenCode can verify its own change? If not, what is the smallest check that can? Which parts are macOS-only?

**Sources.**
- `jangroth/dotfiles` at `e5c3702` (= `origin/main` on the research date), read from the local clone.
- `jangroth/homekube-bakery` at tag `coder-workspace/0.3.0`: `CONTRACT.md`, `images/coder-workspace/Dockerfile`.
- `homekube-apps/manual/coder-templates/kubernetes/main.tf`, which pins `coder-workspace:0.3.0@sha256:92837412…`.
- `docs/specs/012-workspace-egress.md`.
- Experiments: the pinned image run under Docker Desktop on darth (arm64 Linux VM), as the contract tests run it: `--user 1000:1000 --cap-drop ALL --security-opt no-new-privileges`, with an empty uid-1000 tmpfs on `/home/coder`.

## Answer

**Yes, but only after a user-space bootstrap.** The whole dotfiles test suite is `tests/lint.sh` (`make lint`). On the image as shipped it stops at once with `lint: missing required tools: zsh shfmt shellcheck python3`. A non-root bootstrap of about 5 seconds installs all four under `$HOME`, and then lint passes 55/55. With two errors deliberately introduced it reports 53 passed, 2 failed and exits non-zero, so the check does catch real breakage. On macOS the same commit passes 56/56; the extra check is tmux, which lint skips when tmux is absent.

The Docker path (`make docker-build` / `docker-run`) cannot run in a workspace. Running the setup itself (`make install`) isn't a meaningful check there either (see below).

## What the "test suite" actually is

- `tests/` contains only `lint.sh`; the `Makefile`'s `lint` target runs it. There are no Python tests. `pyproject.toml` is a stub (`dependencies = []`, `requires-python >= 3.14`), `main.py` prints "Hello from dotfiles!", and `uv` plays no part in testing.
- `lint.sh` fails fast unless `zsh`, `shfmt`, `shellcheck`, `python3` (with `tomllib`) are present. It then runs:
  - `bash -n`, `shfmt -d -i 4` and `shellcheck` on the `scripts/`, `docker/` and `tests/` shell files;
  - `zsh -n` on the zsh config, completions, functions and aliases;
  - JSON and TOML parsing via `python3`, and `git config --file … --list`;
  - a tmux config load, only if `tmux` is on PATH.
- None of the `.github/workflows` (`changelog.yml`, `claude.yml`, `claude-code-review.yml`) runs lint, so no CI result can stand in for a local run. `dotfiles/CLAUDE.md` says "Run `make lint` before committing".
- `docker/` builds a `debian:12.13-slim` image with the lint tools and more, for running `make install` interactively. It needs a Docker daemon.

## What the workspace image provides

From the `coder-workspace/0.3.0` Dockerfile and contract, confirmed by running the image:

- Base `debian:13-slim` (trixie), aarch64; user `coder` (uid 1000); no `sudo`; no setuid binaries; `USER coder`.
- Installed: `curl git openssh-client bash tree ca-certificates`, plus `opencode` and `gh`.
- Missing: `zsh`, `shfmt`, `shellcheck`, `python3`, `make`, `tmux`, `uv`, `xz`, `zstd`.
- Present from the Debian base, and needed by the bootstrap: `apt-get`, `dpkg-deb`, `tar`, `gzip`, `tput`.
- Writable places: the template mounts a 2Gi Longhorn PVC at `/home/coder` (persists across stop/start) and `/tmp`. The memory limit is 1Gi by default, 2Gi optionally (`main.tf`).

## Bootstrap that works (verified)

This runs as uid 1000 with no privileges. It reproduces exactly what was run in the experiment:

```bash
A="$HOME/.cache/apt"
mkdir -p "$A/lists/partial" "$A/archives/partial" "$A/debs" "$HOME/.local/opt" "$HOME/.local/bin"
APT=(-o "Dir::State::Lists=$A/lists" -o "Dir::Cache=$A" -o Debug::NoLocking=1 -o APT::Sandbox::User=coder)
apt-get "${APT[@]}" update
(cd "$A/debs" && apt-get "${APT[@]}" download zsh zsh-common shfmt shellcheck make)
for d in "$A"/debs/*.deb; do dpkg-deb -x "$d" "$HOME/.local/opt"; done
for t in zsh shfmt shellcheck make; do ln -sf "$HOME/.local/opt/usr/bin/$t" "$HOME/.local/bin/$t"; done
curl -fsSL https://github.com/astral-sh/uv/releases/latest/download/uv-aarch64-unknown-linux-gnu.tar.gz \
  | tar xz -C "$HOME/.local/bin" --strip-components=1
export PATH="$HOME/.local/bin:$PATH"
uv python install 3.14 --default    # provides python3 with tomllib
make lint                            # or ./tests/lint.sh
```

Observed in the experiment:

- apt complains that it can't clean `/var/cache/apt/archives/partial` but carries on.
- The `apt-get download` + `dpkg-deb -x` steps fetch about 11 MB and install `zsh 5.9`, `shfmt 3.8.0`, `shellcheck 0.10.0` and GNU make.
- uv 0.13.9 installs CPython 3.14.10.
- The whole of `$HOME` came to about 217 MB, and the run took about 5 s on a fast connection.
- zsh's shared libraries resolved from the base image without extra packages. `apt-get download` doesn't pull dependencies, so this holds only while the base image still ships them.

## Caveats

- **Not run on a Pi or in a real workspace.** It was tested on darth's arm64 Docker, using the contract tests' restrictions. The template's own pod securityContext (`run_as_user 1000`, `allow_privilege_escalation false`, `seccomp RuntimeDefault`) is the same or looser, so no difference is expected.
- **Egress.** The experiment had direct internet access. Spec 012 currently says workspace egress is open. Once the `workspace-egress` policy lands, every download goes through the Agent Vault proxy, which is `any-host` but decrypts TLS.
  - apt uses plain `http://deb.debian.org` through `HTTP_PROXY`.
  - `curl` and `uv` must trust the proxy CA. The template sets `CURL_CA_BUNDLE`/`SSL_CERT_FILE` to the bundle that spec 012 extends with `agent-vault-ca.crt`; uv honours `SSL_CERT_FILE`.
  - None of this was verified behind the proxy.
- **Tool versions differ from macOS.** darth has shfmt 3.14.1, shellcheck 0.11.0, Python 3.15.2 and tmux 3.8. Debian trixie gives shfmt 3.8.0 and shellcheck 0.10.0. A formatting or lint rule that differs between those versions could pass in the workspace and fail on the Mac, or the other way round.
  - Exact versions can be had from the upstream static release binaries instead (shfmt ships a raw `linux_arm64` binary).
  - shellcheck's aarch64 tarball is `.tar.xz`, and the image has no `xz`. Extract it with Python's `tarfile` once Python is installed.
- **The tmux check is skipped** (55 vs 56 checks). The `tmux` .deb needs libraries the base image lacks (libevent, libutempter), so `dpkg-deb -x` alone isn't enough.
- **The bootstrap isn't guaranteed.** It depends on the base image keeping `apt-get`/`dpkg-deb` and zsh's libraries. The durable fix is a bakery contract request to bake `zsh shfmt shellcheck python3 make` into `coder-workspace`, checked against its 570 MB budget. Newer image tags (`0.3.1`, `0.3.2`) exist but weren't examined.
- **`make install` isn't a useful check in a workspace.**
  - Most setup scripts call `confirm_binaries` for tools the image doesn't have (`fdfind`, `starship`, `tmux`, `vim`, `nvim`, `tree-sitter`), so they fail at once.
  - The scripts overwrite the workspace's own `~/.zshrc`, `~/.gitconfig` and so on.
  - They clone oh-my-zsh, fzf, tpm and the vim plugins from GitHub.
  - It's the job `docker/` exists for.

## Smallest meaningful check

- **With the bootstrap:** the full `make lint`. This is the recommended verification for OpenCode.
- **Without it (image as-is):** `lint.sh` can't run at all, because its fail-fast tool check stops it. The only checks the bare image supports are `bash -n` on `scripts/*.sh` and `scripts/cloud/*.sh`, and `git config --file files/git/gitconfig --list`. That covers syntax only, for a fraction of the files, and misses the zsh files, formatting, shellcheck, JSON and TOML. It isn't a meaningful gate.

## macOS-only parts

Lint only syntax-checks these, so it covers them on Linux, but the darwin branches never execute there:

- `scripts/50_setup_vscode.sh`: on darwin it writes to `~/Library/Application Support/Code/User`.
- `scripts/70_setup_k9s.sh`: on darwin it uses `~/Library/Application Support/k9s`.
- `files/zsh/zshenv`: Homebrew `shellenv` from `/opt/homebrew/bin/brew`.
- `files/zsh/zshrc`: nvm from `/opt/homebrew/opt/nvm`, and Homebrew `site-functions` on `fpath`.
- `files/zsh/zprofile`: `PLATFORM=darwin`, and `$PROJECTS_HOME` is `~/Projects` on macOS but `~` on Linux.
- `files/shell/aliases`: a darwin-only branch.
- `scripts/60_setup_ghostty.sh`: skips when `ghostty` is absent, which is the normal case on Linux.
- Linux needs `fdfind` where macOS has `fd` (`10_setup_zsh.sh`).

The lint step itself has nothing macOS-specific. The Makefile's `tput -Txterm` works on the image (`tput` is present).
