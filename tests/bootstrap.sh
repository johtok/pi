#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
bootstrap=$repo/bootstrap.sh
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
passed=0
failed=0

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	failed=$((failed + 1))
}
pass() {
	printf 'PASS: %s\n' "$*"
	passed=$((passed + 1))
}
assert_contains() { grep -Fq -- "$2" "$1" || fail "$1 missing: $2"; }
assert_not_contains() { ! grep -Fq -- "$2" "$1" || fail "$1 unexpectedly contains: $2"; }
assert_native_events() {
	local expected=$1 agent_dir cwd action arg
	while IFS=$'\t' read -r agent_dir cwd action arg; do
		[[ $agent_dir == "$expected" && $cwd == "$expected" ]] || fail "native $action used agent dir/cwd $agent_dir/$cwd, expected $expected"
		[[ $action == install || $action == update ]] || fail "unexpected native package action: $action"
		[[ -n $arg ]] || fail "native $action omitted its first argument"
	done <"$case_dir/events"
}
fixture_bootstrap() {
	mkdir -p "$case_dir/fixture"
	cp "$bootstrap" "$case_dir/fixture/bootstrap.sh"
	cp "$case_dir/settings.json" "$case_dir/fixture/settings.json"
	TEST_BOOTSTRAP=$case_dir/fixture/bootstrap.sh
}
assert_startup_directory() {
	local actual startup=$case_dir/home/.bash_profile
	[[ -f $startup ]] || startup=$case_dir/home/.bash_login
	actual=$(HOME="$case_dir/home" STARTUP_FILE="$startup" bash --noprofile --norc -c 'source "$STARTUP_FILE"; printf %s "$PI_CODING_AGENT_DIR"') || {
		fail 'synthetic startup flow failed'
		return
	}
	[[ $actual == "$repo" ]] || fail "synthetic startup flow exported $actual, expected $repo"
}

setup() {
	case_dir=$tmp/$1
	mkdir -p "$case_dir/home" "$case_dir/bin" "$case_dir/project"
	ln -s "$(command -v bash)" "$case_dir/bin/bash"
	ln -s "$(command -v git)" "$case_dir/bin/git"
	ln -s "$(command -v dirname)" "$case_dir/bin/dirname"
	ln -s "$(command -v grep)" "$case_dir/bin/grep"
	ln -s "$(command -v od)" "$case_dir/bin/od"
	ln -s "$(command -v node)" "$case_dir/bin/node"
	ln -s "$(command -v mkdir)" "$case_dir/bin/mkdir"
	ln -s "$(command -v pwd)" "$case_dir/bin/pwd"
	cp "$repo/settings.json" "$case_dir/settings.json"
	cat >"$case_dir/bin/pi" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\t%s\t%s\t%s\n' "${PI_CODING_AGENT_DIR-}" "$(pwd -P)" "$1" "${2-}" >>"$RECORD_DIR/events"
printf '%s\n' "${PI_CODING_AGENT_DIR-}" >"$RECORD_DIR/agent-dir"
pwd -P >"$RECORD_DIR/cwd"
printf '%s\n' "$@" >"$RECORD_DIR/args"
if [[ $1 == install ]]; then
	[[ ${PI_INSTALL_EXIT:-0} == 0 ]] || exit "$PI_INSTALL_EXIT"
	mkdir -p "$RECORD_DIR/cache"
	printf '%s\n' "$2" >"$RECORD_DIR/cache/${2//[^a-zA-Z0-9]/_}"
	exit 0
fi
[[ $1 == update && ${2-} == --extensions && ${3-} == --no-approve ]] || exit 64
exit "${PI_EXIT:-0}"
FAKE
	chmod +x "$case_dir/bin/pi"
	export RECORD_DIR=$case_dir
}

run_bootstrap() {
	local -a extra_env=()
	local script=${TEST_BOOTSTRAP:-$bootstrap}
	[[ ${BOOTSTRAP_AGENT_DIR+x} ]] && extra_env+=("PI_CODING_AGENT_DIR=$BOOTSTRAP_AGENT_DIR")
	(cd "$case_dir/project" && env -u PI_CODING_AGENT_DIR HOME="$case_dir/home" SHELL="${SHELL_OVERRIDE:-/bin/bash}" \
		PATH="$case_dir/bin" RECORD_DIR="$case_dir" PI_EXIT="${PI_EXIT:-0}" PI_INSTALL_EXIT="${PI_INSTALL_EXIT:-0}" "${extra_env[@]}" \
		bash "$script") >"$case_dir/out" 2>&1
}

