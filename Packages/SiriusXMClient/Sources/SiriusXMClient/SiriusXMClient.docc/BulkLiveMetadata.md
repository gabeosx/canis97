# Bulk live metadata

Request metadata for many entitled catalog identities through one fixed operation.

## Request and replace

Call ``SiriusXMClient/liveNow(for:)`` with an array of ``LiveChannelID`` values
from the current entitled catalog, in the desired display order. The client
checks current session entitlement before and after the operation and sends
one authenticated metadata request for the entire array. It does not perform
a tune, fetch artwork, prefetch audio, or authorize playback. Caller-supplied
identities are a metadata filter, never evidence of channel playback entitlement.

```swift
let result = await client.liveNow(for: catalog.channels.map(\.id))
switch result {
case let .current(snapshot):
    // Replace the previous snapshot in full, including unavailable channels.
    display(snapshot)
case let .failed(failure):
    displayFailure(failure)
}
```

``LiveNowSnapshot/channels`` contains exactly one result per input identity,
in input order, including repeated identities. An empty array still performs
the single authorized operation and returns an empty snapshot on success.
Unrequested channels are discarded. Catalog coverage is broader than the
metadata feed: the reviewed observation advertised 737 catalog entries but
returned 527 metadata entries. Missing channels are therefore explicitly
``LiveNowChannelState/unavailable``, not a snapshot failure. These counts are
historical observations, not required counts or a current coverage guarantee.

Every successful response is a complete replacement. Missing values must not
be filled with values from an older snapshot. Equatable semantic models permit
local comparisons; compare channel states when checking content changes,
because the snapshot observation time changes with every response.

## Time and current content

``LiveNowSnapshot/observedAt`` is the local response observation time. It is
explicitly **not server time**. No authoritative provider clock is established
at this layer, and no opaque provider marker is interpreted as time or as a
patch token. Incorrect local clock settings can affect current-item selection.

The adapter examines every item and chooses the greatest valid start time
not later than observation time. It admits ordinary and fractional ISO-8601
timestamps and ignores eligible-order differences between arrays. Exact
semantic duplicates collapse. Conflicting candidates at the winning timestamp
make that channel ``LiveNowChannelState/unsupported``. Malformed items are
contained to their channel, including malformed historical or future entries:
the decoder cannot safely establish their ordering and meaning.

``LiveNowContentKind/item`` makes no promise that content is a music track.
Artist/host text is optional. When there is no eligible item, a nonempty show
name with a valid eligible start time can supply ``LiveNowContentKind/show``.
A valid item always takes precedence over a show; malformed items cannot be
hidden by show fallback. No end time or duration is inferred.

## Lifecycle and closed failures

Use one client for the application session. Concurrent calls covered by its
active batch share one request and one response observation time. Each caller
still receives its own full snapshot in its own requested order. Reordered IDs,
subsets, and repeated IDs can join the active batch without another request.
Start shared demand with the full entitled catalog when multiple features need
different subsets of that catalog.

Demand outside the active batch's coverage supersedes that batch. It cancels
the old operation and returns a closed superseded failure to its consumers;
late old responses cannot replace newer results. A catalog refresh, reauthentication, sign-out, or
confirmed access loss prevents old results from publishing. A cancelled
consumer promptly receives ``LiveNowFailure/cancelled`` without cancelling
other consumers of the same request. When its last consumer leaves, the
underlying request is cancelled. Cancellation and supersession remain closed
even if the transport responds late.

The selected-channel
``SiriusXMClient/metadata(for:)`` operation uses the same strict selection
policy and retains its existing artwork behavior. That legacy artwork-bearing
operation supersedes a pending batch; it does not join its metadata-only result.
Features using bulk metadata should share ``SiriusXMClient/liveNow(for:)``.

The client retains no completed metadata cache and starts no polling, retry,
or background loop. A call after completion initiates a new explicit refresh.
In-flight coalescing does not deduplicate independent loops that run at different
times.

## Shared scheduling and freshness

For features that need ongoing updates, explicitly create one ``LiveNowMonitor``
per application session. This main-actor observable owner retains semantic data
only. It begins work only after the app supplies a nonempty entitled catalog and
active demand; it does not tune or acquire playback authority.

```swift
let monitor = LiveNowMonitor { ids in
    await client.liveNow(for: ids)
}
monitor.setDemand(channelIDs: catalog.channels.map(\.id), active: libraryIsVisible || isActivelyPlaying)
// All features read monitor.snapshot instead of starting separate loops.
// At sign-out or session replacement:
monitor.reset()
```

Successful refreshes replace the full snapshot and schedule the next request
60 seconds after completion. Network, rate-limit, and supersession failures
retain the last snapshot as stale and back off for 120, 240, then at most
300 seconds. Authentication, entitlement, protected-control, malformed-response,
and cancellation failures clear the snapshot and stop automatic refresh.
An explicit ``LiveNowMonitor/refresh()`` can retry after a 60-second cooldown.
Manual refresh never bypasses an in-flight request or its cooldown.

Visibility and catalog changes cancel old demand without resetting the request
budget. A catalog identity change clears the snapshot. Late completions cannot
publish, and a replacement waits for the previous refresh closure to finish
even if that closure ignores cancellation. Client consumer cancellation can
settle before a cancelled transport finishes internally; generation checks
continue to reject that transport’s late result. Call ``LiveNowMonitor/reset()`` on session end to clear
semantic state and reset the budget. The app must stop demand when its catalog
is stale or entitlement is no longer current.

``LiveNowMonitor/freshness(at:)`` reports current observations younger than
90 seconds, stale observations from 90 seconds to under five minutes (or after
a recoverable failure), and unavailable observations at five minutes or older.
Future observation times also report unavailable. Views should hide expired
program text and fall back to channel identity. These are local display-age
limits, not provider program end times.

SiriusXM's private protocol is volatile. Malformed root responses, unsupported
transport shapes, authentication/entitlement loss, and protected controls fail
closed with ``LiveNowFailure``. Per-channel unavailable or unsupported states
never grant playback authorization. Raw provider responses, markers, image
keys, credentials, headers, and media resources are absent from these models.
