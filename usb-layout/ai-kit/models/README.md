# ai-kit/models/ — GGUF weights live here

After running `build-usb.sh` you'll have three files here:

| File | Size | Source | Purpose |
|------|------|--------|---------|
| `gemma-4-E4B-it-Q4_K_M.gguf`         |  5.0 GB | [unsloth/gemma-4-E4B-it-GGUF](https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF) | Daily-driver chat / code / Q&A |
| `gemma-4-26B-A4B-it-UD-Q4_K_M.gguf`  | 17.0 GB | [unsloth/gemma-4-26B-A4B-it-GGUF](https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF) | Bigger MoE for harder reasoning |
| `embeddinggemma-300m-qat-Q8_0.gguf`  |  329 MB | [ggml-org/embeddinggemma-300m-qat-q8_0-GGUF](https://huggingface.co/ggml-org/embeddinggemma-300m-qat-q8_0-GGUF) | Sentence embeddings for future RAG |

All three are licensed Apache 2.0 with [Google's Gemma terms](https://ai.google.dev/gemma/terms)
on top — read those before redistributing weights commercially.

## Why these specific quantizations?

- **Q4_K_M**: best size/quality tradeoff for the 4 B-parameter E4B. ~5 GB,
  near-FP16 quality, runs on 8 GB RAM.
- **UD-Q4_K_M**: unsloth's "ultra-dynamic" Q4 K-mix for the 26B MoE. ~17 GB,
  noticeably better than vanilla Q4_K_M on the bigger model.
- **Q8_0 QAT**: quantization-aware-trained Q8 for the embedding model. Embeddings
  are unforgiving of quantization noise, so we keep this one at Q8 even
  though the file is small.

## Why not commit the GGUFs?

GitHub blocks single files >100 MB. All three of these are above that.
Git LFS could host them but the bandwidth costs are real — and they're
already on Hugging Face, served free.
