# Search Open Finder Windows — Alfred Workflow

![Logo](icon.png)

**Lightning-fast Finder window management at your fingertips.** Search, navigate, and manage all your open Finder windows without ever touching your mouse.
![Focus Window](resources/media/preview.png)

## ✨ Features

- 🚀 **Finds windows instantly** — Even with dozens open
- 🔍 **Searches everything** — Window names, paths, even the files inside
- 🎨 **Shows the right icons** — Including your custom ones
- 🔄 **Updates in real-time** — Close a window, and the list updates immediately
- 🧠 **Remembers your setup** — Smart caching for fast load times

## 🎮 Usage

### Actions

* **Enter** — Focus the selected window
* **⌘ Enter** — Copy a file or folder's path to clipboard
* **⌥ Enter** — Close the selected window from within Alfred

### Search Like a Pro

Find windows by typing:
- **Window names** — "Downloads", "Documents", etc.
- **Full and partial paths** — "~/Desktop/that one video.mp4"
- **Files and folders inside** — That PDF you're looking for? **Just type its name.**
- **Path components** — "screenshot desktop 2025 .png" finds ~/Desktop/Screenshot 2025-05-26 at 6.43.54 PM.png

## 🪟 Supported Window Types

### 📁 Finder Browser Windows
Your everyday folder windows — the workflow handles them all with icons that match your system appearance and custom settings.

### ℹ️ "Get Info" Windows
Quickly find and focus any "Get Info" window. Press ⌘ to copy the path of the file or folder being inspected.

### ⚙️ Settings Window
Jump straight to Finder Settings when you need to tweak something.

### 📐 "View Options" Windows
Those "Show View Options" panels? They're searchable, too!

## 🌎 Real-World Examples

### Jump between folders
![Focus Window](resources/media/focus-window.gif)

### Grab paths without breaking your flow
![Copy Directory Path](resources/media/copy-directory-path.gif)

### Clean up your workspace instantly
![Close Window](resources/media/close-window.gif)

## 🏆 Why you'll love it

- **Zero setup** — Just install and go

- **Blazing fast** — Optimized to handle any number of windows

- **Smart caching** — *Learns your setup* for instant results

- **Specific icons for easy identification** — Respects **custom icons**, **dark mode**, **hidden files**, and macOS' **stock icons** for every window type

- **Dynamically shows/hides hidden items** depending on Finder's current setting

- **Keyboard-first** — Everything is just a few keystrokes away

## 🔗 Where to get it

You can download the latest release of this window from the [**Releases page**](https://github.com/dbacks2196/alfred-search-open-finder-windows/releases/latest), or from the [**Alfred Gallery**](https://alfred.app/workflows/davidb/search-open-finder-windows/).

**This workflow uses the [Homebrew](https://brew.sh) version of `jq`.** I recommend installing it directly from the [**Alfred Gallery**](https://alfred.app/workflows/davidb/search-open-finder-windows/), which will automatically manage Homebrew dependencies.

## 🙏 Acknowledgements

This workflow was inspired by the **[Browser Tabs](https://alfred.app/workflows/epilande/browser-tabs/)** workflow by [**Emmanuel Pilande**](https://github.com/epilande).

Special thanks to [**mklement**](https://github.com/mklement0), whose [**fileicon**](https://github.com/mklement0/fileicon) script taught me about macOS' icon resource forks.

Thank you also to [**Vitor Galvão**](https://github.com/vitorgalvao?tab=repositories&q=alfred&type=&language=&sort=) from [**Alfred**](https://github.com/alfredapp) for for helping me to refine this workflow.