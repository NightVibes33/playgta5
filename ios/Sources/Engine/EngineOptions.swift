import Foundation

/// Every launch option below corresponds to an actual query string or
/// engine argument consumed by homepage.html from the existing browser port.
/// Deliberately excludes controls the engine does not currently expose.
enum EngineOptions {
    struct Option {
        let id: String
        let title: String
        let subtitle: String
        let choices: [(String, String)]
        let defaultValue: String
    }
    struct Section {
        let title: String
        let subtitle: String
        let options: [Option]
    }

    static let sections: [Section] = [
        Section(title: "GAME", subtitle: "Actual loading-screen choices and Story Mode startup", options: [
            Option(id: "mode", title: "Start mode", subtitle: "Original LOADINGSCREEN_STARTUP startMode",
                   choices: [("Story Mode", "story"), ("Sandbox · Los Santos", "sandbox5"), ("Sandbox · env_test", "sandbox6")], defaultValue: "story"),
            Option(id: "newgame", title: "Story progression", subtitle: "Continue latest save or -noautoload",
                   choices: [("Continue save", "0"), ("New game / Prologue", "1")], defaultValue: "0")
        ]),
        Section(title: "DISPLAY & RENDERER", subtitle: "Supported homepage.html video controls", options: [
            Option(id: "fps", title: "Frame limit", subtitle: "-frameLimit (VSync divisor, not guaranteed FPS)",
                   choices: [("30 FPS", "30"), ("60 FPS", "60"), ("Uncapped · debug", "0")], defaultValue: "30"),
            Option(id: "scale", title: "Render scale", subtitle: "WebGPU render resolution relative to display",
                   choices: [("50%", "0.5"), ("65%", "0.65"), ("75%", "0.75"), ("85%", "0.85"), ("100%", "1")], defaultValue: "0.65"),
            Option(id: "textureQuality", title: "Texture quality", subtitle: "Engine -textureQuality; larger values are experimental",
                   choices: [("Low · 0", "0"), ("1 · test", "1"), ("2 · test", "2")], defaultValue: "0"),
            Option(id: "shadowQuality", title: "Shadows", subtitle: "Engine -shadowQuality; -1 disables cascades",
                   choices: [("Off", "-1"), ("Low · 0", "0"), ("1 · test", "1")], defaultValue: "-1"),
            Option(id: "reflectionQuality", title: "Reflections", subtitle: "Engine -reflectionQuality",
                   choices: [("Low · 0", "0"), ("1 · test", "1"), ("2 · test", "2")], defaultValue: "0"),
            Option(id: "particleQuality", title: "Particles", subtitle: "Engine -particleQuality",
                   choices: [("Low · 0", "0"), ("1 · test", "1"), ("2 · test", "2")], defaultValue: "0"),
            Option(id: "grassQuality", title: "Grass quality", subtitle: "Engine -grassQuality",
                   choices: [("Low · 0", "0"), ("1 · test", "1"), ("2 · test", "2")], defaultValue: "0")
        ]),
        Section(title: "WORLD & DENSITY", subtitle: "Engine switches present in LOW_ARGS", options: [
            Option(id: "cityDensity", title: "City density", subtitle: "-cityDensity",
                   choices: [("Low · 0", "0"), ("1 · test", "1"), ("2 · test", "2")], defaultValue: "0"),
            Option(id: "lodScale", title: "World level of detail", subtitle: "-lodScale",
                   choices: [("Low · 0", "0"), ("1 · test", "1"), ("2 · test", "2")], defaultValue: "0"),
            Option(id: "pedVariety", title: "Pedestrian variety", subtitle: "-pedVariety",
                   choices: [("Low · 0", "0"), ("1 · test", "1")], defaultValue: "0"),
            Option(id: "vehicleVariety", title: "Vehicle variety", subtitle: "-vehicleVariety",
                   choices: [("Low · 0", "0"), ("1 · test", "1")], defaultValue: "0"),
            Option(id: "pedLodBias", title: "Pedestrian LOD bias", subtitle: "-pedLodBias",
                   choices: [("Low · 0", "0"), ("1 · test", "1")], defaultValue: "0"),
            Option(id: "vehicleLodBias", title: "Vehicle LOD bias", subtitle: "-vehicleLodBias",
                   choices: [("Low · 0", "0"), ("1 · test", "1")], defaultValue: "0")
        ]),
        Section(title: "RUNTIME & MEMORY", subtitle: "Original WebAssembly runtime and worker switches", options: [
            Option(id: "low", title: "Low-memory profile", subtitle: "Loads LOW_ARGS and reduces worker/memory pressure",
                   choices: [("Enabled · recommended", "1"), ("Disabled · experimental", "0")], defaultValue: "1"),
            Option(id: "cores", title: "Logical CPU cores", subtitle: "-numCores / navigator.hardwareConcurrency override",
                   choices: [("2 · recommended", "2"), ("4 · test", "4"), ("Automatic", "0")], defaultValue: "2"),
            Option(id: "nocache", title: "Browser data store", subtitle: "io_worker OPFS persistence; USB remains source",
                   choices: [("Memory only · recommended", "1"), ("Enable OPFS cache", "0")], defaultValue: "1"),
            Option(id: "nohints", title: "Asset read-ahead", subtitle: "io_worker queued streaming requests",
                   choices: [("Enabled", "0"), ("Disabled", "1")], defaultValue: "0")
        ]),
        Section(title: "SHADERS & DIAGNOSTICS", subtitle: "WebGPU pipeline and browser diagnostics switches", options: [
            Option(id: "nopack", title: "Shader source loading", subtitle: "wgpu_worker packed WGSL fetch vs individual files",
                   choices: [("Shader packs", "0"), ("Individual shaders", "1")], defaultValue: "0"),
            Option(id: "syncpipelines", title: "Pipeline compilation", subtitle: "wgpu_worker synchronous diagnostic mode",
                   choices: [("Asynchronous", "0"), ("Synchronous · debug", "1")], defaultValue: "0"),
            Option(id: "verbose", title: "Engine log filtering", subtitle: "Keep Script/replay messages vs warning-only",
                   choices: [("Warnings only", "0"), ("Verbose", "1")], defaultValue: "0"),
            Option(id: "trace", title: "File-request tracing", subtitle: "io_worker trace data sent into app logs",
                   choices: [("Off", "0"), ("On · debug", "1")], defaultValue: "0"),
            Option(id: "mem", title: "Memory sampling", subtitle: "Browser memory measurement if supported by WebKit",
                   choices: [("Off", "0"), ("On", "1")], defaultValue: "0")
        ])
    ]

