# Big Fat Fish at GPT 🐟

[简体中文](README.md) · **English**

Big Fat Fish has come to work at GPT to earn a bowl of rice. Wearing an apron with the ChatGPT logo, it is ready for its first shift as your desktop coworker.

It takes its work seriously—and keeps an eye on lunchtime. It nods when a task arrives, thinks or flips through a book while working, and proudly presents the results when it is done. Between tasks, it plays with a toy car, eats, yawns, or lets a little black bird fly overhead when boredom sets in.

**Big Fat Fish at GPT** is a native macOS desktop companion that turns task states into expressive gestures with 21 animations. It floats above ordinary windows without taking up space in your main workspace. A companion Codex plugin delivers task updates and reply summaries, while blue-outlined thought bubbles let you read messages and open a reply composer right beside the pet.

**App 0.3.1 · Plugin 0.2.1 · macOS 13+ · Verified on Apple Silicon**

![Preview of all 21 animations](docs/previews/all-actions.jpg)

## Features

- **21 animations, 132 animation frames, and one idle image**, with every action available.
- A native, transparent floating window. Drag it to move it; its position is saved automatically. Choose a height of 192, 256, 320, 384, or 512 points.
- Animations for accepting tasks, thinking, researching, waiting for input, completing work, handling corrections, and stopping.
- Slower, repeated idle animations with progressively longer intervals.
- A bell just above the right side of the head, visible only while messages remain unread.
- White thought bubbles with blue outlines, paginated messages, and graphics and text that scale with the pet.
- A matching reply composer. Double-click the pet to bring the Codex desktop app to the foreground.
- Local file communication and stdio MCP, with no network server to run.

## Build and launch

The current installation method is to build from source. You need macOS 13 or later, Python 3, and the Swift compiler included in Xcode Command Line Tools.

```sh
# Install Command Line Tools if needed
xcode-select --install

# Get the source
git clone https://github.com/Knox-zki/gpt-working-fat-fish.git
cd gpt-working-fat-fish

# Build and run the built-in state machine checks
python3 apps/dsl-pet/scripts/build.py

# Install and launch; quit an existing pet from its menu before updating
mkdir -p "$HOME/Applications"
cp -R apps/dsl-pet/dist/DSLPet.app "$HOME/Applications/"
open "$HOME/Applications/DSLPet.app"
```

The app does not require OpenCV, an image generation service, or a local language model at runtime. The build uses local ad-hoc signing and has not been notarized by Apple. This version has been verified on an Apple Silicon Mac; Intel Macs and other operating systems have not been verified.

The default canvas height is 256 points. Most frames are 512 × 512 pixels; bicycle animations use a 640 × 512 canvas. Retina rendering uses the original images. Enlarging beyond the source resolution does not add detail.

## Interacting with the pet

| Action | Behavior |
| --- | --- |
| Single-click | Play one random interaction, hold its final frame for 1 second, then return to the default pose |
| Double-click | Cancel the pending single-click interaction and bring the Codex desktop app to the foreground |
| Drag | Move the pet and save its position; reset the idle timer when idle |
| Right-click / DSL menu bar item | Resize, preview all 21 animations, read messages, pause, hide, or quit |
| Left-click a message bubble | Advance one page; click again after the last page to close it |
| Right-click a message bubble | Close the bubble |
| Click the reply icon | Open the matching composer; Return sends, Shift + Return inserts a line break |

Rapid single-clicks queue at most one additional interaction. During Chinese input method composition, Return confirms the candidate. Failed sends preserve the draft. Closing the composer also preserves it; quitting the app clears it.

## How animations follow tasks

| State | Animation and playback |
| --- | --- |
| Task received | Nod once → hold the final frame for 1 second → start thinking or researching |
| Thinking / working | Loop thinking or reading animations with a 1-second pause between cycles; mixed mode uses weighted selection and avoids consecutive repeats |
| User input needed | Loop the raised-hand question animation with a 1-second pause between cycles |
| Task completed | Present results 70% of the time, strike a proud pose 30%; hold the final frame after playback |
| Correction received | Apologize once → hold for 2 seconds → work → play the careful revision animation when done and hold its final frame |
| Stop requested | Interrupt immediately, play the stop animation, then hold its final frame; a late completion event cannot override it |
| Click interaction | Random actions such as a proud pose, spinning, peeking, eating, or having an idea; play once, hold for 1 second, then return to the default pose |
| Idle | Toy car, eating, yawning, peeking, or the black bird; longer idle periods may also trigger dozing |
| Entrance / exit | Bicycle entrance and bicycle exit |

Idle animations take **1.5 times their original duration and play 3 times**, with a 1-second pause between repetitions. The first trigger follows 60 seconds of idle time. Subsequent intervals are **120, 180, 240 seconds, and so on**, measured from the end of the previous animation group. Clicks, dragging while idle, or plugin activity events reset the timer. Idle animations do not replace a held completion or stop pose.

