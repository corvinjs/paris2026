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
- Aktiviere auf Github in den Repository-Einstellungen Github Pages
### Schreiben & Veröffentlichen
Öffne den Ordner als Vault in Obsidian, und erstelle deine Posts als "tägliche Notizen". Sie erscheinen zunächst in `_drafts/`. Um einen Post zu veröffentlichen, verschiebe die Notiz nach `_posts/`. Synchronisiere deine Änderungen zu Github, und die Website wird automatisch generiert.
### Anhänge
Drag-und-droppe Bilder, Videos und Audio in die Notiz. Die Datei wird in `assets/` abgelegt.
### Link-Vorschau für Social Media
Zu Beginn jeder Datei kannst du einstellen:
- `title` : Wird zu Beginn des Posts, als Tab-Name und bei geteilten Links angezeigt
- `description` : Wird bei geteilten Links als Untertitel verwendet
- `image` : Das Vorschaubild für geteilte Links. Kopiere das Bild manuell nach `assets/` und schreibe den Namen (z.B. assets/vorschau-nov-12.jpg) ins Feld. Das einzige Format, das von jeder Plattform unterstützt wird, ist 1200x780 Pixel grosses .jpg.
### Github Actions und verkleinerte Bildvarianten
TODO