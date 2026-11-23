# Public installer compatibility check

Manually dispatched Ubuntu 24.04 ARM test of the already public `cc-host-kit` installer.
Installs browser dependencies and renders only the bundled local start page.
`PRIME_INSTALL_ONLY=1` skips signing-key creation, registration, and collector services.
No account login, production data, credentials, or browser session data is used.
# Verified release

`kit-1800-v1` provides the public installer archive and a SHA256-pinned bootstrap.
The archive reuses the existing public cc-host-kit payload; only install.sh changed.
Use PRIME_INSTALL_ONLY=1 for installation checks without host keys or agent startup.
The Vercel alias has not been updated because its existing authentication expired.

