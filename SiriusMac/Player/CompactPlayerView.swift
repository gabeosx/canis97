import AppKit
import AVFoundation
import SwiftUI

struct CompactPlayerView: View {
    let presentation: CompactPlayerPresentation
    let appearance: ValidatedSkinAppearance
    let favoriteSongActionState: FavoriteCurrentSongActionState
    let onAction: @MainActor (CompactPlayerAction) -> Void
    let isAlwaysOnTop: Bool
    let onAlwaysOnTopChanged: @MainActor (Bool) -> Void
    let onAppearanceRecovery: @MainActor () -> Void
    let audioRoutingPlayer: AVPlayer?
    let animationBudgetState: AnimatedSkinBudgetState
    let animationReduceMotionOverride: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsNativeAppearanceRecoveryStatus = false
    @State private var marqueeCycleOrigin = Date.now
    @State private var marqueeIsVisible = false
    @State private var showsAudioOutputSelector = false
    @State private var animatedSkinEvent: AnimatedSkinEventTrigger?
    @State private var animatedSkinEventSequence: UInt64 = 0

    // Resolve each decoration once per input snapshot, outside all animation ticks.
    private let renderingAppearance: ValidatedSkinAppearance
    private let decorationImages: [URL: NSImage]
    private var style: CompactSkinStyle { renderingAppearance.style }
    /// A finite, geometry-derived contract for the approved Quartz Link
    /// receiver. It avoids identifier-specific behavior while letting native
    /// controls use the optical centers of this exact validated faceplate.
    private var usesQuartzReceiverGeometry: Bool {
        renderingAppearance.layoutPlan.usesQuartzReceiverGeometry
    }
    private var needsNativeAppearanceRecovery: Bool {
        appearance.reference != .native && renderingAppearance.reference == .native
    }
    /// A schema-v3 backdrop is already a complete, validated faceplate. Keeping
    /// it outside the silhouette mask preserves its authored outer edge while
    /// all interactive content remains in the fixed semantic-slot registry.
    private var hasExpressiveFaceplate: Bool {
        !renderingAppearance.layoutPlan.isLegacy && !renderingAppearance.decorationAssetURLs.isEmpty
    }
    private var presentationScale: CGFloat {
        renderingAppearance.layoutPlan.presentationScale
    }
    private var semanticPresentationScale: CGFloat {
        renderingAppearance.layoutPlan.isLegacy ? 1 : presentationScale
    }

    init(
        presentation: CompactPlayerPresentation,
        appearance: ValidatedSkinAppearance = .native,
        favoriteSongActionState: FavoriteCurrentSongActionState = .disabled(.noConfirmedPlayback),
        onAction: @escaping @MainActor (CompactPlayerAction) -> Void,
        isAlwaysOnTop: Bool = false,
        onAlwaysOnTopChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        onAppearanceRecovery: @escaping @MainActor () -> Void = {},
        audioRoutingPlayer: AVPlayer? = nil,
        animationBudgetState: AnimatedSkinBudgetState = .withinBudget,
        animationReduceMotionOverride: Bool? = nil
    ) {
        self.presentation = presentation
        self.appearance = appearance
        var images: [URL: NSImage] = [:]
        self.renderingAppearance = appearance.renderableAppearance { url in
            if images[url] != nil { return true }
            guard let image = NSImage(contentsOf: url) else { return false }
            images[url] = image
            return true
        }
        self.decorationImages = images
        self.favoriteSongActionState = favoriteSongActionState
        self.onAction = onAction
        self.isAlwaysOnTop = isAlwaysOnTop
        self.onAlwaysOnTopChanged = onAlwaysOnTopChanged
        self.onAppearanceRecovery = onAppearanceRecovery
        self.audioRoutingPlayer = audioRoutingPlayer
        self.animationBudgetState = animationBudgetState
        self.animationReduceMotionOverride = animationReduceMotionOverride
    }

    private var playerCanvas: some View {
        Group {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    decorativeImage(at: renderingAppearance.backgroundAssetURL)
                    expressiveFaceplateLayer
                    if !hasExpressiveFaceplate {
                        appOwnedDecorativeSurfaces
                    }
                    AnimatedSkinHost(
                        motion: renderingAppearance.motion,
                        state: animatedSkinState,
                        event: animatedSkinEvent,
                        isSongFavorite: favoriteSongActionState.isFavorite,
                        isChannelFavorite: presentation.isFavorite,
                        reduceMotion: effectiveReduceMotion,
                        budgetState: animationBudgetState
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .frame(
                    width: renderingAppearance.layoutPlan.contentSize.width,
                    height: renderingAppearance.layoutPlan.contentSize.height,
                    alignment: .topLeading
                )
                .scaleEffect(presentationScale, anchor: .topLeading)
                .frame(
                    width: renderingAppearance.layoutPlan.presentationSize.width,
                    height: renderingAppearance.layoutPlan.presentationSize.height,
                    alignment: .topLeading
                )
                if renderingAppearance.layoutPlan.isLegacy {
                    VStack(alignment: .leading, spacing: style.sectionSpacing) {
                        if let channel = presentation.channelIdentity {
                            populatedContent(channel, at: Date.now)
                        } else {
                            emptyContent(at: Date.now)
                        }
                    }
                    .padding(style.padding)
                } else {
                    expressiveContent(at: Date.now)
                }
            }
        }
    }

    private var decoratedPlayer: some View {
        playerCanvas
        .frame(
            width: renderingAppearance.layoutPlan.presentationSize.width,
            height: renderingAppearance.layoutPlan.presentationSize.height,
            alignment: .topLeading
        )
        .background {
            ZStack {
                if !usesQuartzReceiverGeometry {
                    surfaceBackground(.canvas)
                }
                Color.clear
                    .contentShape(.rect)
                    .gesture(WindowDragGesture())
                    .allowsWindowActivationEvents(true)
                    .accessibilityHidden(true)
            }
        }
        .tint(surfaceTint(.interactiveAccent))
        .mask {
            if usesQuartzReceiverGeometry {
                // Quartz supplies its own RGBA silhouette, including the gap
                // between units. An inset rounded mask would crop the receiver.
                Rectangle()
            } else if hasExpressiveFaceplate {
                RoundedRectangle(cornerRadius: presentationFaceplateCornerRadius, style: .continuous)
                    .padding(presentationFaceplateInset)
            } else {
                CompactSkinSilhouetteShape(
                    variant: renderingAppearance.layoutPlan.silhouette,
                    cornerRadius: renderingAppearance.cornerRadius
                )
            }
        }
        .environment(\.colorScheme, contentColorScheme)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(ProductIdentity.displayName) compact player")
        .accessibilityIdentifier("compact.canvas")
        .id(renderingAppearance.reference)
        .transition(.opacity)
        .animation(effectiveReduceMotion ? nil : .easeInOut(duration: 0.15), value: renderingAppearance.reference)
    }

