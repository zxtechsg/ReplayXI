import Foundation

/// One original player identity, with independent geometry and skin bindings.
/// Source-bound Blender build; native mesh counts and decoded atlas pixels are audited.
enum ReplayTripoDiversityAssets {
    struct Resource: Sendable {
        let name: String
        let sha256: String
    }
    struct Skin: Sendable {
        let asset: Resource
        let contacts: Resource
        let sourceVertices: Int
        let importedVertices: Int
        let triangles: Int
    }

    static let sourceSHA256 = "2b25690666877f3e090d5ce4e5d8e30702d6d02f497e5511de4ba9d3df1dcfc3"
    static let textureSize = 1_024
    static let decodedTextureBytes = 3 * textureSize * textureSize * 4
    static let motion = Resource(name: "ReplayXITripoPlayerAMotion", sha256: "0ec69ffd45a2964c2ac174dcf7f82c8789476a7a6d72b4b8891bcd210836461d")
    static let near = Skin(
        asset: .init(name: "ReplayXITripoPlayerA", sha256: "81a424ee1638fef40a1379d00e95259c04eeb5204d96224d2ce17a694967eeb7"),
        contacts: .init(name: "ReplayXITripoPlayerAContactSurface", sha256: "3a9549fb890f44e0ce1e9b165073c336fcf9ee770dc35e4fdb462e4306e4fc73"),
        sourceVertices: 7_999, importedVertices: 7_999, triangles: 10_289)
    static let low = Skin(
        asset: .init(name: "ReplayXITripoPlayerALow", sha256: "06175656f9e7ea79592b31a511c17fa53bcc84ccf597ed09c462cb3282cacdc0"),
        contacts: .init(name: "ReplayXITripoPlayerALowContactSurface", sha256: "24ace84f76343654b8dca79cd9e72a047ec47dd2f2739a8dda6a28cbd6a47d8e"),
        sourceVertices: 2_590, importedVertices: 2_590, triangles: 2_744)
    /// Home, away, keeper order. Hashes cover decoded RGBA pixels.
    static let atlases: [Resource] = [
        .init(name: "ReplayXITripoPlayerAHome", sha256: "6f3a153e22a2c8a6de78bf72b3fa39bec9b699d8edef13c6df0ce828c1871f64"),
        .init(name: "ReplayXITripoPlayerAAway", sha256: "3f50a80cd465c4617f62d6531d0c587a2a85ee8cf2110913d1096dacf44607bf"),
        .init(name: "ReplayXITripoPlayerAKeeper", sha256: "6e33cdd543d44f5dc0370cb9ec6d5e9819cb6928d5cb22cf6bfafc295241d78b")
    ]
}
