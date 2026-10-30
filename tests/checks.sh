#!/bin/sh
# Runs inside a throwaway container of the platform network (read from the standard input by instance.sh) against the
# storage once the setup job has run. It uses the two accounts of the services exactly as the services do, and prints
# the totals on its last line. Use a disposable instance: it leaves objects under tickets/_checks/.
set -u
total=0
failures=0
pass() { total=$((total + 1)); echo "ok   $1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); echo "FAIL $1"; }
# expect <description> <expected text> <actual output>
expect() { case "$3" in *"$2"*) pass "$1" ;; *) fail "$1: expected '$2', got '$3'" ;; esac; }
expect_not() { case "$3" in *"$2"*) fail "$1: found '$2' in '$3'" ;; *) pass "$1" ;; esac; }
# denied <description> <command...>: the command must fail
denied() { desc=$1; shift; if "$@" >/dev/null 2>&1; then fail "$desc: it succeeded"; else pass "$desc"; fi; }
# allowed <description> <command...>
allowed() { desc=$1; shift; if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi; }

bucket=$TICKETS_BUCKET
key="tickets/_checks/$$.pdf"
rc alias set root "$RUSTFS_ENDPOINT" "$RUSTFS_ROOT_USER" "$RUSTFS_ROOT_PASSWORD" >/dev/null
rc alias set writer "$RUSTFS_ENDPOINT" ticketing_pdf_writer "$TICKETING_PDF_WRITER_SECRET" >/dev/null
rc alias set reader "$RUSTFS_ENDPOINT" ticketing_pdf_reader "$TICKETING_PDF_READER_SECRET" >/dev/null
printf '%%PDF-check' > /tmp/check.pdf

expect "versioning is enabled" "Enabled" "$(rc bucket version info root/$bucket 2>&1)"
lifecycle=$(rc bucket lifecycle rule list root/$bucket --json 2>&1 | tr -d ' \n')
expect "one rule expires non-current versions after 30 days" '"noncurrentDays":30' "$lifecycle"
quota=$(rc bucket quota info root/$bucket 2>&1)
expect "the quota is set and hard" "HARD" "$quota"
expect "the quota is the one of the environment" "$(echo "$TICKETS_BUCKET_QUOTA" | sed 's/G$/ GiB/')" "$quota"

# the worker writes and reads, but cannot list, delete or leave tickets/*
allowed "the writer puts a ticket" rc object copy /tmp/check.pdf "writer/$bucket/$key"
allowed "the writer reads a ticket" rc object stat "writer/$bucket/$key"
denied "the writer cannot list the bucket" rc object list "writer/$bucket/tickets/"
denied "the writer cannot delete" rc object remove "writer/$bucket/$key"
denied "the writer cannot write outside tickets/" rc object copy /tmp/check.pdf "writer/$bucket/other/$$.pdf"
denied "the writer cannot call the admin API" rc admin user list writer

# the API only reads
allowed "the reader reads a ticket" rc object stat "reader/$bucket/$key"
denied "the reader cannot write" rc object copy /tmp/check.pdf "reader/$bucket/tickets/_checks/reader-$$.pdf"
denied "the reader cannot delete" rc object remove "reader/$bucket/$key"
missing=$(rc object stat "reader/$bucket/tickets/_checks/none-$$.pdf" 2>&1)
expect "a missing key is reported as not found, not as denied" "ot found" "$missing"
expect_not "a missing key is not an access denial" "ccess" "$missing"

# the bucket is private
code=$(wget -S -qO- "$RUSTFS_ENDPOINT/$bucket/$key" 2>&1 | head -n 1)
expect "an anonymous read is refused" "403" "$code"
denied "a wrong secret is refused" rc alias set bad "$RUSTFS_ENDPOINT" "$RUSTFS_ROOT_USER" wrong-secret-0000

# clean up the check object with the root account
rc object remove "root/$bucket/$key" >/dev/null 2>&1
echo "checks: $total run, $((total - failures)) passed, $failures failed"
[ "$failures" -eq 0 ] && [ "$total" -gt 0 ]
