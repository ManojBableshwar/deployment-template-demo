FROM vllm/vllm-openai:latest

# Install runit (provides runsvdir) required by Azure ML managed endpoints
RUN apt-get update && apt-get install -y --no-install-recommends runit && \
    rm -rf /var/lib/apt/lists/*

# Create runit service directory for vLLM
RUN mkdir -p /var/runit/vllm

# vLLM runit service: starts the OpenAI-compatible API server on port 8000
# See vllm-run.sh for details — strictly offline, no HF Hub downloads.
COPY vllm-run.sh /var/runit/vllm/run
RUN chmod +x /var/runit/vllm/run

# Reset base image entrypoint so CMD runs as the main process
ENTRYPOINT []
CMD ["runsvdir", "/var/runit"]
