# TensorFold — Windows ARM64 fork

Fork of [ashhart/TensorFold](https://github.com/ashhart/TensorFold) that carries the Windows ARM64
(NVIDIA RTX Spark N1X, `sm_121`) port and the Nemotron 3.5 Bolt lane.

## Branches

| branch | what it is |
| --- | --- |
| `main` | Working baseline: upstream **v1.1.6** (`eea9dc9c`) plus the Bolt recipe's `0002-register-bolt` patch and the Windows `tfgrammar.dll` name. This is what is built and served today. |
| `win-arm64/v1.2.3` | Re-port onto upstream **v1.2.3**. Upstream now ships the Windows grammar library itself (from v1.2.1), so only the Bolt recipe patch is carried. Builds and serves on the N1X (see below). |

Upstream `main` is far ahead of `main` here; do not merge it into `main`, re-port onto a release tag
in the `win-arm64/*` branch instead.

## What `main` carries beyond v1.1.6

- `zig/build/bolt.zig`, `zig/tests/bolt_lib_compile.zig`, `zig/src/families/nemotron/bolt_api.zig`,
  `zig/src/families/nemotron/bolt_native.zig` — the libbolt backend and its build step, from the
  recipe repo [MiaAI-Lab/Nemotron-3.5-Bolt-TensorFold-DGX-Spark](https://github.com/MiaAI-Lab/Nemotron-3.5-Bolt-TensorFold-DGX-Spark)
  (`patches/0002-register-bolt.patch`, PR #7).
- `zig/src/cli/hub.zig`, `zig/src/families/nemotron/cuda.zig`, `zig/src/native/cuda.zig`,
  `zig/src/server/main.zig` — `nemotron_h_puzzle` registration and the omni-wrapper detection.
- `zig/src/core/lanes/grammar.zig`, `zig/src/platform/optional_libraries.zig` — `tfgrammar.dll` on
  Windows. Obsolete from upstream v1.2.1 onward.

## Build (Windows ARM64)

Zig 0.17.0 `aarch64-windows`, CUDA 13.4, MSVC ARM64 build tools (`vcvarsall.bat arm64`):

```bat
zig build native bolt install -Dsm=121 -Dstrip=true ^
  -Dnvcc="%CUDA_PATH%\bin\nvcc.exe" ^
  -Dbolt-src="<path to bolt-recipe>\engine"
```

The server is `zig-out\native\bin\tensorfold-native.exe`; `bolt.dll` is built into `zig-out\native\lib`
beside it. Upstream's Windows notes are in `docs/WINDOWS.md`.

## Status of `win-arm64/v1.2.3`

`zig build native bolt install -Dsm=121` succeeds with Zig 0.17.0, CUDA 13.4 and MSVC ARM64. The one
API change the port needed: upstream's lane vtable now caps `prefill_step` with `max_rows`, so
`bolt_native.zig` takes that budget (0: uncapped) instead of ignoring it.

Smoke test on the RTX Spark N1X: `serve` loaded `Nemotron-3.5-Bolt-74B-A9B-24GB` in 23.2 s, served
`/v1/models`, prefilled 21 tokens and decoded at 144 tok/s through libbolt's MTP rounds. `bolt.dll`
itself is unchanged (the recipe's engine sources are), so the cached artifact is reused.

## Not done yet

JPEG (`turbojpeg.dll`), WebP (`libwebpdecoder`) and video (`tfvideo.dll` + FFmpeg) are not built for
Windows ARM64 yet; plain text, structured output and tool calls are. See the recipe repo's
`NEXT-STEPS.md`.
