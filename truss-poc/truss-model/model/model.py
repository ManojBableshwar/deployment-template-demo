"""
Truss Model class for Qwen/Qwen3.5-0.8B text generation.

Implements the Truss model interface:
  - load(): called once at startup to load model weights
  - predict(request): called per inference request

Health behavior:
  - Truss server exposes GET / (liveness) returning 200 once model is loaded.
  - GET /v1/models/model (readiness) returns model status.

Endpoints available:
  - POST /v1/models/model:predict  (Truss native)
  - POST /v1/chat/completions      (OpenAI-compatible, built into Truss server)
"""

import os
from pathlib import Path

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer


class Model:
    def __init__(self, **kwargs):
        self._model = None
        self._tokenizer = None
        self._device = None

    def load(self):
        """Load model weights from the configured path.

        Priority:
        1. AZUREML_MODEL_DIR (set by AzureML when model is mounted) — only if it
           contains config.json (actual weights)
        2. MODEL_WEIGHTS_PATH (set in config.yaml / environment)
        3. /app/model-weights (default baked-in location)
        """
        # Determine model path
        model_path = None

        # Try AZUREML_MODEL_DIR first (AzureML sets this for registered models)
        azureml_dir = os.environ.get("AZUREML_MODEL_DIR")
        if azureml_dir:
            # AzureML may nest artifacts; find config.json
            config_files = list(Path(azureml_dir).rglob("config.json"))
            if config_files:
                model_path = str(config_files[0].parent)
                print(f"[truss-model] Using AzureML mounted model: {model_path}")
            else:
                print(f"[truss-model] AZUREML_MODEL_DIR={azureml_dir} has no config.json, falling back to baked-in weights")

        # Fall back to baked-in weights
        if model_path is None:
            model_path = os.environ.get("MODEL_WEIGHTS_PATH", "/app/model-weights")
            # Verify baked-in weights exist
            if not Path(model_path).exists() or not (Path(model_path) / "config.json").exists():
                # Try nested structure
                config_files = list(Path(model_path).rglob("config.json"))
                if config_files:
                    model_path = str(config_files[0].parent)
                else:
                    raise FileNotFoundError(
                        f"No model weights found. Checked AZUREML_MODEL_DIR={azureml_dir} "
                        f"and MODEL_WEIGHTS_PATH={model_path}"
                    )

        print(f"[truss-model] Loading model from: {model_path}")
        print(f"[truss-model] Files in path: {list(Path(model_path).iterdir())}")

        self._device = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"[truss-model] Device: {self._device}")

        self._tokenizer = AutoTokenizer.from_pretrained(
            model_path, trust_remote_code=True
        )
        self._model = AutoModelForCausalLM.from_pretrained(
            model_path,
            torch_dtype=torch.float16 if self._device == "cuda" else torch.float32,
            device_map="auto" if self._device == "cuda" else None,
            trust_remote_code=True,
        )
        if self._device == "cpu":
            self._model = self._model.to(self._device)

        print("[truss-model] Model loaded successfully.")

    def predict(self, request: dict) -> dict:
        """Run inference on input text.

        Request format:
            {
                "prompt": "Hello, how are you?",
                "max_new_tokens": 128,
                "temperature": 0.7,
                "top_p": 0.9
            }

        Response format:
            {
                "generated_text": "...",
                "usage": {
                    "prompt_tokens": N,
                    "completion_tokens": M
                }
            }
        """
        prompt = request.get("prompt", "")
        max_new_tokens = request.get("max_new_tokens", 128)
        temperature = request.get("temperature", 0.7)
        top_p = request.get("top_p", 0.9)

        inputs = self._tokenizer(prompt, return_tensors="pt").to(self._device)
        prompt_tokens = inputs["input_ids"].shape[1]

        with torch.no_grad():
            outputs = self._model.generate(
                **inputs,
                max_new_tokens=max_new_tokens,
                temperature=temperature,
                top_p=top_p,
                do_sample=temperature > 0,
                pad_token_id=self._tokenizer.eos_token_id,
            )

        # Decode only the generated tokens (exclude prompt)
        generated_ids = outputs[0][prompt_tokens:]
        generated_text = self._tokenizer.decode(generated_ids, skip_special_tokens=True)

        return {
            "generated_text": generated_text,
            "usage": {
                "prompt_tokens": prompt_tokens,
                "completion_tokens": len(generated_ids),
            },
        }
