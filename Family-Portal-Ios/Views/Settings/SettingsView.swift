import SwiftUI

struct SettingsView: View {
    @Environment(AuthService.self) private var authService
    @State private var showServerConfig = false
    @State private var serverURLInput = ""
    @State private var showLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if authService.isAuthenticated, let user = authService.currentUser {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.name)
                                    .font(.headline)
                                Text(user.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)

                        Button("Sign Out", role: .destructive) {
                            showLogoutConfirmation = true
                        }
                    } else {
                        HStack {
                            Image(systemName: "person.circle")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text("Not signed in")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)

                        NavigationLink("Sign In") {
                            LoginView()
                        }
                    }
                }

                Section("Server") {
                    Button {
                        serverURLInput = authService.serverURL
                        showServerConfig = true
                    } label: {
                        HStack {
                            Text("URL")
                            Spacer()
                            Text(authService.serverURL)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .tint(.primary)

                    HStack {
                        Text("Status")
                        Spacer()
                        if authService.isAuthenticated {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.callout)
                        } else {
                            Label("Disconnected", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Server URL", isPresented: $showServerConfig) {
                TextField("https://example.com", text: $serverURLInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save") {
                    let trimmed = serverURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        authService.updateServerURL(trimmed)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter the URL of your Family Portal server.")
            }
            .confirmationDialog("Sign Out", isPresented: $showLogoutConfirmation) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await authService.logout()
                    }
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }
}
