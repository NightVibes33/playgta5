import Foundation

/// Real persisted launcher configuration. No fabricated renderer readings.
/// Values not yet consumed by a linked RAGE runtime are explicitly staged.
enum GTALaunchPreferences {
    private static let keyPrefix = "gtaios.launcher."
    private static let keys = ["vsync", "antiAliasing", "controlScheme", "controllerVibration",
                                "touchOpacity", "aimSensitivity", "musicVolume", "dialogueVolume",
                                "masterVolume", "preset"]
    static func text(_ key: String, fallback: String) -> String {
        UserDefaults.standard.string(forKey: keyPrefix + key) ?? fallback
    }
    static func setText(_ key: String, value: String) {
        UserDefaults.standard.set(value, forKey: keyPrefix + key)
        LogStore.shared.write("preferences", "Saved launcher option: " + key + "=" + value)
    }
    static func enabled(_ key: String, fallback: Bool) -> Bool {
        guard let value = UserDefaults.standard.object(forKey: keyPrefix + key) as? NSNumber
            else { return fallback }
        return value.boolValue
    }
    static func setEnabled(_ key: String, value: Bool) {
        UserDefaults.standard.set(value, forKey: keyPrefix + key)
    }
    static func fraction(_ key: String, fallback: Double) -> Double {
        guard let value = UserDefaults.standard.object(forKey: keyPrefix + key) as? NSNumber
            else { return fallback }
        return max(0, min(1, value.doubleValue))
    }
    static func setFraction(_ key: String, value: Double) {
        UserDefaults.standard.set(max(0, min(1, value)), forKey: keyPrefix + key)
    }
    static func reset() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: keyPrefix + $0) }
    }
    static func applyPreset(_ name: String) {
        // These choices are validated against EngineOptions, which is the
        // only available engine-option contract. They are NOT live GTA FPS.
        let values: [String: String]
        switch name {
        case "Low":
            values = ["scale":"0.5", "textureQuality":"0",
                      "shadowQuality":"-1", "reflectionQuality":"0",
                      "particleQuality":"0", "grassQuality":"0"]
        case "Balanced":
            values = ["scale":"0.75", "textureQuality":"1",
                      "shadowQuality":"0", "reflectionQuality":"1",
                      "particleQuality":"1", "grassQuality":"1"]
        case "High":
            values = ["scale":"1", "textureQuality":"2",
                      "shadowQuality":"1", "reflectionQuality":"2",
                      "particleQuality":"2", "grassQuality":"2"]
        default: return
        }
        for (id, value) in values { EngineOptions.set(id, value: value) }
        setText("preset", value: name)
    }
}
