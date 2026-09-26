"""Derive 07/90/1 from the accepted 30 calendar, preserving its frame and zero.
New digits use the source's 30-unit stroke and rounded caps; original untouched.
"""
from pathlib import Path
from xml.etree import ElementTree as ET
from copy import deepcopy
r=Path(__file__).resolve().parents[1]/'assets/icons/small'
ET.register_namespace('', 'http://www.w3.org/2000/svg')
ns='{http://www.w3.org/2000/svg}'
source=ET.parse(r/'067-month-clock.svg').getroot()
frame,three,zero=list(source[0])
for number,name in [('07','083-seven-days.svg'),('90','084-all-statement-days.svg'),('1','088-calendar-one.svg')]:
 svg=deepcopy(source);group=svg[0];group.clear();group.append(deepcopy(frame))
 if number=='07':
  first=deepcopy(zero);first.set('transform','translate(-124 0)');group.append(first)
  ET.SubElement(group,ns+'path',{'d':'M274 267 H358 L294 407','fill':'none','stroke':'#000','stroke-width':'30','stroke-linecap':'round','stroke-linejoin':'round'})
 elif number=='90':
  # The 9 has the same oval bowl, 30-unit weight and baseline as the source 0.
  ET.SubElement(group,ns+'path',{'fill-rule':'evenodd','d':'M192.103 252 C162.384 252 138.206 276.178 138.206 305.897 C138.206 335.616 162.384 359.794 192.103 359.794 C200.691 359.794 208.813 357.769 216 354.171 V368.103 C216 381.28 205.28 392 192.103 392 C181.775 392 172.62 385.4 169.4 375.6 C166.8 367.7 158.3 363.5 150.5 366.1 C142.6 368.7 138.4 377.2 141 385 C148.2 407.1 168.7 422 192.103 422 C221.822 422 246 397.822 246 368.103 V305.897 C246 276.178 221.822 252 192.103 252 Z M192.103 282 C205.28 282 216 292.72 216 305.897 C216 319.074 205.28 329.794 192.103 329.794 C178.926 329.794 168.206 319.074 168.206 305.897 C168.206 292.72 178.926 282 192.103 282 Z'})
  group.append(deepcopy(zero))
 else:
  # A centered 1 keeps the source digits' rounded 30-unit weight and baseline.
  ET.SubElement(group,ns+'path',{'d':'M232 282 L256 267 V407 M232 407 H280','fill':'none','stroke':'#000','stroke-width':'30','stroke-linecap':'round','stroke-linejoin':'round'})
 ET.ElementTree(svg).write(r/name,encoding='utf-8',xml_declaration=True)
