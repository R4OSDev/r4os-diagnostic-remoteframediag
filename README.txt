RFDIAG.R4X
==========

RFDIAG prueft den R4DESK-Remote-Frame-Vertrag. Das Programm liest den zuletzt
vom Desktop veroeffentlichten XRGB32-Snapshot, prueft Geometrie, Revision,
Dirty-Rect, Cursorstatus und chunkweises Lesen und meldet `RFDIAG result: OK`.

RFDIAG erzeugt keine eigenen Desktop-Pixel. Es ist ein externer Konsument des
oeffentlichen R4DESK-Vertrags und dient als Abnahmegrundlage fuer RDPSVC.