setup no_pi
rm "$case_dir/bin/pi"
if run_bootstrap; then fail 'missing Pi must fail'; else pass 'missing Pi fails'; fi
[[ ! -e $case_dir/home/.bashrc ]] || fail 'missing Pi wrote bashrc'

setup no_grep
rm "$case_dir/bin/grep"
if run_bootstrap; then fail 'missing grep must fail'; else pass 'missing grep fails'; fi
[[ ! -e $case_dir/agent-dir ]] || fail 'missing grep ran package reconciliation'
[[ ! -e $case_dir/home/.bashrc && ! -e $case_dir/home/.bash_profile ]] || fail 'missing grep wrote shell startup files'

setup no_od
rm "$case_dir/bin/od"
if run_bootstrap; then fail 'missing od must fail'; else pass 'missing od fails'; fi
[[ ! -e $case_dir/agent-dir ]] || fail 'missing od ran package reconciliation'
[[ ! -e $case_dir/home/.bashrc && ! -e $case_dir/home/.bash_profile ]] || fail 'missing od wrote shell startup files'

setup unsupported_shell
SHELL_OVERRIDE=/bin/zsh
if run_bootstrap; then fail 'unsupported shell must fail'; else pass 'unsupported shell fails'; fi
[[ ! -e $case_dir/home/.bashrc ]] || fail 'unsupported shell wrote bashrc'
unset SHELL_OVERRIDE

setup package_failure
PI_EXIT=31
if run_bootstrap; then fail 'package failure must fail'; else pass 'package failure fails'; fi
[[ ! -e $case_dir/home/.bashrc ]] || fail 'package failure wrote bashrc'
expected_event=$repo$'\t'$repo$'\tinstall\tnpm:pi-btw@0.6.1'
assert_contains "$case_dir/events" "$expected_event"
expected_event=$repo$'\t'$repo$'\tupdate\t--extensions'
assert_contains "$case_dir/events" "$expected_event"
assert_native_events "$repo"
unset PI_EXIT

setup pinned_restore
run_bootstrap || fail 'pinned restore failed'
expected_event=$repo$'\t'$repo$'\tinstall\tnpm:pi-btw@0.6.1'
assert_contains "$case_dir/events" "$expected_event"
assert_contains "$case_dir/cache/npm_pi_btw_0_6_1" 'npm:pi-btw@0.6.1'
[[ $(wc -l <"$case_dir/events") == 2 ]] || fail 'expected explicit install and update events'
assert_native_events "$repo"
pass 'configured pinned package explicitly installed when cache is empty'
cp "$case_dir/events" "$case_dir/events.first"
run_bootstrap || fail 'pinned restore rerun failed'
assert_contains "$case_dir/events" "$expected_event"
[[ $(wc -l <"$case_dir/events") == 4 ]] || fail 'rerun did not repeat declared pin install and update'
assert_contains "$case_dir/cache/npm_pi_btw_0_6_1" 'npm:pi-btw@0.6.1'
assert_native_events "$repo"
pass 'pinned install rerun preserves declared pin'

setup no_node
rm "$case_dir/bin/node"
if run_bootstrap; then fail 'missing Node must fail'; else pass 'missing Node fails'; fi
[[ ! -e $case_dir/events && ! -e $case_dir/home/.bashrc ]] || fail 'missing Node had side effects'

settings_refusal() {
	local name=$1 content=$2
	setup "$name"
	printf '%s' "$content" >"$case_dir/settings.json"
	fixture_bootstrap
	if run_bootstrap; then fail "$name settings must refuse"; else pass "$name settings refused"; fi
	[[ ! -e $case_dir/events && ! -e $case_dir/home/.bashrc && ! -e $case_dir/home/.bash_profile ]] || fail "$name settings had package/shell side effects"
	unset TEST_BOOTSTRAP
}
settings_refusal invalid_json '{"packages": ['
settings_refusal invalid_entry '{"packages":[4]}'
settings_refusal option_source '{"packages":["--help"]}'
settings_refusal cr_source '{"packages":["npm:bad\rname"]}'
settings_refusal newline_source '{"packages":["npm:bad\nname"]}'
settings_refusal missing_packages '{"defaultProvider":"x"}'

