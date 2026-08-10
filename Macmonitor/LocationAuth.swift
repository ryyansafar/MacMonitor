import Foundation
import Combine
import CoreLocation
import AppKit

/// Owns the CLLocationManager used solely to obtain Location authorization, which
/// macOS requires before CoreWLAN will return the current Wi-Fi SSID. The prompt is
/// triggered on demand from Settings rather than at launch.
final class LocationAuthManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationAuthManager()

    private let manager = CLLocationManager()
    @Published var status: CLAuthorizationStatus = .notDetermined

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        status = manager.authorizationStatus
    }

    var isGranted: Bool {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: return true
        default: return false
        }
    }

    var isDenied: Bool {
        status == .denied || status == .restricted
    }

    /// Presents the system prompt. On macOS, requestWhenInUseAuthorization() alone is
    /// often a silent no-op — you must also kick an actual location request to force
    /// the dialog. The app must be active/foreground for the prompt to show.
    func request() {
        NSApp.activate(ignoringOtherApps: true)
        manager.requestWhenInUseAuthorization()
        // The real trigger: starting location updates forces CoreLocation to present
        // the prompt while status is .notDetermined. We only need the authorization,
        // so we stop as soon as anything comes back.
        manager.startUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        if s != .notDetermined { manager.stopUpdatingLocation() }   // only needed the grant
        DispatchQueue.main.async { self.status = s }
    }

    // We don't use the location itself — these just satisfy startUpdatingLocation()
    // and let us stop as soon as the authorization flow resolves.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        manager.stopUpdatingLocation()
    }
}
