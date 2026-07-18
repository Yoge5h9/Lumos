# Claude Pro Tips & Feature Menu — Research Dump

**What this is:** A wide, deduplicated menu of candidate "tips/nudges" that Lumos could
occasionally surface as ambient notifications — e.g. an efficiency tip when the 5-hour window
is running low, a feature-discovery tip right after it resets, or a delight-tip during an idle
moment. This is a **selection menu, not a script**: pick the handful that fit Lumos's calm,
glanceable tone and turn those into short copy. Everything here is sourced; anything
promotional or time-sensitive is flagged.

**How to use it:** Each row has a notification-length **one-liner** (≤90 chars), a 1–2 sentence
explanation, a source URL, and a freshness flag:
- `STABLE` — describes a durable product feature, unlikely to change soon.
- `VERIFY-DATED` — true as researched (today is **2026-07-18**) but time-sensitive; re-check
  the date before shipping.
- `UNVERIFIED` — could not be confirmed from an official Anthropic source; do not ship as fact.

Research date: 2026-07-18. Primary sources prioritized: `docs.claude.com`, `code.claude.com`,
`platform.claude.com`, `support.claude.com`, `anthropic.com`, `claude.com`. Third-party sources
used only to corroborate or fill gaps, and marked as such.

---

## 1. Usage & efficiency — make the 5-hour / weekly limits go further

