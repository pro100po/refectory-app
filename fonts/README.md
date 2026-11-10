# Шрифты PDF

Полные TTF IBM Plex Sans Regular, IBM Plex Sans SemiBold и IBM Plex Mono Regular с кириллицей. Имена файлов совпадают с PDF_FONTS в index.html; файлы обслуживаются с того же origin, что и приложение.

Источник: https://github.com/IBM/plex/tree/48e8676114c04f29033b4b53da4ec579f8846297

- packages/plex-sans/fonts/complete/ttf/IBMPlexSans-Regular.ttf
- packages/plex-sans/fonts/complete/ttf/IBMPlexSans-SemiBold.ttf
- packages/plex-mono/fonts/complete/ttf/IBMPlexMono-Regular.ttf

Лицензия SIL Open Font License 1.1: LICENSE.txt. Файлы шрифтов не изменены.

## Шрифты интерфейса

Локальные определения находятся в `ui-fonts.css`. Файлы получены из официального репозитория Google Fonts без изменений:

- Alegreya variable, веса 400–900 (интерфейс использует 500 и 700): https://github.com/google/fonts/blob/main/ofl/alegreya/Alegreya%5Bwght%5D.ttf. Лицензия: `Alegreya-OFL.txt`. SHA-256: `ba5564634b93a8f8ba57b48cd4f1ae7417d2b4656fbac779028679b00de3cf12`.
- IBM Plex Sans variable, веса 100–700 (интерфейс использует 400, 500 и 600): https://github.com/google/fonts/blob/main/ofl/ibmplexsans/IBMPlexSans%5Bwdth%2Cwght%5D.ttf. SHA-256: `3b031aa4216174205bd8471f88a49b91f093169e9e87bd5262242bc5967fe2e3`.
- IBM Plex Mono Regular 400: используется существующий PDF-файл из источника IBM, указанного выше. SHA-256: `7c6fbddca4b700be918f5f6183d9bd4464fa427fe435f0b480d77fe2bb8c5a43`.
- IBM Plex Mono Medium 500: https://github.com/google/fonts/blob/main/ofl/ibmplexmono/IBMPlexMono-Medium.ttf. SHA-256: `a9b4c49bb299e05b5f6c481e7fb5e78943d2793249a0c8874ab574a2d1ea6755`.

Для IBM Plex действует SIL Open Font License 1.1 в `LICENSE.txt`.
