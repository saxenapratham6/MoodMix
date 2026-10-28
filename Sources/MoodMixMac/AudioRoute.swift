#if os(macOS)
import CoreAudio
import Foundation

/// Whether sound is going to headphones (AirPods and other Bluetooth audio, or the headphone jack).
enum AudioRoute {
    static var headphonesConnected: Bool {
        guard let device = defaultOutputDevice else { return false }
        if transportType(of: device) == kAudioDeviceTransportTypeBluetooth
            || transportType(of: device) == kAudioDeviceTransportTypeBluetoothLE {
            return true
        }
        // The built-in output reports a "headphones" data source when something is plugged into the jack.
        return dataSource(of: device) == fourCC("hdpn")
    }

    private static var defaultOutputDevice: AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private static func transportType(of device: AudioDeviceID) -> UInt32? {
        uint32Property(kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal, of: device)
    }

    private static func dataSource(of device: AudioDeviceID) -> UInt32? {
        uint32Property(kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput, of: device)
    }

    private static func uint32Property(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope,
                                       of device: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func fourCC(_ code: String) -> UInt32 {
        code.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }
}

#endif
