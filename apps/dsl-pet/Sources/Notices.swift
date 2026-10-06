import AppKit

struct PetNotice {
    let id: String
    var title: String
    var message: String
    var threadID: String?
    var kind: String
    var unread = true
    var label: String { ["completed":"已完成", "input":"需要你回复", "blocked":"需要处理", "info":"新消息"][kind] ?? "新消息" }
}

final class ThoughtBubbleView: NSView {
    var turnPage:(()->Void)?
    var closeBubble:(()->Void)?
    weak var openButton:NSButton?
    override func hitTest(_ point:NSPoint)->NSView? {
        let local=convert(point,from:superview)
        guard bounds.contains(local) else{return nil}
        if let button=openButton, !button.isHidden, button.frame.contains(local) {return button}
        return self
    }
    override func mouseUp(with event:NSEvent){turnPage?()}
    override func rightMouseDown(with event:NSEvent){closeBubble?()}
    static let ink=NSColor(srgbRed:0.13,green:0.20,blue:0.43,alpha:1)
    override func draw(_ dirtyRect:NSRect) {
        let p=NSBezierPath();p.move(to:NSPoint(x:148,y:66))
        p.curve(to:NSPoint(x:348,y:163),controlPoint1:NSPoint(x:258,y:58),controlPoint2:NSPoint(x:348,y:100))
        p.curve(to:NSPoint(x:180,y:261),controlPoint1:NSPoint(x:348,y:218),controlPoint2:NSPoint(x:274,y:261))
        p.curve(to:NSPoint(x:12,y:163),controlPoint1:NSPoint(x:87,y:261),controlPoint2:NSPoint(x:12,y:220))
        p.curve(to:NSPoint(x:112,y:72),controlPoint1:NSPoint(x:12,y:108),controlPoint2:NSPoint(x:58,y:82))
        p.curve(to:NSPoint(x:112,y:61),controlPoint1:NSPoint(x:111,y:69),controlPoint2:NSPoint(x:110,y:66))
        p.curve(to:NSPoint(x:147,y:61),controlPoint1:NSPoint(x:118,y:45),controlPoint2:NSPoint(x:142,y:48))
        p.curve(to:NSPoint(x:148,y:66),controlPoint1:NSPoint(x:149,y:63),controlPoint2:NSPoint(x:149,y:64));p.close()
        NSColor.white.setFill();p.fill();Self.ink.setStroke();p.lineWidth=5;p.stroke()
        for rect in [NSRect(x:122,y:20,width:30,height:22),NSRect(x:161,y:3,width:18,height:14)] {let dot=NSBezierPath(ovalIn:rect);NSColor.white.setFill();dot.fill();Self.ink.setStroke();dot.lineWidth=4;dot.stroke()}
    }
}
final class BubbleOpenButton:NSButton {
    var closeBubble:(()->Void)?
    override func rightMouseDown(with event:NSEvent){closeBubble?()}
}
final class NoticeBellButton: NSButton {
    var unreadCount=0 {didSet{needsDisplay=true}}
    override func draw(_ dirtyRect:NSRect) {
        NSColor.white.withAlphaComponent(0.95).setFill();NSBezierPath(ovalIn:bounds.insetBy(dx:1,dy:1)).fill()
        super.draw(dirtyRect)
        if unreadCount>0 {NSColor(srgbRed:0.94,green:0.29,blue:0.30,alpha:1).setFill();NSBezierPath(ovalIn:NSRect(x:bounds.maxX-10,y:bounds.maxY-10,width:7,height:7)).fill()}
    }
}

