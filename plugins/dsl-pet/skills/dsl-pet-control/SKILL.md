---
name: dsl-pet-control
description: Control the user's local DeepSeek Lite floating desktop companion during an opted-in Codex task, or inspect, show, hide and interact with it. Applies to the DSL desktop pet, not ChatGPT Pets sprite management.
---

# DSL desktop companion

Use the bundled `dsl_pet_event`, `dsl_pet_status`, and `dsl_pet_notify` MCP tools. If this user has opted into DSL accompaniment in this chat, send events at meaningful transitions. Otherwise activate accompaniment only when requested. The player's rules choose the animation; do not emit events every tool call or animation frame.

- New task: `request_received` with kind `thinking`, `research`, or `mixed`. The player handles the one-second terminal pause before work.
- Research starts: `tool_search`. Reasoning/work: `thinking`. Do not call either after completion or stop merely to keep the pet busy.
- Awaiting user information or approval: `needs_clarification`.
- Successful completion: `task_completed` immediately before the final response.
- User corrects the work: `correction_received`; then work normally and finish with `task_completed`. The player handles apology, two-second pause, and the final revise animation.
- User explicitly stops the task: `user_stop`. Do not resume work without a new user action.
- User has started a new interaction: `user_activity` can clear a terminal hold. A submitted new task should use `request_received` directly.
- Show/hide: `show` / `hide`; exit: `exit`. Click-style interaction: `interaction`.
- `preview` with an existing action key is for explicit animation preview, not a task status.

The app uses only last-keydown timing while GPT is frontmost to clear completed/stopped poses. It cannot read composer text, identify a specific input field, or observe lifecycle events in other chats. These are explicit tool signals, not a global listener. Do not claim automatic input detection or guaranteed lifecycle coverage. A tool failure must not block the user's main task. Read status when checking the connection, rather than repeatedly retrying events.

## Reply bubbles and notifications

For an opted-in chat, send `dsl_pet_notify` after the lifecycle event when the task completes or needs user input. Provide a concise Chinese title, a faithful 1–3 sentence summary, and `notice_kind` (`completed`, `input`, `blocked`, or `info`). For input, show the actual question and choices where useful. Completion summaries must distinguish verified results and remaining limitations. Avoid routine progress popups or every-tool notifications.

Supply `thread_id` only when the current local Codex chat's technical UUID is known from trusted task context or the desktop thread tools. Never guess or associate an unrelated chat. If unknown, omit it: the bubble still displays but Direct reply is disabled. This version supports local Codex conversation links only; do not label a ChatGPT cloud chat as a local Codex chat. Use a stable `notice_id`, such as `<thread-id>:<turn-id>:completed`, when those IDs are known, to update rather than duplicate a notification. Do not invent a turn ID. The app retains at most 20 notices in memory; restarting clears them.

Publish only user-facing summaries, never hidden reasoning, credentials, or raw logs. The notify tool sends text to the user's local desktop companion; it does not send a message to another chat or contact. Showing/closing a notification does not advance or interrupt animation. Voice remains in native Mini. Notifications appear in the pet's own controls and bubble, not macOS Notification Center.

If the tools are not yet available in this conversation after installation, report that client/plugin reload is needed. Do not claim that every chat is automatically monitored. During local development, the installed Resources/bridge.py offers equivalent CLI commands; use structured arguments for text and inspect acknowledgments.

App 0.3.0 has a pet-side reply composer. Its reply arrow opens an input bubble and explicit user Send uses the existing local desktop thread owner. Missing owner or transport errors preserve the draft and report failure; do not claim delivery merely because the composer opened. The private desktop IPC may change across app updates. The app does not autonomously send messages or poll other chats.
