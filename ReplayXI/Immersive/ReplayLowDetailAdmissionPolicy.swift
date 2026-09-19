import Foundation

/// Spends only spare existing skin slots on neighbours of the reviewed player.
/// It does not change near/impact selection or the first-person rig budget.
enum ReplayLowDetailAdmissionPolicy {
    static let switchMargin: Float = 1.25

    struct Context: Equatable {
        let scenarioID: String
        let perspectiveID: String
    }

    struct State: Equatable {
        var context: Context?
        var playerIDs: [String] = []
    }

    static func resolve(
        previous: State,
        scenarioID: String,
        scenarioKind: ExperienceKind,
        viewMode: ReplayViewMode,
        perspectiveID: String,
        posesByPlayerID: [String: PlayerPose],
        nearPlayerIDs: Set<String>,
        maximumTotal: Int,
        lowDetailIsReady: Bool,
        allowsFirstPerson: Bool = false
    ) -> State {
        guard lowDetailIsReady,
              scenarioKind != .shapeLab,
              viewMode == .tacticalTable || viewMode == .touchline
                || (allowsFirstPerson && viewMode == .firstPerson),
              maximumTotal > nearPlayerIDs.count,
              let origin = posesByPlayerID[perspectiveID]?.position,
              origin.x.isFinite, origin.z.isFinite
        else { return State() }

        let context = Context(scenarioID: scenarioID, perspectiveID: perspectiveID)
        let limit = maximumTotal - nearPlayerIDs.count
        var distances: [String: Float] = [:]
        distances.reserveCapacity(posesByPlayerID.count)
        for (id, pose) in posesByPlayerID
            where id != perspectiveID && !nearPlayerIDs.contains(id) {
            let distance = ReplayGeometry.distance(origin, pose.position)
            if distance.isFinite { distances[id] = distance }
        }
        func isNearer(_ lhs: String, _ rhs: String) -> Bool {
            let left = distances[lhs] ?? .greatestFiniteMagnitude
            let right = distances[rhs] ?? .greatestFiniteMagnitude
            return left == right ? lhs < rhs : left < right
        }
        let candidates = distances.keys.sorted(by: isNearer)
        var selected: [String] = []
        selected.reserveCapacity(min(limit, candidates.count))
        if previous.context == context {
            for id in previous.playerIDs
                where distances[id] != nil && !selected.contains(id) {
                selected.append(id)
            }
            if selected.count > limit {
                selected.sort(by: isNearer)
                selected.removeLast(selected.count - limit)
            }
        }
        for id in candidates where selected.count < limit && !selected.contains(id) {
            selected.append(id)
        }
        // Keep crossing neighbours stable. A clear challenger can replace the
        // farthest retained member; equal distances use a stable player ID.
        for candidate in candidates where !selected.contains(candidate) {
            guard let worst = selected.indices.max(by: {
                isNearer(selected[$0], selected[$1])
            }), let candidateDistance = distances[candidate],
               let worstDistance = distances[selected[worst]] else { continue }
            if candidateDistance + switchMargin < worstDistance {
                selected[worst] = candidate
            }
        }
        return State(context: context, playerIDs: selected)
    }
}
