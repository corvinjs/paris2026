## Erstelle deinen eigenen Blog
### Einrichtung
- Clone das Repository in deinen Github-Account und von dort aus auf deinen lokalen Rechner
- Lösche alle Dateien in `_posts/`, `assets/` und `_drafts/`
- Bearbeite den Titel: Öffne `_config.yml` in einem Texteditor und ändere den `title`
- Wähle deine Startseite: Stelle in `_config.yml` via `latest_post_is_home` ein:
  - `true` : die Startseite zeigt den neusten Beitrag
  - `false` : die Startseite zeigt den Inhalt von `pages/home.md` (dort dann deinen Text reinschreiben)
- Ändere die Farben: Öffne `style.css` in einem Texteditor und bearbeite den ersten Abschnitt.
- Falls du nicht auf Deutsch schreibst: Übersetze `index.html` (Texte: "Aktueller Post", "Davor"), `_includes/toc.html` (Text: "Alle Posts") und `_layouts/post.html` (Texte: "Als Nächstes", "Davor") und `style.css` ("Aufklappen" / "Zuklappen").
### Schreiben & Veröffentlichen
Öffne den Ordner als Vault in Obsidian, und erstelle deine Posts als "tägliche Notizen". Sie erscheinen zunächst in `_drafts/`. Um einen Post zu veröffentlichen, verschiebe die Notiz nach `_posts/`. Synchronisiere deine Änderungen zu Github, und die Website wird automatisch generiert.
### Anhänge
Drag-und-droppe Bilder, Videos und Audio in die Notiz. Die Datei wird in `assets/` abgelegt.
### Link-Vorschau für Social Media
Zu Beginn jeder Datei kannst du einstellen:
- `title` : Wird zu Beginn des Posts, als Tab-Name und bei geteilten Links angezeigt
- `description` : Wird bei geteilten Links als Untertitel verwendet
- `image` : Das Vorschaubild für geteilte Links. Kopiere das Bild manuell nach `assets/` und schreibe den Namen (z.B. assets/vorschau-nov-12.jpg) ins Feld. Das einzige Format, das von jeder Plattform unterstützt wird, ist 1200x780 Pixel grosses .jpg.
### Veröffentlichen mit Github Pages
- Stelle in den Repository-Einstellungen unter *Pages* die *Source* auf **GitHub Actions**.
- Trage in `_config.yml` unter `url` die Adresse deiner Seite ein (z.B. `https://deinname.github.io`). `baseurl` setzt der Workflow selbst.
- Wann immer du deine lokalen Änderungen ("commit") auf Github synchronisierst ("push"), wird die Seite neu gebaut. ( siehe `.github/workflows/pages.yml`). Den ersten Lauf im Github-Web-Menu auslösen: *Actions* -> *Pages* -> *Run workflow*.
### Lokal bauen
- Installiere die Programme, die in der zweiten Zeile von `build.sh` stehen (Debian/Ubuntu: `sudo apt install jekyll imagemagick libjxl-tools ffmpegthumbnailer`).
- `bash build.sh` baut die Seite nach `_site/`. Anschauen z.B. mit `python3 -m http.server -d _site` und dann http://localhost:8000 mit dem `baseurl` aus `_config.yml` öffnen, oder `bash build.sh "" _site` für eine Vorschau direkt unter http://localhost:8000.
