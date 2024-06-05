### HatH `galleryinfo.txt` parser for LANraragi

Parse tags from the `galleryinfo.txt` file generated by HatH downloader if it exists in
the archive.

Optionally parse artist, group, title, and parody from the titel.

Optionally use title from filename instead of `galleryinfo.txt` so you can edit the title
without touching the txt file.

When parsing title, accepts simicolon-separated artist, group, or parody. E.g.:

> [Group1 (Artist1; Artist2); Group2 (Artist3)] Title (Parody1; Parody2) [...]

Only spent half an hour to learn perl before writing this... Hope it won't blow anything up.

Inspired by `ComicInfo by Gin-no-kami` and `Filename Parsing by Difegue`.

Thanks to Difegue for the great software and community!
