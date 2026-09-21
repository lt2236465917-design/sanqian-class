// Offline executable; excluded from the production build by default.
// swiftc -D PORTAL_OFFLINE_TESTS SchoolPortalModels.swift SchoolScheduleParser.swift SchoolPortalParserTests.swift -o /tmp/school-portal-tests
#if PORTAL_OFFLINE_TESTS
import Foundation

@main
struct SchoolPortalParserTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError("FAIL: \(message)") }
    }
    static func table(_ rows: [[SchoolPortalTableCell]], url: String = "https://school.example/table?ticket=SECRET#token") -> SchoolPortalFrameMessage {
        SchoolPortalFrameMessage(version: 1, kind: "scheduleTables", requestID: "request", frame: SchoolPortalFrameIdentity(url: url, securityOrigin: "https://school.example", isMainFrame: false), title: "", innerText: "", html: "", rows: rows)
    }
    static func parse(_ meeting: String) -> [SchoolScheduleDraft] {
        SchoolScheduleParser.parse(message: table([
            [SchoolPortalTableCell(text: "课程名称"), SchoolPortalTableCell(text: "上课时间")],
            [SchoolPortalTableCell(text: "英语"), SchoolPortalTableCell(text: meeting)]
        ])).drafts
    }
    static func main() throws {
        let html = """
        <table><tr><th>课程编号</th><th>课程名称</th><th>上课时间</th><th>上课地点</th><th>任课教师</th></tr>
        <tr><td rowspan="2">ART-01</td><td rowspan="2">摄影</td><td>周六 1-4,6-10,12-16周 08:00-09:40</td><td>教室A</td><td>李老师</td></tr>
        <tr><td>周六 5,11周 13:30-15:10</td><td>教室B</td><td>李老师</td></tr>
        <tr><td></td><td>导师课</td><td>待定</td><td></td><td></td></tr></table>
        """
        let result = SchoolScheduleParser.parseHTML(html, sourceURL: URL(string: "https://school.example/t?ticket=SECRET#SECRET"))
        check(result.drafts.count == 3, "rowspan maintains two arrangements plus pending course")
        check(result.drafts[0].title == "摄影" && result.drafts[1].courseCode == "ART-01", "rowspan aligns code and name")
        check(result.drafts[0].weeks?.contains(5) == false && result.drafts[0].weeks?.contains(11) == false, "gap weeks survive")
        check(result.drafts[1].weeks == [5,11] && result.drafts[1].location == "教室B", "room-specific weeks survive")
        check(result.drafts[2].title == "导师课" && result.drafts[2].isPending, "pending course remains")
        check(result.sourceURL == "https://school.example/t", "result URL excludes SSO query and fragment")
        check(result.drafts.allSatisfy { !($0.sourceURL?.contains("SECRET") ?? false) }, "draft URL excludes SSO query")

        let periods = parse("周一 第1-2节")
        check(periods[0].weekday == 1 && periods[0].weeks == nil, "period range is not a week range")
        check(periods[0].startMinutes == nil && periods[0].endMinutes == nil, "periods never fabricate clock minutes")
        check(periods[0].startPeriod == 1 && periods[0].endPeriod == 2, "period indices survive structurally")
        let partial = parse("周四 08:00-09:40")[0]
        check(partial.weekday == 4 && partial.startMinutes == 480 && partial.endMinutes == 580 && partial.weeks == nil, "known fields survive missing weeks")
        check(parse("1-16周 08:00-09:40")[0].weekday == nil, "unknown weekday remains nil")
        check(parse("周一 1-16周 08:99-10:00")[0].startMinutes == nil, "invalid minute rejected")
        check(parse("周一 1-16周 23:00-24:00")[0].endMinutes == nil, "1440 end rejected")
        check(parse("周一 1-16周 10:00-08:00")[0].startMinutes == nil, "reversed clock rejected")
        check(parse("周一 16-1周 08:00-09:00")[0].weeks == nil, "reversed weeks rejected")
        check(parse("周一 1-16周(单) 08:00-09:00")[0].weeks == [1,3,5,7,9,11,13,15], "odd weeks retained")
        let multiple = parse("周一 1-4周 08:00-09:00；周四 5-8周 13:00-14:00")
        check(multiple.count == 2 && multiple[0].weekday == 1 && multiple[1].weekday == 4, "multiple arrangements retained")
        let unseparated = parse("周一 1-4周 08:00-09:00 周四 5-8周 13:00-14:00")
        check(unseparated.count == 2 && unseparated[1].startMinutes == 780, "weekday starts second arrangement")

        let sameDay = parse("周一 1-4周 08:00-09:00 13:00-14:00")
        check(sameDay.count == 2 && sameDay[1].startMinutes == 780, "same weekday multiple clocks retained")
        let mergedGrid = table([
            [SchoolPortalTableCell(text: "时间"), SchoolPortalTableCell(text: "周一"), SchoolPortalTableCell(text: "周二")],
            [SchoolPortalTableCell(text: "08:00-09:00"), SchoolPortalTableCell(text: "英语\n1-4周", rowSpan: 2), SchoolPortalTableCell(text: "")],
            [SchoolPortalTableCell(text: "09:10-10:00"), SchoolPortalTableCell(text: "")]
        ])
        let mergedResult = SchoolScheduleParser.parse(message: mergedGrid)
        check(mergedResult.drafts.count == 1 && mergedResult.drafts[0].isPending && mergedResult.drafts[0].startMinutes == nil, "merged duration is not fabricated from a single row")
        let expanded = SchoolScheduleParser.expand([
            [SchoolPortalTableCell(text: "横跨", colSpan: 2), SchoolPortalTableCell(text: "尾")],
            [SchoolPortalTableCell(text: "跨行", rowSpan: 2), SchoolPortalTableCell(text: "B")],
            [SchoolPortalTableCell(text: "C")]
        ])
        check(expanded[0] == ["横跨","横跨","尾"] && expanded[2][0] == "跨行" && expanded[2][1] == "C", "rowspan and colspan matrix restored")
        let grid = table([
            [SchoolPortalTableCell(text: "时间"), SchoolPortalTableCell(text: "周一"), SchoolPortalTableCell(text: "周二")],
            [SchoolPortalTableCell(text: "08:00-09:40"), SchoolPortalTableCell(text: "英语\n1-4周"), SchoolPortalTableCell(text: "导师课")]
        ])
        let gridResult = SchoolScheduleParser.parse(message: grid)
        check(gridResult.drafts.count == 2 && gridResult.drafts[0].title == "英语", "grid keeps line title")
        check(gridResult.drafts.contains { $0.title == "英语" && $0.weeks == [1,2,3,4] && $0.startMinutes == 480 }, "grid row clock used with weeks")
        check(gridResult.drafts.contains { $0.title == "导师课" && $0.weekday == 2 && $0.weeks == nil }, "grid partial fields preserved")
        check(SchoolScheduleParser.parseHTML("<form><input type='password' value='SECRET'></form>").drafts.isEmpty, "login page produces no drafts")

        let encoded = try JSONEncoder().encode(grid)
        let body = try JSONSerialization.jsonObject(with: encoded)
        check(SchoolPortalFrameMessage(body: body)?.rows[1][1].text == "英语\n1-4周", "JS canonical text rowSpan colSpan contract decodes")
        struct Envelope: Encodable { let tables: [SchoolPortalFrameMessage]; let frameCount: Int; let url: String }
        let envelope = Envelope(tables: [grid,grid], frameCount: 2, url: "https://school.example/t?ticket=SECRET")
        let aggregate = SchoolScheduleParser.parseExtractionJSON(try JSONEncoder().encode(envelope))!
        check(aggregate.drafts.count == 2 && aggregate.frameCount == 2, "frame aggregation deduplicates identical arrangements")
        let hosts: Set<String> = ["school.example"]
        check(SchoolPortalSecurity.allows(scheme: "https", host: "school.example", allowedHosts: hosts), "exact HTTPS host allowed")
        check(!SchoolPortalSecurity.allows(scheme: "http", host: "school.example", allowedHosts: hosts), "HTTP blocked")
        check(!SchoolPortalSecurity.allows(scheme: "https", host: "other.school.example", allowedHosts: hosts), "unlisted subdomain blocked")
        check(!SchoolPortalSecurity.allows(scheme: "https", host: "school.example.evil.test", allowedHosts: hosts), "suffix spoof blocked")
        check(SchoolPortalSecurity.sanitizedURL(URL(string: "https://name:pass@school.example/t?ticket=SECRET#token")) == "https://school.example/t", "credentials stripped from URL")
        // Original tables must remain available when rules cannot parse them.
        let unsupported = table([
            [SchoolPortalTableCell(text: "科目"), SchoolPortalTableCell(text: "安排")],
            [SchoolPortalTableCell(text: "艺术原文课程"), SchoolPortalTableCell(text: "3,4周一-下午课-6406")]
        ])
        let fallback = SchoolScheduleParser.parse(message: unsupported)
        check(fallback.drafts.isEmpty && fallback.canReview, "unparsed timetable can reach AI review")
        let originalTables = try JSONDecoder().decode([[[SchoolPortalTableCell]]].self, from: Data(fallback.timetableText!.utf8))
        check(originalTables == [unsupported.rows], "AI input retains original cells including unparsed arrangements")
        check(!fallback.timetableText!.contains("SECRET") && !fallback.timetableText!.contains("https"), "AI source never contains frame URL or SSO query")
        let combined = SchoolScheduleParser.parse(tables: [unsupported, grid, unsupported])
        let combinedTables = try JSONDecoder().decode([[[SchoolPortalTableCell]]].self, from: Data(combined.timetableText!.utf8))
        check(combinedTables.count == 2 && combinedTables.contains(unsupported.rows), "partial parser success retains other unparsed tables and deduplicates sources")
        let mergedSource = try JSONDecoder().decode([[[SchoolPortalTableCell]]].self, from: Data(mergedResult.timetableText!.utf8))
        check(mergedSource[0][1][1].rowSpan == 2, "AI source keeps original merged-cell structure")
        let nonTimetable = table([[SchoolPortalTableCell(text: "个人中心")], [SchoolPortalTableCell(text: "欢迎登录")]])
        check(!SchoolScheduleParser.parse(message: nonTimetable).canReview, "personal center cannot become an empty AI import")
        for sensitive in ["学号 123456", "密码 SECRET", "https://example.test/?ticket=SECRET", "Cookie: SECRET", "<input value=SECRET>"] {
            let unsafe = table([unsupported.rows[0], [SchoolPortalTableCell(text: sensitive), SchoolPortalTableCell(text: "待定")]])
            let rejected = SchoolScheduleParser.parse(message: unsafe)
            check(rejected.timetableText == nil && !rejected.canReview, "unsafe source text does not cross into AI review")
        }
        var clipped = unsupported
        clipped.truncated = true
        check(!SchoolScheduleParser.parse(message: clipped).canReview, "clipped raw timetable is not sent as complete input")
        let oversized = table([unsupported.rows[0], [SchoolPortalTableCell(text: String(repeating: "课", count: 24000)), SchoolPortalTableCell(text: "待定")]])
        check(SchoolScheduleParser.parse(message: oversized).timetableText == nil, "oversized source rejected without prefix truncation")
        if CommandLine.arguments.count > 1 {
            let data: Data
            if CommandLine.arguments[1].hasSuffix(".swift") {
                let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
                let script = source.components(separatedBy: "static func extractionScript")[1].components(separatedBy: "+ #\"\"\"")[1].components(separatedBy: "\"\"\"#")[0]
                let literal = String(decoding: try JSONEncoder().encode(script), as: UTF8.self)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["node", "-e", "const production = " + literal + ";\n" + javascriptHarness]
                let output = Pipe()
                process.standardOutput = output
                try process.run()
                data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                check(process.terminationStatus == 0, "production JS privacy/protocol/relay/fallback assertions")
            } else {
                data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            }
            let message = try JSONDecoder().decode(SchoolPortalFrameMessage.self, from: data)
            check(message.rows[1][0].text == "摄影", "production JS message decoded by Swift")
            let parsed = SchoolScheduleParser.parse(message: message)
            check(parsed.drafts.count == 1 && parsed.drafts[0].startMinutes == 480, "production JS payload produces draft")
            check(parsed.timetableText?.contains("摄影") == true, "production JS original cells reach AI material")
            let serialized = String(decoding: try JSONEncoder().encode(parsed), as: UTF8.self)
            check(!serialized.contains("SECRET"), "JS-to-Swift output excludes secret fixture")
        }
        print("PASS: \(checks) offline parser/security assertions")
    }
    private static let javascriptHarness = #"""