    var body: some View {
        decoratedPlayer
        .background(CompactPlayerVisibilityProbe { marqueeIsVisible = $0 })
        .onChange(of: needsNativeAppearanceRecovery, initial: true) { _, needsRecovery in
            guard needsRecovery else { return }
            showsNativeAppearanceRecoveryStatus = true
            onAppearanceRecovery()
        }
        .onChange(of: appearance.reference) { _, reference in
            marqueeCycleOrigin = .now
            animatedSkinEvent = nil
            guard reference != .native, !needsNativeAppearanceRecovery else { return }
            showsNativeAppearanceRecoveryStatus = false
        }
        .onChange(of: marqueeContentIdentity) { _, _ in
            marqueeCycleOrigin = .now
        }
        .onChange(of: presentation.channelIdentity) { oldValue, newValue in
            guard oldValue != nil, newValue != nil, oldValue != newValue else { return }
            emitAnimatedSkinEvent(.channelChanged)
        }
        .onChange(of: presentation.isFavorite) { oldValue, newValue in
            guard presentation.channelIdentity != nil, oldValue != newValue else { return }
            emitAnimatedSkinEvent(newValue ? .channelFavoriteAdded : .channelFavoriteRemoved)
        }
        .onChange(of: favoriteSongActionState.isFavorite) { oldValue, newValue in
            guard favoriteSongActionState.isEnabled, oldValue != newValue else { return }
            emitAnimatedSkinEvent(newValue ? .songFavoriteAdded : .songFavoriteRemoved)
        }
        .onChange(of: presentation.status) { oldValue, newValue in
            guard oldValue?.isAnimatedSkinFailure == true, newValue == .playing else { return }
            emitAnimatedSkinEvent(.recovered)
        }
    }

    private var marqueeContentIdentity: String {
        [
            presentation.channelIdentity?.displayText,
            presentation.primaryMetadata,
            presentation.secondaryMetadata,
            presentation.emptyBody,
        ]
        .compactMap { $0 }
        .joined(separator: "\u{1F}")
    }

    private var effectiveReduceMotion: Bool {
        animationReduceMotionOverride ?? reduceMotion
    }

    private var animatedSkinState: SkinMotionState {
        switch presentation.status {
        case .pending: .loading
        case .playing: .playing
        case .paused: .paused
        case .unavailable: .error
        case .stopped, .none: .idle
        }
    }

    private func emitAnimatedSkinEvent(_ event: SkinMotionEvent) {
        animatedSkinEventSequence &+= 1
        animatedSkinEvent = AnimatedSkinEventTrigger(event: event, sequence: animatedSkinEventSequence)
    }

    /// Generated faceplates already draw their own device silhouette. This
    /// shallow, inset mask removes only the opaque source-image corners while
    /// preserving the authored bezel, glow, and every semantic control well.
    private var expressiveFaceplateCornerRadius: CGFloat {
        switch renderingAppearance.layoutPlan.silhouette {
        case .discPod: 30
        case .bubbleCapsule: 28
        case .wideCinema: 18
        default: renderingAppearance.cornerRadius
        }
    }

    private var presentationFaceplateCornerRadius: CGFloat {
        expressiveFaceplateCornerRadius * presentationScale
    }

    private var presentationFaceplateInset: CGFloat {
        4 * presentationScale
    }

    private var contentColorScheme: ColorScheme {
        switch style.foregroundColorScheme {
        case .light: .light
        case .dark: .dark
        }
    }

