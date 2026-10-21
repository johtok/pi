#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
passed=0
failed=0

check() {
	local description=$1
	shift
	if "$@"; then
		printf 'PASS: %s\n' "$description"
		passed=$((passed + 1))
	else
		printf 'FAIL: %s\n' "$description" >&2
		failed=$((failed + 1))
	fi
}
equal() { [[ $1 == "$2" ]]; }
absent() { [[ ! -e $1 ]]; }
contains() { grep -Fq -- "$2" "$1"; }

setup() {
	case_dir=$tmp/$1
	agent_dir=$case_dir/home/.pi/agent
	checkout=$case_dir/'temporary checkout'
	mkdir -p "$case_dir/home" "$case_dir/bin" "$case_dir/project/.pi" "$checkout"
	cp "$repo/bootstrap.sh" "$checkout/bootstrap.sh"
	printf 'harness instructions\n' >"$checkout/AGENTS.md"
	printf '{"providers":{}}\n' >"$checkout/models.json"
	printf '{"packages":["npm:first@1.0.0",{"source":"npm:second","extensions":["one"],"skills":["two"]}]}\n' >"$checkout/settings.json"
	printf 'project settings\n' >"$case_dir/project/.pi/settings.json"
	printf 'keep bashrc\n' >"$case_dir/home/.bashrc"
	printf 'keep profile\n' >"$case_dir/home/.bash_profile"
	for executable in bash node dirname mkdir cmp mktemp cp; do
		ln -s "$(command -v "$executable")" "$case_dir/bin/$executable"
	done
	cat >"$case_dir/bin/pi" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\t%s\t%s\t%s\t%s\n' "${PI_CODING_AGENT_DIR-}" "$(pwd -P)" "$1" "${2-}" "${3-}" >>"$RECORD_DIR/events"
if [[ $1 == install ]]; then
	exit "${PI_INSTALL_EXIT:-0}"
fi
[[ $1 == update && ${2-} == --extensions && ${3-} == --no-approve ]] || exit 64
exit "${PI_UPDATE_EXIT:-0}"
FAKE
	chmod +x "$case_dir/bin/pi"
}

run_bootstrap() {
	(cd "$case_dir/project" && env -u PI_CODING_AGENT_DIR \
		HOME="$case_dir/home" SHELL=/bin/fish PATH="$case_dir/bin" RECORD_DIR="$case_dir" \
		PI_INSTALL_EXIT="${PI_INSTALL_EXIT:-0}" PI_UPDATE_EXIT="${PI_UPDATE_EXIT:-0}" \
		"${@}" bash "$checkout/bootstrap.sh") >"$case_dir/out" 2>&1
}

native_events() {
	local directory cwd action arg approval
	while IFS=$'\t' read -r directory cwd action arg approval; do
		[[ $directory == "$agent_dir" && $cwd == "$agent_dir" && $approval == --no-approve ]] || return 1
		[[ $action == install || $action == update ]] || return 1
		[[ -n $arg ]] || return 1
	done <"$case_dir/events"
}

setup fresh
check 'install from a temporary checkout succeeds with a non-Bash login shell' run_bootstrap
for file in AGENTS.md settings.json models.json; do
	check "$file copied into ~/.pi/agent" cmp -s "$checkout/$file" "$agent_dir/$file"
done
check 'all package actions use the default directory and run outside the caller project' native_events
check 'pinned source is explicitly installed' contains "$case_dir/events" $'install\tnpm:first@1.0.0\t--no-approve'
check 'object source is explicitly installed' contains "$case_dir/events" $'install\tnpm:second\t--no-approve'
check 'two installs and one extension update' equal "$(wc -l <"$case_dir/events")" 3
check 'object resource filters survive installation' contains "$agent_dir/settings.json" '"extensions":["one"],"skills":["two"]'
check 'bashrc is unchanged' equal "$(cat "$case_dir/home/.bashrc")" 'keep bashrc'
check 'login profile is unchanged' equal "$(cat "$case_dir/home/.bash_profile")" 'keep profile'
check 'caller project settings are unchanged' equal "$(cat "$case_dir/project/.pi/settings.json")" 'project settings'
check 'fresh installation creates no backups' absent "$agent_dir/backups"
check 'rerunning bootstrap succeeds' run_bootstrap
check 'identical files create no backup on rerun' absent "$agent_dir/backups"
check 'rerun repeats package restoration' equal "$(wc -l <"$case_dir/events")" 6

