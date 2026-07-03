Please visit [https://xemu.app](https://xemu.app) for more information.

## Container Builds

The supported local build path is containerized. The host needs only this
checkout, Git, and a Docker-compatible CLI. Set `XEMU_DOCKER=podman` when using
Podman instead of Docker.

Build the native Linux target:

```sh
scripts/docker-build.sh native
```

Build the browser/WASM target:

```sh
scripts/docker-build.sh wasm
```

Build both targets:

```sh
scripts/docker-build.sh all
```

The native build writes to `build/` and `dist/`. The WASM build writes to
`build-wasm-sysroot/` and `build-wasm/`, then verifies the browser profile with
`scripts/xbox-verify-wasm-profile.sh`.

For a destructive clean rebuild from a clean worktree:

```sh
scripts/docker-verify-clean-build.sh --yes
```

That script refuses to run when tracked files or untracked non-ignored files are
present, then runs `git clean -fdx` and builds all supported targets through the
container wrappers.
