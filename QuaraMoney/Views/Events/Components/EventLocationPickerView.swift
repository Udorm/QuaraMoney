import SwiftUI
import MapKit

struct EventLocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var latitude: Double?
    @Binding var longitude: Double?
    @Binding var locationName: String
    
    @State private var position: MapCameraPosition
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    
    init(latitude: Binding<Double?>, longitude: Binding<Double?>, locationName: Binding<String>) {
        _latitude = latitude
        _longitude = longitude
        _locationName = locationName
        
        let initialLat = latitude.wrappedValue ?? 13.7563
        let initialLon = longitude.wrappedValue ?? 100.5018
        
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: initialLat, longitude: initialLon),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        _position = State(initialValue: .region(region))
        
        if let lat = latitude.wrappedValue, let lon = longitude.wrappedValue {
            _selectedCoordinate = State(initialValue: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                MapReader { proxy in
                    Map(position: $position) {
                        if let coordinate = selectedCoordinate {
                            Marker("Selected Location", coordinate: coordinate)
                        }
                    }
                    .onTapGesture { screenPoint in
                        if let coordinate = proxy.convert(screenPoint, from: .local) {
                            selectedCoordinate = coordinate
                            updateLocationName(for: coordinate)
                        }
                    }
                }
                
                VStack {
                    Spacer()
                    if let coordinate = selectedCoordinate {
                        VStack(spacing: 12) {
                            Text(locationName.isEmpty ? "Selected Location" : locationName)
                                .font(.app(.headline))
                                .lineLimit(1)
                            
                            Button {
                                latitude = coordinate.latitude
                                longitude = coordinate.longitude
                                dismiss()
                            } label: {
                                Text("Confirm Location")
                                    .font(.app(.body, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(radius: 10)
                        .padding()
                    }
                }
            }
            .navigationTitle("Pick Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func updateLocationName(for coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let request = MKReverseGeocodingRequest(location: location)
        request?.getMapItems { mapItems, error in
            if let mapItem = mapItems?.first {
                let placemark = mapItem.placemark
                let name = [placemark.name, placemark.locality, placemark.country]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                locationName = name
            }
        }
    }
}
