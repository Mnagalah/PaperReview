import AppKit
import SwiftUI
import QuartzCore

/// Native column roles supply the window's sidebar/inspector materials. Tracking
/// toolbar separators join those columns to the titlebar without drawn overlays.
struct WorkspaceSplitView<Sidebar: View, Document: View, Inspector: View, Picker: View>: NSViewControllerRepresentable {
    let width: CGFloat
    let toolbarState: WorkspaceToolbarState
    @ViewBuilder var sidebar: Sidebar
    @ViewBuilder var document: Document
    @ViewBuilder var inspector: Inspector
    @ViewBuilder var picker: Picker

    func makeNSViewController(context: Context) -> WorkspaceSplitController {
        WorkspaceSplitController(sidebar: hosted(sidebar, context: context), document: hosted(document, context: context),
            inspector: hosted(inspector, context: context), state: toolbarState, compact: WorkspaceLayout(width: width).compact)
    }
    func updateNSViewController(_ controller: WorkspaceSplitController, context: Context) {
        controller.sidebarHost.rootView = hosted(sidebar, context: context)
        controller.documentHost.rootView = hosted(document, context: context)
        controller.inspectorHost.rootView = hosted(inspector, context: context)
        let compact = WorkspaceLayout.compactAfterResize(width: width, wasCompact: controller.isCompact)
        controller.windowToolbar.update(toolbarState, compact: compact, pickerContent: hosted(picker, context: context))
        controller.setCompact(compact, animated: !context.environment.accessibilityReduceMotion)
    }
    private func hosted<V: View>(_ view: V, context: Context) -> AnyView {
        AnyView(view.environment(\.workspaceSize, context.environment.workspaceSize)
            .environment(\.scenePhase, context.environment.scenePhase)
            .environment(\.colorScheme, context.environment.colorScheme).tint(WorkspaceStyle.action))
    }
}

final class WorkspaceSplitController: NSSplitViewController {
    let sidebarHost: NSHostingController<AnyView>
    let documentHost: NSHostingController<AnyView>
    let inspectorHost: NSHostingController<AnyView>
    let sidebarItem: NSSplitViewItem
    let inspectorItem: NSSplitViewItem
    private(set) var windowToolbar: WorkspaceToolbar!
    private(set) var isCompact: Bool
    private(set) var isAnimatingColumns = false
    private var transitionID = 0

    init(sidebar: AnyView, document: AnyView, inspector: AnyView, state: WorkspaceToolbarState, compact: Bool) {
        isCompact = compact
        sidebarHost = NSHostingController(rootView: sidebar)
        documentHost = NSHostingController(rootView: document)
        inspectorHost = NSHostingController(rootView: inspector)
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHost)
        inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorHost)
        super.init(nibName: nil, bundle: nil)
        splitView.isVertical = true; splitView.dividerStyle = .thin
        sidebarItem.minimumThickness = WorkspaceLayout.sidebarWidth
        sidebarItem.maximumThickness = WorkspaceLayout.sidebarWidth
        sidebarItem.canCollapse = false; sidebarItem.canCollapseFromWindowResize = false
        sidebarItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        sidebarItem.isCollapsed = compact
        sidebarItem.titlebarSeparatorStyle = .none
        let documentItem = NSSplitViewItem(viewController: documentHost)
        documentItem.minimumThickness = WorkspaceLayout.documentMinimumWidth
        documentItem.holdingPriority = .init(249)
        documentItem.titlebarSeparatorStyle = .none
        if #available(macOS 26.0, *) { documentItem.automaticallyAdjustsSafeAreaInsets = true }
        inspectorItem.minimumThickness = WorkspaceLayout.inspectorMinimumWidth
        inspectorItem.maximumThickness = 370
        inspectorItem.holdingPriority = .init(251)
        inspectorItem.canCollapse = false; inspectorItem.canCollapseFromWindowResize = false
        inspectorItem.titlebarSeparatorStyle = .none
        inspectorHost.view.setFrameSize(NSSize(width: 328, height: 600))
        addSplitViewItem(sidebarItem); addSplitViewItem(documentItem); addSplitViewItem(inspectorItem)
        windowToolbar = WorkspaceToolbar(splitView: splitView, state: state, compact: compact)
    }
    func setCompact(_ compact: Bool, animated: Bool = false) {
        let animate = animated && view.window?.isVisible == true
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard isCompact != compact || (isAnimatingColumns && !animate) else { return }
        isCompact = compact
        transitionID += 1
        let currentTransition = transitionID
        guard animate else {
            isAnimatingColumns = false
            sidebarItem.isCollapsed = compact
            return
        }
        isAnimatingColumns = true
        // Animate the real split item, not a screenshot or a second pane tree.
        // AppKit retargets its current animation when the resize reverses.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = WorkspaceMotion.columnDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            sidebarItem.animator().isCollapsed = compact
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.transitionID == currentTransition else { return }
                self.isAnimatingColumns = false
                self.windowToolbar.updateTitleWidth()
            }
        }
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        guard let window = view.window else { return }
        _ = WorkspaceWindowChrome.configure(window)
        window.toolbar = windowToolbar.toolbar
        window.toolbarStyle = .unified
        windowToolbar.refreshItems()
    }
    override func viewDidLayout() {
        super.viewDidLayout()
        windowToolbar?.updateTitleWidth()
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}
