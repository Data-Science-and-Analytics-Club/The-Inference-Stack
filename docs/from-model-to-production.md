# From Model to Production: The Engineering Behind AI Inference

A conceptual companion to the live demonstration of hosting an
open-weight language model with vLLM.

**Repository guide:** [Start at the main README](../README.md) for the reading order and all reference material. When you are ready to run the demos, continue to the [vLLM live-demo runbook](vllm-qwen3-8b-runbook.md) or the [llm-d CPU routing demo](llm-d-cpu-routing-demo.md). The [presentation deck](../slides/inference-stack.pdf) provides the event-level overview.

This guide is designed to help you understand the systems around an
inference demo---not just copy commands. You do **not** need to master
every section before experimenting. Follow the path, run small tests,
and use the linked references to go deeper.

> **What you will learn**
>
> -   How an application reaches a model running on a remote server.
> -   What a rented GPU server, SSH, ports, DNS, HTTP, and `curl`
>     actually do.
> -   How vLLM serves a model and what happens when you send a prompt.
> -   Why GPU memory, the KV cache, PagedAttention, and batching matter.
> -   How this connects to a larger serving architecture using
>     Kubernetes and llm-d.

## Start here: the request lifecycle

When you type a prompt into an application, the request has to travel
through several layers before the model can answer.

``` text
Your application
      |
      | HTTPS request to a hostname
      v
DNS resolves hostname -> IP address
      |
      v
Public endpoint / proxy
      |
      | forwards traffic to a port
      v
Remote server running vLLM
      |
      v
Model execution on CPU or GPU
      |
      v
Generated tokens -> HTTP response -> your application
```

Each layer has a different responsibility:

  -----------------------------------------------------------------------
  Component                           Responsibility
  ----------------------------------- -----------------------------------
  Application                         Builds the prompt and displays the
                                      answer

  DNS                                 Helps translate a hostname into the
                                      address needed to reach a service

  HTTP/HTTPS                          Defines how the client and server
                                      exchange requests and responses

  Port                                Identifies the network service on a
                                      machine or network endpoint

  Public proxy / endpoint             Makes a service reachable from
                                      outside its private runtime

  vLLM                                Loads and serves the model,
                                      schedules requests, and returns
                                      generated output

  GPU                                 Performs supported model
                                      computations in parallel

  VRAM                                Holds model weights, KV-cache
                                      state, and other GPU working data
  -----------------------------------------------------------------------

The key idea: **a model, a model server, a network endpoint, and an
application are different things.** They work together, but they are not
interchangeable.

------------------------------------------------------------------------

## 1. What are we hosting?

### Model weights are not the application

A trained language model consists of learned numerical parameters,
commonly called *weights*, along with its architecture and
configuration. The weights alone do not provide a web page, an HTTP API,
authentication, or an application interface.

To make a model useful to an application, we need software that loads
the model, runs inference, and exposes a way to submit requests. That is
the model-serving layer.

In this demonstration:

-   **Qwen3-8B** is the language model.
-   **vLLM** is the inference engine and API server.
-   **RunPod** provides rented compute infrastructure for the demo.
-   **The application or `curl`** acts as the client sending prompts.
-   **The public endpoint** provides a network path from the client to
    the service.

### What does "open-weight" mean?

An open-weight model makes its learned weights available for download,
subject to its license. This gives you the option to run the model on
infrastructure you control or rent.

It does not mean that running the model is free. You still need compute,
memory, storage, networking, and operational work. It also does not
automatically mean every part of the model's training process or data is
open.

### What is inference?

**Inference** is using a trained model to produce an output. For a
language model, the system processes the prompt and generates output
tokens. For an image classifier, it might produce a label and confidence
score.

Training changes model parameters. Ordinary inference uses the
already-trained parameters to produce predictions or responses.

------------------------------------------------------------------------

## 2. What is RunPod, and what is a GPU server?

RunPod is a cloud platform where you can rent compute environments,
including machines with GPUs. For this demo, the important point is not
the provider itself: it is that the model runs on a remote machine
rather than on your laptop.

A **server** is a machine or process that provides a service to clients.
A server does not have to be a physical rack in a data centre; it can be
a virtual machine or container running on shared physical hardware.

A **GPU server** is a server with access to a graphics processing unit.
GPUs are useful for many neural-network workloads because they can
execute large amounts of parallel mathematical work. The exact
performance depends on the model, hardware, software, and workload.

### CPU, GPU, and VRAM

-   **CPU:** general-purpose processor, suited to a broad range of
    operating-system, application, and sequential tasks.
-   **GPU:** processor with many parallel computing resources, often
    useful for neural-network matrix operations.