| One-liner | Explanation | Source | Flag |
|---|---|---|---|
| Your 5-hour clock starts at your first message, not on the hour. (YES) | The rolling window begins the moment you send your first prompt and expires exactly 5 hours later — send your first message strategically (e.g. right before a break) to align the reset with when you'll need capacity next. | [Usage limit best practices](https://support.claude.com/en/articles/9797557-usage-limit-best-practices), [Claude Code rate limits explained](https://sessionwatcher.com/guides/claude-code-rate-limits-explained) | STABLE |
| New chat every 15–20 messages keeps costs down. | Anthropic's own guidance: start a fresh conversation regularly instead of letting one thread grow huge; if you need continuity, ask Claude to summarize first and paste that into the new chat. | [Usage limit best practices](https://support.claude.com/en/articles/9797557-usage-limit-best-practices) | STABLE |
| `/clear` between unrelated tasks — stale context burns tokens on every reply. | Clearing resets the context window so old, irrelevant conversation doesn't get re-processed (and re-billed) on every subsequent turn. Use `/rename` first if you want to find the old session later, then `/resume`. | [Common workflows — Claude Code Docs](https://docs.claude.com/en/docs/claude-code/common-workflows) | STABLE |
| For a truly fresh problem, a new session beats `/compact`. | Claude 4.5 models are good at re-discovering state from the filesystem — for unrelated work, starting clean is often cheaper and cleaner than compacting a long, unrelated history. | [Context editing — Claude Docs](https://docs.claude.com/en/docs/build-with-claude/context-editing) | STABLE |
| `/compact` with instructions keeps the summary useful. | You can steer what `/compact` preserves, e.g. "focus on code changes and test output" — otherwise the auto-summary may drop details you still need. | [Common workflows — Claude Code Docs](https://docs.claude.com/en/docs/claude-code/common-workflows) | STABLE |
| Run `/context` to see what's actually eating your context window. | Shows a breakdown of context usage so you know what to trim before it forces an auto-compact. | [Manage costs effectively — Claude Code Docs](https://docs.claude.com/en/docs/claude-code/costs) | STABLE |
| Offload big searches to a subagent so your main thread stays small. (YES) | A subagent runs in its own context window; use one when a side task would otherwise flood your main conversation with logs, search results, or files you won't reference again. | [Create custom subagents — Claude Code Docs](https://code.claude.com/docs/en/sub-agents) | STABLE |
| Prefer CLI tools (`gh`, `aws`, `gcloud`) over MCP servers for context efficiency. | Native CLI output tends to be more compact than the equivalent MCP tool call/response, so it costs less context per operation. | [Manage costs effectively — Claude Code Docs](https://docs.claude.com/en/docs/claude-code/costs) | STABLE |
| Route routine subagent work to Haiku, save Opus for the hard stuff. | Model tiers scale in cost (~Opus 5x Haiku, ~Sonnet 3x Haiku); file search, pattern-matching and codebase exploration are Haiku-level work, freeing budget for the reasoning-heavy tasks that actually need a bigger model. | [Claude Code models — model selection guide](https://claudefa.st/blog/guide/development/higher-usage-limits) (third-party, corroborates official cost-management docs) | STABLE |
| "Opusplan": let Opus plan, Sonnet execute. | A hybrid mode gets Opus-quality architectural planning, then hands the mechanical execution to faster, cheaper Sonnet — best of both without paying Opus rates for the whole task. | [Model selection & cost guides](https://www.augmentcode.com/guides/ai-model-routing-guide) (third-party synthesis of official model docs) | STABLE |
| Batch related questions into one message instead of many small ones. | Combining related asks reduces the number of separate exchanges (and repeated context) needed to get to the same answer. | [Usage limit best practices](https://support.claude.com/en/articles/9797557-usage-limit-best-practices) | STABLE |
| Upload reference docs to a Project once — they're cached, not re-sent. | Content in Project knowledge is cached and reused; referencing it again only costs you the new/uncached portion, not the whole document again. | [Usage limit best practices](https://support.claude.com/en/articles/9797557-usage-limit-best-practices) | STABLE |
| Prompt caching can cut input cost ~90% and latency up to 85% on stable prefixes. | If your system prompt / attached context stays identical across turns, Claude can reuse the encoded representation instead of recomputing it — most effective above ~1,024 tokens of stable prefix. | [Prompt caching — Claude Platform Docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) | STABLE |
| Keep the conversation "shape" stable to get more cache hits. | Same instructions, same attached files, same general thread — changing these invalidates the cached prefix and you pay full price again. | [Prompt caching — Claude Platform Docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) | STABLE |
| Pro/Max quota is shared across Claude products in the same window. | A long web-chat session eats into the same 5-hour allowance available to Claude Code (and vice versa) — they're not separate buckets. | [Claude Code rate limits explained](https://sessionwatcher.com/guides/claude-code-rate-limits-explained) (third-party; corroborate before quoting as fact) | STABLE (source not primary — corroborate) |
| The weekly cap is a rolling 7 days from your first prompt, not a Monday reset. | Unlike the 5-hour window, the weekly ceiling tracks a rolling week from whenever you started using it — it won't reset on a fixed calendar day. | [Claude Code usage limits guide](https://www.truefoundry.com/blog/claude-code-limits-explained) (third-party synthesis; Anthropic no longer publishes exact numeric caps) | STABLE (numbers not officially published) |
| Give Claude full context upfront instead of trickling it in. | For coding, paste the whole relevant context at once; for editing, send the full text; for research, structure all the data together — fewer clarifying round-trips means fewer billed turns. | [Usage limit best practices](https://support.claude.com/en/articles/9797557-usage-limit-best-practices) | STABLE |
| Chat search (paid plans) finds old answers instead of re-asking. | Ask Claude to search your prior conversations rather than repeating information you already discussed in another thread. | [Usage limit best practices](https://support.claude.com/en/articles/9797557-usage-limit-best-practices) | STABLE |

---

## 2. Lesser-known Claude Code features

| One-liner | Explanation | Source | Flag |
|---|---|---|---|
| Plan Mode: Claude researches and drafts a plan, but can't touch a single file.(YES) | A read-only mode for exploring the codebase and proposing an approach before anything is written or run — toggle with Shift+Tab twice or `/plan`. | [How Claude Code works — Claude Code Docs](https://code.claude.com/docs/en/how-claude-code-works) | STABLE |
| Esc-Esc rewinds to any earlier checkpoint — no git required. | Claude Code snapshots your files before every edit; press Esc twice (or ask to undo) to roll back a bad turn, even after resuming a session later. | [Claude Code Rewind guide](https://wmedia.es/en/tips/rewind-changes-instantly-with-checkpoints) (third-party overview of official checkpoint/rewind behavior) | STABLE |
| Skills are reusable instruction bundles Claude loads only when needed. | A Skill is a named SKILL.md file (plus optional helper scripts) that Claude invokes when the task matches its trigger description — keeps your main system prompt lean while adding deep capability on demand. | [Understanding Claude Code's full stack](https://alexop.dev/posts/understanding-claude-code-full-stack/) (third-party; concept confirmed across official Claude Code docs) | STABLE |
| Hooks run your own shell commands, HTTP calls, or prompts at lifecycle points. | You can wire a script to fire on events like PreToolUse or PostToolUse — e.g. auto-run a linter every time Claude edits a file. | [Hooks reference — Claude Code Docs](https://code.claude.com/docs/en/hooks) | STABLE |
| MCP servers turn any tool with an integration into a Claude-usable command. | Connect an MCP server (GitHub, Slack, a database, a browser) and its capabilities — including its own slash commands — show up automatically in Claude Code. | [Connect Claude Code to tools via MCP](https://code.claude.com/docs/en/mcp) | STABLE |
| Subagents live in `.claude/agents/` and persist across sessions/projects. | Unlike ad-hoc Task-tool delegation, a defined subagent has its own name, system prompt, tool access, and model — and Claude auto-delegates to it based on its description. | [Create custom subagents — Claude Code Docs](https://code.claude.com/docs/en/sub-agents) | STABLE |
| CLAUDE.md is Claude Code's persistent project memory. | Run `/init` to bootstrap one — it captures conventions, architecture notes, and rules so you don't have to re-explain your codebase every session. | [How Claude remembers your project — Claude Code Docs](https://docs.claude.com/en/docs/claude-code/memory) | STABLE |
| A custom status line can show anything — cost, git state, context left. | The status line is just a shell script fed session JSON on stdin; it runs locally, costs no tokens, and can surface whatever data you want at a glance (this is exactly what Lumos itself hooks into). | [Customize your status line — Claude Code Docs](https://code.claude.com/docs/en/statusline) | STABLE |
| Output styles change Claude's whole approach, not just tone. | E.g. the built-in "Proactive" style makes Claude act immediately on reasonable assumptions instead of pausing for routine confirmations — it edits the system prompt itself. | [Output styles — Claude Code Docs](https://code.claude.com/docs/en/output-styles.md) | STABLE |
| `--resume` / `--continue` reopen a session with full history intact (YES). | Picks the exact prior session ID back up and appends new messages, so nothing about earlier context or checkpoints is lost. | [Claude Code tips guide](https://knightli.com/en/2026/05/08/claude-code-24-tips-plan-rewind-skills-agents/) (third-party; behavior corroborated by official docs) | STABLE |
| Background tasks let long commands run while you keep prompting. | Press Ctrl+B to move a running Bash command to the background (Ctrl+B twice inside tmux); Claude can check its output anytime and keeps responding to new requests in the meantime. | [Interactive mode — Claude Code Docs](https://code.claude.com/docs/en/interactive-mode) | STABLE |
| "ultrathink" is a real trigger word — but only inside Claude Code. | Dropping "think", "think hard", "think harder", or "ultrathink" into a Claude Code prompt scales the extended-thinking token budget up to ~32K; it does nothing in Claude.ai web chat or the raw API unless you configure thinking parameters explicitly. | [What is UltraThink — ClaudeLog](https://claudelog.com/faqs/what-is-ultrathink/) (third-party; official equivalent is the `/effort` command) | STABLE |
| `/effort` sets thinking depth for the rest of the session. | `/effort max` (or low/high) is the persistent, official way to control reasoning depth, vs. a one-off "ultrathink" nudge for a single prompt. | [Claude Code thinking triggers](https://kentgigger.com/posts/claude-code-thinking-triggers) (third-party) | STABLE |
| Official VS Code and JetBrains extensions put Claude Code inside your editor. | Native chat panel, checkpoint-based undo, @-mention file references, and (VS Code) `@browser` commands that connect to Chrome for live testing. | [JetBrains IDEs — Claude Code Docs](https://code.claude.com/docs/en/jetbrains) | STABLE |
| Claude Code detects and pairs with the Chrome extension automatically. | Build in the terminal, test in the browser — the two talk to each other, including reading console errors and network requests without you leaving the browser. | [Use Claude Code with Chrome — Claude Code Docs](https://code.claude.com/docs/en/chrome) | STABLE |

---

## 3. Products & surfaces people may not know

| One-liner | Explanation | Source | Flag |
|---|---|---|---|
| Cowork is Claude's agentic workspace for non-coding knowledge work.(YES) | Runs the same agentic architecture as Claude Code but for research, analysis, spreadsheets, and documents — you describe an outcome, step away, and come back to finished work rather than chatting turn-by-turn. | [Claude Cowork — Anthropic product page](https://www.anthropic.com/product/claude-cowork), [Get started with Claude Cowork — Help Center](https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork) | STABLE |
| Cowork now runs on desktop, web, and mobile. | Rollout to web and mobile began July 7, 2026, beta-first on Max, expanding to other plans. Tasks can keep running even if your computer goes offline. | [Get started with Claude Cowork](https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork), [TechCrunch coverage](https://techcrunch.com/2026/07/07/the-coding-agent-wars-are-spilling-into-the-rest-of-the-office-claude-cowork/) | STABLE (rollout still in progress as of research date) |
| **Cowork's 5-hour limit is doubled through Aug 5, 2026 — no action needed. (YES add use it well)** | See the dedicated section below — this is time-sensitive and only *partially* corroborated by primary sources. | See §5 below | **VERIFY-DATED** |
| Claude Desktop bundles Chat, Cowork, Code, and one-click MCP extensions. | The native macOS/Windows app supports "Desktop Extensions" (`.mcpb` files) — pre-bundled local MCP servers you install like a browser extension, no manual JSON config. | [Desktop Extensions — Anthropic Engineering](https://www.anthropic.com/engineering/desktop-extensions) | STABLE |
| Claude Desktop can read/write your local files with per-action permission. | Point it at folders and it can create, edit, and organize real files on your machine, asking for explicit permission along the way. | [Getting started with local MCP servers on Claude Desktop](https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop) | STABLE |
| Claude in Chrome is a sidebar agent that can see and click your browser.(YES) | Uses Computer Use to navigate sites, fill forms, extract data, and run multi-step workflows from natural-language instructions; it's free but needs a paid Claude plan. | [Claude for Chrome — Anthropic](https://claude.com/claude-for-chrome), [Get started — Help Center](https://support.anthropic.com/en/articles/12012173-getting-started-with-claude-for-chrome) | STABLE |
| Chrome extension blocks financial transactions and password entry by design. | Anthropic built automatic safety classifiers that stop Claude in Chrome from handling payments, transactions, or sensitive financial data even if asked. | [Get started with Claude for Chrome](https://support.anthropic.com/en/articles/12012173-getting-started-with-claude-for-chrome) | STABLE |
| You can record a browser workflow once and have Claude replay/schedule it.(YES) | Claude in Chrome supports recurring browser tasks — daily, weekly, monthly, or annually — after you demonstrate the steps once. | [Claude for Chrome features](https://www.datacamp.com/tutorial/claude-for-chrome-ai-powered-browser-assistance-automation) (third-party overview) | STABLE |
| Claude lives in Slack — DM it, panel it, or @-mention it in any thread. | Three surfaces: direct message, an assistant panel from Slack's header, and thread participation via @Claude mention; it can also search Slack itself and connected Google Workspace apps. | [Get started with Claude in Slack — Help Center](https://support.claude.com/en/articles/11506255-get-started-with-claude-in-slack) | STABLE |
| @Claude with a coding ask in Slack spins up a real Claude Code session. | Mentioning Claude with a dev task in Slack auto-detects intent and creates a Claude Code session on the web — delegate work without leaving the channel. | [Introducing Claude Tag — Anthropic](https://www.anthropic.com/news/introducing-claude-tag) | STABLE |
| Claude Code now runs on the web and mobile, not just the terminal. | Kick off coding tasks from claude.ai or the mobile app; they execute on Anthropic-managed sandboxed instances, with git access routed through a secure proxy scoped to your repos. | [Claude Code product page](https://claude.com/product/claude-code), [The New Stack coverage](https://thenewstack.io/anthropics-claude-code-comes-to-web-and-mobile/) | STABLE |
| "Remote Control" lets your phone drive a Claude Code session on your machine. (YES)| Send a task from mobile to the CLI session running on your desktop and check progress remotely. | [Claude Code Mobile guide](https://sealos.io/blog/claude-code-on-phone/) (third-party; feature name/behavior, corroborate before quoting verbatim) | STABLE (corroborate exact naming) |
| Artifacts turn a Claude reply into a live, shareable mini-app. (YES)| Code, HTML, SVG, Mermaid diagrams, React components, or long-form Markdown pop into a side panel as an interactive preview — available on every plan including Free. | [What are artifacts — Help Center](https://support.claude.com/en/articles/9487310-what-are-artifacts-and-how-do-i-use-them) | STABLE |
| Projects give Claude standing knowledge + instructions for a whole workflow. | Upload reference docs and set custom instructions once; every conversation inside that Project automatically has that context, without re-briefing Claude each time. | [Collaborate with Claude on Projects — Anthropic](https://www.anthropic.com/news/projects) | STABLE |
| The Connectors Directory is Anthropic's MCP "app store." | A catalog of MCP integrations (Verified + Community) that work across Claude.ai, Desktop, Mobile, Code, and Cowork — browse at claude.com/connectors or from Settings. | [Connectors directory — Claude.ai Docs](https://claude.com/docs/connectors/directory), [Anthropic Connectors Directory FAQ](https://support.claude.com/en/articles/11596036-anthropic-connectors-directory-faq) | STABLE |
| The Agent SDK lets developers build their own Claude Code-style agents. | Same underlying agent loop (give Claude "a computer": file access, code execution, tool use) but embedded in your own app — available for Python and TypeScript. | [Agent SDK overview — Claude Code Docs](https://code.claude.com/docs/en/agent-sdk/overview), [Building agents with the Claude Agent SDK](https://claude.com/blog/building-agents-with-the-claude-agent-sdk) | STABLE |

---

## 4. General Claude usage craft (IGNORE)

| One-liner | Explanation | Source | Flag |
|---|---|---|---|
| Be clear and direct — Claude isn't a mind-reader, spell out the goal. | Anthropic's own prompting guidance: explicit, detailed instructions consistently outperform vague ones, especially for Claude 4 models. | [Be clear, direct, and detailed — Claude Docs](https://docs.claude.com/en/docs/build-with-claude/prompt-engineering/be-clear-and-direct) | STABLE |
| Show, don't just tell — a couple of examples steer Claude's reasoning. | Multishot prompting (a few examples of the reasoning pattern you want) works especially well with extended thinking; Claude tends to mirror the demonstrated approach. | [Extended thinking tips — Claude Docs](https://docs.claude.com/en/docs/build-with-claude/prompt-engineering/extended-thinking-tips) | STABLE |
| Give Claude the "what," not the "how," for hard reasoning tasks. | High-level goals ("think carefully about edge cases") tend to beat prescriptive step-by-step instructions — Claude's own approach can exceed a hand-written procedure. | [Extended thinking tips — Claude Docs](https://docs.claude.com/en/docs/build-with-claude/prompt-engineering/extended-thinking-tips) | STABLE |
| Extended thinking has a 1,024-token floor — start small, raise only if needed. | Thinking budgets below 1,024 tokens aren't allowed; Anthropic recommends starting at the minimum and increasing only as task complexity demands. | [Extended thinking — Claude Platform Docs](https://platform.claude.com/docs/en/build-with-claude/extended-thinking) | STABLE |
| Put images before text in your prompt for best vision results. | Claude's vision pipeline performs better when image content precedes the text describing what to do with it. | [Vision — Claude Platform Docs](https://platform.claude.com/docs/en/build-with-claude/vision) | STABLE |
| Bigger, clearer images beat compressed thumbnails for vision tasks. | Aim for 1000×1000px or larger, avoid blur/pixelation, and make sure any embedded text is legible — undersized or noisy images degrade Claude's read accuracy. | [Vision — Claude Platform Docs](https://platform.claude.com/docs/en/build-with-claude/vision) | STABLE |
| Claude can't tell if an image is AI-generated — don't ask it to referee that. | Explicitly documented limitation: don't rely on Claude to detect synthetic/deepfake images. | [Vision — Claude Platform Docs](https://platform.claude.com/docs/en/build-with-claude/vision) | STABLE |
| Custom Project instructions set tone and role once, for every chat inside it. | E.g. "answer as a senior backend engineer, formal tone" — set once in Project settings rather than repeated per message. | [Claude Projects & custom instructions](https://www.anthropic.com/news/projects) | STABLE |
| Ask Claude not to restate its thinking if you want a clean final answer. | Extended thinking output can leak into the visible reply; an explicit instruction to only output the answer keeps responses tidy. | [Extended thinking tips — Claude Docs](https://docs.claude.com/en/docs/build-with-claude/prompt-engineering/extended-thinking-tips) | STABLE |

---

## 5. Time-sensitive / needs verification

### Cowork "double usage" promotion — **VERIFY-DATED**

**Claim:** Claude Cowork's 5-hour usage limit is doubled for Pro, Max, Team, and legacy
seat-based Enterprise plans, running from roughly **June 5, 2026 through August 5, 2026 (11:59
PM PT)**, applied automatically with no action needed. It affects **only** the Cowork 5-hour
limit — not the weekly cap, not Claude.ai chat, not Claude Code, and not Free or
consumption-based Enterprise seats.

**Verification status:** I could **not** locate a primary Anthropic blog post, changelog entry,
or in-product banner text confirming this directly (the official Cowork help-center article at
[support.claude.com/en/articles/13345190](https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork)
describes Cowork's features and rollout but does **not** mention any usage-limit promotion). The
claim is, however, **consistently corroborated across many independent tech-press outlets**
researched on 2026-07-18, including:
- [The New Stack — "Why Anthropic just doubled Claude Cowork limits at no charge"](https://thenewstack.io/anthropic-claude-cowork-promotion/)
- [TestingCatalog — "Anthropic brings Claude Cowork to web and mobile for Max users"](https://www.testingcatalog.com/anthropic-brings-claude-cowork-to-web-and-mobile-for-max-users/)
- [Let's Data Science — "Anthropic Doubles Claude Cowork Usage Limits"](https://letsdatascience.com/news/anthropic-doubles-claude-cowork-usage-limits-db601c73)
- [KuCoin News (flash) — "Anthropic Doubles Claude Cowork Usage Limits for Paid Users"](https://www.kucoin.com/news/flash/anthropic-doubles-claude-cowork-usage-limits-for-paid-users)
- [9to5Mac — "Anthropic expanding Claude Cowork to mobile and web"](https://9to5mac.com/2026/07/13/anthropic-expanding-claude-cowork-to-mobile-and-web-details-here/)
- [TechCrunch — "Claude Cowork expands to mobile and web"](https://techcrunch.com/2026/07/07/the-coding-agent-wars-are-spilling-into-the-rest-of-the-office-claude-cowork/)

**Recommendation:** Treat the *existence* of a Cowork usage promo as highly likely (independent
convergence across many outlets, all citing the same June 5 → Aug 5 window and same plan
carve-outs), but **do not ship the exact end date in Lumos copy without a final check against
an Anthropic-owned page** — since today is **2026-07-18**, the promo has ~2.5 weeks left as
researched, and it's exactly the kind of detail that goes stale fast. If Lumos ever surfaces
this as a nudge, phrase it softly ("Cowork usage may be running a limited-time boost — check
claude.ai for current details") rather than asserting the specific date range as fact.

### Other dated/rollout items to re-check before shipping copy

| Item | What's dated about it | Flag |
|---|---|---|
| Cowork on web/mobile | Described as "beta," "rolling out over the next several weeks" as of the July 7, 2026 announcement — may be fully GA'd or changed by the time this ships. | VERIFY-DATED |
| Numeric 5-hour / weekly caps by plan tier | Anthropic has reportedly stopped publishing fixed prompts-per-window and hours-per-week numbers, describing only relative multipliers (Max 5x, Max 20x) vs. Pro baseline — treat any specific number ("45 prompts," "900 prompts") as third-party estimate, not official. | UNVERIFIED (numbers) |
| "Remote Control" feature name for mobile→desktop Claude Code control | Feature/behavior described consistently by third parties but the exact official name wasn't confirmed on a primary Anthropic page during this research pass. | STABLE (behavior) / VERIFY (name) |
