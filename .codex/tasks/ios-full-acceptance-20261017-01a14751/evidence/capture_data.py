import pathlib,sqlite3,json,sys,subprocess,plistlib
root=pathlib.Path(__file__).parent
sim="FBC49642-E3AF-4E73-952A-DAE24EEE8E35"
base=pathlib.Path.home()/"Library/Developer/CoreSimulator/Devices"/sim/"data"
a=pathlib.Path(subprocess.check_output(["xcrun","simctl","get_app_container",sim,"love.sanqian.schedule","data"],text=True).strip())
def query(p,q):
 c=sqlite3.connect("file:"+str(p)+"?mode=ro",uri=True);c.row_factory=sqlite3.Row
 return [dict(r) for r in c.execute(q)]
cal=base/"Library/Calendar/Calendar.sqlitedb"
out={"courses":query(a/"Documents/course.db","select * from Course"),"tables":query(a/"Documents/course.db","select * from CourseTable"),"calendars":query(cal,"select ROWID,title,UUID from Calendar"),"events":query(cal,"select ROWID,summary,description,start_date,end_date,calendar_id,UUID from CalendarItem"),"alarms":query(cal,"select ROWID,trigger_interval,calendaritem_owner_id,disabled from Alarm"),"widget":[]}
for p in base.glob("Containers/Shared/AppGroup/*/personal-schedule.json"):out["widget"].append(json.loads(p.read_text()))
pref=a/"Library/Preferences/love.sanqian.schedule.plist"
if pref.exists():
 d=plistlib.loads(pref.read_bytes());out["preferences"]={k:v for k,v in d.items() if any(x in k.lower() for x in ["calendar","remind","tableid","appearance"])}
(root/(sys.argv[1]+".json")).write_text(json.dumps(out,ensure_ascii=False,indent=2,default=str))
print({"courses":len(out["courses"]),"tables":out["tables"],"calendars":out["calendars"],"events":len(out["events"]),"alarms":len(out["alarms"]),"alarmOffsets":sorted(set(a["trigger_interval"] for a in out["alarms"] if a["trigger_interval"] is not None)),"widgetOccurrences":[len(w["occurrences"]) for w in out["widget"]]})
