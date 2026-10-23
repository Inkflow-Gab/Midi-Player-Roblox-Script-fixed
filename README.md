
# Midi-Player-Roblox-Script-fixed

Roblox MIDI sheet player (based on [saucekid's MidiPlayer](https://github.com/saucekid/MidiPlayer)) with **mobile / touch support**, a **configurable MIDI folder**, and a set of **new player features** (branding, playlist chaining, time display, minimize, optional playback throttle).

---

## What's included in this version

### New features (this update)
- **Branding on the GUI header**: `MIDI - IMPROVISED BY GAB` is drawn at the top of the window (change it with `Title` in the config).
- **Elapsed / total time**: the time label now shows `0:12 / 3:45` next to the progress bar.
- **Previous / next song buttons** (`‹` / `›`) in a playlist row above the song search.
- **AUTO / SHFL / RPT playlist toggles** in the same row:
  - `AUTO` (on by default): when a song ends and pauses, the **next song starts playing automatically**.
  - `SHFL`: auto-next picks a **random other song** instead of the next one in line.
  - `RPT`: when a song ends it **replays from the start**.
  - Your choices persist between runs in `getgenv().MidiPlayerPlaylist`.
- **Minimize button** (`–`, top-right of the window): hides the whole player and shows a small floating **`M` bubble** you can drag anywhere and tap to bring the player back — great on phones when the window covers your game view.
- **Optional notes-per-second throttle**: set `Options.MaxNotesPerSecond` (e.g. `25`) to postpone presses on very dense MIDIs so weak phones don't choke. `nil` = unlimited (default).

### Mobile / touch support
- Every button, song entry and scrubber now works with **touch** (taps + finger drags), not just mouse.
- The window **auto-scales and auto-centers** on phones/tablets, and re-fits after screen rotation. It stops recentering once you drag the window yourself.
- Playback keys are sent with a `VirtualInputManager` -> `keypress`/`keyrelease` fallback chain, so it still works on stripped-down mobile executors.

### MIDI folder support (your workspace path)
Songs are scanned from these folders (in priority order):

1. `/storage/emulated/0/Delta/Workspace/MIDI`  *(the Delta executor MIDI workspace)*
2. `midi` *(relative to the executor's local files, created automatically)*

- Subfolders are scanned too (up to 3 levels deep), duplicates removed.
- Both `.mid` and `.midi` files are recognized.
- Every absolute Android path (or Windows path) works — paths are split correctly on both `/` and `\`.
- The song list refreshes automatically every second and sorts alphabetically.

To use different folders **without editing any code**, put this above the main script:

```lua
getgenv().MidiPlayerConfig = {
    Folders = { "D:/my/sheet/format/midis", "midi" }, -- string or table of strings

    Title = "MIDI - IMPROVISED BY GAB",               -- header text (nil = default)

    Options = {
        DisableMobileScale = false,     -- true = keep the GUI at its original size on phones
        MaxNotesPerSecond = nil,        -- e.g. 25 to throttle dense MIDIs on weak phones
    },
}
```

### Performance & fixes
- MIDI playback now walks each track with a **cursor** instead of rescanning every event every frame — long MIDI files (like Animenz arrangements) no longer lag.
- Song list shows proper names for Android-style paths (previously showed the full path).
- Search filter no longer leaves songs invisible after clearing the search box.
- Songs are properly highlighted when selected; the elapsed time label is formatted as `M:SS / M:SS`.
- Scrubbers read their size at interaction time (correct after UI scaling changes).
- Stripped out debug `print` spam.

---

## Steps

### Quick Install (Loadstring)
Skip the manual setup entirely — paste this one-liner into your executor (Delta on Android works fine):

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Inkflow-Gab/Midi-Player-Roblox-Script-fixed/main/Main.lua", true))()
```

It automatically downloads the latest release of this repository when no local `MidiPlayer` folder is present.

### Step 1: Setup the Workspace
1. Download the folder named **"MidiPlayer"** from this repository.
2. Place the **"MidiPlayer"** folder directly into the `Workspace` (or your executor's local files folder).

### Step 2: Run the Script
1. Open the script file **Main.lua** from the repository.
2. Copy the script code into your Roblox script executor (Delta on Android works fine).
3. Run the script. The program initializes the MIDI player and sets up the GUI.

### Step 3: Add MIDI Files
Drop your `.mid` files into either:

- `/storage/emulated/0/Delta/Workspace/MIDI/` (recommended on Android/Delta), or
- the `midi` folder the player creates in your executor's file space.

The list updates automatically — no restart needed.

---

## Notes
- **Original Script:** This project is based on [saucekid's MidiPlayer](https://github.com/saucekid/MidiPlayer). This version adds the fixes and mobile features listed above.
- Ensure your executor supports loading assets into `CoreGui` (Delta does). If CoreGui is blocked, the GUI falls back to `PlayerGui`.
- The hand toggle buttons only mute left/right-hand *preview and playback keys* according to the track layout (track 2 = right hand, track 3 = left hand, same as the original).
