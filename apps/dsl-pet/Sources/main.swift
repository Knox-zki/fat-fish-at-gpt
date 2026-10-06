import AppKit

func selfTest() throws {
    let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]));let a=try JSONDecoder().decode([Animation].self,from:data)
    let e=PetEngine(a);e.chooseNumber={_ in 0}
    func send(_ event:String,_ kind:String?=nil){precondition(e.handle(PetEvent(id:UUID().uuidString,event:event,kind:kind)))}
    func advance(_ seconds:Double){for _ in 0..<Int(seconds/0.01){e.tick(0.01)}}
    send("request_received");advance(1.6);precondition(e.mode=="accepting" && e.sourceFrame==5);advance(0.9);precondition(e.mode=="accepting");advance(0.2);precondition(e.mode=="working")
    send("task_completed");advance(3);precondition(e.holding && e.sourceFrame==5);advance(60);precondition(e.mode=="completed" && e.holding)
    send("user_activity");precondition(e.mode=="idle")
    send("correction_received");advance(2);precondition(e.mode=="apology" && e.sourceFrame==5);advance(1.7);precondition(e.mode=="working");send("task_completed");precondition(e.action=="16-revise");advance(3);precondition(e.holding)
    send("user_stop");advance(3);precondition(e.action=="17-stop" && e.holding);advance(60);precondition(e.mode=="stopped")
    send("interaction");send("interaction");send("interaction");precondition(e.queuedInteraction);advance(8);precondition(e.mode=="idle" && !e.queuedInteraction)
    send("needs_clarification");advance(8);precondition(e.mode=="waiting")
    send("hide");advance(3);precondition(e.mode=="hidden");send("show");advance(3);precondition(e.mode=="idle")
    send("request_received");send("task_completed");advance(1);precondition(e.mode=="accepting");advance(1.8);precondition(e.mode=="working");advance(5);precondition(e.mode=="completed" && e.holding)
    send("user_stop");advance(3);send("task_completed");precondition(e.mode=="stopped")
    precondition(!e.handle(PetEvent(id:"bad",event:"preview",action:"missing")))
    send("user_activity");advance(59);precondition(e.mode=="idle");advance(1.1);precondition(e.mode=="idle-action" && e.idlePass==1 && e.idleTriggerCount==1);let slow=Double(e.animations[e.action]!.durations_ms[0])/1000*1.5;precondition(e.remaining>slow-0.2);advance(11);precondition(e.mode=="idle" && e.idlePass==3 && e.nextIdleInterval==120);advance(105);precondition(e.mode=="idle");advance(15);precondition(e.mode=="idle-action" && e.idleTriggerCount==2);send("user_activity");precondition(e.nextIdleInterval==60 && e.idleTriggerCount==0)
    send("thinking");let duration=Double(e.animations[e.action]!.durations_ms.reduce(0,+))/1000;advance(duration+0.05);precondition(e.terminalPause && e.mode=="working");advance(0.8);precondition(e.terminalPause);send("user_stop");precondition(e.action=="17-stop" && !e.terminalPause)
    for animation in a {send("user_activity");precondition(e.handle(PetEvent(id:animation.key,event:"preview",action:animation.key)));advance(4);precondition(e.holding && e.sourceFrame==animation.frame_count-1)}
    for (kind, expected) in [("thinking", Set(["12-think","22-laptop","24-ponder","25-count"])), ("research", Set(["13-research","23-magnifier"])), ("mixed", Set(["12-think","22-laptop","24-ponder","25-count","13-research","23-magnifier"]))] {
        let worker=PetEngine(a);worker.workingKind=kind
        var seen=Set<String>();var last=""
        for ticket in 0..<300 { worker.chooseNumber={n in ticket % n};worker.work();precondition(worker.action != last);seen.insert(worker.action);last=worker.action;worker.tick(13) }
        precondition(seen==expected)
    }
    send("user_activity");precondition(e.handle(PetEvent(id:"glass",event:"preview",action:"23-magnifier")));e.mode="working";e.remaining=0.2;send("tool_search");precondition(e.action=="23-magnifier" && e.remaining==0.2)
    print("PASS:\(a.count) animations; work pool coverage/no adjacent repeats; research event preserves magnifier; accept1s; correction2s/work/revise; indefinite terminal hold; stop interrupt; bounded interaction queue; 1s loop gaps; 1.5x idle duration/3 repetitions; incremental 60/120s idle/reset; waiting loop; show/hide; validation")
}
if CommandLine.arguments.contains("--self-test") {do{try selfTest()}catch{fputs("\(error)\n",stderr);exit(1)}} else {
    let app=NSApplication.shared;app.setActivationPolicy(.accessory)
    let delegate=Controller();app.delegate=delegate;app.run()
}
