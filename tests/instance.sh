#!/usr/bin/env sh
# Checks the running instance of the current Compose project (ADR-058). The CI runs it after
# `docker compose up -d --wait rustfs`; it can be run by hand with the env file loaded.
# Usage: sh tests/instance.sh dev|qa
#   dev: the console is published to 127.0.0.1 only (compose.dev.yml).
#   qa:  nothing is published (qa and main compose the same).
# It runs the setup job twice, then tests/checks.sh with the real accounts, then restarts the storage and checks that the
# data survives. Every check is counted: the last line prints the totals and the exit code is non-zero if one failed or
# none ran. Use a disposable instance.
set -u
cd "$(dirname "$0")/.."
mode="${1:?usage: instance.sh dev|qa}"
total=0
failures=0
pass() { total=$((total + 1)); echo "ok   $1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); echo "FAIL $1"; }
expect() { case "$3" in *"$2"*) pass "$1" ;; *) fail "$1: expected '$2', got '$3'" ;; esac; }
expect_not() { case "$3" in *"$2"*) fail "$1: found '$2' in '$3'" ;; *) pass "$1" ;; esac; }
setup() { docker compose run --rm -T setup < rustfs/setup.sh 2>&1; }

# ---- setup: it works from nothing and again ----
first=$(setup); expect "the setup job ends on its last line" "setup done" "$first"
second=$(setup); expect "the setup job can run again" "setup done" "$second"
expect_not "the setup job prints no secret" "$RUSTFS_ROOT_PASSWORD" "$first$second"
rules=$(docker compose run --rm -T --entrypoint sh setup -c 'rc alias set r "$RUSTFS_ENDPOINT" "$RUSTFS_ROOT_USER" "$RUSTFS_ROOT_PASSWORD" >/dev/null; rc bucket lifecycle rule list r/"$TICKETS_BUCKET" --json' 2>&1 | tr -d ' \n')
count=$(echo "$rules" | grep -o '"id"' | wc -l | tr -d ' ')
[ "$count" = 1 ] && pass "a second setup does not duplicate the lifecycle rule" || fail "the lifecycle rule exists $count times"

# ---- accounts and rules, with the accounts the services use ----
checks=$(docker compose run --rm -T --entrypoint sh setup -s < tests/checks.sh 2>&1)
echo "$checks"
line=$(echo "$checks" | grep '^checks:' | tail -n 1)
run=$(echo "$line" | sed -n 's/^checks: \([0-9]*\) run.*/\1/p')
failed=$(echo "$line" | sed -n 's/.* \([0-9]*\) failed$/\1/p')
if [ -n "$run" ] && [ "$run" -gt 0 ]; then total=$((total + run)); failures=$((failures + failed)); else fail "the checks did not report their totals"; fi

# ---- ports ----
s3_port=$(docker compose port rustfs 9000 2>&1)
if echo "$s3_port" | grep -Eq ':[1-9][0-9]*$'; then fail "port 9000 (S3) is published: $s3_port"; else pass "port 9000 (S3) is not published"; fi
console_port=$(docker compose port rustfs 9001 2>&1)
if [ "$mode" = dev ]; then
  expect "the console is published to 127.0.0.1 only" "127.0.0.1:" "$console_port"
  expect_not "the console is not published to every interface" "0.0.0.0" "$console_port"
else
  if echo "$console_port" | grep -Eq ':[1-9][0-9]*$'; then fail "port 9001 (console) is published: $console_port"; else pass "port 9001 (console) is not published"; fi
fi

# ---- restart: the bucket, its rules and the accounts survive ----
docker compose restart rustfs >/dev/null 2>&1
docker compose up -d --wait rustfs >/dev/null 2>&1 && pass "the storage is healthy after a restart" || fail "the storage is not healthy after a restart"
after=$(docker compose run --rm -T --entrypoint sh setup -s < tests/checks.sh 2>&1 | grep '^checks:' | tail -n 1)
expect "every check still passes after a restart" ", 0 failed" "$after"

echo "checks: $total run, $((total - failures)) passed, $failures failed"
[ "$failures" -eq 0 ] && [ "$total" -gt 0 ]
