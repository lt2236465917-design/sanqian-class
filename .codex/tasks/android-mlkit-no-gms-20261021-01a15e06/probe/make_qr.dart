import 'dart:io';
import 'dart:convert';
import 'package:zxing2/qrcode.dart';
import 'package:image/image.dart' as img;
void main(List<String> args) {
  final fixture=jsonDecode(File(args[1]).readAsStringSync());
  final data=fixture['encoded'] as String;
  final qr=Encoder.encode(data,ErrorCorrectionLevel.m).matrix!;
  const scale=10,quiet=4; final side=(qr.width+quiet*2)*scale;
  final out=img.Image(width:side,height:side); img.fill(out,color:img.ColorRgb8(255,255,255));
  for(var y=0;y<qr.height;y++) for(var x=0;x<qr.width;x++) if(qr.get(x,y)==1) img.fillRect(out,x1:(x+quiet)*scale,y1:(y+quiet)*scale,x2:(x+quiet+1)*scale-1,y2:(y+quiet+1)*scale-1,color:img.ColorRgb8(0,0,0));
  File(args[0]).writeAsBytesSync(img.encodePng(out));
  final frame=img.Image(width:1800,height:1800); img.fill(frame,color:img.ColorRgb8(255,255,255)); img.compositeImage(frame,out,dstX:200,dstY:(1800-side)~/2); File(args[2]).writeAsBytesSync(img.encodePng(frame));
  print('Synthetic QR generated: $side px, ${data.length} chars');
}
