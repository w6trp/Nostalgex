import Foundation

/// Rating links remain hidden until this fork has its own App Store record.
enum AppStoreLink {
    static var productPage: URL? {
        guard let appID = Bundle.main.object(forInfoDictionaryKey: "CouchWaveAppStoreID") as? String,
              !appID.isEmpty, appID.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appID)")
    }
}
