import SwiftUI

struct PersonalInfoEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(String(localized: "Saved only on this device"), systemImage: "lock.shield.fill")
                        .font(EchoFont.body(15, weight: .bold))
                        .foregroundStyle(Palette.forest)

                    Text(String(localized: "Anything you enter becomes a one-tap phrase in Build > Personal. Leave a field blank to hide it from the board."))
                        .font(EchoFont.body(15, weight: .medium))
                        .foregroundStyle(Palette.muted)

                    profileField(String(localized: "Name"), text: binding(\.profileName), prompt: String(localized: "Avery Johnson"))
                    profileField(String(localized: "Date of birth"), text: binding(\.profileDateOfBirth), prompt: String(localized: "January 1, 1970"))
                    profileField(String(localized: "Address"), text: binding(\.profileAddress), prompt: String(localized: "123 Main Street, Austin, Texas"), multiline: true)
                    profileField(String(localized: "Phone number"), text: binding(\.profilePhone), prompt: "(512) 555-0100")
                    profileField(String(localized: "Email address"), text: binding(\.profileEmail), prompt: "avery@example.com")
                    profileField(String(localized: "Medical conditions"), text: binding(\.profileMedicalConditions), prompt: String(localized: "Conditions you want others to know"), multiline: true)
                    profileField(String(localized: "Medications"), text: binding(\.profileMedications), prompt: String(localized: "Medication names and doses"), multiline: true)
                    profileField(String(localized: "Allergies"), text: binding(\.profileAllergies), prompt: String(localized: "Allergies or none"), multiline: true)
                    profileField(String(localized: "Emergency contact"), text: binding(\.profileEmergencyContact), prompt: String(localized: "Name and phone number"), multiline: true)
                }
                .padding(20)
                .readableContentWidth()
            }
            .background(Palette.cream)
            .navigationTitle(String(localized: "Personal Info"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<AppStore, String>) -> Binding<String> {
        Binding(
            get: { store[keyPath: keyPath] },
            set: { store[keyPath: keyPath] = $0 }
        )
    }

    private func profileField(
        _ title: String,
        text: Binding<String>,
        prompt: String,
        multiline: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(EchoFont.body(16, weight: .bold))
                .foregroundStyle(Palette.ink)

            TextField(prompt, text: text, axis: multiline ? .vertical : .horizontal)
                .font(EchoFont.body(17, weight: .medium))
                .lineLimit(multiline ? 2...4 : 1...1)
                .padding(14)
                .background(Palette.surface, in: .rect(cornerRadius: 15))
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .strokeBorder(Palette.forest.opacity(0.12), lineWidth: 2)
                }
        }
    }
}
