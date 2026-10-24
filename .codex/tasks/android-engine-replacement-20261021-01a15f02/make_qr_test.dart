import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:zxing2/qrcode.dart';
import 'package:image/image.dart' as img;
import 'package:sanqian_class/Pages/Share/qr_payload_codec.dart';
void main() { test("generate synthetic QR fixtures", () => generate([".codex/tasks/android-engine-replacement-20261021-01a15f02/qr"])); }
void generate(List<String> args) {
 final dir=Directory(args[0]);dir.createSync(recursive:true);
 final payload=QrPayloadCodec.buildSchedulePayload(tableName:'引擎验收合成课表',tableData:'{"semester_start_monday":"2026-10-19"}',courseRows:List.generate(3,(i)=>{
  'name':['高等数学','大学英语','大学物理'][i], 'classroom':['教学楼A101','文科楼B203','实验楼C305'][i], 'teacher':['张老师','李老师','王老师'][i],
  'weeks':'[1,2,3,4]','week_time':i+1,'start_time':i*2+1,'time_count':2,'class_number':'SYN${i+1}', 'info':'合成验收样本，非用户真实课表',
 }));
 final encoded=QrPayloadCodec.encodePayload(payload);
 final multi=QrPayloadCodec.buildFramesFromEncodedPayload(encoded,maxPartLength:300);
 final frames=['ncs://qr/v2/s/$encoded',...multi];
 File('${dir.path}/gold.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert({'synthetic':true,'payload':payload,'frames':frames}));
 for(var i=0;i<frames.length;i++){
  final qr=Encoder.encode(frames[i],ErrorCorrectionLevel.m).matrix!;const scale=5,quiet=4;final side=(qr.width+quiet*2)*scale;
  final out=img.Image(width:side,height:side);img.fill(out,color:img.ColorRgb8(255,255,255));
  for(var y=0;y<qr.height;y++)for(var x=0;x<qr.width;x++)if(qr.get(x,y)==1)img.fillRect(out,x1:(x+quiet)*scale,y1:(y+quiet)*scale,x2:(x+quiet+1)*scale-1,y2:(y+quiet+1)*scale-1,color:img.ColorRgb8(0,0,0));
  File('${dir.path}/qr-$i.png').writeAsBytesSync(img.encodePng(out));
  final camera=img.Image(width:1800,height:1800);img.fill(camera,color:img.ColorRgb8(255,255,255));img.compositeImage(camera,out,dstX:200,dstY:(1800-side)~/2);
  File('${dir.path}/camera-$i.png').writeAsBytesSync(img.encodePng(camera));
 }
 print('${frames.length} frames (single + ${multi.length} multipart), encoded ${encoded.length} chars');
}
