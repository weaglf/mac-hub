import Foundation
import Observation

/// Open-Meteo (anahtarsız, ücretsiz) ile hava durumu.
@Observable @MainActor
final class WeatherService {
    var cityName: String?
    var temperature: Double?
    var apparent: Double?
    var high: Double?
    var low: Double?
    var code: Int?
    var isDay = true
    var failed = false
    private var lastFetch: Date?
    private var coordinates: [String: (Double, Double, String)] = [:]

    func refresh(city: String, force: Bool = false) async {
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < 600, cityName != nil { return }
        do {
            let (lat, lon, name) = try await locate(city)
            var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            comps.queryItems = [
                .init(name: "latitude", value: String(lat)),
                .init(name: "longitude", value: String(lon)),
                .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
                .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
                .init(name: "timezone", value: "auto"),
                .init(name: "forecast_days", value: "1"),
            ]
            struct Response: Decodable {
                struct Current: Decodable {
                    let temperature_2m: Double
                    let apparent_temperature: Double?
                    let weather_code: Int
                    let is_day: Int
                }
                struct Daily: Decodable {
                    let temperature_2m_max: [Double]
                    let temperature_2m_min: [Double]
                }
                let current: Current
                let daily: Daily
            }
            let (data, _) = try await URLSession.shared.data(from: comps.url!)
            let r = try JSONDecoder().decode(Response.self, from: data)
            cityName = name
            temperature = r.current.temperature_2m
            apparent = r.current.apparent_temperature
            code = r.current.weather_code
            isDay = r.current.is_day == 1
            high = r.daily.temperature_2m_max.first
            low = r.daily.temperature_2m_min.first
            failed = false
            lastFetch = Date()
        } catch {
            failed = true
        }
    }

    private func locate(_ city: String) async throws -> (Double, Double, String) {
        if let cached = coordinates[city] { return cached }
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [
            .init(name: "name", value: city),
            .init(name: "count", value: "1"),
            .init(name: "language", value: "tr"),
        ]
        struct Response: Decodable {
            struct Place: Decodable { let latitude: Double; let longitude: Double; let name: String }
            let results: [Place]?
        }
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        guard let place = try JSONDecoder().decode(Response.self, from: data).results?.first else {
            throw URLError(.cannotFindHost)
        }
        let value = (place.latitude, place.longitude, place.name)
        coordinates[city] = value
        return value
    }

    var symbol: String { Self.symbol(code: code ?? 0, isDay: isDay) }
    var summary: String { Self.summary(code: code ?? 0) }

    static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61, 63, 80, 81: "cloud.rain.fill"
        case 65, 66, 67, 82: "cloud.heavyrain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func summary(code: Int) -> String {
        switch code {
        case 0: "Açık"
        case 1: "Az bulutlu"
        case 2: "Parçalı bulutlu"
        case 3: "Kapalı"
        case 45, 48: "Sisli"
        case 51, 53, 55: "Çisenti"
        case 56, 57: "Dondurucu çisenti"
        case 61: "Hafif yağmur"
        case 63: "Yağmurlu"
        case 65: "Kuvvetli yağmur"
        case 66, 67: "Dondurucu yağmur"
        case 71, 73: "Kar yağışlı"
        case 75: "Yoğun kar"
        case 77: "Kar taneleri"
        case 80, 81: "Sağanak"
        case 82: "Şiddetli sağanak"
        case 85, 86: "Kar sağanağı"
        case 95: "Gök gürültülü fırtına"
        case 96, 99: "Dolu ve fırtına"
        default: "—"
        }
    }
}
