# On-device model

- `range-parser.gguf`: [Qwen2.5-0.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct) by the Qwen team, quantized to Q4_K_M GGUF by [bartowski](https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF) (`Qwen2.5-0.5B-Instruct-Q4_K_M.gguf`), unmodified.
- SHA-256: `6eb923e7d26e9cea28811e1a8e852009b21242fb157b26149d3b188f3a8c8653`
- License: Apache-2.0 ([`LICENSE`](LICENSE), copied from the Qwen repository).

The file is stored with Git LFS, so it comes with `git clone` when git-lfs is installed. Without git-lfs (or once the repository's LFS quota is used up) the clone holds a small pointer file instead; `tools/fetch_model.sh` then downloads the same file from Hugging Face and checks its hash, and `tools/push_model.sh` runs it automatically.
