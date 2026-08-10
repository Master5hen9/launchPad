import AppKit
import Observation
import SwiftUI

/// Fullscreen Launchpad content, displayed inside a blurred overlay window.
public struct LaunchpadView: View {
    private let onDismiss: () -> Void
    private let onOpenSettings: () -> Void
    private let screenSize: CGSize
    @State private var viewModel = ContentViewModel()
    @State private var appeared = false
    @State private var scroller = PageScroller()
    @State private var folderBeingRenamed: LaunchpadFolder?
    @State private var renameDraft = ""
    @State private var folderBeingDeleted: LaunchpadFolder?
    @State private var draggedItem: LaunchpadItem?
    @State private var dragLocation: CGPoint = .zero
    @State private var dragEdgeZone: DragEdgeZone?
    @State private var isPagingDrag = false
    /// Measured cell frames (item id → frame in its page's coordinate space).
    @State private var cellFrames: [String: CGRect] = [:]
    /// True once the main grid has been shown; returning from a folder should
    /// not replay the full fly-in entrance animation.
    @State private var gridHasAppeared = false
    @State private var keyMonitor: Any?
    @State private var selectedItemID: String?
    @State private var selectedFolderAppID: String?
    @State private var gridSize: CGSize = .zero
    @FocusState private var searchFocused: Bool
    /// Jiggle (uninstall/hide) mode: icons wobble and apps show a manage badge.
    @State private var isJiggleMode = false
    /// The app whose uninstall/hide dialog is currently open.
    @State private var appBeingManaged: AppRecord?
    /// Set when moving an app to the Trash fails.
    @State private var uninstallError: String?
    /// Observes app-directory changes so an open Launchpad refreshes when
    /// apps are installed or removed.
    @State private var directoryChangeObserver: (any NSObjectProtocol)?

    public init(
        onDismiss: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void = {},
        screenSize: CGSize? = nil
    ) {
        self.onDismiss = onDismiss
        self.onOpenSettings = onOpenSettings
        self.screenSize = screenSize ?? NSScreen.main?.frame.size ?? CGSize(width: 1470, height: 956)
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    // Inside a folder, empty clicks should not dismiss the
                    // whole Launchpad (the back button / Esc closes the folder).
                    if isJiggleMode {
                        exitJiggleMode()
                    } else if viewModel.openFolderID == nil {
                        onDismiss()
                    }
                }

