import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var model: RemoteDeckModel
    @Environment(\.openURL) private var openURL
    @State private var showingSettings = false
    @State private var copiedDeviceCode: String?

    var body: some View {
        NavigationStack {
            Group {
                if model.isStreaming, let transport = model.transport {
                    PlayerView(transport: transport)
                        .environmentObject(model)
                        .ignoresSafeArea()
                        .toolbar(.hidden, for: .navigationBar)
                } else {
                    home
                }
            }
            .navigationTitle("RemoteDeck")
            .toolbar {
                if !model.isStreaming {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        if model.hasSavedTokens {
                            Menu {
                                Button {
                                    Task { await model.loadConsoles() }
                                } label: {
                                    Label("Refresh consoles", systemImage: "arrow.clockwise")
                                }
                                Button(role: .destructive) {
                                    model.signOut()
                                } label: {
                                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                                }
                            } label: {
                                Image(systemName: "person.crop.circle")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(model)
            }
            .task {
                if model.hasSavedTokens, model.consoles.isEmpty {
                    await model.loadConsoles()
                }
            }
        }
        .tint(.green)
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
                if let code = model.deviceCode {
                    deviceCodeCard(code)
                } else if model.hasSavedTokens {
                    consoleList
                } else {
                    signInCard
                }
            }
            .padding(22)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.035, green: 0.055, blue: 0.07))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("RemoteDeck")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text("Your Xbox. Your network. Your iPhone.")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 14)
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Connect your Microsoft account", systemImage: "xbox.logo")
                .font(.title3.bold())
            Text("RemoteDeck uses Microsoft's public device sign-in flow. Your password is entered only on Microsoft's sign-in page.")
                .foregroundStyle(.secondary)
            Button {
                Task { await model.beginSignIn() }
            } label: {
                HStack {
                    if model.isBusy { ProgressView().tint(.black) }
                    Text(model.isBusy ? "Starting sign-in…" : "Sign in with Microsoft")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundStyle(.black)
                .background(.green, in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(model.isBusy)
        }
        .padding(20)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }

    private func deviceCodeCard(_ code: DeviceCodeResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Finish signing in")
                .font(.title3.bold())
            Text(code.message ?? "Open the Microsoft page and enter this one-time code.")
                .foregroundStyle(.secondary)
            Text(code.userCode)
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .tracking(3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            Button {
                UIPasteboard.general.string = code.userCode
                copiedDeviceCode = code.userCode
            } label: {
                Label(
                    copiedDeviceCode == code.userCode ? "Copied" : "Copy code",
                    systemImage: copiedDeviceCode == code.userCode ? "checkmark" : "doc.on.doc"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Copy Microsoft sign-in code")
            Button {
                openURL(code.verificationURI)
            } label: {
                Label("Open Microsoft sign-in", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.green, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.black)
                    .fontWeight(.semibold)
            }
            HStack {
                ProgressView()
                Text(model.signInStatus ?? "Waiting for Microsoft approval. Return here after approving.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }

    private var consoleList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your consoles")
                    .font(.title3.bold())
                Spacer()
                if model.isBusy {
                    HStack(spacing: 8) {
                        ProgressView()
                        if let status = model.connectionStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if model.consoles.isEmpty && !model.isBusy {
                VStack(spacing: 10) {
                    Image(systemName: "xbox.console")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No consoles found")
                        .font(.headline)
                    Text("Check that the console is registered to this account and has Remote Features enabled.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
            } else {
                ForEach(model.consoles) { console in
                    Button {
                        Task { await model.connect(to: console) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "xbox.console")
                                .font(.system(size: 24))
                                .foregroundStyle(.green)
                                .frame(width: 44, height: 44)
                                .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(console.deviceName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(console.powerState.map { "Xbox reports \($0)" } ?? "Power status unavailable")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.isBusy {
                                ProgressView()
                            } else {
                                Image(systemName: "play.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(14)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(model.isBusy)
                }
            }
        }
    }
}
