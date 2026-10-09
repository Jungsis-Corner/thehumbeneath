THE HUM BENEATH - ein Dungeon-Abenteuer fuer den Sinclair QL
=============================================================
(English version below)

Vier junge Katzen folgen einem tiefen Summen unter dem Moor: ein
rundenbasiertes Rollenspiel in der Ich-Perspektive, Schritt fuer Schritt
durch acht Ebenen. Komplett in 68000-Assembler, Mode 8 (256x256, 8 Farben).
Braucht einen QL mit mindestens 384K RAM (beim MiSTer RAM auf 640K
stellen). Deutsch und Englisch, im Titelmenue umschaltbar.

Idee: Jungsi - Code: Claude und Jungsi - www.jungsi.de

DATEIEN
  thehum.win      QL-SD/QXL.WIN-Image mit BOOT und Spiel (MiSTer, QPC2,
                  Q-emuLator, QL-SD)
  thehum          Spiel mit XTcc-Trailer (sQLux, Q-emuLator: direkt EXEC)
  hum_bin         rohes Binary ohne Dateiheader (fuer LBYTES/CALL)
  hum_txt         Texte (Englisch)        hum_tde  Texte (Deutsch)
  hum_l1..hum_l8  die Ebenen              hum_w1..8  Waende und Boeden
  hum_s1..hum_s8  Gegnerbilder            hum_scr    Titelbild
  hum_p0..hum_p3  Bilder zu Intro und Enden
  boot            startet das Spiel von win1_
  INSTALL_bas     erzeugt per SEXEC eine startbare Datei und startet sie
  LOADER_bas      Start ueber RESPR/LBYTES/CALL
  Alle Dateien muessen auf demselben Laufwerk liegen. Das Spiel sucht sie
  im Standardverzeichnis, dann auf win1_, flp1_ und mdv1_.

STARTEN
  MiSTer (braucht ein OS-ROM mit QL-SD-Treiber, das Standard-ROM
  kennt kein win1_ und meldet "not found"):
    1. https://www.kilgus.net/soft/MiSTer_QL_OS_qlsd109.zip laden,
       entpacken und alle Dateien nach /media/fat/QL kopieren
    2. thehum.win ebenfalls nach /media/fat/QL kopieren
    3. MiSTer starten, den QL-Core waehlen
    4. F12 - RAM auf 640K stellen
    5. F12 - "Mount HD image": thehum.win waehlen
    6. F12 - "Load OS ROM": js_qlsdxxx oder minerva_xxx_qlsdxxx waehlen
    7. F1 oder F2 druecken - das Spiel startet von win1_
  QPC2 / Q-emuLator: thehum.win als WIN1 einbinden, dann LRUN win1_boot.
  sQLux: die Dateien in ein Verzeichnis legen, es als Laufwerk einbinden
  und EXEC_W thehum (RAMTOP 384 oder mehr).

  Fehlt der Datei nach dem Kopieren vom PC der QDOS-Header, meldet EXEC
  "bad parameter". Dann INSTALL_bas einmal starten (Laufwerk in Zeile 30
  anpassen) oder per CALL starten:
      a=RESPR(20480):LBYTES win1_hum_bin,a:CALL a+20

STEUERUNG
  Hoch / Runter        einen Schritt vor / zurueck
  Links / Rechts       drehen
  SHIFT+Links/Rechts   zur Seite treten
  LEER                 Menue: Beutel, Katzen, Spiel
  I  Beutel   C  Katzen (Werte, Ruestung)   M  Karte
  S  Schleichen an/aus  H  alle Tasten      ESC  Spielmenue
  In Menues: Hoch/Runter waehlen, LEER/ENTER/Rechts nehmen,
  Links/ESC zurueck.
  Joystick: CTL1 wie die Cursortasten mit LEER als Feuer, oder CTL2
  (F1-F5). Am MiSTer meldet der Core das erste Gamepad als F1-F5,
  das zweite als Cursortasten - beide funktionieren.

