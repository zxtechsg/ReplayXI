import SwiftUI

/// The deliberately reduced teaching picture used by Shape Focus.
///
/// Keeping this projection independent from the Canvas makes the promise easy
/// to test: Shape Focus is never an all-22 replay. It is the three coached roles,
/// one relevant defender, and a ball that stays with the #8 source.
struct ShapeFocusPreviewPresentation: Equatable {
    struct Player: Equatable, Identifiable {
        let track: PlayerTrack
        let position: PitchPoint
        let isSource: Bool
        let isDefender: Bool

        var id: String { track.id }
    }

    let stage: ShapeFocusStage
    let players: [Player]
    let trianglePoints: [PitchPoint]
    let targetPoints: [PitchPoint]
    let ballPosition: PitchPoint
    let sourcePlayerID: String
    let defenderPlayerID: String?

    static func make(
        scenario: ReplayScenario,
        time: TimeInterval,
        stage: ShapeFocusStage
    ) -> ShapeFocusPreviewPresentation? {
        guard scenario.kind == .shapeLab else { return nil }

        let targetsByPlayerID = Dictionary(
            uniqueKeysWithValues: scenario.formationTargets.map { ($0.playerID, $0) }
        )
        let featuredTracks = scenario.formationTargets.compactMap { target in
            scenario.player(id: target.playerID)
        }
        guard featuredTracks.count == scenario.formationTargets.count,
              let source = featuredTracks.first(where: { $0.shirtNumber == 8 })
                ?? scenario.player(id: scenario.defaultPerspectiveID) else {
            return nil
        }

        func presentationPosition(for player: PlayerTrack) -> PitchPoint {
            if stage == .ideal, let target = targetsByPlayerID[player.id] {
                return target.position
            }
            return player.presentationPose(at: time).position
        }

        let defenderID = primaryDefenderID(in: scenario, time: time)
        var players = featuredTracks.map { player in
            Player(
                track: player,
                position: presentationPosition(for: player),
                isSource: player.id == source.id,
                isDefender: false
            )
        }
        if let defenderID, let defender = scenario.player(id: defenderID) {
            players.append(
                Player(
                    track: defender,
                    position: defender.presentationPose(at: time).position,
                    isSource: false,
                    isDefender: true
                )
            )
        }

        let trianglePoints = featuredTracks.map(presentationPosition)
        let sourcePosition = presentationPosition(for: source)

        return ShapeFocusPreviewPresentation(
            stage: stage,
            players: players,
            trianglePoints: trianglePoints,
            targetPoints: stage == .ideal ? scenario.formationTargets.map(\.position) : [],
            // Match the immersive tabletop: the ball sits just off #8's boot
            // so both the source player and ball stay legible.
            ballPosition: PitchPoint(x: sourcePosition.x + 0.55, z: sourcePosition.z + 0.25),
            sourcePlayerID: source.id,
            defenderPlayerID: defenderID
        )
    }

    private static func primaryDefenderID(
        in scenario: ReplayScenario,
        time: TimeInterval
    ) -> String? {
        let referencePoint: PitchPoint
        if let danger = scenario.coachMarks.first(where: { $0.kind == .danger }) {
            referencePoint = danger.start.interpolated(to: danger.end, fraction: 0.5)
        } else {
            guard !scenario.formationTargets.isEmpty else { return nil }
            referencePoint = PitchPoint(
                x: scenario.formationTargets.map(\.position.x).reduce(0, +)
                    / Float(scenario.formationTargets.count),
                z: scenario.formationTargets.map(\.position.z).reduce(0, +)
                    / Float(scenario.formationTargets.count)
            )
        }

        return scenario.awayPlayers.min {
            ReplayGeometry.distance($0.presentationPose(at: time).position, referencePoint)
                < ReplayGeometry.distance($1.presentationPose(at: time).position, referencePoint)
        }?.id
    }
}