setup existing
mkdir -p "$agent_dir/sessions" "$agent_dir/themes"
for file in AGENTS.md settings.json models.json auth.json; do
	printf 'original %s\n' "$file" >"$agent_dir/$file"
done
printf 'private session\n' >"$agent_dir/sessions/existing"
printf 'custom theme\n' >"$agent_dir/themes/custom.json"
check 'existing installation can apply harness' run_bootstrap
backups=("$agent_dir"/backups/harness.*)
check 'one backup directory is created' equal "${#backups[@]}" 1
for file in AGENTS.md settings.json models.json; do
	check "$file original is backed up" equal "$(cat "${backups[0]}/$file")" "original $file"
done
check 'credentials stay untouched' equal "$(cat "$agent_dir/auth.json")" 'original auth.json'
check 'sessions stay untouched' equal "$(cat "$agent_dir/sessions/existing")" 'private session'
check 'custom themes stay untouched' equal "$(cat "$agent_dir/themes/custom.json")" 'custom theme'
check 'backups contain only replaced config files' equal "$(find "${backups[0]}" -type f | wc -l)" 3
check 'backup location is reported' contains "$case_dir/out" "${backups[0]}"

setup custom_directory
if run_bootstrap PI_CODING_AGENT_DIR=/old/checkout; then
	check 'custom directory override is refused' false
else
	check 'custom directory override is refused' contains "$case_dir/out" 'unset PI_CODING_AGENT_DIR'
fi
check 'conflicting override causes no package operations' absent "$case_dir/events"
check 'conflicting override creates no agent directory' absent "$agent_dir"

setup matching_directory
check 'an override matching the default directory is accepted' run_bootstrap "PI_CODING_AGENT_DIR=$agent_dir"
check 'matching override still uses default directory' native_events

setup in_place
mkdir -p "$agent_dir"
cp "$checkout/"{bootstrap.sh,AGENTS.md,settings.json,models.json} "$agent_dir/"
checkout=$agent_dir
check 'running a checkout already in the default directory succeeds' run_bootstrap
check 'in-place installation does not back up files onto themselves' absent "$agent_dir/backups"

for missing in pi node; do
	setup "missing_$missing"
	rm "$case_dir/bin/$missing"
	if run_bootstrap; then
		check "missing $missing is refused" false
	else
		check "missing $missing is refused" absent "$agent_dir"
	fi
done

for invalid in '{"packages":[' '{"packages":[4]}' '{"packages":["--help"]}' '{"packages":["npm:bad\nname"]}' '{"packages":["npm:bad\rname"]}' '{"other":[]}'; do
	setup "invalid_$passed"
	printf '%s' "$invalid" >"$checkout/settings.json"
	if run_bootstrap; then
		check 'invalid package configuration is refused' false
	else
		check 'invalid package configuration creates no agent directory' absent "$agent_dir"
	fi
	check 'invalid package configuration runs no package commands' absent "$case_dir/events"
done

setup empty_packages
printf '{"packages":[]}' >"$checkout/settings.json"
check 'empty package list is accepted' run_bootstrap
check 'empty package list only updates extensions' equal "$(wc -l <"$case_dir/events")" 1

setup missing_config
rm "$checkout/models.json"
if run_bootstrap; then
	check 'missing config is refused' false
else
	check 'missing config refuses before copying anything' absent "$agent_dir"
fi

setup symlink_config
mkdir -p "$agent_dir"
printf 'keep target\n' >"$case_dir/target"
ln -s "$case_dir/target" "$agent_dir/settings.json"
if run_bootstrap; then
	check 'symlink config is refused' false
else
	check 'symlink config refuses before package operations' absent "$case_dir/events"
fi
check 'symlink target stays untouched' equal "$(cat "$case_dir/target")" 'keep target'

setup install_failure
PI_INSTALL_EXIT=31
if run_bootstrap; then
	check 'package installation failure propagates' false
else
	check 'package installation failure propagates' equal "$?" 31
fi
unset PI_INSTALL_EXIT
check 'installation failure stops before update' equal "$(wc -l <"$case_dir/events")" 1

setup update_failure
PI_UPDATE_EXIT=32
if run_bootstrap; then
	check 'extension update failure propagates' false
else
	check 'extension update failure propagates' equal "$?" 32
fi
unset PI_UPDATE_EXIT

printf '\n%d passed; %d failed\n' "$passed" "$failed"
((failed == 0))
