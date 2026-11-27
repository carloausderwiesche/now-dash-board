// The sites to block, as the person edits them, and the host names each one
// really uses. A site like YouTube is several names (`youtube.com`,
// `www.youtube.com`, `m.youtube.com`, `youtu.be`), and blocking only the first
// would leave the others open.

import Foundation

public enum BlockedSites {
    /// The default list: one entry per site, the base name people know.
    public static let defaults = ["youtube.com", "instagram.com", "x.com", "reddit.com", "facebook.com", "tiktok.com"]

    /// Most sites the person can list.
    public static let maxEntries = 50

    /// The names each well-known site uses (the base name is the key).
    static let known: [String: [String]] = [
        "youtube.com": ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be", "www.youtu.be"],
        "instagram.com": ["instagram.com", "www.instagram.com"],
        "x.com": ["x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"],
        "twitter.com": ["x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"],
        "reddit.com": ["reddit.com", "www.reddit.com", "old.reddit.com", "m.reddit.com"],
        "facebook.com": ["facebook.com", "www.facebook.com", "m.facebook.com", "fb.com", "www.fb.com"],
        "tiktok.com": ["tiktok.com", "www.tiktok.com", "m.tiktok.com"],
    ]

    /// What one entry typed by the person means as a host name: a known site gives all its names,
    /// anything else gives the name and its `www.` form. Invalid entries give nothing.
    ///
    /// The person may type `https://www.example.com/path` or `Example.com`: the address is cut
    /// down to its host name first.
    public static func names(for entry: String) -> [String] {
        guard let host = hostName(from: entry) else { return [] }
        let base = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if let names = known[base] { return names }
        return HostsBlock.sanitize([base, "www.\(base)"])
    }

    /// Every name for a list of entries, valid, without duplicates and sorted.
    public static func domains(for entries: [String]) -> [String] {
        HostsBlock.sanitize(entries.prefix(maxEntries).flatMap(names(for:)))
    }

    /// The entry as it is stored: the plain host name without `www.`, or nil if it isn't a usable host name.
    public static func normalized(_ entry: String) -> String? {
        guard let host = hostName(from: entry) else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Adds an entry to a list (normalised, no duplicates, at most `maxEntries`). Returns the list unchanged if it isn't valid.
    public static func adding(_ entry: String, to list: [String]) -> [String] {
        guard let name = normalized(entry), !list.contains(name), list.count < maxEntries else { return list }
        return list + [name]
    }

    /// The host name inside what was typed, lower case, or nil.
    /// `https://www.Example.com:8080/a?b#c` → `www.example.com`.
    static func hostName(from entry: String) -> String? {
        var text = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = text.range(of: "://") { text = String(text[range.upperBound...]) }
        // Cut at the first thing that ends a host name in an address.
        if let end = text.firstIndex(where: { "/?#:".contains($0) }) { text = String(text[..<end]) }
        if text.hasSuffix(".") { text.removeLast() }
        return HostsBlock.isValidDomain(text) ? text : nil
    }
}