    /// The semantic registry is fixed in this source order. Schema-v3 supplies
    /// only prevalidated frames; it never creates a control or carries action,
    /// help, accessibility, keyboard, or playback authority.
    private func expressiveContent(at marqueeDate: Date) -> some View {
        let plan = renderingAppearance.layoutPlan
        return ZStack(alignment: .topLeading) {
            if !hasExpressiveFaceplate {
                expressiveMaterialLayer
            }
            expressiveSlot(.artwork) {
                expressiveArtwork
            }
            expressiveSlot(.channelIdentity) {
                let channelText = presentation.channelIdentity?.displayText ?? "Nothing Playing"
                BoundedMarqueeText(
                    channelText,
                    font: skinFont(plan.typography.display, size: 18, weight: .semibold),
                    timestamp: marqueeDate,
                    cycleOrigin: marqueeCycleOrigin,
                    motionScale: semanticPresentationScale,
                    reduceMotionOverride: effectiveReduceMotion,
                    animates: marqueeIsVisible
                )
                    .padding(.horizontal, semanticMetric(8))
                    .padding(.vertical, semanticMetric(2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .clipped()
                    .help(channelText)
                    .accessibilityLabel("Channel \(channelText)")
                    .accessibilityValue(channelText)
            }
            expressiveSlot(.metadata) { expressiveMetadata(at: marqueeDate) }
            expressiveSlot(.favorite) {
                channelFavoriteButton
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .offset(y: semanticMetric(usesQuartzReceiverGeometry ? 4 : 0))
            }
            expressiveSlot(.status) { statusAndRecovery(at: marqueeDate) }
            expressiveSlot(.transport) { transport }
            expressiveSlot(.library) { libraryButton }
            expressiveSlot(.overflowMenu) { overflowMenu }
        }
        // Offset semantic slots do not enlarge a ZStack's layout bounds.
        // Size this container before attaching the foreground drag surface so
        // artwork outside the controls' intrinsic bounds still receives input.
        .frame(width: plan.presentationSize.width, height: plan.presentationSize.height, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            ForEach(Array(plan.dragRegions.enumerated()), id: \.offset) { _, drag in
                // A fully clear layer is omitted from native hit testing in
                // this transparent window. This subpixel alpha is visually
                // imperceptible but keeps the validated drag region tangible.
                CompactWindowDragRegion()
                    .background(Color.white.opacity(0.001))
                    .frame(width: semanticMetric(CGFloat(drag.width)), height: semanticMetric(CGFloat(drag.height)))
                    .allowsHitTesting(true)
                    .accessibilityHidden(true)
                    .offset(x: semanticMetric(CGFloat(drag.x)), y: semanticMetric(CGFloat(drag.y)))
            }
        }
    }

    private func expressiveSlot<Content: View>(
        _ slot: CompactSkinSemanticSlot,
        @ViewBuilder content: () -> Content
    ) -> some View {
        guard let frame = renderingAppearance.layoutPlan.slotFrames[slot] else { return AnyView(EmptyView()) }
        return AnyView(
            content()
                .frame(
                    width: semanticMetric(CGFloat(frame.width)),
                    height: semanticMetric(CGFloat(frame.height)),
                    alignment: expressiveSlotAlignment(slot)
                )
                .offset(
                    x: semanticMetric(CGFloat(frame.x)),
                    y: semanticMetric(CGFloat(frame.y))
                )
        )
    }

    private func expressiveSlotAlignment(_ slot: CompactSkinSemanticSlot) -> Alignment {
        switch slot {
        case .channelIdentity, .metadata: .topLeading
        case .artwork, .favorite, .status, .transport, .library, .overflowMenu: .center
        }
    }

    private func skinFont(_ token: CompactSkinTypographyToken, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let renderedSize = semanticMetric(size)
        return switch token {
        case .systemDefault: Font.system(size: renderedSize, weight: weight)
        case .systemRounded: Font.system(size: renderedSize, weight: weight, design: .rounded)
        case .systemMonospaced: Font.system(size: renderedSize, weight: weight, design: .monospaced)
        }
    }

    private func semanticMetric(_ value: CGFloat) -> CGFloat {
        value * semanticPresentationScale
    }

    @ViewBuilder
    private func expressiveMetadata(at marqueeDate: Date) -> some View {
        if usesQuartzReceiverGeometry {
            quartzReceiverMetadata(at: marqueeDate)
        } else {
            metadata(at: marqueeDate)
        }
    }

    /// Quartz Link has one physical song LCD and a separate heart well. The
    /// real title/artist values share one bounded marquee inside the glass;
    /// the native heart keeps its own 24-point hit target at the measured
    /// painted center, relative to the metadata slot, at (140,21).
    private func quartzReceiverMetadata(at marqueeDate: Date) -> some View {
        ZStack(alignment: .topLeading) {
            if let songText = quartzReceiverSongText {
                BoundedMarqueeText(
                    songText,
                    font: skinFont(renderingAppearance.layoutPlan.typography.body, size: 13, weight: .semibold),
                    timestamp: marqueeDate,
                    cycleOrigin: marqueeCycleOrigin,
                    motionScale: semanticPresentationScale,
                    reduceMotionOverride: effectiveReduceMotion,
                    animates: marqueeIsVisible
                )
                .frame(width: semanticMetric(104), height: semanticMetric(17))
                .position(x: semanticMetric(60), y: semanticMetric(18))
                .help(songText)
                .accessibilityLabel("Current song: \(songText)")
                .accessibilityValue(songText)
                .accessibilitySortPriority(55)
            }

            songFavoriteButton
                .position(x: semanticMetric(140), y: semanticMetric(21))
        }
        .frame(width: semanticMetric(156), height: semanticMetric(40), alignment: .topLeading)
        .clipped()
    }

    private var quartzReceiverSongText: String? {
        let values = [presentation.primaryMetadata, presentation.secondaryMetadata]
            .compactMap { value in
                value?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values.joined(separator: " — ")
    }

    @ViewBuilder
    private func populatedContent(_ channel: CompactPlayerPresentation.ChannelIdentity, at marqueeDate: Date) -> some View {
        ZStack {
            decorativeImage(at: renderingAppearance.metadataPanelAssetURL)
            HStack(alignment: .top, spacing: 8) {
                artwork
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(channel.displayText)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .help(channel.displayText)
                            .accessibilityLabel("Channel \(channel.displayText)")
                        Spacer(minLength: 4)
                        channelFavoriteButton
                    }
                    metadata(at: marqueeDate)
                }
            }
            .padding(4)
        }
        .background(surfaceBackground(.metadata))
        .clipShape(.rect(cornerRadius: renderingAppearance.cornerRadius))
        statusAndRecovery(at: marqueeDate)
        transport
        footer
    }

    @ViewBuilder
    private var artworkImage: some View {
        switch presentation.artwork {
        case let .data(artwork):
            NativeArtworkImage(artwork: artwork)
        case .placeholder, .none:
            Image(systemName: "music.note")
                .resizable()
                .scaledToFit()
                .padding(semanticMetric(20))
                .foregroundStyle(.secondary)
        }
    }

    private var artworkAccessibilityLabel: String {
        presentation.primaryMetadata.map { "Artwork for \($0)" }
            ?? presentation.channelIdentity.map { "Artwork for channel \($0.displayText)" }
            ?? "Artwork"
    }

    private var artwork: some View {
        artworkImage
            .frame(width: 72, height: 72)
            .background(surfaceBackground(.metadata).opacity(hasExpressiveFaceplate ? 0 : 1))
            .clipShape(.rect(cornerRadius: renderingAppearance.cornerRadius))
            .accessibilityLabel(artworkAccessibilityLabel)
            .accessibilitySortPriority(60)
            .padding(CompactPlayerPresentation.focusClearance)
    }

    /// Expressive artwork is bounded by its validated semantic slot. The
    /// legacy 72-point artwork view includes focus padding and must not be
    /// dropped into a 48-point faceplate well, where it visibly spills into
    /// adjacent metadata.
    private var expressiveArtwork: some View {
        Group {
            artworkImage
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(surfaceBackground(.metadata).opacity(hasExpressiveFaceplate ? 0 : 1))
        .clipShape(.rect(cornerRadius: renderingAppearance.cornerRadius * semanticPresentationScale))
        .accessibilityLabel(artworkAccessibilityLabel)
        .accessibilitySortPriority(60)
    }

    private var channelFavoriteButton: some View {
        Button(action: { onAction(.toggleFavorite) }) {
            if hasExpressiveFaceplate {
                FaceplateGlyphView(glyph: .favorite, isFilled: presentation.isFavorite)
                    .frame(width: semanticMetric(15), height: semanticMetric(15))
                    .frame(width: semanticMetric(CompactPlayerPresentation.transportControlSize), height: semanticMetric(CompactPlayerPresentation.transportControlSize))
                    .contentShape(.rect)
            } else {
                Image(systemName: presentation.isFavorite ? "star.fill" : "star")
                    .frame(width: CompactPlayerPresentation.transportControlSize, height: CompactPlayerPresentation.transportControlSize)
                    .contentShape(.rect)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(presentation.isFavorite ? Color(hex: style.accentHex) : .secondary)
        .help(presentation.isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityIdentifier("compact.favorite")
        .accessibilityLabel(presentation.isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityValue(presentation.isFavorite ? "Favorite" : "Not favorite")
        .accessibilitySortPriority(40)
        .disabled(presentation.channelIdentity == nil)
    }

    private var songFavoriteButton: some View {
        let isFavorite = favoriteSongActionState.isFavorite
        return Button(action: { onAction(.toggleSongFavorite) }) {
            if hasExpressiveFaceplate {
                FaceplateGlyphView(glyph: .songFavorite, isFilled: isFavorite)
                    .frame(width: semanticMetric(13), height: semanticMetric(13))
                    .frame(width: semanticMetric(CompactPlayerPresentation.metadataActionSize), height: semanticMetric(CompactPlayerPresentation.metadataActionSize))
                    .contentShape(.rect)
            } else {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: CompactPlayerPresentation.metadataActionSize, height: CompactPlayerPresentation.metadataActionSize)
                    .contentShape(.rect)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isFavorite ? Color(hex: style.accentHex) : .secondary)
        .help(favoriteSongActionState.title)
        .accessibilityIdentifier("compact.song-favorite")
        .accessibilityLabel(favoriteSongActionState.accessibilityLabel)
        .accessibilityValue(favoriteSongActionState.accessibilityValue)
        .accessibilityHint(favoriteSongActionState.accessibilityHint)
        .accessibilitySortPriority(53)
        .disabled(!favoriteSongActionState.isEnabled)
    }

    @ViewBuilder
    private func metadata(at marqueeDate: Date) -> some View {
        VStack(alignment: .leading, spacing: semanticMetric(2)) {
            if let primary = presentation.primaryMetadata {
                currentSongMetadataRow(primary, at: marqueeDate)
            }
            if let secondary = presentation.secondaryMetadata {
                BoundedMarqueeText(
                    secondary,
                    font: skinFont(renderingAppearance.layoutPlan.typography.body, size: 13),
                    tone: .secondary,
                    timestamp: marqueeDate,
                    cycleOrigin: marqueeCycleOrigin,
                    motionScale: semanticPresentationScale,
                    reduceMotionOverride: effectiveReduceMotion,
                    animates: marqueeIsVisible
                )
                    .frame(height: semanticMetric(16))
                    .help(secondary)
                    .accessibilityLabel("Artist: \(secondary)")
                    .accessibilityValue(secondary)
                    .accessibilitySortPriority(54)
            }
        }
        .padding(.horizontal, semanticMetric(8))
        .padding(.vertical, semanticMetric(hasExpressiveFaceplate ? 2 : 4))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func currentSongMetadataRow(_ primary: String, at marqueeDate: Date) -> some View {
        HStack(spacing: semanticMetric(4)) {
            BoundedMarqueeText(
                primary,
                font: skinFont(renderingAppearance.layoutPlan.typography.body, size: 14, weight: .semibold),
                timestamp: marqueeDate,
                cycleOrigin: marqueeCycleOrigin,
                motionScale: semanticPresentationScale,
                    reduceMotionOverride: effectiveReduceMotion,
                    animates: marqueeIsVisible
            )
            .frame(height: semanticMetric(17))
            .help(primary)
            .accessibilityLabel("Current program: \(primary)")
            .accessibilityValue(primary)
            .accessibilitySortPriority(55)

            songFavoriteButton
                .fixedSize()
        }
        .frame(height: semanticMetric(CompactPlayerPresentation.metadataActionSize))
    }

    @ViewBuilder
    private func statusAndRecovery(at marqueeDate: Date) -> some View {
        VStack(alignment: hasExpressiveFaceplate ? .center : .leading, spacing: semanticMetric(2)) {
            if let status = presentation.status {
                playbackStatus(status)
            } else if let emptyBody = presentation.emptyBody {
                if hasExpressiveFaceplate {
                    BoundedMarqueeText(
                        emptyBody,
                        font: skinFont(renderingAppearance.layoutPlan.typography.label, size: 12, weight: .medium),
                        tone: .secondary,
                        timestamp: marqueeDate,
                        cycleOrigin: marqueeCycleOrigin,
                        motionScale: semanticPresentationScale,
                    reduceMotionOverride: effectiveReduceMotion,
                    animates: marqueeIsVisible
                    )
                    .frame(height: semanticMetric(16))
                    .help(emptyBody)
                    .accessibilityLabel(emptyBody)
                    .accessibilityValue(emptyBody)
                    .accessibilityIdentifier("compact.status")
                    .accessibilitySortPriority(50)
                } else {
                    Text(emptyBody)
                        .font(skinFont(renderingAppearance.layoutPlan.typography.label, size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .help(emptyBody)
                        .accessibilityLabel(emptyBody)
                        .accessibilityValue(emptyBody)
                        .accessibilityIdentifier("compact.status")
                        .accessibilitySortPriority(50)
                }
            }
            if needsNativeAppearanceRecovery || showsNativeAppearanceRecoveryStatus {
                Text("This appearance is unavailable. Native appearance has been restored.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(surfaceBackground(.criticalState))
                    .tint(surfaceTint(.criticalState))
                    .accessibilityIdentifier("compact.appearance-recovery")
                    .accessibilityLabel("This appearance is unavailable. Native appearance has been restored.")
                    .accessibilitySortPriority(45)
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: hasExpressiveFaceplate ? .center : .leading
        )
    }

    @ViewBuilder
    private func playbackStatus(_ status: CompactPlayerPresentation.Status) -> some View {
        let surface = statusSurface(for: status)
        HStack(spacing: semanticMetric(usesQuartzReceiverGeometry ? 2 : 4)) {
            switch status {
            case .pending:
                ProgressView().controlSize(.small)
                Text(usesQuartzReceiverGeometry ? "Loading" : "Loading playback")
            case .playing:
                playbackStatusLabel("Playing", glyph: .play, systemImage: "play.fill")
            case .paused:
                playbackStatusLabel("Paused", glyph: .pause, systemImage: "pause.fill")
            case .stopped:
                playbackStatusLabel("Stopped", glyph: .stop, systemImage: "stop.fill")
            case let .unavailable(recovery):
                if hasExpressiveFaceplate {
                    Text("Error")
                    Button("Retry") { onAction(recovery.compactAction) }
                        .accessibilityLabel(recovery.title)
                } else {
                    Text("Playback couldn’t start.")
                    Button(recovery.title) { onAction(recovery.compactAction) }
                }
            }
        }
        .font(skinFont(renderingAppearance.layoutPlan.typography.label, size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .allowsTightening(true)
        .padding(.horizontal, semanticMetric(usesQuartzReceiverGeometry ? 4 : 6))
        .padding(.vertical, semanticMetric(3))
        .fixedSize(horizontal: hasExpressiveFaceplate, vertical: true)
        .multilineTextAlignment(hasExpressiveFaceplate ? .center : .leading)
        .background(surfaceBackground(surface).opacity(hasExpressiveFaceplate ? 0 : 1))
        .tint(surfaceTint(surface))
        .accessibilityValue(status.accessibilityValue)
        .accessibilityIdentifier("compact.status")
        .accessibilitySortPriority(50)
    }

    @ViewBuilder
    private func playbackStatusLabel(_ title: String, glyph: FaceplateGlyph, systemImage: String) -> some View {
        if hasExpressiveFaceplate {
            HStack(spacing: semanticMetric(4)) {
                FaceplateGlyphView(glyph: glyph)
                    .frame(width: semanticMetric(9), height: semanticMetric(9))
                Text(title)
            }
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    @ViewBuilder
    private var transport: some View {
        let availability = presentation.transport
        let playPause = availability?.playPause ?? .play
        if let centers = expressiveTransportControlCenters {
            ZStack(alignment: .topLeading) {
                transportButton("Previous", glyph: .previous, systemImage: "backward.fill", enabled: availability?.previousEnabled == true, action: .previous)
                    .position(centers[0])
                transportButton(playPause == .pause ? "Pause" : "Play Live", glyph: playPause == .pause ? .pause : .play, systemImage: playPause == .pause ? "pause.fill" : "play.fill", enabled: availability != nil, action: .playPause)
                    .position(centers[1])
                transportButton("Next", glyph: .next, systemImage: "forward.fill", enabled: availability?.nextEnabled == true, action: .next)
                    .position(centers[2])
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .tint(surfaceTint(.interactiveAccent))
        } else {
            HStack(spacing: 8) {
                transportButton("Previous", glyph: .previous, systemImage: "backward.fill", enabled: availability?.previousEnabled == true, action: .previous)
                transportButton(playPause == .pause ? "Pause" : "Play Live", glyph: playPause == .pause ? .pause : .play, systemImage: playPause == .pause ? "pause.fill" : "play.fill", enabled: availability != nil, action: .playPause)
                transportButton("Next", glyph: .next, systemImage: "forward.fill", enabled: availability?.nextEnabled == true, action: .next)
            }
            .padding(CompactPlayerPresentation.focusClearance)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(surfaceBackground(.transport))
            .tint(surfaceTint(.interactiveAccent))
        }
    }

    /// App-owned optical centers for the three physical transport wells drawn
    /// by each finite faceplate layout. The surrounding semantic slot remains
    /// the validated accessibility and focus region.
    private var expressiveTransportControlCenters: [CGPoint]? {
        switch renderingAppearance.layoutPlan.layoutVariant {
        case .discConsole:
            scaledPoints([CGPoint(x: 30, y: 23), CGPoint(x: 65, y: 23), CGPoint(x: 100, y: 23)])
        case .aquaPod:
            scaledPoints([CGPoint(x: 32, y: 34), CGPoint(x: 80, y: 34), CGPoint(x: 128, y: 34)])
        case .cinemaDeck:
            if usesQuartzReceiverGeometry {
                scaledPoints([CGPoint(x: 17, y: 21), CGPoint(x: 54, y: 21), CGPoint(x: 91, y: 21)])
            } else {
                scaledPoints([CGPoint(x: 24, y: 24), CGPoint(x: 68, y: 24), CGPoint(x: 112, y: 24)])
            }
        case .legacyStack, .desktopUtility:
            nil
        }
    }

    private func scaledPoints(_ points: [CGPoint]) -> [CGPoint] {
        points.map { CGPoint(x: semanticMetric($0.x), y: semanticMetric($0.y)) }
    }

    @ViewBuilder
    private func transportButton(_ title: String, glyph: FaceplateGlyph, systemImage: String, enabled: Bool, action: CompactPlayerAction) -> some View {
        let button = Button(action: { onAction(action) }) {
            if hasExpressiveFaceplate {
                FaceplateGlyphView(glyph: glyph)
                    .frame(width: semanticMetric(14), height: semanticMetric(14))
                    .frame(width: semanticMetric(CompactPlayerPresentation.transportControlSize), height: semanticMetric(CompactPlayerPresentation.transportControlSize))
                    .contentShape(.rect)
            } else {
                Image(systemName: systemImage)
                    .frame(width: CompactPlayerPresentation.transportControlSize, height: CompactPlayerPresentation.transportControlSize)
                    .contentShape(.rect)
            }
        }
        .disabled(!enabled)
        .help(title)
        .accessibilityIdentifier("compact.transport.\(accessibilityIdentifier(for: action))")
        .accessibilityLabel(title)
        .accessibilityValue(enabled ? "Available" : "Unavailable for the current queue")
        .accessibilityHint(enabled ? "" : "Unavailable for the current queue")
        .accessibilitySortPriority(30)

        if hasExpressiveFaceplate {
            button.buttonStyle(.plain)
                .foregroundStyle(surfaceTint(.interactiveAccent))
        } else {
            button
        }
    }

    private var footer: some View {
        HStack {
            libraryButton
            Spacer()
            overflowMenu
        }
        .font(.system(size: 12))
        .padding(4)
        .background(surfaceBackground(.footer))
        .tint(surfaceTint(.interactiveAccent))
    }

    @ViewBuilder
    private var libraryButton: some View {
        if hasExpressiveFaceplate {
            Button {
                onAction(.showLibrary)
            } label: {
                FaceplateGlyphView(glyph: .library)
                    .frame(width: semanticMetric(15), height: semanticMetric(15))
                    .frame(width: semanticMetric(CompactPlayerPresentation.transportControlSize), height: semanticMetric(CompactPlayerPresentation.transportControlSize))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .help("Show Library")
            .accessibilityIdentifier("compact.show-library")
            .accessibilityLabel("Show Library")
            .accessibilitySortPriority(20)
        } else {
            Button {
                onAction(.showLibrary)
            } label: {
                Label("Show Library", systemImage: "rectangle.stack")
            }
            .help("Show Library")
            .accessibilityIdentifier("compact.show-library")
            .accessibilityLabel("Show Library")
            .accessibilitySortPriority(20)
        }
    }

    @ViewBuilder
    private var overflowMenu: some View {
        Group {
            if hasExpressiveFaceplate {
                Menu {
                    overflowMenuActions
                } label: {
                    FaceplateGlyphView(glyph: .overflow)
                        .frame(width: semanticMetric(15), height: semanticMetric(15))
                        .frame(width: semanticMetric(CompactPlayerPresentation.transportControlSize), height: semanticMetric(CompactPlayerPresentation.transportControlSize))
                        .contentShape(.rect)
                        .accessibilityLabel("More")
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Menu {
                    overflowMenuActions
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .popover(isPresented: $showsAudioOutputSelector, arrowEdge: .trailing) {
            if let audioRoutingPlayer {
                AudioOutputSelector(player: audioRoutingPlayer)
            }
        }
    }

    @ViewBuilder
    private var overflowMenuActions: some View {
        Toggle("Always on Top", isOn: Binding(get: { isAlwaysOnTop }, set: { onAlwaysOnTopChanged($0) }))
            .accessibilityIdentifier("compact.always-on-top")
            .accessibilityLabel("Always on Top")
            .accessibilityValue(isAlwaysOnTop ? "On" : "Off")
            .accessibilitySortPriority(10)
        Divider()
        Button("Audio Output…", systemImage: "airplayaudio") {
            showsAudioOutputSelector = true
        }
        .disabled(audioRoutingPlayer == nil)
        .accessibilityIdentifier("compact.overflow.audio-output")
        .accessibilityLabel("Audio Output")
        .accessibilityHint(
            audioRoutingPlayer == nil
                ? "Audio output selection is unavailable without an active player"
                : "Choose a Bluetooth, connected, or AirPlay output"
        )
        Divider()
        Button("Use Native Appearance") { onAppearanceRecovery() }
            .accessibilityIdentifier("compact.overflow.use-native-appearance")
            .accessibilityLabel("Use Native Appearance")
            .accessibilitySortPriority(9)
        Divider()
        Button("Sign Out") { onAction(.signOut) }
            .accessibilityIdentifier("compact.sign-out")
    }

    private func accessibilityIdentifier(for action: CompactPlayerAction) -> String {
        switch action {
        case .previous: "previous"
        case .playPause: "play-pause"
        case .next: "next"
        case .toggleFavorite: "favorite"
        case .toggleSongFavorite: "song-favorite"
        case .showLibrary: "show-library"
        case .toggleAlwaysOnTop: "always-on-top"
        case .retryPlayback: "retry"
        case .signInAgain: "sign-in-again"
        case .refreshLibrary: "refresh-library"
        case .signOut: "sign-out"
        }
    }

    private func emptyContent(at marqueeDate: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text(presentation.emptyTitle ?? "Nothing Playing")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(presentation.emptyTitle ?? "Nothing Playing")
            if let emptyBody = presentation.emptyBody {
                Text(emptyBody)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .help(emptyBody)
                    .accessibilityLabel(emptyBody)
                    .accessibilityValue(emptyBody)
            }
            statusAndRecovery(at: marqueeDate)
            Button(presentation.emptyLibraryButtonTitle ?? "Show Library") { onAction(.showLibrary) }
                .accessibilityIdentifier("compact.show-library")
                .accessibilityLabel("Show Library")
                .frame(minWidth: CompactPlayerPresentation.transportControlSize, minHeight: CompactPlayerPresentation.transportControlSize)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func statusSurface(for status: CompactPlayerPresentation.Status) -> CompactSkinSurface {
        switch status {
        case .unavailable:
            .criticalState
        case .pending, .playing, .paused, .stopped:
            .status
        }
    }

    private func surfaceBackground(_ surface: CompactSkinSurface) -> some View {
        let treatment = renderingAppearance.surfaceTreatment(for: surface)
        return RoundedRectangle(cornerRadius: renderingAppearance.cornerRadius)
            .fill(Color(hex: treatment.fillHex).opacity(treatment.fillOpacity))
            .overlay {
                RoundedRectangle(cornerRadius: renderingAppearance.cornerRadius)
                    .stroke(
                        Color(hex: treatment.strokeHex).opacity(treatment.strokeOpacity),
                        lineWidth: 1
                    )
            }
    }

    private func surfaceTint(_ surface: CompactSkinSurface) -> Color {
        Color(hex: renderingAppearance.surfaceTreatment(for: surface).tintHex)
    }

    /// These treatments consume only validated colors. Their geometry, opacity,
    /// hit-testing, and accessibility behavior remain fixed and app-owned.
    private var appOwnedDecorativeSurfaces: some View {
        ZStack {
            RoundedRectangle(cornerRadius: renderingAppearance.cornerRadius)
                .stroke(surfaceTint(.chromeHighlight).opacity(0.72), lineWidth: 2)
                .padding(6)
            RoundedRectangle(cornerRadius: renderingAppearance.cornerRadius)
                .fill(surfaceTint(.displayGlow).opacity(0.24))
                .blur(radius: 18)
                .padding(20)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Decorations are validated local assets and are always inert. Faceplates
    /// deliberately sit behind, rather than replace, the app-owned controls.
    @ViewBuilder
    private var expressiveFaceplateLayer: some View {
        if hasExpressiveFaceplate {
            ZStack {
                ForEach(renderingAppearance.decorationAssetURLs, id: \.self) { url in
                    decorativeImage(at: url)
                }
            }
            .frame(width: style.contentSize.width, height: style.contentSize.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var expressiveMaterialLayer: some View {
        let silhouette = renderingAppearance.layoutPlan.silhouette
        if silhouette != .nativeRect {
            Canvas { context, size in
                switch silhouette {
                case .pixelNotched:
                    let border = Path(roundedRect: CGRect(x: 8, y: 8, width: size.width - 16, height: size.height - 16), cornerRadius: 0)
                    context.stroke(border, with: .color(surfaceTint(.chromeHighlight).opacity(0.72)), lineWidth: 2)
                    context.fill(Path(CGRect(x: 12, y: 28, width: size.width - 24, height: 8)), with: .color(surfaceTint(.displayGlow).opacity(0.38)))
                    for x in stride(from: 16, through: Int(size.width) - 16, by: 8) {
                        context.fill(Path(CGRect(x: x, y: 20, width: 2, height: 2)), with: .color(surfaceTint(.chromeHighlight).opacity(0.35)))
                    }
                case .discPod:
                    context.fill(
                        Path(roundedRect: CGRect(x: 8, y: 8, width: size.width - 16, height: size.height - 16), cornerRadius: 36),
                        with: .color(surfaceTint(.displayGlow).opacity(0.36))
                    )
                    context.stroke(
                        Path(roundedRect: CGRect(x: 12, y: 12, width: size.width - 24, height: size.height - 24), cornerRadius: 32),
                        with: .color(surfaceTint(.chromeHighlight).opacity(0.62)),
                        lineWidth: 2
                    )
                    context.fill(Path(ellipseIn: CGRect(x: 20, y: 164, width: 176, height: 92)), with: .color(surfaceTint(.metadata).opacity(0.32)))
                    for point in [CGPoint(x: 24, y: 24), CGPoint(x: size.width - 30, y: 24), CGPoint(x: 24, y: size.height - 30), CGPoint(x: size.width - 30, y: size.height - 30)] {
                        context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: 6, height: 6)), with: .color(surfaceTint(.chromeHighlight).opacity(0.72)))
                    }
                    for x in stride(from: 132, through: 300, by: 12) {
                        context.fill(Path(CGRect(x: x, y: 72, width: 6, height: 3)), with: .color(surfaceTint(.interactiveAccent).opacity(0.5)))
                    }
                case .bubbleCapsule:
                    context.fill(Path(CGRect(x: 8, y: 8, width: size.width - 16, height: size.height * 0.45)), with: .color(surfaceTint(.displayGlow).opacity(0.38)))
                    context.fill(Path(CGRect(x: 8, y: size.height * 0.5, width: size.width - 16, height: size.height * 0.42)), with: .color(surfaceTint(.metadata).opacity(0.34)))
                    context.fill(Path(roundedRect: CGRect(x: 16, y: 36, width: size.width - 32, height: 112), cornerRadius: 24), with: .color(surfaceTint(.chromeHighlight).opacity(0.18)))
                    context.stroke(Path(roundedRect: CGRect(x: 12, y: 12, width: size.width - 24, height: size.height - 24), cornerRadius: 40), with: .color(surfaceTint(.chromeHighlight).opacity(0.7)), lineWidth: 2)
                    for bubble in [CGRect(x: 32, y: 176, width: 12, height: 12), CGRect(x: 72, y: 204, width: 8, height: 8), CGRect(x: size.width - 64, y: 172, width: 16, height: 16), CGRect(x: size.width - 92, y: 204, width: 8, height: 8)] {
                        context.stroke(Path(ellipseIn: bubble), with: .color(surfaceTint(.chromeHighlight).opacity(0.58)), lineWidth: 1)
                    }
                case .wideCinema:
                    context.fill(
                        Path(roundedRect: CGRect(x: 4, y: 4, width: size.width - 8, height: size.height - 8), cornerRadius: 18),
                        with: .color(surfaceTint(.metadata).opacity(0.36))
                    )
                    context.stroke(
                        Path(roundedRect: CGRect(x: 6, y: 6, width: size.width - 12, height: size.height - 12), cornerRadius: 16),
                        with: .color(surfaceTint(.chromeHighlight).opacity(0.54)),
                        lineWidth: 1
                    )
                case .nativeRect:
                    break
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func decorativeImage(at url: URL?) -> some View {
        if let url, let image = decorationImages[url] {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Text animation follows the same visible-window policy as the native ocean.
/// Observes lifecycle changes only; no polling or foreground-app requirement.
private struct CompactPlayerVisibilityProbe: NSViewRepresentable {
    let onChange: (Bool) -> Void
    func makeNSView(context: Context) -> VisibilityView { VisibilityView(onChange: onChange) }
    func updateNSView(_ view: VisibilityView, context: Context) { view.onChange = onChange }
    static func dismantleNSView(_ view: VisibilityView, coordinator: ()) { view.stopObserving() }

    final class VisibilityView: NSView {
        var onChange: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []
        private var lastValue: Bool?
        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else { publish(false); return }
            let events: [(Notification.Name, Any?)] = [
                (NSWindow.didMiniaturizeNotification, window),
                (NSWindow.didDeminiaturizeNotification, window),
                (NSWindow.didChangeOcclusionStateNotification, window),
                (NSApplication.didHideNotification, NSApp),
                (NSApplication.didUnhideNotification, NSApp)
            ]
            observers = events.map { name, object in
                NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.refresh() }
                }
            }
            Task { @MainActor [weak self] in self?.refresh() }
        }
        func stopObserving() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }
        private func refresh() {
            guard let window else { publish(false); return }
            publish(window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible) && !NSApp.isHidden)
        }
        private func publish(_ value: Bool) {
            guard value != lastValue else { return }
            lastValue = value
            onChange(value)
        }
    }
}

/// Expressive skins use app-owned vector ink so the visible glyph centroid is
/// exactly the same point as the validated 32-point hit target. System-symbol
/// side bearings remain available to the native layout, where AppKit owns the
/// surrounding button chrome.
private enum FaceplateGlyph {
    case previous
    case play
    case pause
    case stop
    case next
    case library
    case overflow
    case favorite
    case songFavorite
}

private struct FaceplateGlyphView: View {
    let glyph: FaceplateGlyph
    var isFilled = true

    var body: some View {
        Canvas { context, size in
            let extent = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let strokeWidth = max(1, extent * 0.1)

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: center.x + x * extent, y: center.y + y * extent)
            }

            func triangle(_ points: [CGPoint]) -> Path {
                var path = Path()
                path.move(to: points[0])
                path.addLine(to: points[1])
                path.addLine(to: points[2])
                path.closeSubpath()
                return path
            }

            switch glyph {
            case .play:
                // The triangle's area centroid, rather than its bounding box,
                // sits on the control center.
                context.fill(
                    triangle([point(-0.24, -0.42), point(-0.24, 0.42), point(0.48, 0)]),
                    with: .foreground
                )
            case .previous:
                context.fill(triangle([point(0.32, -0.40), point(0.32, 0.40), point(-0.04, 0)]), with: .foreground)
                context.fill(triangle([point(-0.08, -0.40), point(-0.08, 0.40), point(-0.44, 0)]), with: .foreground)
            case .next:
                context.fill(triangle([point(-0.32, -0.40), point(-0.32, 0.40), point(0.04, 0)]), with: .foreground)
                context.fill(triangle([point(0.08, -0.40), point(0.08, 0.40), point(0.44, 0)]), with: .foreground)
            case .pause:
                context.fill(Path(roundedRect: CGRect(x: center.x - extent * 0.28, y: center.y - extent * 0.38, width: extent * 0.18, height: extent * 0.76), cornerRadius: extent * 0.05), with: .foreground)
                context.fill(Path(roundedRect: CGRect(x: center.x + extent * 0.10, y: center.y - extent * 0.38, width: extent * 0.18, height: extent * 0.76), cornerRadius: extent * 0.05), with: .foreground)
            case .stop:
                context.fill(Path(roundedRect: CGRect(x: center.x - extent * 0.31, y: center.y - extent * 0.31, width: extent * 0.62, height: extent * 0.62), cornerRadius: extent * 0.08), with: .foreground)
            case .overflow:
                for x in [-0.32, 0, 0.32] as [CGFloat] {
                    context.fill(Path(ellipseIn: CGRect(x: point(x, 0).x - extent * 0.085, y: center.y - extent * 0.085, width: extent * 0.17, height: extent * 0.17)), with: .foreground)
                }
            case .library:
                let upper = Path(roundedRect: CGRect(x: center.x - extent * 0.41, y: center.y - extent * 0.28, width: extent * 0.82, height: extent * 0.26), cornerRadius: extent * 0.07)
                let lower = Path(roundedRect: CGRect(x: center.x - extent * 0.41, y: center.y + extent * 0.02, width: extent * 0.82, height: extent * 0.26), cornerRadius: extent * 0.07)
                context.stroke(upper, with: .foreground, lineWidth: strokeWidth)
                context.stroke(lower, with: .foreground, lineWidth: strokeWidth)
            case .favorite:
                var star = Path()
                for index in 0..<10 {
                    let radius = extent * (index.isMultiple(of: 2) ? 0.46 : 0.20)
                    let angle = -CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / 5
                    let vertex = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                    if index == 0 { star.move(to: vertex) } else { star.addLine(to: vertex) }
                }
                star.closeSubpath()
                if isFilled {
                    context.fill(star, with: .foreground)
                } else {
                    context.stroke(star, with: .foreground, lineWidth: strokeWidth)
                }
            case .songFavorite:
                var heart = Path()
                heart.move(to: point(0, 0.44))
                heart.addCurve(
                    to: point(-0.44, -0.08),
                    control1: point(-0.12, 0.30),
                    control2: point(-0.44, 0.18)
                )
                heart.addCurve(
                    to: point(0, -0.22),
                    control1: point(-0.44, -0.44),
                    control2: point(-0.12, -0.48)
                )
                heart.addCurve(
                    to: point(0.44, -0.08),
                    control1: point(0.12, -0.48),
                    control2: point(0.44, -0.44)
                )
                heart.addCurve(
                    to: point(0, 0.44),
                    control1: point(0.44, 0.18),
                    control2: point(0.12, 0.30)
                )
                heart.closeSubpath()
                if isFilled {
                    context.fill(heart, with: .foreground)
                } else {
                    context.stroke(heart, with: .foreground, lineWidth: strokeWidth)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private enum MarqueeTextTone {
    case primary
    case secondary

    var color: Color {
        switch self {
        case .primary: .primary
        case .secondary: .secondary
        }
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// One app-owned overflow policy serves every bounded schema-v3 text slot.
/// Skins choose only geometry and typography; they never supply timing or code.
private struct BoundedMarqueeText: View {
    private static let gap: CGFloat = 32
    private static let speed: CGFloat = 28
    private static let leadingPause: TimeInterval = 1.15

    let text: String
    let font: Font
    let tone: MarqueeTextTone
    let timestamp: Date
    let cycleOrigin: Date
    let motionScale: CGFloat
    private let reduceMotionOverride: Bool
    private let animates: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }
    @Environment(\.displayScale) private var displayScale
    @State private var measuredTextWidth: CGFloat = 0

    init(
        _ text: String,
        font: Font,
        tone: MarqueeTextTone = .primary,
        timestamp: Date,
        cycleOrigin: Date,
        motionScale: CGFloat = 1,
        reduceMotionOverride: Bool = false,
        animates: Bool = true
    ) {
        self.text = text
        self.font = font
        self.tone = tone
        self.timestamp = timestamp
        self.cycleOrigin = cycleOrigin
        self.motionScale = motionScale
        self.reduceMotionOverride = reduceMotionOverride
        self.animates = animates
    }

    var body: some View {
        GeometryReader { proxy in
            let viewportWidth = max(0, proxy.size.width)
            let overflows = measuredTextWidth > viewportWidth + 1

            ZStack(alignment: .leading) {
                if overflows && !reduceMotion {
                    // Only overflowing text ticks. Rebuilding the entire player
                    // here repeatedly loaded images and starved the native scene.
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !animates)) { context in
                        HStack(spacing: Self.gap * motionScale) {
                            fixedText
                            fixedText.accessibilityHidden(true)
                        }
                        .compositingGroup()
                        .offset(x: marqueeOffset(textWidth: measuredTextWidth, at: context.date))
                    }
                } else if overflows {
                    Text(text)
                        .font(font)
                        .foregroundStyle(tone.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.82)
                        .allowsTightening(true)
                } else {
                    fixedText
                }

                fixedText
                    .background {
                        GeometryReader { measurement in
                            Color.clear.preference(key: MarqueeTextWidthKey.self, value: measurement.size.width)
                        }
                    }
                    .hidden()
                    .accessibilityHidden(true)
            }
            .frame(width: viewportWidth, height: proxy.size.height, alignment: .leading)
            .clipped()
        }
        .onPreferenceChange(MarqueeTextWidthKey.self) { measuredTextWidth = $0 }
    }

    private var fixedText: some View {
        Text(text)
            .font(font)
            .foregroundStyle(tone.color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
    }

    private func marqueeOffset(textWidth: CGFloat, at date: Date) -> CGFloat {
        let travelDistance = textWidth + Self.gap * motionScale
        guard travelDistance > 0 else { return 0 }
        let travelDuration = TimeInterval(travelDistance / (Self.speed * motionScale))
        let cycleDuration = Self.leadingPause + travelDuration
        let elapsed = max(0, date.timeIntervalSince(cycleOrigin)).truncatingRemainder(dividingBy: cycleDuration)
        guard elapsed > Self.leadingPause else { return 0 }
        let rawOffset = -min(travelDistance, CGFloat(elapsed - Self.leadingPause) * Self.speed * motionScale)
        let pixelScale = max(displayScale, 1)
        return (rawOffset * pixelScale).rounded() / pixelScale
    }
}

private extension CompactRecoveryAction {
    var compactAction: CompactPlayerAction {
        switch self {
        case .tryAgain: .retryPlayback
        case .signInAgain: .signInAgain
        case .refreshLibrary: .refreshLibrary
        }
    }
}

private extension CompactPlayerPresentation.Status {
    var isAnimatedSkinFailure: Bool {
        if case .unavailable = self { return true }
        return false
    }

    var accessibilityValue: String {
        switch self {
        case .pending: "Playback pending"
        case .playing: "Playing"
        case .paused: "Paused"
        case .stopped: "Stopped"
        case .unavailable: "Playback unavailable"
        }
    }
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

private struct CompactSkinSilhouetteShape: Shape {
    let variant: CompactSkinSilhouetteVariant
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        switch variant {
        case .nativeRect:
            return Path(roundedRect: rect, cornerRadius: cornerRadius)
        case .pixelNotched:
            let notch: CGFloat = 8
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + notch, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + notch))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - notch))
            path.addLine(to: CGPoint(x: rect.maxX - notch, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + notch, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - notch))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + notch))
            path.closeSubpath()
            return path
        case .discPod:
            return Path(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: min(rect.width, rect.height) / 2)
        case .bubbleCapsule:
            return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 3)
        case .wideCinema:
            return Path(roundedRect: rect, cornerRadius: 18)
        }
    }
}

#Preview("Playing") {
    CompactPlayerView(
        presentation: .confirmed(channel: .init(number: 42, name: "The Spectrum"), artwork: .placeholder, primaryMetadata: "An unusually long Unicode title — 音楽と星空のためのライブ・ラジオ・セッション", secondaryMetadata: "An unusually long artist name — कलाकार और अतिथि", playback: .playing, isFavorite: true, queueAvailability: .both),
        onAction: { _ in }
    )
}

#Preview("Nothing Playing") {
    CompactPlayerView(presentation: .empty(), onAction: { _ in })
}

#Preview("Loading") {
    CompactPlayerView(presentation: .empty(status: .pending), onAction: { _ in })
}

#Preview("Paused") {
    CompactPlayerView(
        presentation: .confirmed(channel: .init(number: 7, name: "Fallback Channel"), artwork: .placeholder, primaryMetadata: "Current program unavailable", secondaryMetadata: "7 · Fallback Channel", playback: .paused, isFavorite: false, queueAvailability: .none),
        onAction: { _ in }
    )
}

#Preview("Playback Error") {
    CompactPlayerView(presentation: .empty(status: .unavailable(.tryAgain)), onAction: { _ in })
}

/// Native drag handling for validated decorative regions. Semantic controls
/// never overlap these rectangles, and skin data cannot supply event handlers.
private struct CompactWindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) { }

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            NSApp.activate()
            window?.makeKeyAndOrderFront(nil)
            window?.performDrag(with: event)
        }
        override func accessibilityHitTest(_ point: NSPoint) -> Any? { nil }
        override func isAccessibilityElement() -> Bool { false }
    }
}
