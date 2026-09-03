import Foundation
import CoreTransferable
import GroupActivities

struct ReplayXIActivity: GroupActivity, Sendable {
    static let activityIdentifier = "com.humansbeforemachines.replayxi.review-room"

    let roomID: UUID
    let scenarioID: String
    let coachInstanceID: UUID

    init(roomID: UUID = UUID(), scenarioID: String, coachInstanceID: UUID) {
        self.roomID = roomID
        self.scenarioID = scenarioID
        self.coachInstanceID = coachInstanceID
    }

    var metadata: GroupActivityMetadata {
        get async {
            var metadata = GroupActivityMetadata()
            metadata.type = .learnTogether
            metadata.title = "Replay XI review room"
            metadata.subtitle = "See the play they saw"
            metadata.sceneAssociationBehavior = .content("ReplayXIReviewRoom")
            metadata.lifetimePolicy = .endsWhenInitiatorLeaves
            return metadata
        }
    }
}

extension ReplayXIActivity: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        GroupActivityTransferRepresentation { activity in
            activity
        }
    }
}
