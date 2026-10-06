#!/usr/bin/env python3
"""Local stdio MCP + CLI. No network, no keyboard/content monitoring."""
import argparse,json,os,subprocess,sys,time,uuid
from pathlib import Path
BASE=Path.home()/'Library/Application Support/DSLPet'
APP=Path.home()/'Applications/DSLPet.app'
EVENTS=['request_received','thinking','tool_search','needs_clarification','task_completed','correction_received','user_stop','user_activity','interaction','show','hide','exit','pause','resume','preview','idle','controls','snapshot','notify','dismiss_notice','open_notice','activate_gpt','open_reply']
def status():
 try:
  d=json.loads((BASE/'status.json').read_text());os.kill(d['pid'],0)
  d['running']=time.time()-d['updated_at']<4;return d
 except (OSError,ValueError,KeyError):return {'running':False}
def ensure():
 if status().get('running'):return
 if not APP.exists():raise RuntimeError('Desktop app not installed at '+str(APP))
 subprocess.run(['/usr/bin/open',str(APP)],check=True)
 for _ in range(100):
  if status().get('running'):return
  time.sleep(.05)
 raise RuntimeError('Desktop app did not become ready')
def send(event,kind=None,action=None,**notice):
 if event not in EVENTS:raise ValueError('Unknown event')
 if kind not in [None,'thinking','research','mixed']:raise ValueError('Unknown kind')
 if event=='notify':validate_notice(notice)
 elif notice:raise ValueError('Notice fields require notify event')
 if event=='preview' and action not in [f'{i:02d}-{n}' for i,n in enumerate(['proud','unhappy','apology','toy-car','rice','yawn','idea','spin','dizzy','speechless','accept','think','research','question','result','revise','stop','doze','peek','bicycle','bicycle-exit','laptop','magnifier','ponder','count'],1)]:raise ValueError('Unknown action')
 ensure();commands=BASE/'commands';commands.mkdir(parents=True,exist_ok=True,mode=0o700)
 ident=uuid.uuid4().hex;name=f'{time.time_ns():020d}-{ident}.json';payload={'id':ident,'event':event}
 if kind:payload['kind']=kind
 if action:payload['action']=action
 payload.update(notice)
 temp=commands/(name+'.tmp');temp.write_text(json.dumps(payload));temp.chmod(0o600);temp.replace(commands/name)
 ack=BASE/('ack-'+name)
 for _ in range(80):
  if ack.exists():
   d=json.loads(ack.read_text());ack.unlink();return {'ack':d,'status':status()}
  time.sleep(.025)
 raise RuntimeError('Command acknowledgment timed out; command may remain queued')
def validate_notice(n):
 allowed={'title','message','thread_id','notice_kind','notice_id','show_bubble'}
 if set(n)-allowed:raise ValueError('Unknown notice field')
 for k,limit in [('title',120),('message',4000)]:
  if not isinstance(n.get(k),str) or not n[k].strip() or len(n[k])>limit:raise ValueError(f'{k} must be nonempty and <= {limit} characters')
 if n.get('notice_kind','info') not in ['completed','input','blocked','info']:raise ValueError('Unknown notice kind')
 if 'thread_id' in n:
  if not isinstance(n['thread_id'],str) or str(uuid.UUID(n['thread_id']))!=n['thread_id'].lower():raise ValueError('thread_id must be a canonical UUID')
 if 'notice_id' in n and (not isinstance(n['notice_id'],str) or not n['notice_id'] or len(n['notice_id'])>160):raise ValueError('Invalid notice_id')
 if 'show_bubble' in n and not isinstance(n['show_bubble'],bool):raise ValueError('show_bubble must be boolean')
def notify(title,message,thread_id=None,notice_kind='info',notice_id=None,show_bubble=True):
 n={'title':title,'message':message,'notice_kind':notice_kind,'show_bubble':show_bubble}
 if thread_id is not None:n['thread_id']=thread_id
 if notice_id is not None:n['notice_id']=notice_id
 return send('notify',**n)
def response(ident,result=None,error=None):
 d={'jsonrpc':'2.0','id':ident};d['error' if error else 'result']=error if error else result
 print(json.dumps(d,ensure_ascii=False),flush=True)
def mcp():
 for line in sys.stdin:
  try:
   req=json.loads(line);ident=req.get('id');method=req.get('method');params=req.get('params',{})
   if ident is None:continue
   if method=='initialize':response(ident,{'protocolVersion':params.get('protocolVersion','2024-11-05'),'capabilities':{'tools':{}},'serverInfo':{'name':'dsl-pet','version':'0.2.1'}})
   elif method=='ping':response(ident,{})
   elif method=='tools/list':response(ident,{'tools':[
    {'name':'dsl_pet_status','description':'Read local DSL desktop pet status. Does not observe chat events.','inputSchema':{'type':'object','properties':{},'additionalProperties':False},'annotations':{'readOnlyHint':True}},
    {'name':'dsl_pet_event','description':'Send a task lifecycle or interaction event to the user’s local DSL desktop pet. Launches it if needed.','inputSchema':{'type':'object','properties':{'event':{'type':'string','enum':[e for e in EVENTS if e!='notify']},'kind':{'type':'string','enum':['thinking','research','mixed']},'action':{'type':'string'}},'required':['event'],'additionalProperties':False},'annotations':{'destructiveHint':False,'openWorldHint':False}},
    {'name':'dsl_pet_notify','description':'Show a brief reply or task notification beside the local DSL pet. Supply the current local Codex thread ID to enable Open original conversation. Does not read chats or send chat messages. Use notice_id to update one notification without duplication.','inputSchema':{'type':'object','properties':{'title':{'type':'string','minLength':1,'maxLength':120},'message':{'type':'string','minLength':1,'maxLength':4000},'thread_id':{'type':'string','description':'Verified technical UUID of the local Codex conversation; omit if unknown.'},'notice_kind':{'type':'string','enum':['completed','input','blocked','info']},'notice_id':{'type':'string','minLength':1,'maxLength':160},'show_bubble':{'type':'boolean','default':True}},'required':['title','message'],'additionalProperties':False},'annotations':{'destructiveHint':False,'openWorldHint':False}}]})
   elif method=='tools/call':
    try:
     args=params.get('arguments',{});name=params.get('name')
     if name=='dsl_pet_status':r=status()
     elif name=='dsl_pet_event':r=send(**args)
     elif name=='dsl_pet_notify':r=notify(**args)
     else:raise ValueError('Unknown tool')
     response(ident,{'content':[{'type':'text','text':json.dumps(r,ensure_ascii=False)}],'isError':False})
    except Exception as e:response(ident,{'content':[{'type':'text','text':str(e)}],'isError':True})
   else:response(ident,error={'code':-32601,'message':'Method not found'})
  except Exception as e:
   print(str(e),file=sys.stderr)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--mcp',action='store_true');p.add_argument('event',nargs='?',default='status');p.add_argument('--kind');p.add_argument('--action');p.add_argument('--title');p.add_argument('--message');p.add_argument('--thread-id');p.add_argument('--notice-kind',default='info');p.add_argument('--notice-id');p.add_argument('--quiet',action='store_true');a=p.parse_args()
 if a.mcp:mcp()
 else:
  try:print(json.dumps(status() if a.event=='status' else (notify(a.title,a.message,a.thread_id,a.notice_kind,a.notice_id,not a.quiet) if a.event=='notify' else send(a.event,a.kind,a.action)),ensure_ascii=False,indent=2))
  except Exception as e:p.exit(1,str(e)+'\n')
