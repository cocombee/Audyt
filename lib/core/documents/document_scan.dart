import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:dartcv4/dartcv.dart' as cv;
import 'document_optimization.dart';

/// Normalized clockwise corners: top-left, top-right, bottom-right, bottom-left.
typedef ScanCorners = List<(double, double)>;
final class DocumentScan {
  static Future<ScanCorners?> detect(Uint8List bytes) => Isolate.run(() {
    final source = cv.imdecode(bytes, cv.IMREAD_COLOR);
    if (source.isEmpty) throw const FormatException('Unable to read image.');
    final scale = 900 / math.max(source.cols, source.rows);
    final small = cv.resize(source, ((source.cols * math.min(1, scale)).round(), (source.rows * math.min(1, scale)).round()));
    final gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
    final blur = cv.gaussianBlur(gray, (5, 5), 0);
    final edges = cv.canny(blur, 40, 120);
    ScanCorners? best; double bestArea = small.cols * small.rows * .15;
    final masks=<cv.Mat>[edges];
    final kernel=cv.getStructuringElement(cv.MORPH_RECT,(9,9));
    for(final level in [140.0,170.0,200.0,225.0]) {
      final (_,mask)=cv.threshold(blur,level,255,cv.THRESH_BINARY);
      masks.add(cv.morphologyEx(mask,cv.MORPH_CLOSE,kernel)); mask.dispose();
    }
    kernel.dispose();
    for(final mask in masks) {
    final (contours, hierarchy) = cv.findContours(mask, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
    for (final contour in contours) {
      final polygon = cv.approxPolyDP(contour, cv.arcLength(contour, true) * .025, true);
      final area = cv.contourArea(polygon).abs();
      if (polygon.length == 4 && area > bestArea && cv.isContourConvex(polygon)) {
        final points = polygon.map((p) => (p.x / small.cols, p.y / small.rows)).toList();
        final cx = points.fold<double>(0, (v,p)=>v+p.$1)/4, cy = points.fold<double>(0,(v,p)=>v+p.$2)/4;
        points.sort((a,b)=>math.atan2(a.$2-cy,a.$1-cx).compareTo(math.atan2(b.$2-cy,b.$1-cx)));
        var first = 0;
        for(var i=1;i<4;i++) { if(points[i].$1+points[i].$2 < points[first].$1+points[first].$2) first=i; }
        final ordered=List.generate(4,(i)=>points[(first+i)%4]);
        // A printed border has light paper on both sides; require evidence of
        // a paper/background boundary on at least three edges.
        var boundaries=0;
        if(ordered.any((p)=>p.$1<.01||p.$1>.99||p.$2<.01||p.$2>.99)) { polygon.dispose(); continue; }
        for(var i=0;i<4;i++) {
          final a=ordered[i],b=ordered[(i+1)%4];
          final dx=(b.$1-a.$1)*small.cols,dy=(b.$2-a.$2)*small.rows;
          final len=math.sqrt(dx*dx+dy*dy),nx=-dy/len,ny=dx/len;
          double value(double x,double y)=>gray.atU8(y.round().clamp(0,gray.rows-1),i1:x.round().clamp(0,gray.cols-1)).toDouble();
          var supported=0;
          for(final t in [.15,.3,.5,.7,.85]) {
            final x=(a.$1+(b.$1-a.$1)*t)*small.cols,y=(a.$2+(b.$2-a.$2)*t)*small.rows;
            if(value(x+nx*8,y+ny*8)-value(x-nx*8,y-ny*8)>15) supported++;
          }
          if(supported>=4) boundaries++;
        }
        if(boundaries==4) { best=ordered; bestArea=area; }
      }
      polygon.dispose();
    }
    hierarchy.dispose(); contours.dispose();
    }
    for(final mask in masks) { mask.dispose(); }
    blur.dispose(); gray.dispose(); small.dispose(); source.dispose();
    return best;
  });

  static Future<Uint8List> rectify(Uint8List bytes, ScanCorners corners, {bool clean = false}) => Isolate.run(() {
    if(corners.length != 4) throw const FormatException('Choose four corners.');
    var sign=0.0;
    for(var i=0;i<4;i++) {
      final a=corners[i],b=corners[(i+1)%4],c=corners[(i+2)%4];
      final cross=(b.$1-a.$1)*(c.$2-b.$2)-(b.$2-a.$2)*(c.$1-b.$1);
      if(cross.abs()<.0001 || (sign!=0 && sign*cross<0)) throw const FormatException('Corners must form a non-crossing rectangle.');
      sign=cross;
    }
    final src=cv.imdecode(bytes,cv.IMREAD_COLOR);
    final pts=corners.map((p)=>cv.Point2f(p.$1*(src.cols-1),p.$2*(src.rows-1))).toList();
    double distance(int a,int b)=>math.sqrt(math.pow(pts[a].x-pts[b].x,2)+math.pow(pts[a].y-pts[b].y,2));
    final w=math.max(distance(0,1),distance(3,2)).round().clamp(2,src.cols+src.rows);
    final h=math.max(distance(0,3),distance(1,2)).round().clamp(2,src.cols+src.rows);
    final size=a4OutputSize(w,h);
    final from=cv.VecPoint2f.fromList(pts),to=cv.VecPoint2f.fromList([cv.Point2f(0,0),cv.Point2f(size.width-1.0,0),cv.Point2f(size.width-1.0,size.height-1.0),cv.Point2f(0,size.height-1.0)]);
    final matrix=cv.getPerspectiveTransform2f(from,to);
    final warped=cv.warpPerspective(src,matrix,(size.width,size.height));
    cv.Mat result=warped;
    if(clean) {
      final background=cv.gaussianBlur(warped,(0,0),25);
      final normalized=cv.divide(warped,background,scale:255);
      result=normalized.convertTo(cv.MatType.CV_8UC3,alpha:1.03,beta:-2);
      normalized.dispose(); background.dispose();
    }
    final (ok,encoded)=cv.imencode('.png',result);
    if(clean) result.dispose(); warped.dispose();matrix.dispose();from.dispose();to.dispose();src.dispose();
    if(!ok) throw const FormatException('Unable to prepare scan.');
    return encoded;
  });
}