-   **VRAM:** memory attached to or dedicated to the GPU. It stores
    model weights and other data needed during inference.

A model may fail to load even when the machine has plenty of ordinary
system RAM if there is not enough available GPU memory for the selected
configuration. Quantization, model size, context length, and concurrent
requests can all affect memory requirements.

### A minimal GPU example

If the rented environment has NVIDIA drivers and the NVIDIA management
utility installed, run:

``` bash
nvidia-smi
```

Look for:

-   **GPU name** --- the accelerator available to the environment.
-   **Memory usage** --- how much GPU memory is in use.
-   **GPU utilization** --- how busy the GPU's compute engines were
    during the sampling interval.
-   **Temperature and power** --- useful indicators of current operating
    conditions.
-   **Processes** --- processes the utility can attribute to the GPU.

Memory usage and utilization are different measurements. A model can
occupy GPU memory while waiting for a request, so high memory usage with
low utilization is not automatically an error.

To refresh the display once per second:

``` bash
watch -n 1 nvidia-smi
```

### What is CUDA?

CUDA is NVIDIA's platform and programming model for running
general-purpose computations on NVIDIA GPUs. Libraries and frameworks
can use CUDA-enabled operations to execute supported workloads on the
GPU.

A useful mental model is:

``` text
vLLM serves and schedules requests
          |
          v
Frameworks and GPU kernels execute model operations
          |
          v
CUDA-enabled software uses the NVIDIA GPU
          |
          v
GPU compute + VRAM
```

This is a conceptual view, not every internal software layer. CUDA is
not the model, and it is not the API server.

------------------------------------------------------------------------

## 3. How do you connect to a remote server?

### SSH: a remote terminal

**SSH (Secure Shell)** lets you securely open a terminal session on a
remote machine, provided you have the correct access and network route.

When you use SSH, your terminal is on your local machine, but the
commands you type are executed on the remote server.

This distinction matters when running commands:

-   `nvidia-smi` in the GPU environment inspects that environment's GPU.
-   `curl http://localhost:8000/...` uses the network namespace of the
    environment where `curl` is running.
-   A shell variable set inside a container is not automatically
    available in your laptop's terminal.

Use the connection method and command provided by your cloud
environment. Do not share private SSH keys, access tokens, or API keys.

### What is a port?

An IP address identifies a network endpoint, while a **port** identifies
a service endpoint on that machine or network endpoint. Together, an
address and port help direct traffic to the intended service.

Common examples:

  Port     Common use
  -------- -------------------------------------------------------------
  `22`     SSH
  `80`     HTTP
  `443`    HTTPS
  `8000`   Often used by development APIs, including this vLLM example

Port `8000` is a convention for this demo, not a special port reserved
for AI. A service can listen on a different port if configured to do so.

### What is HTTP?

HTTP is a protocol that defines how clients and servers exchange
requests and responses. HTTPS is HTTP protected with TLS encryption.

A request commonly contains:

-   A **method**, such as `GET` or `POST`.
-   A **path**, such as `/v1/chat/completions`.
-   **Headers**, such as the content type and authorization.
-   A **body**, often JSON, containing the request data.

The server sends a response containing a status code, headers, and
usually a response body.

A status of `200 OK` generally indicates that the HTTP request
succeeded. It does not by itself prove that the answer is correct or
that the service is production-ready.

### What is DNS?

People use hostnames because they are easier to remember than IP
addresses. **DNS (Domain Name System)** helps resolve a hostname into
records, often including the IP address needed to reach a service.

For example, a client requests a hostname such as:

``` text
https://example-service.provider-domain.net
```

The client uses DNS resolution to discover where that hostname points.
It then establishes a connection to the resolved destination and sends
an HTTPS request. DNS resolution does **not** itself carry the model
prompt or generate the model's response.

A cloud provider may give a service a public hostname that includes a
proxy or routing layer. That provider-managed hostname can forward
traffic to a configured internal service port.

### Why the public RunPod URL matters

Inside the same environment as the vLLM process, a request to
`localhost:8000` targets port 8000 on that local network namespace.

From your laptop, `localhost:8000` means port 8000 on **your laptop**,
not the rented server.

The public endpoint provides the route from your laptop to the remote
service:

``` text
Request from your laptop
       |
       v
Provider's public hostname
       |
       v
Provider proxy forwards to configured port
       |
       v
vLLM API listening on port 8000
       |
       v
JSON response returned to the client
```

The provider's exact networking implementation can vary. The important
concept is that the public hostname and proxy make a service reachable
externally; they are not the model itself.

------------------------------------------------------------------------

