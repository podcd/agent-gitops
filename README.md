# agent-gitops

A local AI research stack, declared as [podcd](https://podcd.github.io/podcd/) documents and reconciled onto this workstation by the podcd agent. Git is the desired state:
nothing here is configured by hand on the host, and a change is a commit.

## What it deploys

| Application | Listens on | What it is |
|---|---|---|
| `ollama` | `127.0.0.1:11434` | Local inference runtime, GPU-backed, with the model list pulled from Git |
| `litellm` | `127.0.0.1:4000` | OpenAI-compatible proxy in front of both ollama and any cloud provider |
| `open-webui` | `127.0.0.1:3000` | Browser chat UI, pointed at both of the above |
| `monitoring` | `127.0.0.1:3001` | Grafana over Prometheus and Loki: GPU, proxy traffic, container resources, logs |

All of them run as rootless podman pods on a shared podman network named `ai`, so they resolve each other by pod name. The network is a `Network` document in Git like everything else: podcd creates it before the first pod that joins it and removes it after the last one leaves. Every port is bound to loopback; nothing is reachable from outside the machine.

## Requirements

- Linux with rootless podman, cgroups v2, and `subuid`/`subgid` ranges for your user
- `podcd` on `PATH` (this repository was built against v4.1.1)
- An NVIDIA GPU, if you want the models on the GPU rather than the CPU

## Getting started

```bash
make bootstrap    # seed agent.env, pre-pull images, install and start the agent
make status       # what the host is running, and when it last reconciled
make endpoints    # the three URLs, and the proxy key
```

`make bootstrap` pre-pulls every image the compiled configuration names, then points the agent at this checkout as a local Git remote. The agent reconciles the **committed** state, so an edit to the working tree changes nothing
until you commit it. Run `make reconcile` after each commit instead of waiting for the one-minute loop.

To reconcile from a real remote instead, push this repository somewhere and re-run
`./bootstrap/bootstrap.sh --repo-url git@github.com:you/agent-gitops.git`.

## Layout

```
applications/     Pod templates: what each workload is
config/           The litellm proxy config, carried as a ConfigMap
infrastructure/   Environment, Group and Host: which workloads run here
secrets/          Where secrets come from, never the secrets themselves
values/           The knobs: image tags, ports, model list, GPU mode
bootstrap/        Host preparation the agent cannot do for itself
```

Values are layered. `values/common.yaml` holds values for the local environment; `values/workstation.yaml` overrides it per key for this machine.

## Changing things

**Add or remove a model.** Edit `ollama.models` in `values/workstation.yaml` and
commit. Each entry names the model and says whether its chat template accepts tool
definitions (`curl :11434/api/show -d '{"model":"..."}'` lists `tools` under
`capabilities`). That flag picks the litellm route: native pass-through for models
that support tools, JSON-mode emulation for those that do not. Without it, ollama
rejects any request carrying tools with `does not support tools`, which is every
request an agent like Cline makes. Emulation works, but it is markedly less reliable
than native, and an agent that issues a tool call every turn will stumble on it. The model-puller sidecar pulls anything new the next time it starts, and
the same list generates litellm's local model entries, so the proxy and the runtime
cannot drift apart.

Note that removing a model from the list stops advertising it through litellm, but
does not delete the weights from the `ollama-models` volume. Reclaim that space with
`podman exec ollama-ollama ollama rm <model>`.

**Enable a cloud provider.** Two steps, both required:

```bash
# 1. the key, on the host, never in Git
umask 077 && echo 'ANTHROPIC_API_KEY=sk-ant-...' >> ~/.config/podcd/agent.env
# 2. the switch, in Git
#    values/common.yaml -> litellm.cloud.anthropic: true
```

If you flip the switch without adding the key, litellm alone is held back and reported as failed.

**Change a port, an image tag or a memory limit.** All of them are in
`values/common.yaml`.

## GPU

`gpu.mode` in `values/common.yaml` selects how the GPU reaches the container.

`wsl` (the default) bind-mounts `/dev/dxg` and the whole of `/usr/lib/wsl`, `libnvidia-ml.so.1` reaches through `libdxcore` into the Windows driver store under `/usr/lib/wsl/drivers`, and mounting only `/usr/lib/wsl/lib` gets you `NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver`.

`cdi` asks for `nvidia.com/gpu=all` through `resources.limits`.
It is the portable way to request a GPU and the right choice if this repository ever reconciles a non-WSL host, but it needs `nvidia-container-toolkit` and a generated `/etc/cdi` spec (See`./bootstrap/nvidia-cdi.sh`) as well as a podman new enough to honour CDI
selectors in `kube play`.

Podman 4.9.3, which Ubuntu 24.04 ships, does not document them. Verify with `make gpu-check` before trusting it.

`none` runs on the CPU.

Confirm whichever mode you chose actually worked:

```bash
make gpu-check    # nvidia-smi from inside the ollama container
podcd logs ollama | grep "inference compute"
```

The second one prints the library ollama chose, the device it found and the VRAM available to it.

## Sizing

This stack was sized for 8GB of VRAM, where roughly 6.9GB is actually available to a container. Three things follow, and they are all in `values/`:

- **Q4_K_M quantization.** Q3 introduces subtle syntax errors in generated code.
- **8K context.** Larger contexts push KV cache past the card, and layers that spill to the CPU cost far more throughput than a smaller context does.
- **One loaded model at a time** (`OLLAMA_MAX_LOADED_MODELS: 1`). A second resident model does not fit.

A 7B-class model at this size is good at generating snippets, explaining code and answering questions. It will not reliably drive an agent's plan-execute-verify loop across multiple files.


## Monitoring

`http://127.0.0.1:3001/d/ai-stack` is one dashboard, provisioned from Git, with no
login on this single-user box. Top row is the GPU (VRAM, utilisation, temperature and
power), the middle is what goes through litellm (requests, tokens and latency per model,
which is where a local-versus-cloud comparison becomes a number), then container memory
and CPU, then logs.

Everything lives in one pod, `monitoring`, sized at about 370MB resident in total:

| Container | Role |
|---|---|
| grafana | The UI. Datasources and the dashboard are ConfigMaps, so the state on disk is only what you change in the browser |
| prometheus | Metrics, 15 days by default |
| loki | Logs, 7 days by default |
| alloy | Reads this user's systemd journal, which is where rootless podman writes every container's output, and ships it to Loki |
| gpu-exporter | `nvidia-smi` as metrics, through the same WSL mounts ollama uses |
| podman-exporter | Per-container CPU and memory, over the podman API socket |

Only Grafana and Prometheus get host ports; Prometheus at `:9090/targets` is the fastest
way to see whether a scrape target is up. Retention and ports are in `values/common.yaml`
under `monitoring`. `hostUid` in `values/workstation.yaml` locates the podman socket.

Logs are labelled by `container` (the `pod-container` name podman assigns) and by
`identifier` (the syslog identifier, `podcd` for the agent itself). The `job` label is
not what Alloy's config would suggest: Loki keeps the component name there, so the
dashboard selects on `container` and `identifier` instead.

Three things here needed to be root inside their container, which rootless podman maps
straight back to your user: Alloy, because the journal ACL grants read to that uid and
nobody else; podman-exporter, because the socket is owned by it; and the three data
stores, because the named volumes are created by it. The images' own unprivileged users
would land in the subordinate uid range and be refused.

Alloy keeps its journal cursor on a volume. Without that, every restart replayed the
last day of journal and Loki refused each line as `entry too far behind`.

To change the dashboard, edit it in Grafana, export the JSON, and paste it over
`ai-stack.json` in `config/grafana-dashboards.yaml`. The provisioned copy is read-only
in the UI on purpose: an edit that is not in Git is lost on the next pod restart.

## Using it from an editor

```bash
make vscode       # install the Cline extension, and print the settings below
```

Cline is the agentic VS Code extension this stack is built for: open source, actively maintained, and able to take an arbitrary OpenAI-compatible base URL. Its extension state lives in the editor rather than in a file this repository can own, so the three values below are entered once by hand.

Point any OpenAI-compatible client at the proxy, so switching between a local and a
cloud model is a model name rather than a reconfiguration:

```
Base URL:  http://127.0.0.1:4000/v1
API key:   the LITELLM_MASTER_KEY from `make endpoints`
Model:     local/qwen2.5-coder-7b
```

Cline can also talk to ollama directly at `http://127.0.0.1:11434` if you would rather skip the proxy, at the cost of losing the per-request cost and latency logging that makes local-versus-cloud comparisons measurable.

## Operating

```bash
make plan         # what the agent would change, changing nothing
make reconcile    # apply now instead of waiting for the loop
make health       # what podman says about the running applications
make logs         # agent logs
make models       # models currently resident
make lint         # check every document without touching the host
make teardown     # stop and remove everything, and uninstall the agent
```
