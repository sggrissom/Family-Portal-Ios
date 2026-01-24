import SwiftUI

struct PhotoGalleryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Photos",
                systemImage: "photo.on.rectangle",
                description: Text("Photos will appear here.")
            )
            .navigationTitle("Photos")
        }
    }
}
