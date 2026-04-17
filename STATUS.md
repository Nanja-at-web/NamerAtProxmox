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

## Merge readiness

Not yet merge-ready.

Before merging into `main`, at least these points should be completed:

1. Finish the `dest` conversion in `ct/namer.sh`
2. Remove or explain the remaining `curl 404` side effect during CT creation
3. Run one more full Proxmox test after the final `ct/namer.sh` alignment

## Recommendation

Keep this branch as the active test branch until `ct/namer.sh` is fully aligned and retested.
