import Carbon.HIToolbox
import RippleCore
import SwiftUI

/// The macOS 27 SDK declares a `@State` macro alongside the property wrapper, and its plugin
/// (SwiftUIMacros) is missing from the Command Line Tools that Homebrew builds with.
/// Naming the property wrapper through an alias sidesteps the macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    /// Called with true while the shortcut recorder is listening, so the existing hotkey can be paused.
    var onRecordingChange: (Bool) -> Void

    @ViewState private var draftCode = ""

    private var normalizedDraft: String { PairingCode.normalize(draftCode) }

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("Pairing code", text: $draftCode, prompt: Text("e.g. K7QM-2XPA-9RTD-H4WN"))
                        .labelsHidden()
                        .font(.system(.body, design: .monospaced))
                    Button("Generate") { draftCode = PairingCode.generate() }
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(normalizedDraft, forType: .string)
                    }
                    .disabled(normalizedDraft.isEmpty)
                }
                HStack {
                    Spacer()
                    Button("Save Code") { settings.pairingCode = normalizedDraft }
                        .keyboardShortcut(.defaultAction)
                        .disabled(normalizedDraft.isEmpty || normalizedDraft == settings.pairingCode)
                }
            } header: {
                Text("Pairing Code")
            } footer: {
                Text("Use the same code on every Mac. Generate it on one Mac, then enter it on the others. Macs only accept wake requests signed with this code.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Shortcut") {
                LabeledContent("Wake All Macs") {
                    ShortcutRecorder(shortcut: $settings.shortcut, onRecordingChange: onRecordingChange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { draftCode = settings.pairingCode }
    }
}

private struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    var onRecordingChange: (Bool) -> Void

    @ViewState private var isRecording = false
    @ViewState private var monitor: Any?

    var body: some View {
        HStack {
            Button(isRecording ? "Type shortcut…" : (shortcut?.displayString ?? "Record Shortcut")) {
                isRecording ? stopRecording() : startRecording()
            }
            .frame(minWidth: 130)
            if shortcut != nil && !isRecording {
                Button("Clear") { shortcut = nil }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
            } else if let recorded = Shortcut(event: event) {
                shortcut = recorded
                stopRecording()
            } else {
                NSSound.beep() // needs ⌃, ⌥, or ⌘
            }
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        onRecordingChange(false)
    }
}