            // Subtle edge vignette for depth, like the original Launchpad's
            // slightly darker edges.
            Rectangle()
                .fill(
                    RadialGradient(
                        colors: [.clear, .black.opacity(0.3)],
                        center: .center,
                        startRadius: 250,
                        endRadius: 1400
                    )
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                navBar
                    .padding(.top, 64)
                    .padding(.bottom, 10)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.35), value: appeared)

                content
            }
        }
        .task {
            await viewModel.loadAppsIfNeeded()
            installDirectoryChangeObserver()
        }
        .onAppear {
            scroller.installMonitor()
            installKeyMonitor()
            searchFocused = true
            appeared = true
        }
        .onDisappear {
            scroller.stopMonitor()
            removeKeyMonitor()
            removeDirectoryChangeObserver()
        }
        .onChange(of: viewModel.filteredItems.map(\.id)) { _, newIDs in
            if let selected = selectedItemID, newIDs.contains(selected) {
                return
            }
            let queryEmpty = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            selectedItemID = queryEmpty ? nil : newIDs.first
        }
        .onChange(of: viewModel.filteredOpenFolderApps.map(\.id)) { _, newIDs in
            if let selected = selectedFolderAppID, newIDs.contains(selected) {
                return
            }
            let queryEmpty = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            selectedFolderAppID = queryEmpty ? nil : newIDs.first
        }
        .alert("重命名文件夹", isPresented: renameAlertPresented) {
            TextField("文件夹名称", text: $renameDraft)
            Button("确定") {
                confirmRename()
            }
            Button("取消", role: .cancel) {}
        }
        .alert("删除文件夹", isPresented: deleteAlertPresented) {
            Button("删除", role: .destructive) {
                confirmDelete()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("文件夹里的应用会移回启动台网格。")
        }
        .alert(
            Text(String(format: NSLocalizedString("管理「%@」", comment: ""), appBeingManaged?.name ?? "")),
            isPresented: manageAlertPresented
        ) {
            if let app = appBeingManaged {
                if viewModel.canUninstall(app) {
                    Button("移到废纸篓", role: .destructive) {
                        confirmUninstall(app)
                    }
                }
                Button("隐藏应用") {
                    confirmHide(app)
                }
                Button("取消", role: .cancel) {}
            }
        } message: {
            Text(manageMessage)
        }
        .alert("无法卸载", isPresented: uninstallErrorPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(uninstallError ?? "")
        }
    }

    // MARK: - Search

    private var navBar: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            searchRow
            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(height: 1)
                .padding(.horizontal, 18)
            categoryRow
            Spacer(minLength: 8)
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.14))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        }
        .frame(width: 440, height: navBarHeight)
    }

    /// Height that keeps the nav bar's aspect ratio identical to the screen's,
    /// at a fixed width of 440.
    private var navBarHeight: CGFloat {
        guard screenSize.width > 0 else { return 78 }
        return 440 * screenSize.height / screenSize.width
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            TextField("搜索应用", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .tint(.white)
                .focused($searchFocused)
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var categoryRow: some View {
        HStack(spacing: 0) {
            ForEach(AppCategory.allCases) { category in
                let isSelected = viewModel.category == category
                Button {
                    viewModel.category = category
                } label: {
                    Text(category.localizedName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? .black : .white.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
            }
        }
        .animation(.easeOut(duration: 0.15), value: viewModel.category)
    }

    // MARK: - Content switching

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView("正在加载应用…")
                .tint(.white)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let info = viewModel.openFolderInfo {
            folderContent(info)
                .transition(.opacity)
        } else if viewModel.filteredItems.isEmpty {
            ContentUnavailableView.search(text: viewModel.searchText)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            pagedGrid
        }
    }

    private func folderContent(_ info: (folder: LaunchpadFolder, apps: [AppRecord])) -> some View {
        FolderView(
            folder: info.folder,
            apps: viewModel.filteredOpenFolderApps,
            searchText: viewModel.searchText,
            cellImage: { viewModel.cellImage(for: $0) },
            selectedAppID: selectedFolderAppID,
            onBack: {
                withAnimation(.easeOut(duration: 0.18)) {
                    viewModel.closeFolder()
                }
                exitJiggleMode()
            },
            onLaunch: { app in
                viewModel.launch(app)
                onDismiss()
            },
            onReveal: { viewModel.revealInFinder($0) },
            onRemove: { viewModel.removeAppFromOpenFolder($0) },
            onMoveFolderApp: { dragged, target in
                viewModel.moveFolderApp(dragged.id, before: target.id)
            },
            onRename: { folder in
                folderBeingRenamed = folder
                renameDraft = folder.name
            },
            isJiggleMode: isJiggleMode,
            onBeginJiggle: { enterJiggleMode() },
            onExitJiggle: { exitJiggleMode() },
            onManageApp: { appBeingManaged = $0 }
        )
    }

    // MARK: - Paged grid

    private var pagedGrid: some View {
        GeometryReader { proxy in
            let layout = LaunchpadPager.layout(for: proxy.size)
            let items = viewModel.filteredItems
            let pages = LaunchpadPager.pages(items, itemsPerPage: layout.itemsPerPage)
            let pageCount = max(pages.count, 1)
            let columns = Array(
                repeating: GridItem(.fixed(layout.cellWidth), spacing: layout.spacing),
                count: layout.columns
            )

            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { pageIndex, pageItems in
                        grid(for: pageItems, pageIndex: pageIndex, columns: columns, layout: layout, screenSize: proxy.size)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .coordinateSpace(name: pageCoordinateSpace(pageIndex))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                .offset(x: -scroller.offset)
                .clipped()

                pageDots(pageCount: pages.count)
                    .padding(.bottom, 28)

                if let draggedItem {
                    Image(nsImage: viewModel.artwork(for: draggedItem))
                        .resizable()
                        .frame(width: 135, height: 150)
                        .scaleEffect(1.08)
                        .opacity(0.9)
                        .position(dragLocation)
                        .allowsHitTesting(false)
                        .zIndex(10)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        handleDragChanged(value, size: proxy.size, layout: layout, pageCount: pages.count, items: items)
                    }
                    .onEnded { value in
                        handleDragEnded(value, size: proxy.size, layout: layout, pageCount: pages.count, items: items)
                    }
            )
            .onChange(of: viewModel.filteredItems.count) { _, _ in
                cellFrames.removeAll()
                scroller.normalize(pageCount: pageCount)
            }
            .onChange(of: pageCount, initial: true) { _, newValue in
                scroller.normalize(pageCount: newValue)
            }
            .onChange(of: proxy.size, initial: true) { _, newSize in
                gridSize = newSize
                scroller.pageWidth = newSize.width
            }
        }
    }

    private func grid(
        for pageItems: [LaunchpadItem],
        pageIndex: Int,
        columns: [GridItem],
        layout: LaunchpadPager.Layout,
        screenSize: CGSize
    ) -> some View {
        LazyVGrid(columns: columns, spacing: layout.rowSpacing) {
            ForEach(Array(pageItems.enumerated()), id: \.element.id) { index, item in
                cell(for: item, index: index, pageIndex: pageIndex, layout: layout)
            }
        }
        .padding(.horizontal, 48)
        .padding(.top, 8)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func cell(for item: LaunchpadItem, index: Int, pageIndex: Int, layout: LaunchpadPager.Layout) -> some View {
        let manageAction: (() -> Void)?
        switch item {
        case .app(let app):
            manageAction = { appBeingManaged = app }
        case .folder:
            manageAction = nil
        }
        return LaunchpadCell(
            item: item,
            artwork: viewModel.artwork(for: item),
            entranceDelay: popEntranceDelay(for: index, layout: layout),
            onPrimaryAction: { primaryAction(for: item) },
            onLaunch: { app in
                viewModel.launch(app)
                onDismiss()
            },
            onReveal: { viewModel.revealInFinder($0) },
            onOpenFolder: { viewModel.openFolder($0) },
            onBeginRename: { folder in
                folderBeingRenamed = folder
                renameDraft = folder.name
            },
            onDeleteFolder: { folderBeingDeleted = $0 },
            onRemoveFromFolder: nil,
            animateEntrance: !gridHasAppeared,
            isSelected: item.id == selectedItemID,
            isJiggleMode: isJiggleMode,
            jigglePhase: Double(index) * 0.6,
            onBeginJiggle: { enterJiggleMode() },
            onManageApp: manageAction
        )
        .overlay(alignment: .topLeading) {
            GeometryReader { geo in
                let frame = geo.frame(in: .named(pageCoordinateSpace(pageIndex)))
                Color.clear
                    .onAppear {
                        cellFrames[item.id] = frame
                    }
                    .onChange(of: frame) { _, newFrame in
                        cellFrames[item.id] = newFrame
                    }
            }
            .allowsHitTesting(false)
        }
    }

    /// iPhone-unlock style stagger: a tight top-left to bottom-right wave so
    /// the whole page pops in almost together with a slight ripple.
    private func popEntranceDelay(for index: Int, layout: LaunchpadPager.Layout) -> Double {
        let row = index / layout.columns
        let col = index % layout.columns
        return 0.02 + min(Double(row) * 0.018 + Double(col) * 0.012, 0.16)
    }

    private func primaryAction(for item: LaunchpadItem) {
        switch item {
        case .app(let app):
            viewModel.launch(app)
            onDismiss()
        case .folder(let folder):
            // The grid has been on screen; returning from the folder should
            // not replay the fly-in entrance animation. Setting this on folder
            // open (instead of on grid appear) keeps the first-open animation
            // guaranteed regardless of onAppear ordering.
            gridHasAppeared = true
            viewModel.openFolder(folder)
        }
    }

    // MARK: - Custom drag & drop

    /// What the cursor is over in grid terms: the flat item index (respecting
    /// the current page offset) and the item itself, if the slot is occupied.
    private struct GridHit {
        let index: Int
        let item: LaunchpadItem?
    }

    private func pageCoordinateSpace(_ pageIndex: Int) -> String {
        "launchpadPage\(pageIndex)"
    }

    private func hitGrid(
        at location: CGPoint,
        size: CGSize,
        layout: LaunchpadPager.Layout,
        pageCount: Int,
        items: [LaunchpadItem]
    ) -> GridHit {
        let pageIndex = min(
            max(Int((location.x + scroller.offset) / size.width), 0),
            pageCount - 1
        )
        let pagePoint = CGPoint(
            x: location.x + scroller.offset - CGFloat(pageIndex) * size.width,
            y: location.y
        )

        let pageStart = pageIndex * layout.itemsPerPage
        let pageEnd = min(pageStart + layout.itemsPerPage, items.count)
        for index in pageStart..<pageEnd {
            let item = items[index]
            if let frame = cellFrames[item.id], frame.contains(pagePoint) {
                return GridHit(index: index, item: item)
            }
        }
        // Empty area: map the cursor to the grid slot under it, so icons can
        // be placed at any free position instead of always landing at the end
        // of the page. The page's first cell anchors the grid geometry.
        if pageStart < items.count,
           let anchor = cellFrames[items[pageStart].id] {
            let pageItemCount = pageEnd - pageStart
            let slot = pageStart + LaunchpadPager.slotIndex(
                at: pagePoint,
                anchor: anchor.origin,
                layout: layout,
                itemCountOnPage: pageItemCount
            )
            return GridHit(index: min(slot, items.count), item: nil)
        }
        // No measured cells yet: fall back to the end of the page.
        return GridHit(index: pageEnd, item: nil)
    }

    private func handleDragChanged(
        _ value: DragGesture.Value,
        size: CGSize,
        layout: LaunchpadPager.Layout,
        pageCount: Int,
        items: [LaunchpadItem]
    ) {
        if draggedItem == nil, !isPagingDrag {
            let hit = hitGrid(at: value.startLocation, size: size, layout: layout, pageCount: pageCount, items: items)
            if let item = hit.item {
                draggedItem = item
                Diagnostics.log("drag started: \(item.id)")
            } else {
                // Empty-area drag pages the grid iPhone-style.
                isPagingDrag = true
                scroller.beginDrag()
            }
        }
        if draggedItem != nil {
            dragLocation = value.location
            handleItemDragEdgePaging(value, size: size)
            return
        }
        guard isPagingDrag else { return }
        scroller.updateDrag(
            translation: value.translation.width,
            time: ProcessInfo.processInfo.systemUptime
        )
    }

    private func handleItemDragEdgePaging(_ value: DragGesture.Value, size: CGSize) {
        let edge: DragEdgeZone?
        if value.location.x < 70 {
            edge = .left
        } else if value.location.x > size.width - 70 {
            edge = .right
        } else {
            edge = nil
        }
        if let edge, edge != dragEdgeZone {
            dragEdgeZone = edge
            if edge == .left {
                scroller.showPrevious()
            } else {
                scroller.showNext()
            }
        } else if edge == nil {
            dragEdgeZone = nil
        }
    }

    private func handleDragEnded(
        _ value: DragGesture.Value,
        size: CGSize,
        layout: LaunchpadPager.Layout,
        pageCount: Int,
        items: [LaunchpadItem]
    ) {
        defer {
            draggedItem = nil
            dragEdgeZone = nil
            isPagingDrag = false
        }
        if let dragged = draggedItem {
            let hit = hitGrid(at: value.location, size: size, layout: layout, pageCount: pageCount, items: items)
            Diagnostics.log("drop: \(dragged.id) index=\(hit.index) target=\(hit.item?.id ?? "nil")")

            if let target = hit.item {
                guard target.id != dragged.id else { return }
                switch (dragged, target) {
                case (.app(let sourceApp), .app(let targetApp)):
                    viewModel.createFolder(dragging: sourceApp.id, onto: targetApp.id)
                case (.app(let sourceApp), .folder(let folder)):
                    viewModel.addToFolder(appID: sourceApp.id, folderID: folder.id)
                case (.folder, _):
                    viewModel.moveItem(dragged.id, toIndexInFiltered: hit.index)
                }
            } else {
                viewModel.moveItem(dragged.id, toIndexInFiltered: hit.index)
            }
            return
        }

        // Nothing was dragged. In jiggle mode a plain click on empty space
        // exits the mode instead of dismissing the whole Launchpad.
        if isJiggleMode {
            exitJiggleMode()
            return
        }

        guard isPagingDrag else { return }
        // Tiny mouse jitter cancels the background tap gesture on macOS,
        // making click-to-dismiss flaky; treat a small empty-area drag as the
        // same click.
        if abs(value.translation.width) < 30, abs(value.translation.height) < 30 {
            onDismiss()
        } else {
            // Let the grid spring to the nearest page, iPhone-style.
            scroller.endDrag()
        }
    }

    // MARK: - Keyboard navigation

    private func installKeyMonitor() {
        removeKeyMonitor()
        // The view is a value type; capturing it strongly keeps the same
        // @State storage alive without creating a retain cycle.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func installDirectoryChangeObserver() {
        removeDirectoryChangeObserver()
        let vm = viewModel
        directoryChangeObserver = NotificationCenter.default.addObserver(
            forName: AppDirectoryMonitor.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak vm] _ in
            Task { @MainActor in
                await vm?.reloadApps()
            }
        }
    }

    private func removeDirectoryChangeObserver() {
        if let directoryChangeObserver {
            NotificationCenter.default.removeObserver(directoryChangeObserver)
        }
        directoryChangeObserver = nil
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        // While a modal dialog is up, let it handle keys (Esc cancels it)
        // instead of closing the folder or the Launchpad.
        if folderBeingRenamed != nil || folderBeingDeleted != nil || appBeingManaged != nil {
            return event
        }
        switch event.keyCode {
        case 43 where event.modifierFlags.contains(.command): // Cmd+, → Settings
            // Consume the event and let the window controller open Settings
            // explicitly; the app menu's key equivalent does not reliably
            // reach Settings while the overlay is up.
            Diagnostics.log("CMD+, intercepted by launchpad view")
            onOpenSettings()
            return nil
        case 53: // Esc
            if isJiggleMode {
                exitJiggleMode()
            } else if viewModel.openFolderID != nil {
                withAnimation(.easeOut(duration: 0.18)) {
                    viewModel.closeFolder()
                }
            } else {
                onDismiss()
            }
            return nil
        case 123, 124: // left / right
            moveSelection(dx: event.keyCode == 124 ? 1 : -1, dy: 0)
            return nil
        case 125, 126: // down / up
            moveSelection(dx: 0, dy: event.keyCode == 125 ? 1 : -1)
            return nil
        case 36, 76: // return / keypad enter
            activateSelection()
            return nil
        default:
            return event
        }
    }

    private func moveSelection(dx: Int, dy: Int) {
        if viewModel.openFolderID != nil {
            moveFolderSelection(dx: dx, dy: dy)
            return
        }
        let items = viewModel.filteredItems
        guard !items.isEmpty else { return }
        let layout = LaunchpadPager.layout(for: gridSize)
        let current = items.firstIndex { $0.id == selectedItemID } ?? 0
        let newIndex = min(max(current + dx + dy * layout.columns, 0), items.count - 1)
        selectedItemID = items[newIndex].id
        ensurePageVisible(for: newIndex, itemsPerPage: layout.itemsPerPage)
    }

    private func moveFolderSelection(dx: Int, dy: Int) {
        let apps = viewModel.filteredOpenFolderApps
        guard !apps.isEmpty else { return }
        let layout = LaunchpadPager.layout(for: gridSize)
        let current = apps.firstIndex { $0.id == selectedFolderAppID } ?? 0
        let newIndex = min(max(current + dx + dy * layout.columns, 0), apps.count - 1)
        selectedFolderAppID = apps[newIndex].id
    }

    private func activateSelection() {
        if isJiggleMode {
            if viewModel.openFolderID != nil {
                let apps = viewModel.filteredOpenFolderApps
                guard let id = selectedFolderAppID ?? apps.first?.id,
                      let app = apps.first(where: { $0.id == id }) else {
                    return
                }
                appBeingManaged = app
            } else {
                let items = viewModel.filteredItems
                guard let id = selectedItemID ?? items.first?.id,
                      let item = items.first(where: { $0.id == id }) else {
                    return
                }
                if case .app(let app) = item {
                    appBeingManaged = app
                }
            }
            return
        }
        if viewModel.openFolderID != nil {
            let apps = viewModel.filteredOpenFolderApps
            guard let id = selectedFolderAppID ?? apps.first?.id,
                  let app = apps.first(where: { $0.id == id }) else {
                return
            }
            viewModel.launch(app)
            onDismiss()
            return
        }
        let items = viewModel.filteredItems
        guard let id = selectedItemID ?? items.first?.id,
              let item = items.first(where: { $0.id == id }) else {
            return
        }
        primaryAction(for: item)
    }

    private func ensurePageVisible(for index: Int, itemsPerPage: Int) {
        let targetPage = index / itemsPerPage
        if targetPage != scroller.pageIndex {
            scroller.jump(to: targetPage)
        }
    }

    // MARK: - Dialogs

    private var renameAlertPresented: Binding<Bool> {
        Binding(
            get: { folderBeingRenamed != nil },
            set: { isPresented in
                if !isPresented {
                    folderBeingRenamed = nil
                }
            }
        )
    }

    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { folderBeingDeleted != nil },
            set: { isPresented in
                if !isPresented {
                    folderBeingDeleted = nil
                }
            }
        )
    }

    private var manageAlertPresented: Binding<Bool> {
        Binding(
            get: { appBeingManaged != nil },
            set: { isPresented in
                if !isPresented {
                    appBeingManaged = nil
                }
            }
        )
    }

    private var uninstallErrorPresented: Binding<Bool> {
        Binding(
            get: { uninstallError != nil },
            set: { isPresented in
                if !isPresented {
                    uninstallError = nil
                }
            }
        )
    }

    private var manageMessage: String {
        guard let app = appBeingManaged else { return "" }
        if viewModel.canUninstall(app) {
            return String(
                format: NSLocalizedString("「%@」可移到废纸篓卸载，或从启动台隐藏。隐藏后可在「设置 → 隐藏的应用」中恢复。", comment: ""),
                app.name
            )
        }
        return NSLocalizedString("系统应用无法卸载，只能从启动台隐藏。隐藏后可在「设置 → 隐藏的应用」中恢复。", comment: "")
    }

    private func enterJiggleMode() {
        isJiggleMode = true
    }

    private func exitJiggleMode() {
        isJiggleMode = false
    }

    private func confirmRename() {
        if let folder = folderBeingRenamed {
            viewModel.renameFolder(folderID: folder.id, name: renameDraft)
        }
        folderBeingRenamed = nil
    }

    private func confirmDelete() {
        if let folder = folderBeingDeleted {
            viewModel.deleteFolder(folderID: folder.id)
        }
        folderBeingDeleted = nil
    }

    private func confirmHide(_ app: AppRecord) {
        viewModel.hide(app)
        appBeingManaged = nil
        exitJiggleMode()
    }

    private func confirmUninstall(_ app: AppRecord) {
        appBeingManaged = nil
        do {
            try viewModel.uninstall(app)
            exitJiggleMode()
        } catch {
            uninstallError = error.localizedDescription
        }
    }

    // MARK: - Page dots

    private func pageDots(pageCount: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { page in
                Circle()
                    .fill(.white.opacity(scroller.pageIndex == page ? 0.95 : 0.35))
                    .frame(width: 8, height: 8)
                    .onTapGesture {
                        scroller.jump(to: page)
                    }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.black.opacity(0.35))
        }
    }
}

