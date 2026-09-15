// WaterStore.swift
// Target membership: Drinkstand

import Foundation
import Combine
import SwiftUI
import CloudKit

// The log-entry types are `nonisolated` because they cross the actor
// boundary: the sync helpers build and parse them off the main actor
// (see CKMappable). Default isolation for this target is MainActor,
// so without this they'd be main-actor types — plain data that can't
// leave the main thread.
nonisolated struct WaterEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var amountML: Int
    var timestamp: Date

    init(amountML: Int, timestamp: Date = .now, id: UUID = UUID()) {
        self.id = id
        self.amountML = amountML
        self.timestamp = timestamp
    }
}

nonisolated struct ProteinEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var amountG: Int
    var timestamp: Date

    init(amountG: Int, timestamp: Date = .now, id: UUID = UUID()) {
        self.id = id
        self.amountG = amountG
        self.timestamp = timestamp
    }
}

nonisolated struct CoffeeEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var amountCups: Int
    var timestamp: Date

    init(amountCups: Int, timestamp: Date = .now, id: UUID = UUID()) {
        self.id = id
        self.amountCups = amountCups
        self.timestamp = timestamp
    }
}

nonisolated struct CarbsEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var amountG: Int
    var timestamp: Date

    init(amountG: Int, timestamp: Date = .now, id: UUID = UUID()) {
        self.id = id
        self.amountG = amountG
        self.timestamp = timestamp
    }
}

nonisolated struct StepsEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var amountSteps: Int
    var timestamp: Date

    init(amountSteps: Int, timestamp: Date = .now, id: UUID = UUID()) {
        self.id = id
        self.amountSteps = amountSteps
        self.timestamp = timestamp
    }
}

nonisolated struct MovementEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var amountMin: Int
    var timestamp: Date

    init(amountMin: Int, timestamp: Date = .now, id: UUID = UUID()) {
        self.id = id
        self.amountMin = amountMin
        self.timestamp = timestamp
    }
}

nonisolated struct SleepEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var amountHr: Int
    var timestamp: Date

    init(amountHr: Int, timestamp: Date = .now, id: UUID = UUID()) {
        self.id = id
        self.amountHr = amountHr
        self.timestamp = timestamp
    }
}

nonisolated struct CigarettesEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var amountCigs: Int
    var timestamp: Date

    init(amountCigs: Int, timestamp: Date = .now, id: UUID = UUID()) {
        self.id = id
        self.amountCigs = amountCigs
        self.timestamp = timestamp
    }
}

/// Whether a tracker's goal is a floor to reach (`.min`, the original
/// behavior — water, protein, steps, movement, sleep) or a ceiling to
/// stay under (`.max` — coffee, calories, cigarettes are the ones
/// that can be switched to it; see `goalModes`). Only meaningful for
/// trackers the settings UI actually exposes the switch for; every
/// other tracker is always treated as `.min` regardless of what's
/// stored here.
enum GoalMode: String, Codable {
    case min, max
}

/// A single check-off of a to-do item on a given day. Presence of a
/// record for "today" means that task is done; removing it un-checks
/// it. Only used for plain (unlinked) items — see `TodoItem`. The
/// item list itself (user-editable custom slots + the fixed linked
/// ones) lives in `WaterStore.todoItems`.
nonisolated struct TodoCompletion: Codable, Identifiable, Hashable {
    let id: UUID
    var task: String
    var timestamp: Date

    init(task: String, timestamp: Date = .now, id: UUID = UUID()) {
        self.id = id
        self.task = task
        self.timestamp = timestamp
    }
}

/// One user-defined to-do, as STORED (see `AppData.todoTasks`) —
/// distinct from `TodoItem` below, which is the rendered checklist
/// row and also covers the auto-completing tracker-linked ones.
///
/// The id exists for the settings editor's benefit only: it gives
/// each text field a stable identity so focus survives rows being
/// added or removed around it. It is deliberately NOT what
/// completions are keyed by — those still match on `name`.
struct TodoTask: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    /// What a fresh install starts with: NOTHING. There used to be
    /// three sample to-dos here ("Leg day", "10pg read", "45m
    /// sport"), but the first-run tour now asks for one habit in your
    /// own words and creates it — samples on top of that would mean
    /// starting at four to-dos, only one of which you chose.
    static let defaults: [TodoTask] = []
}

/// A row in the to-do checklist. Plain items are tapped by hand like
/// before; `.water`/`.protein` items instead show a live-updating
/// label (today's goal, rounded to a friendly unit) and strike
/// themselves through automatically once that tracker's goal is hit
/// — not manually toggleable, no completion record needed.
struct TodoItem: Identifiable, Hashable {
    enum Link: Hashable {
        case none, water, protein, coffee, carbs, steps, movement, sleep, cigarettes

        /// The tracker this row mirrors, or nil for a plain
        /// hand-ticked item that isn't tied to one.
        var trackerKind: TrackerKind? {
            switch self {
            case .none: nil
            case .water: .water
            case .protein: .protein
            case .coffee: .coffee
            case .carbs: .carbs
            case .steps: .steps
            case .movement: .movement
            case .sleep: .sleep
            case .cigarettes: .cigarettes
            }
        }
    }
    let id: String
    let staticLabel: String
    let link: Link
}

/// The trackers shown on the home screen's left column. Fixed set for
/// now — "trackers" in settings only lets you show/hide these, not
/// define new ones.
enum TrackerKind: String, Codable, CaseIterable, Identifiable {
    // Raw values (and therefore this case's NAME) are what's actually
    // persisted — in `disabledTrackers`, `goalModes`, and synced to
    // CloudKit — so `carbs` stays `carbs` here even though it now
    // DISPLAYS as "calories": renaming the case would silently orphan
    // every existing save's disabled/goal-mode state for it. Same
    // reasoning the `todoTaskSlots` CloudKit field name already
    // follows elsewhere in this file.
    case todo, water, protein, coffee, carbs, steps, movement, sleep, cigarettes
    var id: String { rawValue }

    var label: String {
        switch self {
        case .todo: "todo"
        case .water: "water"
        case .protein: "protein"
        case .coffee: "coffee"
        case .carbs: "calories"
        case .steps: "steps"
        case .movement: "movement"
        case .sleep: "sleep"
        case .cigarettes: "cigarettes"
        }
    }

    /// Quick-add preset amounts shown on the home screen; "more"
    /// opens the free-entry panel instead.
    ///
    /// Coffee's presets are cup COUNTS, not a continuous amount like
    /// the others — 1/2/3 cups covers a normal day's logging in one
    /// tap each. Calories uses the same three-tier shape as protein/
    /// water, sized to typical meal/snack increments (a snack ≈150,
    /// a light meal ≈350, a full meal ≈600). Steps mirrors water's
    /// three-tier shape at a step-count scale (a short walk ≈1000, a
    /// longer one ≈2500, a proper walk/run ≈5000). Movement is
    /// minutes in 10/20/30 chunks — common workout-block sizes.
    /// Sleep's presets are whole hours (6/7/8), since that's how
    /// people actually think about a night's sleep, not a continuous
    /// amount you add to across the day. Cigarettes is a plain count,
    /// one at a time being the normal way you'd log it, with 3/5 as
    /// shortcuts for logging a few at once after the fact.
    var presets: [Int] {
        switch self {
        case .todo: []
        case .water: [330, 500, 700]
        case .protein: [20, 40, 60]
        case .coffee: [1, 2, 3]
        case .carbs: [150, 350, 600]
        case .steps: [1000, 2500, 5000]
        case .movement: [10, 20, 30]
        case .sleep: [6, 7, 8]
        case .cigarettes: [1, 3, 5]
        }
    }

    var unit: String {
        switch self {
        case .todo: ""
        case .water: "ml"
        case .protein: "gr"
        case .coffee: "cups"
        case .carbs: "kcal"
        // No unit string for steps/cigarettes — "steps(steps)" would
        // be redundant the way "water(ml)" isn't; the row label alone
        // already says what it's counting.
        case .steps: ""
        case .movement: "min"
        case .sleep: "hr"
        case .cigarettes: ""
        }
    }

    /// Coffee, calories, and cigarettes are the trackers the settings
    /// UI actually lets you flip between "at least" (`.min`) and "at
    /// most" (`.max`) — see `GoalMode`. Every other tracker's goal is
    /// unambiguously one or the other (you don't "max out" water),
    /// so there's nothing to switch and no UI for it.
    var supportsGoalModeSwitch: Bool {
        switch self {
        case .coffee, .carbs, .cigarettes: true
        case .todo, .water, .protein, .steps, .movement, .sleep: false
        }
    }
}

/// Rough estimates (grams of protein per typical serving) for the
/// "type a food, get an amount" quick-add on the protein panel —
/// meant to get you close enough with one word, not to replace an
/// actual nutrition label. Easy to extend: just add more entries.
/// Keys are lowercase; `proteinForFood` also tries the singular form
/// (dropping a trailing "s") so plurals hit without listing both.
enum FoodProteinLookup {
    static let table: [String: Int] = [
        "croissant": 8,
        "egg": 6,
        "banana": 1,
        "apple": 0,
        "chicken breast": 31,
        "chicken": 27,
        "yogurt": 10,
        "greek yogurt": 17,
        "toast": 3,
        "bread": 3,
        "peanut butter": 8,
        "almonds": 6,
        "protein shake": 25,
        "protein bar": 20,
        "milk": 8,
        "cheese": 7,
        "avocado": 2,
        "salmon": 25,
        "rice": 4,
        "pasta": 8,
        "oatmeal": 6,
        "tofu": 10,
        "beans": 8,
        "hummus": 4,
        "tuna": 25
    ]

    static func grams(for foodName: String) -> Int? {
        let key = foodName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let exact = table[key] { return exact }
        if key.hasSuffix("s") { return table[String(key.dropLast())] }
        return nil
    }
}

