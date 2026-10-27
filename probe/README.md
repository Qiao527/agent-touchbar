# Probe

Automatically tests two things on your Mac:

1. Whether the private APIs for a global Touch Bar still work on the current macOS
2. Whether a program can light the Touch Bar up again after it dims from inactivity, and which method works

## Running

You only need the Xcode Command Line Tools (if they are missing, run `xcode-select --install` first):

```bash
cd agent-touchbar/probe
./run.sh
```

The whole run takes about 3 to 5 minutes. The terminal asks you to do two things:

- **Step 2**: When a line of text and a purple "Tap me" button appear on the Touch Bar, tap the button.
- **Step 4**: After the "do not touch the keyboard or trackpad" prompt, take your hands off completely and wait for the Touch Bar to turn off by itself. The program then tries to light it up again and measures how long it stays lit.

When it finishes, the report is saved to `agentTouchbar-probe.txt` on your Desktop. Review the report for personal information before sharing it in an issue or review. Include the tested commit, Mac model, and macOS version.

## Effects on your system

- It needs no system permissions and does not change any system settings.
- During the test the Touch Bar is turned off and back on once. On exit the program removes its test content and turns the Touch Bar back on.
- If the Touch Bar looks wrong afterwards, run `sudo pkill TouchBarServer; killall ControlStrip` in Terminal to restore it.
