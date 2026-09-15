// ContentView.swift
// Target membership: Drinkstand
//
// Three trackers now: to-do (a checklist — up to 5 user-editable
// custom items, plus two auto-completing ones linked to the water/
// protein goals), water (ml), and protein (g). The top overview is
// always a combined dashboard — one row per ENABLED tracker, current
// value on the left (big), "goal(percent%)" on the right (smaller) —
// rather than switching with whichever tab is open.
//
// Tapping "water" or "protein" in the left column just switches
// which tracker is active — the right column then shows that
// tracker's presets + "more" (to-do shows its checklist instead).
//
// ONE tier of navigation now: "settings" AND "more" both replace the
// home screen with a genuine full-screen white page (macOS) or a
// native sheet (iOS) — same `page(...)` container / same sheet+
// toolbar chrome either way, intercepted at the top of `body` before
// the home screen ever renders. Everything settings leads to
// (history / trackers / sync & reset) works the same way; each has
// its own "<pagename"/"close" link (or circular back/X on iOS) to get
// back. Goals live inline on the trackers page (no separate screen);
// reset lives inline on the sync page; to-do's custom slots live
// inline on the trackers page too, same reasoning.
//
// FONT: GoogleSansCode-Medium.ttf (PostScript name confirmed from
// the font file itself). Needs to be added to the Xcode project and
// registered in Info.plist under "Fonts provided by application" —
// see SETUP.md. Falls back silently to the system font if that
// registration is missing (no crash, just the wrong typeface).
//
// ESTIMATES flagged inline below — confirm or correct these.

import SwiftUI
import Combine
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
    /// One value that resolves to a different color depending on the
    /// SYSTEM's own light/dark appearance — dark mode here always
    /// follows the OS setting, no in-app override, so this is the
    /// only piece of plumbing dark mode needs: every color below is
    /// defined with this instead of a flat RGB, and every call site
    /// that already just used a plain `Color` is untouched.
    ///
    /// Built from a platform DYNAMIC color (`UIColor`'s trait closure
    /// on iOS, `NSColor`'s appearance closure on macOS) rather than
    /// reading `\.colorScheme` from the SwiftUI environment — these
    /// constants are file-scope `let`s outside any View, with no
    /// environment to read, and a dynamic platform color resolves
    /// itself live at DRAW time regardless of that. That's also what
    /// keeps `UIColor(fillNavy)` (the one place a Color here gets
    /// handed to a plain UIKit view — see TodoTextField) updating
    /// correctly: unwrapping a dynamic Color back to UIColor keeps it
    /// dynamic, it doesn't freeze it at the moment of conversion.
    static func adaptive(light: Color, dark: Color) -> Color {
        #if os(iOS)
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #else
        Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
        #endif
    }
}

// Page fill/background — the home screen's fill layer, History's
// background, and the paging scroll view's overscroll color. #CECECE
// in light mode; dark mode picked (not specified) to sit close to
// true black without going all the way there, matching the flat,
// slightly-soft feel of the light value rather than a harsher OLED
// black.
private let pageBG = Color.adaptive(
    light: Color(red: 0xCE / 255, green: 0xCE / 255, blue: 0xCE / 255),   // #CECECE
    dark: Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)     // #1C1C1E
)
// Sheet/settings-page chrome background — plain white in light mode.
// Its dark counterpart sits a step LIGHTER than `pageBG`'s dark
// value, which keeps the same relationship light mode has (the sheet
// reads as a lighter card lifted off the page fill behind it) instead
// of sinking into near-black.
private let sheetBG = Color.adaptive(
    light: .white,
    dark: Color(red: 0x26 / 255, green: 0x26 / 255, blue: 0x2A / 255)     // #26262A
)
// "all logs" row cards specifically — was reusing `pageBG`, which
// reads a little too dark/flat as a card sitting ON TOP of that same
// `pageBG` page background (no separation between the two). A step
// lighter in light mode, a step lighter in dark mode too.
private let logRowBG = Color.adaptive(
    light: Color(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF7 / 255),   // #F4F4F7
    dark: Color(red: 0x39 / 255, green: 0x39 / 255, blue: 0x3E / 255)     // #39393E
)
private let fillNavy = Color.adaptive(
    light: Color(red: 0x1E / 255, green: 0x1E / 255, blue: 0x1E / 255),   // #1E1E1E
    dark: Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF0 / 255)     // #F2F2F0
)
private let fillWater = Color.adaptive(
    light: Color(red: 0x00 / 255, green: 0x62 / 255, blue: 0xFF / 255),   // #0062FF
    dark: Color(red: 0x3D / 255, green: 0x8B / 255, blue: 0xFF / 255)     // #3D8BFF
)
private let fillProtein = Color.adaptive(
    light: Color(red: 0xFF / 255, green: 0x30 / 255, blue: 0x26 / 255),   // #FF3026
    dark: Color(red: 0xFF / 255, green: 0x54 / 255, blue: 0x49 / 255)     // #FF5449
)
// Coffee's light value is a muddy dark brown — nearly invisible on a
// near-black dark background — so its dark counterpart is lightened
// substantially (a warm tan) rather than just brightened a little,
// unlike every other tracker color here.
private let fillCoffee = Color.adaptive(
    light: Color(red: 0x6F / 255, green: 0x4E / 255, blue: 0x37 / 255),   // #6F4E37
    dark: Color(red: 0xC8 / 255, green: 0x9B / 255, blue: 0x72 / 255)     // #C89B72
)
private let fillCarbs = Color.adaptive(
    light: Color(red: 0xFF / 255, green: 0xB3 / 255, blue: 0x00 / 255),   // #FFB300
    dark: Color(red: 0xFF / 255, green: 0xC2 / 255, blue: 0x33 / 255)     // #FFC233
)
private let fillSteps = Color.adaptive(
    light: Color(red: 0x00 / 255, green: 0x7A / 255, blue: 0x33 / 255),   // #007A33
    dark: Color(red: 0x12 / 255, green: 0xD9 / 255, blue: 0x65 / 255)     // #12D965
)
private let fillMovement = Color.adaptive(
    light: Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x35 / 255),   // #FF6B35
    dark: Color(red: 0xFF / 255, green: 0x8B / 255, blue: 0x5E / 255)     // #FF8B5E
)
private let fillSleep = Color.adaptive(
    light: Color(red: 0x5B / 255, green: 0x5F / 255, blue: 0xEF / 255),   // #5B5FEF
    dark: Color(red: 0x7B / 255, green: 0x7F / 255, blue: 0xFF / 255)     // #7B7FFF
)
// Only shown in .min mode (rare for this tracker — see GoalMode) since
// .max mode replaces it entirely with the green/red scheme below. A
// muted smoke grey, distinct from every other tracker color.
private let fillCigarettes = Color.adaptive(
    light: Color(red: 0x5C / 255, green: 0x66 / 255, blue: 0x70 / 255),   // #5C6670
    dark: Color(red: 0x9B / 255, green: 0xA5 / 255, blue: 0xAF / 255)     // #9BA5AF
)
// Celebration color once ALL of today's to-dos are done — overrides
// whichever per-tracker color would normally show, on every tab. The
// light value is dark/muted enough that it would nearly disappear
// against a near-black dark background, so its dark counterpart is a
// substantially brighter green, not just a tint adjustment.
private let fillAccent = Color.adaptive(
    light: Color(red: 0x00 / 255, green: 0x7A / 255, blue: 0x33 / 255),   // #007A33
    dark: Color(red: 0x12 / 255, green: 0xD9 / 255, blue: 0x65 / 255)     // #12D965
)

// MARK: - Max-mode (goal-is-a-ceiling) green/red scheme
//
// For a tracker in .max mode (coffee/calories/cigarettes — see
// GoalMode), the usual "fill rises toward a goal" metaphor reads
// backwards: filling up looks like progress, but for a max you're
// trying to STAY UNDER, more filled is worse. So instead the home
// screen ALWAYS opens on this scheme while that tracker is active —
// not just once something's logged: a medium green #4FB06F page
// background with a darker green #007A33 fill block on top (reusing
// fillAccent's own light value — same "good" green as the fully-done
// celebration color) — collapsing to one flat dark red covering
// background AND fill with no visible fill line once you go over.
// Deliberately separate from `pageBG` — that constant is shared by
// many other, unrelated pages and must stay untouched; only the home
// screen's own background layer becomes mode-aware.
private let maxModeSafeBG = Color.adaptive(
    light: Color(red: 0x4F / 255, green: 0xB0 / 255, blue: 0x6F / 255),   // #4FB06F
    dark: Color(red: 0x14 / 255, green: 0x3D / 255, blue: 0x27 / 255)     // #143D27
)
private let maxModeOverColor = Color.adaptive(
    light: Color(red: 0xA8 / 255, green: 0x2F / 255, blue: 0x31 / 255),   // #A82F31
    dark: Color(red: 0xA8 / 255, green: 0x2F / 255, blue: 0x31 / 255)     // #A82F31
)

// History's streak-length milestone colors — separate from fillAccent
// above, which is the home screen's own "today's fully done" color
// and unrelated to a multi-day run. Ordered ascending; a run's color
// is whichever of these its total length qualifies for, applied to
// the WHOLE run (see `historyDayTiers`), highest tier wins.
private let historyMilestone10 = Color.adaptive(
    light: Color(red: 0x00 / 255, green: 0x7A / 255, blue: 0x33 / 255),   // #007A33
    dark: Color(red: 0x12 / 255, green: 0xD9 / 255, blue: 0x65 / 255)     // #12D965
)
private let historyMilestone35 = Color.adaptive(
    light: Color(red: 0xCC / 255, green: 0x47 / 255, blue: 0xDB / 255),   // #CC47DB
    dark: Color(red: 0xDB / 255, green: 0x5F / 255, blue: 0xE8 / 255)     // #DB5FE8
)
// Chosen (not specified): a saturated gold for the top tier — reads
// as "the big one" next to green/purple, and stays clear of carbs'
// amber (#FFB300), the only other warm color already in the palette.
private let historyMilestone75 = Color.adaptive(
    light: Color(red: 0xC9 / 255, green: 0xA2 / 255, blue: 0x27 / 255),   // #C9A227
    dark: Color(red: 0xE0 / 255, green: 0xB9 / 255, blue: 0x3A / 255)     // #E0B93A
)

#if os(iOS)
/// Colors the `UIScrollView` that backs a page-style `TabView` so
/// overscrolling past the first/last page (the rubber-band bounce)
/// shows OUR grey instead of UIKit's default white.
///
/// `UIScrollView.appearance().backgroundColor` was tried first and
/// does nothing here: SwiftUI's page TabView sets its scroll view's
/// backgroundColor explicitly, which always beats an appearance-proxy
/// default. So instead this hangs an invisible, zero-size view off
/// the TabView (as a `.background`) and, once it's actually in the
/// hierarchy, walks UP through `superview` looking for the first
/// `UIScrollView` it finds and recolors THAT directly — same effect
/// SwiftUI's own explicit set has, just applied a moment later.
private struct PagingScrollViewBackgroundFixer: UIViewRepresentable {
    let color: UIColor

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        // Not present on the first layout pass — `view.superview` is
        // nil until after this view is actually inserted, so this has
        // to run after that, on the next runloop turn.
        DispatchQueue.main.async {
            var current: UIView? = view.superview
            while let candidate = current {
                if let scrollView = candidate as? UIScrollView {
                    scrollView.backgroundColor = color
                    return
                }
                current = candidate.superview
            }
        }
    }
}
#endif

// History's "not touched" mark — a visibly lighter grey than
// fillNavy, distinct from both the pageBG page background and the
// black/green marks, so a skipped day (past OR upcoming) still shows
// SOMETHING there instead of empty space.
private let historyNotTouchedColor = Color.adaptive(
    light: Color(red: 0xB9 / 255, green: 0xB9 / 255, blue: 0xB9 / 255),   // #B9B9B9
    dark: Color(red: 0x48 / 255, green: 0x48 / 255, blue: 0x4A / 255)     // #48484A
)
private let historyTodayColor = Color.adaptive(
    light: Color(red: 0x00 / 255, green: 0x68 / 255, blue: 0xFF / 255),   // #0068FF
    dark: Color(red: 0x4D / 255, green: 0x90 / 255, blue: 0xFF / 255)     // #4D90FF
)

// trackers page: all grey (faint/disabled) text and icons
// there use this exact grey, not a fillNavy opacity — and the goal
// input border below it.
private let greyText = Color.adaptive(
    light: Color(red: 0x8B / 255, green: 0x8B / 255, blue: 0x8B / 255),   // #8B8B8B
    dark: Color(red: 0x9A / 255, green: 0x9A / 255, blue: 0x9E / 255)     // #9A9A9E
)
private let goalBorderGrey = Color.adaptive(
    light: Color(red: 0x8D / 255, green: 0x8D / 255, blue: 0x8D / 255),   // #8D8D8D
    dark: Color(red: 0x6E / 255, green: 0x6E / 255, blue: 0x72 / 255)     // #6E6E72
)

// 0.8x applied here, once, rather than at every call site — every
// numberFont/textFont caller (including ones passing their own custom
// size) gets the same 20% reduction automatically.
private let fontScale: CGFloat = 0.8

// iOS reads smaller at the same point size than macOS did in this
// app's original design, so the body-text default is bigger there —
// callers that just write textFont() (no explicit size) pick this up
// automatically per platform; only the small handful of call sites
// that used to hardcode textFont(18) needed updating to drop the
// literal and go back to using the default.
#if os(iOS)
private let bodyTextSize: CGFloat = 26
#else
private let bodyTextSize: CGFloat = 26
#endif

private func numberFont(_ size: CGFloat = 50) -> Font {
    .custom("GoogleSansCode-Medium", size: size * fontScale)
}
private func textFont(_ size: CGFloat = bodyTextSize) -> Font {
    .custom("GoogleSansCode-Medium", size: size * fontScale)
}

/// Today's cell in History's week grid — same symbol as any other day
/// (see `historySymbol`), just a slow opacity fade in and out. Its own
/// tiny view with local @State (not a property on ContentView) so the
/// fade reliably restarts every time this cell is created, rather than
/// depending on shared state that may already be "true" from a
/// previous visit and so never animate again.
/// Today's mark, pulsing — same fixed dot+stripe shape as every other
/// day (see `historyMark`), just fading in and out to read as "live".
private struct PulsingHistoryMark: View {
    let showDot: Bool
    let color: Color
    @State private var faded = false

    var body: some View {
        historyMark(showDot: showDot, color: color)
            .opacity(faded ? 0.35 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    faded = true
                }
            }
    }
}

#if os(iOS)
/// One row of the to-do editor, backed by a real UITextField.
///
/// SwiftUI's own TextField was tried first and can't do two things
/// this list needs:
///
///  • Focus the moment a row is created. @FocusState in this
///    NavigationStack-inside-a-sheet either ignored the assignment or
///    applied it whenever the next unrelated redraw happened along
///    (which was the "keyboard takes ~5 seconds" symptom). Calling
///    becomeFirstResponder() directly has no such ambiguity.
///  • Report Backspace pressed on an ALREADY-empty field. That's the
///    keystroke that removes a line in Notes, and SwiftUI simply
///    doesn't surface it — only UITextFieldDelegate does.
///
/// Focus stays owned by the caller: it passes `isFocused` down, and
/// gets told through `onFocusChange` when the user moves focus
/// themselves, so there's still one source of truth for which row is
/// being edited.
struct TodoTextField: UIViewRepresentable {
    /// Backspace on an ALREADY-empty field is the gesture that removes
    /// a line in Notes, and it has to be caught by overriding
    /// `deleteBackward()`. The obvious-looking route —
    /// `shouldChangeCharactersIn` with a zero-length range — does NOT
    /// fire dependably when there's nothing left to delete, which is
    /// exactly the case that matters here; emptied rows just sat there
    /// refusing to go away.
    final class BackspaceReportingTextField: UITextField {
        var onBackspaceWhenEmpty: (() -> Void)?

        override func deleteBackward() {
            let wasEmpty = (text ?? "").isEmpty
            super.deleteBackward()
            if wasEmpty { onBackspaceWhenEmpty?() }
        }
    }

    @Binding var text: String
    let isFocused: Bool
    let textColor: UIColor
    let font: UIFont?
    /// `.right` on the trackers page (fields hang off the right edge,
    /// under the "todo" label's column); `.left` in the first-run
    /// tour, where the field is the only thing on the page.
    var alignment: NSTextAlignment = .right
    let onFocusChange: (Bool) -> Void
    let onSubmit: () -> Void
    let onBackspaceWhenEmpty: () -> Void

    func makeUIView(context: Context) -> BackspaceReportingTextField {
        let field = BackspaceReportingTextField()
        field.delegate = context.coordinator
        field.returnKeyType = .next
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.borderStyle = .none
        field.backgroundColor = .clear
        // Matches the SwiftUI rows around it: same face, same
        // underline the design calls for.
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: textColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        if let font { attributes[.font] = font }
        field.defaultTextAttributes = attributes
        // AFTER defaultTextAttributes, never before: assigning that
        // dictionary resets the alignment back to natural (left), so
        // setting it first silently does nothing.
        field.textAlignment = alignment
        field.onBackspaceWhenEmpty = onBackspaceWhenEmpty
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )
        return field
    }

    func updateUIView(_ field: BackspaceReportingTextField, context: Context) {
        context.coordinator.parent = self
        // Re-assigned every update so it calls into the CURRENT row's
        // handler rather than the one from when the view was created.
        field.onBackspaceWhenEmpty = onBackspaceWhenEmpty
        if field.text != text { field.text = text }
        field.textAlignment = alignment
        if isFocused, !field.isFirstResponder {
            field.becomeFirstResponder()
        } else if !isFocused, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TodoTextField

        init(_ parent: TodoTextField) { self.parent = parent }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            parent.onFocusChange(true)
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            parent.onFocusChange(false)
        }
    }
}
#endif

