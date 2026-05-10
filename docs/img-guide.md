# Offline Image Generation — Guide

> [!NOTE]
> **Image generation on CPU takes 1-3 minutes per 1024×1024 image and needs ~8-10 GB working RAM. On 8 GB hosts, stop the AI core (close `start.bat` or kill `llamafile`) before generating.**
>
> The kit's sd.cpp build targets AVX2 — the widest CPU vector extension that
> ships reliably without a GPU runtime dependency. There is no CUDA, no Metal,
> no Vulkan. Every pixel is computed on the CPU, which is orders of magnitude
> slower than a dedicated GPU. A mid-range laptop GPU would generate the same
> 1024×1024 image in 3-10 seconds; on CPU, the same work takes 60-180 seconds.
> This is the cost of "no drivers, no runtime, plug in and go." The trade-off
> is deliberate — the kit runs on any host without requiring GPU drivers or
> CUDA installation.

---

## Quick Start

Three steps. Nothing to install.

```text
1. Double-click start-img.bat (Windows) or start-img.command (macOS),
   or run ./start-img.sh on Linux.
2. Type your prompt at the "Prompt:" prompt and press Enter.
3. Wait 1-3 minutes. The PNG opens automatically when ready.
   File saved to USB root as img-out-YYYYMMDD-HHMMSS.png.
```

**Per OS:**

```bash
# Linux
./start-img.sh
```

```bash
# macOS — Finder double-click, or:
open start-img.command
```

```powershell
# Windows — Explorer double-click, or:
.\start-img.bat
```

The output PNG is timestamped (`img-out-20260509-143022.png`) so multiple runs
never overwrite each other. Every image lands at the USB root alongside the
launchers.

---

## How it works

The kit runs [stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)
(`master-596-90e87bc`) — a pure C++ implementation of Stable Diffusion and
FLUX inference. The binary lives at `ai-kit/sd-img/{linux,mac,win}/sd-cli[.exe]`,
roughly 10-25 MB per OS. No Python, no ONNX Runtime, no GPU driver.

The model is **FLUX.2 klein 4B Q4\_K\_M** (Black Forest Labs, January 2026).
Unlike SD 1.5 or SDXL, FLUX.2 is a **multi-file architecture** — the kit ships
three files that work together:

