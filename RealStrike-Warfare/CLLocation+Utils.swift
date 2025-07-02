import CoreLocation

extension CLLocation {
    /// Returns the bearing in degrees from this location to the given location.
    func bearing(to destination: CLLocation) -> Double {
        let lat1 = self.coordinate.latitude.radians
        let lon1 = self.coordinate.longitude.radians
        let lat2 = destination.coordinate.latitude.radians
        let lon2 = destination.coordinate.longitude.radians
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let initialBearing = atan2(y, x)
        var degrees = initialBearing.degrees
        if degrees < 0 { degrees += 360 }
        return degrees
    }
}

private extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}

func angleDifference(_ a1: Double, _ a2: Double) -> Double {
    var diff = fmod(a1 - a2 + 180, 360) - 180
    if diff < -180 { diff += 360 }
    return diff
}

