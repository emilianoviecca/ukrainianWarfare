# Ukrainian Warfare

Sparatutto in terza persona per Android, in stile battle royale, ambientato il 24 febbraio 2022 all'aeroporto Antonov di Hostomel. Giochi da difensore ucraino, offline, contro bot russi: raccogli le armi, resta nella zona sicura e resta l'ultimo in piedi.

Progetto personale, non destinato a store. La mappa è una ricostruzione semplificata e non in scala dell'aeroporto.

## Installazione sul telefono

Scarica l'APK da **Releases**, aprilo sul telefono e autorizza l'installazione da quella sorgente.

## Struttura

| Percorso | Contenuto |
|---|---|
| `scripts/world.gd` | Mappa, ostacoli e griglia dei percorsi |
| `scripts/player.gd` | Giocatore, armi, camera in terza persona |
| `scripts/bot.gd` | Intelligenza dei nemici |
| `scripts/main.gd` | Regole di partita, zona, oggetti, difficoltà |
| `scripts/hud.gd` | Comandi touch, interfaccia, menu |
| `scripts/autotest.gd` | Collaudo automatico (escluso dall'APK) |
| `tools/make_assets.py` | Genera texture, icona e suoni |

## Compilazione

Serve Godot 4.4.1 con i modelli di esportazione Android e un Android SDK configurato nell'editor.

```bash
GODOT=/percorso/godot KEYSTORE=/percorso/release.keystore KEY_ALIAS=alias KEY_PASS=password tools/build_apk.sh
```

Conserva sempre lo stesso keystore: un APK firmato con una chiave diversa non si installa sopra la versione precedente. Il keystore non va mai inserito nel repository.

## Collaudo

```bash
godot --headless --fixed-fps 60 -- --test=sim1     # partita simulata
xvfb-run godot --resolution 2400x1080 --fixed-fps 30 -- --test=touch   # comandi touch
```
