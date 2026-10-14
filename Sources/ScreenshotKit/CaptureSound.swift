import AudioToolbox
import Foundation

/// Plays one sound. A test gives a fake that counts the plays.
public protocol SoundPlaying {
    func play()
}

/// The sound of the macOS screenshot, from the file on this Mac (YAZ-2866).
///
/// The app does not copy the file: the sound belongs to Apple. A Mac without the file plays nothing.
public final class SystemCaptureSound: SoundPlaying {
    /// The first file that exists is used. A later macOS can move or remove one of them.
    static let paths = [
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif",
    ]

    private var soundID: SystemSoundID = 0

    /// Loads the sound now, so the first Done does not wait for the file.
    public init() {
        guard let path = SystemCaptureSound.paths.first(where: FileManager.default.fileExists(atPath:)) else { return }
        if AudioServicesCreateSystemSoundID(URL(fileURLWithPath: path) as CFURL, &soundID) != noErr {
            soundID = 0
        }
    }

    deinit {
        if soundID != 0 { AudioServicesDisposeSystemSoundID(soundID) }
    }

    /// Plays at the alert volume, on the device for sound effects. It does not wait.
    /// macOS plays nothing when "Play user interface sound effects" is off.
    public func play() {
        guard soundID != 0 else { return }
        AudioServicesPlaySystemSound(soundID)
    }
}
