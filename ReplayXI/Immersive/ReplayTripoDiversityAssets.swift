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
        asset: .init(name: "ReplayXITripoPlayerA", sha256: "688434ce9398f7fdcda6480b09f6a80c281f754a3bad8591d83084699ecbab26"),
        contacts: .init(name: "ReplayXITripoPlayerAContactSurface", sha256: "20cd8157804c9bf63f0f227c3bc48ea0e33758dc5f66f41ab77d3759c9ff5c28"),
        sourceVertices: 7_999, importedVertices: 7_999, triangles: 10_289)
    static let low = Skin(
        asset: .init(name: "ReplayXITripoPlayerALow", sha256: "a35f7e7cdca279cbc3e8978dbced568b494f932d88f6925d704707609756879e"),
        contacts: .init(name: "ReplayXITripoPlayerALowContactSurface", sha256: "0199ce5faed7df86281cddb4599c77c3dfcb6f6c34cb7e5052887d77eddb7576"),
        sourceVertices: 2_590, importedVertices: 2_590, triangles: 2_744)
    /// Home, away, keeper order. Hashes cover decoded RGBA pixels.
    static let atlases: [Resource] = [
        .init(name: "ReplayXITripoPlayerAHome", sha256: "6f3a153e22a2c8a6de78bf72b3fa39bec9b699d8edef13c6df0ce828c1871f64"),
        .init(name: "ReplayXITripoPlayerAAway", sha256: "3f50a80cd465c4617f62d6531d0c587a2a85ee8cf2110913d1096dacf44607bf"),
        .init(name: "ReplayXITripoPlayerAKeeper", sha256: "6e33cdd543d44f5dc0370cb9ec6d5e9819cb6928d5cb22cf6bfafc295241d78b")
    ]
}
