# Changelog

All notable changes of `csp-infra-rustfs` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Each change is recorded in the pull request that introduces it.

## [Unreleased]

### Added

- The single RustFS storage of the platform for the ticket PDF (ADR-058): `compose.yml` with the pinned image
  `rustfs/rustfs:1.0.4`, a named volume, no published S3 port and the `platform` network; `compose.dev.yml`, which
  publishes the console to `127.0.0.1` only in dev.
- `rustfs/setup.sh` and the one-shot `setup` service (`rustfs/rc:v0.1.36`): the private bucket `tickets` with versioning,
  a 30-day expiry of non-current versions and a hard quota, the policies `ticketing-pdf-writer` and `ticketing-pdf-reader`
  and the accounts `ticketing_pdf_writer` and `ticketing_pdf_reader`. It is idempotent.
- The env examples of `dev`, `qa` and `main`; `scripts/up.sh` and `scripts/down.sh`.
- `.github/workflows/ci.yml`, `tests/instance.sh` and `tests/checks.sh`: they start the storage, run the setup twice and
  check the bucket, the rules, what each account can and cannot do, the ports and the restart.
- The pull request template of the annex, `.gitignore` and `.gitattributes`.
- This changelog.

### Changed

- `README.md` describes the storage, its variables, the bucket and the accounts, and cites ADR-058 (the repository was
  created as `csp-infra-minio` and renamed once ADR-058 chose RustFS).
