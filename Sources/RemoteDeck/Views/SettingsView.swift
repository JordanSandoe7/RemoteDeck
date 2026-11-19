import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: RemoteDeckModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Video") {
                    Picker("Resolution", selection: $model.resolution) {
                        Text("720p").tag(720)
                        Text("1080p").tag(1080)
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Maximum bitrate")
                            Spacer()
                            Text("\(model.bitrateKbps) kbps")
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(model.bitrateKbps) },
                                set: { model.bitrateKbps = Int($0) }
                            ),
                            in: 3000...20000,
                            step: 1000
                        )
                        .tint(.green)
                    }
                    Text("Target: \(model.resolution)p at up to 60 FPS. Actual frame rate and latency depend on your Xbox, game, and network.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Controls") {
                    Toggle("On-screen touch controller", isOn: $model.showTouchControls)
                    LabeledContent("Bluetooth controller") {
                        Text(model.controller.controllerName ?? "Not connected")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("Connect an Xbox controller in iOS Settings > Bluetooth. Video streaming uses your home console and Microsoft sign-in services.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
