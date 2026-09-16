# Native Mac integrations

Canis97 exposes its existing listening session through App Intents, Shortcuts,
Spotlight, and a desktop widget. These surfaces all return to the same app-owned
session controller. They never create another player, provider client, or polling
loop.

## Shortcuts and Siri

After Canis97 has loaded the entitled channel catalog, Shortcuts can:

- tune a selected entitled channel;
- play or pause the confirmed channel;
- stop playback;
- move to the previous or next channel in the active queue;
- open the channel Library; and
- report the confirmed channel and current semantic program metadata.

Tune can be placed in a personal automation. macOS still controls when an
automation runs, and Canis97 does not promise exact wake-from-sleep or quit-state
timing. Every tune performs the normal session and entitlement checks when the app
handles it.

## Spotlight

While signed in, Canis97 indexes the current entitled channel catalog by channel
name, number, category, and favorite status. Opening a result launches Canis97 and
routes the selected identity through the normal tune coordinator. Signing out
removes the Canis97 Spotlight domain.

The index contains app-owned semantic catalog text and an opaque channel identity.
It contains no request body, response body, URL from SiriusXM, header, cookie,
token, session identifier, playback key, artwork key, or playback authorization.

## Desktop widget

The small widget shows the last channel and program that Canis97 published. The
medium widget also shows up to three ordered favorites that open and tune through
Canis97. The favorites are projections of the existing Favorites list; the widget
does not maintain a preset bank.

WidgetKit does not keep the extension continuously active. Canis97 writes a
bounded, versioned semantic snapshot to its App Group when authenticated state
changes. The widget reads that snapshot without network access and shows when it
was updated. It schedules a refresh at the five-minute stale boundary when the
system budget permits. Signing out deletes the shared snapshot.

The widget snapshot is metadata only. It cannot authorize playback or reconstruct
a provider request. Tapping a channel launches the app, which revalidates the
current catalog identity and uses the existing authenticated tune path.

## Signing requirement

Signed builds require the `group.com.canis97.player` App Group on both
`com.canis97.player` and `com.canis97.player.widget`. The source entitlements and
release script preserve that capability for the containing app and widget
extension. The Apple Developer identifiers and provisioning configuration must be
enabled before producing a signed distribution build. The release workflow
requires separate Developer ID distribution profiles for the app and widget,
validates that each profile authorizes its exact bundle identifier and the App
Group, and embeds both profiles before signing.

The SiriusXM protocol remains private and volatile. If authentication, entitlement,
catalog, or semantic metadata is unavailable, each integration fails closed and
asks the listener to return to Canis97 rather than guessing or retaining provider
material.
