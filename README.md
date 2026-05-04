# Saber — Fork personale

**Fork di [Saber Notes](https://github.com/saber-notes/saber) con integrazioni Google Drive e supporto ai pulsanti della Redmi Smart Pen.**

Questo fork mantiene tutto il lavoro originale del progetto Saber e aggiunge funzionalità specifiche per l'uso con il **Redmi Pad 2** e la **Redmi Smart Pen**, oltre alla sincronizzazione con **Google Drive** al posto di Nextcloud.

---

## Modifiche rispetto all'originale

### 🖊️ Pulsanti Redmi Smart Pen
I pulsanti laterali della Redmi Smart Pen vengono intercettati nativamente tramite `dispatchKeyEvent` in `MainActivity.kt`:

| Pulsante | Azione |
|---|---|
| Pulsante 1 (PAGE_DOWN) | Toggle gomma — se già attiva, torna alla penna precedente |
| Pulsante 2 (PAGE_UP) | Toggle selezione — se già attiva, torna alla penna precedente |

### ☁️ Sincronizzazione Google Drive
Sostituisce completamente il sistema di sync Nextcloud con Google Drive:

- Autenticazione OAuth2 tramite browser (flusso installed-app, senza SHA1)
- File salvati in `appDataFolder` — privati, accessibili solo dall'app
- Upload automatico dopo ogni modifica (con debounce di 3 secondi)
- Sync completo all'avvio se già autenticati
- Nessun server intermedio — i dati restano nel tuo Google Drive

---

## Prerequisiti

- Flutter SDK (stable) — vedi [flutter.dev](https://flutter.dev/docs/get-started/install)
- Android SDK 36 con Build Tools 36.0.0
- JDK 17
- Un progetto Google Cloud con **Google Drive API** abilitata
- Credenziali OAuth2 di tipo **Desktop app**

---

## Setup ambiente (macOS)

```bash
# Flutter e Android SDK tramite Homebrew
brew install flutter --cask android-commandlinetools openjdk@17

# Aggiungi al PATH (~/.zshrc)
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
export PATH="/opt/homebrew/opt/openjdk@17/bin:$PATH"

# Installa SDK Android
sdkmanager --install "platform-tools" "platforms;android-36" "build-tools;36.0.0"
flutter doctor --android-licenses
```

---

## Setup Google Cloud

1. Crea un progetto su [console.cloud.google.com](https://console.cloud.google.com)
2. Abilita **Google Drive API**
3. Configura la **OAuth consent screen** (External)
4. Crea credenziali **OAuth 2.0 → Desktop app**
5. Salva Client ID e Client Secret in un file `.env` locale:

```bash
# .env (non committare questo file)
GOOGLE_CLIENT_ID=il_tuo_client_id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=il_tuo_client_secret
```

---

## Build e Run

```bash
# Installa le dipendenze
flutter pub get

# Avvia in debug sul dispositivo connesso
flutter run \
  --dart-define=GOOGLE_CLIENT_ID=$(grep GOOGLE_CLIENT_ID .env | cut -d= -f2) \
  --dart-define=GOOGLE_CLIENT_SECRET=$(grep GOOGLE_CLIENT_SECRET .env | cut -d= -f2)

# Build APK release
flutter build apk --release \
  --dart-define=GOOGLE_CLIENT_ID=$(grep GOOGLE_CLIENT_ID .env | cut -d= -f2) \
  --dart-define=GOOGLE_CLIENT_SECRET=$(grep GOOGLE_CLIENT_SECRET .env | cut -d= -f2)
```

---

## Connessione dispositivo Android (debug USB)

1. **Impostazioni → Info sul dispositivo** → tocca "Versione MIUI" 7 volte
2. **Impostazioni → Impostazioni aggiuntive → Opzioni sviluppatore**:
   - Attiva **Debug USB**
   - Attiva **Installa tramite USB**
3. Collega il dispositivo e autorizza il debug sul popup
4. Verifica la connessione: `adb devices`

---

## Struttura delle modifiche

```
android/app/src/main/kotlin/com/adilhanney/saber/
└── MainActivity.kt              # Intercetta KeyEvent per i pulsanti Smart Pen

lib/
├── data/
│   └── googledrive/
│       ├── drive_client.dart    # Autenticazione OAuth2 Google
│       └── drive_syncer.dart    # Upload/download file su Drive
├── pages/
│   ├── user/
│   │   └── drive_login.dart     # Pagina di login Google Drive
│   └── editor/
│       └── editor.dart          # Modificato: gestione pulsanti Smart Pen
└── data/
    ├── prefs.dart               # Aggiunto: preferenze Drive
    ├── file_manager/
    │   └── file_manager.dart    # Aggiunto: enqueue upload Drive
    └── main.dart                # Aggiunto: sync Drive all'avvio
```

---

## Come funziona il sync

```
App scrive nota
      │
      ▼
FileManager.writeFile()
      │
      ▼
DriveUploadQueue.enqueue()   ← debounce 3 secondi
      │
      ▼
DriveSyncer.uploadFile()
      │
      ▼
Google Drive (appDataFolder)
      │
      ▼
Webapp (notes.tuodominio.com)
```

---

## Webapp compagna

Le note sincronizzate su Drive sono visualizzabili via browser tramite **[Saber Web](https://github.com/Ken5998/saber-web)** — una webapp Next.js che si autentica con lo stesso account Google e renderizza i tratti a mano su canvas.

---

## Roadmap

- [ ] Sync bidirezionale migliorato (conflict resolution)
- [ ] Indicatore di sync nella UI (icona cloud)
- [ ] Supporto multi-account
- [ ] Notifica quando una nota è stata aggiornata da un altro dispositivo

---

## Crediti

Questo progetto è un fork di [Saber Notes](https://github.com/saber-notes/saber) di [@adilhanney](https://github.com/adilhanney).  
Tutto il lavoro originale appartiene ai rispettivi autori.

---

## Licenza

**GPL-3.0** — in conformità con il progetto originale.  
Vedi [LICENSE](LICENSE) per i dettagli.
