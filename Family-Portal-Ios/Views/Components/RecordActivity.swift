import SwiftUI

extension View {
    /// Advertises the record on screen as its web page, so Siri suggestions learn the places a family goes back to and Handoff can carry it to a Mac's browser. A tapped suggestion comes back as a universal link, which the app already routes. Nothing when `path` is nil — a record with no server id has no page yet.
    /// Not eligible for search: `SpotlightIndexer` indexes records itself, and two entries for one record would show twice.
    func advertisesRecord(path: String?, title: String) -> some View {
        userActivity(NSUserActivityTypeBrowsingWeb, isActive: path != nil) { activity in
            guard let path else { return }
            activity.title = title
            activity.webpageURL = URL(string: AppConstants.defaultServerURL + path)
            activity.isEligibleForPrediction = true
            activity.isEligibleForSearch = false
            activity.isEligibleForHandoff = true
        }
    }
}
