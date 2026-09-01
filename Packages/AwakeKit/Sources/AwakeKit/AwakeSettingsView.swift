import SwiftUI
import EyrieCore

struct AwakeSettingsView: View {
    @Bindable var module: AwakeModule

    var body: some View {
        Form {
            Toggle("Allow display to sleep during sessions", isOn: $module.allowDisplaySleep)
            Text("The system stays awake either way; this only controls whether the screen may turn off.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Simulated activity interval", selection: $module.activityInterval) {
                ForEach(AwakeActivityInterval.allCases) { interval in
                    Text(interval.label).tag(interval)
                }
            }
            Text("How often the pointer is nudged while Simulate activity is on and you haven't touched the mouse or keyboard.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
