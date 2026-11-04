import Foundation

/// Fecha en que vence el perfil de instalación de la cuenta gratuita.
enum AppExpiry {
    static let current: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }()

    /// El perfil es un plist envuelto en una firma: se recorta el XML y se lee la fecha.
    static func parse(_ data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil)
        return (plist as? [String: Any])?["ExpirationDate"] as? Date
    }

    static func notices(expiry: Date?, now: Date) -> [LocalNotification] {
        guard let expiry else { return [] }
        return [48, 24, 3].compactMap { hours in
            let date = expiry.addingTimeInterval(Double(-hours) * 3600)
            guard date > now else { return nil }
            return LocalNotification(id: "app-expiry-\(hours)", date: date, title: "La app está por vencer",
                                     body: "Conectá el iPhone a la Mac para reinstalar. Tus datos no se pierden.")
        }
    }
}