DAS SPIEL
  Die vier Katzen haben eigene Rollen:
    Kaempfer  viele Lebenspunkte, starker Angriff; Gegner greifen ihn
              in der vorderen Reihe bevorzugt an; geht er in Deckung,
              zieht er alle Angriffe auf sich und schuetzt die anderen
    Heiler    Moos, Kraeuter und der Sternzauber, der die Gruppe schuetzt
    Spaeher   flink, warnt vor Fallen direkt voraus und meldet Gegner
              bis zu zwei Felder voraus
    Jaeger    Ansprung: trifft seltener, aber doppelt so hart (nur vorne);
              spuert ausserhalb von Kaempfen Beute auf (danach ist sie
              eine Weile scheu)
  Die ersten beiden Katzen stehen im Kampf vorne, die anderen hinten.
  Wer in eine Gegnergruppe laeuft (oder von ihr erwischt wird), kaempft.
  Jede Katze waehlt pro Runde: Angriff, Deckung, Faehigkeit, Gegenstand
  oder Flucht. Oben links stehen die Lebenspunkte der Gegner.
  Starke Gegner holen manchmal weit aus (ein "!" hinter ihren
  Lebenspunkten): Ihr naechster Schlag trifft sicher und doppelt so
  hart - Zeit fuer Deckung, den Schutz des Kaempfers oder Heilung.
  Wunden bluten weiter, Schritt fuer Schritt: Kratzer, Riss, tiefe Wunde.
  Moos stillt die Blutung - beim Heiler am besten. Kraeuter heilen Gift.
  Beim Gehen kommt langsam Lebenskraft zurueck; leuchtende Teiche heilen
  alles. Nach einem gewonnenen Kampf hoeren Kratzer auf zu bluten, und
  gefallene Katzen stehen wieder auf.
  Erfahrung bringt neue Raenge (Taste C zeigt, wie viele EP noch fehlen).
  An den Waenden haben die verschollenen Tiefenwaechter Kratzzeichen
  hinterlassen - sie erzaehlen, was unten geschah.
  Die Karte (Taste M) zeigt nur, was die Gruppe gesehen hat, und keine
  Gegner. Solange sie offen ist, wird nicht gelaufen: eine Pfeiltaste
  schliesst sie.
  In der stillen Ebene hilft Schleichen (Taste S): langsamer, aber leise.
  Jedes neue Spiel legt Gegner, Gegenstaende und Fallen an andere Stellen.
  Es gibt drei verschiedene Enden.

SPEICHERN
  ESC - Speichern: drei Plaetze. Bei jedem Ebenenwechsel speichert das
  Spiel zusaetzlich auf den Platz "Auto". Die Zeile im Lademenue zeigt
  die Ebene und wie viel des Spiels geschafft ist. Die Spielstaende
  (hum_sv0..hum_sv3) und die gewaehlte Sprache (hum_cfg) liegen auf dem
  Laufwerk des Spiels.
  ESC - Ton: Klaenge an oder aus.

BAUEN
  In src/: ./make.sh  (braucht vasm und Python 3 mit Pillow; fuer
  thehum.win zusaetzlich qxltool, als 32-Bit-Programm uebersetzt).
  tools/setup_tools.sh baut vasm, den Emulator sQLux und qxltool.
  tools/dist.sh packt das Release (ZIP und WIN-Image) nach dist/.
  Die Ebenen stehen als Text in data/levels/, alle Texte in
  data/text.txt und data/text_de.txt, Grafik wird von tools/gfxc.py,
  tools/deco.py und tools/pics.py erzeugt.

----------------------------------------------------------------------

THE HUM BENEATH - a dungeon adventure for the Sinclair QL
=========================================================

Four young cats follow a deep hum below the moor: a turn-based role
playing game in first person view, step by step through eight levels.
Written entirely in 68000 assembler, Mode 8 (256x256, 8 colours).
Needs a QL with at least 384K RAM (on MiSTer set RAM to 640K).
English and German, switchable in the title menu.

Idea: Jungsi - Code: Claude and Jungsi - www.jungsi.de

FILES
  thehum.win      QL-SD/QXL.WIN image with BOOT and game (MiSTer, QPC2,
                  Q-emuLator, QL-SD)
  thehum          game with XTcc trailer (sQLux, Q-emuLator: EXEC directly)
  hum_bin         raw binary without file header (for LBYTES/CALL)
  hum_txt         texts (English)          hum_tde  texts (German)
  hum_l1..hum_l8  the levels               hum_w1..8  walls and floors
  hum_s1..hum_s8  enemy pictures           hum_scr    title picture
  hum_p0..hum_p3  pictures of the intro and the endings
  boot            starts the game from win1_
  INSTALL_bas     creates an executable file with SEXEC and runs it
  LOADER_bas      starts the game via RESPR/LBYTES/CALL
  All files must be on the same drive. The game looks for them in the
  default directory, then on win1_, flp1_ and mdv1_.

