import CoreLocation
import Foundation

enum LocationServiceError: LocalizedError {
    case unavailable
    case denied
    case restricted
    case noLocation

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "transaction.location.errorUnavailable".localized
        case .denied:
            return "transaction.location.errorDenied".localized
        case .restricted:
            return "transaction.location.errorRestricted".localized
        case .noLocation:
            return "transaction.location.errorNoLocation".localized
        }
    }
}

@MainActor
final class CurrentLocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = false
    }

    func requestCurrentLocation() async throws -> CLLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationServiceError.unavailable
        }

        let status = await requestAuthorizationIfNeeded()
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .denied:
            throw LocationServiceError.denied
        case .restricted:
            throw LocationServiceError.restricted
        case .notDetermined:
            throw LocationServiceError.denied
        @unknown default:
            throw LocationServiceError.unavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func requestAuthorizationIfNeeded() async -> CLAuthorizationStatus {
        let status = manager.authorizationStatus
        guard status == .notDetermined else { return status }

        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let continuation = authorizationContinuation else { return }
        authorizationContinuation = nil
        continuation.resume(returning: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil

        if let location = locations.last {
            continuation.resume(returning: location)
        } else {
            continuation.resume(throwing: LocationServiceError.noLocation)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(throwing: error)
    }
}