setup package_entries
cat >"$case_dir/settings.json" <<'JSON'
{"packages":["npm:first@1.0.0",{"source":"npm:second@2.0.0","extensions":["one"],"skills":["two"]}]}
JSON
fixture_bootstrap
run_bootstrap || fail 'string/object package entries failed'
expected_event=$case_dir/fixture$'\t'$case_dir/fixture$'\tinstall\tnpm:first@1.0.0'
assert_contains "$case_dir/events" "$expected_event"
expected_event=$case_dir/fixture$'\t'$case_dir/fixture$'\tinstall\tnpm:second@2.0.0'
assert_contains "$case_dir/events" "$expected_event"
assert_contains "$case_dir/settings.json" '"extensions":["one"]'
assert_contains "$case_dir/settings.json" '"skills":["two"]'
assert_native_events "$case_dir/fixture"
pass 'string and object.source entries installed unchanged'
unset TEST_BOOTSTRAP

setup empty_packages
printf '{"packages":[]}' >"$case_dir/settings.json"
fixture_bootstrap
run_bootstrap || fail 'empty package list failed'
[[ $(wc -l <"$case_dir/events") == 1 ]] || fail 'empty package list should only update'
assert_native_events "$case_dir/fixture"
unset TEST_BOOTSTRAP

setup install_failure
PI_INSTALL_EXIT=31
if run_bootstrap; then fail 'install failure must fail'; else pass 'install failure fails'; fi
[[ ! -e $case_dir/home/.bashrc && ! -e $case_dir/home/.bash_profile ]] || fail 'install failure wrote shell startup files'
assert_native_events "$repo"
unset PI_INSTALL_EXIT

setup settings_spaced_path
spaced_repo=$case_dir/'repo with spaces'
mkdir -p "$spaced_repo"
cp "$repo/bootstrap.sh" "$spaced_repo/bootstrap.sh"
cp "$repo/settings.json" "$spaced_repo/settings.json"
(cd "$case_dir/project" && env -u PI_CODING_AGENT_DIR HOME="$case_dir/home" SHELL=/bin/bash PATH="$case_dir/bin" RECORD_DIR="$case_dir" PI_EXIT=0 PI_INSTALL_EXIT=0 bash "$spaced_repo/bootstrap.sh") >"$case_dir/out" 2>&1 || fail 'bootstrap/settings spaced path failed'
assert_contains "$case_dir/events" "$spaced_repo"
assert_native_events "$spaced_repo"

setup conflict
printf 'export PI_CODING_AGENT_DIR=/custom/pi\nkeep=yes\n' >"$case_dir/home/.bashrc"
before=$(cat "$case_dir/home/.bashrc")
if run_bootstrap; then fail 'conflicting export must fail'; else pass 'conflicting export fails'; fi
[[ $(cat "$case_dir/home/.bashrc") == "$before" ]] || fail 'conflict changed bashrc'
[[ ! -e $case_dir/agent-dir ]] || fail 'conflict ran package reconciliation'

setup ambiguous_assignment
printf 'true; export PI_CODING_AGENT_DIR=/wrong\n' >"$case_dir/home/.bashrc"
if run_bootstrap; then fail 'ambiguous assignment must fail'; else pass 'ambiguous assignment fails'; fi
[[ ! -e $case_dir/agent-dir ]] || fail 'ambiguous assignment ran package reconciliation'

setup ambiguous_export_list
printf 'export FOO=bar PI_CODING_AGENT_DIR=/wrong\n' >"$case_dir/home/.bashrc"
if run_bootstrap; then fail 'assignment in export list must fail'; else pass 'assignment in export list fails'; fi
[[ ! -e $case_dir/agent-dir ]] || fail 'export list ambiguity ran package reconciliation'

setup ambiguous_readonly
printf 'readonly PI_CODING_AGENT_DIR=/wrong\n' >"$case_dir/home/.bashrc"
if run_bootstrap; then fail 'readonly assignment must fail'; else pass 'readonly assignment fails'; fi
[[ ! -e $case_dir/agent-dir ]] || fail 'readonly ambiguity ran package reconciliation'

