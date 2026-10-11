import Foundation

enum TMDBConfig {
    /// Prefer `Info.plist` keys in production builds; fall back to environment for CI/dev.
    /// Keep these empty by default so the app still compiles without secrets.
    static let tmdbAPIKey: String = value(forEnv: "TMDB_API_KEY", infoPlistKey: "TMDBApiKey")
    static let omdbAPIKey: String = value(forEnv: "OMDB_API_KEY", infoPlistKey: "OMDBApiKey")
    static let supabaseURL: String = value(forEnv: "SUPABASE_URL", infoPlistKey: "SupabaseURL")
    static let supabaseAnonKey: String = value(forEnv: "SUPABASE_ANON_KEY", infoPlistKey: "SupabaseAnonKey")

    /// Optional fork-owned v2 table with a composite (media_type, tmdb_id) key.
    /// Empty by default: never write into an upstream cache implicitly.
    static let supabaseV2Table = value(forEnv: "SUPABASE_ENRICHMENT_V2_TABLE", infoPlistKey: "SupabaseEnrichmentV2Table")

    private static func value(forEnv envKey: String, infoPlistKey: String) -> String {
        if let v = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String, !v.isEmpty {
            return v
        }
        if let v = ProcessInfo.processInfo.environment[envKey], !v.isEmpty {
            return v
        }
        return ""
    }
}