/// The folder screen: a header with back/rename plus the folder's app grid.
private struct FolderView: View {
    let folder: LaunchpadFolder
    let apps: [AppRecord]
    let searchText: String
    let cellImage: (AppRecord) -> NSImage
    let selectedAppID: String?
    let onBack: () -> Void
    let onLaunch: (AppRecord) -> Void
    let onReveal: (AppRecord) -> Void
    let onRemove: (AppRecord) -> Void
    let onMoveFolderApp: (AppRecord, AppRecord) -> Void
    let onRename: (LaunchpadFolder) -> Void
    let isJiggleMode: Bool
    let onBeginJiggle: () -> Void
    let onExitJiggle: () -> Void
    let onManageApp: (AppRecord) -> Void

    @State private var draggedApp: AppRecord?
    @State private var dragLocation: CGPoint = .zero
    @State private var cellFrames: [String: CGRect] = [:]

    var body: some View {
        GeometryReader { proxy in
            let layout = LaunchpadPager.layout(for: proxy.size)
            let columns = Array(
                repeating: GridItem(.fixed(layout.cellWidth), spacing: layout.spacing),
                count: layout.columns
            )

            ZStack {
                VStack(spacing: 0) {
                    HStack {
                        Button(action: onBack) {
                            Label("返回", systemImage: "chevron.left")
                                .font(.system(size: 15, weight: .medium))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.leading, 28)

                        Spacer()

                        Text(folder.name)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()

                        Button("重命名…", action: { onRename(folder) })
                            .buttonStyle(.plain)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.trailing, 28)
                    }
                    .padding(.top, 40)

                    if apps.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: layout.rowSpacing) {
                                ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                                    LaunchpadCell(
                                        item: .app(app),
                                        artwork: cellImage(app),
                                        entranceDelay: min(Double(index) * 0.02, 0.2),
                                        onPrimaryAction: { onLaunch(app) },
                                        onLaunch: { onLaunch($0) },
                                        onReveal: { onReveal($0) },
                                        onOpenFolder: { _ in },
                                        onBeginRename: { _ in },
                                        onDeleteFolder: { _ in },
                                        onRemoveFromFolder: { onRemove(app) },
                                        gentleEntrance: true,
                                        isSelected: app.id == selectedAppID,
                                        isJiggleMode: isJiggleMode,
                                        jigglePhase: Double(index) * 0.6,
                                        onBeginJiggle: onBeginJiggle,
                                        onManageApp: { onManageApp(app) }
                                    )
                                    .overlay(alignment: .topLeading) {
                                        GeometryReader { geo in
                                            let frame = geo.frame(in: .named(folderDragSpace))
                                            Color.clear
                                                .onAppear {
                                                    cellFrames[app.id] = frame
                                                }
                                                .onChange(of: frame) { _, newFrame in
                                                    cellFrames[app.id] = newFrame
                                                }
                                        }
                                        .allowsHitTesting(false)
                                    }
                                }
                            }
                            .padding(.horizontal, 48)
                            .padding(.top, 8)
                            .padding(.bottom, 48)
                        }
                    }
                }

                if let draggedApp {
                    Image(nsImage: cellImage(draggedApp))
                        .resizable()
                        .frame(width: 135, height: 150)
                        .scaleEffect(1.08)
                        .opacity(0.9)
                        .position(dragLocation)
                        .allowsHitTesting(false)
                        .zIndex(10)
                }

                if draggedApp != nil {
                    Text("拖到其他应用上排序，拖到空白处移出文件夹")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background {
                            Capsule()
                                .fill(.black.opacity(0.5))
                        }
                        .position(x: proxy.size.width / 2, y: proxy.size.height - 60)
                        .allowsHitTesting(false)
                        .zIndex(10)
                }
            }
            .coordinateSpace(name: folderDragSpace)
            .highPriorityGesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        handleDragChanged(value)
                    }
                    .onEnded { value in
                        handleDragEnded(value)
                    }
            )
        }
    }

    private var folderDragSpace: String {
        "folderDragSpace"
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        if draggedApp == nil {
            if let app = app(at: value.startLocation) {
                draggedApp = app
                Diagnostics.log("folder drag started: \(app.id)")
            }
        }
        guard draggedApp != nil else { return }
        dragLocation = value.location
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        defer { draggedApp = nil }
        guard let dragged = draggedApp else {
            if isJiggleMode {
                onExitJiggle()
            }
            return
        }
        // Dropping on another app sorts the folder; dropping on empty space
        // moves the app back to the Launchpad grid.
        if let target = app(at: value.location) {
            guard target.id != dragged.id else { return }
            Diagnostics.log("folder drag reorder: \(dragged.id) before \(target.id)")
            onMoveFolderApp(dragged, target)
            return
        }
        Diagnostics.log("folder drag out: \(dragged.id)")
        onRemove(dragged)
    }

    private func app(at location: CGPoint) -> AppRecord? {
        apps.first { app in
            cellFrames[app.id]?.contains(location) ?? false
        }
    }
}

