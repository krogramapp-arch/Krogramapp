import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var themes: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var apiID = ""
    @State private var apiHash = ""
    @State private var isAPIHashVisible = false
    @State private var phone = ""
    @State private var code = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            AuroraBackdrop()
            ScrollView {
                VStack(spacing: KroSpacing.xl) {
                    header
                    stepCard
                    if let error = session.errorText {
                        Text(error)
                            .kro(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    Text("login.privacyNote")
                        .kro(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(KroSpacing.xl)
                .padding(.top, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(themes.shouldAnimate(reduceMotion: reduceMotion) ? .smooth : nil, value: stepID)
    }

    private var stepCard: some View {
        Group {
            if themes.shouldAnimate(reduceMotion: reduceMotion) {
                stepContent
                    .id(stepID)
                    .transition(KroBlurTransition())
            } else {
                stepContent
                    .id(stepID)
                    .transition(.identity)
            }
        }
        .padding(KroSpacing.xl)
        .glass(cornerRadius: 28)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: KroSpacing.md) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(themes.current.onAccent)
                .frame(width: 92, height: 92)
                .background(themes.current.accent, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .neonGlow(themes.current.accent, radius: 24)
            Text("login.welcome.title").kro(.title, weight: .bold)
            Text("login.welcome.subtitle")
                .kro(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Steps

    private var stepID: String {
        switch session.phase {
        case .welcome: return "welcome"
        case .credentials: return "credentials"
        case .connecting: return "connecting"
        case .login(let step):
            switch step {
            case .waitPhone: return "phone"
            case .waitCode: return "code"
            case .waitPassword: return "password"
            case .unsupported: return "unsupported"
            default: return "failed"
            }
        default: return "other"
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch session.phase {
        case .welcome:
            welcomeStep
        case .credentials:
            credentialsStep
        case .connecting:
            HStack(spacing: KroSpacing.md) {
                ProgressView()
                Text("login.connecting").kro(.body)
            }
        case .login(let step):
            switch step {
            case .waitPhone: phoneStep
            case .waitCode: codeStep
            case .waitPassword(let hint): passwordStep(hint: hint)
            case .unsupported: messageStep(key: "login.unsupported")
            default: messageStep(key: "login.failed", offersReset: true)
            }
        default:
            EmptyView()
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: KroSpacing.md) {
            Button {
                Haptics.tap()
                session.beginLogin()
            } label: {
                Text("login.start").frame(maxWidth: .infinity)
            }
            .buttonStyle(KroPrimaryButtonStyle())
            .neonGlow(themes.current.accent, radius: 14)

            Button("login.demo") {
                Task { await session.enterDemo() }
            }
            .kro(.subheadline, weight: .medium)
        }
    }

    private var credentialsStep: some View {
        VStack(alignment: .leading, spacing: KroSpacing.md) {
            Text("login.creds.title").kro(.headline, weight: .semibold)
            Text("login.creds.hint").kro(.footnote).foregroundStyle(.secondary)
            Link("my.telegram.org", destination: URL(string: "https://my.telegram.org")!)
                .kro(.footnote, weight: .medium)
            field(TextField("login.creds.id", text: $apiID).keyboardType(.numberPad))
            HStack(spacing: KroSpacing.sm) {
                Group {
                    if isAPIHashVisible {
                        TextField("login.creds.hash", text: $apiHash)
                    } else {
                        SecureField("login.creds.hash", text: $apiHash)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button {
                    isAPIHashVisible.toggle()
                } label: {
                    Image(systemName: isAPIHashVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(Text(isAPIHashVisible ? "login.creds.hideHash" : "login.creds.showHash"))
            }
            .kro(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemBackground).opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            primaryButton("login.creds.save") {
                session.saveCredentials(apiIDText: apiID, apiHash: apiHash)
            }
            Button("login.demo") {
                Task { await session.enterDemo() }
            }
            .kro(.subheadline, weight: .medium)
            backButton
        }
    }

    private var phoneStep: some View {
        VStack(alignment: .leading, spacing: KroSpacing.md) {
            Text("login.phone.title").kro(.headline, weight: .semibold)
            Text("login.phone.hint").kro(.footnote).foregroundStyle(.secondary)
            field(TextField("login.phone.placeholder", text: $phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber))
            primaryButton("login.next") { session.submitPhone(phone) }
                .disabled(session.isBusy || phone.trimmingCharacters(in: .whitespaces).isEmpty)
            backButton
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: KroSpacing.md) {
            Text("login.code.title").kro(.headline, weight: .semibold)
            Text("login.code.hint").kro(.footnote).foregroundStyle(.secondary)
            field(TextField("login.code.title", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode))
            primaryButton("login.next") { session.submitCode(code) }
                .disabled(session.isBusy || code.trimmingCharacters(in: .whitespaces).isEmpty)
            backButton
        }
    }

    private func passwordStep(hint: String) -> some View {
        VStack(alignment: .leading, spacing: KroSpacing.md) {
            Text("login.password.title").kro(.headline, weight: .semibold)
            if !hint.isEmpty {
                Text(String(format: L("login.password.hintFormat"), hint))
                    .kro(.footnote).foregroundStyle(.secondary)
            }
            field(SecureField("login.password.title", text: $password))
            primaryButton("login.next") { session.submitPassword(password) }
                .disabled(session.isBusy || password.isEmpty)
            backButton
        }
    }

    private func messageStep(key: LocalizedStringKey, offersReset: Bool = false) -> some View {
        VStack(spacing: KroSpacing.md) {
            Text(key).kro(.body).multilineTextAlignment(.center)
            if offersReset {
                Button("login.creds.reset") {
                    session.forgetCredentials()
                    session.backToWelcome()
                }
                .kro(.footnote, weight: .medium)
            }
            backButton
        }
    }

    // MARK: Pieces

    private func field<Content: View>(_ content: Content) -> some View {
        content
            .kro(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemBackground).opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func primaryButton(_ key: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack {
                if session.isBusy { ProgressView().tint(.white) }
                Text(key)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(KroPrimaryButtonStyle())
    }

    private var backButton: some View {
        Button("login.back") {
            password = ""
            code = ""
            session.backToWelcome()
        }
        .kro(.footnote, weight: .medium)
        .frame(maxWidth: .infinity)
    }
}