## 4. What is `curl`, and how does an application call the model?

`curl` is a command-line tool for making network requests. It is useful
for testing an API without building a user interface first.

A simplified example of a request to a chat-completion API looks like
this:

``` bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-8B",
    "messages": [
      {
        "role": "user",
        "content": "Explain DNS in two sentences."
      }
    ],
    "max_tokens": 100
  }'
```

This is an **illustrative request**, not a guarantee that the API is
reachable or that authentication is disabled. Your actual service may
require an authorization header and a different hostname. Follow the
working commands in the accompanying runbook.

Break it down:

-   `curl` sends the HTTP request.
-   The URL identifies the server and API path.
-   `Content-Type: application/json` says the body is JSON.
-   The JSON body names the model and contains the conversation
    messages.
-   The API returns a response, commonly JSON, containing the generated
    message and usage information.

### Why test with `curl` before integrating an application?

It separates two questions:

1.  **Can the model-serving endpoint accept a request and return a
    response?**
2.  **Can my application call that endpoint and handle its response
    correctly?**

If the first works but the application fails, you can investigate the
application integration separately: URL, authentication, request format,
timeout, networking, or response parsing.

### How does the application fit in?

The application does not usually need to load the model weights itself.
It can send a request to the inference API and display the returned
answer.

``` text
User types a prompt
       |
       v
Application constructs API request
       |
       v
HTTP client sends request to vLLM endpoint
       |
       v
vLLM runs inference
       |
       v
Application receives JSON response
       |
       v
UI displays generated text
```

Keep API keys on the server side of your application when possible. Do
not embed privileged keys in public browser code or commit them to a
repository.

------------------------------------------------------------------------

## 5. What happens when vLLM receives a prompt?

vLLM is an inference engine designed for serving language models. In
addition to executing model operations, a serving engine manages
incoming requests and the resources needed to generate responses.

For the demo:

-   **Qwen3-8B** is the model.
-   **vLLM** loads and serves that model.
-   The API accepts chat-completion requests.
-   The model generates output tokens.
-   The server returns the response to the caller.

The same conceptual separation applies to other inference engines,
although their interfaces, hardware support, and optimization strategies
differ.

### Tokens and autoregressive generation

Language models do not generally generate an entire paragraph in one
indivisible operation. Text is represented as **tokens**---units that
may correspond to words, word fragments, punctuation, or other pieces of
text.

An autoregressive language model repeatedly predicts a next token based
on the prompt and tokens generated so far. The process continues until a
stopping condition is reached, such as an end token or a generation
limit.

### Prefill and decode

It helps to distinguish two stages:

1.  **Prefill:** the model processes the input prompt and computes the
    attention information needed to begin generation.
2.  **Decode:** the model generates subsequent tokens step by step,
    reusing previously computed attention state.

The stages have different performance characteristics. A long prompt can
make prefill expensive; generating a long answer requires many decode
steps.

------------------------------------------------------------------------

## 6. KV cache: reusing work during generation

Transformer attention uses **keys** and **values** derived from token
representations. As a language model generates more tokens, it can store
the previously computed keys and values and reuse them in later decoding
steps.

That stored attention state is the **KV cache**.

### An analogy

Imagine solving a multi-step problem while keeping your earlier
calculations on paper. You can refer to those calculations instead of
recomputing everything from scratch every time you add a new step.

The KV cache serves a similar purpose for attention state during
autoregressive generation.

### Why it helps

Without reusing cached attention state, the system would need to redo
more of the work associated with previous tokens at each decode step.
Reusing the cache avoids that repeated computation and makes generation
more practical.

### Why it is also a memory problem

The KV cache occupies memory. Its size generally increases with:

-   The number of tokens in active sequences.
-   The number of simultaneous requests.
-   The model's architecture, including its attention configuration and
    number of layers.
-   The cache data type.

The GPU must hold model weights, KV-cache data, and other working data
within its available memory. Serving more concurrent requests therefore
creates a resource-management problem, not just a compute problem.

**Key takeaway:** the KV cache trades additional memory capacity for
less repeated attention computation. It is useful, but it is not free
and it is not unlimited.

------------------------------------------------------------------------

## 7. PagedAttention: managing KV-cache memory in blocks

PagedAttention is the attention-memory management approach introduced by
vLLM. It draws on the idea of virtual-memory paging: manage data in
fixed-size blocks rather than requiring each sequence to occupy one
large contiguous region of memory.

### The problem it addresses

Requests have different prompt and output lengths. If memory is reserved
inefficiently for sequences, some space may be wasted or become
difficult to use. That can limit how many sequences fit in GPU memory at
once.

