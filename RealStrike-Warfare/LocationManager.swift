// LocationManager.swift
import Foundation
import CoreLocation

protocol LocationManagerDelegate: AnyObject {
    func didUpdateLocation(_ location: CLLocation)
    func didUpdateHeading(_ heading: CLHeading)
}

class LocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    
    @Published var currentLocation: CLLocation = CLLocation(latitude: 0, longitude: 0)
    @Published var currentHeading: CLHeading?
    
    weak var delegate: LocationManagerDelegate?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.headingFilter = kCLHeadingFilterNone
    }
    
    func requestPermissions() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startTracking() {
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    func stopTracking() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            DispatchQueue.main.async {
                self.currentLocation = loc
                self.delegate?.didUpdateLocation(loc)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.currentHeading = newHeading
            self.delegate?.didUpdateHeading(newHeading)
        }
    }
}
