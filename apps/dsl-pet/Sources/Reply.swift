import AppKit
import CoreGraphics

final class ReplyBubbleView:NSView {
    var closeReply:(()->Void)?
    override func draw(_ dirtyRect:NSRect) {
        // Use exactly the same oval, border and thought dots as the reading bubble.
        ThoughtBubbleView(frame:bounds).draw(dirtyRect)
    }
    override func rightMouseDown(with event:NSEvent){closeReply?()}
}
final class ReplySendButton:NSButton {
    override func draw(_ dirtyRect:NSRect) {
        ThoughtBubbleView.ink.setFill();NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:10,yRadius:10).fill()
        let text="发送" as NSString,attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:12,weight:.semibold),.foregroundColor:NSColor.white]
        let size=text.size(withAttributes:attributes);text.draw(at:NSPoint(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2),withAttributes:attributes)
    }
}
final class ReplyTextView:NSTextView {
    var sendReply:(()->Void)?
    override func keyDown(with event:NSEvent) {
        if (event.keyCode==36 || event.keyCode==76) && !event.modifierFlags.contains(.shift) && !hasMarkedText() {sendReply?()}
        else {super.keyDown(with:event)}
    }
}

extension Controller {
    @objc func showReplyComposer() {
        guard notices.indices.contains(selectedNotice),let id=notices[selectedNotice].threadID,UUID(uuidString:id) != nil,!replySending else{return}
        saveReplyDraft()
        if replyPanel == nil {
            let w=PetPanel(contentRect:NSRect(x:0,y:0,width:360,height:270),styleMask:[.borderless],backing:.buffered,defer:false)
            w.title="小 DSL · 直接回复";w.level = .floating;w.isOpaque=false;w.backgroundColor = .clear;w.hasShadow=false;w.hidesOnDeactivate=false;w.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
            let root=ReplyBubbleView(frame:NSRect(x:0,y:0,width:360,height:270));root.closeReply={ [weak self] in self?.closeReplyComposer() };root.autoresizesSubviews=false;w.contentView=root
            let title=NSTextField(labelWithString:"回复原会话");title.font = .systemFont(ofSize:13,weight:.semibold);title.textColor=ThoughtBubbleView.ink;title.alignment = .center;title.frame=NSRect(x:90,y:218,width:180,height:18);root.addSubview(title)
            let scroll=NSScrollView(frame:NSRect(x:59,y:137,width:242,height:68));scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
            let text=ReplyTextView(frame:NSRect(x:0,y:0,width:242,height:68));text.isEditable=true;text.isSelectable=true;text.drawsBackground=false;text.font = .systemFont(ofSize:16);text.textColor=ThoughtBubbleView.ink;text.insertionPointColor=ThoughtBubbleView.ink;text.textContainerInset=NSSize(width:5,height:5);text.textContainer?.widthTracksTextView=true;text.autoresizingMask = .width;text.delegate=self;text.setAccessibilityLabel("输入回复，回车发送，Shift 回车换行");text.sendReply={ [weak self] in self?.sendDirectReply() };scroll.documentView=text;root.addSubview(scroll);replyText=text
            let status=NSTextField(wrappingLabelWithString:"回车发送 · Shift 回车换行");status.font = .systemFont(ofSize:10);status.textColor=ThoughtBubbleView.ink;status.alignment = .center;status.frame=NSRect(x:69,y:99,width:143,height:31);root.addSubview(status);replyStatus=status
            let button=ReplySendButton(title:"发送",target:self,action:#selector(sendDirectReply));button.bezelStyle = .rounded;button.contentTintColor=ThoughtBubbleView.ink;button.frame=NSRect(x:222,y:101,width:58,height:28);button.setAccessibilityLabel("发送回复到原会话");root.addSubview(button);replySend=button
            replyPanel=w
        }
        if replyThreadID != id {replyLastError=nil}
        replyThreadID=id;replyText?.string=replyDrafts[id] ?? "";replyStatus?.stringValue=replyLastError ?? "回车发送 · Shift 回车换行";replySend?.isEnabled=true
        markNoticeRead();bubblePanel.orderOut(nil);positionReplyComposer();NSApp.activate(ignoringOtherApps:true);replyPanel?.makeKeyAndOrderFront(nil);replyPanel?.makeFirstResponder(replyText)
        clearTerminalPose();writeStatus()
    }
    func saveReplyDraft(){if let id=replyThreadID,let text=replyText {replyDrafts[id]=text.string}}
    func closeReplyComposer(){saveReplyDraft();replyPanel?.orderOut(nil);writeStatus()}
    func positionReplyComposer() {
        guard let w=replyPanel,let panel else{return}
        let scale=panel.frame.height/256*0.85,size=NSSize(width:360*scale,height:270*scale)
        if w.frame.size != size {w.setContentSize(size);w.contentView?.setFrameSize(size);w.contentView?.setBoundsSize(NSSize(width:360,height:270))}
        if let bubblePanel {w.setFrameOrigin(bubblePanel.frame.origin)}
        if ["hidden","quit"].contains(engine.mode) {w.orderOut(nil)}
    }
    func clearTerminalPose(){if ["completed","stopped"].contains(engine.mode){event("user_activity")}}
    func textDidChange(_ notification:Notification) {
        guard let text=notification.object as? NSTextView,text === replyText else{return}
        saveReplyDraft();clearTerminalPose();replyLastError=nil;replyStatus?.stringValue="回车发送 · Shift 回车换行"
    }
    @objc func sendDirectReply() {
        guard !replySending,let text=replyText?.string,let thread=replyThreadID,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
        guard text.count<=4000 else {replyStatus?.stringValue="回复最多 4000 字，请缩短后发送。";return}
        // Keep an uncertain attempt's ID when retrying the same text, preventing duplicates.
        if replyAttemptText != text || replyAttemptThread != thread {replyMessageID=UUID().uuidString;replyAttemptText=text;replyAttemptThread=thread}
        replyLastError=nil;replySending=true;replySend?.isEnabled=false;replyText?.isEditable=false;replyStatus?.stringValue="正在发送到原会话…";saveReplyDraft();writeStatus()
        let process=Process(),input=Pipe(),output=Pipe();process.executableURL=URL(fileURLWithPath:"/usr/bin/python3");process.arguments=[resources.appendingPathComponent("reply.py").path];process.standardInput=input;process.standardOutput=output;process.standardError=FileHandle.nullDevice;replyProcess=process
        let payload:[String:String]=["thread_id":thread,"text":text,"message_id":replyMessageID]
        process.terminationHandler={ [weak self] p in
            let bytes=output.fileHandleForReading.readDataToEndOfFile()
            let result=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any]
            DispatchQueue.main.async {
                guard let self else{return};self.replySending=false;self.replySend?.isEnabled=true;self.replyText?.isEditable=true;self.replyProcess=nil
                if result?["ok"] as? Bool == true,let turn=result?["turn_id"] as? String {
                    self.lastReplyTurnID=turn;self.replyLastError=nil;self.replyDrafts[thread]="";self.replyText?.string="";self.replyAttemptText=nil;self.replyAttemptThread=nil;self.replyStatus?.stringValue="已发送";self.replyPanel?.orderOut(nil);self.event("request_received",kind:"mixed")
                } else {self.replyLastError=result?["error"] as? String ?? "未确认发送成功，草稿已保留。";self.replyStatus?.stringValue=self.replyLastError!}
                self.writeStatus()
            }
        }
        do {
            try process.run()
            let data=try JSONSerialization.data(withJSONObject:payload);input.fileHandleForWriting.write(data);try? input.fileHandleForWriting.close()
        } catch {replySending=false;replyProcess=nil;replySend?.isEnabled=true;replyText?.isEditable=true;replyLastError="无法启动发送通道，草稿已保留。";replyStatus?.stringValue=replyLastError!;writeStatus()}
    }
    func checkMainInputActivity() {
        // Only event timing, never key codes, typed characters or chat contents.
        let now=ProcessInfo.processInfo.systemUptime
        let age=CGEventSource.secondsSinceLastEventType(.combinedSessionState,eventType:.keyDown)
        let stamp=now-age
        defer {lastKeyboardStamp=stamp}
        guard lastKeyboardStamp>0,stamp-lastKeyboardStamp>0.05,age<0.5,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.openai.codex",
              ["completed","stopped"].contains(engine.mode) else{return}
        mainInputResets+=1;clearTerminalPose()
    }
}