| File | Where on USB | Size | Role |
|---|---|---:|---|
| `flux-2-klein-4b-Q4_K_M.gguf` | `ai-kit/sd-img/models/` | 2.43 GB | Diffusion transformer |
| `full_encoder_small_decoder.safetensors` | `ai-kit/sd-img/models/` | 238 MB | VAE (encoder + decoder) |
| `Qwen3-4B-Q4_K_M.gguf` | `ai-kit/models/` | 2.33 GB | Text encoder (FLUX.2's `--llm`) |

**Qwen3-4B does double duty.** It lives at `ai-kit/models/` (alongside the
Gemma 4 weights, NOT inside `sd-img/`) because the AI core launcher
(`start.{sh,bat,command}`) runtime-detects it and offers it as a 3rd model
option (E4B / 26B / **Qwen3 4B**). One 2.33 GB fetch, two uses. Hollama picks
it up automatically via llamafile's `/v1/models`. If you skipped image gen at
build time, Qwen3 isn't on the stick and the AI core picker shows only 2
options — graceful degradation.

The launcher invokes sd-cli with the following recipe (per
[`sd.cpp/docs/flux2.md`](https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/flux2.md)):

```bash
sd-cli \
  --diffusion-model ai-kit/sd-img/models/flux-2-klein-4b-Q4_K_M.gguf \
  --vae ai-kit/sd-img/models/full_encoder_small_decoder.safetensors \
  --llm ai-kit/models/Qwen3-4B-Q4_K_M.gguf \
  -p "<your prompt>" \
  -H 1024 -W 1024 \
  --steps 4 \
  --cfg-scale 1.0 \
  --sampling-method euler \
  --diffusion-fa --offload-to-cpu \
  -o img-out-YYYYMMDD-HHMMSS.png
```

The `--steps 4` setting comes directly from FLUX.2 klein's distilled inference
recipe — the model was trained to converge in 4 denoising steps rather than the
20-50 that vanilla Stable Diffusion 1.5 or SDXL require. `--cfg-scale 1.0` and
`euler` sampler are the upstream-doc defaults for FLUX.2 klein 4B (the
non-distilled klein-base 4B uses `--cfg-scale 4.0 --steps 20` instead — don't
mix them up). `--diffusion-fa` enables flash attention; `--offload-to-cpu`
keeps peak working set down by paging weights through RAM rather than holding
all three components in VRAM-equivalent memory at once. Both flags are baked
into the launcher.

---

## Prompt-writing tips

- **Short prompts work as well as long ones.** FLUX is tuned at the model level;
  a five-word prompt like "a fox in a library" produces coherent results. You
  do not need to pad prompts with quality tokens like `masterpiece, 8k, highly
  detailed` the way SD 1.5 required.

- **FLUX renders legible text in images.** If you want a sign, label, or caption
  in the image, ask for it explicitly — e.g., "a coffee shop sign reading OPEN."
  SDXL and SD 1.5 produce scrambled gibberish for in-image text; FLUX gets it
  right most of the time. Qwen3-4B as the text encoder is even better at this
  than FLUX.1's clip_l + t5xxl combo.

- **Comma-separated style tags work.** Example: `a city skyline, watercolor,
  sunset` or `portrait of an astronaut, oil painting, dramatic lighting`. Style
  modifiers at the end of the prompt are processed naturally.

- **Negative prompts are not supported by FLUX in sd.cpp.** The launcher does
  not pass a `-n` flag for this reason. FLUX's distilled inference doesn't
  use classifier-free guidance the same way vanilla SD does; negative prompts
  either have no effect or degrade output. Don't add `-n` manually.

- **Don't change `--steps` or `--cfg-scale` for FLUX.2 klein 4B.** The recipe
  is `--steps 4 --cfg-scale 1.0 --sampling-method euler`. Using `--steps 20`
  or `--cfg-scale 7.0` (the vanilla SD 1.5 defaults) produces garbled output
  or wastes time with no quality gain. Those values are calibrated for a
  different training regime. The non-distilled `klein-base 4B` variant uses
  `--steps 20 --cfg-scale 4.0` — that's a different model, not the one shipped.

- **Example prompts that work well:**
  - `a Martian landscape at dusk, photorealistic`
  - `a knight in armor reading a paperback novel, detailed illustration`
  - `neon-lit Tokyo alley, rain reflection, cyberpunk`
  - `watercolor map of an imaginary island`

---

## Performance & expectations

The numbers below are measured at 1024×1024, 4 steps, `euler` sampler,
`--diffusion-fa --offload-to-cpu` on AVX2-capable CPUs. "Subsequent" latency
matches "First" because sd.cpp loads the model fresh on each invocation —
there is no persistent server keeping the model hot.

| Hardware | First-image latency | Subsequent |
|---|---:|---:|
| Modern laptop (Ryzen 7 / i7 / M1+, 16 GB RAM) | 60–120 s | 60–120 s |
| Older laptop (Ryzen 5 / i5, 8 GB RAM) | 180–240 s + must stop AI core first | 180–240 s |
| Raspberry Pi 5 (16 GB) | 8–15 min, be patient | 8–15 min |

**The "stop AI core first" row is non-negotiable on 8 GB hosts.** The AI core
(Gemma 4 E4B Q4\_K\_M, ~5 GB working set; or Qwen3-4B Q4\_K\_M, ~3 GB) and
image gen (~8-10 GB working set with all three components loaded) cannot
coexist on 8 GB total RAM. The OS will begin swapping or the OOM killer will
terminate one of them. Stop the AI core before launching image gen on any
machine with 8 GB or less.

To stop the AI core:
- Windows: close the `llamafile.exe` terminal window, or kill `llamafile.exe`
  in Task Manager.
- macOS / Linux: `pkill -f llamafile` in a terminal.

---

## Troubleshooting

<details>
<summary><strong>"ERROR: sd-cli not found" or "ERROR: ...gguf not found" or "ERROR: ...safetensors not found"</strong></summary>

The kit hasn't been built yet, or the build skipped image generation. Run
`./build-usb.sh /mnt/usb` (Linux/macOS) or `.\build-usb.ps1 D:\` (Windows)
and pick "Y" at the "Include offline image gen" wizard prompt. The image-gen
knob is opt-in (default N) because the model files total ~5 GB and not every
user needs it.

If you already ran the wizard and answered N, re-run with `./build-usb.sh -i
/mnt/usb` (the `-i` flag forces the wizard even if a config already exists)
and change the answer.

The launcher checks for all three files (transformer + VAE + Qwen3 encoder)
and fails fast if any is missing. A partial build can be completed by
re-running `build-usb` against the same target — the existing files are
detected and skipped, and only the missing ones are fetched.
</details>

<details>
<summary><strong>"Out of memory" / killed mid-generation</strong></summary>

Close every other application you can. On 8 GB hosts, the AI core (`start.bat`)
also wants 3-5 GB — stop it first (close the terminal, or `pkill -f llamafile`
on Linux/macOS, or close `llamafile.exe` from Task Manager on Windows).

If you are still running out of memory after stopping the AI core, try adding
`--vae-tiling` to the sd-cli invocation. This flag processes the VAE decode
pass in tiles instead of all at once, reducing peak RAM at the cost of 10-30
extra seconds:

```bash
# Edit start-img.sh (Linux/macOS) and add --vae-tiling to the sd-cli call:
sd-cli \
  --diffusion-model "$SD_MODEL" \
  --vae "$SD_VAE" \
  --llm "$SD_LLM" \
  -p "$PROMPT" \
  -H 1024 -W 1024 \
  --steps 4 --cfg-scale 1.0 --sampling-method euler \
  --diffusion-fa --offload-to-cpu --vae-tiling \
  -o "$OUTFILE"
```

```powershell
# Edit start-img.bat (Windows) and add --vae-tiling to the sd-cli call:
ai-kit\sd-img\win\sd-cli.exe ^
  --diffusion-model ai-kit\sd-img\models\flux-2-klein-4b-Q4_K_M.gguf ^
  --vae ai-kit\sd-img\models\full_encoder_small_decoder.safetensors ^
  --llm ai-kit\models\Qwen3-4B-Q4_K_M.gguf ^
  -p "%PROMPT%" ^
  -H 1024 -W 1024 ^
  --steps 4 --cfg-scale 1.0 --sampling-method euler ^
  --diffusion-fa --offload-to-cpu --vae-tiling ^
  -o "%OUTFILE%"
```
</details>

<details>
<summary><strong>PNG output is garbled, all-black, or not what you asked for</strong></summary>

Most likely an upstream sd.cpp + FLUX combo issue. Check the
[stable-diffusion.cpp issues](https://github.com/leejet/stable-diffusion.cpp/issues)
for your prompt pattern. If you don't find a match, file a new issue with:
the exact prompt you used, the kit's pinned sd.cpp version
(`master-596-90e87bc`), the model filename
(`flux-2-klein-4b-Q4_K_M.gguf`), and the companion files
(`full_encoder_small_decoder.safetensors`, `Qwen3-4B-Q4_K_M.gguf`). Include
whether the image is entirely black, partially rendered, or fully generated
but wrong.

One known cause of all-black output: running out of memory silently — sd.cpp
may produce a black PNG instead of crashing when the VAE decode runs out of
RAM. If you see all-black images, try `--vae-tiling` (see the OOM entry above)
before filing a bug.
</details>

<details>
<summary><strong>"missing tensor 'first_stage_model.*'" or "'text_encoders.*'" errors</strong></summary>

This was the v0.10 W3 BUG-2 failure mode. It means sd-cli loaded the FLUX.2
transformer but couldn't find the VAE or the text encoder. Check that all
three files exist on the stick:

```bash
ls -la ai-kit/sd-img/models/flux-2-klein-4b-Q4_K_M.gguf      # 2.43 GB
ls -la ai-kit/sd-img/models/full_encoder_small_decoder.safetensors  # 238 MB
ls -la ai-kit/models/Qwen3-4B-Q4_K_M.gguf                    # 2.33 GB
```

If any are missing, re-run `build-usb.{sh,ps1}` against the stick to fetch
them. If all three are present and you still get the error, check that the
launcher's `--vae` and `--llm` flags point to the correct paths — manual
edits to `start-img.{sh,bat,command}` may have introduced typos.
</details>

---

## Why FLUX.2 klein?

FLUX.2 klein (Black Forest Labs, January 2026) is newer than SDXL (2023) and
SD 3.5 (2024), with a smaller diffusion transformer — the Q4\_K\_M
quantisation brings the transformer alone to 2.43 GB versus SDXL Turbo's
4.1 GB Q8\_0. It ships under Apache-2.0 with no Stability AI Community License
registration overhead and no "Powered by Stability AI" attribution
requirement.

FLUX.2 is a **multi-file architecture**, unlike SD 1.5/SDXL's single-file
GGUFs. The kit ships the transformer, an Apache-2.0 ungated VAE
(`full_encoder_small_decoder.safetensors` from BFL's FLUX.2-small-decoder
release), and Qwen3-4B as the text encoder. Total image-gen footprint ~5 GB —
larger than SDXL Turbo's single 4 GB file, but with substantially better
quality, in-image text rendering, and a 4-step distilled inference loop that
keeps CPU wall-clock manageable.

The choice of Qwen3-4B as the text encoder is a kit win: BFL designed FLUX.2
to use a single LLM-style encoder (replacing FLUX.1's clip_l + t5xxl combo),
and that LLM happens to be a fully functional general-purpose chat model. So
the same 2.33 GB file that powers image gen also doubles as the kit's
lightest AI core option (start launcher menu choice [3]). One download, two
uses.

The kit uses sd.cpp rather than the `diffusers` Python stack because the
project's core constraint is "no Python on host" — users plug in a USB and
run native binaries, with no interpreter, package manager, or virtual
environment to install. sd.cpp is a single self-contained native binary per
OS, the same distribution model as llamafile and redbean.

---

## Advanced — different models

sd.cpp supports many model families beyond FLUX.2: SD 1.x, SD 2.x, SD 3/3.5,
SDXL, SDXL Turbo, FLUX.1, FLUX.2-dev, Chroma, Qwen Image, Z-Image (see
[leejet's README](https://github.com/leejet/stable-diffusion.cpp) for the
current list and any new additions). To swap models, drop the new files into
`ai-kit/sd-img/models/` and edit `start-img.{sh,bat,command}` to point the
flags at the new filenames. Recipe flags vary by model family:

- **FLUX.2 klein 4B (distilled, current default):** `--steps 4 --cfg-scale 1.0 --sampling-method euler --vae <vae> --llm <qwen3>`
- **FLUX.2 klein-base 4B (non-distilled):** `--steps 20 --cfg-scale 4.0 --sampling-method euler --vae <vae> --llm <qwen3>`
- **FLUX.1 schnell:** `--steps 4 --cfg-scale 1.0 --sampling-method euler --vae <ae> --clip_l <clip_l> --t5xxl <t5xxl>` (different encoder set)
- **SDXL Turbo:** `--steps 4 --cfg-scale 1.0 --sampling-method euler` (single-file GGUF, no `--vae`/`--llm` needed)
- **Vanilla SD 1.5:** `--steps 20 --cfg-scale 7.0 --sampling-method euler_a` (single-file)

Always check the model's recipe at
[`sd.cpp/docs/`](https://github.com/leejet/stable-diffusion.cpp/tree/master/docs)
before running — using the wrong sampler settings or omitting required
companion files for a given model family produces garbage output (or a
"missing tensor" error), not a graceful fallback.

---

*`docs/img-guide.md` — GitHub-readable companion. Not deployed to USB. Accessed via GitHub or local clone.*
