# Pi harness

Personal [Pi](https://pi.dev) configuration: **working baseline first, improve from evidence, communicate tersely**. Installs into `~/.pi/agent`; use it from any project.

## Install

Requires macOS/Linux, Git, Bash and Pi with Node.js 22.19+. Install Pi using its [official installer](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/README.md#getting-started), which can supply Node.js:

```bash
curl -fsSL https://pi.dev/install.sh | sh
```

Open a new terminal, then apply this harness from a temporary checkout:

```bash
harness_checkout=$(mktemp -d)
git clone https://github.com/johtok/pi.git "$harness_checkout"
bash "$harness_checkout/bootstrap.sh"
```

Bootstrap replaces `AGENTS.md`, `settings.json` and `models.json` in `~/.pi/agent`, backs up differing originals under `backups/harness.*`, and installs/updates the configured extensions. It prints the backup path. Credentials, sessions and shell startup files are untouched. The checkout is disposable afterward; an existing checkout works too.

**Old custom directory:** remove the `PI_CODING_AGENT_DIR` export from your shell configuration and run `unset PI_CODING_AGENT_DIR` in Bash/Zsh before installing. Bootstrap refuses conflicting overrides. Old credentials/sessions stay in the old directory; authenticate again with `/login`.

## Use

```bash
cd /path/to/project
pi
```

Run `/login`, choose an available model with `/model`, then give Pi a task. Defaults: OpenAI Codex, medium thinking, dark theme.

To bypass workflow ceremony:

> Implement directly. Skip planning, specs, tickets and approval checkpoints. Make reasonable assumptions and finish the change.

“Just build it” and “force implementation” also activate direct mode for the current task. Necessary checks and tool/action permissions still apply.

## Included

| File | Purpose |
| --- | --- |
| [AGENTS.md](AGENTS.md) | Rapid prototypes, terse output, deliberate tool use and verification. |
| [settings.json](settings.json) | Models, appearance and extension sources. |
| [models.json](models.json) | Optional local provider at `http://127.0.0.1:8001/v1`; requires a separate server. |
| [bootstrap.sh](bootstrap.sh) | Configuration installation, backups and extension restoration. |

All extensions are unpinned: `pi-btw` (side conversations), `pi-subagents` (delegation), `pi-web-extension` (web research), `pi-tokenburn` (usage/cost), `pi-context-cap` (context limits).

Workflow helpers such as `tmux`, `tk` and `codex` are installed separately. Shared `~/.agents/skills` and Omarchy resources are not bundled; adapt the instructions to your tools.

## Maintain

```bash
pi update                    # Pi itself
pi update --extensions       # Extensions
pi install npm:pi-btw        # Example: restore a missing extension
```

Customize files in `~/.pi/agent`; resources go in `extensions/`, `skills/`, `prompts/` or `themes/`. Run `/reload` or restart Pi after resource changes. Project configuration belongs in the project's `AGENTS.md` and `.pi/`.

To update this harness, repeat the checkout/bootstrap steps. The three config files are replaced again with backups; reapply local customizations as needed.

To roll back, restore files from the printed backup directory into `~/.pi/agent` and restart Pi. Newly created files have no backup; remove those individually if needed. Config backups do not undo extension installs/updates.

Keep credentials and runtime data local; never commit `auth.json` or `mcp-auth.json`.

[MIT license](LICENSE).
