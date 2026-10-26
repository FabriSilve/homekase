# Token Optimization Research

Research on reducing token usage for local LLM inference in homekase, specifically for Qwen2.5-Coder 7B via llama.cpp.

## Problem

Local models have limited context windows (32k tokens for Qwen2.5-Coder 7B). OpenCode builds large contexts with system prompts, workspace analysis, tool definitions, and conversation history. Without optimization, context fills quickly, triggering compaction and degrading quality.

## Token Optimization Landscape

| Plugin | What it reduces | Savings | Effort | Best for |
|--------|-----------------|---------|--------|----------|
| **Caveman** | Agent output tokens | ~65% | Low | Every session |
| **DCP** (Dynamic Context Pruning) | Context bloat in long sessions | 50-70% | Medium | Sessions >15 turns |
| **OpenSlimedit** | Tool description tokens (sent every API call) | 11-45% | Low | Every API call |
| **OpenToken/RTK** | Bash output tokens | 60-90% | Medium | Bash-heavy sessions |
| **Context Optimizer** | Compaction quality | 40-60% | High | Heavy ML pipeline |
| **Built-in pruning** | Old tool outputs | Variable | Trivial | Easy win |

## Detailed Analysis

### 1. Caveman Mode (~65% output token reduction)

Makes the agent talk tersely: no filler, no pleasantries, fragments OK. Technical terms exact, code unchanged.

| Level | Reduction | Use Case |
|-------|-----------|----------|
| lite | ~30% | Readable, drops filler only |
| full | ~65% | Default, good balance |
| ultra | ~75% | Maximum compression |
| wenyan | ~80% | Classical Chinese style |

**Only affects output tokens** — reasoning/thinking untouched. The brain stays big, only the mouth gets smaller.

Sources:
- https://github.com/al-bashkir/opencode-caveman
- https://github.com/JuliusBrussee/caveman
- https://docs.8labs.id/guides/opencode/caveman/

### 2. DCP (Dynamic Context Pruning) (~50-70% context reduction)

Model-driven context management. Compresses stale conversation content into high-fidelity technical summaries.

Unlike OpenCode's built-in compaction (which triggers statically at context limit), DCP lets the model decide when to compress and which messages to target.

Key features:
- Deduplication of repeated tool calls
- Purge errored tool inputs after configurable turns
- Range or message compression modes
- Nested compression (new compression includes earlier summaries)

**Best for sessions >15 turns.** On short sessions, overhead can outweigh savings.

Sources:
- https://github.com/p4r4d0xb0x/opencode-dcp
- https://github.com/ranxianglei/opencode-acp (ACP = Active Context Pruning, more aggressive variant)

### 3. OpenSlimedit (~11-45% tool description reduction)

Aggressively shortens all built-in tool descriptions. Because tool schemas are sent with every API call, compressing them saves thousands of input tokens per step — compounds across multi-step tasks.

Works by modifying descriptions of existing tools only, which avoids model confusion.

Source: https://github.com/unknown/openslimedit (referenced in Upsun blog)

### 4. OpenToken / RTK (~60-90% bash output reduction)

CLI proxy that compresses command outputs before they reach LLM context.

| Command | Standard tokens | Compressed | Savings |
|---------|----------------|------------|---------|
| `git status` | 3,000 | 600 | -80% |
| `git diff` | 10,000 | 2,500 | -75% |
| `grep/rg` | 16,000 | 3,200 | -80% |
| `cargo test` | 25,000 | 2,500 | -90% |

**Caveat**: JetBrains blog tested RTK and found measured savings were actually +7.6% MORE tokens on real agent work, not the advertised 60-90%. The issue is that RTK rewrites commands, but OpenCode's built-in tools (Read, Grep, Glob) bypass the hook entirely.

OpenToken claims to solve this with 46 compression stages and a 0-risk safety filter.

Sources:
- https://github.com/rtk-ai/rtk
- https://github.com/MrGray17/opentoken
- https://blog.jetbrains.com/ai/2026/07/rtk-claude-code-token-savings/

### 5. Context Optimizer (~40-60% compaction reduction)