struct TacticalPreview: View {
    let scenario: ReplayScenario
    let time: TimeInterval
    var marks: [CoachMark]? = nil
    var highlightedPlayerID: String?
    var showsSightCones = false
    var shapeFocusStage: ShapeFocusStage? = nil

    private var shapePresentation: ShapeFocusPreviewPresentation? {
        guard scenario.kind == .shapeLab else { return nil }
        return ShapeFocusPreviewPresentation.make(
            scenario: scenario,
            time: time,
            stage: shapeFocusStage ?? .problem
        )
    }

    static func resolvedMarkGeometry(
        for mark: CoachMark,
        in scenario: ReplayScenario,
        at time: TimeInterval
    ) -> ResolvedCoachMarkGeometry {
        mark.resolvedGeometry(in: scenario, at: time)
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let pitchRect = CGRect(x: 18, y: 18, width: size.width - 36, height: size.height - 36)
                if let shapePresentation {
                    drawShapeFocus(
                        shapePresentation,
                        in: &context,
                        rect: pitchRect
                    )
                } else {
                    drawPitch(in: &context, rect: pitchRect)
                    drawMarks(in: &context, rect: pitchRect)

                    for player in scenario.players {
                        let pose = player.presentationPose(at: time)
                        let point = screenPoint(for: pose.position, in: pitchRect)
                        if showsSightCones, player.id == highlightedPlayerID {
                            drawSightCone(in: &context, origin: point, facingDegrees: pose.facingDegrees, team: player.team)
                        }
                        drawPlayer(
                            player,
                            point: point,
                            highlighted: player.id == highlightedPlayerID,
                            in: &context
                        )
                    }

                    let ball = scenario.ball.pose(at: time)
                    let ballPoint = screenPoint(for: ball.position, in: pitchRect)
                    drawBall(in: &context, at: ballPoint)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [ReplayTheme.pitch, Color(red: 0.02, green: 0.08, blue: 0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay(alignment: .topLeading) {
                if let shapePresentation {
                    HStack(spacing: 8) {
                        StatusPill(
                            text: shapePresentation.stage == .problem
                                ? "Problem • recorded spacing"
                                : "Ideal • coach correction",
                            systemImage: shapePresentation.stage.systemImage,
                            color: shapePresentation.stage == .problem
                                ? ReplayTheme.orange
                                : ReplayTheme.signal
                        )
                        StatusPill(
                            text: "#8 is the source",
                            systemImage: "soccerball",
                            color: .white
                        )
                    }
                    .padding(28)
                } else {
                    HStack(spacing: 8) {
                        StatusPill(text: "Tracked replay", systemImage: "dot.scope", color: ReplayTheme.cyan)
                        if showsSightCones {
                            StatusPill(text: "Authored facing", systemImage: "viewfinder", color: ReplayTheme.signal)
                        }
                        Text(formatTime(time))
                            .font(.caption.monospacedDigit().weight(.black))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.42), in: Capsule())
                    }
                    .padding(28)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let shapePresentation {
                    Text(
                        shapePresentation.stage == .problem
                            ? "ONE COVER SHADOW • TWO BLOCKED EXITS"
                            : "THREE HEIGHTS • TWO OPEN EXITS"
                    )
                    .font(.caption2.monospaced().weight(.black))
                    .foregroundStyle(
                        shapePresentation.stage == .problem
                            ? ReplayTheme.orange
                            : ReplayTheme.signal
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.48), in: Capsule())
                    .padding(28)
                } else if showsSightCones {
                    Text("DIRECTION ESTIMATE • NOT EYE GAZE")
                        .font(.caption2.monospaced().weight(.black))
                        .foregroundStyle(.white.opacity(0.58))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.42), in: Capsule())
                        .padding(28)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        if let shapePresentation {
            let result = shapePresentation.stage == .problem
                ? "one defender screens two passing options"
                : "three distinct heights create two passing options"
            return "Shape Focus \(shapePresentation.stage.title) diagram: \(result). Number eight is the source."
        }
        return "Tactical preview of \(scenario.title) at \(formatTime(time))"
    }

    private func drawShapeFocus(
        _ presentation: ShapeFocusPreviewPresentation,
        in context: inout GraphicsContext,
        rect: CGRect
    ) {
        drawShapePitch(in: &context, rect: rect)
        let color = presentation.stage == .problem ? ReplayTheme.orange : ReplayTheme.signal

        if presentation.stage == .ideal {
            for target in presentation.targetPoints {
                let point = shapeScreenPoint(for: target, in: rect)
                let outer = CGRect(x: point.x - 17, y: point.y - 17, width: 34, height: 34)
                let inner = CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)
                context.fill(Path(ellipseIn: outer), with: .color(color.opacity(0.10)))
                context.stroke(
                    Path(ellipseIn: outer),
                    with: .color(color.opacity(0.72)),
                    style: StrokeStyle(lineWidth: 2, dash: [5, 4])
                )
                context.stroke(Path(ellipseIn: inner), with: .color(color.opacity(0.30)), lineWidth: 1)
            }
        }

        let triangle = presentation.trianglePoints.map { shapeScreenPoint(for: $0, in: rect) }
        if triangle.count == 3 {
            var fill = Path()
            fill.move(to: triangle[0])
            fill.addLine(to: triangle[1])
            fill.addLine(to: triangle[2])
            fill.closeSubpath()
            context.fill(fill, with: .color(color.opacity(0.10)))
            context.stroke(
                fill,
                with: .color(color.opacity(0.92)),
                style: StrokeStyle(
                    lineWidth: presentation.stage == .problem ? 4 : 5,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: presentation.stage == .problem ? [9, 6] : []
                )
            )
        }

        if presentation.stage == .problem,
           let defender = presentation.players.first(where: \.isDefender) {
            let defenderPoint = shapeScreenPoint(for: defender.position, in: rect)
            let sourcePoint = shapeScreenPoint(for: presentation.ballPosition, in: rect)
            var shadow = Path()
            shadow.move(to: defenderPoint)
            shadow.addLine(to: sourcePoint)
            context.stroke(
                shadow,
                with: .color(ReplayTheme.danger.opacity(0.72)),
                style: StrokeStyle(lineWidth: 12, lineCap: .round, dash: [2, 8])
            )
        }

        for player in presentation.players {
            drawShapePlayer(
                player,
                at: shapeScreenPoint(for: player.position, in: rect),
                stageColor: color,
                in: &context
            )
        }

        drawBall(
            in: &context,
            at: shapeScreenPoint(for: presentation.ballPosition, in: rect),
            radius: 6
        )
    }

