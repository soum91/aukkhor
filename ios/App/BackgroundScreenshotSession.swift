import UIKit
import CoreLocation
import Photos
import Combine

// Explicit, app-only experiment. No coordinates are retained or transmitted.
// Permission alone does not keep a process alive: this owns an active session.
@MainActor final class BackgroundScreenshotSession: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Background experiment is stopped."
    private let manager = CLLocationManager()
    private var requested = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = 1000
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    func start() {
        guard ScreenshotClipboard.enabled else {
            status = "Enable automatic screenshot copying first."
            return
        }
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            status = "Allow full Photos access before starting this experiment."
            return
        }
        requested = true
        switch manager.authorizationStatus {
        case .notDetermined:
            status = "Waiting for your location permission choice."
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.allowsBackgroundLocationUpdates = true
            manager.startUpdatingLocation()
            isRunning = true
            status = "Location session requested. No coordinates are stored. Background screenshot copying needs device verification."
            refreshObserver()
        case .restricted, .denied:
            requested = false
            status = "Location access is unavailable. You can change it in iOS Settings."
        @unknown default:
            requested = false
            status = "Location authorization is unavailable."
        }
    }

    func requestAlwaysPermission() {
        manager.requestAlwaysAuthorization()
    }

    func stop() {
        requested = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isRunning = false
        status = "Background location session stopped."
        if UIApplication.shared.applicationState == .active, ScreenshotClipboard.enabled {
            ScreenshotClipboard.shared.start(context: "app foreground")
        } else { ScreenshotClipboard.shared.stop() }
    }

    func refreshObserver() {
        guard isRunning, ScreenshotClipboard.enabled else { return }
        ScreenshotClipboard.shared.start(context: UIApplication.shared.applicationState == .active
            ? "app foreground" : "app background")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard requested else { return }
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            stop()
            status = "Location permission was revoked. Background session stopped."
        } else { start() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Ignore the coordinate values. Only record that execution occurred.
        status = "Location callback at \(Date().formatted(date: .omitted, time: .standard)). No coordinates saved."
        refreshObserver()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = "Location service: \(error.localizedDescription)"
        if (error as? CLError)?.code == .denied { stop() }
    }
}
