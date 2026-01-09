ZEN Mode Key Samples
====================

Place .ogg piano samples in this folder. Each sample plays when the corresponding
character is typed correctly in ZEN mode.

Expected Files:
---------------

LETTERS (lowercase):
a.ogg, b.ogg, c.ogg, d.ogg, e.ogg, f.ogg, g.ogg, h.ogg, i.ogg, j.ogg,
k.ogg, l.ogg, m.ogg, n.ogg, o.ogg, p.ogg, q.ogg, r.ogg, s.ogg, t.ogg,
u.ogg, v.ogg, w.ogg, x.ogg, y.ogg, z.ogg

GERMAN UMLAUTS:
ae.ogg (ä), oe.ogg (ö), ue.ogg (ü), ss.ogg (ß)

NUMBERS:
0.ogg, 1.ogg, 2.ogg, 3.ogg, 4.ogg, 5.ogg, 6.ogg, 7.ogg, 8.ogg, 9.ogg

PUNCTUATION:
space.ogg       (Space key)
enter.ogg       (Enter/Newline)
period.ogg      (.)
comma.ogg       (,)
colon.ogg       (:)
semicolon.ogg   (;)
exclamation.ogg (!)
question.ogg    (?)
dash.ogg        (- — –)
apostrophe.ogg  (' ')
quote.ogg       (" " „ « »)
paren_open.ogg  (()
paren_close.ogg ())
slash.ogg       (/)
ellipsis.ogg    (…)

FALLBACK:
default.ogg     (Played when no specific sample exists)

Notes:
------
- All samples should be short piano notes (0.5-2 seconds)
- Recommended: Different pitches for variety (C3-C5 range)
- Format: Ogg Vorbis (.ogg)
- Samples are preloaded for performance
- Uppercase letters use the same samples as lowercase

Mapping Logic:
--------------
1. Character is normalized to lowercase
2. Special characters are mapped to descriptive names
3. If no sample found, default.ogg is used
4. If no default.ogg, no sound plays (silent fallback)
