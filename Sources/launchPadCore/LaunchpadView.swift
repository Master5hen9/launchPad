import AppKit
import Observation
import SwiftUI

/// Fullscreen Launchpad content, displayed inside a blurred overlay window.
public struct LaunchpadView: View {
    private let onDismiss: () -> Void
    @State private var viewModel = ContentViewModel()
    @State private var appeared = false
    @State private var scroller = PageScroller()

    public init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    onDismiss()
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
                searchBar
                    .padding(.top, 48)
                    .padding(.bottom, 24)
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.35), value: appeared)

                content
            }
        }
        .task {
            await viewModel.loadAppsIfNeeded()
        }
        .onAppear {
            scroller.installMonitor()
            appeared = true
        }
        .onDisappear {
            scroller.stopMonitor()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            TextField("搜索应用", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .tint(.white)
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
        .background {
            Capsule()
                .fill(.white.opacity(0.14))
        }
        .overlay {
            Capsule()
                .strokeBorder(.white.opacity(0.18))
        }
        .frame(maxWidth: 420)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView("正在加载应用…")
                .tint(.white)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.filteredApps.isEmpty {
            ContentUnavailableView.search(text: viewModel.searchText)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { proxy in
                let layout = LaunchpadPager.layout(for: proxy.size)
                let pages = LaunchpadPager.pages(viewModel.filteredApps, itemsPerPage: layout.itemsPerPage)
                let pageCount = max(pages.count, 1)
                let columns = Array(
                    repeating: GridItem(.fixed(layout.cellWidth), spacing: layout.spacing),
                    count: layout.columns
                )

                ZStack(alignment: .bottom) {
                    HStack(spacing: 0) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { page, pageApps in
                            grid(for: pageApps, columns: columns, layout: layout, screenSize: proxy.size)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                    .offset(x: -scroller.offset)
                    .clipped()
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { value in
                                if value.translation.width < -60 {
                                    scroller.showNext()
                                } else if value.translation.width > 60 {
                                    scroller.showPrevious()
                                }
                            }
                    )

                    pageDots(pageCount: pages.count)
                        .padding(.bottom, 28)
                }
                .onChange(of: viewModel.filteredApps.count) { _, _ in
                    scroller.reset()
                }
                .onChange(of: pageCount, initial: true) { _, newValue in
                    scroller.pageCount = newValue
                    if newValue <= scroller.pageIndex {
                        scroller.reset()
                    }
                }
                .onChange(of: proxy.size.width, initial: true) { _, newValue in
                    scroller.pageWidth = newValue
                }
            }
        }
    }

    private func grid(
        for pageApps: [AppRecord],
        columns: [GridItem],
        layout: LaunchpadPager.Layout,
        screenSize: CGSize
    ) -> some View {
        LazyVGrid(columns: columns, spacing: layout.rowSpacing) {
            ForEach(Array(pageApps.enumerated()), id: \.element.id) { index, app in
                LaunchpadCell(
                    app: app,
                    artwork: viewModel.cellImage(for: app),
                    entranceOffset: Self.entranceOffset(
                        for: index,
                        layout: layout
                    ),
                    entranceDelay: Self.entranceDelay(
                        for: index,
                        layout: layout
                    )
                )
                .onTapGesture {
                    viewModel.launch(app)
                    onDismiss()
                }
                .contextMenu {
                    Button("启动") {
                        viewModel.launch(app)
                        onDismiss()
                    }
                    Button("在 Finder 中显示") {
                        viewModel.revealInFinder(app)
                    }
                }
            }
        }
        .padding(.horizontal, 48)
        .padding(.top, 8)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Off-screen start position matching the original Launchpad: each icon
    /// starts on the ray from the grid center through its slot, pushed out far
    /// enough that edge icons begin beyond the screen edge. Travel distance is
    /// therefore proportional to the slot's distance from the center: edge
    /// icons fly the farthest from the four screen edges, while center icons
    /// only shift slightly, so all four directions stay perfectly symmetric.
    private static func entranceOffset(
        for index: Int,
        layout: LaunchpadPager.Layout
    ) -> CGSize {
        let col = index % layout.columns
        let row = index / layout.columns
        let dxNorm = (CGFloat(col) + 0.5) / CGFloat(layout.columns) - 0.5
        let dyNorm = (CGFloat(row) + 0.5) / CGFloat(max(layout.rows, 1)) - 0.5

        let gridWidth = CGFloat(layout.columns) * layout.cellWidth
            + CGFloat(layout.columns - 1) * layout.spacing
        let gridHeight = CGFloat(layout.rows) * layout.cellHeight
            + CGFloat(max(layout.rows - 1, 0)) * layout.rowSpacing

        // Push the start beyond the screen edge far enough that the outer
        // columns/rows are already off-screen when the animation begins; the
        // fly-in curve then carries them across the visible screen at speed.
        let stretch: CGFloat = 1.8
        return CGSize(
            width: dxNorm * gridWidth * (stretch - 1),
            height: dyNorm * gridHeight * (stretch - 1)
        )
    }

    /// Edge-first ripple: the outermost icons launch first and the wave rolls
    /// inward, so each ring is already mid-flight before the next one starts
    /// (an outer icon is never seen popping in beside an inner one).
    private static func entranceDelay(
        for index: Int,
        layout: LaunchpadPager.Layout
    ) -> Double {
        let col = index % layout.columns
        let row = index / layout.columns
        let dxNorm = (CGFloat(col) + 0.5) / CGFloat(layout.columns) - 0.5
        let dyNorm = (CGFloat(row) + 0.5) / CGFloat(max(layout.rows, 1)) - 0.5
        let radial = sqrt(dxNorm * dxNorm + dyNorm * dyNorm) / sqrt(0.5)
        // The extra base delay lets the window fade-in finish before the
        // icons start moving, so the heavy first frames (window alpha +
        // full-screen blur) don't overlap the start of the fly-in.
        return 0.12 + (1 - radial) * 0.32
    }

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

private struct LaunchpadCell: View {
    let app: AppRecord
    let artwork: NSImage
    let entranceOffset: CGSize
    let entranceDelay: Double

    @State private var appeared = false
    @State private var isHovering = false

    var body: some View {
        // The artwork is a single pre-rendered image (icon + label + shadows),
        // so the entrance animation moves one layer per cell — no per-frame
        // text layout or shadow rasterization.
        Image(nsImage: artwork)
            .resizable()
            .frame(width: 135, height: 150)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(isHovering ? 0.14 : 0))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(isHovering ? 0.22 : 0))
        }
        .scaleEffect(isHovering ? 1.05 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isHovering)
        .offset(appeared ? .zero : entranceOffset)
            .animation(
                // A steep-start ease keeps icons at high speed the moment they
                // enter the screen, unlike a spring that launches from rest
                // and reads as "pulled" across the visible portion.
                .timingCurve(0.12, 0.85, 0.25, 1, duration: 0.42)
                    .delay(entranceDelay),
                value: appeared
            )
        .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.12).delay(entranceDelay), value: appeared)
        .onAppear {
            // Each cell flies in from its nearest screen edge: the position
            // uses a fast ease, while the opacity snaps solid early so the
            // cell reads as a flying object rather than a fade-in.
            appeared = true
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
