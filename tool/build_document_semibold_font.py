"""Build the PDF-only Inter 600 instance from Audyt's original UI font.

Requires fonttools[woff]. Existing regular/bold assets and UI font are unchanged.
"""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

fonts = Path(__file__).resolve().parents[1] / 'assets/fonts'
font = TTFont(fonts / 'Inter-Variable.woff2')
axes = {axis.axisTag: 600 if axis.axisTag == 'wght' else axis.defaultValue
        for axis in font['fvar'].axes}
font = instantiateVariableFont(font, axes, inplace=True)
font.flavor = None
names = {1: 'Inter', 2: 'SemiBold', 4: 'Inter SemiBold',
         6: 'Inter-SemiBold', 16: 'Inter', 17: 'SemiBold'}
for record in font['name'].names:
    if record.nameID in names:
        record.string = names[record.nameID].encode(record.getEncoding())
assert font['OS/2'].usWeightClass == 600
font.save(fonts / 'Inter-SemiBold.ttf')