RUNNING
  MiSTer (needs an OS ROM with the QL-SD driver; the standard ROM does
  not know win1_ and reports "not found"):
    1. download https://www.kilgus.net/soft/MiSTer_QL_OS_qlsd109.zip,
       extract it and copy all files to /media/fat/QL
    2. copy thehum.win to /media/fat/QL as well
    3. start the MiSTer, choose the QL core
    4. F12 - set RAM to 640K
    5. F12 - "Mount HD image": choose thehum.win
    6. F12 - "Load OS ROM": choose js_qlsdxxx or minerva_xxx_qlsdxxx
    7. press F1 or F2 - the game starts from win1_
  QPC2 / Q-emuLator: attach thehum.win as WIN1, then LRUN win1_boot.
  sQLux: put the files in a directory, attach it as a drive and
  EXEC_W thehum (RAMTOP 384 or more).

  If the QDOS header got lost while copying from a PC, EXEC reports
  "bad parameter". Run INSTALL_bas once (change the drive in line 30) or
  start via CALL:
      a=RESPR(20480):LBYTES win1_hum_bin,a:CALL a+20

CONTROLS
  Up / Down            one step forward / back
  Left / Right         turn
  SHIFT+Left/Right     step aside
  SPACE                menu: pack, cats, game
  I  pack   C  cats (stats, gear)   M  map
  S  sneak on/off   H  all keys     ESC  game menu
  In menus: up/down choose, SPACE/ENTER/right take it, left/ESC back.
  Joystick: CTL1 like the cursor keys with SPACE as fire, or CTL2
  (F1-F5). On MiSTer the core reports the first gamepad as F1-F5 and
  the second as cursor keys - both work.

THE GAME
  The four cats have their own roles:
    Fighter  many hit points, a strong attack; enemies prefer it in the
             front row; when it keeps guard it draws every attack and
             shields the others
    Healer   moss, herbs and the Starfolk Charm that shields the party
    Scout    quick, warns of traps just ahead and tells of enemies up
             to two cells ahead
    Hunter   Pounce: hits less often but twice as hard (front row only);
             tracks prey outside fights (then the prey is wary for a
             while)
  The first two cats stand in the front row of a fight, the others behind.
  Walk into an enemy group (or let it catch you) and you fight. Every cat
  chooses each round: attack, defend, skill, item or flee. The enemies'
  hit points are shown top left. Strong enemies sometimes wind up a blow
  (a "!" after their hit points): their next blow hits for sure and twice
  as hard - time to keep guard, let the fighter shield the others, or heal.
  Wounds keep bleeding, step by step: scratch, gash, deep wound. Moss
  stops the bleeding - best in the healer's paws. Herbs cure poison.
  Walking slowly brings strength back; glowing pools heal everything.
  After a won fight scratches stop bleeding and fallen cats get back up.
  Experience brings new ranks (key C shows how many XP are still missing).
  The lost Deepwardens left Scratch-Marks on the walls - they tell what
  happened down there.
  The map (key M) shows only what the party has seen, and no enemies.
  While it is open the party does not walk: a cursor key closes it.
  In the silent level sneaking helps (key S): slower, but quiet.
  Every new game puts enemies, items and traps in other places.
  There are three different endings.

SAVING
  ESC - Save: three slots. On every change of level the game also saves
  to the slot "Auto". The line in the load menu shows the level and how
  much of the game is done. The saves (hum_sv0..hum_sv3) and the chosen
  language (hum_cfg) are kept on the drive of the game.
  ESC - Sound: sound on or off.

BUILDING
  In src/: ./make.sh  (needs vasm and Python 3 with Pillow; for
  thehum.win also qxltool, compiled as a 32-bit program).
  tools/setup_tools.sh builds vasm, the sQLux emulator and qxltool.
  tools/dist.sh packs the release (ZIP and WIN image) into dist/.
  The levels are text files in data/levels/, all texts are in
  data/text.txt and data/text_de.txt, the graphics are made by
  tools/gfxc.py, tools/deco.py and tools/pics.py.
