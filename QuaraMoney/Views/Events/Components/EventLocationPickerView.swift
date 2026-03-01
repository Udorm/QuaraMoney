import SwiftUI
import MapKit
import CoreLocation

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
                            Marker(L10n.EventAdditional.locationSelected, coordinate: coordinate)
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
                            Text(locationName.isEmpty ? L10n.EventAdditional.locationSelected : locationName)
                                .font(.app(.headline))
                                .lineLimit(1)
                            
                            Button {
                                latitude = coordinate.latitude
                                longitude = coordinate.longitude
                                dismiss()
                            } label: {
                                Text(L10n.EventAdditional.locationConfirm)
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
            .navigationTitle(L10n.EventAdditional.locationPick)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func updateLocationName(for coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else { return }
        
        Task {
            do {
                let response = try await request.mapItems
                if let mapItem = response.first {
                    let name = mapItem.name
                    let cityName = mapItem.addressRepresentations?.cityName
                    let regionName = mapItem.addressRepresentations?.regionName
                    
                    let components = [name, cityName, regionName].compactMap { $0 }
                    let joinedName = components.joined(separator: ", ")
                    
                    await MainActor.run {
                        locationName = joinedName
                    }
                }
            } catch {
                print("Geocoding failed: \(error)")
            }
        }
    }
}
