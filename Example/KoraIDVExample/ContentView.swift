import SwiftUI
import KoraIDV

struct ContentView: View {

    @State private var externalId = "user-123"
    @State private var selectedTier: VerificationTier = .standard
    @State private var resultMessage: String?
    @State private var showResult = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer()

                Text("KoraIDV Sample")
                    .font(.title)
                    .fontWeight(.bold)

                Text("v\(KoraIDV.version)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("External ID")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Enter external ID", text: $externalId)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Verification Tier")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Tier", selection: $selectedTier) {
                        Text("Basic").tag(VerificationTier.basic)
                        Text("Standard").tag(VerificationTier.standard)
                        Text("Enhanced").tag(VerificationTier.enhanced)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                .padding(.horizontal)

                Button(action: startVerification) {
                    Text("Start Verification")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color(red: 0.05, green: 0.58, blue: 0.53))
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationBarHidden(true)
            .alert(isPresented: $showResult) {
                Alert(
                    title: Text("Result"),
                    message: Text(resultMessage ?? ""),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func startVerification() {
        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .rootViewController else {
            return
        }

        KoraIDV.startVerification(
            externalId: externalId,
            tier: selectedTier,
            from: rootVC
        ) { result in
            switch result {
            case .success(let verification):
                resultMessage = "Verified: \(verification.status.rawValue) (ID: \(verification.id))"
            case .failure(let error):
                resultMessage = "Error: \(error.message)"
            case .cancelled:
                resultMessage = "Verification cancelled"
            }
            showResult = true
        }
    }
}
