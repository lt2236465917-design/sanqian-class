"""Manual oracle from the five supplied images; no model output used as truth."""
import json,re,sys
from pathlib import Path
P=Path(__file__).parent
R=lambda a,b:list(range(a,b+1))
def meeting(day,weeks,start,end,room):return {'weekday':day,'weeks':weeks,'startMinute':start,'endMinute':end,'location':room}
def course(code,teacher,*meetings):return {'code':code,'teacher':teacher,'meetings':list(meetings)}
E={
'中国特色社会主义理论与实践研究':course('90001001','申坤',meeting(4,R(3,11),540,720,'三楼学术报告厅')),
'艺术意识形态分析':course('10121S102','韩子勇',meeting(5,R(5,8),810,990,'6408')),
'中国艺术史':course('90001003','杨明刚',meeting(1,[3,4]+R(6,11),810,990,'6406')),
'艺术美学':course('90001005','孙伟科',meeting(2,[3,4]+R(6,11),810,990,'6406')),
'导师课':course('90001011',None),
'硕士英语(全日制学术型)':course('S90001014','林敬和,刘先福',meeting(2,[3,4],540,720,'第五会议室'),meeting(2,R(6,10)+[12],540,720,'6310')),
'曲艺学导论':course('30101009','吴文科',meeting(1,[4,6],1140,1290,'6401教室'),meeting(2,[4],1140,1290,'6401教室'),meeting(3,[4],1140,1290,'6401教室')),
'艺术人类学理论与沿革专题研究':course('10118B103',None,meeting(3,[3,4,6,7],810,990,'6408')),
'黑白摄影暗房工艺基础':course('49106104','张涛',*(meeting(d,[5],s,e,'虚拟教室1') for d in [6,7] for s,e in [(540,720),(810,990)])),
'保护非物质文化遗产政策法规解读专题':course('10121S104',None,meeting(3,R(6,13),540,720,'6607')),
'艺术跨学科理论前沿':course('10118s300',None,meeting(5,R(14,17),810,990,'虚拟教室3')),
'非物质文化遗产概论':course('10118s105',None,meeting(1,R(6,13),540,720,'6607')),
'非物质文化遗产保护理论与实践专题':course('10118s106',None,meeting(3,R(9,12),810,990,'6408')),
'思政大讲堂：形势与政策':course('90001020',None),
'中国美学史专题':course(None,'李修建,杨明刚',meeting(1,R(6,13),540,720,'6408')),
'经济学':course(None,'周泓洋',meeting(3,[3,4]+R(6,11),810,990,'6606')),
'文旅投融资与艺术经济':course(None,'周泓洋',meeting(3,R(12,15),810,990,'6606')),
'艺术机构运营':course(None,'张朝霞',meeting(4,R(5,8),810,990,'6607')),
}
def norm(s):return re.sub(r'\s+','',s or '').replace('（','(').replace('）',')').replace('，',',').replace('：',':')
def room(s):return norm(s).replace('(主校区)','').replace('自排教室:','')
def occ(c):return {(m['weekday'],w,m['startMinute'],m['endMinute'],room(m['location'])) for m in c['meetings'] for w in m.get('weeks') or []}
def verify(path,portal=False):
 expected=dict(E)
 if portal:
  expected={k:dict(v) for k,v in list(E.items())[:14]}
  for name,teacher in [('艺术人类学理论与沿革专题研究','方李莉'),('保护非物质文化遗产政策法规解读专题','葛玉清'),('非物质文化遗产概论','罗微'),('非物质文化遗产保护理论与实践专题','郑长铃')]:expected[name]['teacher']=teacher
 actual=json.loads(Path(path).read_text());byname={norm(c['name']):c for c in actual};errors=[]
 if len(byname)!=len(actual):errors.append('Duplicate course names')
 if set(byname)!={norm(x) for x in expected}:errors.append('Course set mismatch')
 for name,exp in expected.items():
  c=byname.get(norm(name))
  if c is None:continue
  if norm(c.get('teacher'))!=norm(exp['teacher']):errors.append(f'{name}: teacher {c.get("teacher")} != {exp["teacher"]}')
  if norm(c.get('courseCode')).lower()!=norm(exp['code']).lower():errors.append(f'{name}: code {c.get("courseCode")} != {exp["code"]}')
  if str(c.get('section'))!='1':errors.append(f'{name}: section {c.get("section")} != 1')
  a,b=occ(c),occ(exp)
  if a!=b:errors.append(f'{name}: extra={a-b} missing={b-a}')
  total=sum(len(m.get('weeks') or []) for m in c['meetings'])
  if total!=len(a):errors.append(f'{name}: duplicate occurrences')
  if not exp['meetings'] and (c['meetings'] or not c.get('pendingReason')):errors.append(f'{name}: pending invalid')
 result={'file':str(Path(path).name),'source':'portal' if portal else 'photos','courses':len(actual),'occurrences':sum(len(occ(c)) for c in actual),'pending':sum(not c['meetings'] for c in actual),'teachers':sum(bool(c.get('teacher')) for c in actual),'errors':errors,'passed':not errors}
 return result
if __name__=='__main__':
 results=[verify(P/name,'portal' in name) for name in sys.argv[1:]]
 print(json.dumps(results,ensure_ascii=False,indent=2))
 sys.exit(any(not r['passed'] for r in results))
