# SBOMit Action

A GitHub Action that runs your build under [witness](https://github.com/in-toto/witness)
and generates an SBOM from the resulting attestation using [sbomit](https://github.com/sbomit/sbomit).

> **Status:** the file-trace pipeline is complete: your build runs under witness
> eBPF file tracing, a signed attestation is produced, an SBOM is generated from
> it, and all results are uploaded with a summary. Network trace
> (`network-trace: true`) is implemented but not yet tested on GitHub Actions,
> because no GitHub-hosted runner currently has a kernel it works on
> (see [Network trace](#network-trace)).

## How it fits into your workflow

This action is used **in place of the build step of your existing build job**.
Your job keeps doing what it already does: check out the source and prepare the
build environment (toolchains, environment variables, services). This action then
runs your build command under witness, and your later steps run as usual.

```yaml
jobs:
  build:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: actions/setup-go@v7
        with:
          go-version-file: go.mod
          cache: false                      # recommended, see "Accurate SBOMs" below
      - uses: Uk-jake/sbomit-pipeline-runner@main
        with:
          build-command: make build         # the command your build step runs
      - run: make test                      # later steps work as usual
```

What you provide and what the action does:

| Your job | This action |
|---|---|
| Checks out the source (before this action) | Installs witness, sbomit and syft |
| Sets up toolchains and environment | Runs `build-command` under witness eBPF tracing, with your environment |
| Runs any steps after the build | Returns files created by the build to the runner user |
| | Generates the SBOM and uploads the results as an artifact |

The action does not install or change any build toolchain. The Go version it
needs for building witness and sbomit is kept separate from your PATH and caches.

## Inputs

| Input | Default | Values |
|---|---|---|
| `build-command` | (required) | The command your build step runs. Multi-line allowed. |
| `network-trace` | `false` | `true`, `false`. `true` needs kernel 6.12+ (see [Network trace](#network-trace)) |
| `sbom-format` | `spdx23` | `spdx23`, `cdx14`, `cdx15` |
| `use-syft` | `true` | `true`, `false` (`cdx15` requires `false`) |

## Outputs

| Output | Description |
|---|---|
| `attestation-path` | Signed witness attestation |
| `sbom-path` | Generated SBOM |
| `metadata-path` | Run metadata (environment, tool versions, inputs) |

The SBOM document is named after your repository, and its version is the short
commit SHA of the checked-out source, so each SBOM identifies the build it describes.

## What you get

**An artifact** named `sbomit-<job>-<matrix index>-<sbom-format>` containing:

| File | What it is |
|---|---|
| `attestation.json` | Signed witness attestation of the build (DSSE envelope) |
| `sbom.spdx.json` or `sbom.cdx.json` | SBOM generated from the attestation |
| `signing.pub` | Public key to verify the attestation (the private key is never uploaded) |
| `witness-run.log` | witness output, for troubleshooting |
| `run-metadata.json` | Runner, kernel, tool versions and commits, inputs, and how far the run got |

**A summary** on the workflow run page with the SBOM result, what was traced,
a link to the artifact, and the environment and tool versions.

The artifact and the summary are produced even when the build or SBOM step
fails, so you can see how far the run got.

> Do not put secrets in `build-command`. The attestation records the command
> line. Pass secrets to the build through environment variables instead.

## Accurate SBOMs: turn off dependency caches

witness records what your build actually does. If dependencies are restored from
a cache (for example `actions/setup-go` caches by default), the build does not
download them, so that activity is not observed. For the most accurate SBOM,
disable dependency caching in the job that uses this action (for example
`cache: false` on `actions/setup-go`). Detailed guidance per ecosystem will be
added after testing how caches affect the results.

## Network trace

With `network-trace: true`, witness also records the network connections the
build makes (hosts, IPs and, for HTTPS, the requested URLs). sbomit uses them to
add `url=` and `ip=` qualifiers to the SBOM. The sbomit command is the same.

**How HTTPS is recorded.** witness redirects the build's connections to a local
proxy. To read HTTPS, the proxy acts as the server towards the build (man in the
middle): it presents a certificate for each requested host, signed by its own CA,
and makes the real, verified connection to the server itself. Programs in the
build accept these certificates only if they trust that CA. This action therefore:

1. creates a short-lived CA for the job (`[2-2]`). Its key stays in the runner's
   temp directory, never in your workspace, and is never uploaded,
2. adds it to the OS trust store for the build (`[2-2]`),
3. removes it again right after the build, also when the build failed (`[2-4]`),
   so your later steps do not trust it.

**Limitations**

- Kernel 6.12 or newer is required. The runner check refuses `network-trace: true`
  on older kernels. `ubuntu-22.04` (6.8) is too old, and kernel 7.0 (`ubuntu-26.04`,
  newer `ubuntu-24.04` images) is affected by the witness issue under
  [Requirements](#requirements). So no GitHub-hosted runner supports it today.
- Only the OS trust store is configured. Go, curl and git use it. Tools that
  ship their own CA list (for example Node/npm, Python requests/pip, Java) do not,
  and their HTTPS requests fail with a certificate error. Support per ecosystem
  will be added after testing.
- Tools that pin certificates cannot be traced this way.
- Ubuntu/Debian runners only (`update-ca-certificates`).
- Self-hosted runners: if the job is killed before `[2-4]`, the CA stays in the
  trust store until the next run of this action removes it (`[1-1]`). Its key is
  in the job's temp directory. Prefer ephemeral runners.

## Requirements

- Linux x86_64 runner with passwordless `sudo` (witness needs root for eBPF).
- A kernel where witness eBPF file tracing works. There is no ptrace fallback.
  - Tested: `ubuntu-22.04` (kernel 6.8).
  - Known issue: tracing fails on kernel 7.0 (`command-run eBPF trace missing pending open`),
    which affects `ubuntu-26.04` and newer `ubuntu-24.04` images. Tracked in go-witness.
  - `network-trace: true` needs kernel 6.12 or newer.
- Network access to github.com, dl.google.com, proxy.golang.org and sum.golang.org (tools are installed at run time).

## What happens inside

| Stage | Step | Script |
|---|---|---|
| Validate | inputs, workspace (source checked out) | `scripts/validate/` |
| Prepare | runner check, tool install | `scripts/prepare/`, `scripts/install/` |
| Run witness | signing key, network-trace CA, traced build, return file ownership, remove CA | `scripts/witness/` |
| Run sbomit | generate, check | `scripts/sbomit/` |
| Report | metadata, upload, summary | `scripts/report/` |

## Tools

Each tool is installed by one script in `scripts/install/`. The install
commands are at the top of each script, so changing how a tool is installed
means editing that one file.

| Tool | Script | How |
|---|---|---|
| witness | `witness.sh` | Built from `in-toto/witness` + `in-toto/go-witness` (`main` by default) with `go work` |
| sbomit | `sbomit.sh` | `go install github.com/sbomit/sbomit@latest` |
| syft | `syft.sh` | Pinned release archive from GitHub, verified against a SHA-256 pinned in the script |
| Go (tools only) | `go.sh` | Official archive, sha256-verified; isolated from your PATH and caches |

Tools are installed under the job's temp directory (`$RUNNER_TEMP/sbomit/tools`), and the exact versions
and commits used in a run are recorded for the run metadata.

## Running scripts locally

Every script reads `SBOMIT_*` environment variables and can run without GitHub Actions:

```bash
SBOMIT_BUILD_COMMAND="go build ./..." SBOMIT_NETWORK_TRACE=false \
SBOMIT_SBOM_FORMAT=spdx23 SBOMIT_USE_SYFT=true \
  bash scripts/validate/inputs.sh
```

## Contributing

Commits must be signed off (`git commit -s`) under the
[Developer Certificate of Origin](https://developercertificate.org/); a DCO check
runs on every pull request. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[Apache License 2.0](LICENSE)