private struct LaunchpadCell: View {
    let item: LaunchpadItem
    let artwork: NSImage
    let entranceDelay: Double
    let onPrimaryAction: () -> Void
    let onLaunch: (AppRecord) -> Void
    let onReveal: (AppRecord) -> Void
    let onOpenFolder: (LaunchpadFolder) -> Void
    let onBeginRename: (LaunchpadFolder) -> Void
    let onDeleteFolder: (LaunchpadFolder) -> Void
    /// Non-nil inside a folder screen: adds "移出文件夹" and disables drag & drop.
    let onRemoveFromFolder: (() -> Void)?
    /// True inside a folder screen: icons fade + scale in gently instead of
    /// flying in from the screen edges.
    var gentleEntrance = false
    /// False after the grid has been shown once, so returning from a folder
    /// does not replay the fly-in entrance animation.
    var animateEntrance = true
    /// Keyboard-navigation selection highlight.
    var isSelected = false
    /// Jiggle (uninstall/hide) mode: icons wobble and apps show a manage badge.
    var isJiggleMode = false
    /// Per-cell phase so neighboring icons don't jiggle in lockstep.
    var jigglePhase: Double = 0
    /// Long-press callback; enters jiggle mode.
    var onBeginJiggle: (() -> Void)?
    /// Non-nil for apps: shows the manage badge and the hide/uninstall dialog.
    var onManageApp: (() -> Void)?