Uses LLMLingua-2 ML model to compress context during compaction. Reranks relevant parts, drops duplicates, compresses rest.

Requires Python + ~3-5GB ML model download. Too heavy for most local servers.

Source: https://github.com/evermeer/context-optimizer

### 6. OpenCode Built-in Compaction

```json
{
  "compaction": {
    "auto": true,
    "prune": true,
    "reserved": 10000
  }
}
```

- `prune: true` removes old tool outputs automatically
- `reserved: 10000` leaves buffer for compaction

## Recommended Stack for Local Models

### For Qwen2.5-Coder 7B (32k context, CPU inference)

| Layer | Plugin | What it targets | Why |
|-------|--------|-----------------|-----|
| Output | Caveman (full) | Agent replies | ~65% fewer output tokens |
| Context | DCP | Stale conversation content | 50-70% context reduction |
| Tools | OpenSlimedit | Tool descriptions | 11-45% on every API call |
| Pruning | Built-in `prune: true` | Old tool outputs | Easy win |

**Skip**: RTK/OpenToken (mixed results), Context Optimizer (too heavy)

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Orchestrator (expensive model) — designs, delegates, reviews│
│   ↓  spec + task                                            │
├─────────────────────────────────────────────────────────────┤
│ Subagent (Qwen2.5-Coder 7B local)                          │
│   ├─ Caveman mode → terse output back to orchestrator       │
│   ├─ OpenSlimedit → compressed tool descriptions            │
│   └─ DCP → compressed context for long sessions            │
├─────────────────────────────────────────────────────────────┤
│ Persistent context                                          │
│   ├─ caveman-compressed CLAUDE.md / project notes           │
│   └─ Built-in pruning for old tool outputs                  │
└─────────────────────────────────────────────────────────────┘
```

## Key Insights

1. **Tool schemas compound**: OpenSlimedit saves tokens on every API call because tool descriptions are sent with every request. 11-45% savings compounds across hundreds of calls.

2. **Output vs input**: Caveman reduces output tokens (agent replies). DCP/OpenSlimedit reduce input tokens (what the model sees). Both are important.

3. **Session length matters**: DCP is most effective for long sessions (>15 turns). On short sessions, the overhead can outweigh savings.

4. **Local model constraints**: With 32k context, every token counts. A 7B model has less "brain space" than a 70B model, so efficient context usage is critical.

5. **Cache hit rates**: DCP claims ~91% cache hit rate vs traditional compression. This matters for API costs but less for local inference.

## Implementation Notes

### Plugin Location

For homekase coder service, plugins live in `${DEPLOY_DIR}/plugins/`:
```
/opt/homekase/coder/plugins/
├── caveman.ts          # Minimal caveman plugin
├── openslimedit/       # Tool description compression
└── dcp/               # Dynamic context pruning
```

### opencode.json Configuration

```json
{
  "compaction": {
    "auto": true,
    "prune": true,
    "reserved": 10000
  },
  "plugin": [
    "/opt/homekase/coder/plugins/caveman.ts",
    "/opt/homekase/coder/plugins/openslimedit",
    "/opt/homekase/coder/plugins/dcp"
  ]
}
```

### Interactive Installation

During `deploy_coder`, ask the user:

```
Token optimization plugins reduce token usage significantly.
Recommended for local models with limited context.

Install Caveman mode? (~65% output token reduction) [Y/n]
Install DCP (Dynamic Context Pruning)? (~50-70% context reduction) [Y/n]
Install OpenSlimedit? (~11-45% tool description reduction) [Y/n]
```

## References

- Caveman: https://github.com/al-bashkir/opencode-caveman
- DCP: https://github.com/p4r4d0xb0x/opencode-dcp
- ACP: https://github.com/ranxianglei/opencode-acp
- OpenSlimedit: Referenced in https://developer.upsun.com/posts/ai/opencode-token-optimization
- RTK: https://github.com/rtk-ai/rtk
- OpenToken: https://github.com/MrGray17/opentoken
- Context Optimizer: https://github.com/evermeer/context-optimizer
- JetBrains RTK analysis: https://blog.jetbrains.com/ai/2026/07/rtk-claude-code-token-savings/
