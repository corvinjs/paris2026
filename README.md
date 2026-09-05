## Erstelle deinen eigenen Blog
- Clone das Repository in deinen Github-Account und von dort aus auf deinen lokalen Rechner
- Lösche alle Dateien in `_posts/` und `assets/`
- Bearbeite den Titel: Öffne `_config.yml` in einem Texteditor und ändere den `title`
- Wähle deine Startseite: Stelle in `_config.yml` via `latest_post_is_home` ein:
  - `true` : die Startseite zeigt den neusten Beitrag
  - `false` : die Startseite zeigt den Inhalt von `pages/home.md` (dort dann deinen Text reinschreiben)
- Ändere die Farben: Öffne `style.css` in einem Texteditor und bearbeite den ersten Abschnitt.

- Falls du nicht auf Deutsch schreibst: Übersetze `latest.html` (Texte: "Aktueller Post", "Davor"), `_includes/toc.html` (Text: "Alle Posts") und `_layouts/post.html` (Texte: "Als Nächstes", "Davor").

Öffne den Ordner als Vault in Obsidian, und erstelle deine Posts als "tägliche Notizen". Synchronisiere deine Änderungen zu Github, und die Website wird automatisch generiert.
