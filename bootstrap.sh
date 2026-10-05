#!/usr/bin/env bash
set -euo pipefail

die() {
	printf 'bootstrap: %s\n' "$*" >&2
	exit 1
}

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || die 'cannot resolve repository directory'

[[ ${SHELL-} == */bash ]] || die 'Bash is required; set up PI_CODING_AGENT_DIR manually for another shell.'
command -v bash >/dev/null 2>&1 || die 'Bash is required.'
command -v git >/dev/null 2>&1 || die 'git is required.'
command -v grep >/dev/null 2>&1 || die 'grep is required.'
command -v od >/dev/null 2>&1 || die 'od is required.'
command -v node >/dev/null 2>&1 || die 'Node.js is required to read settings.json safely.'
command -v pi >/dev/null 2>&1 || die 'Pi must already be installed; install it with your package manager first.'

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

home=${HOME:?HOME must be set}
rc=$home/.bashrc
if [[ -L $rc || (-e $rc && ! -f $rc) ]]; then
	die "$rc must be a regular file, not a symlink or special file."
fi

login_profile=
for candidate in "$home/.bash_profile" "$home/.bash_login" "$home/.profile"; do
	if [[ -e $candidate || -L $candidate ]]; then
		[[ ! -L $candidate && -f $candidate ]] || die "$candidate must be a regular file, not a symlink or special file."
		login_profile=$candidate
		break
	fi
done

if [[ -n $login_profile ]]; then
	if ! profile_hex=$(LC_ALL=C od -An -v -tx1 "$login_profile"); then
		die "cannot inspect effective login profile $login_profile"
	fi
	if [[ $profile_hex =~ (^|[[:space:]])00([[:space:]]|$) ]]; then
		die "$login_profile:1 contains a NUL byte; supported login profiles use plain text lines. See README.md for supported forms and manual setup."
	fi
	if LC_ALL=C grep -F $'\r' "$login_profile" >/dev/null; then
		die "$login_profile:1 contains a carriage return; supported login profiles use plain text lines. See README.md for manual setup."
	fi
	source_count=0
	line_number=0
	# Keep expansion literals in the anchored ERE; never evaluate profile text.
	# shellcheck disable=SC2016
	path_export_re='^export[[:blank:]]+PATH="([A-Za-z0-9_./: +,-]|\$HOME|\$PATH|\$\{HOME\}|\$\{PATH\})*"$'
	# shellcheck disable=SC2016
	source_dot_home='. "$HOME/.bashrc"'
	# shellcheck disable=SC2016
	source_keyword_home='source "$HOME/.bashrc"'
	while IFS= read -r line || [[ -n $line ]]; do
		((line_number += 1))
		line=${line#"${line%%[!$' \t']*}"}
		line=${line%"${line##*[!$' \t']}"}
		[[ -z $line || $line == \#* ]] && continue
		case $line in
		"$source_dot_home" | '. ~/.bashrc' | "$source_keyword_home" | 'source ~/.bashrc' | \
			'[[ -f ~/.bashrc ]] && . ~/.bashrc' | 'if [ -f ~/.bashrc ]; then . ~/.bashrc; fi')
			((source_count += 1))
			;;
		*)
			[[ $line =~ $path_export_re ]] && continue
			die "$login_profile:$line_number is not a supported complete startup line. Supported forms are direct . or source of ~/.bashrc, the exact guarded forms, comments, blanks, and safe double-quoted PATH exports. See README.md; adding a source line does not repair other unsupported syntax."
			;;
		esac
	done <"$login_profile"
	if ((source_count != 1)); then
		line_number=$((line_number > 0 ? line_number : 1))
		die "$login_profile:$line_number must contain exactly one supported ~/.bashrc source (found $source_count). See README.md for supported forms and manual PI_CODING_AGENT_DIR setup."
	fi
fi

export_line="export PI_CODING_AGENT_DIR=$(printf '%q' "$repo_dir")"
if [[ ${PI_CODING_AGENT_DIR+x} ]] && [[ $PI_CODING_AGENT_DIR != "$repo_dir" ]]; then
	die 'PI_CODING_AGENT_DIR is already set to a different directory; resolve it before continuing.'
fi

for config_file in "$rc" ${login_profile:+"$login_profile"}; do
	[[ -f $config_file ]] || continue
	while IFS= read -r line || [[ -n $line ]]; do
		[[ $line =~ ^[[:space:]]*# ]] && continue
		if [[ $line == *PI_CODING_AGENT_DIR* ]]; then
			[[ $line == "$export_line" ]] || die "conflicting or ambiguous PI_CODING_AGENT_DIR reference in $config_file; resolve it before continuing."
		fi
	done <"$config_file"
done

# Pi derives project config from cwd. Explicit installs restore declared packages, including pinned npm sources.
if [[ -n $package_sources ]]; then
	while IFS= read -r source; do
		[[ -n $source ]] || continue
		(cd -- "$repo_dir" && PI_CODING_AGENT_DIR="$repo_dir" pi install "$source" --no-approve)
	done <<<"$package_sources"
fi
(cd -- "$repo_dir" && PI_CODING_AGENT_DIR="$repo_dir" pi update --extensions --no-approve)

if [[ ! -e $rc ]]; then
	(umask 077 && : >"$rc") || die "cannot create $rc"
fi
if ! grep -Fqx -- "$export_line" "$rc"; then
	printf '\n# Pi native agent directory\n%s\n' "$export_line" >>"$rc" || die "cannot update $rc"
fi

if [[ -z $login_profile ]]; then
	login_profile=$home/.bash_profile
	(umask 077 && printf "# Load interactive Bash configuration for login shells.\n. \"\$HOME/.bashrc\"\n" >"$login_profile") || die "cannot create $login_profile"
fi

printf 'Pi bootstrap complete.\n'
printf 'Authenticate interactively with: pi\nThen run /login for each provider that needs credentials.\n'
printf 'Shared ~/.agents/skills are not included in this repository; skills that depend on them will be unavailable on a fresh clone. Omarchy system skills are machine-specific too.\n'
printf 'Restart or reload your shell to apply PI_CODING_AGENT_DIR; this script cannot change its parent shell environment.\n'