struct AppData: Codable {
    var goalML: Int = 4000
    var proteinGoalG: Int = 2100
    /// Cups/day — a common "moderate caffeine" guideline, not a
    /// medical recommendation.
    var coffeeGoal: Int = 3
    /// Property name stayed `carbsGoalG` (unit-in-name and all) even
    /// though the tracker now displays as "calories" in kcal — see
    /// the comment on `TrackerKind`'s cases for why the underlying
    /// name doesn't follow the display rename.
    var carbsGoalG: Int = 2000
    /// A common "aim for" daily step count, not a medical
    /// recommendation.
    var stepsGoal: Int = 8000
    var movementGoalMin: Int = 30
    var sleepGoalHr: Int = 8
    /// A commonly-cited "cutting down" target, not a medical
    /// recommendation — same spirit as `coffeeGoal`.
    var cigarettesGoal: Int = 5
    var entries: [WaterEntry] = []
    var proteinEntries: [ProteinEntry] = []
    var coffeeEntries: [CoffeeEntry] = []
    var carbsEntries: [CarbsEntry] = []
    var stepsEntries: [StepsEntry] = []
    var movementEntries: [MovementEntry] = []
    var sleepEntries: [SleepEntry] = []
    var cigarettesEntries: [CigarettesEntry] = []
    var todoCompletions: [TodoCompletion] = []
    /// The user's own to-do names, in list order — a plain dynamic
    /// list now (no fixed slot count, no blank padding). A task can
    /// sit here with an empty name only WHILE it's being typed into;
    /// the editor prunes those the moment they lose focus, so nothing
    /// blank is ever persisted for long.
    ///
    /// Each carries a UUID purely so the editor has a stable identity
    /// per row: SwiftUI focus follows identity, and index-based
    /// identity breaks the moment a row above the focused one is
    /// removed (the classic "keyboard jumps to the wrong field").
    /// Completions are still keyed by NAME (see `TodoCompletion`), not
    /// by this id — renaming a task orphans its history exactly as it
    /// did before.
    var todoTasks: [TodoTask] = TodoTask.defaults
    /// Trackers NOT in this set are enabled. Water/protein/to-do on
    /// by default; coffee/carbs/steps/movement/sleep/cigarettes are
    /// newer and start off, an explicit "add" away, rather than
    /// suddenly appearing active for existing users (see the matching
    /// decode fallback below — though that fallback only covers a
    /// SAVE FILE predating `disabledTrackers` entirely; one from
    /// after an earlier tracker shipped but before a later one did
    /// will decode the later one as enabled, a one-time cosmetic
    /// quirk not worth a real migration for at this app's scale).
    var disabledTrackers: Set<TrackerKind> = [.coffee, .carbs, .steps, .movement, .sleep, .cigarettes]
    /// `.min`/`.max` per tracker, for the ones `TrackerKind.
    /// supportsGoalModeSwitch` allows switching at all (coffee,
    /// calories, cigarettes) — missing entries (every other tracker,
    /// and any of those three that's never been switched) read as
    /// `.min` via `WaterStore.goalMode(for:)`, never stored explicitly
    /// unless the user actually flips it.
    var goalModes: [TrackerKind: GoalMode] = [:]
    /// Bumped on every local write — used to decide which side's
    /// scalar settings (goals, disabled trackers) win when merging
    /// with the shared sync file. Entries/completions never use this;
    /// they always union instead, so a log entry is never lost.
    var lastModified: Date = .distantPast
    init() {}

    /// `todoTaskSlots` is the old fixed-slot key (see `todoTasks`) —
    /// still read below so existing saves migrate, never written.
    /// It lives in its own key type on purpose: a case in the real
    /// `CodingKeys` with no matching property stops Swift from
    /// synthesizing `encode(to:)` at all ("does not conform to
    /// Encodable"), and `CodingKeys` itself is better left synthesized
    /// so a newly added property can't silently go unencoded.
    private enum LegacyCodingKeys: String, CodingKey {
        case todoTaskSlots
    }

    // Manual decoding: auto-synthesized Codable ignores the property
    // defaults above for keys that are simply ABSENT (as opposed to
    // null) — it throws instead, and every field added after the very
    // first release of this struct (todoTaskSlots included) is exactly
    // that case for anyone's save file from before it existed. Without
    // this, WaterStore.init()'s `try?` treats that decode failure as
    // "start fresh," silently wiping existing history. Decoding each
    // field with a default keeps old saves intact as new fields keep
    // getting added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goalML = try c.decodeIfPresent(Int.self, forKey: .goalML) ?? 4000
        proteinGoalG = try c.decodeIfPresent(Int.self, forKey: .proteinGoalG) ?? 2100
        coffeeGoal = try c.decodeIfPresent(Int.self, forKey: .coffeeGoal) ?? 3
        carbsGoalG = try c.decodeIfPresent(Int.self, forKey: .carbsGoalG) ?? 2000
        stepsGoal = try c.decodeIfPresent(Int.self, forKey: .stepsGoal) ?? 8000
        movementGoalMin = try c.decodeIfPresent(Int.self, forKey: .movementGoalMin) ?? 30
        sleepGoalHr = try c.decodeIfPresent(Int.self, forKey: .sleepGoalHr) ?? 8
        cigarettesGoal = try c.decodeIfPresent(Int.self, forKey: .cigarettesGoal) ?? 5
        entries = try c.decodeIfPresent([WaterEntry].self, forKey: .entries) ?? []
        proteinEntries = try c.decodeIfPresent([ProteinEntry].self, forKey: .proteinEntries) ?? []
        coffeeEntries = try c.decodeIfPresent([CoffeeEntry].self, forKey: .coffeeEntries) ?? []
        carbsEntries = try c.decodeIfPresent([CarbsEntry].self, forKey: .carbsEntries) ?? []
        stepsEntries = try c.decodeIfPresent([StepsEntry].self, forKey: .stepsEntries) ?? []
        movementEntries = try c.decodeIfPresent([MovementEntry].self, forKey: .movementEntries) ?? []
        sleepEntries = try c.decodeIfPresent([SleepEntry].self, forKey: .sleepEntries) ?? []
        cigarettesEntries = try c.decodeIfPresent([CigarettesEntry].self, forKey: .cigarettesEntries) ?? []
        todoCompletions = try c.decodeIfPresent([TodoCompletion].self, forKey: .todoCompletions) ?? []
        // Missing key = a save from before coffee/carbs existed —
        // default THOSE off rather than []; an explicit (even empty)
        // saved set is always respected as-is. A save from AFTER
        // coffee/carbs but before steps/movement/sleep/cigarettes also
        // has this key, so it takes the "respected as-is" branch and
        // those decode as enabled — see the comment on the property
        // default above for why that one-time quirk is left alone.
        disabledTrackers = try c.decodeIfPresent(Set<TrackerKind>.self, forKey: .disabledTrackers) ?? [.coffee, .carbs, .steps, .movement, .sleep, .cigarettes]
        goalModes = try c.decodeIfPresent([TrackerKind: GoalMode].self, forKey: .goalModes) ?? [:]
        lastModified = try c.decodeIfPresent(Date.self, forKey: .lastModified) ?? .distantPast

        // Three formats to accept, newest first: the current
        // `todoTasks` (name + stable id), the older `todoTaskSlots`
        // (a fixed-length [String] with "" for unused slots — those
        // blanks are dropped, they were a storage artifact, never
        // real to-dos), and neither (a fresh install → the defaults).
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        if let tasks = try c.decodeIfPresent([TodoTask].self, forKey: .todoTasks) {
            todoTasks = tasks
        } else if let legacySlots = try legacy.decodeIfPresent([String].self, forKey: .todoTaskSlots) {
            let names = legacySlots.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            todoTasks = names.isEmpty ? TodoTask.defaults : names.map { TodoTask(name: $0) }
        } else {
            todoTasks = TodoTask.defaults
        }
    }
}

// MARK: - CloudKit record mapping
//
// Every log entry maps 1:1 to a CKRecord whose recordID IS the
// entry's own UUID — that's what makes sync close to free: two
// devices logging different entries just create different records
// (no merge needed), and re-saving the SAME id just overwrites in
// place (so re-pushing everything on every sync, which this does, is
// idempotent rather than duplicating anything). A real CKRecord
// delete is also a real deletion — unlike the old file-based union
// merge, "reset" no longer needs a `lastResetAt` cutoff hack to keep
// a deleted entry from quietly reappearing.

// `nonisolated` throughout, and not by accident: this target builds
// with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, so an unannotated
// protocol, extension or global here would be @MainActor — which
// would quietly drag every record-mapping call back onto the main
// thread and defeat the whole point of the `remote*` helpers below.
private nonisolated protocol CKMappable {
    static var ckRecordType: String { get }
    init?(record: CKRecord)
    func ckRecord() -> CKRecord
}

nonisolated extension WaterEntry: CKMappable {
    static let ckRecordType = "WaterEntry"
    init?(record: CKRecord) {
        guard let amountML = record["amountML"] as? Int,
              let timestamp = record["timestamp"] as? Date,
              let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        self.init(amountML: amountML, timestamp: timestamp, id: id)
    }
    func ckRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: id.uuidString))
        record["amountML"] = amountML
        record["timestamp"] = timestamp
        return record
    }
}

nonisolated extension ProteinEntry: CKMappable {
    static let ckRecordType = "ProteinEntry"
    init?(record: CKRecord) {
        guard let amountG = record["amountG"] as? Int,
              let timestamp = record["timestamp"] as? Date,
              let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        self.init(amountG: amountG, timestamp: timestamp, id: id)
    }
    func ckRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: id.uuidString))
        record["amountG"] = amountG
        record["timestamp"] = timestamp
        return record
    }
}

