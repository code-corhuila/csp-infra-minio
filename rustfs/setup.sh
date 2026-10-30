#!/bin/sh
# Brings the storage to the state ADR-058 describes. Idempotent: it can run after every start. Read from the standard
# input by the `setup` service, so it needs no mount.
set -eu
rc alias set root "$RUSTFS_ENDPOINT" "$RUSTFS_ROOT_USER" "$RUSTFS_ROOT_PASSWORD" >/dev/null
bucket="root/$TICKETS_BUCKET"

# private bucket (no anonymous policy is ever set), versioned
rc bucket create --ignore-existing --with-versioning "$bucket"
rc bucket version enable "$bucket"

# non-current versions expire after 30 days (backup-and-recovery.md); the rule is added only when it is missing
if ! rc bucket lifecycle rule list "$bucket" --json | tr -d ' \n' | grep -q '"noncurrentDays":30'; then
  rc bucket lifecycle rule remove "$bucket" --all >/dev/null 2>&1 || true
  rc bucket lifecycle rule add "$bucket" --noncurrent-expiry-days 30
fi

# hard quota (norm 5.3.10): a write over it is refused
rc bucket quota set "$bucket" "$TICKETS_BUCKET_QUOTA"

# least privilege: the worker writes and reads tickets/*, the API only reads it; neither lists nor deletes
policies=/tmp/policies
mkdir -p "$policies"
cat > "$policies/writer.json" <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:PutObject","s3:GetObject"],"Resource":["arn:aws:s3:::$TICKETS_BUCKET/tickets/*"]}]}
EOF
cat > "$policies/reader.json" <<EOF
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject"],"Resource":["arn:aws:s3:::$TICKETS_BUCKET/tickets/*"]}]}
EOF
rc admin policy create root ticketing-pdf-writer "$policies/writer.json"
rc admin policy create root ticketing-pdf-reader "$policies/reader.json"
rc admin user add root ticketing_pdf_writer "$TICKETING_PDF_WRITER_SECRET"
rc admin user add root ticketing_pdf_reader "$TICKETING_PDF_READER_SECRET"
rc admin policy attach root ticketing-pdf-writer --user ticketing_pdf_writer
rc admin policy attach root ticketing-pdf-reader --user ticketing_pdf_reader
rm -rf "$policies"
echo "setup done: bucket $TICKETS_BUCKET, accounts ticketing_pdf_writer and ticketing_pdf_reader"
