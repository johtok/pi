#!/usr/bin/env bash
set -euo pipefail
umask 077

die() {
	printf 'bootstrap: %s\n' "$*" >&2
	exit 1
}

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || die 'cannot resolve repository directory'
agent_dir=${HOME:?HOME must be set}/.pi/agent

command -v node >/dev/null 2>&1 || die 'Node.js is required to read settings.json safely.'
command -v pi >/dev/null 2>&1 || die 'Pi must already be installed; see https://pi.dev for installation.'

if [[ -n ${PI_CODING_AGENT_DIR-} && $PI_CODING_AGENT_DIR != "$agent_dir" ]]; then
	die 'PI_CODING_AGENT_DIR points elsewhere. Remove the old export from your shell configuration and run unset PI_CODING_AGENT_DIR before installing into ~/.pi/agent.'
fi

for file in AGENTS.md settings.json models.json; do
	[[ -f $repo_dir/$file ]] || die "missing harness file: $file"
	[[ ! -L $agent_dir/$file && (! -e $agent_dir/$file || -f $agent_dir/$file) ]] || die "$agent_dir/$file must be a regular file, not a symlink or special file."
done

if ! package_sources=$(
	node - "$repo_dir/settings.json" <<'NODE'
const fs = require("node:fs");

try {
  const settings = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
  if (!settings || typeof settings !== "object" || Array.isArray(settings) || !Array.isArray(settings.packages)) {
    throw new Error();
  }
  const sources = settings.packages.map((entry) => {
    const source = typeof entry === "string" ? entry : entry && typeof entry === "object" && !Array.isArray(entry) ? entry.source : null;
    if (typeof source !== "string" || source.length === 0 || /[\0\r\n]/u.test(source) || source.startsWith("-")) {
      throw new Error();
    }
    return source;
  });
  process.stdout.write(sources.length ? `${sources.join("\n")}\n` : "");
} catch {
  process.stderr.write("bootstrap: settings.json must contain valid package entries.\n");
  process.exitCode = 1;
}
NODE
); then
	die 'cannot read valid package entries from settings.json.'
fi

mkdir -p -- "$agent_dir"
agent_dir=$(cd -- "$agent_dir" && pwd -P)
backup_dir=
for file in AGENTS.md settings.json models.json; do
	cmp -s -- "$repo_dir/$file" "$agent_dir/$file" && continue
	if [[ -e $agent_dir/$file ]]; then
		if [[ -z $backup_dir ]]; then
			mkdir -p -- "$agent_dir/backups"
			backup_dir=$(mktemp -d "$agent_dir/backups/harness.XXXXXXXX")
			printf 'Existing configuration backed up to %s\n' "$backup_dir"
		fi
		cp -p -- "$agent_dir/$file" "$backup_dir/$file"
	fi
done

for file in AGENTS.md settings.json models.json; do
	cmp -s -- "$repo_dir/$file" "$agent_dir/$file" && continue
	cp -- "$repo_dir/$file" "$agent_dir/$file"
done

# Use the global agent directory as cwd so a caller's project config is not changed.
# Explicit installs restore pinned npm sources that extension updates skip.
if [[ -n $package_sources ]]; then
	while IFS= read -r source; do
		[[ -n $source ]] || continue
		(cd -- "$agent_dir" && PI_CODING_AGENT_DIR="$agent_dir" pi install "$source" --no-approve)
	done <<<"$package_sources"
fi
(cd -- "$agent_dir" && PI_CODING_AGENT_DIR="$agent_dir" pi update --extensions --no-approve)

printf 'Pi harness installed in %s\n' "$agent_dir"
printf 'Start pi from your project and run /login to authenticate, then /model to choose a model.\n'
