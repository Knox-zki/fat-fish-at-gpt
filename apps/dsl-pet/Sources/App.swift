import AppKit

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func accessibilityPerformRaise() -> Bool { orderFrontRegardless(); return true }
}
final class PetView: NSView {
    var image: NSImage?
    var clicked: (() -> Void)?
    var doubleClicked: (() -> Void)?
    var pendingClick: DispatchWorkItem?
    var clickToken: UUID?
    var singleClickCount=0, doubleClickCount=0
    var rightClicked: ((NSEvent) -> Void)?
    var moved: (() -> Void)?
    var downPoint = NSPoint.zero, origin = NSPoint.zero, dragged = false
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        NSGraphicsContext.current?.imageInterpolation = .high
        let scale = bounds.height / 512
        let size = NSSize(width:image.size.width * scale,height:image.size.height * scale)
        image.draw(in:NSRect(x:(bounds.width-size.width)/2,y:0,width:size.width,height:size.height),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
    }
    override func mouseDown(with event:NSEvent) { if event.clickCount>=2 {pendingClick?.cancel();pendingClick=nil;clickToken=nil};downPoint = NSEvent.mouseLocation; origin = window!.frame.origin; dragged = false }
    override func mouseDragged(with event:NSEvent) {
        let p = NSEvent.mouseLocation, dx=p.x-downPoint.x, dy=p.y-downPoint.y
        if abs(dx)+abs(dy)>4 { dragged = true; window?.setFrameOrigin(NSPoint(x:origin.x+dx,y:origin.y+dy)) }
    }
    override func mouseUp(with event:NSEvent) {
        if dragged {pendingClick?.cancel();pendingClick=nil;clickToken=nil;moved?();return}
        if event.clickCount>=2 {pendingClick?.cancel();pendingClick=nil;clickToken=nil;doubleClickCount+=1;doubleClicked?()}
        else {pendingClick?.cancel();let token=UUID();clickToken=token;let job=DispatchWorkItem { [weak self] in guard let self,self.clickToken==token else{return};self.singleClickCount+=1;self.clicked?();self.pendingClick=nil;self.clickToken=nil };pendingClick=job;DispatchQueue.main.asyncAfter(deadline:.now()+NSEvent.doubleClickInterval,execute:job)}
    }
    override func rightMouseDown(with event:NSEvent) { rightClicked?(event) }
}
final class Controller: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextViewDelegate {
    var panel:NSPanel!, view:PetView!, statusItem:NSStatusItem!, debugWindow:NSWindow?
    var debugLabel:NSTextField?, timer:Timer?
    var engine:PetEngine!
    var notices:[PetNotice] = [], selectedNotice=0
    var bubbleTextPage=0,bubbleTextPages:[String]=[]
    var noticePanel:PetPanel!, bubblePanel:PetPanel!, noticeBell:NSButton!, noticeTitle:NSTextField!, noticeText:NSTextView!
    var noticePrevious:NSButton!, noticeNext:NSButton!, noticeOpen:NSButton!, noticePage:NSTextField!
    var replyPanel:PetPanel?, replyText:NSTextView?, replyStatus:NSTextField?, replySend:NSButton?
    var replyThreadID:String?, replyDrafts:[String:String]=[:], replySending=false
    var replyMessageID=UUID().uuidString, replyAttemptText:String?, replyAttemptThread:String?
    var lastReplyTurnID:String?, replyLastError:String?, replyProcess:Process?
    var lastKeyboardStamp:Double=0, mainInputResets=0
    var lastOpenedThread:String?
    var gptActivationAccepted=false
    var gptBecameFrontmost=false
    var frames:[String:[NSImage]] = [:]
    let resources = Bundle.main.resourceURL!
    let ipc = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DSLPet")
    var history:[String] = [], lastTick=Date(), lastStatus=Date.distantPast
    func applicationDidFinishLaunching(_ notification:Notification) {
        let fm=FileManager.default
        do {
            try fm.createDirectory(at:ipc.appendingPathComponent("commands"),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let data=try Data(contentsOf:resources.appendingPathComponent("assets/animations.json"))
            let animations=try JSONDecoder().decode([Animation].self,from:data)
            for a in animations {
                guard a.frame_count == a.playback_frame_order.count, a.durations_ms.count == a.frame_count else { throw NSError(domain:"Invalid timeline",code:1) }
                frames[a.key]=try (1...a.frame_count).map { n in
                    let u=resources.appendingPathComponent(String(format:"assets/%@/逐帧PNG/frame-%02d.png",a.key,n))
                    guard let image=NSImage(contentsOf:u) else { throw NSError(domain:"Missing frame \(u.path)",code:2) }
                    // Logical dimensions are source pixels; Retina drawing retains full PNG data.
                    image.size=NSSize(width:a.frame_size[0],height:a.frame_size[1]); return image
                }
            }
            guard let idle=NSImage(contentsOf:resources.appendingPathComponent("assets/待机.png")) else { throw NSError(domain:"Missing idle",code:3) }
            idle.size=NSSize(width:512,height:512);frames["idle"]=[idle]
            engine=PetEngine(animations)
        } catch { let alert=NSAlert();alert.messageText="小 DSL 素材加载失败";alert.informativeText=error.localizedDescription;alert.runModal();NSApp.terminate(nil);return }
        let height=UserDefaults.standard.double(forKey:"height");let h=height>0 ? height:256
        let screen=NSScreen.main!.visibleFrame
        let x=UserDefaults.standard.object(forKey:"x") == nil ? screen.maxX-360:UserDefaults.standard.double(forKey:"x")
        let y=UserDefaults.standard.object(forKey:"y") == nil ? screen.minY+50:UserDefaults.standard.double(forKey:"y")
        panel=PetPanel(contentRect:NSRect(x:x,y:y,width:h*1.25,height:h),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title="小 DSL 悬浮桌宠";panel.level = .floating;panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=false
        panel.hidesOnDeactivate=false;panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];panel.delegate=self
        view=PetView(frame:NSRect(origin:.zero,size:panel.contentRect(forFrameRect:panel.frame).size));view.autoresizingMask=[.width,.height];panel.contentView=view
        view.setAccessibilityElement(true);view.setAccessibilityRole(.button);view.setAccessibilityLabel("小 DSL：单击互动，双击打开GPT，拖动移动，右键菜单")
        view.clicked={ [weak self] in self?.event("interaction") }
        view.doubleClicked={ [weak self] in self?.activateGPT() }
        view.moved={ [weak self] in guard let self else{return};self.savePosition();self.positionNotices();if ["idle","idle-action"].contains(self.engine.mode) {self.event("user_activity")} }
        view.rightClicked={ [weak self] e in guard let self else{return};NSMenu.popUpContextMenu(self.makeMenu(),with:e,for:self.view) }
        engine.changed={ [weak self] in self?.render() };engine.log={ [weak self] line in self?.record(line) }
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength);statusItem.button?.title="DSL";statusItem.menu=makeMenu()
        setupNotices();panel.orderFrontRegardless();event("show")
        timer=Timer.scheduledTimer(withTimeInterval:0.025,repeats:true) { [weak self] _ in
            guard let self else{return};let now=Date();let dt=min(now.timeIntervalSince(self.lastTick),0.25);self.lastTick=now
            self.readCommands();self.engine.tick(dt);self.checkMainInputActivity()
            if self.gptActivationAccepted && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.openai.codex" {self.gptBecameFrontmost=true}
            if now.timeIntervalSince(self.lastStatus)>0.5 { self.writeStatus();self.lastStatus=now }
        }
        RunLoop.main.add(timer!,forMode:.common)
    }
    func activateGPT() {
        gptActivationAccepted=false;gptBecameFrontmost=false
        let configuration=NSWorkspace.OpenConfiguration();configuration.activates=true
        let location=NSWorkspace.shared.urlForApplication(withBundleIdentifier:"com.openai.codex") ?? URL(fileURLWithPath:"/Applications/ChatGPT.app")
        NSWorkspace.shared.openApplication(at:location,configuration:configuration) { [weak self] app,error in
            DispatchQueue.main.async {
                if let app,error == nil {self?.gptActivationAccepted=true;_ = app.activate(options:[]);self?.gptBecameFrontmost = app.isActive && NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.openai.codex"}
                self?.writeStatus()
            }
        }
    }
    func record(_ line:String) {history.append("\(ISO8601DateFormatter().string(from:Date())) \(line)");if history.count>100 {history.removeFirst()};try? history.joined(separator:"\n").write(to:ipc.appendingPathComponent("history.log"),atomically:true,encoding:.utf8)}
    func event(_ name:String,kind:String?=nil,action:String?=nil) { _=engine.handle(PetEvent(id:UUID().uuidString,event:name,kind:kind,action:action)) }
    func render() {
        if engine.mode == "hidden" {panel.orderOut(nil)} else if engine.mode == "quit" {NSApp.terminate(nil);return} else { if !panel.isVisible {panel.orderFrontRegardless()};view.image=frames[engine.action]?[min(engine.sourceFrame,(frames[engine.action]?.count ?? 1)-1)];view.needsDisplay=true }
        positionNotices();writeStatus()
        debugLabel?.stringValue="状态：\(engine.mode)  动作：\(engine.action)  帧：\(engine.sourceFrame+1)\n保持：\(engine.holding)  暂停：\(engine.paused)\n最近事件：\(engine.lastEvent)\n\n"+history.suffix(7).joined(separator:"\n")
    }
    func writeStatus() {
        var d=(try? JSONSerialization.jsonObject(with:JSONEncoder().encode(engine.snapshot))) as? [String:Any] ?? [:]
        d["pid"]=ProcessInfo.processInfo.processIdentifier;d["updated_at"]=Date().timeIntervalSince1970;d["source_frame"]=engine.sourceFrame;d["window_visible"]=panel?.isVisible ?? false;d["window_level"]=panel?.level.rawValue ?? 0;d["canvas_height"]=panel?.frame.height ?? 0;d["asset_count"]=engine.animations.count;d["loop_gap_seconds"]=engine.loopGap;d["idle_slow_factor"]=engine.idleSlowFactor;d["idle_repetitions"]=engine.idleRepetitions;d["idle_trigger_count"]=engine.idleTriggerCount;d["next_idle_interval_seconds"]=engine.nextIdleInterval;d["idle_elapsed_seconds"]=engine.idleElapsed;d["cycle_gap"]=engine.terminalPause
        d["reply_error"]=replyLastError;d["reply_draft_length"]=replyText?.string.count ?? 0
        d["reply_composer_visible"]=replyPanel?.isVisible ?? false;d["reply_sending"]=replySending;if let b=replySend {d["reply_send_frame"]=[b.frame.minX,b.frame.minY,b.frame.width,b.frame.height]};d["reply_thread_id"]=replyThreadID;d["last_reply_turn_id"]=lastReplyTurnID;d["main_input_resets"]=mainInputResets
        d["pet_single_clicks"]=view.singleClickCount;d["pet_double_clicks"]=view.doubleClickCount
        d["gpt_became_frontmost"]=gptBecameFrontmost;d["gpt_activation_accepted"]=gptActivationAccepted;d["gpt_frontmost"]=NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.openai.codex"
        if let noticePanel,let panel {d["pet_window_frame"]=[panel.frame.minX,panel.frame.minY,panel.frame.width,panel.frame.height];d["bell_window_frame"]=[noticePanel.frame.minX,noticePanel.frame.minY,noticePanel.frame.width,noticePanel.frame.height]}
        if let bubblePanel,let panel {d["bubble_window_frame"]=[bubblePanel.frame.minX,bubblePanel.frame.minY,bubblePanel.frame.width,bubblePanel.frame.height];d["bubble_scale"]=panel.frame.height/256*0.85;d["bubble_scaled_font_size"]=(noticeText?.font?.pointSize ?? 0)*panel.frame.height/256*0.85}
        d["bubble_text_page"]=bubbleTextPage;d["bubble_text_pages"]=bubbleTextPages.count;d["selected_notice_index"]=selectedNotice
        d["notice_count"]=notices.count;d["unread_count"]=notices.filter{$0.unread}.count;d["bubble_visible"]=bubblePanel?.isVisible ?? false;d["notice_controls_visible"]=noticePanel?.isVisible ?? false
        d["latest_notice_id"]=notices.last?.id;d["latest_notice_kind"]=notices.last?.kind;d["selected_thread_id"]=notices.indices.contains(selectedNotice) ? notices[selectedNotice].threadID:nil;d["last_opened_thread_id"]=lastOpenedThread
        if let bytes=try? JSONSerialization.data(withJSONObject:d,options:[.prettyPrinted,.sortedKeys]) {try? bytes.write(to:ipc.appendingPathComponent("status.json"),options:.atomic)}
    }
    func readCommands() {
        let fm=FileManager.default,dir=ipc.appendingPathComponent("commands")
        for f in ((try? fm.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil)) ?? []).filter({$0.pathExtension=="json"}).sorted(by:{$0.lastPathComponent<$1.lastPathComponent}) {
            do {
                let e=try JSONDecoder().decode(PetEvent.self,from:Data(contentsOf:f));let accepted:Bool
                if e.event == "open_reply" {showReplyComposer();accepted=replyPanel?.isVisible ?? false} else if e.event == "activate_gpt" {activateGPT();accepted=true} else if e.event == "notify" {accepted=receiveNotice(e)} else if e.event == "dismiss_notice" {dismissNotice();accepted=true} else if e.event == "open_notice" {openNoticeThread();accepted=lastOpenedThread != nil} else if e.event == "controls" {showDebug();accepted=true} else if e.event == "snapshot" {saveSnapshot();accepted=true} else {accepted=engine.handle(e);if accepted && ["request_received","user_activity"].contains(e.event) {bubblePanel.orderOut(nil)}}
                let ack:[String:Any]=["id":e.id,"accepted":accepted,"mode":engine.mode,"action":engine.action]
                if let data=try? JSONSerialization.data(withJSONObject:ack) {try? data.write(to:ipc.appendingPathComponent("ack-\(f.lastPathComponent)"),options:.atomic)}
            } catch {record("invalid command \(f.lastPathComponent): \(error)")}
            try? fm.removeItem(at:f)
        }
    }
    func saveSnapshot() {
        if let bubblePanel=replyPanel?.isVisible == true ? replyPanel : bubblePanel, bubblePanel.isVisible, let content=bubblePanel.contentView,let bitmap=content.bitmapImageRepForCachingDisplay(in:content.bounds) {
            content.cacheDisplay(in:content.bounds,to:bitmap)
            if let data=bitmap.representation(using:.png,properties:[:]) {try? data.write(to:ipc.appendingPathComponent("bubble-preview.png"),options:.atomic)}
        }
        guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{return}
        view.cacheDisplay(in:view.bounds,to:bitmap)
        if let data=bitmap.representation(using:.png,properties:[:]) {try? data.write(to:ipc.appendingPathComponent("preview.png"),options:.atomic)}
    }
    func savePosition() {UserDefaults.standard.set(panel.frame.origin.x,forKey:"x");UserDefaults.standard.set(panel.frame.origin.y,forKey:"y")}
    func menuItem(_ title:String,_ selector:Selector,_ represented:String?=nil)->NSMenuItem {let i=NSMenuItem(title:title,action:selector,keyEquivalent:"");i.target=self;i.representedObject=represented;return i}
    func makeMenu()->NSMenu {
        let m=NSMenu();m.addItem(menuItem("小 DSL · 显示 / 出场",#selector(showPet)));m.addItem(menuItem("播放互动",#selector(interact)));m.addItem(menuItem("恢复默认姿势",#selector(restPet)))
        m.addItem(menuItem("暂停 / 继续",#selector(togglePause)));m.addItem(.separator())
        let size=NSMenuItem(title:"显示大小",action:nil,keyEquivalent:""),sizes=NSMenu()
        for h in [192,256,320,384,512] {sizes.addItem(menuItem("\(h) px 高",#selector(resizePet(_:)),String(h)))};size.submenu=sizes;m.addItem(size)
        let preview=NSMenuItem(title:"预览全部 21 个动作",action:nil,keyEquivalent:""),actions=NSMenu()
        if let engine {for a in engine.animations.values.sorted(by:{$0.key<$1.key}) {actions.addItem(menuItem(a.name,#selector(previewAction(_:)),a.key))}};preview.submenu=actions;m.addItem(preview)
        m.addItem(menuItem("消息与回复",#selector(toggleNotices)));m.addItem(menuItem("控制与状态面板",#selector(showDebug)));m.addItem(menuItem("离场并隐藏",#selector(hidePet)));m.addItem(menuItem("离场并退出",#selector(quitPet)));return m
    }
    @objc func showPet(){event("show")};@objc func hidePet(){event("hide")};@objc func quitPet(){event("exit")};@objc func interact(){event("interaction")};@objc func restPet(){event("user_activity")};@objc func togglePause(){event(engine.paused ? "resume":"pause")}
    @objc func resizePet(_ sender:NSMenuItem){guard let v=sender.representedObject as? String,let h=Double(v) else{return};panel.setFrame(NSRect(origin:panel.frame.origin,size:NSSize(width:h*1.25,height:h)),display:true);UserDefaults.standard.set(h,forKey:"height");render()}
    @objc func previewAction(_ sender:NSMenuItem){event("preview",action:sender.representedObject as? String)}
    @objc func sendButton(_ sender:NSButton){event(sender.identifier!.rawValue,kind:sender.identifier!.rawValue == "tool_search" ? "research":nil)}
    @objc func showDebug(){
        if let debugWindow {debugWindow.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);return}
        let w=NSWindow(contentRect:NSRect(x:200,y:180,width:650,height:430),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false);w.title="小 DSL · 情境控制与状态";w.isReleasedWhenClosed=false
        let root=NSView(frame:NSRect(x:0,y:0,width:650,height:430));w.contentView=root
        let buttons=[("接到任务","request_received"),("思考","thinking"),("查资料","tool_search"),("需要输入","needs_clarification"),("完成","task_completed"),("收到纠正","correction_received"),("停止","user_stop"),("用户有动作","user_activity")]
        for (i,p) in buttons.enumerated(){let b=NSButton(title:p.0,target:self,action:#selector(sendButton(_:)));b.identifier=NSUserInterfaceItemIdentifier(p.1);b.frame=NSRect(x:18+(i%4)*155,y:385-(i/4)*42,width:145,height:32);root.addSubview(b)}
        let label=NSTextField(wrappingLabelWithString:"");label.frame=NSRect(x:20,y:20,width:610,height:270);label.font=NSFont.monospacedSystemFont(ofSize:12,weight:.regular);root.addSubview(label);debugLabel=label;debugWindow=w;render();w.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
}