The next user action can be a click on the pet, opening its reply composer, or new keyboard activity while Codex is in the foreground. These actions clear a held completion or stop pose. A new task starts the acceptance sequence directly.

Idle timing follows pet and plugin activity, rather than mouse activity across every application. Keyboard detection reads only the most recent keydown time and the foreground app identifier, not what you type. Keyboard shortcuts within Codex also count as activity.

All 21 actions: proud pose, unhappy, apology, toy car, eating, yawn, idea, spin, dizzy, black bird, task acceptance, thinking, reading/research, asking a question, presenting results, careful revision, stop, doze, peek, bicycle entrance, and bicycle exit.

## Connect the Codex plugin

The plugin is in `plugins/dsl-pet`; the local marketplace configuration is in `.agents/plugins/marketplace.json`. Add this marketplace in a Codex client that supports local plugin marketplaces, install `dsl-pet`, and reload the plugin. Install the app at `~/Applications/DSLPet.app` first; the plugin resolves the control bridge relative to the current user's home directory.

The plugin exposes three MCP tools:

| Tool | Purpose |
| --- | --- |
| `dsl_pet_event` | Send task states or commands such as show, hide, and interaction |
| `dsl_pet_status` | Read the pet's current state |
| `dsl_pet_notify` | Display completion summaries, requests for input, or other notifications |

Once the user opts into pet accompaniment, the bundled Skill sends events at meaningful task transitions. **It does not automatically watch every chat or guarantee coverage of every client lifecycle event.** Existing chats without the tools need a plugin reload or a reopened conversation.

You can also use the local bridge directly:

```sh
python3 apps/dsl-pet/scripts/bridge.py status
python3 apps/dsl-pet/scripts/bridge.py request_received --kind mixed
python3 apps/dsl-pet/scripts/bridge.py needs_clarification
python3 apps/dsl-pet/scripts/bridge.py task_completed
python3 apps/dsl-pet/scripts/bridge.py correction_received
python3 apps/dsl-pet/scripts/bridge.py user_stop
python3 apps/dsl-pet/scripts/bridge.py user_activity
```

## Messages and direct reply: current scope

Notifications are summaries explicitly sent by the plugin. The pet keeps up to 20 messages in memory and clears them on restart. It does not scrape chat content or use macOS Notification Center. There is currently no voice input button.

Direct reply supports local Codex conversations only. A notification must reference a valid local conversation ID, and that conversation must have an owner in the running desktop client. When the user explicitly sends a reply, the bridge submits it to the original conversation through the client's internal IPC, retaining its model, working directory, and permissions.

This IPC is not a stable public interface, so client updates may affect compatibility. Failed sends show an error and preserve the draft. A timeout can leave delivery uncertain; check the original conversation before retrying. Local transport and UI checks have passed; the complete flow of a real model receiving a reply and continuing generation still needs verification in actual use.

## Source and assets

```text
apps/dsl-pet/
  Sources/           Swift / AppKit app and animation state machine
  assets/            Independent assets: 21 animations, idle image, timing JSON
  scripts/           Build, MCP bridge, and reply transport
plugins/dsl-pet/      Codex plugin and accompaniment Skill
.agents/plugins/     Local marketplace configuration
docs/previews/       Project images and animation previews
```

Builds read directly from `apps/dsl-pet/assets`, with no dependency on the original asset library. The apron emblem was locally replaced with a small navy ChatGPT logo on the lower-left fabric as seen by the viewer, adjusted for pose, perspective, and occlusion. Character outlines, frame dimensions, transparency, and original animation timing were preserved.

Runtime data is stored in `~/Library/Application Support/DSLPet`. Build outputs, virtual environments, development screenshots, previous app backups, and the original asset library are excluded from this repository.

## Repository synchronization

NAS Forgejo is the primary repository; GitHub is its public, one-way push mirror. In the maintainer's configured local checkout, run:

```sh
git push
```

This pushes to Forgejo and the NAS Git backup on a separate disk. Forgejo then synchronizes to GitHub when it receives a push, with an additional hourly check. A separate GitHub push is unnecessary. Other clones need their own remote and upstream configuration.

The mirror authenticates with a writable deploy key limited to this repository. It synchronizes Git branches, tags, and commits, not repository descriptions, issues, pull requests, or other platform settings. Changes made directly on GitHub do not flow back automatically; make routine changes locally and push them to Forgejo first.

## License and asset rights

**Source code is licensed under the [MIT License](LICENSE). No license is granted for the visual assets.**

The MIT license does not cover character designs, images, animations, logos, screenshots, or other visual assets. Their public display does not grant permission to use, copy, modify, redistribute, or commercially exploit them. Third-party names and marks remain the property of their respective rights holders.

**If any material infringes third-party rights, please contact me.** You can use [Issues](https://github.com/Knox-zki/gpt-working-fat-fish/issues) or the contact information on my [GitHub profile](https://github.com/Knox-zki). See [ASSET_RIGHTS.md](ASSET_RIGHTS.md) for the full bilingual statement.