extension Controller {
    func receiveNotice(_ e: PetEvent) -> Bool {
        guard let title=e.title, !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, title.count<=120,
              let message=e.message, !message.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, message.count<=4000,
              ["completed","input","blocked","info"].contains(e.notice_kind ?? "info"),
              e.thread_id == nil || UUID(uuidString:e.thread_id!) != nil,
              e.notice_id == nil || (!(e.notice_id!.isEmpty) && e.notice_id!.count<=160) else {return false}
        let n=PetNotice(id:e.notice_id ?? e.id,title:title,message:message,threadID:e.thread_id,kind:e.notice_kind ?? "info")
        if let index=notices.firstIndex(where:{$0.id==n.id}) {notices.remove(at:index)}
        notices.append(n);if notices.count>20 {notices.removeFirst(notices.count-20)}
        selectedNotice=notices.count-1;bubbleTextPage=0
        setupNotices();updateNoticeUI()
        if (e.show_bubble ?? true) && !["hidden","quit"].contains(engine.mode) {bubblePanel.orderFrontRegardless()}
        writeStatus();return true
    }
    func setupNotices() {
        guard noticePanel == nil else{return}
        let controls=PetPanel(contentRect:NSRect(x:0,y:0,width:40,height:40),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        controls.title="小 DSL · 消息通知";controls.isOpaque=false;controls.backgroundColor = .clear;controls.hasShadow=true;controls.level = .floating
        controls.hidesOnDeactivate=false;controls.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        let bell=NoticeBellButton(title:"",target:self,action:#selector(toggleNotices));bell.frame=NSRect(x:0,y:0,width:40,height:40);bell.isBordered=false;bell.imagePosition = .imageOnly
        bell.image=NSImage(systemSymbolName:"bell",accessibilityDescription:"消息通知")?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize:20,weight:.regular));bell.contentTintColor=ThoughtBubbleView.ink
        bell.isEnabled=false;bell.toolTip="暂无消息";bell.setAccessibilityLabel("小 DSL 消息通知");controls.contentView=bell;noticePanel=controls;noticeBell=bell
        let bubble=PetPanel(contentRect:NSRect(x:0,y:0,width:360,height:270),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        bubble.title="小 DSL · 回复气泡";bubble.level = .floating;bubble.hidesOnDeactivate=false;bubble.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];bubble.isOpaque=false;bubble.backgroundColor = .clear;bubble.hasShadow=false
        let root=ThoughtBubbleView(frame:NSRect(x:0,y:0,width:360,height:270));bubble.contentView=root
        root.turnPage={ [weak self] in self?.turnBubblePage() };root.closeBubble={ [weak self] in self?.dismissNotice() }
        root.setAccessibilityElement(true);root.setAccessibilityRole(.button);root.setAccessibilityLabel("回复气泡：左键翻页，右键关闭")
        let label=NSTextField(labelWithString:"");label.isHidden=true;root.addSubview(label);noticeTitle=label
        let scroll=NSScrollView(frame:NSRect(x:53,y:111,width:254,height:105));scroll.hasVerticalScroller=false;scroll.drawsBackground=false
        let text=NSTextView(frame:NSRect(x:0,y:0,width:240,height:105));text.isEditable=false;text.isSelectable=false;text.drawsBackground=false;text.font = .systemFont(ofSize:19,weight:.semibold);text.textColor=NSColor(srgbRed:0.32,green:0.43,blue:0.68,alpha:1);text.alignment = .center;text.textContainerInset=NSSize(width:0,height:5);text.autoresizingMask = .width;text.textContainer?.widthTracksTextView=true;scroll.documentView=text;root.addSubview(scroll);noticeText=text
        let count=NSTextField(labelWithString:"");count.frame=NSRect(x:105,y:82,width:100,height:16);count.font = .systemFont(ofSize:10);count.textColor=ThoughtBubbleView.ink;count.alignment = .center;root.addSubview(count);noticePage=count
        let open=BubbleOpenButton(title:"",target:self,action:#selector(showReplyComposer));open.isBordered=false;open.image=NSImage(systemSymbolName:"arrowshape.turn.up.left",accessibilityDescription:"直接回复");open.contentTintColor=ThoughtBubbleView.ink;open.setAccessibilityLabel("直接回复");open.frame=NSRect(x:220,y:78,width:26,height:24);root.addSubview(open);noticeOpen=open;root.openButton=open;open.closeBubble={ [weak self] in self?.dismissNotice() }
        bubblePanel=bubble;positionNotices()
    }
    func positionNotices() {
        guard let panel,let noticePanel else{return}
        let bounds=(panel.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
        func fit(_ origin:NSPoint,_ size:NSSize)->NSPoint {NSPoint(x:max(bounds.minX,min(origin.x,bounds.maxX-size.width)),y:max(bounds.minY,min(origin.y,bounds.maxY-size.height)))}
        noticePanel.setFrameOrigin(fit(NSPoint(x:panel.frame.midX+panel.frame.height*0.37-20,y:panel.frame.maxY-panel.frame.height*0.04-20),noticePanel.frame.size))
        let scale=panel.frame.height/256*0.85
        let desired=NSSize(width:360*scale,height:270*scale)
        if bubblePanel.frame.size != desired {
            bubblePanel.setContentSize(desired);bubblePanel.contentView?.setFrameSize(desired)
            bubblePanel.contentView?.setBoundsSize(NSSize(width:360,height:270));bubblePanel.contentView?.needsDisplay=true
        }
        let size=bubblePanel.frame.size
        let above=panel.frame.maxY-45*scale
        let x=above+size.height<=bounds.maxY ? panel.frame.midX-215*scale : panel.frame.minX-size.width+35*scale
        let y=above+size.height<=bounds.maxY ? above : panel.frame.midY-40*scale
        bubblePanel.setFrameOrigin(fit(NSPoint(x:x,y:y),size))
        positionReplyComposer()
        if ["hidden","quit"].contains(engine.mode) {noticePanel.orderOut(nil);bubblePanel.orderOut(nil)} else if notices.contains(where:{$0.unread}) {if !noticePanel.isVisible {noticePanel.orderFrontRegardless()}} else {noticePanel.orderOut(nil)}
    }
    func updateNoticeUI() {
        guard noticePanel != nil else{return}
        noticeBell.isEnabled = !notices.isEmpty;noticeBell.toolTip=notices.isEmpty ? "暂无消息":"查看最近的回复和任务通知"
        let count=notices.filter{$0.unread}.count;(noticeBell as? NoticeBellButton)?.unreadCount=count;noticeBell.setAccessibilityLabel("消息通知，\(count)条未读")
        guard !notices.isEmpty else{return}
        selectedNotice=max(0,min(selectedNotice,notices.count-1));let n=notices[selectedNotice]
        noticeTitle.stringValue="\(n.label) · \(n.title)";bubblePanel.contentView?.toolTip=noticeTitle.stringValue+" · 左键翻页，右键关闭"
        let font=NSFont.systemFont(ofSize:n.message.count<=80 ? 24:14,weight:n.message.count<=80 ? .semibold:.regular)
        let width:CGFloat=n.message.count<=80 ? 224:254
        bubbleTextPages=paginateBubble(n.message,font:font,width:width-14)
        bubbleTextPage=max(0,min(bubbleTextPage,bubbleTextPages.count-1))
        let message=bubbleTextPages[bubbleTextPage];noticeText.string=message;noticeText.font=font
        if let scroll=noticeText.enclosingScrollView {
            let measured=(message as NSString).boundingRect(with:NSSize(width:width-14,height:1000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font]).height
            let h=min(112,max(40,ceil(measured)+14));scroll.frame=NSRect(x:(360-width)/2,y:164-h/2,width:width,height:h)
            noticeText.setFrameSize(NSSize(width:scroll.contentSize.width,height:max(h,measured+14)))
        }
        noticeText.scrollRangeToVisible(NSRange(location:0,length:0))
        noticePage.stringValue=bubbleTextPages.count>1 ? "页 \(bubbleTextPage+1)/\(bubbleTextPages.count)" : "消息 \(selectedNotice+1)/\(notices.count)"
        noticePage.isHidden=notices.count<=1 && bubbleTextPages.count<=1
        noticeOpen.isEnabled=n.threadID != nil
        noticeOpen.toolTip=n.threadID == nil ? "这条消息未关联会话":"在桌宠旁输入并发送回复"
        positionNotices()
    }
    func markNoticeRead() {if notices.indices.contains(selectedNotice) {notices[selectedNotice].unread=false};updateNoticeUI();writeStatus()}
    @objc func toggleNotices() {
        guard !notices.isEmpty else{return}
        if bubblePanel.isVisible {dismissNotice()} else {selectedNotice=notices.count-1;bubbleTextPage=0;markNoticeRead();bubblePanel.makeKeyAndOrderFront(nil)}
    }
    @objc func dismissNotice(){markNoticeRead();bubblePanel.orderOut(nil);writeStatus()}
    func paginateBubble(_ message:String,font:NSFont,width:CGFloat)->[String] {
        var result:[String]=[],page=""
        for char in message {
            let candidate=page+String(char)
            let height=(candidate as NSString).boundingRect(with:NSSize(width:width,height:1000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font]).height
            if height>98 && !page.isEmpty {result.append(page);page=String(char)} else {page=candidate}
        }
        if !page.isEmpty {result.append(page)}
        return result.isEmpty ? [message]:result
    }
    @objc func turnBubblePage() {
        guard !notices.isEmpty else{return}
        notices[selectedNotice].unread=false
        if bubbleTextPage+1<bubbleTextPages.count {bubbleTextPage+=1}
        else {dismissNotice();return}
        markNoticeRead()
    }
    @objc func previousNotice(){selectedNotice=max(0,selectedNotice-1);bubbleTextPage=0;markNoticeRead()}
    @objc func nextNotice(){selectedNotice=min(notices.count-1,selectedNotice+1);bubbleTextPage=0;markNoticeRead()}
    @objc func openNoticeThread() {
        lastOpenedThread=nil
        guard notices.indices.contains(selectedNotice),let id=notices[selectedNotice].threadID,
              UUID(uuidString:id) != nil,let url=URL(string:"codex://threads/"+id) else{return}
        if NSWorkspace.shared.open(url) {lastOpenedThread=id;markNoticeRead();bubblePanel.orderOut(nil);writeStatus()}
        else {noticeTitle.stringValue="无法打开会话，请确认 ChatGPT 已安装"}
    }
}