    private static let prefix = "gtaios.engine."
    static func option(_ id: String) -> Option? {
        for section in sections {
            if let value = section.options.first(where: { $0.id == id }) { return value }
        }
        return nil
    }
    static func value(_ id: String) -> String {
        let option = option(id)
        if let saved = UserDefaults.standard.string(forKey: prefix + id),
           option?.choices.contains(where: { $0.1 == saved }) == true {
            return saved
        }
        // Preserve settings from the first unsigned IPA.
        if id == "fps", UserDefaults.standard.integer(forKey: "gtaios.fps") == 60 { return "60" }
        if id == "scale" {
            let old = UserDefaults.standard.double(forKey: "gtaios.scale")
            if old > 0 {
                let opts = option?.choices ?? []
                return opts.min(by: {
                    abs((Double($0.1) ?? 0.65) - old) < abs((Double($1.1) ?? 0.65) - old)
                })?.1 ?? "0.65"
            }
        }
        return option?.defaultValue ?? ""
    }
    static func set(_ id: String, value: String) {
        guard let spec = option(id), spec.choices.contains(where: { $0.1 == value }) else { return }
        UserDefaults.standard.set(value, forKey: prefix + id)
        LogStore.shared.write("boot", "Engine option " + id + "=" + value)
    }
    static func display(_ id: String) -> String {
        let actual = value(id)
        return option(id)?.choices.first(where: { $0.1 == actual })?.0 ?? actual
    }
    static func resetAll() {
        for s in sections {
            for option in s.options {
                UserDefaults.standard.removeObject(forKey: prefix + option.id)
            }
        }
        // Remove legacy migrated values or they would defeat reset.
        UserDefaults.standard.removeObject(forKey: "gtaios.fps")
        UserDefaults.standard.removeObject(forKey: "gtaios.scale")
        LogStore.shared.write("boot", "Engine settings reset to supported low-memory defaults")
    }


}
