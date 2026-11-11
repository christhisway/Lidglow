# Lidglow privacy

Lidglow is a menu-bar app that controls your MacBook's illuminated lid logo. It's built to know as little about you as possible.

- **No microphone.** Lidglow never uses the microphone. Music mode listens to your Mac's own audio output through Apple's system audio tap.
- **Nothing is recorded.** As audio plays, Lidglow reduces it to a single brightness level for the logo and then discards it. No audio is recorded, stored, or saved.
- **No network code.** Lidglow sends nothing anywhere. It has no analytics, telemetry, crash reporting, or update checks. Links in Settings open in your web browser, and Lidglow itself makes no connection.
- **Settings stay on your Mac.** Your choices (the switch, mode, brightness, and Music options) are stored in macOS preferences (`UserDefaults`) and nowhere else.
- **Local diagnostics only.** Lidglow writes a few messages to the macOS log, for example when it takes or releases control of the logo or when the audio tap starts. They contain no audio, stay on your Mac, and are only shared if you paste them into a bug report yourself.
- **You control the permission.** macOS asks for System Audio Recording permission only when you choose Music. You can revoke it at any time in **System Settings → Privacy & Security → Screen & System Audio Recording**.
- **Your Mac's finish.** To draw the panel's preview in the right color, Lidglow reads your MacBook's finish (for example Space Black) from the system's hardware registry. It's used only for the preview.

If Lidglow ever adds a feature that needs the network, such as an automatic updater, this statement will be updated before that feature ships.
