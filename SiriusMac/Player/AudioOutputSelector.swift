import AppKit
import AVFoundation
import AVKit
import CoreAudio
import SwiftUI

struct AudioOutputSelector: View {
    @StateObject private var model: AudioOutputSelectionModel

    init(player: AVPlayer) {
        _model = StateObject(wrappedValue: AudioOutputSelectionModel(player: player))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Audio Output", systemImage: "speaker.wave.2.fill")
                .font(.headline)

            Text("Choose a connected Mac audio device or send playback over AirPlay.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Connected Devices")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                outputButton(
                    title: "This Mac / System Output",
                    systemImage: "macbook",
                    isSelected: model.selectedDeviceUID == nil
                ) {
                    model.selectSystemOutput()
                }

                ForEach(model.devices) { device in
                    outputButton(
                        title: device.name,
                        systemImage: device.systemImage,
                        isSelected: model.selectedDeviceUID == device.id
                    ) {
                        model.select(device)
                    }
                }

                if model.devices.isEmpty {
                    Text("No additional connected audio devices")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            }

            Divider()

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AirPlay")
                        .font(.callout.weight(.medium))
                    Text("HomePod, Apple TV, and compatible speakers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                AirPlayRoutePicker(player: model.player)
                    .frame(width: 34, height: 26)
                    .help("Choose AirPlay Output")
                    .accessibilityLabel("Choose AirPlay Output")
            }

            Button("Open Sound Settings…", systemImage: "gear") {
                model.openSoundSettings()
            }
            .buttonStyle(.link)
            .accessibilityIdentifier("audio-output.open-sound-settings")
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { model.refresh() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Audio Output Selector")
    }

    private func outputButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Available")
    }
}

@MainActor
private final class AudioOutputSelectionModel: ObservableObject {
    let player: AVPlayer
    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var selectedDeviceUID: String?

    init(player: AVPlayer) {
        self.player = player
        selectedDeviceUID = player.audioOutputDeviceUniqueID
        refresh()
    }

    func refresh() {
        devices = CoreAudioOutputCatalog.connectedDevices()
        selectedDeviceUID = player.audioOutputDeviceUniqueID
    }

    func selectSystemOutput() {
        player.audioOutputDeviceUniqueID = nil
        selectedDeviceUID = nil
    }

    func select(_ device: AudioOutputDevice) {
        player.audioOutputDeviceUniqueID = device.id
        selectedDeviceUID = device.id
    }

    func openSoundSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct AirPlayRoutePicker: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.player = player
        picker.isRoutePickerButtonBordered = true
        return picker
    }

    func updateNSView(_ picker: AVRoutePickerView, context: Context) {
        if picker.player !== player {
            picker.player = player
        }
    }

    static func dismantleNSView(_ picker: AVRoutePickerView, coordinator: ()) {
        picker.player = nil
    }
}

private struct AudioOutputDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let transportType: UInt32

    var systemImage: String {
        switch transportType {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            "headphones"
        case kAudioDeviceTransportTypeBuiltIn:
            "laptopcomputer"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            "display"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt:
            "cable.connector"
        default:
            "speaker.wave.2"
        }
    }
}

private enum CoreAudioOutputCatalog {
    static func connectedDevices() -> [AudioOutputDevice] {
        allDeviceIDs()
            .filter(isAliveOutputDevice)
            .compactMap { deviceID in
                guard let uid = stringProperty(
                    deviceID,
                    selector: kAudioDevicePropertyDeviceUID
                ),
                let name = stringProperty(
                    deviceID,
                    selector: kAudioObjectPropertyName
                )
                else { return nil }

                return AudioOutputDevice(
                    id: uid,
                    name: name,
                    transportType: uint32Property(
                        deviceID,
                        selector: kAudioDevicePropertyTransportType
                    ) ?? kAudioDeviceTransportTypeUnknown
                )
            }
            .sorted { left, right in
                let leftBluetooth = isBluetooth(left.transportType)
                let rightBluetooth = isBluetooth(right.transportType)
                if leftBluetooth != rightBluetooth { return leftBluetooth }
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: count)
        let status = devices.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &dataSize,
                buffer.baseAddress!
            )
        }
        return status == noErr ? devices : []
    }

    private static func isAliveOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        guard (uint32Property(deviceID, selector: kAudioDevicePropertyDeviceIsAlive) ?? 0) != 0 else {
            return false
        }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize >= MemoryLayout<AudioBufferList>.size
        else { return false }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, storage) == noErr else {
            return false
        }

        let bufferList = storage.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(bufferList).contains { $0.mNumberChannels > 0 }
    }

    private static func stringProperty(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, pointer)
        }
        return status == noErr ? value as String? : nil
    }

    private static func uint32Property(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value)
        return status == noErr ? value : nil
    }

    private static func isBluetooth(_ transportType: UInt32) -> Bool {
        transportType == kAudioDeviceTransportTypeBluetooth
            || transportType == kAudioDeviceTransportTypeBluetoothLE
    }
}
