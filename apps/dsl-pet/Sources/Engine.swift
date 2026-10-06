import Foundation

struct Animation: Codable {
    let name: String
    let key: String
    let frame_size: [Int]
    let frame_count: Int
    let playback_frame_order: [Int]
    let durations_ms: [Int]
}
struct PetEvent: Codable {
    let id: String
    let event: String
    var kind: String? = nil
    var action: String? = nil
    var title: String? = nil
    var message: String? = nil
    var thread_id: String? = nil
    var notice_kind: String? = nil
    var notice_id: String? = nil
    var show_bubble: Bool? = nil
}
struct PetSnapshot: Codable {
    var mode: String
    var action: String
    var frame: Int
    var holding: Bool
    var paused: Bool
    var corrected: Bool
    var lastEvent: String
    var eventID: String
}
final class PetEngine {
    let animations: [String: Animation]
    var mode = "idle", action = "idle", frame = 0
    var holding = false, paused = false, corrected = false
    var lastEvent = "startup", eventID = ""
    var remaining = 0.0
    var after = "idle"
    var workingKind = "thinking"
    var queuedInteraction = false
    var pendingCompletion = false
    var idleTotal = 0.0
    var idleElapsed = 0.0, idleThreshold = 60.0
    var idleTriggerCount = 0
    var idlePass = 0
    var terminalPause = false
    let loopGap = 1.0
    let idleSlowFactor = 1.5
    let idleRepetitions = 3
    var nextIdleInterval: Double { idleThreshold * Double(idleTriggerCount + 1) }
    var frameSpeed: Double { mode == "idle-action" ? idleSlowFactor : 1.0 }
    var apologyHold = 2.0
    var previous: [String: String] = [:]
    var cooldowns: [String: Double] = [:]
    var clock = 0.0
    var chooseNumber: (Int) -> Int = { Int.random(in: 0..<$0) }
    var changed: (() -> Void)?
    var log: ((String) -> Void)?
    init(_ animations: [Animation]) { self.animations = Dictionary(uniqueKeysWithValues: animations.map { ($0.key, $0) }) }
    var snapshot: PetSnapshot { PetSnapshot(mode: mode, action: action, frame: frame, holding: holding, paused: paused, corrected: corrected, lastEvent: lastEvent, eventID: eventID) }
    func pick(_ pool: [(String, Int)], category: String) -> String {
        let ready = pool.filter { ($0.0 != previous[category] || pool.count == 1 || category == "complete") && (cooldowns[$0.0] ?? 0) <= clock }
        let candidates = ready.isEmpty ? pool.filter { $0.0 != previous[category] || pool.count == 1 || category == "complete" } : ready
        let choices = candidates.isEmpty ? pool : candidates
        var ticket = chooseNumber(choices.reduce(0) { $0 + $1.1 })
        for (key, weight) in choices { ticket -= weight; if ticket < 0 { previous[category] = key; cooldowns[key] = clock + 12; return key } }
        return choices[0].0
    }
    func play(_ key: String, mode: String, after: String) {
        self.mode = mode; self.action = key; self.after = after
        frame = 0; holding = false; terminalPause = false; remaining = Double(animations[key]?.durations_ms.first ?? 250) / 1000 * frameSpeed
        idleElapsed = 0
        log?("play \(key) mode=\(mode) after=\(after)"); changed?()
    }
    func rest() { mode = "idle"; action = "idle"; frame = 0; holding = false; terminalPause = false; remaining = 0; idleElapsed = 0; changed?() }
    func finishTask() {
        if corrected { corrected = false; play("16-revise",mode:"completed",after:"hold") }
        else { play(pick([("15-result",70),("01-proud",30)],category:"complete"),mode:"completed",after:"hold") }
    }
    func work() { let key = workingKind == "research" ? "13-research" : (workingKind == "mixed" ? pick([("12-think",65),("13-research",35)],category:"work") : "12-think"); play(key,mode:"working",after:pendingCompletion ? "finishTask" : "work") }
    func interaction() {
        let key = pick([("01-proud",25),("08-spin",15),("19-peek",25),("05-rice",25),("07-idea",8),("10-speechless",2)],category:"interaction")
        play(key,mode:"interaction",after:"interactionHold")
    }
    @discardableResult func handle(_ e: PetEvent) -> Bool {
        let allowed = ["request_received","thinking","tool_search","needs_clarification","task_completed","correction_received","user_stop","user_activity","interaction","show","hide","exit","pause","resume","preview","idle"]
        guard allowed.contains(e.event), e.kind == nil || ["thinking","research","mixed"].contains(e.kind!), e.event != "preview" || animations[e.action ?? ""] != nil else { return false }
        lastEvent = e.event; eventID = e.id
        if !["pause","resume"].contains(e.event) { idleTotal = 0; idleTriggerCount = 0; idlePass = 0 }
        if let kind = e.kind { workingKind = kind }
        if !["pause","resume","interaction"].contains(e.event) { queuedInteraction = false }
        switch e.event {
        case "request_received": pendingCompletion = false; corrected = false; paused = false; play("11-accept",mode:"accepting",after:"acceptHold")
        case "thinking", "tool_search":
            if e.event == "tool_search" { workingKind = "research" }
            if mode == "accepting" || mode == "apology" { break }
            if mode == "working", (e.event != "tool_search" || action == "13-research") { break }
            work()
        case "needs_clarification": play("14-question",mode:"waiting",after:"wait")
        case "task_completed":
            if ["stopped","leaving","hidden"].contains(mode) { break }
            if ["accepting","apology"].contains(mode) { pendingCompletion = true } else { finishTask() }
        case "correction_received": pendingCompletion = false; corrected = true; paused = false; play("03-apology",mode:"apology",after:"apologyHold")
        case "user_stop": pendingCompletion = false; corrected = false; paused = false; play("17-stop",mode:"stopped",after:"hold")
        case "user_activity": pendingCompletion = false; corrected = false; rest()
        case "interaction":
            corrected = false
            if mode == "interaction" { queuedInteraction = true } else { paused = false; interaction() }
        case "show": paused = false; play("20-bicycle",mode:"appearing",after:"idle")
        case "hide", "exit": paused = false; play("21-bicycle-exit",mode:"leaving",after:e.event == "exit" ? "quit" : "hidden")
        case "pause": paused = true; changed?()
        case "resume": paused = false; changed?()
        case "preview": corrected = false; paused = false; play(e.action!,mode:"preview",after:"hold")
        case "idle": corrected = false; rest()
        default: break
        }
        log?("event \(e.event) id=\(e.id)"); changed?(); return true
    }
    func tick(_ dt: Double) {
        guard !paused else { return }
        clock += dt
        if mode == "idle" {
            idleElapsed += dt; idleTotal += dt
            if idleElapsed >= nextIdleInterval {
                idleTriggerCount += 1; idlePass = 1
                let pool: [(String,Int)] = idleTotal > 90 ? [("04-toy-car",25),("05-rice",15),("06-yawn",20),("19-peek",20),("10-speechless",10),("18-doze",10)] : [("04-toy-car",30),("05-rice",20),("06-yawn",20),("19-peek",20),("10-speechless",10)]
                play(pick(pool,category:"idle"),mode:"idle-action",after:"idle")
            }; return
        }
        guard !holding, let a = animations[action] else { return }
        remaining -= dt
        guard remaining <= 0 else { return }
        if !terminalPause && frame + 1 < a.playback_frame_order.count {
            frame += 1; remaining += Double(a.durations_ms[frame]) / 1000 * frameSpeed; changed?(); return
        }
        // Terminal poses use the final physical source frame, not a loop-closing duplicate.
        switch after {
        case "acceptHold": frame = a.frame_count - 1; terminalPause = true; remaining = 1; after = "beginWork"; changed?()
        case "apologyHold": frame = a.frame_count - 1; terminalPause = true; remaining = apologyHold; after = "beginWork"; changed?()
        case "interactionHold": frame = a.frame_count - 1; terminalPause = true; remaining = 1; after = "interactionEnd"; changed?()
        case "interactionEnd": if queuedInteraction { queuedInteraction = false; interaction() } else { rest() }
        case "beginWork", "workResume": work()
        case "work": frame = a.frame_count - 1; terminalPause = true; remaining = loopGap; after = "workResume"; changed?()
        case "finishTask": pendingCompletion = false; finishTask()
        case "wait": frame = a.frame_count - 1; terminalPause = true; remaining = loopGap; after = "waitResume"; changed?()
        case "waitResume": play("14-question",mode:"waiting",after:"wait")
        case "idle" where mode == "idle-action":
            if idlePass < idleRepetitions { frame = a.frame_count - 1; terminalPause = true; remaining = loopGap; after = "idleRepeat"; changed?() } else { rest() }
        case "idleRepeat": idlePass += 1; play(action,mode:"idle-action",after:"idle")
        case "hold": frame = a.frame_count - 1; holding = true; changed?()
        case "hidden": mode = "hidden"; holding = true; changed?()
        case "quit": mode = "quit"; holding = true; changed?()
        default: rest()
        }
    }
    var sourceFrame: Int {
        guard let a = animations[action] else { return 0 }
        if holding || terminalPause { return a.frame_count - 1 }
        return a.playback_frame_order[min(frame,a.playback_frame_order.count-1)]
    }
}
