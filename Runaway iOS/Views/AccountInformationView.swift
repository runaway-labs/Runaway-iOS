//
//  AccountInformationView.swift
//  Runaway iOS
//
//  View for editing user account information including name and profile photo
//

import SwiftUI
import PhotosUI

struct AccountInformationView: View {
    @Environment(DataManager.self) var dataManager
    @Environment(\.dismiss) private var dismiss

    @State private var firstname: String = ""
    @State private var lastname: String = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var profileImage: UIImage?
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            ZStack {
                (AppTheme.Colors.adaptiveBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppTheme.Spacing.xl) {
                        // Profile Photo Section
                        profilePhotoSection

                        // Name Fields
                        nameFieldsSection

                        // Account Info
                        accountInfoSection
                    }
                    .padding(AppTheme.Spacing.lg)
                }
            }
            .adaptiveSurfaceTint()
            .navigationTitle("Account Information")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(AppTheme.Colors.DarkMode.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.DarkMode.accent)
                    .darkSurfaceTint()
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await saveChanges()
                        }
                    }
                    .foregroundColor(AppTheme.Colors.DarkMode.accent)
                    .darkSurfaceTint()
                    .disabled(isSaving || !hasChanges)
                }
            }
            .background {
                Color.clear
                    .alert("Error", isPresented: $showError) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(errorMessage)
                    }
                    .adaptiveSurfaceTint()
            }
            .onAppear {
                loadCurrentData()
            }
            .onChange(of: selectedPhoto) { _, newPhoto in
                Task {
                    await loadSelectedPhoto(newPhoto)
                }
            }
        }
        .darkSurfaceTint()
    }

    // MARK: - View Components

    private var profilePhotoSection: some View {
        let profileURL = dataManager.athlete?.profile

        return VStack(spacing: AppTheme.Spacing.md) {
            // Photo Display
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                if let profileImage = profileImage {
                    Image(uiImage: profileImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppTheme.Colors.accent, lineWidth: 3))
                } else if let profileURL {
                    AsyncImage(url: profileURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        placeholderImage
                    }
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppTheme.Colors.accent, lineWidth: 3))
                } else {
                    placeholderImage
                }
            }

            Text("Tap to change photo")
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)
        }
        .padding(.top, AppTheme.Spacing.lg)
    }

    private var placeholderImage: some View {
        ZStack {
            Circle()
                .fill(AppTheme.Colors.accent.opacity(0.1))
                .frame(width: 120, height: 120)

            Image(systemName: "person.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(AppTheme.Colors.accent)
        }
    }

    private var nameFieldsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Personal Information")
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

            // First Name
            VStack(alignment: .leading, spacing: 8) {
                Text("First Name")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)

                TextField("First name", text: $firstname)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(AppTheme.Colors.adaptiveSurfaceBackground)
                    .cornerRadius(AppTheme.CornerRadius.medium)
                    .autocapitalization(.words)
            }

            // Last Name
            VStack(alignment: .leading, spacing: 8) {
                Text("Last Name")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)

                TextField("Last name", text: $lastname)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(AppTheme.Colors.adaptiveSurfaceBackground)
                    .cornerRadius(AppTheme.CornerRadius.medium)
                    .autocapitalization(.words)
            }
        }
    }

    private var accountInfoSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("Account Details")
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)

            InfoRow(label: "Email", value: dataManager.athlete?.email ?? "Not available")
            InfoRow(label: "Athlete ID", value: "\(dataManager.athlete?.id ?? 0)")
        }
    }

    // MARK: - Helper Methods

    private var hasChanges: Bool {
        let currentFirstname = dataManager.athlete?.firstname ?? ""
        let currentLastname = dataManager.athlete?.lastname ?? ""
        return firstname != currentFirstname ||
               lastname != currentLastname ||
               profileImage != nil
    }

    private func loadCurrentData() {
        firstname = dataManager.athlete?.firstname ?? ""
        lastname = dataManager.athlete?.lastname ?? ""
    }

    private func loadSelectedPhoto(_ photoItem: PhotosPickerItem?) async {
        guard let photoItem = photoItem else { return }

        do {
            if let data = try await photoItem.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    profileImage = image
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to load photo"
                showError = true
            }
        }
    }

    private func saveChanges() async {
        isSaving = true
        defer { isSaving = false }

        guard let athlete = dataManager.athlete,
              let userId = athlete.userId else {
            errorMessage = "No athlete data available"
            showError = true
            return
        }

        do {
            var profileURL: URL? = athlete.profile

            // Upload photo if changed
            if let newImage = profileImage {
                profileURL = try await SupabaseStorageService.shared.uploadProfilePhoto(newImage, userId: userId)
            }

            // Update athlete data
            try await AthleteService.shared.updateAthlete(
                athleteId: athlete.id ?? 0,
                firstname: firstname.isEmpty ? nil : firstname,
                lastname: lastname.isEmpty ? nil : lastname,
                profileURL: profileURL
            )

            // Refresh data
            if let athleteId = athlete.id {
                await dataManager.loadAthlete(for: athleteId)
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Supporting Views

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.adaptiveTextSecondary)

            Spacer()

            Text(value)
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.adaptiveTextPrimary)
        }
        .padding()
        .background(AppTheme.Colors.adaptiveSurfaceBackground)
        .cornerRadius(AppTheme.CornerRadius.medium)
    }
}

struct AccountInformationView_Previews: PreviewProvider {
    static var previews: some View {
        AccountInformationView()
            .environment(DataManager.shared)
    }
}
