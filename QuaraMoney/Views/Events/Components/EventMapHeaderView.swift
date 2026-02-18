import SwiftUI
import MapKit

struct EventMapHeaderView: View {
    let event: Event
    let members: [EventMember]
    
    @State private var position: MapCameraPosition
    
    init(event: Event, members: [EventMember]) {
        self.event = event
        self.members = members
        
        let initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: event.latitude ?? 13.7563, // Default to Bangkok or similar if not set
                longitude: event.longitude ?? 100.5018
            ),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        _position = State(initialValue: .region(initialRegion))
    }
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Map
            Map(position: $position) {
                if let lat = event.latitude, let lon = event.longitude {
                    Marker(event.title, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                }
            }
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .disabled(true) // Static map feel
            
            // Gradient Overlay for readability
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            
            // Content
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.app(.title2, weight: .bold))
                        .foregroundStyle(.white)
                    
                    if let location = event.location {
                        Text(location)
                            .font(.app(.subheadline))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                
                Spacer()
                
                OverlappingAvatarsView(members: members)
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 16)
    }
}
