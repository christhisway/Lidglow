# Lidglow privacy

Lidglow is a menu-bar app that controls your MacBook's illuminated lid logo. It's built to know as little about you as possible.

- **Microphone only if you choose it.** By default Music mode listens to your Mac's own audio output through Apple's system audio tap, and Lidglow doesn't use the microphone. If you choose **Microphone** under **Settings → Music → Listen to**, macOS asks for permission, and the microphone stays on only while Music mode is running. It turns off when you switch modes, lock your Mac, let the display sleep, or close the lid, and macOS shows its microphone indicator whenever it's on.
- **Nothing is recorded.** As audio plays or the microphone hears sound, Lidglow reduces it to a single brightness level for the logo and then discards it. No audio is recorded, stored, or saved.
- **Automatic switching reads only whether an app is playing.** If you turn on **Settings → Music → Automatically switch to Music** (off by default), Lidglow asks macOS whether your chosen music apps (or, with **All apps**, any app) have audio playing. The same check is used when **Switch back after silence** is set to **Automatically**. That's a yes or no from Core Audio, with no audio attached. The audio tap starts only once Music mode is on.
- **No network code.** Lidglow sends nothing anywhere. It has no analytics, telemetry, crash reporting, or update checks. Links in Settings open in your web browser, and Lidglow itself makes no connection.
- **Settings stay on your Mac.** Your choices (the switch, mode, brightness, and Music options) are stored in macOS preferences (`UserDefaults`) and nowhere else.
- **Local diagnostics only.** Lidglow writes a few messages to the macOS log, for example when it takes or releases control of the logo or when the audio tap or microphone input starts. They contain no audio, stay on your Mac, and are only shared if you paste them into a bug report yourself.
- **You control the permissions.** macOS asks for System Audio Recording permission only when Music mode first starts, whether you choose it or it switches on automatically, and for Microphone permission only when you choose Microphone as its source. You can revoke either at any time in **System Settings → Privacy & Security**, under **Screen & System Audio Recording** or **Microphone**.
- **Your Mac's finish.** To draw the panel's preview in the right color, Lidglow reads your MacBook's finish (for example Space Black) from the system's hardware registry. It's used only for the preview.

If Lidglow ever adds a feature that needs the network, such as an automatic updater, this statement will be updated before that feature ships.