### The basic idea

-   Divide KV-cache storage into blocks.
-   Allocate blocks as needed for active sequences.
-   Use a mapping structure to associate a sequence's logical tokens
    with physical cache blocks.
-   Allow blocks for a sequence to be physically non-contiguous.

This flexible allocation can reduce memory waste and help the server
accommodate more active sequences.

### What PagedAttention does not mean

-   It does not eliminate the KV cache.
-   It does not create extra physical VRAM.
-   It does not guarantee that every workload will be faster.
-   It is not the same thing as the model's learned weights.

Its main contribution is more flexible and efficient management of the
KV-cache memory used during serving.

------------------------------------------------------------------------

## 8. Batching, latency, and throughput

### What is batching?

A GPU can often process work more efficiently when requests are
scheduled together rather than handled as entirely isolated tasks.

**Continuous batching** lets a serving engine add new requests as other
sequences finish, instead of waiting for an entire fixed batch to
complete before admitting more work. This can help keep the GPU busy and
improve aggregate throughput.

Batching is not a guarantee of lower latency for every user. More
concurrent work can increase queueing or resource contention, depending
on the workload and configuration.

### Understand the metrics

  -----------------------------------------------------------------------
  Metric                              Meaning
  ----------------------------------- -----------------------------------
  Time to first token (TTFT)          How long a request waits before
                                      receiving its first generated token

  Inter-token latency                 Time between successive generated
                                      tokens

  Request latency                     Time taken for an individual
                                      request, based on the chosen start
                                      and end points

  Throughput                          Amount of work completed per unit
                                      time, often measured in output
                                      tokens per second

  GPU utilization                     How busy GPU compute was during the
                                      sampling interval

  VRAM usage                          GPU memory occupied or allocated
                                      for weights, cache, and working
                                      data
  -----------------------------------------------------------------------

A system can increase aggregate throughput without improving every
user's latency. Performance must be evaluated against the workload and
the metric that matters to the application.

------------------------------------------------------------------------

## 9. From one model server to Kubernetes and llm-d

The GPU demo focuses on one model-serving endpoint. Larger systems may
run multiple model-server replicas and need to manage deployment,
networking, health, capacity, and routing.

These components have different responsibilities:

  -----------------------------------------------------------------------
  Component                           Responsibility
  ----------------------------------- -----------------------------------
  Kubernetes                          Orchestrates workloads and
                                      resources, including Pods,
                                      Services, scheduling, and health
                                      management

  vLLM                                Executes the model and serves
                                      inference requests

  Envoy                               Proxy that receives and forwards
                                      network requests in a configured
                                      deployment

  llm-d                               Adds inference-aware routing and
                                      serving coordination across
                                      eligible model-server endpoints

  Endpoint Picker (EPP)               Helps select a model-serving
                                      endpoint based on the routing
                                      configuration and available signals

  InferencePool                       Defines the pool of eligible
                                      inference-serving endpoints in the
                                      relevant architecture
  -----------------------------------------------------------------------

A conventional load balancer distributes requests using its configured
routing rules. Inference-aware routing can use LLM-serving
signals---depending on the deployment---to make more informed endpoint
choices.

The conceptual request path is:

``` text
Application / client
        |
        v
Gateway / Envoy + llm-d routing
        |
        v
Eligible model-serving endpoint
        |
        v
vLLM
        |
        v
Model inference
        |
        v
Response to the client
```

Kubernetes provides the infrastructure on which the components run; it
does not itself generate model tokens. vLLM serves the model; it does
not replace Kubernetes. llm-d adds routing and coordination
capabilities; it does not automatically guarantee faster inference.

A single-replica or CPU-based demonstration can show how components
connect and how a request travels through the system. It does **not**,
by itself, demonstrate production-scale performance, multi-replica
scaling, or throughput gains.

------------------------------------------------------------------------

## 10. Suggested hands-on learning path

You do not need to learn all the concepts at once. Try these in order:

### Step 1 --- Understand the network request

-   Learn the difference between a hostname, IP address, port, HTTP, and
    HTTPS.
-   Use `curl` against a public API you are authorized to access.
-   Inspect the HTTP status code, headers, and JSON response.
-   Learn why `localhost` refers to the machine or network namespace
    where the command is running.

### Step 2 --- Understand the remote machine

-   Learn what a VM and a container are.
-   Connect to a remote environment using the provider's documented
    access method.
-   Learn what SSH does.
-   Run `nvidia-smi` in a GPU-enabled environment and inspect the
    output.

### Step 3 --- Understand model serving

