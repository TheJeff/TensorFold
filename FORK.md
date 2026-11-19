# TensorFold — Windows ARM64 fork

Fork of [ashhart/TensorFold](https://github.com/ashhart/TensorFold) that carries the Windows ARM64
(NVIDIA RTX Spark N1X, `sm_121`) port and the Nemotron 3.5 Bolt lane.

## Branches

| branch | what it is |
| --- | --- |
| `main` | Working baseline: upstream **v1.1.6** (`eea9dc9c`) plus the Bolt recipe's `0002-register-bolt` patch and the Windows `tfgrammar.dll` name. This is what is built and served today. |
| `win-arm64/v1.2.3` | Re-port onto upstream **v1.2.3**. Upstream now ships the Windows grammar library itself (from v1.2.1), so only the Bolt recipe patch is carried. Builds and serves on the N1X (see below). |
| `win-arm64/v1.2.6` | Re-port onto upstream **v1.2.6** (2026-11-10). Builds and serves on the N1X; the A/B against v1.2.3 is in the parent repo's `BENCH-1.2.6.md`. Registry moved to `native/cuda_families.zig`, so `nemotron.bolt` is registered there. |
| `win-arm64/v1.2.7` | Re-port onto upstream **v1.2.7** (`93a2e93e`, 2026-11-19) plus MiaAI-Lab's five Flash-Next patches (MIT; parent repo `local-patches/mia-v1.2.7/`). Zero conflicts. Builds and serves on the N1X; PDF input and the stock quantised vision tower work; fp8 KV admits 5 full 262k streams. Receipts: parent repo's `UPSTREAM-1.2.7.md`, `BENCH-1.2.7.md`, `MIA-V127-REVIEW.md`. |

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

## Status of `win-arm64/v1.2.7`

The v1.2.6 delta applied onto `v1.2.7` with **zero conflicts** (the lane vtable, `build/cuda.zig`,
the family registry, `optional_libraries.zig`, `grammar.zig` and `server/cli.zig` are
byte-identical between the tags), then MiaAI-Lab's patches 0001-0005 as five commits: quantised
vision towers decode to bf16 at load (0001), 16k per-request image budget (0002), opt-in
`--kv-cache fp8` (0003), the MXFP8 prompt tile, default on, `TF_FLASHNEXT_PROMPT_MX128=0` off
(0004), and the video wiring, inert until `tfvideo.dll` exists (0005).

Built first attempt via the parent repo's `build-bolt-127.bat` (7.5 min, warm cache). Host gates:
codec diagnostics 12/12, vision-weights 16/16 (incl. 0001's quant tests), `check-native-cuda-host`
OK. Serve gate on the N1X: **0 failed, 0 warned** including PDF (`document.pdf` read back as
`PDFIUM-OK`, `corrupt.pdf` refused 400); the **stock unspliced** FP4-Local loads with `--vision`
(77.65 GiB, 55.9 s). fp8 KV admits **5 full 262,144-token streams** (4.72 GiB each vs bf16's 7.86,
which caps at 3); a 255,002-token needle is found on both dtypes. A/B vs v1.2.6 (power-capped
1761 MHz, cold n-gram cache after the 11-18 reboot — absolutes not comparable to BENCH-1.2.6's
warm day): prefill +1-5%, single-stream decode level, **8-stream +6.4% at 384-token replies**,
replies bit-identical. Bolt loads ~22 s and passes a strict `json_schema` through the copied
`tfgrammar.dll`. Full method and per-run JSON: parent repo's `BENCH-1.2.7.md`.

## Status of `win-arm64/v1.2.6`

`zig build native bolt install -Dsm=121` succeeds, first attempt, with Zig 0.17.0, CUDA 13.4.59 and
MSVC ARM64. Re-applying the v1.2.3 delta with `git apply --3way` left two structural conflicts and
no semantic ones: `zig/build/cuda.zig` lost `golden.zig` upstream (its step moved to
`cuda_server_host.zig`), so only the `bolt_build` import and `bolt_build.steps(b, nvcc)` call were
re-added; and the CUDA family registry moved into `zig/src/native/cuda_families.zig`, so
`nemotron.bolt` is registered there. The lane vtable is byte-identical to v1.2.3, so
`bolt_native.zig` needed no work.

Verified on the N1X: Qwen3.8 Flash Next FP4 loads in 35-42 s at 80.8 GiB and serves with replies
identical to v1.2.3 (same `primes` hash on every run); Nemotron 3.5 Bolt loads in 25.2 s and answers
through libbolt. Speed against v1.2.3, warm page cache: cold prefill level (2K +6%, 8K −1%, 32K
+1%), single-stream decode level, 8 concurrent streams **+3.7%**. Full receipts, method and the
page-cache trap that fakes a 25% prefill win: `BENCH-1.2.6.md` in the parent repo.

## Status of `win-arm64/v1.2.3`

`zig build native bolt install -Dsm=121` succeeds with Zig 0.17.0, CUDA 13.4 and MSVC ARM64. The one
API change the port needed: upstream's lane vtable now caps `prefill_step` with `max_rows`, so
`bolt_native.zig` takes that budget (0: uncapped) instead of ignoring it.

Smoke test on the RTX Spark N1X: `serve` loaded `Nemotron-3.5-Bolt-74B-A9B-24GB` in 23.2 s, served
`/v1/models`, prefilled 21 tokens and decoded at 144 tok/s through libbolt's MTP rounds. `bolt.dll`
itself is unchanged (the recipe's engine sources are), so the cached artifact is reused.

## Not done yet

JPEG (`turbojpeg.dll` 3.1.4.1) and WebP (`libwebpdecoder.dll` 1.6.0) are built and pixel-exact
(parent repo `build-jpeg.bat` / `build-webp.bat`, 2026-11-17). PDF (`pdfium.dll` from the
pypdfium2 5.14.0 win_arm64 wheel) works on `win-arm64/v1.2.7` (2026-11-19). **Video**
(`tfvideo.dll` + FFmpeg 9.0.2 for winarm64) is still not built; the 0005 wiring is in the branch
and inert until the DLL exists. See the parent repo's `NEXT-STEPS.md` item 3.
