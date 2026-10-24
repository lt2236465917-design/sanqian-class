from pathlib import Path
import json,re,math
p=Path(__file__).parent

def lev(a,b):
 row=list(range(len(b)+1))
 for i,x in enumerate(a,1):
  nex=[i]
  for j,y in enumerate(b,1):nex.append(min(nex[-1]+1,row[j]+1,row[j-1]+(x!=y)))
  row=nex
 return row[-1]
def norm(s):return re.sub(r'\s','',s)
def box(t,w,h):
 vals=list(map(float,re.findall(r'=([^,)]+)',t['box'])))
 return [vals[0]*w,vals[1]*h,(vals[0]+vals[2])*w,(vals[1]+vals[3])*h]
def center(b):return ((b[0]+b[2])/2,(b[1]+b[3])/2)
def iou(a,b):
 inter=max(0,min(a[2],b[2])-max(a[0],b[0]))*max(0,min(a[3],b[3])-max(a[1],b[1]));return inter/((a[2]-a[0])*(a[3]-a[1])+(b[2]-b[0])*(b[3]-b[1])-inter)
summary={}
for name in ['old-contract','final-cold']:
 s=(p/(name+'.txt')).read_text();d=json.loads(s.split('result=',1)[1].split('\n')[0]);(p/(name+'.json')).write_text(json.dumps(d,ensure_ascii=False,indent=2))
 summary[name]={k:v for k,v in d.items() if k!='runs'};metrics=[]
 for row in d['runs']:
  gold=row['gold'];boxes=row['goldBoxes'];groups=[[] for _ in gold]; unmatched=[];valid=True
  for t in row['tokens']:
   if 'box' not in t:valid=False;continue
   b=box(t,row['width'],row['height']);cx,cy=center(b)
   distances=[math.hypot(max(g[0]-cx,0,cx-g[2]), max(g[1]-cy,0,cy-g[3])) for g in boxes];idx=min(range(len(gold)),key=lambda i:distances[i])
   if distances[idx]>250:unmatched.append(t['text'])
   else:groups[idx].append((b,t['text']))
   c=t.get('confidence');valid&=all(math.isfinite(v) for v in b) and b[0]>=0 and b[1]>=0 and b[2]<=row['width']+.01 and b[3]<=row['height']+.01 and b[2]>b[0] and b[3]>b[1]
   if name=='final-cold':valid&=isinstance(c,(int,float)) and math.isfinite(c) and 0<=c<=1
  fields=[]
  for expected,g,parts in zip(gold,boxes,groups):
   observed=''.join(v for _,v in sorted(parts,key=lambda x:x[0][0]));a=norm(expected);b=norm(observed)
   union=[min(v[0][0] for v in parts),min(v[0][1] for v in parts),max(v[0][2] for v in parts),max(v[0][3] for v in parts)] if parts else [0,0,0,0]
   fields.append({'expected':expected,'observed':observed,'edits':lev(a,b),'chars':len(a),'exact':a==b,'iou':round(iou(g,union),4)})
  total=sum(f['chars'] for f in fields);edits=sum(f['edits'] for f in fields)+sum(len(norm(t)) for t in unmatched)
  numbers=[f for f in fields if any(c.isdigit() for c in f['expected'])]
  metrics.append({'kind':row['kind'],'sha256':row['sha256'],'elapsedMs':row['elapsedMs'],'strictExact':sum(f['exact'] for f in fields),'fields':len(fields),'characterAccuracy':1-edits/total,'edits':edits,'characters':total,'numericExact':sum(f['exact'] for f in numbers),'numericTotal':len(numbers),'boxesIoU50':sum(f['iou']>=.5 for f in fields),'contractValid':valid,'unmatched':unmatched,'details':fields})
 summary[name]['metrics']=metrics
(p/'comparison.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2))
for name,d in summary.items():
 print(name,{k:d.get(k) for k in ['apkSha256','modelCacheBefore','initialPssKB','peakPssKB','cancelLatencyMs','invalidImageError']})
 for m in d['metrics']:print({k:v for k,v in m.items() if k not in ['details','sha256']})