nonisolated extension CoffeeEntry: CKMappable {
    static let ckRecordType = "CoffeeEntry"
    init?(record: CKRecord) {
        guard let amountCups = record["amountCups"] as? Int,
              let timestamp = record["timestamp"] as? Date,
              let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        self.init(amountCups: amountCups, timestamp: timestamp, id: id)
    }
    func ckRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: id.uuidString))
        record["amountCups"] = amountCups
        record["timestamp"] = timestamp
        return record
    }
}

nonisolated extension CarbsEntry: CKMappable {
    static let ckRecordType = "CarbsEntry"
    init?(record: CKRecord) {
        guard let amountG = record["amountG"] as? Int,
              let timestamp = record["timestamp"] as? Date,
              let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        self.init(amountG: amountG, timestamp: timestamp, id: id)
    }
    func ckRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: id.uuidString))
        record["amountG"] = amountG
        record["timestamp"] = timestamp
        return record
    }
}

nonisolated extension StepsEntry: CKMappable {
    static let ckRecordType = "StepsEntry"
    init?(record: CKRecord) {
        guard let amountSteps = record["amountSteps"] as? Int,
              let timestamp = record["timestamp"] as? Date,
              let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        self.init(amountSteps: amountSteps, timestamp: timestamp, id: id)
    }
    func ckRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: id.uuidString))
        record["amountSteps"] = amountSteps
        record["timestamp"] = timestamp
        return record
    }
}

nonisolated extension MovementEntry: CKMappable {
    static let ckRecordType = "MovementEntry"
    init?(record: CKRecord) {
        guard let amountMin = record["amountMin"] as? Int,
              let timestamp = record["timestamp"] as? Date,
              let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        self.init(amountMin: amountMin, timestamp: timestamp, id: id)
    }
    func ckRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: id.uuidString))
        record["amountMin"] = amountMin
        record["timestamp"] = timestamp
        return record
    }
}

nonisolated extension SleepEntry: CKMappable {
    static let ckRecordType = "SleepEntry"
    init?(record: CKRecord) {
        guard let amountHr = record["amountHr"] as? Int,
              let timestamp = record["timestamp"] as? Date,
              let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        self.init(amountHr: amountHr, timestamp: timestamp, id: id)
    }
    func ckRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: id.uuidString))
        record["amountHr"] = amountHr
        record["timestamp"] = timestamp
        return record
    }
}

nonisolated extension CigarettesEntry: CKMappable {
    static let ckRecordType = "CigarettesEntry"
    init?(record: CKRecord) {
        guard let amountCigs = record["amountCigs"] as? Int,
              let timestamp = record["timestamp"] as? Date,
              let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        self.init(amountCigs: amountCigs, timestamp: timestamp, id: id)
    }
    func ckRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: id.uuidString))
        record["amountCigs"] = amountCigs
        record["timestamp"] = timestamp
        return record
    }
}

nonisolated extension TodoCompletion: CKMappable {
    static let ckRecordType = "TodoCompletion"
    init?(record: CKRecord) {
        guard let task = record["task"] as? String,
              let timestamp = record["timestamp"] as? Date,
              let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        self.init(task: task, timestamp: timestamp, id: id)
    }
    func ckRecord() -> CKRecord {
        let record = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: id.uuidString))
        record["task"] = task
        record["timestamp"] = timestamp
        return record
    }
}

// File scope on purpose, NOT nested in WaterStore: anything declared
// inside a @MainActor type inherits that isolation, and the
// `nonisolated` sync helpers below couldn't then touch it.

private nonisolated let ckSettingsRecordName = "AppSettings"

private nonisolated var ckSyncDatabase: CKDatabase {
    CKContainer.default().privateCloudDatabase
}

/// The settings record as read from CloudKit. Every field stays
/// optional so a missing one can be left alone rather than
/// overwriting the local value with a default.
private struct RemoteSettings: Sendable {
    var goalML: Int?
    var proteinGoalG: Int?
    var coffeeGoal: Int?
    var carbsGoalG: Int?
    var stepsGoal: Int?
    var movementGoalMin: Int?
    var sleepGoalHr: Int?
    var cigarettesGoal: Int?
    var todoNames: [String]?
    var disabledTrackerRawValues: [String]?
    /// `TrackerKind.rawValue: GoalMode.rawValue` — a plain
    /// `[String: String]` rather than shipping `goalModes` itself,
    /// since CKRecord fields need to be one of CloudKit's own storable
    /// types, not an arbitrary Codable dictionary.
    var goalModeRawValues: [String: String]?
    var lastModified: Date?
}

/// What a push sends up — read off `data` on the main actor (cheap
/// value copies), turned into a CKRecord away from it.
private struct SettingsPayload: Sendable {
    var goalML: Int
    var proteinGoalG: Int
    var coffeeGoal: Int
    var carbsGoalG: Int
    var stepsGoal: Int
    var movementGoalMin: Int
    var sleepGoalHr: Int
    var cigarettesGoal: Int
    var todoNames: [String]
    var disabledTrackerRawValues: [String]
    var goalModeRawValues: [String: String]
    var lastModified: Date
}

@MainActor
final class WaterStore: ObservableObject {
    @Published private(set) var data: AppData

    private let storageKey = "drinkstandData"

    /// Always present, auto-completing, not part of the user's own
    /// editable list — see `TodoItem.Link`.
    static let linkedTodoItems: [TodoItem] = [
        TodoItem(id: "protein-goal", staticLabel: "", link: .protein),
        TodoItem(id: "water-goal", staticLabel: "", link: .water),
        TodoItem(id: "coffee-goal", staticLabel: "", link: .coffee),
        TodoItem(id: "carbs-goal", staticLabel: "", link: .carbs),
        TodoItem(id: "steps-goal", staticLabel: "", link: .steps),
        TodoItem(id: "movement-goal", staticLabel: "", link: .movement),
        TodoItem(id: "sleep-goal", staticLabel: "", link: .sleep),
        TodoItem(id: "cigarettes-goal", staticLabel: "", link: .cigarettes),
    ]

    /// The live checklist: the user's own tasks (in list order) plus
    /// the linked ones. A task that's momentarily blank because it's
    /// being typed into in settings is skipped here rather than
    /// showing up as an empty checklist row.
    var todoItems: [TodoItem] {
        // A `TodoItem`'s id IS its name (that's what ties it to a
        // `TodoCompletion`, which also stores the name) — so two
        // to-dos called the same thing would hand ForEach two rows
        // with one id, and ticking either would tick both. That was
        // near-impossible with five fixed slots; with free text and
        // no limit it's a matter of time, so the second one is
        // dropped from the checklist here. It stays in the settings
        // list, where rows are keyed by UUID and duplicates are
        // harmless — you can see it and rename it.
        var seen = Set<String>()
        let custom = data.todoTasks
            .map(\.name)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .filter { seen.insert($0).inserted }
            .map { TodoItem(id: $0, staticLabel: $0, link: .none) }
        // A linked row only exists while ITS tracker is on — a
        // switched-off tracker shouldn't keep contributing a
        // checklist row (and a slice of todoProgress) that can never
        // be seen or ticked.
        let linked = Self.linkedTodoItems.filter { item in
            guard let kind = item.link.trackerKind else { return true }
            return isTrackerEnabled(kind)
        }
        return custom + linked
    }

    init() {
        if let saved = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(AppData.self, from: saved) {
            data = decoded
        } else {
            data = AppData()
        }
        refreshCloudKitAccountStatus()
        // First sync after launch: push whatever's local (covers a
        // fresh install migrating its very first UserDefaults-only
        // data up to CloudKit) and pull in anything from elsewhere.
        Task {
            await pushToCloudKit()
            await pullFromCloudKit()
        }
    }

    // MARK: - Water