/// The hint shown on an empty to-do row, typed out and rubbed back
/// out again a character at a time so it reads as someone thinking
/// out loud rather than as static placeholder text.
///
/// Its own view with its own @State and timer ON PURPOSE, rather than
/// driving the TextField's `prompt` from the parent: a prompt would
/// mean re-rendering the field itself ~15x a second, and needless
/// redraws around a focused text field are exactly what left this
/// section unable to take focus at all once before. Here the ticking
/// is contained to this little view, and the field next to it never
/// changes. It only exists while a row is blank, so when there's
/// nothing to hint at, nothing is running either.
private struct TypingSuggestion: View {
    let suggestions: [String]
    let color: Color

    @State private var wordIndex = 0
    @State private var shownCount = 0
    @State private var isDeleting = false
    @State private var holdTicks = 0
    // @State so it survives the parent re-rendering this struct;
    // a plain `let` would hand out a fresh, disconnected publisher.
    @State private var timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    private var word: String {
        suggestions.isEmpty ? "" : suggestions[wordIndex % suggestions.count]
    }

    var body: some View {
        Text(String(word.prefix(shownCount)))
            .foregroundStyle(color)
            .underline()
            .onReceive(timer) { _ in advance() }
    }

    private func advance() {
        guard !suggestions.isEmpty else { return }

        if isDeleting {
            if shownCount > 0 {
                shownCount -= 1
            } else {
                // Beat of nothing between words, so it doesn't snap
                // straight from empty into the next one.
                holdTicks += 1
                if holdTicks >= 4 {
                    holdTicks = 0
                    isDeleting = false
                    wordIndex = (wordIndex + 1) % suggestions.count
                }
            }
        } else if shownCount < word.count {
            shownCount += 1
        } else {
            // Sit on the finished word long enough to read it.
            holdTicks += 1
            if holdTicks >= 16 {
                holdTicks = 0
                isDeleting = true
            }
        }
    }
}

/// The ONE mark shape used everywhere in History — a small dot (only
/// when the day succeeded) sitting above a short stripe (always
/// shown, colored by status). Real Circle/Rectangle shapes, not a
/// Text+underline trick — the text-based version was rendering some
/// marks invisible depending on size/context, a fixed-size shape
/// can't do that regardless of font quirks.
private func historyMark(showDot: Bool, color: Color) -> some View {
    VStack(spacing: 6) {
        Circle()
            .fill(showDot ? color : Color.clear)
            .frame(width: 10, height: 10)
        // The stripe STRETCHES to fill its grid column rather than
        // being a fixed 22pt left-aligned inside it. With a fixed
        // width the last column's stripe stopped well short of the
        // column's right edge, so the row's right margin came out as
        // sideInset PLUS that leftover — visibly bigger than the flat
        // sideInset on the left. Filling the column makes the last
        // stripe end exactly at the content's right edge, so both
        // sides are just sideInset and the row reads as symmetric.
        Rectangle()
            .fill(color)
            .frame(height: 3)
            .frame(maxWidth: .infinity)
    }
    .frame(height: 32)
}

#if os(macOS)
/// Catches two-finger trackpad gestures (scroll wheel events with
/// precise deltas) so macOS can page Home<->History the same way
/// iOS's swipe does, and cycle the active tracker on a vertical
/// scroll — there's no SwiftUI gesture for a raw trackpad swipe, so
/// this bridges to AppKit's `scrollWheel(with:)`. Transparent, sized
/// to fill its container as a `.background()` — sits behind the real
/// content so buttons on top still get their own clicks; only scroll
/// events (which have nothing else to hit) end up here.
///
/// NOTE: direction here assumes natural scrolling is ON (Apple's
/// default) — under natural scrolling, swiping right makes content
/// follow your fingers, which reports as a POSITIVE scrollingDeltaX.
/// This is our best guess without a live Mac to test on; if swipes
/// feel backwards, just swap the `onSwipeRight`/`onSwipeLeft` (or
/// `onScrollUp`/`onScrollDown`) branches below.
private struct TrackpadSwipeCatcher: NSViewRepresentable {
    let onSwipeRight: () -> Void
    let onSwipeLeft: () -> Void
    let onScrollUp: () -> Void
    let onScrollDown: () -> Void

    func makeNSView(context: Context) -> SwipeCatchingView {
        let view = SwipeCatchingView()
        view.onSwipeRight = onSwipeRight
        view.onSwipeLeft = onSwipeLeft
        view.onScrollUp = onScrollUp
        view.onScrollDown = onScrollDown
        return view
    }

    func updateNSView(_ nsView: SwipeCatchingView, context: Context) {
        nsView.onSwipeRight = onSwipeRight
        nsView.onSwipeLeft = onSwipeLeft
        nsView.onScrollUp = onScrollUp
        nsView.onScrollDown = onScrollDown
    }

    final class SwipeCatchingView: NSView {
        var onSwipeRight: (() -> Void)?
        var onSwipeLeft: (() -> Void)?
        var onScrollUp: (() -> Void)?
        var onScrollDown: (() -> Void)?

        private var accumulatedX: CGFloat = 0
        private var accumulatedY: CGFloat = 0
        private var consumed = false

        override func scrollWheel(with event: NSEvent) {
            // Only trackpad gestures have precise deltas — a plain
            // mouse wheel just passes through untouched.
            guard event.hasPreciseScrollingDeltas else {
                super.scrollWheel(with: event)
                return
            }
            if event.phase == .began {
                accumulatedX = 0
                accumulatedY = 0
                consumed = false
            }
            accumulatedX += event.scrollingDeltaX
            accumulatedY += event.scrollingDeltaY

            guard !consumed else { return }
            let threshold: CGFloat = 60
            // Whichever axis moved further decides what the gesture
            // means: mostly-horizontal pages Home<->History,
            // mostly-vertical cycles the active tracker.
            if abs(accumulatedX) > abs(accumulatedY), abs(accumulatedX) >= threshold {
                consumed = true
                if accumulatedX > 0 { onSwipeRight?() } else { onSwipeLeft?() }
            } else if abs(accumulatedY) >= threshold {
                consumed = true
                if accumulatedY > 0 { onScrollUp?() } else { onScrollDown?() }
            }
        }
    }
}
#endif

struct ContentView: View {
    @EnvironmentObject private var store: WaterStore
    @Environment(\.scenePhase) private var scenePhase

    // macOS only: whether the full-window settings flow (trackers +
    // sync/reset) or the quick-add panel is showing in place of the
    // home screen. History isn't part of this anymore — see
    // `homePage`.
    private enum BottomMode: Equatable { case main, quickAdd, settings }

    @State private var bottomMode: BottomMode = .main
    @State private var activeMetric: TrackerKind = .water
    // Stable, created once — NOT inline in `body` (which is
    // re-evaluated constantly), otherwise a fresh, disconnected timer
    // gets created almost every redraw and never reliably ticks.
    @State private var syncTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @State private var pendingAmount = 0   // shared by the water/protein quick-add panel
    // Which to-do row currently holds the keyboard, by task id — nil
    // means the list isn't being edited at all (which is also what
    // brings "+ add to do" back). Keyed by id, never by index: rows
    // get removed out from under the focused one, and an index would
    // then point at a different task (or off the end) while the
    // keyboard is still up.
    //
    // Plain @State, not @FocusState: on iOS the row is a UITextField
    // (see `TodoTextField`) that takes focus by calling
    // becomeFirstResponder() itself and reports back when the user
    // moves focus. @FocusState was the source of the "keyboard comes
    // up eventually, or not at all" behaviour here.
    @State private var focusedTodo: UUID?
    #if os(macOS)
    // AppKit still goes through SwiftUI's own field, which needs a
    // real @FocusState; kept mirrored with `focusedTodo` above so
    // there's still only one thing the rest of the code reads.
    @FocusState private var macFocusedTodo: UUID?
    #endif

    // Hints shown on a blank to-do row, typed in and out one letter at
    // a time — the animation itself lives in `TypingSuggestion`.
    private static let todoSuggestions = ["no sugar", "no alcohol", "read 10 min", "45min sport"]
    #if DEBUG
    @State private var showingClearAllHistoryConfirm = false
    #endif

    private let windowSize = CGSize(width: 340, height: 640)
    private let sideInset: CGFloat = 22
    private let bottomInset: CGFloat = 10
    private let lineHeight: CGFloat = 40    // confirmed: line-height everywhere (incl. popups)
    /// Gap between top-level tracker sections on the trackers page
    /// (to-do / water / protein / coffee / carbs) — see `todosPageRows`.
    private let trackerSectionGap: CGFloat = 20

    // MARK: History layout
    //
    // Six per row, not seven: a week-shaped grid invites reading it as
    // a calendar (which weekday is this?), and that's exactly the
    // reading this page doesn't want.
    private let historyColumns = 6
    private let historyHeaderHeight: CGFloat = 48
    /// Where the grid's FIRST row sits, as a fraction of the full
    /// screen height. Fixed on purpose: the grid is anchored here and
    /// only ever grows downward, so adding a day never shifts the rows
    /// you were already looking at. Tune this one number to move the
    /// whole block up or down.
    private let historyGridTopFraction: CGFloat = 0.40
    /// Breathing room between the last row of marks and the legend.
    /// Also the trigger point: while there's more than this going
    /// spare the legend sits pinned at the bottom of the screen, and
    /// once the grid grows into it the legend gets pushed down and the
    /// page starts scrolling, with the legend at the very bottom.
    private let historyLegendMinGap: CGFloat = 50
    private let historyLegendSampleWidth: CGFloat = 33
    private let historyLegendSampleGap: CGFloat = 14

