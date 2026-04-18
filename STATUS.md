# Project Status

Current working branch: `test/nfs-v1-autark-installer`

## Current status

The test branch has been validated on a real Proxmox VE host with a real QNAP NFS export.

### Confirmed working

- Proxmox Community-Scripts based CT creation
- NFS host mount on the Proxmox host
- bind mount into the LXC container
- embedded CT installer flow
- ThePornDB token handoff from host to CT installer
- Docker installation inside the CT
- Namer startup and reachable web UI
- healthcheck-based startup validation

## Destination directory default

The project is being aligned to use:

- `watch`
- `work`
- `failed`
- `dest`

instead of `DESTINATION`.

### Already switched to `dest`

- `install/namer-install-community.sh`
- `install/namer-install-standalone.sh`
- `README.md`

### Still pending

- `ct/namer.sh` still contains remaining `DESTINATION` references and must be aligned before merge to `main`.

## Important behavior

If the directories already exist on the NAS share, they should not be deleted.

The installer is intended to:

- reuse existing directories when present
- create missing directories only if needed
- never delete NAS media directories during CT setup or on installer failure

The optional write test should only create and remove a temporary test file.

## curl 404 side effect

A non-blocking `curl 404` still appears during CT creation.

### Current likely cause

The timing strongly suggests that this 404 comes from the Community-Scripts `build.func` install phase and not from the custom embedded Namer installer.

Reasoning:

- the message appears right after `Customized LXC Container`
- this matches known Community-Scripts issue patterns where `build.func` performs an internal install fetch using `lxc-attach ... curl ... install/${var_install}.sh`
- the branch then continues successfully with the custom bind-mount and embedded installer flow, which shows that the actual Namer installation path is separate

### Likely fix direction

One of these approaches is still needed:

1. fully own the `build.func` and related install URL chain for this repository and branch
2. bypass the automatic `build.func` install phase so only the custom embedded installer path is used

Until one of those is implemented, the 404 should be treated as expected noise and not as the real installation failure source.

## Merge readiness

Not yet merge-ready.

Before merging into `main`, at least these points should be completed:

1. Finish the `dest` conversion in `ct/namer.sh`
2. Remove or explain the remaining `curl 404` side effect during CT creation
3. Run one more full Proxmox test after the final `ct/namer.sh` alignment

## Recommendation

Keep this branch as the active test branch until `ct/namer.sh` is fully aligned and retested.