setup false_and_profile
printf 'false && . ~/.bashrc\n' >"$case_dir/home/.bash_profile"
if run_bootstrap; then fail 'false && profile must fail'; else pass 'false && profile fails'; fi
[[ ! -e $case_dir/agent-dir ]] || fail 'false && profile ran package reconciliation'
[[ ! -e $case_dir/home/.bashrc ]] || fail 'false && profile wrote bashrc'

setup matching_export
printf '# keep this\nexport PI_CODING_AGENT_DIR=%q\ncustom=true\n' "$repo" >"$case_dir/home/.bashrc"
run_bootstrap || fail 'matching export failed'
run_bootstrap || {
	fail 'second matching export run failed'
	cat "$case_dir/out" >&2
}
[[ $(grep -Fc 'export PI_CODING_AGENT_DIR=' "$case_dir/home/.bashrc") == 1 ]] || fail 'matching export duplicated'
assert_contains "$case_dir/home/.bashrc" 'custom=true'

setup custom_rc
printf 'alias ll="ls -la"\n' >"$case_dir/home/.bashrc"
run_bootstrap || fail 'fresh Bash setup failed'
assert_contains "$case_dir/home/.bashrc" 'alias ll="ls -la"'
assert_contains "$case_dir/home/.bashrc" "export PI_CODING_AGENT_DIR=$(printf '%q' "$repo")"
assert_contains "$case_dir/home/.bash_profile" ". \"\$HOME/.bashrc\""
assert_contains "$case_dir/agent-dir" "$repo"
assert_startup_directory
[[ $(cat "$case_dir/cwd") == "$repo" ]] || fail 'Pi ran from caller project directory'

setup spaced_path
spaced_repo=$case_dir/'repo with spaces'
mkdir -p "$spaced_repo"
cp "$repo/bootstrap.sh" "$spaced_repo/bootstrap.sh"
cp "$repo/settings.json" "$spaced_repo/settings.json"
if [[ -f $spaced_repo/bootstrap.sh ]]; then
	(cd "$case_dir/project" && env -u PI_CODING_AGENT_DIR HOME="$case_dir/home" SHELL=/bin/bash PATH="$case_dir/bin" \
		RECORD_DIR="$case_dir" bash "$spaced_repo/bootstrap.sh") >"$case_dir/out" 2>&1 || fail 'spaced repo failed'
	assert_contains "$case_dir/agent-dir" "$spaced_repo"
	assert_contains "$case_dir/home/.bashrc" "$(printf '%q' "$spaced_repo")"
else
	fail 'bootstrap missing for spaced path case'
fi

setup symlink_rc
printf 'preserve-target\n' >"$case_dir/target-rc"
ln -s "$case_dir/target-rc" "$case_dir/home/.bashrc"
if run_bootstrap; then fail 'symlink rc must be refused'; else pass 'symlink rc refused'; fi
assert_contains "$case_dir/target-rc" preserve-target
[[ ! -e $case_dir/agent-dir ]] || fail 'symlink refusal ran package reconciliation'

setup env_conflict
BOOTSTRAP_AGENT_DIR=/custom/from-env
export BOOTSTRAP_AGENT_DIR
if run_bootstrap; then fail 'conflicting environment export must fail'; else pass 'conflicting environment export fails'; fi
unset BOOTSTRAP_AGENT_DIR
[[ ! -e $case_dir/agent-dir ]] || fail 'environment conflict ran package reconciliation'

setup profile_choice
printf '# source ~/.bashrc\necho profile-kept\n' >"$case_dir/home/.bash_profile"
printf 'echo later-profile\n' >"$case_dir/home/.profile"
if run_bootstrap; then fail 'non-sourcing effective login profile must refuse'; else pass 'effective profile refusal'; fi
[[ ! -e $case_dir/agent-dir ]] || fail 'profile refusal ran package reconciliation'
assert_contains "$case_dir/home/.bash_profile" 'echo profile-kept'
[[ ! -e $case_dir/home/.bashrc ]] || fail 'profile refusal wrote bashrc'

setup login_profile_choice
printf 'if [ -f ~/.bashrc ]; then . ~/.bashrc; fi\n' >"$case_dir/home/.bash_login"
run_bootstrap || fail 'effective .bash_login setup failed'
assert_contains "$case_dir/home/.bashrc" "export PI_CODING_AGENT_DIR=$(printf '%q' "$repo")"
assert_startup_directory
[[ ! -e $case_dir/home/.bash_profile ]] || fail 'created shadow profile ahead of .bash_login'