const vm=require('vm'),fs=require('fs'),assert=require('assert');

const results=[]; let removals=0;
function cell(text,secret='') {
  return {getAttribute:()=>null, cloneNode:()=>({textContent:text+secret,
    querySelectorAll(selector) {const clone=this; return secret && selector.includes('input') ? [{remove(){clone.textContent=text;removals++;}}] : [];}})};
}
const courseTable={querySelector:()=>null,rows:[
  {cells:[cell('课程名称'),cell('上课时间')]},
  {cells:[cell('摄影','SECRET-INPUT'),cell('周一 1-4周 08:00-09:40')]}
]};
function frame(host, tables=[]) {
  let listener;
  const location={protocol:'https:',hostname:host,origin:'https://'+host,pathname:'/t',href:'https://'+host+'/t?ticket=SECRET-URL'};
  const window={frames:[],top:{},webkit:{messageHandlers:{customHandler:{postMessage:data=>results.push(data)}}},addEventListener:(name,callback)=>{listener=callback;}};
  const ctx={window,location,document:{querySelectorAll:()=>tables},URL,Set,Array,String,Math,Number,parseInt,
    sanqianAllowedHosts:['a.school.test','b.school.test','c.school.test'],sanqianHandler:'customHandler'};
  vm.runInNewContext(production,ctx);
  return {window,deliver:(data,origin)=>listener?.({data,origin})};
}
const a=frame('a.school.test'), b=frame('b.school.test'), c=frame('c.school.test',[courseTable]);
a.window.frames=[{postMessage(data){b.deliver(data,'https://a.school.test')}}];
b.window.frames=[{postMessage(data){c.deliver(data,'https://b.school.test')}}];
const request={sanqianSchedule:'extract',requestID:'12345678-1234-1234-1234-123456789012'};
a.deliver(request,'https://a.school.test');
assert.equal(results.length,3,'cross-origin nested frame relay and empty acknowledgements');
const table=results.find(x=>x.rows.length);
assert.equal(table.rows[1][0].text,'摄影');
assert.equal(table.rows[1][0].rowSpan,1);assert.equal(table.rows[1][0].colSpan,1);
assert.equal(table.html,'');assert.equal(table.frame.url,'https://c.school.test/t');
assert(!JSON.stringify(results).includes('SECRET'));assert.equal(removals,1);
a.deliver(request,'https://a.school.test');assert.equal(results.length,3,'same request not reported twice');
a.deliver({...request,requestID:'99945678-1234-1234-1234-123456789012'},'https://evil.test');assert.equal(results.length,3,'foreign sender rejected');
const evil=frame('evil.test',[courseTable]);evil.deliver(request,'https://a.school.test');assert.equal(results.length,3,'unlisted frame never installs listener');
const unknownTable={querySelector:()=>null,rows:[{cells:[cell('科目'),cell('安排')]},{cells:[cell('艺术原文课程'),cell('3,4周一-下午课-6406')]}]};
frame('c.school.test',[unknownTable]).deliver(request,'https://a.school.test');
assert.equal(results.at(-1).rows[1][0].text,'艺术原文课程','unparsed timetable is retained');
assert.equal(results.at(-1).truncated,false);
const largeTable={querySelector:()=>null,rows:[courseTable.rows[0],{cells:[cell('长课表'),cell('课'.repeat(2100))]}]};
frame('c.school.test',[largeTable]).deliver(request,'https://a.school.test');
assert.equal(results.at(-1).truncated,true,'source truncation is explicit');
assert.equal(results.at(-1).rows[1][1].text.length,2000);
process.stdout.write(JSON.stringify(table));
"""#

}
#endif
