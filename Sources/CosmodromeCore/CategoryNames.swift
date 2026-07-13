import Foundation

/// Human names for LSApplicationCategoryType values — the vocabulary of
/// auto-folders and suggested names for drag-created folders.
public enum CategoryNames {
    private static let names: [String: String] = [
        "business": "Business",
        "developer-tools": "Developer Tools",
        "education": "Education",
        "entertainment": "Entertainment",
        "finance": "Finance",
        "graphics-design": "Graphics & Design",
        "healthcare-fitness": "Health & Fitness",
        "lifestyle": "Lifestyle",
        "medical": "Medical",
        "music": "Music",
        "news": "News",
        "photography": "Photography",
        "productivity": "Productivity",
        "reference": "Reference",
        "social-networking": "Social",
        "sports": "Sports",
        "travel": "Travel",
        "utilities": "Utilities",
        "video": "Video",
        "weather": "Weather",
    ]

    /// "public.app-category.developer-tools" → "Developer Tools";
    /// every games subgenre collapses into "Games", like the iOS App Library.
    public static func displayName(for categoryType: String?) -> String? {
        guard let categoryType, !categoryType.isEmpty else { return nil }
        let key = categoryType.hasPrefix("public.app-category.")
            ? String(categoryType.dropFirst("public.app-category.".count))
            : categoryType
        guard !key.isEmpty else { return nil }
        if key == "games" || key.hasSuffix("-games") { return "Games" }
        if let known = names[key] { return known }
        return key.split(separator: "-").map(\.capitalized).joined(separator: " ")
    }
}
