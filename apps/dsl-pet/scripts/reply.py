#!/usr/bin/env python3
"""Explicit user-click replies through the existing desktop thread owner.

No independent app-server, UI automation, auto-retry, or policy overrides.
Uses the versioned private desktop IPC; unsupported calls fail explicitly.
"""
import json, os, socket, stat, struct, time, uuid
from pathlib import Path

MAX_FRAME = 32 * 1024 * 1024

class ReplyError(Exception):
    pass

class DesktopIPC:
    def __init__(self, path=None):
        self.path = Path(path or Path.home()/'.codex/ipc/ipc.sock')
        self.client = 'initializing-client'
        self.sock = None

    def __enter__(self):
        info = self.path.lstat()
        parent = self.path.parent.stat()
        if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid() or parent.st_uid != os.getuid() or parent.st_mode & 0o022:
            raise ReplyError('本地会话通道权限异常，未发送。')
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.settimeout(6)
        self.sock.connect(str(self.path))
        result = self.request('initialize', {'clientType':'dsl-pet'}, 0)
        self.client = result['result']['clientId']
        return self

    def __exit__(self, *args):
        if self.sock:
            self.sock.close()

    def exact(self, n):
        data = bytearray()
        while len(data) < n:
            part = self.sock.recv(n-len(data))
            if not part:
                raise ReplyError('连接已断开；请先在原会话核对是否已收到回复。')
            data.extend(part)
        return bytes(data)

    def request(self, method, params, version, target=None, timeout=5):
        request_id = str(uuid.uuid4())
        request = dict(type='request', requestId=request_id, sourceClientId=self.client,
                       version=version, method=method, params=params, timeoutMs=int(timeout*1000))
        if target:
            request['targetClientId'] = target
        body = json.dumps(request, ensure_ascii=False).encode()
        self.sock.sendall(struct.pack('<I',len(body))+body)
        deadline = time.monotonic()+timeout+1
        while time.monotonic() < deadline:
            self.sock.settimeout(max(.1,deadline-time.monotonic()))
            size = struct.unpack('<I',self.exact(4))[0]
            if not 0 < size <= MAX_FRAME:
                raise ReplyError('本地会话通道格式变化，未确认发送结果。')
            response = json.loads(self.exact(size))
            # Not a subscriber: discard unrelated notifications; never print them.
            if response.get('requestId') != request_id:
                continue
            if response.get('resultType') != 'success':
                reason = response.get('error','')
                if reason == 'no-client-found':
                    raise ReplyError('原会话尚未在 GPT 中打开，请先打开原会话后重试。')
                raise ReplyError('GPT 未确认发送成功，请在原会话核对后重试。')
            return response
        raise ReplyError('发送超时，请在原会话核对是否已收到回复后重试。')

def send_reply(thread_id, text, message_id, path=None):
    uuid.UUID(thread_id); uuid.UUID(message_id)
    if not isinstance(text,str) or not text.strip() or len(text)>4000:
        raise ReplyError('请输入 1–4000 字的回复。')
    with DesktopIPC(path) as ipc:
        owner = ipc.request('thread-owner-discovery',{'hostId':'local','conversationId':thread_id},1)
        target = owner.get('handledByClientId')
        if not target or owner.get('result',{}).get('supportsUntrustedAppInput') is not True:
            raise ReplyError('当前 GPT 版本不支持此回复通道，未发送。')
        # Preserve the owner's model, permissions, workspace and conversation context.
        response = ipc.request('thread-follower-start-turn',{
            'conversationId':thread_id,
            'turnStart':{'request':{'threadId':thread_id,
                'input':[{'type':'text','text':text,'text_elements':[]}],
                'clientUserMessageId':message_id},
                'context':{'inheritThreadSettings':True}}
        },2,target=target,timeout=30)
        result = response.get('result',{}).get('result',{})
        if not isinstance(result,dict) or not result.get('turn',{}).get('id'):
            raise ReplyError('GPT 返回了未知发送结果，请在原会话核对。')
        return {'ok':True,'thread_id':thread_id,'turn_id':result['turn']['id']}

if __name__ == '__main__':
    import sys
    try:
        payload=json.load(sys.stdin)
        output=send_reply(payload['thread_id'],payload['text'],payload['message_id'])
    except (ReplyError,OSError,ValueError,KeyError,TypeError,json.JSONDecodeError) as error:
        message=str(error) if isinstance(error,ReplyError) else '无法连接 GPT 本地会话通道；草稿已保留。'
        output={'ok':False,'error':message}
    print(json.dumps(output,ensure_ascii=False),flush=True)
