// Default config written to ~/.config/agentTouchbar/config.yaml on first launch.
// config/config.example.yaml must match it (enforced by a unit test).
public enum DefaultConfig {
    public static let yaml = #"""
        # agentTouchbar config
        # Changes apply on save, no restart needed. If you break it, the app keeps the last working config and shows the error in the menu bar.
        version: 1

        theme:
          accent: "#7C5CFF"     # accent color: #RRGGBB or red / orange / green / blue / purple …
          font_size: 13
          density: comfortable  # compact / comfortable
          animations: true

        touchbar:
          mode: full            # full: whole strip; app_region: left side only, keeping the system brightness and volume buttons
          wake_on_alert: true   # wake the Touch Bar for new alerts if it is dimmed

        # Default widgets for the three zones. Use a widget type name or an id defined under widgets below
        layout:
          left: [esc]
          island: [next_event, now_playing, pomodoro]
          right: [weather, clock, battery, volume]

        # Scenes are matched top to bottom; the first match wins. Zones a scene leaves out fall back to layout.
        # Conditions: app (frontmost app name or bundle id), mic_in_use, playing, time ("22:00-06:00"),
        #             weekdays (1=Mon…7=Sun), on_battery, in_meeting. With match: any, one condition is enough
        scenes:
          - name: Meeting
            when:
              app: [腾讯会议, TencentMeeting, 飞书, Feishu, Lark, zoom.us, us.zoom.xos, Microsoft Teams]
              in_meeting: true
              match: any
            island: [meeting]
            right: [clock, volume]

          - name: Coding
            when:
              app: [Terminal, 终端, iTerm2, Warp, Ghostty, Code, Visual Studio Code, Cursor, Xcode, Codex, Claude]
            island: [agents, git_branch, dev]

          - name: Browser
            when:
              app: [Google Chrome, Safari, Arc, Microsoft Edge]
            island: [video, browser, ai]

          - name: Night
            when:
              time: "23:00-06:00"
            hide: [weather]

        # Alerts: higher priority shows first; ttl is seconds until auto-dismiss (omit to keep); sticky must be handled manually
        alerts:
          agent_permission:  { priority: 100, sticky: true }
          verification_code: { priority: 90, ttl: 120 }
          meeting_soon:      { priority: 80, ttl: 600 }
          agent_done:        { priority: 60, ttl: 30 }
          pomodoro:          { priority: 55, sticky: true }
          battery_low:       { priority: 50, ttl: 60 }
          reminder:          { priority: 40, ttl: 60 }
          download_done:     { priority: 30, ttl: 15 }

        agents:
          permission_on_touchbar: true   # allow or deny Claude Code / Codex permission requests on the Touch Bar
          permission_wait: 30            # seconds to wait for a tap; after that the terminal asks as usual

        verification_codes:
          enabled: true                  # requires Full Disk Access
          clear_clipboard_after: 120
          extra_keywords: []

        clipboard:
          enabled: true
          max_items: 20
          show: 4

        calendar:
          enabled: true                  # requires Calendar access
          lead_minutes: 5

        downloads:
          enabled: true
          path: ~/Downloads

        battery:
          low_threshold: 20

        ai:
          base_url: https://api.openai.com/v1   # any OpenAI-compatible service works, e.g. DeepSeek or a local Ollama
          model: gpt-4o-mini
          api_key_env: OPENAI_API_KEY           # or run `atb set-key` to store it in the Keychain
          prompts:
            - { title: Translate, prompt: "If the text below is in English, translate it into Simplified Chinese; otherwise translate it into English. Output only the translation." }
            - { title: Polish, prompt: "Polish the text below. Keep its meaning and language. Output only the result." }
            - { title: Explain, prompt: "Explain the content below in plain language, in 80 words or fewer." }

        server:
          port: 47800

        # Custom widgets. id is referenced from layout and scenes; type is the widget type; other keys are widget options
        widgets:
          - id: clock
            type: clock
            zones: [Asia/Shanghai]       # add more, e.g. America/Los_Angeles; multiple zones rotate
            format: "HH:mm"

          - id: weather
            type: weather
            latitude: 31.23              # defaults to Shanghai; set your own city
            longitude: 121.47

          - id: pomodoro
            type: pomodoro
            focus_minutes: 25
            rest_minutes: 5
            water_every: 60              # remind to drink water every 60 minutes; 0 disables
            stand_every: 50              # remind to stand up every 50 minutes; 0 disables

          - id: dev
            type: buttons
            items:
              - { title: Test, icon: "sf:checkmark.seal", run: "cd ~ && echo replace with your test command" }
              - { title: Clipboard, icon: "sf:doc.on.clipboard", widget: clipboard }
              - { title: Snippets, icon: "sf:text.badge.star", widget: snippets }

          - id: snippets
            type: snippets
            items:
              - { title: Email, text: "me@example.com" }
              - { title: Phone, text: "13800000000" }
              # Keep sensitive text in the Keychain: run `atb set-secret bank-card`, then
              # - { title: Bank card, keychain: bank-card, masked: true }

          - id: system
            type: system
            items: [dark_mode, dnd, screenshot, lock, audio_output]
            dnd_shortcut: "Toggle Focus"   # name of a Shortcuts shortcut that toggles Do Not Disturb

          - id: meeting
            type: meeting
            # Per-app shortcuts; adjust to your settings. Format: cmd+shift+a
            keys:
              zoom.us:  { mute: "cmd+shift+a", camera: "cmd+shift+v", leave: "cmd+w" }
              腾讯会议: { mute: "cmd+shift+a", camera: "cmd+shift+v", leave: "cmd+w" }
              飞书:     { mute: "cmd+shift+d", camera: "cmd+shift+v", leave: "cmd+w" }

          - id: video
            type: video
            skip_seconds: 85             # seconds to jump for "skip intro"

          # Script widget example: the script prints one line of JSON or plain text
          # - id: btc
          #   type: script
          #   command: "~/bin/btc-price.sh"
          #   interval: 60
        """#
}