    private func drawShapePitch(in context: inout GraphicsContext, rect: CGRect) {
        context.fill(Path(rect), with: .color(.white.opacity(0.018)))
        var grid = Path()
        for column in 1..<4 {
            let x = rect.minX + (CGFloat(column) * rect.width / 4)
            grid.move(to: CGPoint(x: x, y: rect.minY))
            grid.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for row in 1..<4 {
            let y = rect.minY + (CGFloat(row) * rect.height / 4)
            grid.move(to: CGPoint(x: rect.minX, y: y))
            grid.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        context.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 1)

        var boundary = Path()
        boundary.addRect(rect)
        context.stroke(boundary, with: .color(.white.opacity(0.38)), lineWidth: 1.25)

        var touchline = Path()
        touchline.move(to: CGPoint(x: rect.maxX - 2, y: rect.minY))
        touchline.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.maxY))
        context.stroke(touchline, with: .color(.white.opacity(0.74)), lineWidth: 3)

        context.draw(
            Text("ATTACK ↑").font(.caption2.monospaced().weight(.black)).foregroundStyle(.white.opacity(0.48)),
            at: CGPoint(x: rect.maxX - 48, y: rect.maxY - 15)
        )
        context.draw(
            Text("RIGHT CHANNEL").font(.caption2.monospaced().weight(.black)).foregroundStyle(.white.opacity(0.34)),
            at: CGPoint(x: rect.minX + 58, y: rect.maxY - 15)
        )
    }

    private func drawShapePlayer(
        _ player: ShapeFocusPreviewPresentation.Player,
        at point: CGPoint,
        stageColor: Color,
        in context: inout GraphicsContext
    ) {
        let playerColor = player.track.team == .home ? ReplayTheme.cyan : ReplayTheme.danger
        let outerRadius: CGFloat = player.isSource ? 14 : 12
        if player.isSource {
            context.fill(
                Path(ellipseIn: CGRect(
                    x: point.x - outerRadius - 4,
                    y: point.y - outerRadius - 4,
                    width: (outerRadius + 4) * 2,
                    height: (outerRadius + 4) * 2
                )),
                with: .color(stageColor.opacity(0.18))
            )
            context.stroke(
                Path(ellipseIn: CGRect(
                    x: point.x - outerRadius - 4,
                    y: point.y - outerRadius - 4,
                    width: (outerRadius + 4) * 2,
                    height: (outerRadius + 4) * 2
                )),
                with: .color(stageColor),
                lineWidth: 2.5
            )
        }

        context.fill(
            Path(ellipseIn: CGRect(
                x: point.x - outerRadius,
                y: point.y - outerRadius,
                width: outerRadius * 2,
                height: outerRadius * 2
            )),
            with: .color(playerColor)
        )
        context.stroke(
            Path(ellipseIn: CGRect(
                x: point.x - outerRadius,
                y: point.y - outerRadius,
                width: outerRadius * 2,
                height: outerRadius * 2
            )),
            with: .color(.black.opacity(0.55)),
            lineWidth: 1.5
        )
        context.draw(
            Text("\(player.track.shirtNumber)")
                .font(.caption.monospacedDigit().weight(.black))
                .foregroundStyle(.black),
            at: point
        )

        let roleText = player.isDefender
            ? "DEFENDER  #\(player.track.shirtNumber)"
            : "#\(player.track.shirtNumber)  \(shortShapeRole(player.track.role))"
        context.draw(
            Text(roleText)
                .font(.caption2.monospaced().weight(.black))
                .foregroundStyle(.white.opacity(0.92)),
            at: CGPoint(x: point.x, y: point.y + outerRadius + 13),
            anchor: .center
        )
    }

    private func drawBall(
        in context: inout GraphicsContext,
        at point: CGPoint,
        radius: CGFloat = 4
    ) {
        context.fill(
            Path(ellipseIn: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )),
            with: .color(.white)
        )
        context.stroke(
            Path(ellipseIn: CGRect(
                x: point.x - radius - 1.5,
                y: point.y - radius - 1.5,
                width: (radius + 1.5) * 2,
                height: (radius + 1.5) * 2
            )),
            with: .color(.black.opacity(0.65)),
            lineWidth: 1
        )
    }

    private func shapeScreenPoint(for point: PitchPoint, in rect: CGRect) -> CGPoint {
        // A fixed coaching-board viewport keeps Problem and Ideal directly
        // comparable instead of auto-zooming the correction into a new frame.
        let xRange: ClosedRange<Float> = 8...34
        let zRange: ClosedRange<Float> = 13...33
        let horizontal = CGFloat(
            min(max((point.x - xRange.lowerBound) / (xRange.upperBound - xRange.lowerBound), 0), 1)
        )
        let vertical = CGFloat(
            min(max((point.z - zRange.lowerBound) / (zRange.upperBound - zRange.lowerBound), 0), 1)
        )
        let insetRect = rect.insetBy(dx: 34, dy: 34)
        return CGPoint(
            x: insetRect.minX + horizontal * insetRect.width,
            y: insetRect.maxY - vertical * insetRect.height
        )
    }

    private func shortShapeRole(_ role: String) -> String {
        role
            .replacingOccurrences(of: "Right ", with: "R ")
            .replacingOccurrences(of: "Left ", with: "L ")
            .uppercased()
    }

    private func drawPitch(in context: inout GraphicsContext, rect: CGRect) {
        var lines = Path()
        lines.addRect(rect)
        lines.move(to: CGPoint(x: rect.midX, y: rect.minY))
        lines.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        lines.addEllipse(in: CGRect(x: rect.midX - 31, y: rect.midY - 31, width: 62, height: 62))
        lines.addRect(CGRect(x: rect.midX - 72, y: rect.minY, width: 144, height: 62))
        lines.addRect(CGRect(x: rect.midX - 72, y: rect.maxY - 62, width: 144, height: 62))
        context.stroke(lines, with: .color(.white.opacity(0.44)), lineWidth: 1.25)

        for index in 0..<8 where index.isMultiple(of: 2) {
            let stripe = CGRect(
                x: rect.minX + (CGFloat(index) * rect.width / 8),
                y: rect.minY,
                width: rect.width / 8,
                height: rect.height
            )
            context.fill(Path(stripe), with: .color(.white.opacity(0.018)))
        }
    }

    private func drawMarks(in context: inout GraphicsContext, rect: CGRect) {
        for mark in (marks ?? scenario.coachMarks) where mark.isVisible(at: time) {
            let geometry = Self.resolvedMarkGeometry(
                for: mark,
                in: scenario,
                at: time
            )
            let start = screenPoint(for: geometry.start, in: rect)
            let end = screenPoint(for: geometry.end, in: rect)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            let color: Color = mark.kind == .danger ? ReplayTheme.danger : mark.kind == .pass ? ReplayTheme.cyan : ReplayTheme.orange
            context.stroke(path, with: .color(color.opacity(0.82)), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: mark.kind == .danger ? [5, 5] : []))
            context.fill(Path(ellipseIn: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10)), with: .color(color))
        }
    }

    private func drawPlayer(_ player: PlayerTrack, point: CGPoint, highlighted: Bool, in context: inout GraphicsContext) {
        let teamColor = player.team == .home ? ReplayTheme.cyan : ReplayTheme.danger
        if highlighted {
            context.stroke(
                Path(ellipseIn: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24)),
                with: .color(ReplayTheme.signal),
                lineWidth: 3
            )
        }
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)),
            with: .color(teamColor)
        )
        context.stroke(
            Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)),
            with: .color(.black.opacity(0.45)),
            lineWidth: 1
        )
        if highlighted {
            context.draw(
                Text("\(player.shirtNumber)").font(.caption2.monospacedDigit().weight(.black)).foregroundStyle(.black),
                at: point
            )
        }
    }

    private func drawSightCone(in context: inout GraphicsContext, origin: CGPoint, facingDegrees: Float, team: FootballTeam) {
        let radians = CGFloat((facingDegrees - 90) * .pi / 180)
        let length: CGFloat = 48
        let spread: CGFloat = 0.36
        let left = CGPoint(x: origin.x + cos(radians - spread) * length, y: origin.y + sin(radians - spread) * length)
        let right = CGPoint(x: origin.x + cos(radians + spread) * length, y: origin.y + sin(radians + spread) * length)
        var cone = Path()
        cone.move(to: origin)
        cone.addLine(to: left)
        cone.addLine(to: right)
        cone.closeSubpath()
        context.fill(cone, with: .color((team == .home ? ReplayTheme.cyan : ReplayTheme.danger).opacity(0.09)))
    }

    private func screenPoint(for point: PitchPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.midX + (CGFloat(point.x / 34) * rect.width / 2),
            y: rect.midY - (CGFloat(point.z / 52.5) * rect.height / 2)
        )
    }

    private func formatTime(_ value: TimeInterval) -> String {
        let seconds = max(0, value)
        return String(format: "00:%05.2f", seconds)
    }
}
