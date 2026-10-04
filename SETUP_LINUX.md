# Uruchomienie SafeShare na czystym Linuksie: krok po kroku

Instrukcja prowadzi od świeżo zainstalowanego systemu do aplikacji działającej w emulatorze OpenHarmony. Wszystkie komendy wpisujesz w terminalu. Sprawdzona na **Ubuntu 24.04 (x86_64)** z wersjami podanymi w [README](README.md#tested-environment). Na innych dystrybucjach zmieniają się tylko nazwy pakietów w kroku 1.

Co zostanie zainstalowane:

| Narzędzie | Do czego | Gdzie trafia |
| --- | --- | --- |
| Pakiety systemowe (JDK, QEMU, git, curl…) | podpisywanie aplikacji, emulator | system (`apt`) |
| Node.js 22 (przez nvm) | uruchamia `oniro-app` i testy | `~/.nvm` |
| `oniro-app` | CLI: SDK, budowanie, podpis, instalacja | globalny pakiet npm |
| OpenHarmony SDK 6.1 (API 23) | kompilator ArkTS, natywny toolchain, `hdc` | `~/setup-ohos-sdk/linux/23` |
| Command-line tools 5.1 | `hvigorw`, `ohpm` | `~/command-line-tools` |
| Emulator OpenHarmony 7.0 (QEMU, telefon x86_64) | urządzenie, na którym działa aplikacja | `~/.ohos-qemu` |
| Model Qwen2.5-0.5B (opcjonalnie) | asystent „period in words” | `models/` w repo |

---

## 0. Wymagania sprzętowe

- Procesor **x86_64** z wirtualizacją (Intel VT-x albo AMD-V) **włączoną w BIOS/UEFI**. Bez KVM emulator też ruszy, ale będzie bardzo wolny.
- **RAM**: minimum 8 GB, zalecane 16 GB (emulator sam zajmuje 4 GB).
- **Dysk**: około **25 GB wolnego miejsca** (SDK ≈ 3,7 GB, command-line tools ≈ 7 GB, emulator ≈ 4,7 GB, plus archiwa pobierane w trakcie instalacji i model 0,4 GB).
- Internet: w sumie pobiera się kilka GB.

Sprawdzenie:

```bash
uname -m                              # ma być: x86_64
grep -cE 'vmx|svm' /proc/cpuinfo      # ma być liczba większa od 0
df -h ~                               # kolumna "Avail" ≥ 25G
```

---

## 1. Pakiety systemowe

```bash
sudo apt update
sudo apt install -y git curl unzip tar coreutils \
    openjdk-21-jdk-headless \
    qemu-system-x86 qemu-system-gui qemu-utils \
    cpu-checker
```

- `openjdk-21-jdk-headless` daje `java` i `keytool`, których `oniro-app sign` używa do podpisu.
- `qemu-system-x86` i `qemu-system-gui` to emulator i jego okno (SDL).
- `cpu-checker` daje polecenie `kvm-ok`.

Opcjonalnie, tylko jeśli chcesz uruchamiać test modelu AI na komputerze (krok 10):

```bash
sudo apt install -y build-essential cmake ninja-build
```

> Fedora: `sudo dnf install git curl unzip java-21-openjdk-devel qemu-kvm qemu-ui-sdl`.

---

## 2. Dostęp do KVM

```bash
kvm-ok                         # oczekiwane: "KVM acceleration can be used"
sudo usermod -aG kvm "$USER"
```

**Wyloguj się i zaloguj ponownie** (albo zrestartuj komputer), żeby nowa grupa zaczęła działać. Potem sprawdź:

```bash
groups | grep -w kvm           # musi wypisać linię z "kvm"
```

Jeśli nie chcesz się teraz wylogowywać, każde polecenie emulatora możesz poprzedzić `sg kvm -c "…"` (pokazane w kroku 6).

---

## 3. Node.js 22

`oniro-app` wymaga Node.js 20 lub nowszego, a testy projektu Node.js 22.18 lub nowszego. Node z repozytorium Ubuntu jest za stary (wersja 18), dlatego instalujemy go przez **nvm**, bez `sudo`:

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
```

Zamknij i otwórz terminal (albo wykonaj `source ~/.bashrc`, a w zsh `source ~/.zshrc`), a potem:

```bash
nvm install 22
nvm alias default 22
node --version                 # v22.x.x, gdzie x ≥ 18
```

---

## 4. `oniro-app` (CLI do OpenHarmony)

```bash
npm install -g @oniroproject/oniro-app
oniro-app --version            # sprawdzone na 0.11.0
```

---

## 5. SDK OpenHarmony i command-line tools

Projekt kompiluje się z API 23 (`compileSdkVersion: 23` w [build-profile.json5](build-profile.json5)), czyli z SDK **6.1**:

```bash
oniro-app sdk install 6.1      # → ~/setup-ohos-sdk/linux/23   (kilka minut)
oniro-app cmdtools install     # → ~/command-line-tools        (kilka minut)
```

Sprawdzenie:

```bash
oniro-app sdk list             # przy "6.1  api 23" musi być gwiazdka *
oniro-app cmdtools status      # "Installed (5.1.0.840)"
```

Dodaj `hdc` (narzędzie do komunikacji z urządzeniem, odpowiednik `adb`) do `PATH`. Dopisz tę linię na końcu `~/.bashrc` (w zsh: `~/.zshrc`) i otwórz nowy terminal:

```bash
export PATH="$HOME/setup-ohos-sdk/linux/23/toolchains:$PATH"
```

```bash
hdc version                    # wypisuje wersję, np. "Ver: 3.x.x"
```

> Jeśli instalacja przerywa się z braku miejsca na archiwa tymczasowe, wskaż inny katalog: `oniro-app cmdtools install --tmp-dir /ścieżka/z/miejscem`.

---

## 6. Emulator OpenHarmony 7.0 (QEMU)

### Instalacja

Obraz telefonu x86_64 z projektu [harmony-contrib/ohos-qemu](https://github.com/harmony-contrib/ohos-qemu), w wersji, na której aplikacja była testowana:

```bash
curl -fsSL https://raw.githubusercontent.com/harmony-contrib/ohos-qemu/main/scripts/install.sh \
  | bash -s -- --release v20260809
```

Skrypt pobiera i rozpakowuje obraz (około 4,7 GB) do `~/.ohos-qemu/openharmony-qemu-x86_64-x86_64_virt-phone/`.

### Uruchomienie

W **osobnym terminalu**, bo emulator działa, dopóki ten terminal jest otwarty:

```bash
~/.ohos-qemu/openharmony-qemu-x86_64-x86_64_virt-phone/launch/linux.sh -r 720x1280
```

Jeśli po kroku 2 sesja nie była jeszcze odświeżona (bez ponownego logowania):

```bash
sg kvm -c "~/.ohos-qemu/openharmony-qemu-x86_64-x86_64_virt-phone/launch/linux.sh -r 720x1280"
```

Otworzy się okno z telefonem, a start trwa około 15–30 s.

### Połączenie `hdc` z emulatorem

W drugim terminalu:

```bash
hdc tconn 127.0.0.1:5555
hdc list targets                               # ma wypisać 127.0.0.1:5555
hdc shell param get bootevent.boot.completed   # "true" = system wystartował
```

Jeśli `list targets` pokazuje `[Empty]`, emulator jeszcze się uruchamia: odczekaj chwilę i powtórz `hdc tconn …`.

Zatrzymanie emulatora: `hdc shell reboot shutdown` albo zamknięcie jego okna.

> **Alternatywa:** `oniro-app emulator install` i `oniro-app emulator start --wait-for-hdc 300` instalują i uruchamiają emulator Oniro (OpenHarmony 6.1, `hdc` na `127.0.0.1:55555`, katalog `~/oniro-emulator`). Na nim był sprawdzany asystent AI. Główne testy aplikacji przeprowadzono jednak na obrazie 7.0 opisanym wyżej.

---

## 7. Pobranie, podpisanie, zbudowanie i uruchomienie projektu

```bash
mkdir -p ~/projects && cd ~/projects
git clone https://github.com/TomAsh97e/borrowPhone1.git
cd borrowPhone1
```

### 7.1 Podpis (jednorazowo na danym komputerze)

Katalog `signatures/` z kluczami **nie jest w repozytorium** (jest w `.gitignore`), więc na nowym komputerze trzeba go wygenerować:

```bash
oniro-app sign . --acls ohos.permission.READ_IMAGEVIDEO
```

- `--acls ohos.permission.READ_IMAGEVIDEO` jest obowiązkowe. Bez tego instalacja kończy się błędem `grant request permissions failed`, bo dostęp do galerii to uprawnienie poziomu `system_basic`.
- Polecenie nadpisuje blok `signingConfigs` w `build-profile.json5` (nowe hasła i ścieżki). **Nie commituj tej zmiany**, bo dotyczy tylko twojego komputera.
- Każde kolejne `oniro-app sign` tworzy **nowe** klucze. Wcześniej zainstalowaną aplikację trzeba wtedy odinstalować (zob. sekcję „Problemy”).

### 7.2 Budowanie

```bash
oniro-app build .
```

Pierwsze budowanie trwa kilka minut, bo kompiluje się też natywna biblioteka z llama.cpp, osobno dla `arm64-v8a` i `x86_64`. Kolejne są szybsze. Wynik to `entry/build/default/outputs/default/entry-default-signed.hap`.

### 7.3 Instalacja i uruchomienie (emulator musi działać, krok 6)

```bash
hdc tconn 127.0.0.1:5555
oniro-app app install .
oniro-app app launch .
```

W emulatorze pojawi się pytanie o dostęp do zdjęć: wybierz **Allow**. Przy pierwszym przekazaniu telefonu aplikacja poprosi o utworzenie 4-cyfrowego PIN-u.

---

## 8. Dane demonstracyjne (zdjęcia, notatki, PDF-y)

W świeżym emulatorze galeria jest pusta. Gotowe pliki są w [demo_data/](demo_data/README.md) i mają daty z okolic **niedzieli 4 października 2026**. Jeśli data w emulatorze jest inna, przyciski „Today” i „Yesterday” mogą ich nie obejmować. Użyj wtedy własnego zakresu dat (custom range).

**Zdjęcia**: trafiają do galerii systemowej, a datą zdjęcia staje się EXIF `DateTimeOriginal`:

```bash
hdc file send demo_data/photos /data/local/tmp/photos
hdc shell mediatool send /data/local/tmp/photos
```

**Notatki i PDF-y** importuje się w aplikacji przez systemowy wybór plików (zakładki Notes / PDF → import). Najpierw skopiuj je do publicznego katalogu „Download” emulatora:

```bash
hdc shell mkdir -p /storage/media/100/local/files/Docs/Download
for f in demo_data/notes/* demo_data/pdfs/*; do
  hdc file send "$f" /storage/media/100/local/files/Docs/Download/
done
```

---

## 9. Model AI dla „period in words” (opcjonalnie)

Bez modelu aplikacja działa normalnie, a pole opisu okresu słowami pokazuje tylko komunikat „The AI assistant is unavailable on this device”. Żeby je włączyć:

```bash
tools/fetch_model.sh           # pobiera ~380 MB do models/ i sprawdza SHA-256
```

Na **emulatorze** model wgrywa się bezpośrednio do piaskownicy aplikacji, bo partycja danych jest za mała na wersję z modelem w środku HAP-a. Aplikacja musi być zainstalowana i **raz uruchomiona** (krok 7.3):

```bash
tools/push_model.sh
```

Następnie zamknij aplikację i uruchom ją ponownie (`oniro-app app launch .`).

> Na **prawdziwym telefonie** użyj `tools/fetch_model.sh --bundle` i zbuduj ponownie (`oniro-app build .`). Model trafi wtedy do HAP-a, który urośnie do około 395 MB.

---

## 10. Testy (opcjonalnie)

Lekkie testy logiki, bez emulatora:

```bash
node tests/session_rules_test.mjs
node tests/text_range_test.mjs
node tests/documents_test.mjs
```

Test asystenta AI na komputerze, tym samym kodem C++ co w aplikacji. Wymaga pakietów z kroku 1 (`build-essential cmake ninja-build`) i pobranego modelu (krok 9):

```bash
cmake -S tests/ai -B /tmp/range-eval -G Ninja && cmake --build /tmp/range-eval
node tests/ai/run_eval.mjs /tmp/range-eval/range_eval models/range-parser.gguf
```

---

## 11. Codzienna praca: ściąga

```bash
# terminal 1: emulator
~/.ohos-qemu/openharmony-qemu-x86_64-x86_64_virt-phone/launch/linux.sh -r 720x1280

# terminal 2: projekt
cd ~/projects/borrowPhone1
hdc tconn 127.0.0.1:5555
oniro-app build .
oniro-app app install .
oniro-app app launch .
```

---

## 12. Problemy i rozwiązania

| Objaw | Przyczyna i rozwiązanie |
| --- | --- |
| `oniro-app: command not found` albo błąd składni w Node | Terminal używa starego Node. Wykonaj `nvm use 22` (albo `nvm alias default 22`) i otwórz nowy terminal. |
| Emulator: `Could not access KVM kernel module: Permission denied` | Brak grupy `kvm` w bieżącej sesji. Wyloguj się i zaloguj (krok 2) albo uruchom przez `sg kvm -c "…"`. |
| Emulator: `KVM not available` / bardzo wolny start | Wirtualizacja wyłączona w BIOS/UEFI. Włącz Intel VT-x / AMD-V (SVM). |
| Okno emulatora się nie otwiera albo się wysypuje, gdy uruchamiasz go z terminala VS Code | Uruchom emulator ze zwykłego terminala systemowego, nie z wbudowanego terminala VS Code (szczególnie w wersji snap). |
| Brak ekranu graficznego (serwer, SSH) | Uruchom z `--display vnc`: `QEMU_EXTRA_ARGS='-vga none' …/launch/linux.sh -r 720x1280 --display vnc`, a potem połącz się klientem VNC z `127.0.0.1:5921`. |
| Emulator działa wolno, przewijanie się tnie | Grafika w emulatorze jest renderowana programowo. Pomaga mniejsza rozdzielczość, np. `-r 540x960`. |
| `hdc list targets` → `[Empty]` | Emulator jeszcze się uruchamia albo połączenie zerwało się po restarcie. Powtórz `hdc tconn 127.0.0.1:5555`. |
| Instalacja: `sign info inconsistent` / niezgodny podpis | Aplikacja była podpisana innymi kluczami. Wykonaj `oniro-app app uninstall org.hackyeah.borrowphone` i zainstaluj ponownie. To usuwa też zapisany PIN. |
| Instalacja: `grant request permissions failed` | Podpis bez `--acls`. Wykonaj `oniro-app sign . --acls ohos.permission.READ_IMAGEVIDEO`, potem odinstaluj, zbuduj i zainstaluj ponownie. |
| Build: brak plików w `signatures/` | Nie wykonano kroku 7.1 na tym komputerze. |
| `oniro-app screenshot` pokazuje tylko ekran główny | Tak ma być: okno aplikacji działa w trybie prywatności (blokada zrzutów ekranu). |
| Okna dialogowe pojawiają się z 1,5–3 s opóźnieniem | To normalne na emulatorze przy pierwszym otwarciu. |
| PDF: „PDF preview is unavailable on this device” | Ograniczenie emulatora x86_64 (ArkWeb tylko dla arm64). Podgląd PDF działa na urządzeniu arm64. |
| „The AI assistant is unavailable on this device” | Brak modelu w piaskownicy aplikacji. Wykonaj krok 9, a po każdym odinstalowaniu aplikacji powtórz `tools/push_model.sh`. |
| „Today” / „Yesterday” nie obejmują zdjęć demo | Data w emulatorze nie zgadza się z datami plików (4.10.2026), a strefa czasowa emulatora to Asia/Shanghai. Użyj własnego zakresu dat. |
| Brak miejsca na dysku | Największy jest katalog `~/command-line-tools/sdk` (≈ 6 GB, HarmonyOS SDK niepotrzebny temu projektowi). Można go zastąpić dowiązaniem do toolchainu API 23: `rm -rf ~/command-line-tools/sdk && mkdir -p ~/command-line-tools/sdk/default/openharmony && ln -s ~/setup-ohos-sdk/linux/23/toolchains ~/command-line-tools/sdk/default/openharmony/toolchains`. |