-   Follow the accompanying vLLM runbook to inspect the running service.
-   Send a chat-completion request.
-   Change the prompt and generation limit.
-   Compare a request made from inside the server environment with one
    made through the public endpoint.

### Step 4 --- Understand GPU memory and generation

-   Learn what model weights and tokens are.
-   Draw the prefill and decode stages.
-   Explain in your own words what the KV cache stores and why it
    consumes memory.
-   Learn how PagedAttention organizes cache blocks.
-   Distinguish latency from throughput.

### Step 5 --- Explore serving architecture

-   Learn the purpose of a Kubernetes Pod and Service.
-   Trace a request from a client through a proxy to a model server.
-   Understand the different roles of Kubernetes, vLLM, Envoy, and
    llm-d.
-   Only then explore multi-replica deployments, routing policies,
    metrics, and performance tests.

------------------------------------------------------------------------

## 11. Glossary

  -----------------------------------------------------------------------
  Term                                In one sentence
  ----------------------------------- -----------------------------------
  Inference                           Using a trained model to produce a
                                      prediction or response

  Model weights                       Learned numerical parameters used
                                      by the model

  Inference engine                    Software that executes and serves a
                                      model

  API                                 A defined interface through which
                                      software communicates

  HTTP                                A protocol for exchanging requests
                                      and responses

  DNS                                 A system that resolves domain names
                                      to records used to locate services

  Port                                A numbered service endpoint used by
                                      network communication

  SSH                                 An encrypted protocol for remote
                                      terminal access

  GPU                                 A processor suited to many parallel
                                      computations

  VRAM                                Memory available to the GPU

  CUDA                                NVIDIA's platform and programming
                                      model for GPU computation

  Token                               A unit of text representation
                                      processed or generated by a
                                      language model

  Prefill                             Processing the input prompt before
                                      token-by-token generation

  Decode                              Generating subsequent output tokens

  KV cache                            Stored attention keys and values
                                      reused during generation

  PagedAttention                      vLLM's block-based approach to
                                      managing KV-cache memory

  Continuous batching                 Scheduling requests dynamically as
                                      active sequences progress or finish

  Latency                             How long an operation or request
                                      takes

  Throughput                          How much work is completed per unit
                                      of time

  Kubernetes                          A system for orchestrating
                                      containerized workloads

  Envoy                               A proxy commonly used to receive
                                      and forward service traffic

  llm-d                               An inference-serving architecture
                                      focused on inference-aware routing
                                      and coordination
  -----------------------------------------------------------------------

------------------------------------------------------------------------

## 12. References and next steps

Use the following primary resources to continue learning:

-   [RunPod documentation](https://docs.runpod.io/) --- GPU
    environments, endpoints, and access.
-   [vLLM documentation](https://docs.vllm.ai/) --- serving
    configuration, APIs, performance, and supported features.
-   [vLLM: PagedAttention blog
    post](https://vllm.ai/blog/2023-06-20-vllm) --- the motivation
    behind block-based KV-cache management.
-   [Original PagedAttention
    paper](https://doi.org/10.1145/3600006.3613165) --- technical
    details and evaluation of the approach.
-   [NVIDIA CUDA Programming
    Guide](https://docs.nvidia.com/cuda/cuda-programming-guide/) ---
    CUDA concepts and GPU programming.
-   [NVIDIA `nvidia-smi`
    documentation](https://docs.nvidia.com/deploy/nvidia-smi/index.html)
    --- GPU monitoring output and metrics.
-   [Kubernetes concepts](https://kubernetes.io/docs/concepts/) ---
    Pods, Services, scheduling, and workloads.
-   [llm-d documentation](https://llm-d.ai/) --- inference-aware routing
    and distributed inference serving.

### Continue to the live-demo runbook

Once these concepts are familiar, follow the [vLLM Qwen3-8B Live Demo Runbook](vllm-qwen3-8b-runbook.md) for the actual commands, endpoint checks, GPU inspection, and chat-completion request.

To explore inference-aware routing on Kubernetes, continue to the [llm-d CPU Demo: vLLM, Envoy and the Endpoint Picker](llm-d-cpu-routing-demo.md).

The purpose of this guide is to explain *what the components mean and
how they fit together*. The runbook is where you follow the concrete
commands.

------------------------------------------------------------------------

## Final mental model

A model is not the whole application. The model needs compute to run, an
inference engine to execute it, an API to expose it, and a network path
for applications to reach it. During LLM generation, the KV cache reuses
attention state but consumes GPU memory; techniques such as
PagedAttention and continuous batching help manage serving resources.
When deployments grow beyond one model server, orchestration and
inference-aware routing become additional parts of the system.
