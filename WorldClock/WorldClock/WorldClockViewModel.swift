import Foundation

struct TimeZoneItem: Identifiable {
    let id = UUID()
    let timeZone: TimeZone
    var currentTime: String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.timeStyle = .medium
        return formatter.string(from: Date())
    }
    var displayName: String {
        timeZone.identifier.replacingOccurrences(of: "_", with: " ")
    }
}

class WorldClockViewModel: ObservableObject {
    @Published var timeZones: [TimeZoneItem] = []
    private var timer: Timer?

    func start() {
        timeZones = TimeZone.knownTimeZoneIdentifiers.prefix(10).compactMap { id in
            if let tz = TimeZone(identifier: id) {
                return TimeZoneItem(timeZone: tz)
            }
            return nil
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
