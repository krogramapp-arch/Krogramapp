import CoreLocation
import SwiftUI

@MainActor
private final class CurrentLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var isLoading = true
    @Published private(set) var isDenied = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        isLoading = true
        isDenied = false
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            isDenied = true
            isLoading = false
        @unknown default:
            isDenied = true
            isLoading = false
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        request()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last(where: { $0.horizontalAccuracy >= 0 })
        isLoading = false
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isLoading = false
    }
}

struct LocationShareView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var provider = CurrentLocationProvider()
    @State private var isSending = false
    @State private var errorMessage: String?

    let onSend: (Double, Double) async throws -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: KroSpacing.md) {
                if provider.isLoading {
                    ProgressView("location.fetching")
                } else if provider.isDenied {
                    ContentUnavailableView("location.permissionDenied", systemImage: "location.slash")
                } else if let location = provider.location {
                    Label("location.confirmTitle", systemImage: "location.fill")
                        .font(.headline)
                    Text(String(format: "%.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude))
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Text(String(format: L("location.accuracy"), Int(location.horizontalAccuracy.rounded(.up))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("location.send") {
                        send(location.coordinate)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSending)
                } else {
                    ContentUnavailableView("location.unavailable", systemImage: "location.slash")
                    Button("location.retry") { provider.request() }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .padding(KroSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("location.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
            }
            .task { provider.request() }
        }
    }

    private func send(_ coordinate: CLLocationCoordinate2D) {
        isSending = true
        errorMessage = nil
        Task {
            do {
                try await onSend(coordinate.latitude, coordinate.longitude)
                dismiss()
            } catch {
                errorMessage = TGErrors.message(for: error)
                isSending = false
            }
        }
    }
}
