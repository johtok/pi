# Pi agent directory

This repository is the Pi runtime directory itself: `PI_CODING_AGENT_DIR` points here, and Pi reads `settings.json`, `models.json`, instructions, and custom resources directly from this repo. Pi must already be installed (tested with Pi 1.0.2); Node.js 22.19 or newer is required.

## Fresh machine

Clone to the expected path and bootstrap from Bash:

```bash
git clone <repo-url> "$HOME/git/pi"
"$HOME/git/pi/bootstrap.sh"
```

Open a new Bash shell, or set it in the current one with `export PI_CODING_AGENT_DIR="$HOME/git/pi"`. Start `pi`, then run `/login` to authenticate the OpenAI provider and any others you use. OpenAI OAuth needs interactive authentication on each new machine.

Bootstrap reads plain JSON from `settings.json`, explicitly installs every declared package (including pinned npm packages), then reconciles floating package updates. It checks the effective login profile and `.bashrc` without executing either file, and adds the exact `PI_CODING_AGENT_DIR` export to `.bashrc`. The effective login profile must contain exactly one supported complete source statement: `. "$HOME/.bashrc"`, `. ~/.bashrc`, `source` equivalents, `[[ -f ~/.bashrc ]] && . ~/.bashrc`, or `if [ -f ~/.bashrc ]; then . ~/.bashrc; fi`. Blank lines, full-line comments, and safe double-quoted `PATH` exports are also accepted. The PATH form permits literal path characters and `$HOME`, `$PATH`, `${HOME}`, or `${PATH}` references; it rejects substitutions, escapes, operators, extra assignments, and inline comments.

This is a deliberately conservative line grammar, not a Bash parser. Other valid profiles, including profiles with functions, commands, multiline syntax, or additional assignments, are refused with a filename and line number before package updates or writes. Adding a `.bashrc` source line does not make otherwise unsupported syntax safe. To proceed, manually arrange for the existing login startup flow to load `.bashrc` and set `PI_CODING_AGENT_DIR` to this repository path (for example, `export PI_CODING_AGENT_DIR="$HOME/git/pi"` in `.bashrc`), then omit bootstrap or simplify the profile to the supported forms. The validator checks profile structure only; it cannot prove that arbitrary commands inside `.bashrc` will reach the appended export. Bootstrap never executes either profile. It never installs Pi or copies credentials.

## Configuration and runtime state

Configuration lives directly in this directory. Review Git state before adding files:

- Tracked candidates: `AGENTS.md`, `settings.json`, `models.json`, global instructions, and custom `extensions/`, `skills/`, `prompts/`, and `themes/` resources.
- Locally ignored runtime/private state: `auth.json`, `mcp-auth.json`, trust data, model store, crash reports, sessions, package installs, Git package clones, managed tool binaries, logs, scratch files, dependencies, and `.env` / `.env.*` files. There is no `.env.example` exemption.

Never copy `auth.json` or `mcp-auth.json` from Git or another machine. They belong in this runtime directory and remain locally ignored.

`settings.json` must be plain JSON (no comments) and its `packages` value must be an array of source strings or objects with a `source` string. Object resource filters remain in effect through Pi's native install matching. Bootstrap explicitly installs each listed source; `pi update --extensions` updates floating npm packages and reconciles Git packages, but skips pinned npm packages, including missing pinned installs. To restore packages after changing a pin, rerun bootstrap or install the selected source directly with `pi install`.

To update floating packages and reconcile Git packages manually, run from a neutral directory or this repository:

```bash
PI_CODING_AGENT_DIR="$HOME/git/pi" pi update --extensions --no-approve
```

The configured `pi-btw` version is pinned to `0.6.1`. `pi update` without these package flags updates Pi itself and is a separate operation.

Custom resources belong directly in this repository's `extensions/`, `skills/`, `prompts/`, and `themes/` directories. Track your own resources here; reload or restart Pi after changes. Project-local `AGENTS.md` and `.pi/` configuration remain in each project and are not replaced by this user-level directory.

## Machine-specific dependencies and rollback

Shared `~/.agents/skills` and Omarchy skills are absent by design; their provenance is not established here, so this repository makes no upstream pin claim. The configured `local-qwopus` model requires a separately installed local service at `127.0.0.1:8001`. It is unavailable on a fresh machine unless you install and run that service.

To roll back shell wiring, remove only the Pi export line from `.bashrc` and unset `PI_CODING_AGENT_DIR` in any current shell. The old `~/.pi/agent` directory remains untouched. Bootstrap may create `.bash_profile` to source `.bashrc` when no effective login profile exists; it does not overwrite an existing profile.