setup actual_guarded_profile
# shellcheck disable=SC2016
printf '# startup\n\n[[ -f ~/.bashrc ]] && . ~/.bashrc\nexport PATH="$HOME/.elan/bin:$PATH"\nexport PATH="$PATH:/example/.lmstudio/bin"\n' >"$case_dir/home/.bash_profile"
run_bootstrap || fail 'actual guarded profile must pass unchanged'
assert_contains "$case_dir/home/.bash_profile" '[[ -f ~/.bashrc ]] && . ~/.bashrc'
assert_contains "$case_dir/home/.bashrc" "export PI_CODING_AGENT_DIR=$(printf '%q' "$repo")"
assert_startup_directory

refusal_fixture() {
	local name=$1 profile_content=$2 reason=$3
	setup "$name"
	printf '%s' "$profile_content" >"$case_dir/home/.bash_profile"
	printf 'keep-rc\n' >"$case_dir/home/.bashrc"
	cp "$case_dir/home/.bash_profile" "$case_dir/profile.before"
	cp "$case_dir/home/.bashrc" "$case_dir/rc.before"
	if run_bootstrap; then fail "$reason must be refused"; else pass "$reason refused"; fi
	[[ ! -e $case_dir/agent-dir ]] || fail "$reason ran package reconciliation"
	cmp -s "$case_dir/profile.before" "$case_dir/home/.bash_profile" || fail "$reason changed profile"
	cmp -s "$case_dir/rc.before" "$case_dir/home/.bashrc" || fail "$reason changed rc"
	[[ ! -e $case_dir/home/.profile ]] || fail "$reason created shadow profile"
	assert_contains "$case_dir/out" "$case_dir/home/.bash_profile:"
	rm -f "$case_dir/agent-dir" "$case_dir/home/.bashrc"
	if run_bootstrap; then fail "$reason must refuse when rc is absent"; fi
	[[ ! -e $case_dir/agent-dir ]] || fail "$reason with absent rc ran package reconciliation"
	[[ ! -e $case_dir/home/.bashrc ]] || fail "$reason created absent rc"
	cmp -s "$case_dir/profile.before" "$case_dir/home/.bash_profile" || fail "$reason with absent rc changed profile"
	[[ ! -e $case_dir/home/.profile ]] || fail "$reason with absent rc created shadow profile"
}

refusal_fixture inactive_if $'if false; then\n. ~/.bashrc\nfi\n' 'inactive if wrapper'
refusal_fixture function_body $'f() {\n. ~/.bashrc\n}\n' 'function body'
refusal_fixture exit_before $'exit 0\n. ~/.bashrc\n' 'exit before source'
refusal_fixture return_before $'return 0\n. ~/.bashrc\n' 'return before source'
refusal_fixture continuation_wrapper $'false && \\\n. ~/.bashrc\n' 'line continuation wrapper'
refusal_fixture heredoc_wrapper $": <<'EOF'\n. ~/.bashrc\nEOF\n" 'heredoc wrapper'
refusal_fixture exit_after $'. ~/.bashrc\nexit 0\n' 'exit after source'
refusal_fixture command_substitution $'export PATH="$(touch sentinel):$PATH"\n. ~/.bashrc\n' 'PATH command substitution'
[[ ! -e $case_dir/sentinel ]] || fail 'PATH command substitution created sentinel'
refusal_fixture duplicate_source $'. ~/.bashrc\n. ~/.bashrc\n' 'duplicate source'

setup nul_profile
printf '. ~/.bashrc\n\0' >"$case_dir/home/.bash_profile"
printf 'keep-nul-rc\n' >"$case_dir/home/.bashrc"
cp "$case_dir/home/.bash_profile" "$case_dir/profile.before"
cp "$case_dir/home/.bashrc" "$case_dir/rc.before"
if run_bootstrap; then fail 'NUL profile must be refused'; else pass 'NUL profile refused'; fi
[[ ! -e $case_dir/agent-dir ]] || fail 'NUL refusal ran package reconciliation'
[[ ! -e $case_dir/home/.profile ]] || fail 'NUL refusal created shadow profile'
cmp -s "$case_dir/profile.before" "$case_dir/home/.bash_profile" || fail 'NUL refusal changed profile'
cmp -s "$case_dir/rc.before" "$case_dir/home/.bashrc" || fail 'NUL refusal changed rc'
assert_contains "$case_dir/out" "$case_dir/home/.bash_profile"
rm "$case_dir/home/.bashrc"
run_bootstrap && fail 'NUL profile passed with absent rc'
[[ ! -e $case_dir/home/.bashrc && ! -e $case_dir/agent-dir ]] || fail 'NUL refusal with absent rc had side effects'