    // Lets a pending amount be typed directly instead of only +/-50
    // taps. Strips non-digits so the field can't end up in a state
    // that doesn't parse back to an Int.
    private func amountBinding(_ value: Binding<Int>) -> Binding<String> {
        Binding(
            get: { String(value.wrappedValue) },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)
                value.wrappedValue = Int(digits) ?? 0
            }
        )
    }

    // Shared form-field look used by both the quick-add panel and the
    // goals panel: a grey box with just the editable number — the
    // unit goes in the row's label instead, e.g. "protein(gr)". Grey
    // ("0", untouched) vs full color (an actual value) makes it clear
    // at a glance whether the field holds something or not.
    private func amountField(value: Binding<Int>) -> some View {
        TextField("", text: amountBinding(value))
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.plain)
            .foregroundStyle(value.wrappedValue == 0 ? fillNavy.opacity(0.4) : fillNavy)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(width: 140)
            .background(pageBG)
    }

    // Thousands-separated with "." (e.g. 4000 -> "4.000"), matching
    // the design's number formatting.
    private static let amountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        f.groupingSize = 3
        f.usesGroupingSeparator = true
        return f
    }()

    private static func formatAmount(_ n: Int) -> String {
        amountFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private var enabledTrackers: [TrackerKind] {
        TrackerKind.allCases.filter { store.isTrackerEnabled($0) }
    }

    // Scrolling/dragging vertically on the home screen steps through
    // the enabled trackers, same list/order as the tap targets in the
    // left column (`enabledTrackers`, i.e. todo, water, protein).
    // "Scrolling up" (content moving up, same feel as scrolling down a
    // list to see what's next) steps forward; scrolling down steps
    // back. Wraps around either way.
    private func cycleActiveMetric(forward: Bool) {
        let list = enabledTrackers
        guard list.count > 1, let index = list.firstIndex(of: activeMetric) else { return }
        let count = list.count
        activeMetric = forward ? list[(index + 1) % count] : list[(index - 1 + count) % count]
    }

    private var currentProgress: Double {
        switch activeMetric {
        case .todo: store.todoProgress
        case .water: store.progress
        case .protein: store.proteinProgress
        case .coffee: store.coffeeProgress
        case .carbs: store.carbsProgress
        case .steps: store.stepsProgress
        case .movement: store.movementProgress
        case .sleep: store.sleepProgress
        case .cigarettes: store.cigarettesProgress
        }
    }

    // True while the active tab is one of the trackers whose goal can
    // mean "stay under this" rather than "reach this" (coffee/
    // calories/cigarettes — see GoalMode) AND that switch is
    // currently set to .max. Drives both `fillColor` and the home
    // screen's background: green while at/under the max, flat red
    // once over — see the MARK above the max-mode colors for why.
    private var isActiveMetricMaxMode: Bool {
        activeMetric.supportsGoalModeSwitch && store.goalMode(for: activeMetric) == .max
    }

    private var isActiveMetricOverMax: Bool {
        isActiveMetricMaxMode && currentProgress > 1.0
    }

    // Only the safe/green state breathes — once you're over the max
    // and the screen has gone flat red, a pulse would read as a
    // second "warning" signal fighting the red itself, so it stops.
    private var showsMaxModePulse: Bool {
        isActiveMetricMaxMode && !isActiveMetricOverMax
    }

    // `numberStack`/`mainMenu` mirror every number/label twice — once
    // in `fillNavy`, once in this color masked to just the fill
    // rectangle — so text stays readable whether it's sitting over
    // the background or over the fill. `pageBG` is the right masked
    // color for every OTHER tracker (their fills are bright/saturated
    // enough that pageBG's near-black dark-mode value still reads
    // fine on top), but the max-mode green/red fills are much lower-
    // luminance — dark-mode pageBG text on top of them was reading as
    // barely-visible dark-on-dark. Plain white instead, only while a
    // max-mode tracker is active.
    private var fillTextColor: Color {
        isActiveMetricMaxMode ? .white : pageBG
    }

    // Per-tracker color while tracking (water blue, protein red,
    // coffee brown, carbs amber, steps green, movement orange, sleep
    // indigo) — EXCEPT once all of today's to-dos are done, which
    // overrides every tab to the green celebration color regardless
    // of which one is active.
    private var fillColor: Color {
        // Max-mode green/red overrides everything else, including the
        // all-done celebration color below — see the max-mode MARK.
        if isActiveMetricMaxMode {
            return isActiveMetricOverMax ? maxModeOverColor : fillAccent
        }
        guard store.todoProgress < 1.0 else { return fillAccent }
        switch activeMetric {
        case .water: return fillWater
        case .protein: return fillProtein
        case .coffee: return fillCoffee
        case .carbs: return fillCarbs
        case .steps: return fillSteps
        case .movement: return fillMovement
        case .sleep: return fillSleep
        case .cigarettes: return fillCigarettes
        case .todo: return fillNavy
        }
    }

    // The home screen's own background layer — plain `pageBG`
    // normally, but swapped to the max-mode green/red scheme while
    // the active tracker is in max mode (see the max-mode MARK).
    // Deliberately scoped to just this one call site rather than
    // touching `pageBG` itself, which many other unrelated pages
    // still use unconditionally.
    private var homeScreenBG: Color {
        guard isActiveMetricMaxMode else { return pageBG }
        return isActiveMetricOverMax ? maxModeOverColor : maxModeSafeBG
    }

    // Shared by both platforms: settings pushes into these via
    // NavigationStack — a native sliding transition + back button on
    // both, not hand-rolled. iOS hosts it in a real .sheet
    // (partial-height, drag-dismissible); macOS hosts the identical
    // NavigationStack in-place, full-window, inside the MenuBarExtra
    // popover — no .sheet there, since we already hit a real crash
    // once with a system-level presentation (NSOpenPanel) stealing
    // focus from this popover and tearing down the view mid-flight.
    // NavigationStack itself doesn't create a new OS window, so it
    // doesn't have that risk.
    // Settings opens to a small root menu now — "trackers" (the
    // to-do list + tracker on/off + goals, combined) and "test
    // stuff" (sync status/reset + the DEBUG-only seed/wipe buttons).
    private enum SettingsDestination: Hashable {
        case todos
        case allLogs
        case testStuff
        var title: String {
            switch self {
            // The page is "trackers" — it's the to-do list AND every
            // other tracker's on/off + goal, so it's named after the
            // whole page rather than just its first section.
            case .todos: "trackers"
            case .allLogs: "all logs"
            case .testStuff: "test stuff"
            }
        }
    }

    @State private var settingsPath: [SettingsDestination] = []
    #if os(iOS)
    @State private var showingSettingsSheet = false
    @State private var showingQuickAddSheet = false
    // History's day-detail opens as the SAME kind of layover as
    // settings (a native sheet, rounded card + circular glass
    // buttons) rather than a full-page push within His+tory's own
    // NavigationStack — macOS has no sheets (see the note on
    // `settingsPath` further down), so it keeps using
    // `historyDetailPath`'s push instead.
    @State private var showingHistoryDaySheet = false
    // Tapping a tracker's goal (or "add" on one that's off) opens a
    // wheel-picker sheet for that tracker — nil while none is open.
    @State private var goalSheetKind: TrackerKind?
    @State private var pendingGoal = 0
    // Staged min/max choice for the goal sheet's Calendar-style pill
    // switch (coffee/calories/cigarettes only — see
    // `TrackerKind.supportsGoalModeSwitch`); seeded from the store in
    // `openGoalSheet` and committed alongside `pendingGoal` when the
    // sheet's checkmark/save is tapped.
    @State private var pendingGoalMode: GoalMode = .min
    @State private var historySheetDate: Date = .now

    // First-run tour. `hasSeenTour` is @AppStorage — i.e. plain
    // UserDefaults, deliberately NOT part of `AppData` and so NOT
    // synced through CloudKit: it's a property of this install, not
    // of the account, and hanging it off the settings record would
    // put it at the mercy of that record's last-write-wins merge.
    // Each device therefore shows the tour exactly once.
    @AppStorage("hasSeenFirstRunTour") private var hasSeenTour = false
    // Ships OFF: this build's TestFlight users shouldn't see the tour
    // yet, but it should stay reachable for testing — see
    // "replay tour" under test stuff, and the `onAppear` this gates.
    // One line to flip when it's ready for real users.
    private let tourEnabledOnLaunch = false
    @State private var showingTour = false
    @State private var tourPage: TourPage = .goal
    @State private var tourGoalKind: TrackerKind?
    @State private var tourHabit = ""
    @State private var tourHabitFocused = false
    @State private var tourFillProgress: CGFloat = 0
    /// The to-do the tour created, if any — kept so `commitTourHabit`
    /// can tell "already saved" from "not saved yet" and never write
    /// the same habit twice.
    @State private var tourHabitTaskID: UUID?
    #endif

    // History is one page again — day streak, "this week"'s single
    // row, "previous" (all-time totals) and then every week before
    // this one, all stacked top to bottom, scrollable. Reached by
    // swiping (not part of settings). Separate navigation state for
    // pushing a day's detail so it doesn't interact with settingsPath
    // at all.
    private enum HomePage: Hashable { case home, history }
    @State private var homePage: HomePage = .home
    @State private var historyDetailPath: [Date] = []

    // Custom (not the system's bottom-placed) page indicator — one
    // dot per page, the current one dark and the other faint. Left-
    // aligned now (used to be centered) since it shares its row with
    // the hamburger button — see `topBar`.
    private var homePageIndicator: some View {
        HStack(spacing: 10) {
            ForEach([HomePage.home, .history], id: \.self) { page in
                Circle()
                    .fill(homePage == page ? fillNavy : fillNavy.opacity(0.3))
                    .frame(width: pageIndicatorDotSize, height: pageIndicatorDotSize)
            }
        }
    }

    // Opens settings — shared by the hamburger button (below) and,
    // on iOS, was previously also a "settings" text row in the
    // bottom-left tab list (removed; the hamburger is the only entry
    // point now).
    private func openSettings() {
        #if os(iOS)
        settingsPath.removeAll()
        showingSettingsSheet = true
        #else
        bottomMode = .settings
        #endif
    }

    // Two stacked dots, same size as the pagination dots — a plain
    // "menu" glyph rather than the hamburger image, both solid navy
    // (unlike the pagination dots, this one has no on/off state).
    private var hamburgerButton: some View {
        Button(action: openSettings) {
            VStack(spacing: 6) {
                Circle().fill(fillNavy).frame(width: pageIndicatorDotSize, height: pageIndicatorDotSize)
                Circle().fill(fillNavy).frame(width: pageIndicatorDotSize, height: pageIndicatorDotSize)
            }
            // The two dots alone are a tiny target (~12pt wide) —
            // pad the tappable area well past the visible glyph
            // without changing how it looks.
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Top bar: page dots (leading) + menu button (trailing), one row,
    // replacing the old centered-dots-only overlay — this is what
    // actually opens settings now.
    private var topBar: some View {
        HStack {
            homePageIndicator
            Spacer()
            hamburgerButton
        }
    }

    // One shared vertical rhythm for the top of EVERY page: safe area,
    // then the page dots, then the first big number. Both the home
    // screen's numberStack and History's rows derive their top padding
    // from `contentTopPadding` alone, so "3 done" and "4 streak" land
    // on exactly the same baseline no matter which page you swipe to —
    // previously each page did its own +8 math and drifted apart.
    private let pageIndicatorDotSize: CGFloat = 10
    private let pageIndicatorTopGap: CGFloat = 24
    private let pageIndicatorBottomGap: CGFloat = 50

    private func contentTopPadding(_ topInset: CGFloat) -> CGFloat {
        topInset + pageIndicatorTopGap + pageIndicatorDotSize + pageIndicatorBottomGap
    }

    var body: some View {
        GeometryReader { geo in
            #if os(macOS)
            // macOS: settings (and anything it leads to) is a
            // full-window NavigationStack in place of the home
            // screen — bottomMode just picks whether that's showing
            // at all; which page WITHIN it is showing is settingsPath.
            Group {
                switch bottomMode {
                case .settings, .quickAdd:
                    settingsFlow(size: geo.size)
                case .main:
                    homeOrHistoryMac(geo: geo)
                        .overlay(alignment: .top) {
                            topBar
                                .padding(.top, geo.safeAreaInsets.top + pageIndicatorTopGap)
                                .padding(.horizontal, sideInset)
                        }
                }
            }
            #else
            // iOS: a native page-swipe TabView, History only to the
            // RIGHT of Home — swipe left from Home to reach it, swipe
            // right to return. The native page dots are turned off in
            // favor of our own `homePageIndicator` overlay (top, not
            // the system's bottom placement, and styled to match).
            //
            // Explicit .frame(geo.size) on the TabView itself, not
            // just relying on it filling a GeometryReader — a
            // page-style TabView has sized itself to intrinsic content
            // rather than the reader's full size before, which put the
            // ".overlay(alignment: .top)" dots wherever THAT
            // (content-sized) top edge landed instead of the real
            // screen top — i.e. wherever content happened to end,
            // mid-page, rather than at the top.
            // The frame here MUST be the true full-screen size, not
            // `geo.size`: `geo` is safe-area-constrained, so framing to
            // it and THEN calling .ignoresSafeArea() centers that
            // too-short frame inside the full screen — which is exactly
            // what pushed every page up and clipped the bottom menu
            // behind the home indicator. A nested reader with
            // .ignoresSafeArea() applied to IT reports the real size
            // (same trick numberStack/the fill rectangle already use).
            GeometryReader { fullGeo in
                TabView(selection: $homePage) {
                    // The fixer has to be a DESCENDANT of a page's own
                    // content, not the TabView itself — `.background`
                    // on the TabView puts it BEHIND as a sibling in the
                    // surrounding SwiftUI hierarchy, never inside the
                    // paging UIScrollView, so walking up from it never
                    // reaches that scroll view at all. Hung off each
                    // page instead, it's genuinely inside.
                    homeScreen(geo: geo)
                        .background(
                            PagingScrollViewBackgroundFixer(color: UIColor(pageBG))
                        )
                        .tag(HomePage.home)
                    historyFullPage(geo: geo)
                        .background(
                            PagingScrollViewBackgroundFixer(color: UIColor(pageBG))
                        )
                        .tag(HomePage.history)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(width: fullGeo.size.width,
                       height: fullGeo.size.height)
                .overlay(alignment: .top) {
                    topBar
                        .padding(.top, geo.safeAreaInsets.top + pageIndicatorTopGap)
                        .padding(.horizontal, sideInset)
                }
            }
            .ignoresSafeArea()
            #endif
        }
        // macOS: this is a menu-bar popover, so it stays a fixed
        // small size. iOS: let it size to whatever the WindowGroup
        // gives it (the full screen) — a fixed 340x640 box would
        // just float in the middle of the default black background.
        #if os(macOS)
        .frame(width: windowSize.width, height: windowSize.height)
        #endif
        // Pull in whatever the other device wrote, and re-evaluate
        // today's totals across a midnight rollover — once when this
        // view appears (menu bar popover opening / app foregrounding
        // both trigger this), then every few seconds while it's open,
        // since there's no push notification without a paid iCloud
        // entitlement.
        .onAppear { store.tick() }
        .onReceive(syncTimer) { _ in
            store.tick()
        }
        // Immediate refresh the moment you switch back to the app —
        // don't wait up to 5s for the next timer tick. Also the only
        // realistic hook on iOS, where a backgrounded app is fully
        // suspended and the timer above doesn't fire at all until
        // it's foregrounded again anyway.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                store.tick()
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showingSettingsSheet) {
            settingsSheet
        }
        .sheet(isPresented: $showingQuickAddSheet) {
            quickAddSheet
        }
        .sheet(isPresented: $showingHistoryDaySheet) {
            historyDaySheet
        }
        // First launch only. A cover, not a sheet: the tour owns the
        // whole screen (page 3's fill runs edge to edge) and isn't
        // something to swipe away half-read — leaving is the × or
        // running it to the end.
        .fullScreenCover(isPresented: $showingTour) {
            tourView
        }
        .onAppear {
            // `tourEnabledOnLaunch` gates ONLY the automatic show —
            // "replay tour" under test stuff still opens it directly
            // regardless, so it stays reachable for testing while
            // real TestFlight users don't see it yet. Flip this back
            // on when it's ready to ship: every existing install
            // still has `hasSeenTour == false` (it was never set,
            // since this branch never ran), so they'll all get it
            // exactly once on their next launch after that — the same
            // "shown once" guarantee a brand new install gets, just
            // delayed to whenever you turn it on.
            if tourEnabledOnLaunch, !hasSeenTour { showingTour = true }
        }
        #endif
    }

    // The actual home screen: numbers + fill + bottom tab row, plus
    // the two panels that stay layered over it (quick-add, settings).
    private func homeScreen(geo: GeometryProxy) -> some View {
        return ZStack(alignment: .topLeading) {
            // Background bleeds edge-to-edge (under the dynamic
            // island / status bar / home indicator on iOS) — but
            // that's ONLY these two color layers. The content below
            // stays laid out against `geo.size`, which GeometryReader
            // reports as the safe-area-constrained size, so the
            // numbers/menu never end up hidden behind the dynamic
            // island.
            homeScreenBG
                .ignoresSafeArea()

            // Breathing highlight for the max-mode "safe" (green)
            // state — a plain white wash whose opacity oscillates
            // between 0 and a low ceiling, lightening/darkening the
            // green underneath it rather than swapping in a second
            // flat color. Driven by `TimelineView(.animation)` (system
            // time in, opacity out) rather than a `@State` flag toggled
            // once inside a `repeatForever` animation — that first cut
            // LOOKED right but silently stalled after a few seconds:
            // `store.tick()` (a periodic, unrelated `objectWillChange`
            // used to notice midnight rollovers / pull CloudKit) forces
            // this whole view to re-evaluate outside of any animation
            // transaction, and a `repeatForever` loop doesn't reliably
            // survive that kind of external interruption. A
            // `TimelineView` has no persistent animation state to lose
            // — every tick it just re-reads the clock — so it can't be
            // knocked out of rhythm by an unrelated re-render.
            TimelineView(.animation) { timeline in
                let period = 3.2
                let t = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period)
                let phase = (sin(2 * Double.pi * t / period) + 1) / 2   // 0...1
                Color.white
                    .opacity(showsMaxModePulse ? phase * 0.16 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            // A nested GeometryReader with .ignoresSafeArea() applied
            // TO IT directly reports the TRUE full-screen size in
            // `fullGeo.size`, regardless of the outer (safe-area-
            // constrained) `geo` — this is what actually gets the fill
            // to reach the real top of the screen. `bottomMenu`'s own
            // mirrored-text mask lives in THIS SAME reader now (it used
            // to compute its own "true height" via the shared
            // `trueFullHeight` arithmetic instead — that's the exact
            // anti-pattern that already burned this fill once: it
            // isn't reliably identical to what a nested reader reports,
            // and using it made the mask drift out of sync with the
            // real fill edge. Sharing this one `fullGeo.size.height`
            // for both is what guarantees they can't disagree.
            GeometryReader { fullGeo in
                // Capped at the screen's own height — max-mode trackers
                // (see GoalMode) let `currentProgress` run past 100%
                // with NO ceiling (260%, 900%, however far over you've
                // logged), and letting that uncapped value flow
                // straight into `fillColor`'s `.frame(height:)` and the
                // masks below reproduces the EXACT class of bug the
                // `Color.clear` anchor just below was already added to
                // fix once (see its comment): a genuinely oversized
                // child throws off this ZStack's own bottom-alignment
                // math, and `bottomMenu` — also bottom-aligned, in the
                // very same ZStack — was observed rendering with all
                // but its first row pushed below the visible screen
                // once a max-mode tracker went far enough over.
                // Confirmed empirically: capping at 1.5x the screen's
                // height still reproduced it, capping at exactly 1x
                // (this container can never legitimately need MORE
                // than its own height to read as "fully covered, no
                // visible seam" — the whole point of letting
                // `currentProgress` itself run uncapped) does not.
                let fillHeight = min(fullGeo.size.height * currentProgress, fullGeo.size.height)

                ZStack(alignment: .bottom) {
                    // Invisible, always-full-size anchor. Without this,
                    // when BOTH real children resolve short — fillColor
                    // at fillHeight 0 (0% progress) and bottomMenu's own
                    // modest content height — the ZStack stops actually
                    // touching the true edges of the explicit
                    // `.frame(width:height:)` below: everything renders
                    // shifted up, floating mid-screen with a dead grey
                    // gap underneath, even though this reader still
                    // (correctly) MEASURES `fullGeo.size.height` as the
                    // true screen height. Confirmed by isolating it down
                    // to a single small Rectangle in a same-size
                    // `.frame`'d ZStack — the fix was exactly one
                    // full-bleed sibling. Cheapest, safest one: Color.clear.
                    Color.clear

                    fillColor
                        .frame(height: fillHeight)
                        .frame(maxWidth: .infinity, alignment: .bottom)

                    // bottomMenu sits `safeAreaInsets.bottom` above the
                    // true bottom (same "clear of the home indicator"
                    // spot it always has) — padding it up from this
                    // ZStack's own bottom edge (== the true bottom,
                    // since the ZStack below is sized to fullGeo and
                    // this reader ignores the safe area) reproduces
                    // that without a second height formula.
                    bottomMenu(fillHeight: max(0, fillHeight - geo.safeAreaInsets.bottom))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, geo.safeAreaInsets.bottom)
                }
                .frame(width: fullGeo.size.width, height: fullGeo.size.height)
            }
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.5), value: currentProgress)
            .animation(.easeOut(duration: 0.25), value: activeMetric)

            numberStack(topInset: geo.safeAreaInsets.top)
        }
        #if os(iOS)
        // Vertical drag cycles the active tracker — only when the
        // drag is clearly more vertical than horizontal, so it
        // doesn't fight the enclosing TabView's own left/right paging
        // swipe (that one owns horizontal drags to switch to History).
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let dy = value.translation.height
                    let dx = value.translation.width
                    guard abs(dy) > abs(dx), abs(dy) > 30 else { return }
                    withAnimation { cycleActiveMetric(forward: dy < 0) }
                }
        )
        #endif
    }

    // MARK: - Combined overview: one row per enabled tracker,
    // mirrored across the fill line like before.

    private func overviewRow(for kind: TrackerKind) -> (left: String, right: String) {
        switch kind {
        case .todo:
            let total = Self.formatAmount(store.todoItems.count)
            let done = store.todoCompletedCount
            let pct = Int(store.todoProgress * 100)
            let left = store.todoProgress >= 1.0 ? "Big succes!" : "\(done) done"
            return (left, "\(total)(\(pct)%)")
        case .water:
            let pct = Int(store.progress * 100)
            return ("\(Self.formatAmount(store.todayTotal)) ml", "\(Self.formatAmount(store.data.goalML))(\(pct)%)")
        case .protein:
            let pct = Int(store.proteinProgress * 100)
            return ("\(Self.formatAmount(store.todayProteinTotal)) gr", "\(Self.formatAmount(store.data.proteinGoalG))(\(pct)%)")
        case .coffee:
            let pct = Int(store.coffeeProgress * 100)
            return ("\(Self.formatAmount(store.todayCoffeeTotal)) cups", "\(Self.formatAmount(store.data.coffeeGoal))(\(pct)%)")
        case .carbs:
            let pct = Int(store.carbsProgress * 100)
            return ("\(Self.formatAmount(store.todayCarbsTotal)) gr", "\(Self.formatAmount(store.data.carbsGoalG))(\(pct)%)")
        case .steps:
            let pct = Int(store.stepsProgress * 100)
            return ("\(Self.formatAmount(store.todayStepsTotal))", "\(Self.formatAmount(store.data.stepsGoal))(\(pct)%)")
        case .movement:
            let pct = Int(store.movementProgress * 100)
            return ("\(Self.formatAmount(store.todayMovementTotal)) min", "\(Self.formatAmount(store.data.movementGoalMin))(\(pct)%)")
        case .sleep:
            let pct = Int(store.sleepProgress * 100)
            return ("\(Self.formatAmount(store.todaySleepTotal)) hr", "\(Self.formatAmount(store.data.sleepGoalHr))(\(pct)%)")
        case .cigarettes:
            let pct = Int(store.cigarettesProgress * 100)
            return ("\(Self.formatAmount(store.todayCigarettesTotal))", "\(Self.formatAmount(store.data.cigarettesGoal))(\(pct)%)")
        }
    }

    // All text is a flat #1E1E1E now — no more mirrored dark/light
    // swap against the fill (that effect only made sense when the
    // fill itself varied in darkness per tracker; now every bar is
    // the same #00BC60 green, which dark text reads fine against on
    // its own). `topInset` clears the dynamic island — comes from the
    // OUTER GeometryReader in `homeScreen`, not a safe-area-ignoring
    // nested one (which reports ~0 for `.safeAreaInsets` even though
    // its `.size` correctly expands — bit us once already).
    // Pixel-precise mirror: draw the numbers twice (once dark, once
    // light), mask the light copy to exactly the fill rectangle — back
    // on, now that fills vary in color/brightness again (blue/red/
    // green), so a single flat text color no longer has reliable
    // contrast everywhere. `topInset` comes from the OUTER
    // GeometryReader in `homeScreen` (not a safe-area-ignoring nested
    // one, which reports ~0 for `.safeAreaInsets` even though its
    // `.size` correctly expands).
    private func numberStack(topInset: CGFloat) -> some View {
        let todoComplete = store.todoProgress >= 1.0
        // Everything dims to 50% once today's to-dos are all done,
        // EXCEPT the "Big succes!" line itself, which stays at full
        // opacity so it's the one thing that still pops. Applied per-
        // Text inside `content`, which the mirror draws twice below —
        // both copies get the same opacity, so it composes fine with
        // the mask.
        let dimmedOpacity: Double = todoComplete ? 0.5 : 1

        return GeometryReader { fullGeo in
            // Same cap as `homeScreen`'s own `fillHeight` — see its
            // comment; this mask is independently computed but
            // vulnerable to the identical oversized-child issue.
            let fillHeight = min(fullGeo.size.height * currentProgress, fullGeo.size.height)

            let content = VStack(alignment: .leading, spacing: 0) {
                ForEach(enabledTrackers) { kind in
                    let row = overviewRow(for: kind)
                    let isBigSuccess = kind == .todo && todoComplete

                    // .firstTextBaseline, not the default .center —
                    // with a 40pt number next to 18pt text, center-
                    // aligning their bounding boxes doesn't line up
                    // how the text actually SITS; baseline alignment
                    // is the correct way to mix sizes on one line. A
                    // slightly taller row (48pt, not `lineHeight`'s
                    // 40) also gives the big font room so it doesn't
                    // overflow into the next row.
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.left)
                            .font(numberFont(50))
                            .tracking(-2)
                            .opacity(isBigSuccess ? 1 : dimmedOpacity)
                        Spacer()
                        Text(row.right)
                            .font(textFont())
                            .opacity(dimmedOpacity)
                    }
                    .frame(height: 48)
                }
            }
            .padding(.leading, sideInset)
            .padding(.trailing, sideInset)
            .padding(.top, contentTopPadding(topInset))
            .frame(width: fullGeo.size.width, height: fullGeo.size.height, alignment: .topLeading)

            // Success screen: green everywhere (see `fillColor`), and
            // dark text reads fine over it at any height, so the
            // whole point of the light/dark mirror (matching whatever
            // color the fill happens to be at each pixel) doesn't
            // apply — skip it and just go flat #1E1E1E. Not while a
            // max-mode tracker is active, though: `fillColor` ignores
            // `todoComplete` entirely there (green/red always wins —
            // see `fillColor`), so this shortcut's flat-green
            // assumption would be wrong; fall through to the masked
            // version, which already has the right colors for that.
            if todoComplete, !isActiveMetricMaxMode {
                content
                    .foregroundStyle(fillNavy)
            } else {
                ZStack(alignment: .topLeading) {
                    content
                        .foregroundStyle(fillNavy)
                    content
                        .foregroundStyle(fillTextColor)
                        .mask(
                            Rectangle()
                                .frame(width: fullGeo.size.width, height: fillHeight)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        )
                }
            }
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.5), value: currentProgress)
        .animation(.easeOut(duration: 0.25), value: activeMetric)
        .animation(.easeOut(duration: 0.3), value: todoComplete)
    }

    // MARK: - Bottom menu (home screen only)
    //
    // Just the tab row now — quick-add and settings both left this
    // layered-over-home-screen approach behind; they're full pages
    // (macOS: settingsFlow, in place of the home screen entirely) or
    // sheets (iOS), handled at the top of `body`. bottomMode is only
    // ever `.main` while this is on screen, on either platform.

    private func bottomMenu(fillHeight: CGFloat) -> some View {
        mainMenu(fillHeight: fillHeight)
            .padding(.horizontal, sideInset)
            .padding(.bottom, bottomInset)
    }

    // Pure layout, no color — `mainMenu` below gives it its flat text
    // color.
    private var mainMenuRows: some View {
        HStack(alignment: .bottom) {
            // Left column: one row per enabled tracker — tapping just
            // switches which one is active/shown, it does NOT open
            // any panel. Settings moved out of this list entirely
            // (now the hamburger icon top-right, see `topBar`) so
            // this reads as a clean to-do/tracker switcher, nothing
            // else mixed in.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(enabledTrackers) { kind in
                    Button {
                        activeMetric = kind
                    } label: {
                        Text(kind.label).underline(activeMetric == kind)
                    }
                    .frame(height: lineHeight)
                }
            }
            Spacer()
            // Right column: the to-do checklist when that tab is
            // active; for water/protein, their presets + "more" —
            // "more" is the ONLY thing that opens the quick-add panel.
            VStack(alignment: .trailing, spacing: 0) {
                switch activeMetric {
                case .todo:
                    ForEach(store.todoItems) { item in
                        let done = store.isTodoItemDone(item)
                        let label = store.todoLabel(for: item)
                        Group {
                            if item.link == .none {
                                Button {
                                    store.toggleTodoItem(item)
                                } label: {
                                    Text(label).strikethrough(done)
                                }
                                .buttonStyle(.plain)
                            } else {
                                // water/protein rows auto-complete from
                                // the tracker's own progress — not tappable.
                                Text(label).strikethrough(done)
                            }
                        }
                        .frame(height: lineHeight)
                    }
                case .water, .protein, .coffee, .carbs, .steps, .movement, .sleep, .cigarettes:
                    ForEach(activeMetric.presets, id: \.self) { amount in
                        Button("+\(amount)") {
                            switch activeMetric {
                            case .water: store.addWater(amount)
                            case .protein: store.addProtein(amount)
                            case .coffee: store.addCoffee(amount)
                            case .carbs: store.addCarbs(amount)
                            case .steps: store.addSteps(amount)
                            case .movement: store.addMovement(amount)
                            case .sleep: store.addSleep(amount)
                            case .cigarettes: store.addCigarettes(amount)
                            case .todo: break
                            }
                        }
                        .frame(height: lineHeight)
                    }
                    Button("more") {
                        pendingAmount = snappedDefaultAmount(for: activeMetric)
                        #if os(iOS)
                        showingQuickAddSheet = true
                        #else
                        bottomMode = .quickAdd
                        #endif
                    }
                    .frame(height: lineHeight)
                }
            }
        }
        .font(textFont())
        .buttonStyle(.plain)
    }

    // Same mirrored dark/light mask numberStack uses, re-applied here
    // — `fillHeight` comes from `homeScreen`, computed with the exact
    // same true-height formula the background fill itself uses, so it
    // can't drift out of sync with where the fill actually is. The
    // extra `- bottomInset` accounts for `bottomMenu`'s own bottom
    // padding: fillHeight is measured from the TRUE screen bottom, but
    // mainMenuRows sits `bottomInset` above that once that padding is
    // applied, so its OWN local mask needs the same offset subtracted
    // to still land on the real fill boundary.
    private func mainMenu(fillHeight: CGFloat) -> some View {
        let localFillHeight = max(0, fillHeight - bottomInset)
        return ZStack(alignment: .bottomLeading) {
            mainMenuRows
                .foregroundStyle(fillNavy)
            mainMenuRows
                .foregroundStyle(fillTextColor)
                .mask(
                    Rectangle()
                        .frame(height: localFillHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                )
        }
    }

    // MARK: - Quick add (shared by water + protein)
    //
    // Same layover element as settings now — `page(...)` on macOS,
    // the same sheet/toolbar chrome as settingsSheet on iOS — not a
    // bespoke panel. The amount itself defaults to "however much is
    // left to hit today's goal" rather than 0, so opening "more" with
    // nothing logged yet starts you right at a sensible number.
    //
    // iOS gets a native wheel picker (5 round-number candidates around
    // the current amount, plus the exact current amount itself if
    // it's not already one of them). macOS has no wheel-style Picker,
    // so it just keeps the plain text field for now.
    //
    // FoodProteinLookup (WaterStore.swift) — the "type a food name,
    // get an amount" table — isn't wired to any UI right now (dropped
    // the input field it used to sit behind); still there if this
    // gets revisited later.

    private func pickerStep(for kind: TrackerKind) -> Int {
        switch kind {
        case .protein, .carbs: 5
        case .coffee: 1   // whole cups, not a continuous amount
        case .steps: 500
        case .movement: 5
        case .sleep: 1   // whole hours
        case .cigarettes: 1
        default: 100
        }
    }

    /// The wheel's full fixed range — water 0-5000ml, protein/carbs
    /// 0-500g, coffee 0-10 cups, steps 0-30000, movement 0-180min,
    /// sleep 0-16hr, cigarettes 0-60.
    private func pickerRange(for kind: TrackerKind) -> ClosedRange<Int> {
        switch kind {
        case .water: 0...5000
        case .protein, .carbs: 0...500
        case .coffee: 0...10
        case .steps: 0...30000
        case .movement: 0...180
        case .sleep: 0...16
        case .cigarettes: 0...60
        case .todo: 0...0
        }
    }

    private func remainingToGoal(for kind: TrackerKind) -> Int {
        switch kind {
        case .water: max(0, store.data.goalML - store.todayTotal)
        case .protein: max(0, store.data.proteinGoalG - store.todayProteinTotal)
        case .coffee: max(0, store.data.coffeeGoal - store.todayCoffeeTotal)
        case .carbs: max(0, store.data.carbsGoalG - store.todayCarbsTotal)
        case .steps: max(0, store.data.stepsGoal - store.todayStepsTotal)
        case .movement: max(0, store.data.movementGoalMin - store.todayMovementTotal)
        case .sleep: max(0, store.data.sleepGoalHr - store.todaySleepTotal)
        case .cigarettes: max(0, store.data.cigarettesGoal - store.todayCigarettesTotal)
        case .todo: 0
        }
    }

    // The GOAL wheel is a different animal from the quick-add
    // amount wheel above: goals are set once in a while and sit at
    // much rounder numbers, so these ranges start well above zero
    // (a 0 goal is never a real answer) and step coarser.
    private func goalStep(for kind: TrackerKind) -> Int {
        switch kind {
        case .water: 100
        case .protein, .carbs: 10
        case .coffee: 1
        case .steps: 500
        case .movement: 5
        case .sleep: 1
        case .cigarettes: 1
        case .todo: 1
        }
    }

    private func goalRange(for kind: TrackerKind) -> ClosedRange<Int> {
        switch kind {
        case .water: 500...8000
        case .protein: 20...400
        case .carbs: 20...600
        case .coffee: 1...15
        case .steps: 1000...30000
        case .movement: 5...180
        case .sleep: 1...14
        case .cigarettes: 1...40
        case .todo: 0...0
        }
    }

    private func snappedGoal(_ value: Int, for kind: TrackerKind) -> Int {
        let step = goalStep(for: kind)
        let range = goalRange(for: kind)
        let snapped = ((value + step / 2) / step) * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }

    #if os(iOS)
    private func goalCandidates(for kind: TrackerKind) -> [Int] {
        let range = goalRange(for: kind)
        return Array(stride(from: range.lowerBound, through: range.upperBound, by: goalStep(for: kind)))
    }
    #endif

    /// What "more" prefills the amount with: how much is left to hit
    /// today's goal, snapped to the wheel's step and clamped into its
    /// range so it always lands exactly on one of the wheel's rows.
    private func snappedDefaultAmount(for kind: TrackerKind) -> Int {
        let step = pickerStep(for: kind)
        let range = pickerRange(for: kind)
        let snapped = ((remainingToGoal(for: kind) + step / 2) / step) * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }

    #if os(iOS)
    private func pickerCandidates(for kind: TrackerKind) -> [Int] {
        let range = pickerRange(for: kind)
        return Array(stride(from: range.lowerBound, through: range.upperBound, by: pickerStep(for: kind)))
    }
    #endif

    private func dismissQuickAdd() {
        pendingAmount = 0
        #if os(iOS)
        showingQuickAddSheet = false
        #else
        bottomMode = .main
        #endif
    }

    // Split in two so the two platform wrappers can put a flexible
    // gap BETWEEN the amount control and "add" — that's what actually
    // centers the wheel in the available space while still pinning
    // "add" toward the bottom, rather than one flexible-Spacer pair
    // around the whole group (which centers "add" along with the
    // wheel, floating it away from the bottom instead of anchoring it
    // there).
    @ViewBuilder
    private func quickAddAmountControl(_ kind: TrackerKind) -> some View {
        #if os(iOS)
        // Explicit .foregroundColor AND .font on the row Text, not
        // inherited from an ancestor — the wheel style is
        // UIPickerView-backed under the hood and routinely fails to
        // pick up inherited .foregroundStyle/.font, rendering rows
        // either invisible (navy-on-white, just not actually drawn —
        // the wheel's height still reserves its space) or in the
        // wrong (system) typeface. .tint for the same color reason,
        // belt and braces.
        Picker("", selection: $pendingAmount) {
            ForEach(pickerCandidates(for: kind), id: \.self) { value in
                Text("\(Self.formatAmount(value)) \(kind.unit)")
                    .font(textFont(24))
                    .foregroundColor(fillNavy)
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .tint(fillNavy)
        .frame(height: 160)
        #else
        HStack {
            Text("\(kind.label)(\(kind.unit))")
            Spacer()
            amountField(value: $pendingAmount)
        }
        .frame(height: lineHeight)
        #endif
    }

    private func quickAddButtonRow(_ kind: TrackerKind) -> some View {
        HStack {
            Spacer()
            Button("add") {
                switch kind {
                case .water: store.addWater(pendingAmount)
                case .protein: store.addProtein(pendingAmount)
                case .coffee: store.addCoffee(pendingAmount)
                case .carbs: store.addCarbs(pendingAmount)
                case .steps: store.addSteps(pendingAmount)
                case .movement: store.addMovement(pendingAmount)
                case .sleep: store.addSleep(pendingAmount)
                case .cigarettes: store.addCigarettes(pendingAmount)
                case .todo: break
                }
                dismissQuickAdd()
            }
            Spacer()
        }
        .frame(height: lineHeight)
    }

    #if os(macOS)
    private func quickAddPage(size: CGSize) -> some View {
        page(size: size) {
            quickAddAmountControl(activeMetric)
            quickAddButtonRow(activeMetric)

            Spacer(minLength: 0)

            HStack {
                Button("close") { dismissQuickAdd() }
                Spacer()
            }
            .frame(height: lineHeight)
        }
    }
    #endif

    // MARK: - Settings screen
    //
    // A nav list: history / trackers (also has the goal fields now) /
    // sync & reset. The calendar day itself rolls over on its own at
    // midnight — todayTotal etc. are always computed from real
    // timestamps, so yesterday's logged entries just fall out of
    // "today" and into History
    // without needing this button at all.


    // Shared shape for every full-screen page reached from settings:
    // white background bleeding edge-to-edge, content top-anchored at
    // the same inset as the home screen, a back link pinned to the
    // bottom via the trailing Spacer.
    private func page(size: CGSize, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .buttonStyle(.plain)
        .font(textFont())
        .foregroundStyle(fillNavy)
        .padding(.horizontal, sideInset)
        .padding(.top, 24)
        .padding(.bottom, bottomInset)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(sheetBG.ignoresSafeArea())
    }

    // "sync & reset" together — reset doesn't need its own page, it's
    // just one more row alongside the sync status. CloudKit sync is
    // silent/automatic (follows whichever Apple ID is already signed
    // in on the device) — nothing to link/create/unlink any more, so
    // this row just reports whether it's actually working right now.
    @ViewBuilder
    private var syncRows: some View {
        Text(syncStatusText)
            .frame(height: lineHeight)

        Button("reset") {
            store.resetToday()
        }
        .frame(height: lineHeight)
    }

    private var syncStatusText: String {
        switch store.cloudSyncStatus {
        case .unknown: "checking icloud…"
        case .available: "synced via icloud"
        case .noAccount: "not signed in to icloud"
        case .restricted: "icloud unavailable"
        case .error: "icloud sync error"
        }
    }

    // MARK: - Trackers screen (also where goals live now)
    //
    // One row per tracker: tapping the label shows/hides it (same as
    // before, strikethrough = hidden); water/protein additionally get
    // an inline goal field on the same row — no separate goals page.

    private var waterGoalBinding: Binding<Int> {
        Binding(get: { store.data.goalML }, set: { store.setGoal($0) })
    }

    private var proteinGoalBinding: Binding<Int> {
        Binding(get: { store.data.proteinGoalG }, set: { store.setProteinGoal($0) })
    }

    private var coffeeGoalBinding: Binding<Int> {
        Binding(get: { store.data.coffeeGoal }, set: { store.setCoffeeGoal($0) })
    }

    private var carbsGoalBinding: Binding<Int> {
        Binding(get: { store.data.carbsGoalG }, set: { store.setCarbsGoal($0) })
    }

    private var stepsGoalBinding: Binding<Int> {
        Binding(get: { store.data.stepsGoal }, set: { store.setStepsGoal($0) })
    }

    private var movementGoalBinding: Binding<Int> {
        Binding(get: { store.data.movementGoalMin }, set: { store.setMovementGoal($0) })
    }

    private var sleepGoalBinding: Binding<Int> {
        Binding(get: { store.data.sleepGoalHr }, set: { store.setSleepGoal($0) })
    }

    private var cigarettesGoalBinding: Binding<Int> {
        Binding(get: { store.data.cigarettesGoal }, set: { store.setCigarettesGoal($0) })
    }

    // Shared row layout for the to-do's/trackers page — no more grey
    // background (removed per redesign), just the shared height every
    // row (to-do, tracker, add) needs to line up consistently. NO
    // horizontal padding of its own — the page container already
    // applies `sideInset`, and this used to add its own 16pt on top of
    // that (22+16=38pt total), which read as noticeably narrower than
    // every other page in the app.
    private func pillRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack { content() }
            .frame(height: lineHeight + 8)
    }

    // Goal number lives INSIDE a pill row now, not in its own boxed
    // field (amountField's own grey background would nest a box
    // inside the row's box) — a thin bordered box instead of the old
    // underline marks it as an input.
    private func pillGoalField(value: Binding<Int>) -> some View {
        goalInputBorder {
            TextField("", text: amountBinding(value))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(fillNavy)
        }
    }

    // Shared border box for every goal "input" on the trackers page —
    // macOS's actual inline TextField (pillGoalField above) and iOS's
    // value display (which opens the goal wheel sheet on tap instead
    // of editing inline, but reads as the same kind of input).
    private func goalInputBorder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(goalBorderGrey, lineWidth: 1)
            )
    }

    /// Today's goal for a tracker, in its own unit.
    private func goalValue(for kind: TrackerKind) -> Int {
        switch kind {
        case .water: store.data.goalML
        case .protein: store.data.proteinGoalG
        case .coffee: store.data.coffeeGoal
        case .carbs: store.data.carbsGoalG
        case .steps: store.data.stepsGoal
        case .movement: store.data.movementGoalMin
        case .sleep: store.data.sleepGoalHr
        case .cigarettes: store.data.cigarettesGoal
        case .todo: 0
        }
    }

    private func goalBinding(for kind: TrackerKind) -> Binding<Int> {
        switch kind {
        case .water: waterGoalBinding
        case .protein: proteinGoalBinding
        case .coffee: coffeeGoalBinding
        case .carbs: carbsGoalBinding
        case .steps: stepsGoalBinding
        case .movement: movementGoalBinding
        case .sleep: sleepGoalBinding
        case .cigarettes: cigarettesGoalBinding
        case .todo: .constant(0)
        }
    }

    private func commitGoal(_ value: Int, for kind: TrackerKind) {
        switch kind {
        case .water: store.setGoal(value)
        case .protein: store.setProteinGoal(value)
        case .coffee: store.setCoffeeGoal(value)
        case .carbs: store.setCarbsGoal(value)
        case .steps: store.setStepsGoal(value)
        case .movement: store.setMovementGoal(value)
        case .sleep: store.setSleepGoal(value)
        case .cigarettes: store.setCigarettesGoal(value)
        case .todo: break
        }
    }

    #if os(iOS)
    private func openGoalSheet(_ kind: TrackerKind) {
        // Seed the wheel with the tracker's current goal, snapped
        // into the wheel's own steps so it lands exactly on a row.
        pendingGoal = snappedGoal(goalValue(for: kind), for: kind)
        pendingGoalMode = store.goalMode(for: kind)
        goalSheetKind = kind
    }
    #endif

    // Simple split, same on every row (to-do AND tracker): a leading
    // icon is the ONE-TAP toggle — filled "−" removes/disables,
    // outline "+" is available-to-add — and the rest of the row does
    // the "look at/edit this" action instead. Both are the SAME SF
    // Symbol family (solid circle-minus vs. outline circle-plus) so
    // they read as one on/off control rather than two different
    // icons — the custom flat "PlusIcon" asset (no circle) used to
    // sit here instead and didn't match the filled circle at all.
    private func toggleIcon(filled: Bool) -> some View {
        Group {
            if filled {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(fillNavy)
            } else {
                Image(systemName: "plus.circle")
                    .foregroundStyle(greyText)
            }
        }
    }

    // Icon toggles enabled/disabled; tapping anywhere else on the row
    // opens the tracker's goal editor directly (iOS: the wheel sheet;
    // macOS has no separate "open" step since its goal field is
    // already inline-editable right here).
    private func trackerRow(_ kind: TrackerKind) -> some View {
        let enabled = store.isTrackerEnabled(kind)
        let label = kind.unit.isEmpty ? kind.label : "\(kind.label)(\(kind.unit))"

        let rowContent = HStack {
            Button {
                focusedTodo = nil
                store.toggleTracker(kind)
                if !store.isTrackerEnabled(activeMetric) {
                    activeMetric = enabledTrackers.first ?? kind
                }
            } label: {
                toggleIcon(filled: enabled)
            }

            #if os(iOS)
            Button {
                focusedTodo = nil
                openGoalSheet(kind)
            } label: {
                HStack {
                    Text(label)
                    Spacer()
                    if enabled {
                        goalInputBorder {
                            Text(Self.formatAmount(goalValue(for: kind)))
                        }
                    }
                }
            }
            #else
            Text(label)
            Spacer()
            if enabled {
                pillGoalField(value: goalBinding(for: kind))
            }
            #endif
        }
        .foregroundStyle(enabled ? fillNavy : greyText)

        return pillRow { rowContent }
    }

    // MARK: - To-do list (trackers page)
    //
    // Shaped like one tracker row whose "value" happens to be a whole
    // column: the "− to do" label sits on the left of the FIRST line,
    // and every to-do is a right-aligned, underlined field stacked
    // under it, with "+ add to do" closing off the list. Individual
    // to-dos have no icon of their own — emptying one deletes it,
    // which is why there's nothing to tap-to-remove.
    //
    // Editing model, deliberately Reminders-like:
    //  • "+ add to do" appends a blank row and focuses it
    //  • Return commits and opens a fresh row right below (chaining),
    //    so several to-dos in a row never needs a second tap
    //  • Return on a blank row ends the session instead
    //  • blank rows are deleted once editing stops entirely, so
    //    clearing a to-do's text is how you remove it
    //  • "+ add to do" hides while anything is focused, since it'd
    //    otherwise sit right under the row you're typing into
    //
    // Everything here is deliberately animation-free and mutates the
    // list as little as possible while a field holds focus. A first
    // pass had spring transitions on insert/remove plus a prune on
    // every focus change, and the whole section came out dead — no
    // caret, no keyboard, taps on existing rows doing nothing. Both
    // rewrite the list (a @Published store write) at exactly the
    // moment focus is being handed over. Re-add either one only with
    // a device in hand to check it against.

    /// A touch tighter than the tracker rows below (`lineHeight + 8`)
    /// — the to-do column is a list of its own, and the extra air read
    /// as gaps between entries rather than as one block.
    private var todoRowHeight: CGFloat { lineHeight }

    private func todoNameBinding(_ task: TodoTask) -> Binding<String> {
        Binding(
            get: { store.data.todoTasks.first { $0.id == task.id }?.name ?? "" },
            set: { store.setTodoTaskName(id: task.id, to: $0) }
        )
    }

    private func startAddingTodo() {
        // Reuse a blank row if one is somehow already sitting there
        // (double-tap on "add", say) rather than stacking a second.
        if let blank = store.data.todoTasks.first(where: { $0.name.isEmpty }) {
            focusedTodo = blank.id
            return
        }
        // Deliberately NOT animated: an insert animation is still in
        // flight when focus is claimed, and focusing a row mid-
        // transition is one of the ways this silently does nothing.
        // Worth revisiting once the basics are solid.
        //
        // Set straight away, no waiting for the row to exist: the new
        // row renders with `isFocused` already true, and its field
        // takes first responder itself the first time it's laid out.
        focusedTodo = store.insertBlankTodoTask()
    }

    private func handleTodoSubmit(_ task: TodoTask) {
        let name = (store.data.todoTasks.first { $0.id == task.id }?.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            // Return on an empty row is the natural "I'm done adding"
            // gesture — drop the row and put the keyboard away.
            store.removeTodoTask(id: task.id)
            focusedTodo = nil
            return
        }

        // Safe to assign directly now: the UIKit field returns false
        // from textFieldShouldReturn, so the system never resigns
        // first responder behind our back the way SwiftUI's onSubmit
        // did (which used to drop the keyboard and send the second
        // to-do nowhere).
        focusedTodo = store.insertBlankTodoTask(after: task.id)
    }

    /// Backspace with the row already empty — the Notes gesture for
    /// "remove this line". Focus moves up to the row above so the list
    /// keeps deleting under your finger; if this was the first row,
    /// editing just ends.
    private func handleTodoBackspaceWhenEmpty(_ task: TodoTask) {
        guard let index = store.data.todoTasks.firstIndex(where: { $0.id == task.id }) else { return }
        let previousID = index > 0 ? store.data.todoTasks[index - 1].id : nil
        store.removeTodoTask(id: task.id)
        focusedTodo = previousID
    }

    /// The explicit "−" tap next to a to-do — a one-off delete, as
    /// opposed to `handleTodoBackspaceWhenEmpty`'s keyboard-chain
    /// gesture. Only clears focus if THIS row had it; deleting a
    /// different row than the one you're editing shouldn't interrupt
    /// that edit.
    private func deleteTodoTask(_ task: TodoTask) {
        if focusedTodo == task.id { focusedTodo = nil }
        store.removeTodoTask(id: task.id)
    }

    private func todoTaskRow(_ task: TodoTask) -> some View {
        let isBlank = (store.data.todoTasks.first { $0.id == task.id }?.name ?? "").isEmpty

        // The field itself, unchanged from before — still a ZStack so
        // the typing hint can sit behind it without becoming the
        // field's own `prompt` (see the comment on TypingSuggestion).
        let field = ZStack(alignment: .trailing) {
            // Sits BEHIND the field rather than being its `prompt`, so
            // the animation's ticking never re-renders the field —
            // see TypingSuggestion. Non-interactive, so taps aimed at
            // the row still land on the field on top of it.
            //
            // Only on the row being typed into, not on every blank one:
            // several rows each running their own hint at once read as
            // clutter rather than as a prompt.
            if isBlank, focusedTodo == task.id {
                TypingSuggestion(suggestions: Self.todoSuggestions, color: greyText)
                    .allowsHitTesting(false)
            }

            #if os(iOS)
            TodoTextField(
                text: todoNameBinding(task),
                isFocused: focusedTodo == task.id,
                textColor: UIColor(fillNavy),
                font: UIFont(name: "GoogleSansCode-Medium", size: bodyTextSize * fontScale),
                onFocusChange: { nowFocused in
                    if nowFocused {
                        focusedTodo = task.id
                    } else {
                        // Don't call it "editing stopped" yet. Moving
                        // between two rows fires this field's
                        // didEndEditing BEFORE the next one's
                        // didBeginEditing, so there's a blink with
                        // nothing focused — and treating that as the
                        // end of the session would prune rows in the
                        // middle of handing focus over. A tick later,
                        // whoever took focus has already said so.
                        DispatchQueue.main.async {
                            if focusedTodo == task.id { focusedTodo = nil }
                        }
                    }
                },
                onSubmit: { handleTodoSubmit(task) },
                onBackspaceWhenEmpty: { handleTodoBackspaceWhenEmpty(task) }
            )
            .frame(maxWidth: .infinity)
            .frame(height: todoRowHeight)
            #else
            TextField("", text: todoNameBinding(task))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .underline()
                .foregroundStyle(fillNavy)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .focused($macFocusedTodo, equals: task.id)
                .onSubmit { handleTodoSubmit(task) }
                .frame(height: todoRowHeight)
            #endif
        }

        // Delete button sits OUTSIDE the field's own ZStack, in an
        // HStack alongside it — the field keeps `.frame(maxWidth:
        // .infinity)` but now shares the row's width with a fixed-size
        // trailing "×" instead of claiming all of it, so the field's
        // own right-aligned text ends up snug against the button
        // rather than the row's outer edge.
        return HStack(spacing: 6) {
            field

            Button {
                deleteTodoTask(task)
            } label: {
                Text("×")
                    .font(textFont())
                    .foregroundStyle(fillNavy)
            }
        }
        .frame(height: todoRowHeight)
    }

    private var todoSection: some View {
        let enabled = store.isTrackerEnabled(.todo)

        return HStack(alignment: .top, spacing: 8) {
            // Left is intrinsic (icon + label only, no Spacer) and one
            // row tall, so it lines up with the first to-do; the
            // column on the right takes everything else. Giving the
            // fields the leftover width — instead of a Spacer here
            // squeezing them — is what makes their hit areas match
            // what's drawn.
            HStack(spacing: 8) {
                Button {
                    focusedTodo = nil
                    store.toggleTracker(.todo)
                    if !store.isTrackerEnabled(activeMetric) {
                        activeMetric = enabledTrackers.first ?? .todo
                    }
                } label: {
                    toggleIcon(filled: enabled)
                }
                Text("todo")
            }
            .frame(height: todoRowHeight)
            .foregroundStyle(enabled ? fillNavy : greyText)

            if enabled {
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(store.data.todoTasks) { task in
                        todoTaskRow(task)
                    }

                    if focusedTodo == nil {
                        Button { startAddingTodo() } label: {
                            Text("+ add todo")
                                .foregroundStyle(greyText)
                                .frame(height: todoRowHeight)
                        }
                        .transition(.opacity)
                    }
                }
                // The column claims the leftover width itself rather
                // than leaning on its children to do it. With no
                // to-dos yet, its only child is the "add" button,
                // which hugs its own text — so the column shrank to
                // that and sat against the label instead of at the
                // right edge.
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        // No horizontal padding here either — see `pillRow`'s comment;
        // the page container's `sideInset` already covers it, and this
        // used to double up on top of that.
        // Prune only once editing has FULLY stopped, not on every
        // focus change: pruning mid-move rewrites the list (a
        // @Published store write) at the exact moment focus is
        // transferring between two fields, and that re-render can
        // swallow the focus it was moving to. The visible cost is that
        // a row you emptied sticks around until you tap away entirely,
        // instead of vanishing the moment you jump to another row.
        .onChange(of: focusedTodo) { _, newValue in
            #if os(macOS)
            macFocusedTodo = newValue
            #endif
            guard newValue == nil else { return }
            store.pruneEmptyTodoTasks()
        }
        #if os(macOS)
        // AppKit's field owns its own focus, so mirror what the user
        // does there back into the shared value the rest reads.
        .onChange(of: macFocusedTodo) { _, newValue in
            focusedTodo = newValue
        }
        #endif
        // Safety net for the one case focus changes can't cover:
        // leaving the page (or the app being killed) while a blank row
        // is still open would otherwise persist an empty to-do.
        .onDisappear { store.pruneEmptyTodoTasks() }
    }

    // Settings root: just two destinations. ("how it works" from the
    // early mockup isn't built yet — only these two were confirmed.)
    @ViewBuilder
    private var settingsRootRows: some View {
        Button("trackers") { settingsPath.append(.todos) }
            .frame(height: lineHeight)
        Button("all logs") { settingsPath.append(.allLogs) }
            .frame(height: lineHeight)
        Button("test stuff") { settingsPath.append(.testStuff) }
            .frame(height: lineHeight)
    }

    // home/settings/trackers — the to-do list and the trackers on one
    // page, no section headers, just one icon-led row shape straight
    // through. To-do comes first and brings its own column of entries
    // (see `todoSection`); the rest are single rows with a goal.
    //
    // "Tap elsewhere to finish editing" is deliberately NOT a
    // Color.clear laid down as one broad layer BEHIND everything
    // either — that was tried (a ZStack with the real content
    // layered on top as a "sibling") on the theory that a sibling,
    // unlike an ancestor, wouldn't compete with a descendant
    // TextField's own tap handling. Tested wrong: tapping from one
    // to-do straight into another stopped working — direct evidence
    // that SwiftUI's tap recognizer for a broad background view CAN
    // still intercept a touch that lands on a same-region UIKit field
    // sitting "on top" of it, same underlying class of interference
    // as the documented ancestor case, just less obviously so. Lesson
    // repeated from elsewhere in this file: don't reason about
    // SwiftUI/UIKit touch routing from a mental model, verify it.
    //
    // So instead: NO view's geometry ever overlaps a to-do field's.
    // (1) every OTHER row's own button action clears focus
    // explicitly, (2) `sectionGapCatcher` fills the small gaps
    // BETWEEN sections (VStack lays out non-overlapping bands, so
    // these truly never touch a field's rect), and (3) a catcher on
    // the empty space below the last row.
    @ViewBuilder
    private var todosPageRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            todoSection
            sectionGapCatcher
            trackerRow(.water)
            sectionGapCatcher
            trackerRow(.protein)
            sectionGapCatcher
            trackerRow(.coffee)
            sectionGapCatcher
            trackerRow(.carbs)
            sectionGapCatcher
            trackerRow(.steps)
            sectionGapCatcher
            trackerRow(.movement)
            sectionGapCatcher
            trackerRow(.sleep)
            sectionGapCatcher
            trackerRow(.cigarettes)

            Color.clear
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { focusedTodo = nil }
        }
    }

    /// One `trackerSectionGap`-tall strip, standing in for the VStack
    /// `spacing` `todosPageRows` used to use — spacing alone is inert
    /// (nothing to tap), so tapping in one of these gaps did nothing.
    /// An explicit view here instead gives it something to catch that
    /// tap with, still with zero geometric overlap with any row.
    private var sectionGapCatcher: some View {
        Color.clear
            .frame(height: trackerSectionGap)
            .contentShape(Rectangle())
            .onTapGesture { focusedTodo = nil }
    }

    // home/settings/test stuff — sync status/reset plus the
    // DEBUG-only seed/wipe buttons, moved off the to-do's page.
    @ViewBuilder
    private var testStuffRows: some View {
        syncRows

        #if DEBUG
        // Dev-only — backfills/removes fake History data so that
        // page has a real streak/scrolling to look at. Never compiled
        // into a release build.
        Button("seed test data") { store.seedDemoHistory() }
            .frame(height: lineHeight)
        Button("remove test data") { store.removeDemoHistory() }
            .frame(height: lineHeight)

        #if os(iOS)
        // The first-run tour is, by definition, hard to get back to.
        Button("replay tour") {
            showingSettingsSheet = false
            tourPage = .goal
            tourHabit = ""
            tourHabitTaskID = nil
            tourFillProgress = 0
            showingTour = true
        }
        .frame(height: lineHeight)
        #endif

        // Separate from the two above — this wipes REAL history too,
        // not just seeded demo data, so it gets its own confirmation
        // rather than firing on a single tap like the others.
        Button("clear all history") { showingClearAllHistoryConfirm = true }
            .frame(height: lineHeight)
            .alert("Clear all history?", isPresented: $showingClearAllHistoryConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Clear everything", role: .destructive) { store.clearAllHistory() }
            } message: {
                Text("Deletes every water, protein, coffee, carbs, and to-do entry ever logged — today included. Goals and to-do names are kept. This can't be undone.")
            }
        #endif
    }

    // MARK: - All logs (every entry, any tracker, swipe to delete)
    //
    // For fixing a mis-tap: `resetToday()` only reaches today and
    // wipes it wholesale, `clearAllHistory()` is everything-or-
    // nothing — neither lets you take back ONE wrong "+700" from
    // three days ago. This lists every entry from every tracker
    // (regardless of whether that tracker is currently enabled —
    // History already judges old days that way, so a log staying
    // visible after its tracker's turned off is consistent, not a
    // bug), newest first, grouped by day, one swipe from gone.

    /// One row in the log — a thin display-only wrapper over
    /// whichever entry type it came from; `kind` is what
    /// `store.deleteLogEntry` needs to find and remove the real thing.
    private struct LogRow: Identifiable {
        let id: UUID
        let kind: TrackerKind
        let amount: Int
        let timestamp: Date
    }

    private var allLogRows: [LogRow] {
        let water = store.data.entries.map { LogRow(id: $0.id, kind: .water, amount: $0.amountML, timestamp: $0.timestamp) }
        let protein = store.data.proteinEntries.map { LogRow(id: $0.id, kind: .protein, amount: $0.amountG, timestamp: $0.timestamp) }
        let coffee = store.data.coffeeEntries.map { LogRow(id: $0.id, kind: .coffee, amount: $0.amountCups, timestamp: $0.timestamp) }
        let carbs = store.data.carbsEntries.map { LogRow(id: $0.id, kind: .carbs, amount: $0.amountG, timestamp: $0.timestamp) }
        let steps = store.data.stepsEntries.map { LogRow(id: $0.id, kind: .steps, amount: $0.amountSteps, timestamp: $0.timestamp) }
        let movement = store.data.movementEntries.map { LogRow(id: $0.id, kind: .movement, amount: $0.amountMin, timestamp: $0.timestamp) }
        let sleep = store.data.sleepEntries.map { LogRow(id: $0.id, kind: .sleep, amount: $0.amountHr, timestamp: $0.timestamp) }
        return (water + protein + coffee + carbs + steps + movement + sleep)
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// `allLogRows`, bucketed into calendar days (newest day first,
    /// newest entry first within each day) — the shape the day-header
    /// grouping in the list needs.
    private var logDayGroups: [(day: Date, rows: [LogRow])] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: allLogRows) { cal.startOfDay(for: $0.timestamp) }
        return byDay.keys.sorted(by: >).map { day in (day: day, rows: byDay[day] ?? []) }
    }

    private static let logDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()

    private static let logTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// "protein - 10gr" — no space before the unit on purpose, kept
    /// tight so it reads as one token next to the tracker name, the
    /// same density the reference design used.
    private func logRowLabel(_ row: LogRow) -> String {
        "\(row.kind.label) - \(Self.formatAmount(row.amount))\(row.kind.unit)"
    }

    /// Day headers read "today" for the current day rather than its
    /// date — the one group you're most likely scanning for, and the
    /// same shorthand every other app's log/history list uses.
    /// Yesterday deliberately stays a date: "yesterday" is a second
    /// special case to keep straight for very little gain once you're
    /// already reading down a dated list.
    private func logDayLabel(_ day: Date) -> String {
        Calendar.current.isDateInToday(day)
            ? "today"
            : Self.logDayFormatter.string(from: day)
    }

    /// Plain content row — no leading icon any more (see
    /// `SwipeToDeleteRow` for how deletion happens now). Taller than
    /// the original `lineHeight + 8` for more visual "body", per the
    /// reference design.
    private func logRowView(_ row: LogRow) -> some View {
        HStack {
            Text(Self.logTimeFormatter.string(from: row.timestamp))
            Spacer()
            Text(logRowLabel(row))
        }
        .padding(.horizontal, 16)
        .frame(height: lineHeight + 16)
        .background(logRowBG, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Reminders/Mail-style swipe-left-to-reveal-trash, built by hand
    /// with a plain `DragGesture` rather than `List`'s `.swipeActions`.
    /// `.swipeActions` was tried first and dropped for two reasons:
    /// (1) it can only ever show a rectangular full-height slab, never
    /// the reference design's floating BLACK CIRCLE badge, and (2)
    /// extensive simulator testing found a synthesized drag/pan
    /// touch never actually revealed it (bare `Text` rows, no
    /// grouping, no styling — all ruled out one at a time) even
    /// though a plain tap on the same row worked every time — this
    /// hand-rolled version uses a `DragGesture`, different machinery
    /// entirely from `UISwipeActionsConfiguration`'s continuous-
    /// tracking pan recognizer, and needs re-confirming against the
    /// same tooling rather than assumed fixed.
    #if os(iOS)
    /// A real `UIPanGestureRecognizer`, bridged in, whose delegate
    /// answers YES to `shouldRecognizeSimultaneouslyWith` for
    /// everything — which is the whole point of it existing. UIKit
    /// asks BOTH competing recognizers for permission before letting
    /// them track the same touch; SwiftUI's `.simultaneousGesture`
    /// only ever answers for its own gesture, so an enclosing
    /// ScrollView's system pan recognizer still refused to start on a
    /// touch that began over a row. Owning the recognizer means owning
    /// its delegate, and that's the only place that answer can be
    /// given. Reports its translation in the recognizer's own view.
    private struct SimultaneousPan: UIGestureRecognizerRepresentable {
        let onChange: (CGSize) -> Void
        let onEnd: (CGSize) -> Void

        func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
            Coordinator()
        }

        func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
            let pan = UIPanGestureRecognizer()
            pan.delegate = context.coordinator
            return pan
        }

        func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {}

        func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
            let translation = recognizer.translation(in: recognizer.view)
            let size = CGSize(width: translation.x, height: translation.y)
            switch recognizer.state {
            case .changed:
                onChange(size)
            case .ended, .cancelled, .failed:
                onEnd(size)
            default:
                break
            }
        }

        final class Coordinator: NSObject, UIGestureRecognizerDelegate {
            func gestureRecognizer(
                _ gestureRecognizer: UIGestureRecognizer,
                shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
            ) -> Bool {
                true
            }
        }
    }
    #endif

    private struct SwipeToDeleteRow<Content: View>: View {
        let onDelete: () -> Void
        let content: () -> Content

        @State private var isRevealed = false
        @State private var dragTranslation: CGFloat = 0
        private let revealWidth: CGFloat = 64
        /// Horizontal slack before the row starts following the finger
        /// — without it, the couple of pixels of sideways jitter in a
        /// normal vertical flick would nudge the row.
        private let activationSlack: CGFloat = 10

        init(onDelete: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
            self.onDelete = onDelete
            self.content = content
        }

        var body: some View {
            let baseOffset: CGFloat = isRevealed ? -revealWidth : 0
            ZStack(alignment: .trailing) {
                // Declared FIRST (SwiftUI's ZStack z-orders later
                // children on top), so the trash button below stays
                // frontmost and reliably hit-testable in the gap this
                // leaves exposed — content's own hit-shape, despite
                // moving with `.offset`, was intercepting taps meant
                // for the button otherwise.
                swipeableContent(baseOffset: baseOffset)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.black))
                }
                .buttonStyle(.plain)
                .opacity(isRevealed ? 1 : 0)
                .allowsHitTesting(isRevealed)
            }
        }

        // Two gesture paths, because the coexistence problem this
        // solves is an iOS-touch-only one:
        //
        // iOS gets a REAL `UIPanGestureRecognizer` (see
        // `SimultaneousPan`). `.gesture` and even
        // `.simultaneousGesture(DragGesture())` were both tried first
        // and both broke scrolling in the same telling way: a drag
        // STARTED on a row did nothing, a drag started on the
        // background between rows scrolled fine, and a drag started on
        // a row WHILE the list was already coasting kept scrolling.
        // That's the signature of the enclosing ScrollView's own pan
        // recognizer never being allowed to start — UIKit asks BOTH
        // recognizers whether they'll run together, and
        // `.simultaneousGesture` only answers for SwiftUI's side; the
        // system scroll recognizer never agreed back. Bridging a real
        // recognizer is what lets us answer for both, via its delegate.
        //
        // macOS keeps the plain `DragGesture`: scrolling there is
        // scroll-wheel/trackpad-scroll events, not a pan recognizer, so
        // there's nothing to compete with in the first place.
        @ViewBuilder
        private func swipeableContent(baseOffset: CGFloat) -> some View {
            let base = content()
                .offset(x: baseOffset + dragTranslation)
                .contentShape(Rectangle())

            #if os(iOS)
            base
                .gesture(
                    SimultaneousPan(
                        onChange: { handleDragChange($0, baseOffset: baseOffset) },
                        onEnd: { handleDragEnd($0, baseOffset: baseOffset) }
                    )
                )
                .onTapGesture { collapseIfRevealed() }
            #else
            base
                .simultaneousGesture(
                    DragGesture(minimumDistance: activationSlack)
                        .onChanged { handleDragChange($0.translation, baseOffset: baseOffset) }
                        .onEnded { handleDragEnd($0.translation, baseOffset: baseOffset) }
                )
                .onTapGesture { collapseIfRevealed() }
            #endif
        }

        /// Only a clearly-horizontal drag moves the row. A vertical one
        /// is the ScrollView's (it's recognizing simultaneously now),
        /// so this deliberately does nothing and lets it scroll.
        private func handleDragChange(_ translation: CGSize, baseOffset: CGFloat) {
            let dx = translation.width
            let dy = translation.height
            guard abs(dx) > abs(dy), abs(dx) > activationSlack else { return }
            let proposed = baseOffset + dx
            dragTranslation = min(0, max(-revealWidth, proposed)) - baseOffset
        }

        private func handleDragEnd(_ translation: CGSize, baseOffset: CGFloat) {
            let dx = translation.width
            let dy = translation.height
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                if abs(dx) > abs(dy), abs(dx) > activationSlack {
                    isRevealed = (baseOffset + dragTranslation) < -revealWidth / 2
                }
                dragTranslation = 0
            }
        }

        private func collapseIfRevealed() {
            guard isRevealed else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isRevealed = false }
        }
    }

    /// A plain `ScrollView`/`LazyVStack`, not `List` — `List` is what
    /// made `.swipeActions` free, but that's gone now (see
    /// `SwipeToDeleteRow`), and a `List` fighting a hand-rolled
    /// horizontal `DragGesture` for its OWN vertical scroll gesture is
    /// exactly the kind of interference this file has been burned by
    /// before. Horizontal padding matches the trackers page's own
    /// `sideInset` now (was flush to the screen edge, using only the
    /// row's internal 16pt as margin); the 1pt vertical padding per
    /// row means ~2pt between consecutive cards, tighter than the
    /// original 8pt gap.
    private var allLogsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(logDayGroups, id: \.day) { group in
                    Text(logDayLabel(group.day))
                        .font(textFont())
                        .foregroundStyle(fillNavy)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    ForEach(group.rows) { row in
                        SwipeToDeleteRow {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                store.deleteLogEntry(id: row.id, kind: row.kind)
                            }
                        } content: {
                            logRowView(row)
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
            .padding(.horizontal, sideInset)
        }
        .buttonStyle(.plain)
        .font(textFont())
    }

    // MARK: - History (combined: water + protein + to-do per day)

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd.MM"
        return f
    }()

    /// One day in the History grid. No `.blank`/`.future` slots any
    /// more: the grid starts at TODAY and runs backwards to the first
    /// recorded day, so every slot is a real, already-happened day and
    /// the last row simply stops wherever the history does (rather
    /// than being padded out to a full row). A day in the middle with
    /// nothing logged is still a `.day`, just untouched.
    ///
    /// `.today` is its own case — it pulses and always draws in the
    /// blue "you are here" color, whatever its result so far.
    private enum HistoryCell {
        case today(succeeded: Bool)
        case day(date: Date, touched: Bool, succeeded: Bool, tier: HistoryTier)
    }

    /// A streak-length milestone. Ordered ascending — a run's tier is
    /// whichever of these its TOTAL length qualifies for, and that one
    /// tier's color applies to every day in the run, including the
    /// days at the start that earned an earlier, lower tier. So a run
    /// that reaches 35 shows as solid purple start to finish, not
    /// green-then-purple.
    private enum HistoryTier: Int, CaseIterable {
        case none = 0, ten = 10, thirtyFive = 35, seventyFive = 75

        var color: Color? {
            switch self {
            case .none: nil
            case .ten: historyMilestone10
            case .thirtyFive: historyMilestone35
            case .seventyFive: historyMilestone75
            }
        }

        /// Highest tier a run of `length` consecutive 100% days
        /// qualifies for. `allCases` is already ascending by
        /// `rawValue`, so the last one whose threshold is met wins.
        static func forRunLength(_ length: Int) -> HistoryTier {
            allCases.last { length >= $0.rawValue } ?? .none
        }
    }

    /// Every day's tier, from runs of consecutive 100% days.
    ///
    /// A run's tier only locks in once the run ENDS (a non-100% day,
    /// or today if the run is still going) — right up to the last
    /// day, one more 100% day could still push it into the next tier,
    /// and that has to recolor every earlier day in the same run too.
    private func historyDayTiers(_ results: [WaterStore.DayResult]) -> [Date: HistoryTier] {
        let cal = Calendar.current
        var tiers: [Date: HistoryTier] = [:]
        var run: [Date] = []

        func flush() {
            let tier = HistoryTier.forRunLength(run.count)
            if tier != .none {
                for day in run { tiers[day] = tier }
            }
            run.removeAll()
        }

        for result in results {   // oldest -> today
            if result.succeeded {
                run.append(cal.startOfDay(for: result.date))
            } else {
                flush()
            }
        }
        flush()
        return tiers
    }

    /// Every recorded day as one flat list, TODAY FIRST, running
    /// backwards to the earliest one. The 6-column grid then just
    /// wraps it — today lands top-left and stays there, and reading
    /// right/down walks back through time.
    private var historyDayCells: [HistoryCell] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let results = store.dailyResults
        let tiers = historyDayTiers(results)

        return results.reversed().map { result in
            let day = cal.startOfDay(for: result.date)
            if cal.isDate(day, inSameDayAs: today) {
                return .today(succeeded: result.succeeded)
            }
            return .day(
                date: day,
                touched: result.touched,
                succeeded: result.succeeded,
                tier: tiers[day] ?? .none
            )
        }
    }

    // A stripe per day, with a dot above it when that day hit 100%.
    // Every cell fills its grid column edge to edge (maxWidth
    // .infinity, no inter-cell spacing) so the row sits flush across
    // the full page width. An untouched day is always the neutral
    // grey no matter what its neighbours did; a day inside a
    // milestone-length run gets that tier's color; anything else
    // logged is plain navy.
    @ViewBuilder
    private func historySymbol(touched: Bool, succeeded: Bool, tier: HistoryTier) -> some View {
        let color: Color = !touched ? historyNotTouchedColor : (tier.color ?? fillNavy)
        historyMark(showDot: succeeded, color: color)
    }

    // Opens a given day's detail — a native sheet on iOS (same
    // layover as settings), a NavigationStack push on macOS (no
    // sheets there, see the note on `settingsPath`).
    private func openHistoryDay(_ date: Date) {
        #if os(iOS)
        historySheetDate = date
        showingHistoryDaySheet = true
        #else
        historyDetailPath.append(date)
        #endif
    }

    @ViewBuilder
    private func historyCell(_ cell: HistoryCell) -> some View {
        switch cell {
        case .today(let succeeded):
            // Today is ALWAYS the dedicated blue — live "you are
            // here" marker, not just another day's result — even
            // before anything's been tracked yet today, and even when
            // it's sitting inside a milestone run. Same historyMark
            // shape as every other cell, just pulsing.
            Button {
                openHistoryDay(.now)
            } label: {
                PulsingHistoryMark(showDot: succeeded, color: historyTodayColor)
            }
        case .day(let date, let touched, let succeeded, let tier):
            Button {
                openHistoryDay(date)
            } label: {
                historySymbol(touched: touched, succeeded: succeeded, tier: tier)
            }
        }
    }

    // The one History header: just today's streak, big. ("rec", the
    // all-time record, was here too — pulled for now, at the user's
    // request.)
    private var historyStreakHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(store.currentStreak)")
                .font(numberFont(50))
                .tracking(-2)
            Text("streak")
                .font(numberFont(50))
                .tracking(-2)
            Spacer(minLength: 8)
        }
        .frame(height: historyHeaderHeight)
    }

    /// One legend line: a short sample of the mark itself, then what
    /// it means. Same `historyMark` the grid uses, just pinned to a
    /// fixed sample width instead of filling a grid column.
    private func historyLegendRow(showDot: Bool, color: Color, meaning: String) -> some View {
        HStack(spacing: historyLegendSampleGap) {
            historyMark(showDot: showDot, color: color)
                .frame(width: historyLegendSampleWidth)
            Text("= \(meaning)")
                .font(textFont())
        }
        .frame(height: lineHeight)
    }

    // The key to the grid above it — every mark that can appear, in
    // the order you'd meet them, so the page explains itself to
    // someone opening the app for the first time rather than being a
    // wall of stripes you have to infer the rules of. No "legend"
    // title line above it — just the rows — at the user's request.
    //
    // Only the FIRST milestone tier (10 days) is spelled out here —
    // 35 and 75 stay unlisted on purpose, so hitting purple or gold
    // for the first time is a surprise rather than something you saw
    // coming from reading this list on day one. Their colors are
    // still real and still used in the grid (`historySymbol`) — they
    // just don't get a legend row.
    private var historyLegend: some View {
        VStack(alignment: .leading, spacing: 0) {
            historyLegendRow(showDot: false, color: historyNotTouchedColor, meaning: "not registered yet")
            historyLegendRow(showDot: false, color: historyTodayColor, meaning: "active day")
            historyLegendRow(showDot: false, color: fillNavy, meaning: "registered something")
            historyLegendRow(showDot: true, color: fillNavy, meaning: "100% day")
            historyLegendRow(showDot: true, color: historyMilestone10,
                             meaning: "\(HistoryTier.ten.rawValue) day streak")
        }
    }

    // Six columns, today top-left, walking BACKWARDS through time to
    // the right and down. No week boundaries any more — "which weekday
    // was this" is deliberately gone, and what's left reads as "how
    // have the last N days gone". The final row just stops where the
    // history does rather than being padded out to six.
    //
    // One flat array keyed by index: nested ForEach loops each keyed
    // by \.offset restart at 0 per row, so cell 2 of row 0 and cell 2
    // of row 1 shared an id and SwiftUI's diffing confused the two
    // across re-renders (marks doubling up in one cell, others never
    // picking up their styling). Flat keeps every id unique.
    private var historyGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: historyColumns),
            spacing: 0
        ) {
            ForEach(Array(historyDayCells.enumerated()), id: \.offset) { _, cell in
                historyCell(cell)
            }
        }
        // `GridItem(.flexible())` columns don't always land on exact
        // pixel boundaries — the leftover fraction of a point shows up
        // as a hairline gap between two adjacent cells' Rectangles,
        // right through the background color, wherever their colors
        // differ (invisible between two cells of the SAME color, since
        // the gap just blends into it — which is why it only ever
        // showed up mid-row, at a grey/black or black/green seam,
        // never at the page's outer edges). `.drawingGroup()` flattens
        // the whole grid into one rendered layer instead of one CALayer
        // per shape, so there's no seam between shapes left to show
        // through — same fix as any "hairline gap between adjacent
        // SwiftUI shapes" case. Doesn't affect tapping a day: hit-
        // testing still goes through the real view hierarchy, only
        // the drawing is flattened.
        .drawingGroup()
    }

    /// Per-day breakdown for the `.historyDay` detail page — a dot +
    /// date "title" row, then water/protein (actual/goal, judged
    /// against today's goal like the rest of History) and each plain
    /// to-do item, struck through if it was achieved that day.
    private func historyDayRows(for date: Date) -> some View {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
        let dayResult = store.dailyResults.first { cal.isDate($0.date, inSameDayAs: dayStart) }
        let touched = dayResult?.touched ?? false
        let succeeded = dayResult?.succeeded ?? false

        let waterTotal = store.data.entries
            .filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
            .reduce(0) { $0 + $1.amountML }
        let proteinTotal = store.data.proteinEntries
            .filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
            .reduce(0) { $0 + $1.amountG }
        let coffeeTotal = store.data.coffeeEntries
            .filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
            .reduce(0) { $0 + $1.amountCups }
        let carbsTotal = store.data.carbsEntries
            .filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
            .reduce(0) { $0 + $1.amountG }
        let doneTaskIDs = Set(
            store.data.todoCompletions
                .filter { $0.timestamp >= dayStart && $0.timestamp < dayEnd }
                .map(\.task)
        )

        // Same three-state mark as the week grid, just at title
        // size: plain date = day never touched, underlined = touched
        // but not finished, "•" + underline = fully completed —
        // concatenated into one Text (not separate views) so the
        // underline runs continuously under the dot AND the date
        // instead of two disconnected underlines.
        let dateText = Text(Self.dayFormatter.string(from: dayStart))
            .font(numberFont(50))
            .tracking(-2)
        let title: Text = succeeded ? Text("•").font(numberFont(24)) + dateText : dateText

        return VStack(alignment: .leading, spacing: 0) {
            title
                .underline(touched)
                .frame(height: 48)

            Spacer(minLength: lineHeight / 10)

            HStack {
                Text("water").strikethrough(waterTotal >= store.data.goalML)
                Spacer()
                Text("\(Self.formatAmount(waterTotal))/\(Self.formatAmount(store.data.goalML))ml")
            }
            .frame(height: lineHeight)

            HStack {
                Text("protein").strikethrough(proteinTotal >= store.data.proteinGoalG)
                Spacer()
                Text("\(Self.formatAmount(proteinTotal))/\(Self.formatAmount(store.data.proteinGoalG))gr")
            }
            .frame(height: lineHeight)

            HStack {
                Text("coffee").strikethrough(coffeeTotal >= store.data.coffeeGoal)
                Spacer()
                Text("\(Self.formatAmount(coffeeTotal))/\(Self.formatAmount(store.data.coffeeGoal))cups")
            }
            .frame(height: lineHeight)

            HStack {
                Text("carbs").strikethrough(carbsTotal >= store.data.carbsGoalG)
                Spacer()
                Text("\(Self.formatAmount(carbsTotal))/\(Self.formatAmount(store.data.carbsGoalG))gr")
            }
            .frame(height: lineHeight)

            ForEach(store.todoItems.filter { $0.link == .none }) { item in
                HStack {
                    Text(item.staticLabel).strikethrough(doneTaskIDs.contains(item.id))
                    Spacer()
                }
                .frame(height: lineHeight)
            }
        }
    }

    // History is now its own full page (reached by swiping, not
    // pushed from settings) with its own NavigationStack for the
    // day-detail page — completely separate from settingsPath. Bare
    // chrome throughout (no system nav bar, no title text): the
    // streak/total numbers and the dot+date already say what page
    // you're on.
    // Same true-full-screen technique `numberStack` uses: a nested
    // GeometryReader with `.ignoresSafeArea()` applied directly to it
    // reports the TRUE screen size no matter what's around it — a
    // NavigationStack (which both History pages sit inside, unlike
    // homeScreen) reserves its own safe-area room for a potential nav
    // bar even when that bar is hidden, so padding based on the OUTER
    // `geo` alone landed lower than `numberStack`'s "topInset + 8" and
    // visibly jumped at the Home<->History swipe boundary. Nesting the
    // reader restores the same true-coordinate math both places use.
    // Uses the OUTER `geo` (passed in from body's top-level
    // GeometryReader) for its true-size math, NOT a nested
    // GeometryReader inside the NavigationStack — a nested reader
    // here was reporting a size shorter/narrower than the real
    // window on macOS (a "screen within a screen": the last row
    // clipped, extra padding on the right that isn't on the left).
    // `homeScreen`'s `trueFullHeight` uses this exact same outer-geo
    // approach and has always been reliable; NavigationStack seems to
    // be what makes a NESTED reader's own geometry untrustworthy.
    private func historyFullPage(geo: GeometryProxy) -> some View {
        let trueFullWidth = geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing
        let trueFullHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom

        // The three numbers the layout below is built from.
        let topPad = contentTopPadding(geo.safeAreaInsets.top)
        let bottomPad = geo.safeAreaInsets.bottom + bottomInset
        // What the ScrollView can actually show at once. Matching the
        // content's minHeight to this is what makes "legend pinned to
        // the bottom" and "legend pushed down, page scrolls" the same
        // piece of layout instead of two modes to switch between.
        let viewportHeight = max(0, trueFullHeight - topPad - bottomPad)
        // Distance from the header down to the first row of marks,
        // chosen so that row lands on `historyGridTopFraction` of the
        // screen. Floored at the legend gap so it can't collapse (or
        // go negative) on a short screen.
        let gridTopGap = max(
            historyLegendMinGap,
            trueFullHeight * historyGridTopFraction - topPad - historyHeaderHeight
        )

        return NavigationStack(path: $historyDetailPath) {
            ScrollView {
                // Horizontal padding lives on the CONTENT here, not
                // the ScrollView itself — padding the ScrollView
                // shrinks its own bounds, and the system scroll
                // indicator draws at THOSE bounds' trailing edge, so
                // it ended up inset from the true screen edge instead
                // of flush against it.
                VStack(alignment: .leading, spacing: 0) {
                    historyStreakHeader

                    // Fixed, so the grid's top edge never moves as
                    // rows are added — new days push DOWNWARD.
                    Color.clear.frame(height: gridTopGap)

                    historyGrid

                    // The only flexible gap on the page. While the
                    // grid is short this soaks up all the slack and
                    // parks the legend on the bottom edge; once the
                    // grid grows past it, it clamps to its minimum,
                    // the content outgrows the viewport, and the
                    // legend rides down to the end of the scroll.
                    Spacer(minLength: historyLegendMinGap)

                    historyLegend
                }
                // minHeight (not height): exactly a screenful while it
                // fits, free to grow taller once it doesn't.
                .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .topLeading)
                .padding(.horizontal, sideInset)
                // Bottom inset belongs on the CONTENT, not the
                // ScrollView (see below) — it still lets the last
                // row scroll clear of the home indicator, without
                // shrinking the scrollable viewport itself.
                .padding(.bottom, bottomPad)
            }
            // ScrollView adds its OWN automatic top content inset by
            // default (tied to the safe area, independent of the
            // .padding below) — on top of a NavigationStack that ALSO
            // reserves space for its hidden nav bar, this was the
            // residual bit of drift between "4 streak" and the home
            // screen's "3 done" even after the geometry fix above.
            // Zeroing it here makes .padding(.top,...) below the ONLY
            // thing positioning content, same as numberStack's plain
            // VStack (no ScrollView) does.
            .contentMargins(.top, 0, for: .scrollContent)
            // No rubber-band scroll while the marks still fit on
            // screen — the page only becomes scrollable once the
            // grid actually grows past the bottom.
            .scrollBounceBehavior(.basedOnSize)
            // macOS reserves real WIDTH for a scrollbar track next to
            // scrollable content by default (unlike iOS's overlay-
            // style indicator, which doesn't take up layout space) —
            // that's a likely source of the right-side-only gap.
            .scrollIndicators(.hidden)
            .padding(.top, contentTopPadding(geo.safeAreaInsets.top))
            // NO .padding(.bottom) here on purpose — padding the
            // ScrollView shrinks its viewport, so its bounds ended
            // ~54pt above the real screen bottom and content was
            // clipped there, leaving dead space underneath. The
            // ScrollView now runs to the true bottom edge; the same
            // inset lives on its content instead (see above).
            .frame(width: trueFullWidth, height: trueFullHeight, alignment: .topLeading)
            .ignoresSafeArea()
            .buttonStyle(.plain)
            .font(textFont())
            .foregroundStyle(fillNavy)
            .background(pageBG.ignoresSafeArea())
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #else
            // iOS's equivalent above hides the nav bar — this is the
            // macOS placement for the same thing. Missing entirely
            // before, this was very likely reserving invisible space
            // for a title-bar-style strip inside the NavigationStack,
            // shrinking the actual content area (the "screen within a
            // screen" clipping).
            .toolbar(.hidden, for: .windowToolbar)
            #endif
            .navigationDestination(for: Date.self) { date in
                historyDayDetailPage(for: date, geo: geo)
            }
        }
    }

    // Same outer-geo true-size approach as `historyFullPage` — no
    // nested GeometryReader inside the NavigationStack's destination.
    private func historyDayDetailPage(for date: Date, geo: GeometryProxy) -> some View {
        let trueFullWidth = geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing
        let trueFullHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom

        return VStack(alignment: .leading, spacing: 0) {
            historyDayRows(for: date)
            Spacer(minLength: 0)
            HStack {
                Button("<") { historyDetailPath.removeLast() }
                Spacer()
            }
            .frame(height: lineHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, sideInset)
        .padding(.top, contentTopPadding(geo.safeAreaInsets.top))
        .padding(.bottom, geo.safeAreaInsets.bottom + bottomInset)
        .frame(width: trueFullWidth, height: trueFullHeight, alignment: .topLeading)
        .ignoresSafeArea()
        .buttonStyle(.plain)
        .font(textFont())
        .foregroundStyle(fillNavy)
        .background(pageBG.ignoresSafeArea())
        #if os(iOS)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        #else
        .toolbar(.hidden, for: .windowToolbar)
        #endif
    }

    #if os(macOS)
    // macOS has no touch swipe, so History is reached by a two-finger
    // trackpad swipe instead — see `TrackpadSwipeCatcher` below. Same
    // catcher also drives the vertical-scroll tracker-cycling on this
    // platform (iOS uses a plain DragGesture on the home screen for
    // that instead, see `homeScreen`).
    // Back to two pages, one direction — History always slides in
    // from the trailing edge and out toward it, Home the reverse.
    private func homeOrHistoryMac(geo: GeometryProxy) -> some View {
        ZStack {
            switch homePage {
            case .home:
                homeScreen(geo: geo)
                    .transition(.move(edge: .leading))
            case .history:
                historyFullPage(geo: geo)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: homePage)
        .background(
            TrackpadSwipeCatcher(
                onSwipeRight: {
                    if homePage == .history { homePage = .home }
                },
                onSwipeLeft: {
                    if homePage == .home { homePage = .history }
                },
                onScrollUp: { cycleActiveMetric(forward: true) },
                onScrollDown: { cycleActiveMetric(forward: false) }
            )
        )
    }
    #endif

    // MARK: - macOS settings flow (NavigationStack, in-window — no
    // .sheet, see the note on `settingsPath` above for why)

    #if os(macOS)
    @ViewBuilder
    private func settingsFlow(size: CGSize) -> some View {
        // "more" isn't part of settingsPath's navigation (it's reached
        // straight from the home screen, not from within settings) —
        // just swap in its page directly, same `page(...)` container.
        if bottomMode == .quickAdd {
            quickAddPage(size: size)
        } else {
            settingsNavigationFlow(size: size)
        }
    }

    // Root menu: "trackers" and "test stuff".
    private func settingsNavigationFlow(size: CGSize) -> some View {
        NavigationStack(path: $settingsPath) {
            page(size: size) {
                settingsRootRows

                Spacer(minLength: 0)

                HStack {
                    Button("close") {
                        bottomMode = .main
                        settingsPath.removeAll()
                    }
                    Spacer()
                }
                .frame(height: lineHeight)
            }
            .navigationDestination(for: SettingsDestination.self) { destination in
                settingsDetailPage(destination, size: size)
            }
        }
    }

    private func settingsDetailPage(_ destination: SettingsDestination, size: CGSize) -> some View {
        page(size: size) {
            switch destination {
            case .todos:
                todosPageRows
            case .allLogs:
                allLogsList
            case .testStuff:
                testStuffRows
            }

            Spacer(minLength: 0)

            HStack {
                Button("< \(destination.title)") { settingsPath.removeLast() }
                Spacer()
                Button("close") {
                    bottomMode = .main
                    settingsPath.removeAll()
                }
            }
            .frame(height: lineHeight)
        }
    }
    #endif

    // MARK: - iOS settings sheet
    //
    // Native .sheet + NavigationStack: partial-height, drag-
    // dismissible, sliding push navigation. Custom circular back/X
    // buttons (not the system blue chevron) so it still looks like
    // Drinkstand, not stock iOS — only the presentation MECHANICS are
    // native, per the reference video.

    #if os(iOS)
    /// How loud a `glassCircleButton` is.
    ///
    /// `.regular` is the neutral glass Apple uses for chrome you look
    /// past — back, close. It picks up light or dark from the system
    /// on its own, which is exactly the behaviour we want and the
    /// reason it isn't built out of our own palette.
    ///
    /// `.prominent` is the one action that moves you forward. Tinted
    /// with `fillNavy`, so it's a dark glass circle with a light glyph
    /// in light mode and inverts along with everything else in dark
    /// mode — "the ink-colored button", the same way the rest of the
    /// app treats fillNavy.
    private enum GlassButtonWeight { case regular, prominent }

    // Native iOS 26 Liquid Glass, applied explicitly to a circle we
    // control — rather than the toolbar's OWN automatic glass chrome,
    // which we still suppress per-ToolbarItem via
    // .sharedBackgroundVisibility(.hidden) (see those call sites) so
    // it doesn't layer a second glass ring behind this one.
    //
    // `.interactive()` is what gives it the press response — the
    // glass flexes and re-lights under your finger instead of just
    // dimming. Free, native, and the thing that makes it read as a
    // real iOS 26 control rather than a circle with a blur behind it.
    private func glassCircleButton(
        systemName: String,
        weight: GlassButtonWeight = .regular,
        // 44 = Apple's minimum comfortable tap target, and what the
        // Liquid Glass circles in the reference screenshots measure
        // out to. Every back/close in the app is this size; only the
        // tour's "next" goes bigger, because it's the one thing on
        // the page you're meant to reach for.
        diameter: CGFloat = 44,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: diameter * 0.44, weight: .medium))
                .foregroundStyle(weight == .prominent ? pageBG : fillNavy)
                .frame(width: diameter, height: diameter)
                .glassEffect(
                    weight == .prominent
                        ? .regular.tint(fillNavy).interactive()
                        : .regular.interactive(),
                    in: .circle
                )
        }
        .buttonStyle(.plain)
    }

    /// The toolbar-sized one every sheet's back/close uses.
    private func circleIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        glassCircleButton(systemName: systemName, action: action)
    }

    /// Calendar-style pill switch (min/max — see `goalSheet`), built
    /// to match `circleIconButton`'s own weight/feel: same 44pt
    /// height, same Liquid Glass material on the outer capsule. The
    /// native `.pickerStyle(.segmented)` was tried first and read too
    /// small/flat sitting next to the circular glass X/checkmark —
    /// this reuses that exact material instead of the system control.
    private func goalModePill(selection: Binding<GoalMode>) -> some View {
        HStack(spacing: 2) {
            goalModeSegment(.min, label: "min", selection: selection)
            goalModeSegment(.max, label: "max", selection: selection)
        }
        .padding(4)
        .frame(height: 44)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    /// One tap target inside `goalModePill` — plain text normally,
    /// but the selected side gets its own solid capsule (fillNavy, so
    /// it's dark-on-light or light-on-dark to match whichever mode
    /// the system is in) — same dark-pill-on-glass look the reference
    /// screenshot's own selected segment has.
    private func goalModeSegment(_ mode: GoalMode, label: String, selection: Binding<GoalMode>) -> some View {
        let selected = selection.wrappedValue == mode
        return Button {
            guard selection.wrappedValue != mode else { return }
            withAnimation(.easeInOut(duration: 0.2)) { selection.wrappedValue = mode }
        } label: {
            Text(label)
                .font(textFont(20))
                .foregroundStyle(selected ? pageBG : fillNavy)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background {
                    if selected {
                        Capsule().fill(fillNavy)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func settingsSheetTitle(_ title: String) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(title).font(textFont()).foregroundStyle(fillNavy)
        }
    }

    private var settingsSheetRoot: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsRootRows
            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
        .font(textFont())
        .foregroundStyle(fillNavy)
        .padding(.horizontal, sideInset)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(sheetBG)
        .toolbar {
            settingsSheetTitle("settings")
            ToolbarItem(placement: .topBarTrailing) {
                circleIconButton(systemName: "xmark") { showingSettingsSheet = false }
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    /// Shared by every settings detail page's toolbar — title (per
    /// destination) + circular back/close. Factored out so `.allLogs`
    /// (a `List`, not the shared row-VStack the others use) can get
    /// the identical chrome without going through that VStack too.
    @ToolbarContentBuilder
    private func settingsDetailToolbar(_ destination: SettingsDestination) -> some ToolbarContent {
        settingsSheetTitle(destination.title)
        ToolbarItem(placement: .topBarLeading) {
            circleIconButton(systemName: "chevron.left") { settingsPath.removeLast() }
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarTrailing) {
            circleIconButton(systemName: "xmark") { showingSettingsSheet = false }
        }
        .sharedBackgroundVisibility(.hidden)
    }

    @ViewBuilder
    private func settingsSheetDetail(_ destination: SettingsDestination) -> some View {
        if destination == .allLogs {
            allLogsList
                .foregroundStyle(fillNavy)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(sheetBG)
                .navigationBarBackButtonHidden(true)
                .toolbar { settingsDetailToolbar(destination) }
        } else {
            let detailContent = VStack(alignment: .leading, spacing: 0) {
                switch destination {
                case .todos:
                    todosPageRows
                case .testStuff:
                    testStuffRows
                case .allLogs:
                    EmptyView()
                }
                Spacer(minLength: 0)
            }
            .buttonStyle(.plain)
            .font(textFont())
            .foregroundStyle(fillNavy)
            .padding(.horizontal, sideInset)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(sheetBG)
            .navigationBarBackButtonHidden(true)
            .toolbar { settingsDetailToolbar(destination) }

            detailContent
        }
    }

    private var settingsSheet: some View {
        NavigationStack(path: $settingsPath) {
            settingsSheetRoot
                .navigationDestination(for: SettingsDestination.self) { destination in
                    settingsSheetDetail(destination)
                }
        }
        // .large ONLY — this page opens straight to full height (like
        // tapping the profile button in the App Store), rather than
        // starting half-height and needing a drag up.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onDisappear { settingsPath.removeAll() }
        // Nested sheet: the goal wheel opens on TOP of this page,
        // leaving the trackers list visible behind it.
        .sheet(item: $goalSheetKind) { kind in
            goalSheet(for: kind)
        }
    }

    // Same layover as settings — a native sheet, rounded card, the
    // same circular glass buttons — just for one day's detail. No
    // title text (the big date "•12.09" IS the title, as content, not
    // a toolbar row) and no back-vs-close distinction to make since
    // this is always a single level: both buttons just dismiss.
    private var historyDaySheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                historyDayRows(for: historySheetDate)
                Spacer(minLength: 0)
            }
            .buttonStyle(.plain)
            .font(textFont())
            .foregroundStyle(fillNavy)
            .padding(.horizontal, sideInset)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(sheetBG)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    circleIconButton(systemName: "chevron.left") { showingHistoryDaySheet = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    circleIconButton(systemName: "xmark") { showingHistoryDaySheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // Same shape as settingsSheetRoot — title toolbar + circular "X",
    // same presentation detents/drag indicator. No back button (this
    // is always one level, no push navigation) — still needs its own
    // NavigationStack though, just without a path, purely so the
    // .toolbar's topBarTrailing/.principal placements have a
    // navigation bar to attach to (they no-op without one).
    //
    // A flexible Spacer BEFORE the amount control and another BEFORE
    // "add" (not one pair wrapping the whole group) — that centers
    // the wheel in the space below the title while "add" still ends
    // up anchored toward the bottom, not floating in the middle along
    // with the wheel.
    private var quickAddSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                quickAddAmountControl(activeMetric)
                Spacer(minLength: 0)
                quickAddButtonRow(activeMetric)
            }
            .buttonStyle(.plain)
            .font(textFont())
            .foregroundStyle(fillNavy)
            .padding(.horizontal, sideInset)
            .padding(.bottom, 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(sheetBG)
            .toolbar {
                settingsSheetTitle(activeMetric.label)
                ToolbarItem(placement: .topBarTrailing) {
                    circleIconButton(systemName: "xmark") { dismissQuickAdd() }
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // Tracker goal editor — same wheel/sheet shape as quickAddSheet,
    // but the buttons change with the tracker's state: one "add" when
    // it's off (picking a goal is what switches it on), "delete" +
    // "save" once it's on. "delete" doesn't erase logged entries, it
    // just switches the tracker back off — the row returns to its
    // greyed-out "add" state and any history it already has stays
    // intact underneath.
    /// `allowDelete: false` is the first-run tour's variant — the
    /// tour is where you SET your first goal, so offering to delete
    /// the tracker in the same breath makes no sense, and the design
    /// for it shows a single centered "save". Everywhere else keeps
    /// the normal delete/save pair.
    private func goalSheet(for kind: TrackerKind, allowDelete: Bool = true) -> some View {
        let isOn = store.isTrackerEnabled(kind) && allowDelete
        let showsModeSwitch = kind.supportsGoalModeSwitch

        // Shared by the mode-switch checkmark AND the plain save/add
        // button below — same commit either kind ends up taking, the
        // mode-switch kinds just also stage `pendingGoalMode` first.
        func commitAndClose() {
            if showsModeSwitch {
                store.setGoalMode(pendingGoalMode, for: kind)
            }
            commitGoal(pendingGoal, for: kind)
            if !store.isTrackerEnabled(kind) { store.toggleTracker(kind) }
            goalSheetKind = nil
            tourGoalKind = nil
        }
        func cancelAndClose() {
            goalSheetKind = nil
            tourGoalKind = nil
        }

        return NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // Calendar-style top bar — EVERY tracker's goal sheet
                // now uses this, not just coffee/calories/cigarettes:
                // circular X (cancel) and checkmark (commit) flanking
                // either the min/max pill (mode-switch trackers) or
                // just the tracker's own name (everyone else), same
                // material/size either way. This is the sheet's ONLY
                // commit control — the old plain "save"/"add" text
                // button at the bottom is gone, the checkmark does its
                // job everywhere now.
                HStack {
                    circleIconButton(systemName: "xmark") { cancelAndClose() }
                    Spacer(minLength: 0)
                    if showsModeSwitch {
                        goalModePill(selection: $pendingGoalMode)
                            .frame(maxWidth: 240)
                    } else {
                        Text(kind.label)
                            .font(textFont())
                            .foregroundStyle(fillNavy)
                    }
                    Spacer(minLength: 0)
                    circleIconButton(systemName: "checkmark") { commitAndClose() }
                }
                .frame(height: 44)
                .padding(.top, 12)

                Spacer(minLength: 0)
                Picker("", selection: $pendingGoal) {
                    ForEach(goalCandidates(for: kind), id: \.self) { value in
                        Text("\(Self.formatAmount(value)) \(kind.unit)")
                            .font(textFont(24))
                            .foregroundColor(fillNavy)
                            .tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .tint(fillNavy)
                .frame(height: 160)
                Spacer(minLength: 0)

                // Only ever "delete" now (the checkmark above covers
                // save/add for everyone) — centered, same as every
                // other single-button layover in this app rather than
                // hugging the leading edge.
                if isOn {
                    HStack {
                        Spacer()
                        Button("delete") {
                            store.toggleTracker(kind)
                            if !store.isTrackerEnabled(activeMetric) {
                                activeMetric = enabledTrackers.first ?? .todo
                            }
                            goalSheetKind = nil
                        }
                        .foregroundStyle(fillProtein)
                        Spacer()
                    }
                    .frame(height: lineHeight)
                }
            }
            .buttonStyle(.plain)
            .font(textFont())
            .foregroundStyle(fillNavy)
            .padding(.horizontal, sideInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(sheetBG)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - First-run tour
    //
    // Five pages, shown once on a fresh install. The first two ASK
    // FOR REAL INPUT rather than just describing things — you set
    // your water goal and name your first habit, so by the time the
    // tour ends the app is already yours and already usable. (That's
    // also why a fresh install no longer ships sample to-dos; see
    // `TodoTask.defaults`.) The last three explain what the app does
    // with that, using the app's own components so they can't drift
    // out of sync with the real thing.
    //
    // iOS only: the designs are phone-shaped, and the macOS build is
    // a 340x640 menu bar popover with nowhere to put this.

    private enum TourPage: Int, CaseIterable {
        case goal, habit, fill, streak, simple

        var next: TourPage? { TourPage(rawValue: rawValue + 1) }
        var isLast: Bool { next == nil }
    }

    /// Where the blue comes to rest on the `fill` page — chosen so it
    /// cuts straight THROUGH the big numbers, which is the whole
    /// point of that page: you watch it rise and stop mid-text, and
    /// the two-tone mask that makes the home screen readable at any
    /// level is suddenly obvious.
    private let tourFillRestingLevel: CGFloat = 0.73

    private func advanceTour() {
        // Drop the keyboard before the slide — animating a focused
        // field sideways is visibly janky, and the habit is already
        // committed below either way.
        tourHabitFocused = false
        commitTourHabit()

        guard let next = tourPage.next else {
            finishTour()
            return
        }
        withAnimation(.easeInOut(duration: 0.35)) {
            tourPage = next
        }
    }

    /// Writes whatever's been typed on the habit page into the real
    /// list — idempotent, so advancing past it (or closing the tour
    /// from a later page) can't create the same to-do twice.
    private func commitTourHabit() {
        let name = tourHabit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, tourHabitTaskID == nil else { return }
        let id = store.insertBlankTodoTask()
        store.setTodoTaskName(id: id, to: name)
        tourHabitTaskID = id
    }

    private func finishTour() {
        commitTourHabit()
        tourHabitFocused = false
        hasSeenTour = true
        showingTour = false
    }

    // The whole tour: one sliding layer with the pages, one fixed
    // layer with the buttons. The buttons deliberately sit OUTSIDE
    // the transition so they stay nailed in place while everything
    // behind them slides — pressing "next" shouldn't make the thing
    // you just pressed fly off the screen.
    private var tourView: some View {
        ZStack(alignment: .topLeading) {
            pageBG.ignoresSafeArea()

            Group {
                switch tourPage {
                case .goal: tourGoalPage
                case .habit: tourHabitPage
                case .fill: tourFillPage
                case .streak: tourStreakPage
                case .simple: tourSimplePage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // New page in from the right, old one out to the left —
            // `.id` is what makes SwiftUI treat a page change as a
            // replacement (and so run the transition) rather than an
            // in-place update of the same view.
            .id(tourPage)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            ))

            tourChrome
        }
        .font(textFont())
        .foregroundStyle(fillNavy)
        .buttonStyle(.plain)
        .sheet(item: $tourGoalKind) { kind in
            // Its own binding, not the shared `goalSheetKind`: that
            // one's `.sheet` hangs off the root view, which is BEHIND
            // this full-screen cover and can't present over it.
            goalSheet(for: kind, allowDelete: false)
        }
    }

    private var tourChrome: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                glassCircleButton(systemName: "xmark") { finishTour() }
            }
            Spacer()
            HStack {
                Spacer()
                glassCircleButton(
                    systemName: tourPage.isLast ? "checkmark" : "chevron.right",
                    weight: .prominent,
                    diameter: 52
                ) { advanceTour() }
            }
        }
        .padding(.horizontal, sideInset)
        .padding(.vertical, 24)
    }

    /// Shared page shape: heading pinned top-left, whatever the page
    /// is about in the middle, a line of copy bottom-left. Trailing
    /// padding on the copy keeps it clear of the "next" button, which
    /// floats over every page in the same spot.
    private func tourScaffold<Content: View>(
        heading: String? = nil,
        caption: String? = nil,
        captionIsHint: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let heading {
                Text(heading)
                    .font(textFont(34))
                    .underline()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
            content()
            Spacer(minLength: 0)

            if let caption {
                Text(caption)
                    .font(textFont())
                    .underline(!captionIsHint)
                    .foregroundStyle(captionIsHint ? greyText : fillNavy)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 80)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, sideInset)
        .padding(.top, 56)
        .padding(.bottom, 96)
    }

    // Page 1 — set a real goal. The row is deliberately the same
    // shape as the one on the trackers page, so finding it there
    // later is recognition rather than discovery. Only the number is
    // tappable: the on/off icon is inert here, since switching water
    // OFF in the middle of "let's track your water" would be a
    // strange thing to let happen by accident.
    private var tourGoalPage: some View {
        tourScaffold(
            heading: "shall we start tracking your water?",
            caption: "tap the number to change how much you're aiming for...",
            captionIsHint: true
        ) {
            HStack {
                HStack(spacing: 8) {
                    toggleIcon(filled: true)
                    Text("water")
                }
                Spacer()
                Button {
                    pendingGoal = snappedGoal(store.data.goalML, for: .water)
                    tourGoalKind = .water
                } label: {
                    goalInputBorder {
                        Text("\(Self.formatAmount(store.data.goalML)) \(TrackerKind.water.unit)")
                    }
                }
            }
            .frame(height: lineHeight + 8)
        }
    }

    // Page 2 — name a real habit. Same field and same rotating,
    // typed-out suggestions as the trackers page, just left-aligned
    // (there's no label column to hang off here) and focused on
    // arrival, so the keyboard is already up and you can just type.
    private var tourHabitPage: some View {
        tourScaffold(heading: "which habit would you like to add?") {
            ZStack(alignment: .leading) {
                if tourHabit.isEmpty {
                    TypingSuggestion(suggestions: Self.todoSuggestions, color: greyText)
                        .allowsHitTesting(false)
                }
                TodoTextField(
                    text: $tourHabit,
                    isFocused: tourHabitFocused,
                    textColor: UIColor(fillNavy),
                    font: UIFont(name: "GoogleSansCode-Medium", size: bodyTextSize * fontScale),
                    alignment: .left,
                    onFocusChange: { tourHabitFocused = $0 },
                    onSubmit: { advanceTour() },
                    onBackspaceWhenEmpty: {}
                )
                .frame(height: lineHeight)
            }
            .onAppear { tourHabitFocused = true }
        }
    }

    // Page 3 — the home screen's one real trick, animated. The blue
    // rises on arrival and stops mid-number, which is exactly when
    // the two-tone mask becomes visible: dark where the fill hasn't
    // reached, light where it has. Drawn with the SAME two-layer
    // technique `numberStack` uses (see it for why), so what's shown
    // here is what the app actually does.
    //
    // `.ignoresSafeArea()` on the whole stack, not just the color:
    // the mask rectangle and the fill rectangle have to share one
    // coordinate space or they drift apart, and that drift is
    // precisely the bug this page is trying to show off.
    private var tourFillPage: some View {
        GeometryReader { geo in
            let fillHeight = geo.size.height * tourFillProgress

            let content = VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0).frame(height: geo.size.height * 0.24)
                VStack(alignment: .leading, spacing: 0) {
                    Text("1 done")
                    Text("3.000ml")
                }
                .font(numberFont(50))
                .tracking(-2)

                Spacer(minLength: 0)

                Text("no motivation needed,\nyou can already do it,\nnow you actually will")
                    .font(textFont())
                    .underline()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 80)
                Spacer(minLength: 0).frame(height: geo.size.height * 0.15)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .padding(.horizontal, sideInset)

            ZStack(alignment: .topLeading) {
                fillWater
                    .frame(height: fillHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                content.foregroundStyle(fillNavy)
                content
                    .foregroundStyle(pageBG)
                    .mask(
                        Rectangle()
                            .frame(height: fillHeight)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    )
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .onAppear {
            tourFillProgress = 0
            withAnimation(.easeOut(duration: 1.4)) {
                tourFillProgress = tourFillRestingLevel
            }
        }
    }

    // Page 4 — what History looks like once it has something to
    // show, built from the real `historyMark` so the marks here and
    // the marks there can never disagree. Static on purpose: a brand
    // new user has no history, and "0 streak" would undersell it.
    private var tourStreakPage: some View {
        tourScaffold(caption: "trackers and todo's\ngive you the streak\nyou need") {
            VStack(spacing: 12) {
                ForEach(Array(Self.tourStreakRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            historyMark(showDot: cell.dot, color: cell.color)
                        }
                    }
                }
            }
        }
    }

    /// The three rows page 4 draws — a run that starts plain, then
    /// crosses the 10-day line mid-row and turns green from there,
    /// which is the one rule about History worth showing rather than
    /// explaining.
    private static var tourStreakRows: [[(dot: Bool, color: Color)]] {
        let today = historyTodayColor, navy = fillNavy, green = historyMilestone10
        return [
            [(false, today), (true, navy), (false, navy), (true, navy), (false, navy), (false, navy)],
            [(true, navy), (true, navy), (false, navy), (false, navy), (true, green), (true, green)],
            Array(repeating: (dot: true, color: green), count: 6),
        ]
    }

    // Page 5 — the sign-off.
    private var tourSimplePage: some View {
        tourScaffold(caption: "you focus,\nwe keep it simple") {
            VStack(spacing: 28) {
                Text("100%")
                    .font(numberFont(44))
                    .tracking(-2)
                    .foregroundStyle(pageBG)
                    .frame(width: 172, height: 172)
                    .background(fillNavy, in: .circle)

                Rectangle()
                    .fill(fillNavy)
                    .frame(width: 210, height: 24)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    #endif
}
