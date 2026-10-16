import Foundation

/// Spends the chosen visual budget on neighbours of the reviewed player.
/// It does not change near/impact selection or the first-person close-rig cap.
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
        allowsFirstPerson: Bool = false,
        allowsShapeReplay: Bool = false
    ) -> State {
        let maximum = min(maximumTotal, ReplayPlayerDetail.maximumSquadSize)
        guard lowDetailIsReady,
              scenarioKind != .shapeLab || allowsShapeReplay,
              viewMode == .tacticalTable || viewMode == .touchline
                || (allowsFirstPerson && viewMode == .firstPerson),
              maximum > nearPlayerIDs.count,
              let origin = posesByPlayerID[perspectiveID]?.position,
              origin.x.isFinite, origin.z.isFinite
        else { return State() }

        let context = Context(scenarioID: scenarioID, perspectiveID: perspectiveID)
        let limit = maximum - nearPlayerIDs.count
        func isEligible(_ id: String, _ pose: PlayerPose) -> Bool {
            id != perspectiveID && !nearPlayerIDs.contains(id)
                && pose.position.x.isFinite && pose.position.z.isFinite
        }
        let eligibleCount = posesByPlayerID.reduce(into: 0) { count, entry in
            if isEligible(entry.key, entry.value) { count += 1 }
        }
        // The usual full-squad case needs no distance calculations or rank
        // churn: every valid non-near player fits. A stable ID order keeps
        // view changes and scrubbing independent of dictionary iteration.
        if eligibleCount <= limit {
            // Repeated full-squad frames keep the same immutable Array buffer.
            // Validate membership and strict ordering so malformed/stale state
            // cannot retain duplicates or consume an invalid player's slot.
            if previous.context == context, previous.playerIDs.count == eligibleCount {
                var last: String?
                let unchanged = previous.playerIDs.allSatisfy { id in
                    guard let pose = posesByPlayerID[id], isEligible(id, pose),
                          last.map({ $0 < id }) ?? true else { return false }
                    last = id
                    return true
                }
                if unchanged { return previous }
            }
            return State(context: context, playerIDs: posesByPlayerID.compactMap { id, pose in
                isEligible(id, pose) ? id : nil
            }.sorted())
        }
        var distances: [String: Float] = [:]
        distances.reserveCapacity(eligibleCount)
        for (id, pose) in posesByPlayerID where isEligible(id, pose) {
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
