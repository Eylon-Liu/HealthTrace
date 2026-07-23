import Foundation
import Combine

final class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager()
    private let key = "favorite_metrics"
    @Published private(set) var favorites: Set<String> = []

    private init() {
        if let arr = UserDefaults.standard.array(forKey: key) as? [String] {
            favorites = Set(arr)
        }
    }

    func isFavorite(_ metric: String) -> Bool {
        favorites.contains(metric)
    }

    func toggle(_ metric: String) {
        if favorites.contains(metric) {
            favorites.remove(metric)
        } else {
            favorites.insert(metric)
        }
        persist()
    }

    func add(_ metric: String) {
        favorites.insert(metric)
        persist()
    }

    func remove(_ metric: String) {
        favorites.remove(metric)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Array(favorites), forKey: key)
        objectWillChange.send()
    }
}