setup cr_profile
printf '. ~/.bashrc\r\n' >"$case_dir/home/.bash_profile"
printf 'keep-cr-rc\n' >"$case_dir/home/.bashrc"
cp "$case_dir/home/.bash_profile" "$case_dir/profile.before"
cp "$case_dir/home/.bashrc" "$case_dir/rc.before"
if run_bootstrap; then fail 'CR profile must be refused'; else pass 'CR profile refused'; fi
[[ ! -e $case_dir/agent-dir ]] || fail 'CR refusal ran package reconciliation'
[[ ! -e $case_dir/home/.profile ]] || fail 'CR refusal created shadow profile'
cmp -s "$case_dir/profile.before" "$case_dir/home/.bash_profile" || fail 'CR refusal changed profile'
cmp -s "$case_dir/rc.before" "$case_dir/home/.bashrc" || fail 'CR refusal changed rc'
rm "$case_dir/home/.bashrc"
run_bootstrap && fail 'CR profile passed with absent rc'
[[ ! -e $case_dir/home/.bashrc && ! -e $case_dir/agent-dir ]] || fail 'CR refusal with absent rc had side effects'

setup no_final_newline
printf '# comment\n. ~/.bashrc' >"$case_dir/home/.bash_profile"
run_bootstrap || fail 'profile without final newline failed'
assert_contains "$case_dir/agent-dir" "$repo"
assert_startup_directory

setup direct_profile
printf ". \"\$HOME/.bashrc\"\n" >"$case_dir/home/.bash_profile"
run_bootstrap || fail 'direct quoted profile source must pass unchanged'
assert_contains "$case_dir/home/.bash_profile" ". \"\$HOME/.bashrc\""

setup single_quoted_home_profile
printf ". '\$HOME/.bashrc'\n" >"$case_dir/home/.bash_profile"
if run_bootstrap; then fail 'single-quoted HOME source must be refused'; else pass 'single-quoted HOME source refused'; fi
[[ ! -e $case_dir/agent-dir ]] || fail 'single-quoted HOME source ran package reconciliation'
[[ ! -e $case_dir/home/.bashrc ]] || fail 'single-quoted HOME source wrote bashrc'

setup unquoted_home_profile
printf '%s\n' ". \$HOME/.bashrc" >"$case_dir/home/.bash_profile"
if run_bootstrap; then fail 'unquoted HOME source must be refused'; else pass 'unquoted HOME source refused'; fi
[[ ! -e $case_dir/agent-dir ]] || fail 'unquoted HOME source ran package reconciliation'
[[ ! -e $case_dir/home/.bashrc ]] || fail 'unquoted HOME source wrote bashrc'

setup no_auth_copy
mkdir -p "$case_dir/home/.pi/agent"
printf 'do-not-copy' >"$case_dir/home/.pi/agent/auth.json"
run_bootstrap || fail 'auth non-copy case failed'
[[ ! -e $case_dir/home/auth.json ]] || fail 'auth copied to home root'
[[ $(cat "$case_dir/home/.pi/agent/auth.json") == do-not-copy ]] || fail 'source auth changed'

for ignored in auth.json mcp-auth.json trust.json models-store.json crashes.json sessions/run npm/pkg git/pkg bin/fd bin/rg app.log app.log.1 .env .env.example .env.local node_modules/pkg cache.tmp cache/state.bin tmp/generated.bin private.pem settings.json.bak settings.json.lock; do
	git -C "$repo" check-ignore -q -- "$ignored" || fail ".gitignore does not ignore $ignored"
done
for tracked in AGENTS.md models.json settings.json mcp.json keybindings.json resources/skill/SKILL.md scripts/tool.sh assets/data.bin assets/cache/skill.png assets/tmp/reference.txt extensions/bin/helper.ts; do
	git -C "$repo" check-ignore -q -- "$tracked" && fail ".gitignore hides $tracked"
done

printf '\n%d passed; %d failed\n' "$passed" "$failed"
((failed == 0))
