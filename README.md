# csp-infra-rustfs

> The single object storage of the platform: the private bucket with the ticket PDFs and one account per service (ADR-058)

Part of the **Cinesync Platform** distributed system — team `cinesync-platform`, Group 1.
Governance and documentation live in [`csp-docs`](https://github.com/code-corhuila/csp-docs.git).
The decision is recorded in ADR-058 (`ADR-058-object-storage-for-the-ticket-pdf-rustfs`, in `05-architecture/decisions/` of `csp-docs`).

## Purpose

`csp-worker` renders the PDF of a ticket and writes it here; `csp-ticketing-api` reads it and streams it to the owner of
the ticket. Nobody else touches the storage, and the clients never reach it. This repository **defines the only RustFS
storage** of each environment: the bucket `tickets`, its rules and the two accounts.

```
compose.yml                 the rustfs service (pinned image, volume, health check) and the one-shot setup job
compose.dev.yml             dev only: the console published to 127.0.0.1
rustfs/setup.sh             idempotent: bucket, versioning, lifecycle, quota, policies and accounts
env/<env>.env.example       one file per environment: dev, qa, main (git-ignored without .example)
scripts/up.sh, down.sh      bring an environment up (waits until healthy, runs the setup) and stop it
tests/instance.sh, checks.sh   the checks of the CI, also runnable by hand
.github/workflows/ci.yml    starts the storage as dev and as qa/main and runs the checks
```

## Environments and variables

Each environment has its own env file, its own `COMPOSE_PROJECT_NAME` (`csp-dev`, `csp-qa`, `csp-main`) and therefore its
own container and volume (J.5.1). Only the `.example` file is versioned. In `qa` and `main` the real values come from the
secret of the environment, never from the repository.

| Variable | Meaning |
|---|---|
| `COMPOSE_PROJECT_NAME` | Compose project of the environment |
| `RUSTFS_CONSOLE_PORT` | dev only: host port of the console (default `9001`, bound to `127.0.0.1`) |
| `RUSTFS_ROOT_USER`, `RUSTFS_ROOT_PASSWORD` | root account: operation and the setup job; no service uses it |
| `TICKETS_BUCKET`, `TICKETS_BUCKET_QUOTA` | name of the bucket (`tickets`) and its hard quota; the `qa` and `main` value (`5G`) is a starting point to be agreed |
| `TICKETING_PDF_WRITER_SECRET`, `TICKETING_PDF_READER_SECRET` | secrets of the two service accounts |
| `OBJECT_STORAGE_URL`, `OBJECT_STORAGE_BUCKET`, `OBJECT_STORAGE_ACCESS_KEY`, `OBJECT_STORAGE_SECRET_KEY` | what `csp-ticketing-api` reads: `http://rustfs:9000`, the bucket and the reader account |

Generate the secrets with `openssl rand -hex 24`.

## How to run

```bash
cp env/dev.env.example env/dev.env      # then set the root account and the two secrets
./scripts/up.sh dev                     # creates the platform network, starts RustFS, waits until it is healthy, runs the setup
./scripts/down.sh dev                   # stops it; the volume and the tickets in it are kept
./scripts/up.sh qa                      # the environment argument is mandatory
```

The image is `rustfs/rustfs:1.0.4`, pinned by tag, and the setup job uses `rustfs/rc:v0.1.36`. Services reach the storage by
the name `rustfs` on the `platform` network, never by `localhost`. The S3 port (9000) is never published to the host.
The console (9001) is published to `127.0.0.1` only in `dev`. By hand, `dev` needs both files:
`COMPOSE_FILE=compose.yml:compose.dev.yml COMPOSE_PATH_SEPARATOR=:`, and the setup job reads its script from the standard input:
`docker compose --env-file env/dev.env run --rm -T setup < rustfs/setup.sh`.

## Bucket and accounts

| Object | Value |
|---|---|
| Bucket `tickets` | private (no anonymous policy), versioning on, hard quota from `TICKETS_BUCKET_QUOTA` |
| Lifecycle | non-current versions expire after 30 days |
| Key | `tickets/{reservationId}/{ticketId}.pdf`, immutable; the worker checks it before writing |

| Account | Allowed | Used by |
|---|---|---|
| root | everything | operation and the setup job; no service |
| `ticketing_pdf_writer` | `s3:PutObject`, `s3:GetObject` on `tickets/*` | `csp-worker` |
| `ticketing_pdf_reader` | `s3:GetObject` on `tickets/*` | `csp-ticketing-api` |

Neither service account can list, delete, write outside `tickets/*` or call the admin API. A missing key answers
`404 NoSuchKey` to both, not `403`, so the API can tell "no such PDF" from "not allowed". The worker also refuses a PDF
over 1 MiB (norm 5.3.10) before writing it.

## Rules

- **No secret is versioned.** `env/*.env.example` carries names and placeholders only.
- **Single node, named volume.** A lost volume loses the PDFs and their versions. The setup recreates the bucket, its rules and the accounts, but nothing renders a ticket again once its reference is recorded (TD-051 in `csp-docs`), so back up the volume if the PDFs matter.
- **The setup is idempotent** and re-applies the bucket, the rule, the quota, the policies and the accounts at every `up`.
  It does not remove what the script no longer lists (use `rc` from a container, or drop the volume in dev).
- The 30-day rule is stored and listed by RustFS; its expiry runs in the storage and was not observed here, because it
  needs 30 days. The quota refusal was checked by hand (`InvalidRequest: Bucket quota exceeded`), not by the CI.

## Tests

`tests/instance.sh dev` is the check the CI runs after starting the storage. It runs the setup twice (no secret in its
output, one lifecycle rule), then `tests/checks.sh` in a throwaway container of the `platform` network with the real
accounts: versioning, the 30-day rule, the quota, what the writer and the reader can and cannot do, a missing key, the
anonymous read and a wrong secret. It also checks the ports and that every check still passes after a restart.
`tests/instance.sh qa` checks that nothing is published. Both print their totals and fail if no check ran. By hand, export
the variables of the env file and run `sh tests/instance.sh dev`.

## Branching

Three permanent branches. **None of them accepts a direct commit** — you enter through a child
branch and leave through a Pull Request.

```
develop  <--PR--  feat/... fix/... chore/...
qa       <--PR--  qa/...
main     <--PR--  release/...  hotfix/...
```

Promotion happens **by re-application** (`git cherry-pick -x`), never by merging one permanent
branch into another: `merge develop -> qa` and `merge qa -> main` do not exist in this model.

`main` requires **1 approval from `ariel5253`**. On `develop` and `qa` the team sets its own review
rule.

Full policy: `00-governance/branching-policy.md` in `csp-docs`.
