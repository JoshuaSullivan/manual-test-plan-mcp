//
//  SettingsView.swift
//  ManualTestPlan
//

import SwiftUI

/// Server port, connection status, and the command that registers this server with Claude Code.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var portText = ""

    var body: some View {
        Form {
            Section("Server") {
                LabeledContent("Status") {
                    ServerStatusRow(state: model.server.state)
                }
                TextField("Port", text: $portText)
                    .onSubmit(applyPort)
                    .onChange(of: model.port, initial: true) { _, port in
                        portText = String(port)
                    }
                if let port = Int(portText), port != Int(model.port) {
                    Button("Apply and Restart Server", action: applyPort)
                        .disabled(!AppModel.isValid(port: port))
                }
                if let port = Int(portText), !AppModel.isValid(port: port) {
                    Text("Choose a port between \(AppModel.minimumPort) and 65535.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section("General") {
                @Bindable var model = model
                Toggle("Keep plan windows on top", isOn: $model.keepPlanWindowsOnTop)
                Text("Plan windows float above other apps so they never get lost behind the app you're testing. They can cover what you're testing, so this is off by default.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                if model.launchAtLogin.needsApproval {
                    Text("Approve ManualTestPlan in System Settings › General › Login Items.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let message = model.launchAtLogin.errorMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section("Connect an Agent") {
                Text("Run this once in a terminal to give Claude Code access to ManualTestPlan:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(model.setupCommand)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                Button("Copy Command", systemImage: "doc.on.doc") {
                    Clipboard.copy(model.setupCommand)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { model.launchAtLogin.isEnabled },
            set: { model.launchAtLogin.setEnabled($0) }
        )
    }

    private func applyPort() {
        if let port = Int(portText) {
            model.changePort(to: port)
        }
    }
}
