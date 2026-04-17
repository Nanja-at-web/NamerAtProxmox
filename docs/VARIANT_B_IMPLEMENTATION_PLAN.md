# Variant B Implementation Plan

This document is the repository-native source of truth for the current Variant-B migration on branch:

- `test/nfs-v1-autark-installer`

It exists so the project can be understood without relying on temporary chat uploads or expired attachments.

## Goal

Move the test branch from a mixed installer model to a clean Community-Scripts-aligned flow with exactly one real application installer.

Target flow:

```text
ct/namer.sh
-> misc/build.func
-> pre_install_hook
-> host NFS mount
-> bind mount into CT
-> install/namer-install.sh
-> Docker + Namer + namer.cfg
```

## Current status

Already implemented on the test branch:

- branch-local `misc/build.func`
- branch-local `misc/install.func`
- branch-local `misc/core.func`
- branch-local `misc/error_handler.func`
- branch-local `misc/api.func`
- branch-local `misc/tools.func`
- branch-local `misc/alpine-install.func`
- `ct/namer.sh` switched to branch-local `misc/build.func`
- `pre_install_hook` injection point added in branch-local `misc/build.func`
- destination directory naming aligned to `dest` in the main installer paths

Still pending:

- build native `install/namer-install.sh`
- move the NFS/bind-mount/token staging logic from the embedded installer path into `pre_install_hook`
- remove the embedded full installer from `ct/namer.sh`
- run a fresh end-to-end Proxmox test
- only after that consider merge to `main`

## Why this document matters

Chat attachments and temporary uploads may expire.
The repository itself must therefore contain enough context for a third party to understand:

- the intended architecture
- the current state
- the migration order
- the safety rules
- the remaining work

## Required safety rules

These rules are mandatory for all future installer changes.

### NAS media directories must never be deleted

The following directories are considered persistent media directories on the NAS share:

- `watch`
- `work`
- `failed`
- `dest`

Rules:

- existing directories must be reused
- missing directories may be created with `mkdir -p`
- these directories must never be removed automatically
- installer failure must not delete them
- CT creation failure must not delete them

### Write test must only use a temporary file

If write-test mode is enabled, only a temporary file may be created and removed again.
No directory cleanup is allowed.

## Directory naming standard

The branch is being normalized to:

```ini
watch_dir = /media/watch
work_dir = /media/work
failed_dir = /media/failed
dest_dir = /media/dest
```

`DESTINATION` is legacy naming and should not be used for the final Variant-B state.

## File responsibilities

### `ct/namer.sh`

Responsibility:

- user input collection
- host-side NFS preparation
- token prompt on host side
- orchestration only
- defines or exposes `pre_install_hook`

Must not remain the long-term location of the full Namer installer.

### `misc/build.func`

Responsibility:

- branch-local Community-Scripts wrapper
- branch-local URL chain
- runs `pre_install_hook` before the native installer if defined

### `install/namer-install.sh`

Responsibility:

- the one real installer inside the CT
- install Docker
- create `/opt/namer`
- create `.env`
- create `docker-compose.yml`
- create `/opt/namer/config/namer.cfg`
- use `/media/watch`, `/media/work`, `/media/failed`, `/media/dest`
- start Namer and verify health

### `misc/install.func`

Responsibility:

- branch-local installer helper path
- update helper paths must resolve to this repository and branch

## Required `pre_install_hook` duties

The future `pre_install_hook` in `ct/namer.sh` must handle at least:

1. attach host bind mount to the CT
2. reboot CT if needed after mount change
3. verify mount visibility in CT
4. optionally run the temporary write test
5. stage install variables into the CT, for example:
   - `NAMER_MEDIA_ROOT`
   - `NAMER_TPDB_TOKEN`
   - `NAMER_WATCH_DIR`
   - `NAMER_WORK_DIR`
   - `NAMER_FAILED_DIR`
   - `NAMER_DEST_DIR`
   - `NAMER_WEB_PORT`

A simple implementation target is a staged environment file such as:

- `/root/namer-install.env`

which is then consumed by `install/namer-install.sh`.

## Ordered implementation plan

The migration order is intentionally strict.

1. clean `ct/namer.sh`
2. add branch-local `misc/build.func`
3. add branch-local `misc/install.func`
4. add hook support in `misc/build.func`
5. build `install/namer-install.sh`
6. refactor `ct/namer.sh` to use `pre_install_hook`
7. full Proxmox retest
8. only then discuss merge to `main`

## Definition of done for Variant B

Variant B is only considered complete when all of the following are true:

- `ct/namer.sh` is an orchestrator and no longer embeds the full Namer installer
- `install/namer-install.sh` exists and works as the native installer path
- `pre_install_hook` performs NFS/bind/token preparation before install
- no stray `DESTINATION` references remain in the active path
- no unnecessary `curl 404` side-effect remains in the normal flow
- a full real-world Proxmox + QNAP test has passed again

## Suggested next action

The next concrete engineering step is:

- create `install/namer-install.sh`

After that:

- move the NFS and token staging work in `ct/namer.sh` into `pre_install_hook`
- remove the embedded installer path
