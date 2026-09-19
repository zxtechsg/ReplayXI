import SwiftUI

/// A shared, inline library: no popovers or modal presentation in immersive space.
struct ReplayReviewLibraryView: View {
    @Environment(ReplayStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var action: LibraryAction?
    @State private var reviewName = ""
    @State private var pendingSaveState: SavedReplayState?
    let close: () -> Void

    private var usesAccessibilityText: Bool { dynamicTypeSize.isAccessibilitySize }
    private var layout: ReplayReviewLibraryLayout { .resolve(usesAccessibilityText: usesAccessibilityText) }

    private enum LibraryAction: Equatable {
        case save
        case rename(UUID)
        case delete(UUID)
        case restore(SavedReplayReview)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerLayout {
                HStack(alignment: .top, spacing: 12) {
                    Button(action: close) {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close saved reviews")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saved reviews").font(.title3.bold())
                        Text(store.reviewSaveStatus)
                            .font(.subheadline)
                            .foregroundStyle(store.reviewSaveBlockReason == nil ? Color.secondary : ReplayTheme.orange)
                            .lineLimit(usesAccessibilityText ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    reviewName = store.selectedScenario.title
                    pendingSaveState = store.makeSavedReviewState()
                    action = .save
                } label: {
                    Label("Save a copy", systemImage: "square.and.arrow.down")
                        .frame(minHeight: 44)
                }
                .tint(ReplayTheme.signal)
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.black)
                .disabled(!store.canSaveReview || action != nil)
                .accessibilityHint(store.reviewSaveBlockReason ?? "Saves this moment, player view, and annotations on this device")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let action {
                        actionRow(action)
                    } else {
                        reviewList
                    }
                    if !store.canRestoreSavedReview {
                        Label("Finish editing or leave positioning mode to load a review.", systemImage: "lock")
                            .font(.subheadline).foregroundStyle(ReplayTheme.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.trailing, 6)
            }
            .frame(height: layout.contentHeight)
            .id(action == nil)
            .scrollIndicators(.visible)
            .accessibilityHint("Scroll for saved reviews or confirmation controls")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(12)
        .onChange(of: store.canRestoreSavedReview) { _, allowed in
            // Editing or positioning must not leave a stale load confirmation active.
            if !allowed, case .restore = action { action = nil }
        }
    }

    private var headerLayout: AnyLayout {
        usesAccessibilityText ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }

    private var reviewList: some View {
        LazyVStack(spacing: 8) {
            if let autosave = store.autosavedReview {
                reviewRow(autosave, isAutosave: true)
            }
            ForEach(store.savedReviews) { review in
                reviewRow(review, isAutosave: false)
            }
            if store.savedReviews.isEmpty {
                Label("Save key moments with your marks and player view.", systemImage: "bookmark")
                    .font(.body).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            }
        }
    }

    private func reviewRow(_ review: SavedReplayReview, isAutosave: Bool) -> some View {
        let rowLayout = usesAccessibilityText ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return rowLayout {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isAutosave ? "clock.arrow.circlepath" : "bookmark.fill")
                    .font(.title3).foregroundStyle(ReplayTheme.cyan)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isAutosave ? "Last session" : review.name)
                        .font(.headline).lineLimit(usesAccessibilityText ? nil : 1)
                    Text(summary(review))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(usesAccessibilityText ? nil : 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            ReplayReviewActionButtons {
                Button("Load") { action = .restore(review) }
                    .frame(minHeight: 60)
                    .disabled(!store.canRestoreSavedReview)
                    .accessibilityLabel("Load \(isAutosave ? "last session" : review.name)")

                if !isAutosave {
                    Button {
                        reviewName = review.name
                        action = .rename(review.id)
                    } label: {
                        Image(systemName: "pencil").frame(width: 40, height: 44)
                    }
                    .accessibilityLabel("Rename \(review.name)")
                    Button {
                        action = .delete(review.id)
                    } label: {
                        Image(systemName: "trash").frame(width: 40, height: 44)
                    }
                    .accessibilityLabel("Delete \(review.name)")
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func actionRow(_ action: LibraryAction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch action {
            case .save, .rename:
                Text(action == .save ? "Name this review" : "Rename review").font(.headline)
                if action == .save, let pendingSaveState {
                    Text("Moment captured at \(formattedTime(pendingSaveState.playhead))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                TextField("Review name", text: $reviewName)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .onChange(of: reviewName) { _, value in
                        reviewName = String(value.prefix(ReplayReviewLibrary.maximumNameLength))
                    }
                    .onSubmit { commitName(action) }
                    .accessibilityLabel("Review name")
                ReplayReviewActionButtons {
                    Button("Cancel") { self.action = nil }.frame(minHeight: 60)
                    Button("Save") { commitName(action) }
                        .frame(minHeight: 60)
                        .disabled(reviewName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (action == .save && !store.canSaveReview))
                }
            case .delete(let id):
                confirmation(
                    "Delete this saved review?",
                    detail: "The current replay and last session are kept.",
                    button: "Delete", destructive: true
                ) {
                    if store.deleteSavedReview(id: id) { self.action = nil }
                }
            case .restore(let review):
                confirmation(
                    "Load this review?",
                    detail: "Replaces your current marks and view. Save a copy first to keep them.",
                    button: "Load paused", destructive: false
                ) {
                    let restored = store.restoreReview(review)
                    if restored { self.action = nil }
                }
                .disabled(!store.canRestoreSavedReview)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .background(ReplayTheme.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    private func confirmation(
        _ title: String, detail: String, button: String, destructive: Bool,
        perform: @escaping () -> Void
    ) -> some View {
        ReplayReviewInlineConfirmation(title: title, detail: detail, button: button, destructive: destructive,
                                       cancel: { action = nil }, confirm: perform)
    }

    private func commitName(_ action: LibraryAction) {
        let succeeded: Bool
        switch action {
        case .save: succeeded = store.saveReview(named: reviewName, state: pendingSaveState)
        case .rename(let id): succeeded = store.renameSavedReview(id: id, name: reviewName)
        default: return
        }
        if succeeded {
            self.action = nil
            pendingSaveState = nil
        }
    }

    private func summary(_ review: SavedReplayReview) -> String {
        let scenario = store.scenarios.first { $0.id == review.state.scenarioID }
        let time = formattedTime(review.state.playhead)
        let count = review.state.marks.count
        let date = review.savedAt.formatted(date: .abbreviated, time: .shortened)
        return "\(scenario?.title ?? "Replay") · \(time) · \(count) marks · \(date)"
    }

    private func formattedTime(_ playhead: TimeInterval) -> String {
        let seconds = Int(playhead)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct ReplayReviewLibraryLayout: Equatable {
    let sheetWidth: CGFloat
    let sheetHeight: CGFloat
    let contentHeight: CGFloat

    static func resolve(usesAccessibilityText: Bool) -> Self {
        usesAccessibilityText
            ? .init(sheetWidth: 960, sheetHeight: 860, contentHeight: 380)
            : .init(sheetWidth: 820, sheetHeight: 440, contentHeight: 220)
    }
}

struct ReplayReviewActionButtons<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12, content: content).fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8, content: content)
        }
    }
}

/// The same inline confirmation is used by dashboard and immersive review lists.
struct ReplayReviewInlineConfirmation: View {
    let title: String
    let detail: String
    let button: String
    let destructive: Bool
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ReplayReviewActionButtons {
                Button("Cancel", action: cancel).frame(minHeight: 60)
                Button(button, role: destructive ? .destructive : nil, action: confirm)
                    .frame(minHeight: 60)
            }
        }
    }
}
