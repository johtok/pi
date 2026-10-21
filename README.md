# Pi harness

My configuration for [Pi](https://pi.dev): engineering instructions, model settings, and extensions for delegated work, web research, and usage tracking.

The harness installs into Pi's standard `~/.pi/agent` directory. Start `pi` from any project to use it.

## Install

On macOS or Linux, install Pi with its [official installer](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/README.md#getting-started):

```bash
curl -fsSL https://pi.dev/install.sh | sh
```

Open a new terminal and check that `pi` is on your `PATH`. Pi needs Node.js 22.19 or newer; its installer can install Node.js if needed. Applying this harness also requires Git and Bash.

Clone the harness into a temporary directory and apply it:

```bash
harness_checkout=$(mktemp -d)
git clone https://github.com/johtok/pi.git "$harness_checkout"
bash "$harness_checkout/bootstrap.sh"
```

Bootstrap copies `AGENTS.md`, `settings.json`, and `models.json` into `~/.pi/agent`, then installs every extension declared in `settings.json`. Existing files that differ are backed up under `~/.pi/agent/backups/harness.*`; the script prints the backup location. Applying the harness replaces these three files, including your current settings and custom model definitions.

The temporary checkout is only needed while applying the harness. Credentials, sessions, and other existing Pi resources stay in their usual directory. Bootstrap does not edit shell startup files.

If you already have a checkout, run `bash /path/to/checkout/bootstrap.sh` instead. Its location does not affect where the harness is installed.

## First run

```bash
cd /path/to/your/project
pi
```

Inside Pi:

1. Run `/login` to connect your provider.
2. Run `/model` to select a model available to your account.
3. Give Pi a task.

The supplied settings use OpenAI Codex models with medium thinking and a dark theme. Model access depends on your account; choose your own defaults in `~/.pi/agent/settings.json`.

## Direct implementation

You control the workflow. To have Pi proceed straight to implementation, say:

> Implement directly. Skip planning, specs, tickets, and approval checkpoints. Make reasonable assumptions and finish the change.

"Just build it" or "force implementation" also works. This overrides the harness's default planning and skill workflows for the current task. Pi inspects the relevant code, implements the change, performs necessary checks, and reports the result. It asks only when essential information cannot be inferred or discovered. Tool permissions and authorization for destructive or external actions still apply.

## What's included

| File | Purpose |
| --- | --- |
| [`AGENTS.md`](AGENTS.md) | Engineering workflow: practical prototypes, deliberate checks, tmux visibility, and delegation when useful. |
| [`settings.json`](settings.json) | Provider and model preferences, appearance, and extension sources. |
| [`models.json`](models.json) | An optional local model provider at `http://127.0.0.1:8001/v1`. It needs a separately configured model server. |
| [`bootstrap.sh`](bootstrap.sh) | Applies the configuration to Pi's default directory and restores the declared extensions. |

### Extensions

| Package | Purpose |
| --- | --- |
| `pi-btw` | Side conversations. |
| `pi-subagents` | Delegated and parallel agent workflows. |
| `pi-web-extension` | Web search and page retrieval. |
| `pi-tokenburn` | Token and cost tracking. |
| `pi-context-cap` | Context limit controls. |

The engineering instructions reflect my own workflow. Some refer to tools such as `tmux`, `tk`, and `codex`; install those separately if you want to follow that workflow, or adapt `AGENTS.md`. Shared `~/.agents/skills` and Omarchy resources are machine specific and are not bundled here.

## Update and customize

Update Pi itself:

```bash
pi update
```

Update floating extensions:

```bash
pi update --extensions
```

Bootstrap explicitly installs each configured package before updating extensions, restoring missing packages. All bundled extensions follow their latest versions. To reinstall the side-conversation extension manually:

```bash
pi install npm:pi-btw
```

Edit your installed settings in `~/.pi/agent`. Add your own resources under `extensions/`, `skills/`, `prompts/`, or `themes/`, and run `/reload` or restart Pi after changing resources. Project instructions belong in that project's `AGENTS.md` and `.pi/` directory.

To apply a newer version of this harness, repeat the temporary checkout and bootstrap commands above. This replaces the three managed config files again, with backups; keep any customizations you want to reapply.

## Moving from the old custom directory

Earlier versions pointed `PI_CODING_AGENT_DIR` at a Git checkout. To return to Pi's normal directory:

1. Remove the old `export PI_CODING_AGENT_DIR=...` line from your shell startup configuration.
2. Run `unset PI_CODING_AGENT_DIR` in your current Bash or Zsh shell, or open a new terminal.
3. Run the install steps above.

Bootstrap refuses to run while that variable points elsewhere. Sessions and credentials in the old directory are not migrated; they remain there, and you can authenticate again with `/login` in the default installation.

## Privacy and backups

Authentication files, sessions, installed packages, and generated runtime state belong to your local Pi installation. Never commit `auth.json` or `mcp-auth.json`. The repository's `.gitignore` excludes credentials and runtime files.

To undo the configuration change, copy the backed up files from the printed backup directory into `~/.pi/agent`, then restart Pi. Files that did not exist before installation have no backup; remove those individually if needed. Extension installations and updates are separate from configuration backups.

## License

[MIT](LICENSE).
