# On-device model

`range-parser.gguf` is not in the repository. `tools/fetch_model.sh` downloads it with [Ollama](https://ollama.com) and copies it here (`tools/push_model.sh` runs it when the file is missing):

- Ollama model `qwen2.5:0.5b`: [Qwen2.5-0.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct) by the Qwen team, Q4_K_M GGUF, Apache-2.0.
- Checked with `tests/ai` (31/31 valid requests, 26/26 rejections): blob `sha256-c5396e06af294bd101b30dce59131a76d2b773e76950acc870eda801d3ab0515`.
