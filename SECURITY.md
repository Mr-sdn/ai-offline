# Security

AI Offline runs local servers that listen only on `127.0.0.1`. The app server rejects requests from other websites (it checks the `Host` and `Origin` headers and requires a custom header), and the interface uses a strict Content Security Policy. Every download is checked against a pinned SHA-256 checksum.

If you find a security problem, please don't open a public issue. Email **sdndevelop@gmail.com** with the details and, if possible, steps to reproduce it. You'll get a reply within a few days.
