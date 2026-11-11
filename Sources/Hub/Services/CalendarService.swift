import EventKit
import SwiftUI

struct CalendarItem: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
}

/// Takvim widget'ı eklenince izin ister.
@Observable @MainActor
final class CalendarService {
    enum Access { case unknown, granted, denied }

    private let store = EKEventStore()
    var access: Access = .unknown
    var items: [CalendarItem] = []

    func refresh(requestIfNeeded: Bool) async {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
        case .notDetermined:
            guard requestIfNeeded else { return }
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            access = granted ? .granted : .denied
        default:
            access = .denied
        }
        guard access == .granted else { return }

        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: now))!
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        items = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(4)
            .map {
                CalendarItem(
                    id: $0.eventIdentifier ?? UUID().uuidString,
                    title: $0.title ?? "Etkinlik",
                    start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay,
                    color: Color(cgColor: $0.calendar.cgColor)
                )
            }
    }
}