    var todayEntries: [WaterEntry] {
        let start = Calendar.current.startOfDay(for: .now)
        return data.entries
            .filter { $0.timestamp >= start }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var todayTotal: Int {
        todayEntries.reduce(0) { $0 + $1.amountML }
    }

    var progress: Double {
        min(1.0, Double(todayTotal) / Double(max(data.goalML, 1)))
    }

    func addWater(_ amount: Int) {
        guard amount > 0 else { return }
        data.entries.append(WaterEntry(amountML: amount))
        persist()
    }

    func setGoal(_ goal: Int) {
        // No floor here on purpose — the goal field is live-bound to
        // a TextField, so this runs on every keystroke while typing.
        // A "max(100, ...)" clamp used to fire mid-type (e.g. typing
        // "1" of "160" would clamp to 100 before the next digit even
        // lands), corrupting the value as you typed. The field
        // already only accepts digits, so `goal` can't go negative.
        data.goalML = goal
        persist()
    }

    // MARK: - Protein

    var todayProteinEntries: [ProteinEntry] {
        let start = Calendar.current.startOfDay(for: .now)
        return data.proteinEntries
            .filter { $0.timestamp >= start }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var todayProteinTotal: Int {
        todayProteinEntries.reduce(0) { $0 + $1.amountG }
    }

    var proteinProgress: Double {
        min(1.0, Double(todayProteinTotal) / Double(max(data.proteinGoalG, 1)))
    }

    func addProtein(_ amount: Int) {
        guard amount > 0 else { return }
        data.proteinEntries.append(ProteinEntry(amountG: amount))
        persist()
    }

    func setProteinGoal(_ goal: Int) {
        // Same reasoning as setGoal — no floor, this runs live per
        // keystroke and a clamp would corrupt the value mid-type.
        data.proteinGoalG = goal
        persist()
    }

    // MARK: - Coffee

    var todayCoffeeEntries: [CoffeeEntry] {
        let start = Calendar.current.startOfDay(for: .now)
        return data.coffeeEntries
            .filter { $0.timestamp >= start }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var todayCoffeeTotal: Int {
        todayCoffeeEntries.reduce(0) { $0 + $1.amountCups }
    }

    // Uncapped in `.max` mode, unlike every other tracker's progress
    // — going over a CEILING is a distinct, meaningful state (the
    // home screen's fill turns red for it, see `fillColor`), so
    // capping at 1.0 here would throw away exactly the information
    // that matters. Still capped in `.min` mode: reaching a FLOOR
    // goal caps out at "fully done" same as water/protein always have.
    var coffeeProgress: Double {
        let raw = Double(todayCoffeeTotal) / Double(max(data.coffeeGoal, 1))
        return goalMode(for: .coffee) == .max ? raw : min(1.0, raw)
    }

    func addCoffee(_ amount: Int) {
        guard amount > 0 else { return }
        data.coffeeEntries.append(CoffeeEntry(amountCups: amount))
        persist()
    }

    func setCoffeeGoal(_ goal: Int) {
        data.coffeeGoal = goal
        persist()
    }

    // MARK: - Carbs

    var todayCarbsEntries: [CarbsEntry] {
        let start = Calendar.current.startOfDay(for: .now)
        return data.carbsEntries
            .filter { $0.timestamp >= start }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var todayCarbsTotal: Int {
        todayCarbsEntries.reduce(0) { $0 + $1.amountG }
    }

    // See the comment on `coffeeProgress` — same uncapped-in-`.max`-
    // mode reasoning.
    var carbsProgress: Double {
        let raw = Double(todayCarbsTotal) / Double(max(data.carbsGoalG, 1))
        return goalMode(for: .carbs) == .max ? raw : min(1.0, raw)
    }

    func addCarbs(_ amount: Int) {
        guard amount > 0 else { return }
        data.carbsEntries.append(CarbsEntry(amountG: amount))
        persist()
    }

    func setCarbsGoal(_ goal: Int) {
        data.carbsGoalG = goal
        persist()
    }

    // MARK: - Steps

    var todayStepsEntries: [StepsEntry] {
        let start = Calendar.current.startOfDay(for: .now)
        return data.stepsEntries
            .filter { $0.timestamp >= start }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var todayStepsTotal: Int {
        todayStepsEntries.reduce(0) { $0 + $1.amountSteps }
    }

    var stepsProgress: Double {
        min(1.0, Double(todayStepsTotal) / Double(max(data.stepsGoal, 1)))
    }

    func addSteps(_ amount: Int) {
        guard amount > 0 else { return }
        data.stepsEntries.append(StepsEntry(amountSteps: amount))
        persist()
    }

    func setStepsGoal(_ goal: Int) {
        data.stepsGoal = goal
        persist()
    }

    // MARK: - Movement

    var todayMovementEntries: [MovementEntry] {
        let start = Calendar.current.startOfDay(for: .now)
        return data.movementEntries
            .filter { $0.timestamp >= start }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var todayMovementTotal: Int {
        todayMovementEntries.reduce(0) { $0 + $1.amountMin }
    }

    var movementProgress: Double {
        min(1.0, Double(todayMovementTotal) / Double(max(data.movementGoalMin, 1)))
    }

    func addMovement(_ amount: Int) {
        guard amount > 0 else { return }
        data.movementEntries.append(MovementEntry(amountMin: amount))
        persist()
    }

    func setMovementGoal(_ goal: Int) {
        data.movementGoalMin = goal
        persist()
    }

    // MARK: - Sleep
    //
    // Same shape as every other tracker (entries you add, a goal,
    // progress toward it) even though in practice most people log it
    // once a day rather than adding to it repeatedly — nothing here
    // assumes otherwise, it just doesn't force a different model on
    // it.

    var todaySleepEntries: [SleepEntry] {
        let start = Calendar.current.startOfDay(for: .now)
        return data.sleepEntries
            .filter { $0.timestamp >= start }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var todaySleepTotal: Int {
        todaySleepEntries.reduce(0) { $0 + $1.amountHr }
    }

    var sleepProgress: Double {
        min(1.0, Double(todaySleepTotal) / Double(max(data.sleepGoalHr, 1)))
    }

    func addSleep(_ amount: Int) {
        guard amount > 0 else { return }
        data.sleepEntries.append(SleepEntry(amountHr: amount))
        persist()
    }

    func setSleepGoal(_ goal: Int) {
        data.sleepGoalHr = goal
        persist()
    }

    // MARK: - Cigarettes

    var todayCigarettesEntries: [CigarettesEntry] {
        let start = Calendar.current.startOfDay(for: .now)
        return data.cigarettesEntries
            .filter { $0.timestamp >= start }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var todayCigarettesTotal: Int {
        todayCigarettesEntries.reduce(0) { $0 + $1.amountCigs }
    }

    // See the comment on `coffeeProgress` — same uncapped-in-`.max`-
    // mode reasoning.
    var cigarettesProgress: Double {
        let raw = Double(todayCigarettesTotal) / Double(max(data.cigarettesGoal, 1))
        return goalMode(for: .cigarettes) == .max ? raw : min(1.0, raw)
    }

    func addCigarettes(_ amount: Int) {
        guard amount > 0 else { return }
        data.cigarettesEntries.append(CigarettesEntry(amountCigs: amount))
        persist()
    }

    func setCigarettesGoal(_ goal: Int) {
        data.cigarettesGoal = goal
        persist()
    }

    // MARK: - Goal mode (min/max — coffee, calories, cigarettes only)

    func goalMode(for kind: TrackerKind) -> GoalMode {
        data.goalModes[kind] ?? .min
    }

    func setGoalMode(_ mode: GoalMode, for kind: TrackerKind) {
        guard kind.supportsGoalModeSwitch else { return }
        data.goalModes[kind] = mode
        persist()
    }

    // MARK: - To-do

    var todayTodoCompletions: [TodoCompletion] {
        let start = Calendar.current.startOfDay(for: .now)
        return data.todoCompletions.filter { $0.timestamp >= start }
    }

    /// The live label for a to-do row — plain items just show their
    /// static text; water/protein items show today's goal, rounded to
    /// a friendly unit (water: nearest 0.5L, protein: nearest 25g).
    func todoLabel(for item: TodoItem) -> String {
        switch item.link {
        case .none:
            return item.staticLabel
        case .water:
            let roundedML = (Double(data.goalML) / 500).rounded() * 500
            let liters = roundedML / 1000
            let litersText = liters.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(liters))
                : String(format: "%.1f", liters)
            return "\(litersText)l water"
        case .protein:
            let roundedG = Int((Double(data.proteinGoalG) / 25).rounded() * 25)
            return "\(roundedG)g protein"
        case .coffee:
            return "\(data.coffeeGoal) cups coffee"
        case .carbs:
            let roundedKcal = Int((Double(data.carbsGoalG) / 50).rounded() * 50)
            return "\(roundedKcal)kcal calories"
        case .steps:
            let roundedSteps = Int((Double(data.stepsGoal) / 500).rounded() * 500)
            return "\(roundedSteps) steps"
        case .movement:
            return "\(data.movementGoalMin)min movement"
        case .sleep:
            return "\(data.sleepGoalHr)h sleep"
        case .cigarettes:
            return "\(data.cigarettesGoal) cigarettes"
        }
    }

    /// Water/protein rows strike themselves through automatically
    /// once that tracker's goal is hit today — not manually
    /// toggleable. Plain rows are a stored completion, like before.
    func isTodoItemDone(_ item: TodoItem) -> Bool {
        switch item.link {
        case .none:
            return todayTodoCompletions.contains { $0.task == item.id }
        case .water:
            return progress >= 1.0
        case .protein:
            return proteinProgress >= 1.0
        case .coffee:
            return coffeeProgress >= 1.0
        case .carbs:
            return carbsProgress >= 1.0
        case .steps:
            return stepsProgress >= 1.0
        case .movement:
            return movementProgress >= 1.0
        case .sleep:
            return sleepProgress >= 1.0
        case .cigarettes:
            return cigarettesProgress >= 1.0
        }
    }

    /// No-op for water/protein rows — they're derived, not stored.
    func toggleTodoItem(_ item: TodoItem) {
        guard item.link == .none else { return }
        let start = Calendar.current.startOfDay(for: .now)
        if let index = data.todoCompletions.firstIndex(where: { $0.task == item.id && $0.timestamp >= start }) {
            data.todoCompletions.remove(at: index)
        } else {
            data.todoCompletions.append(TodoCompletion(task: item.id))
        }
        persist()
    }

    var todoCompletedCount: Int {
        todoItems.filter(isTodoItemDone).count
    }

    var todoProgress: Double {
        let total = todoItems.count
        guard total > 0 else { return 0 }
        return min(1.0, Double(todoCompletedCount) / Double(total))
    }

    // MARK: - To-do list editing (settings)
    //
    // All id-based rather than index-based: the editor binds a live
    // TextField per row, and a row above the one being typed into can
    // disappear (emptied, then pruned) while that field still holds
    // focus. An index captured before that happens points at the
    // wrong task afterwards; an id never does.

    /// Renames one task in place. Unknown ids are ignored. Empty is
    /// allowed on purpose — that's just a row mid-edit; `pruneEmptyTodoTasks`
    /// is what actually removes it, once it's no longer being typed into.
    func setTodoTaskName(id: UUID, to name: String) {
        guard let index = data.todoTasks.firstIndex(where: { $0.id == id }) else { return }
        data.todoTasks[index].name = name
        persist()
    }

    /// Adds a blank task and hands back its id so the caller can focus
    /// it. `after` puts it directly below that task (what Return does,
    /// so a chained to-do lands where you're looking); nil appends to
    /// the end (what "+ add to do" does).
    @discardableResult
    func insertBlankTodoTask(after id: UUID? = nil) -> UUID {
        let task = TodoTask(name: "")
        if let id, let index = data.todoTasks.firstIndex(where: { $0.id == id }) {
            data.todoTasks.insert(task, at: index + 1)
        } else {
            data.todoTasks.append(task)
        }
        // No persist() on purpose. A blank row is a piece of UI, not
        // data — it gets pruned again if nothing is typed — and
        // persisting means a full JSON encode plus a queued CloudKit
        // push sitting directly between the tap on "add to do" and the
        // field appearing. The first keystroke persists it anyway.
        return task.id
    }

    func removeTodoTask(id: UUID) {
        data.todoTasks.removeAll { $0.id == id }
        persist()
    }

    /// Drops every task whose name is blank (or just whitespace) —
    /// called when the editor loses focus, so "cleared it out" reads
    /// as "deleted it" without the row vanishing mid-keystroke.
    /// `except` keeps the row that's still being typed into alive.
    func pruneEmptyTodoTasks(except keepID: UUID? = nil) {
        let before = data.todoTasks.count
        data.todoTasks.removeAll {
            $0.id != keepID && $0.name.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard data.todoTasks.count != before else { return }
        persist()
    }

    // MARK: - Trackers on/off

    func isTrackerEnabled(_ kind: TrackerKind) -> Bool {
        !data.disabledTrackers.contains(kind)
    }

    func toggleTracker(_ kind: TrackerKind) {
        if data.disabledTrackers.contains(kind) {
            data.disabledTrackers.remove(kind)
        } else {
            data.disabledTrackers.insert(kind)
        }
        persist()
    }

    // MARK: - Shared

    /// Deletes exactly one logged entry, of any tracker, by id — what
    /// the "all logs" list uses to let you remove a single mis-tap
    /// without wiping the rest of the day (`resetToday()` is
    /// today-only and all-or-nothing; this is one entry, any day).
    /// `.todo`/`.none` are a no-op — to-do completions aren't logged
    /// as a numeric entry the same way and aren't shown in that list.
    func deleteLogEntry(id: UUID, kind: TrackerKind) {
        switch kind {
        case .water:
            guard let entry = data.entries.first(where: { $0.id == id }) else { return }
            data.entries.removeAll { $0.id == id }
            persist()
            Task { await deleteFromCloudKit([entry]) }
        case .protein:
            guard let entry = data.proteinEntries.first(where: { $0.id == id }) else { return }
            data.proteinEntries.removeAll { $0.id == id }
            persist()
            Task { await deleteFromCloudKit([entry]) }
        case .coffee:
            guard let entry = data.coffeeEntries.first(where: { $0.id == id }) else { return }
            data.coffeeEntries.removeAll { $0.id == id }
            persist()
            Task { await deleteFromCloudKit([entry]) }
        case .carbs:
            guard let entry = data.carbsEntries.first(where: { $0.id == id }) else { return }
            data.carbsEntries.removeAll { $0.id == id }
            persist()
            Task { await deleteFromCloudKit([entry]) }
        case .steps:
            guard let entry = data.stepsEntries.first(where: { $0.id == id }) else { return }
            data.stepsEntries.removeAll { $0.id == id }
            persist()
            Task { await deleteFromCloudKit([entry]) }
        case .movement:
            guard let entry = data.movementEntries.first(where: { $0.id == id }) else { return }
            data.movementEntries.removeAll { $0.id == id }
            persist()
            Task { await deleteFromCloudKit([entry]) }
        case .sleep:
            guard let entry = data.sleepEntries.first(where: { $0.id == id }) else { return }
            data.sleepEntries.removeAll { $0.id == id }
            persist()
            Task { await deleteFromCloudKit([entry]) }
        case .cigarettes:
            guard let entry = data.cigarettesEntries.first(where: { $0.id == id }) else { return }
            data.cigarettesEntries.removeAll { $0.id == id }
            persist()
            Task { await deleteFromCloudKit([entry]) }
        case .todo:
            break
        }
    }

    /// Clears today's log so far for water, protein, coffee, carbs,
    /// AND to-do check-offs — previous days stay intact for History.
    /// Deletes the matching CloudKit records too, so it's a real
    /// removal, not just a local one a future sync would undo.
    func resetToday() {
        let start = Calendar.current.startOfDay(for: .now)
        let removedWater = data.entries.filter { $0.timestamp >= start }
        let removedProtein = data.proteinEntries.filter { $0.timestamp >= start }
        let removedCoffee = data.coffeeEntries.filter { $0.timestamp >= start }
        let removedCarbs = data.carbsEntries.filter { $0.timestamp >= start }
        let removedSteps = data.stepsEntries.filter { $0.timestamp >= start }
        let removedMovement = data.movementEntries.filter { $0.timestamp >= start }
        let removedSleep = data.sleepEntries.filter { $0.timestamp >= start }
        let removedCigarettes = data.cigarettesEntries.filter { $0.timestamp >= start }
        let removedTodo = data.todoCompletions.filter { $0.timestamp >= start }

        data.entries.removeAll { $0.timestamp >= start }
        data.proteinEntries.removeAll { $0.timestamp >= start }
        data.coffeeEntries.removeAll { $0.timestamp >= start }
        data.carbsEntries.removeAll { $0.timestamp >= start }
        data.stepsEntries.removeAll { $0.timestamp >= start }
        data.movementEntries.removeAll { $0.timestamp >= start }
        data.sleepEntries.removeAll { $0.timestamp >= start }
        data.cigarettesEntries.removeAll { $0.timestamp >= start }
        data.todoCompletions.removeAll { $0.timestamp >= start }
        persist()

        Task {
            await deleteFromCloudKit(removedWater)
            await deleteFromCloudKit(removedProtein)
            await deleteFromCloudKit(removedCoffee)
            await deleteFromCloudKit(removedCarbs)
            await deleteFromCloudKit(removedSteps)
            await deleteFromCloudKit(removedMovement)
            await deleteFromCloudKit(removedSleep)
            await deleteFromCloudKit(removedCigarettes)
            await deleteFromCloudKit(removedTodo)
        }
    }

    #if DEBUG
    /// Wipes EVERY water/protein/coffee/carbs/steps/movement/sleep/
    /// cigarettes/to-do entry ever logged — real history included,
    /// not just today and not just seeded demo data — so today
    /// becomes a genuine day one. Goals and custom to-do slot names
    /// are settings, not history, and are left alone. Deletes the
    /// CloudKit copies too. Debug-only and irreversible — never
    /// compiled into a release build, and there's no confirmation
    /// dialog here (the caller adds one), so only wire this up
    /// somewhere you won't tap by accident.
    func clearAllHistory() {
        let removedWater = data.entries
        let removedProtein = data.proteinEntries
        let removedCoffee = data.coffeeEntries
        let removedCarbs = data.carbsEntries
        let removedSteps = data.stepsEntries
        let removedMovement = data.movementEntries
        let removedSleep = data.sleepEntries
        let removedCigarettes = data.cigarettesEntries
        let removedTodo = data.todoCompletions

        data.entries = []
        data.proteinEntries = []
        data.coffeeEntries = []
        data.carbsEntries = []
        data.stepsEntries = []
        data.movementEntries = []
        data.sleepEntries = []
        data.cigarettesEntries = []
        data.todoCompletions = []
        data.lastModified = .now
        saveLocally()

        Task {
            await deleteFromCloudKit(removedWater)
            await deleteFromCloudKit(removedProtein)
            await deleteFromCloudKit(removedCoffee)
            await deleteFromCloudKit(removedCarbs)
            await deleteFromCloudKit(removedSteps)
            await deleteFromCloudKit(removedMovement)
            await deleteFromCloudKit(removedSleep)
            await deleteFromCloudKit(removedCigarettes)
            await deleteFromCloudKit(removedTodo)
        }
    }
    #endif

    struct DailyTotal: Identifiable {
        let date: Date
        let totalML: Int
        let totalG: Int
        let todoCompleted: Int
        let todoTotal: Int
        var id: Date { date }
    }

    /// One combined row per calendar day that has at least one water,
    /// protein, or to-do entry, newest first. The water/protein
    /// to-do rows aren't stored per day (they're derived live), so
    /// for past days they're judged against TODAY'S goal — if you
    /// changed your goal since, older days re-evaluate against the
    /// new number rather than whatever it was back then.
    var dailyTotals: [DailyTotal] {
        let cal = Calendar.current
        let waterByDay = Dictionary(grouping: data.entries) { cal.startOfDay(for: $0.timestamp) }
            .mapValues { $0.reduce(0) { $0 + $1.amountML } }
        let proteinByDay = Dictionary(grouping: data.proteinEntries) { cal.startOfDay(for: $0.timestamp) }
            .mapValues { $0.reduce(0) { $0 + $1.amountG } }
        let coffeeByDay = Dictionary(grouping: data.coffeeEntries) { cal.startOfDay(for: $0.timestamp) }
            .mapValues { $0.reduce(0) { $0 + $1.amountCups } }
        let carbsByDay = Dictionary(grouping: data.carbsEntries) { cal.startOfDay(for: $0.timestamp) }
            .mapValues { $0.reduce(0) { $0 + $1.amountG } }
        let stepsByDay = Dictionary(grouping: data.stepsEntries) { cal.startOfDay(for: $0.timestamp) }
            .mapValues { $0.reduce(0) { $0 + $1.amountSteps } }
        let movementByDay = Dictionary(grouping: data.movementEntries) { cal.startOfDay(for: $0.timestamp) }
            .mapValues { $0.reduce(0) { $0 + $1.amountMin } }
        let sleepByDay = Dictionary(grouping: data.sleepEntries) { cal.startOfDay(for: $0.timestamp) }
            .mapValues { $0.reduce(0) { $0 + $1.amountHr } }
        let cigarettesByDay = Dictionary(grouping: data.cigarettesEntries) { cal.startOfDay(for: $0.timestamp) }
            .mapValues { $0.reduce(0) { $0 + $1.amountCigs } }
        let todoByDay = Dictionary(grouping: data.todoCompletions) { cal.startOfDay(for: $0.timestamp) }
            .mapValues { Set($0.map(\.task)).count }
        let days = Set(waterByDay.keys).union(proteinByDay.keys).union(coffeeByDay.keys).union(carbsByDay.keys)
            .union(stepsByDay.keys).union(movementByDay.keys).union(sleepByDay.keys).union(cigarettesByDay.keys).union(todoByDay.keys)
        return days
            .map { day -> DailyTotal in
                let waterTotal = waterByDay[day] ?? 0
                let proteinTotal = proteinByDay[day] ?? 0
                let coffeeTotal = coffeeByDay[day] ?? 0
                let carbsTotal = carbsByDay[day] ?? 0
                let stepsTotal = stepsByDay[day] ?? 0
                let movementTotal = movementByDay[day] ?? 0
                let sleepTotal = sleepByDay[day] ?? 0
                let cigarettesTotal = cigarettesByDay[day] ?? 0
                var completed = todoByDay[day] ?? 0
                if waterTotal >= data.goalML { completed += 1 }
                if proteinTotal >= data.proteinGoalG { completed += 1 }
                if coffeeTotal >= data.coffeeGoal { completed += 1 }
                if carbsTotal >= data.carbsGoalG { completed += 1 }
                if stepsTotal >= data.stepsGoal { completed += 1 }
                if movementTotal >= data.movementGoalMin { completed += 1 }
                if sleepTotal >= data.sleepGoalHr { completed += 1 }
                if cigarettesTotal >= data.cigarettesGoal { completed += 1 }
                return DailyTotal(
                    date: day,
                    totalML: waterTotal,
                    totalG: proteinTotal,
                    todoCompleted: completed,
                    todoTotal: todoItems.count
                )
            }
            .sorted { $0.date > $1.date }
    }

    // MARK: - History (streak & day grid)

    struct DayResult: Identifiable, Hashable {
        let date: Date
        /// Any water/protein/to-do activity logged that day at all —
        /// distinct from `succeeded`, so History can tell "never
        /// opened the app" apart from "opened it, didn't finish".
        let touched: Bool
        let succeeded: Bool
        var id: Date { date }
    }

    /// Every calendar day from the earliest recorded entry (any
    /// water/protein/to-do log) through today, oldest first, each
    /// marked whether that day's to-do checklist was fully completed
    /// — the ONLY thing that counts as "success" here, water/protein
    /// don't factor in on their own. A day with nothing logged at all
    /// counts as not-succeeded (not "unknown"), so a skipped day
    /// correctly breaks the streak. Today counts the moment its
    /// checklist is fully done — no waiting for the day to end.
    var dailyResults: [DayResult] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let totalsByDay = Dictionary(uniqueKeysWithValues: dailyTotals.map { (cal.startOfDay(for: $0.date), $0) })

        let allTimestamps = data.entries.map(\.timestamp)
            + data.proteinEntries.map(\.timestamp)
            + data.coffeeEntries.map(\.timestamp)
            + data.carbsEntries.map(\.timestamp)
            + data.stepsEntries.map(\.timestamp)
            + data.movementEntries.map(\.timestamp)
            + data.sleepEntries.map(\.timestamp)
            + data.cigarettesEntries.map(\.timestamp)
            + data.todoCompletions.map(\.timestamp)
        let earliest = allTimestamps.map { cal.startOfDay(for: $0) }.min() ?? today

        var results: [DayResult] = []
        var day = earliest
        while true {
            let total = totalsByDay[day]
            let touched = total != nil
            // `&& touched` guards the edge case of zero to-do items
            // existing at all (every tracker disabled) — todoCompleted
            // (0) >= todoItems.count (0) would otherwise read as
            // "succeeded" even on a day nothing was logged.
            let succeeded = touched && (total?.todoCompleted ?? 0) >= todoItems.count
            results.append(DayResult(date: day, touched: touched, succeeded: succeeded))
            if day >= today { break }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return results
    }

    /// Consecutive successful days counting back from today. Today
    /// itself only ADDS to the streak if it has already succeeded —
    /// it never BREAKS one just for being unfinished, since the day
    /// isn't over yet. Any past day (yesterday and earlier) that
    /// didn't succeed still ends the streak as normal.
    var currentStreak: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var streak = 0
        for result in dailyResults.reversed() {
            if cal.isDate(result.date, inSameDayAs: today) {
                if result.succeeded { streak += 1 }
                continue
            }
            guard result.succeeded else { break }
            streak += 1
        }
        return streak
    }

    /// All-time count of fully-successful days.
    var totalSuccessfulDays: Int {
        dailyResults.filter(\.succeeded).count
    }

    /// The best `currentStreak` ever reached — the "rec(ord)" shown
    /// next to today's streak in History, so a broken streak still
    /// leaves something to beat rather than just resetting to 0.
    ///
    /// Counts the longest run of consecutive succeeded days anywhere
    /// in the history, today's still-running streak included (a
    /// record you're in the middle of setting is still the record).
    var longestStreak: Int {
        var best = 0
        var run = 0
        for result in dailyResults {
            if result.succeeded {
                run += 1
                best = max(best, run)
            } else {
                run = 0
            }
        }
        return best
    }

    /// All-time count of days the app was actually used at all —
    /// ANY water/protein/to-do activity logged, not just fully
    /// successful ones. Unlike `dailyResults.count` (every CALENDAR
    /// day since the first entry, gaps included), this only counts
    /// days something was genuinely measured — the denominator for
    /// the "4 streak / of 32" summary.
    var totalTrackedDays: Int {
        dailyResults.filter(\.touched).count
    }

    /// Consecutive WEEKS (Monday...Sunday) with at least one touched
    /// day, counting back from the current week — much looser than
    /// `currentStreak` (a full 100% DAY): a week only needs ONE
    /// touched day, any day, to keep this alive. Same "doesn't wait
    /// for it to be over" rule as the day streak — the current week
    /// counts the moment it has its first touch, not just once it's
    /// finished.
    var weekStreak: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        func weekStart(of date: Date) -> Date {
            let mondayIndex = (cal.component(.weekday, from: date) + 5) % 7
            return cal.date(byAdding: .day, value: -mondayIndex, to: date) ?? date
        }

        let touchedDays = Set(dailyResults.filter(\.touched).map { cal.startOfDay(for: $0.date) })
        guard !touchedDays.isEmpty else { return 0 }

        var streak = 0
        var cursor = weekStart(of: today)
        while true {
            let weekHasTouch = (0..<7).contains { offset in
                guard let day = cal.date(byAdding: .day, value: offset, to: cursor) else { return false }
                return touchedDays.contains(day)
            }
            guard weekHasTouch else { break }
            streak += 1
            guard let previousWeek = cal.date(byAdding: .day, value: -7, to: cursor) else { break }
            cursor = previousWeek
        }
        return streak
    }

    #if DEBUG
    private enum DemoDayState { case none, partial, full }

    /// Debug-only: backfills 140 days (20 weeks) of fake history so
    /// the History grid overflows a real screen by a wide margin and
    /// genuinely scrolls — a mix of fully-done, partial-touch, and
    /// no-touch days so the grey/navy/milestone marks all show up,
    /// PLUS two deliberate clean runs (see `reserveRun` below) long
    /// enough to actually reach the 10-day and 35-day milestone tiers,
    /// which the mixed pattern alone never runs long enough to hit.
    /// `.full` completes every plain to-do item and clears both goals;
    /// `.partial` logs a bit of water — touched, but deliberately
    /// short of 100%; `.none` logs nothing. Clears any previously
    /// seeded data first, so tapping it twice doesn't stack duplicate
    /// entries on the same days. Never compiled into a release build,
    /// so it can't touch real user data outside of testing.
    func seedDemoHistory() {
        // Idempotent: wipe whatever a previous tap left behind before
        // writing a fresh set.
        let previouslySeeded = clearDemoEntries()

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        func mark(daysAgo: Int, state: DemoDayState) {
            guard daysAgo > 0, let day = cal.date(byAdding: .day, value: -daysAgo, to: today) else { return }
            let atNoon = cal.date(byAdding: .hour, value: 12, to: day) ?? day
            switch state {
            case .none:
                return
            case .partial:
                data.entries.append(WaterEntry(amountML: max(1, data.goalML / 4), timestamp: atNoon))
            case .full:
                for item in todoItems where item.link == .none {
                    data.todoCompletions.append(TodoCompletion(task: item.id, timestamp: atNoon))
                }
                data.entries.append(WaterEntry(amountML: data.goalML, timestamp: atNoon))
                data.proteinEntries.append(ProteinEntry(amountG: data.proteinGoalG, timestamp: atNoon))
                data.coffeeEntries.append(CoffeeEntry(amountCups: data.coffeeGoal, timestamp: atNoon))
                data.carbsEntries.append(CarbsEntry(amountG: data.carbsGoalG, timestamp: atNoon))
                data.stepsEntries.append(StepsEntry(amountSteps: data.stepsGoal, timestamp: atNoon))
                data.movementEntries.append(MovementEntry(amountMin: data.movementGoalMin, timestamp: atNoon))
                data.sleepEntries.append(SleepEntry(amountHr: data.sleepGoalHr, timestamp: atNoon))
                data.cigarettesEntries.append(CigarettesEntry(amountCigs: data.cigarettesGoal, timestamp: atNoon))
            }
        }

        // A 20-day pattern, repeated back through 140 days (20 weeks).
        // Repeating rather than writing 140 literal entries still
        // gives every week a realistic full/partial/none mix, and 20
        // vs 7 means the pattern doesn't line up with week boundaries
        // (so weeks don't all look identical).
        let pattern: [DemoDayState] = [
            .full, .full, .full, .partial, .full, .none, .full,
            .full, .partial, .full, .full, .none, .partial, .full,
            .full, .full, .partial, .none, .full, .full
        ]

        // Two DELIBERATE clean runs, long enough to actually hit
        // History's green (10-day) and purple (35-day) milestone
        // tiers — the repeating pattern above never runs `.full` more
        // than 2-3 days straight, so without this, seeded data alone
        // could never show them. `.partial` on the day right before
        // and after each run overrides whatever the pattern would
        // have put there, so the run's length is exactly 10 (or
        // exactly 35), not accidentally longer by bleeding into an
        // adjacent `.full` day from the pattern.
        var overrides: [Int: DemoDayState] = [:]
        // `nearDaysAgo` is the run's edge CLOSER to today (the smaller
        // `daysAgo`) — the run then reaches further into the past from
        // there, so `nearDaysAgo...(nearDaysAgo + length - 1)` are the
        // `.full` days, with one `.partial` bookend just outside each
        // end to guarantee the run is exactly `length` long.
        func reserveRun(length: Int, nearDaysAgo: Int) {
            let farDaysAgo = nearDaysAgo + length - 1
            overrides[nearDaysAgo - 1] = .partial
            overrides[farDaysAgo + 1] = .partial
            for daysAgo in nearDaysAgo...farDaysAgo { overrides[daysAgo] = .full }
        }
        reserveRun(length: 10, nearDaysAgo: 15)   // days 15...24 ago
        reserveRun(length: 35, nearDaysAgo: 40)   // days 40...74 ago

        for daysAgo in 1...140 {
            let state = overrides[daysAgo] ?? pattern[(daysAgo - 1) % pattern.count]
            mark(daysAgo: daysAgo, state: state)
        }

        data.lastModified = .now
        saveLocally()
        Task {
            await deleteFromCloudKit(previouslySeeded.water)
            await deleteFromCloudKit(previouslySeeded.protein)
            await deleteFromCloudKit(previouslySeeded.coffee)
            await deleteFromCloudKit(previouslySeeded.carbs)
            await deleteFromCloudKit(previouslySeeded.steps)
            await deleteFromCloudKit(previouslySeeded.movement)
            await deleteFromCloudKit(previouslySeeded.sleep)
            await deleteFromCloudKit(previouslySeeded.cigarettes)
            await deleteFromCloudKit(previouslySeeded.todo)
            await pushToCloudKit()
        }
    }

    private struct DemoEntries {
        let water: [WaterEntry]
        let protein: [ProteinEntry]
        let coffee: [CoffeeEntry]
        let carbs: [CarbsEntry]
        let steps: [StepsEntry]
        let movement: [MovementEntry]
        let sleep: [SleepEntry]
        let cigarettes: [CigarettesEntry]
        let todo: [TodoCompletion]
    }

    /// Drops (and returns) exactly what `seedDemoHistory()` writes and
    /// nothing else: every entry timestamped at noon on the dot, which
    /// is how the seed marks each fake day and something a real
    /// tap-logged entry (timestamped to the second you actually
    /// tapped) will essentially never land on by coincidence. Only
    /// mutates `data` — callers decide when to save/sync.
    @discardableResult
    private func clearDemoEntries() -> DemoEntries {
        let cal = Calendar.current
        // Just hour+minute, not also an exact second==0 — a whole-
        // minute match is still practically impossible to hit by
        // real-world coincidence, and it can't be defeated by any
        // sub-second drift calendar math might introduce.
        func isDemoTimestamp(_ date: Date) -> Bool {
            let comps = cal.dateComponents([.hour, .minute], from: date)
            return comps.hour == 12 && comps.minute == 0
        }
        let removed = DemoEntries(
            water: data.entries.filter { isDemoTimestamp($0.timestamp) },
            protein: data.proteinEntries.filter { isDemoTimestamp($0.timestamp) },
            coffee: data.coffeeEntries.filter { isDemoTimestamp($0.timestamp) },
            carbs: data.carbsEntries.filter { isDemoTimestamp($0.timestamp) },
            steps: data.stepsEntries.filter { isDemoTimestamp($0.timestamp) },
            movement: data.movementEntries.filter { isDemoTimestamp($0.timestamp) },
            sleep: data.sleepEntries.filter { isDemoTimestamp($0.timestamp) },
            cigarettes: data.cigarettesEntries.filter { isDemoTimestamp($0.timestamp) },
            todo: data.todoCompletions.filter { isDemoTimestamp($0.timestamp) }
        )
        data.entries.removeAll { isDemoTimestamp($0.timestamp) }
        data.proteinEntries.removeAll { isDemoTimestamp($0.timestamp) }
        data.coffeeEntries.removeAll { isDemoTimestamp($0.timestamp) }
        data.carbsEntries.removeAll { isDemoTimestamp($0.timestamp) }
        data.stepsEntries.removeAll { isDemoTimestamp($0.timestamp) }
        data.movementEntries.removeAll { isDemoTimestamp($0.timestamp) }
        data.sleepEntries.removeAll { isDemoTimestamp($0.timestamp) }
        data.cigarettesEntries.removeAll { isDemoTimestamp($0.timestamp) }
        data.todoCompletions.removeAll { isDemoTimestamp($0.timestamp) }
        return removed
    }

    /// Removes seeded demo data, leaving today's and every other real
    /// entry untouched.
    func removeDemoHistory() {
        let removed = clearDemoEntries()
        data.lastModified = .now
        saveLocally()
        Task {
            await deleteFromCloudKit(removed.water)
            await deleteFromCloudKit(removed.protein)
            await deleteFromCloudKit(removed.coffee)
            await deleteFromCloudKit(removed.carbs)
            await deleteFromCloudKit(removed.steps)
            await deleteFromCloudKit(removed.movement)
            await deleteFromCloudKit(removed.sleep)
            await deleteFromCloudKit(removed.cigarettes)
            await deleteFromCloudKit(removed.todo)
        }
    }
    #endif

    /// Local save is immediate; the CloudKit push is coalesced. Every
    /// live-bound TextField in settings (goals, and now each to-do
    /// name) calls persist() on EVERY keystroke — one network round
    /// trip per character was both wasteful and enough to make typing
    /// feel sticky. Whatever the last edit within the window is, is
    /// what gets pushed; nothing is lost, since the local copy is
    /// already written and the push always sends current state.
    private func persist() {
        data.lastModified = .now
        saveLocally()
        schedulePush()
    }

    /// Non-nil while an edit is settling — also read by `tick()` as a
    /// stand-in for "the user is busy right now".
    private(set) var pendingPush: Task<Void, Never>?

    private func schedulePush() {
        pendingPush?.cancel()
        pendingPush = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.pushToCloudKit()
            self?.pendingPush = nil
        }
    }

    private func saveLocally() {
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    // MARK: - Cross-device sync (CloudKit)
    //
    // Private database, one CKRecord per log entry — see the
    // CKMappable extensions above for why that makes syncing close
    // to free: two devices logging different entries just create
    // different records (nothing to merge), and a real CKRecord
    // delete is a real deletion, no `lastResetAt`-style cutoff hack
    // needed to keep a reset from quietly reappearing. Scalar
    // settings (goals, disabled trackers, custom to-do names) live in
    // one fixed "AppSettings" record, last-write-wins via
    // `lastModified` — same rule the old file-based version used.
    //
    // No push notifications/subscriptions here (that needs its own
    // entitlement + background modes) — sync is polling-based, same
    // cadence as before: every local change pushes immediately
    // (fire-and-forget), and the periodic tick + foreground pulls in
    // whatever showed up from elsewhere.

    // This class is @MainActor, so anything it does directly runs on
    // the main thread — including, before this, building a CKRecord per
    // entry on every push and mapping every fetched record back on
    // every pull. With a few hundred entries that's real work landing
    // between keystrokes. The `remote*` helpers below are `nonisolated`
    // so that work happens off the main actor; only the results, which
    // are plain Sendable structs, come back to it.
    //
    // CKRecord/CKRecord.ID/CKDatabase deliberately never cross that
    // boundary (CKRecord is a mutable class and not Sendable) — each
    // helper makes its own database handle and does its own mapping,
    // start to finish.
    private let ckContainer = CKContainer.default()

    enum CloudSyncStatus: Equatable {
        case unknown, available, noAccount, restricted, error
    }
    @Published private(set) var cloudSyncStatus: CloudSyncStatus = .unknown

    private func refreshCloudKitAccountStatus() {
        Task {
            let status = (try? await ckContainer.accountStatus()) ?? .couldNotDetermine
            switch status {
            case .available: cloudSyncStatus = .available
            case .noAccount: cloudSyncStatus = .noAccount
            case .restricted, .temporarilyUnavailable: cloudSyncStatus = .restricted
            default: cloudSyncStatus = .error
            }
        }
    }

    /// Saves every local record — idempotent, since each record's ID
    /// is its entry's own UUID, so re-saving unchanged data just
    /// overwrites in place. Simpler and safer than tracking exactly
    /// which records are "new" for a personal-scale amount of data.
    private func pushToCloudKit() async {
        // Only cheap value reads happen on the main actor here; every
        // record gets built inside the nonisolated helpers.
        let entries = data.entries
        let proteinEntries = data.proteinEntries
        let coffeeEntries = data.coffeeEntries
        let carbsEntries = data.carbsEntries
        let stepsEntries = data.stepsEntries
        let movementEntries = data.movementEntries
        let sleepEntries = data.sleepEntries
        let cigarettesEntries = data.cigarettesEntries
        let todoCompletions = data.todoCompletions
        let payload = SettingsPayload(
            goalML: data.goalML,
            proteinGoalG: data.proteinGoalG,
            coffeeGoal: data.coffeeGoal,
            carbsGoalG: data.carbsGoalG,
            stepsGoal: data.stepsGoal,
            movementGoalMin: data.movementGoalMin,
            sleepGoalHr: data.sleepGoalHr,
            cigarettesGoal: data.cigarettesGoal,
            todoNames: data.todoTasks.map(\.name),
            disabledTrackerRawValues: data.disabledTrackers.map(\.rawValue),
            goalModeRawValues: Dictionary(uniqueKeysWithValues: data.goalModes.map { ($0.key.rawValue, $0.value.rawValue) }),
            lastModified: data.lastModified
        )

        await Self.remoteSave(entries)
        await Self.remoteSave(proteinEntries)
        await Self.remoteSave(coffeeEntries)
        await Self.remoteSave(carbsEntries)
        await Self.remoteSave(stepsEntries)
        await Self.remoteSave(movementEntries)
        await Self.remoteSave(sleepEntries)
        await Self.remoteSave(cigarettesEntries)
        await Self.remoteSave(todoCompletions)
        await Self.remoteSaveSettings(payload)
    }

    /// Thin main-actor forwarder, kept so the twenty-odd call sites
    /// elsewhere read the same as before; the work is off-actor.
    private func deleteFromCloudKit<T: CKMappable & Sendable>(_ items: [T]) async {
        await Self.remoteDelete(items)
    }

    private nonisolated static func remoteSave<T: CKMappable & Sendable>(_ items: [T]) async {
        guard !items.isEmpty else { return }
        let records = items.map { $0.ckRecord() }
        _ = try? await ckSyncDatabase.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)
    }

    private nonisolated static func remoteDelete<T: CKMappable & Sendable>(_ items: [T]) async {
        guard !items.isEmpty else { return }
        let recordIDs = items.map { $0.ckRecord().recordID }
        _ = try? await ckSyncDatabase.modifyRecords(saving: [], deleting: recordIDs)
    }

    /// Every record of one type, mapped straight to `T` — paging
    /// through as many `CKQueryOperation.Cursor`s as it takes. Mapping
    /// happens in here rather than at the call site precisely so no
    /// CKRecord has to travel back to the main actor.
    private nonisolated static func remoteFetch<T: CKMappable & Sendable>(_ type: T.Type) async -> [T] {
        var results: [T] = []
        let query = CKQuery(recordType: T.ckRecordType, predicate: NSPredicate(value: true))
        do {
            let first = try await ckSyncDatabase.records(matching: query)
            var cursor = first.queryCursor
            results.append(contentsOf: first.matchResults.compactMap { try? $0.1.get() }.compactMap(T.init(record:)))
            while let c = cursor {
                let next = try await ckSyncDatabase.records(continuingMatchFrom: c)
                results.append(contentsOf: next.matchResults.compactMap { try? $0.1.get() }.compactMap(T.init(record:)))
                cursor = next.queryCursor
            }
        } catch {
            // Offline or not-yet-available — local cache stays
            // authoritative until the next successful pull.
        }
        return results
    }

    private nonisolated static func remoteSaveSettings(_ payload: SettingsPayload) async {
        let record = CKRecord(
            recordType: "Settings",
            recordID: CKRecord.ID(recordName: ckSettingsRecordName)
        )
        record["goalML"] = payload.goalML
        record["proteinGoalG"] = payload.proteinGoalG
        record["coffeeGoal"] = payload.coffeeGoal
        record["carbsGoalG"] = payload.carbsGoalG
        record["stepsGoal"] = payload.stepsGoal
        record["movementGoalMin"] = payload.movementGoalMin
        record["sleepGoalHr"] = payload.sleepGoalHr
        record["cigarettesGoal"] = payload.cigarettesGoal
        // Field name stays "todoTaskSlots" even though the property is
        // `todoTasks` now — renaming it would mean a CloudKit schema
        // change (and a mismatch with any device still on the old
        // build) for zero benefit. Names only: the local UUIDs exist
        // purely for focus identity in the editor, nothing remote
        // needs them.
        record["todoTaskSlots"] = payload.todoNames
        record["disabledTrackers"] = payload.disabledTrackerRawValues
        // Stored as parallel arrays — CKRecord fields can't hold a
        // dictionary directly, only CloudKit's own storable types
        // (strings, arrays of strings, etc).
        record["goalModeKeys"] = Array(payload.goalModeRawValues.keys)
        record["goalModeValues"] = Array(payload.goalModeRawValues.values)
        record["lastModified"] = payload.lastModified
        _ = try? await ckSyncDatabase.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
    }

    private nonisolated static func remoteFetchSettings() async -> RemoteSettings? {
        guard let record = try? await ckSyncDatabase.record(
            for: CKRecord.ID(recordName: ckSettingsRecordName)
        ) else { return nil }
        let goalModeKeys = record["goalModeKeys"] as? [String]
        let goalModeValues = record["goalModeValues"] as? [String]
        var goalModeRawValues: [String: String]?
        if let goalModeKeys, let goalModeValues, goalModeKeys.count == goalModeValues.count {
            goalModeRawValues = Dictionary(uniqueKeysWithValues: zip(goalModeKeys, goalModeValues))
        }
        return RemoteSettings(
            goalML: record["goalML"] as? Int,
            proteinGoalG: record["proteinGoalG"] as? Int,
            coffeeGoal: record["coffeeGoal"] as? Int,
            carbsGoalG: record["carbsGoalG"] as? Int,
            stepsGoal: record["stepsGoal"] as? Int,
            movementGoalMin: record["movementGoalMin"] as? Int,
            sleepGoalHr: record["sleepGoalHr"] as? Int,
            cigarettesGoal: record["cigarettesGoal"] as? Int,
            todoNames: record["todoTaskSlots"] as? [String],
            disabledTrackerRawValues: record["disabledTrackers"] as? [String],
            goalModeRawValues: goalModeRawValues,
            lastModified: record["lastModified"] as? Date
        )
    }

    /// Union by id — new local records are already reflected in
    /// `local` (pushToCloudKit already sent them), new remote ones
    /// get pulled in here.
    private func merged<T: Identifiable>(local: [T], remote: [T]) -> [T] where T.ID == UUID {
        var byID: [UUID: T] = [:]
        for item in local { byID[item.id] = item }
        for item in remote { byID[item.id] = item }
        return Array(byID.values)
    }

    private func pullFromCloudKit() async {
        // Fetch AND map off the main actor — what comes back is
        // already our own model types, not CKRecords.
        async let water = Self.remoteFetch(WaterEntry.self)
        async let protein = Self.remoteFetch(ProteinEntry.self)
        async let coffee = Self.remoteFetch(CoffeeEntry.self)
        async let carbs = Self.remoteFetch(CarbsEntry.self)
        async let steps = Self.remoteFetch(StepsEntry.self)
        async let movement = Self.remoteFetch(MovementEntry.self)
        async let sleep = Self.remoteFetch(SleepEntry.self)
        async let cigarettes = Self.remoteFetch(CigarettesEntry.self)
        async let todos = Self.remoteFetch(TodoCompletion.self)
        async let settings = Self.remoteFetchSettings()
        let (w, p, c, cb, st, mv, sl, cg, t, s) = await (water, protein, coffee, carbs, steps, movement, sleep, cigarettes, todos, settings)

        data.entries = merged(local: data.entries, remote: w)
        data.proteinEntries = merged(local: data.proteinEntries, remote: p)
        data.coffeeEntries = merged(local: data.coffeeEntries, remote: c)
        data.carbsEntries = merged(local: data.carbsEntries, remote: cb)
        data.stepsEntries = merged(local: data.stepsEntries, remote: st)
        data.movementEntries = merged(local: data.movementEntries, remote: mv)
        data.sleepEntries = merged(local: data.sleepEntries, remote: sl)
        data.cigarettesEntries = merged(local: data.cigarettesEntries, remote: cg)
        data.todoCompletions = merged(local: data.todoCompletions, remote: t)

        if let s, let remoteModified = s.lastModified, remoteModified > data.lastModified {
            if let v = s.goalML { data.goalML = v }
            if let v = s.proteinGoalG { data.proteinGoalG = v }
            if let v = s.coffeeGoal { data.coffeeGoal = v }
            if let v = s.carbsGoalG { data.carbsGoalG = v }
            if let v = s.stepsGoal { data.stepsGoal = v }
            if let v = s.movementGoalMin { data.movementGoalMin = v }
            if let v = s.sleepGoalHr { data.sleepGoalHr = v }
            if let v = s.cigarettesGoal { data.cigarettesGoal = v }
            if let rawValues = s.goalModeRawValues {
                data.goalModes = Dictionary(uniqueKeysWithValues: rawValues.compactMap { key, value -> (TrackerKind, GoalMode)? in
                    guard let kind = TrackerKind(rawValue: key), let mode = GoalMode(rawValue: value) else { return nil }
                    return (kind, mode)
                })
            }
            // Keep the local id for any name that's still in the list
            // — otherwise every pull would hand the editor brand-new
            // identities and yank focus out of whatever's being typed.
            if let names = s.todoNames {
                var reusableIDs = data.todoTasks.reduce(into: [String: UUID]()) { acc, task in
                    if acc[task.name] == nil { acc[task.name] = task.id }
                }
                data.todoTasks = names.map { name in
                    let id = reusableIDs.removeValue(forKey: name) ?? UUID()
                    return TodoTask(id: id, name: name)
                }
            }
            if let v = s.disabledTrackerRawValues {
                data.disabledTrackers = Set(v.compactMap(TrackerKind.init(rawValue:)))
            }
            data.lastModified = remoteModified
        }

        saveLocally()
    }

    /// Periodic/foreground "tick" — always nudges SwiftUI to
    /// re-evaluate today's totals (the only way a midnight rollover
    /// shows up without some other change forcing a redraw), and
    /// pulls in whatever's new from CloudKit.
    func tick() {
        objectWillChange.send()
        guard cloudSyncStatus == .available else { return }
        // Skip the pull while an edit is still settling. A pull maps
        // every fetched record and merges the lot, and this class is
        // @MainActor, so that work lands on the main thread — kicking
        // it off mid-typing is a way to make the keyboard feel stuck.
        // It'll run on one of the next ticks instead.
        guard pendingPush == nil else { return }
        Task { await pullFromCloudKit() }
    }
}