    @State private var appeared = false
    @State private var isHovering = false

    var body: some View {
        cellContent
            .modifier(JiggleModifier(isJiggling: isJiggleMode, phase: jigglePhase))
    }

    @ViewBuilder
    private var cellContent: some View {
        let shouldShow = appeared || !animateEntrance
        // Grid cells pop from 55% (iPhone unlock), folder cells fade from 92%.
        let entranceScale: CGFloat = gentleEntrance ? 0.92 : 0.55
        let scale = (!shouldShow ? entranceScale : 1) * (isHovering ? 1.05 : 1)
        // The artwork is a single pre-rendered image (icon + label + shadows),
        // so the entrance animation moves one layer per cell — no per-frame
        // text layout or shadow rasterization.
        let artworkView = Image(nsImage: artwork)
            .resizable()
            .frame(width: 135, height: 150)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(isHovering || isSelected ? 0.14 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(isHovering || isSelected ? 0.22 : 0))
            }
            .scaleEffect(scale)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isHovering)
            .animation(
                gentleEntrance
                    ? .easeOut(duration: 0.25).delay(entranceDelay)
                    : .spring(response: 0.42, dampingFraction: 0.6)
                        .delay(entranceDelay),
                value: appeared
            )
            .opacity(shouldShow ? 1 : 0)
            .animation(
                .easeOut(duration: gentleEntrance ? 0.25 : 0.16)
                    .delay(entranceDelay),
                value: appeared
            )
            .onAppear {
                appeared = true
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onHover { hovering in
                isHovering = hovering
            }
            .onTapGesture {
                // While jiggling, only the × badge (or Esc / empty space)
                // acts; a plain click must not launch the app.
                guard !isJiggleMode else { return }
                onPrimaryAction()
            }
            .onLongPressGesture(minimumDuration: 0.45) {
                onBeginJiggle?()
            }

        if isJiggleMode {
            artworkView
                .overlay(alignment: .topLeading) {
                    if onManageApp != nil {
                        manageBadge
                    }
                }
        } else {
            artworkView
                .contextMenu {
                    switch item {
                    case .app(let app):
                        Button("启动") {
                            onLaunch(app)
                        }
                        Button("在 Finder 中显示") {
                            onReveal(app)
                        }
                        if let onRemoveFromFolder {
                            Button("移出文件夹", role: .destructive) {
                                onRemoveFromFolder()
                            }
                        }
                        if onManageApp != nil {
                            Button("隐藏应用…") {
                                onManageApp?()
                            }
                        }
                    case .folder(let folder):
                        Button("打开") {
                            onOpenFolder(folder)
                        }
                        Button("重命名…") {
                            onBeginRename(folder)
                        }
                        Button("删除文件夹", role: .destructive) {
                            onDeleteFolder(folder)
                        }
                    }
                }
        }
    }

    /// The macOS Launchpad-style × badge, centered on the icon's top-left
    /// corner. Tapping it opens the hide/uninstall dialog for the app.
    private var manageBadge: some View {
        Button {
            onManageApp?()
        } label: {
            ZStack {
                Circle()
                    .fill(.white)
                Circle()
                    .strokeBorder(.black.opacity(0.15))
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
            }
            .frame(width: 24, height: 24)
            .shadow(color: .black.opacity(0.45), radius: 2.5, y: 1)
        }
        .buttonStyle(.plain)
        .offset(x: -4, y: -4)
    }
}

/// Wobbles a cell while jiggle mode is active. Uses a paused `TimelineView`
/// so exiting the mode stops all animation work immediately, and a per-cell
/// phase so icons don't move in lockstep.
private struct JiggleModifier: ViewModifier {
    let isJiggling: Bool
    let phase: Double

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isJiggling)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            content
                .rotationEffect(.degrees(isJiggling ? sin(time * 5 + phase) * 2.4 : 0))
                .animation(.easeOut(duration: 0.18), value: isJiggling)
        }
    }
}

private enum DragEdgeZone: Equatable {
    case left
    case right
}
