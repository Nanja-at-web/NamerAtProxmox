# Changelog

All notable changes to this project will be documented in this file.

## [0.4.1-test] - 2026-04-17

### Validated
- Test branch was validated on a real Proxmox VE host with a real QNAP NFS export
- NFS host mount, LXC bind mount, embedded installer flow, token handoff, Docker setup, and Namer web UI startup were confirmed working

### Changed
- Project direction documented around `dest` as preferred destination directory name
- Current branch state documented in `STATUS.md`

### Known Issues
- `ct/namer.sh` still contains remaining `DESTINATION` references and is not yet fully aligned with the new `dest` default
- A non-blocking `curl 404` side effect still appears during CT creation and should be cleaned up before merge to `main`

## [0.4.0-test] - 2026-04-08

### Added
- Test branch for autonomous NFS-v1 installer work
- Embedded CT installer flow in `ct/namer.sh`
- NFS host mount and bind mount workflow in `ct/namer.sh`
- Healthcheck support in generated Docker Compose files
- LICENSE and .gitignore

### Changed
- Updated script headers to `Nanja-at-web`
- Community installer and standalone installer now share token prompt and startup checks

### Notes
- This is a test branch state and not the final main-branch release
